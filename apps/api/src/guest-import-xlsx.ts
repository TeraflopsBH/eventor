import { posix } from "node:path";
import { SaxesParser, type SaxesTagNS } from "saxes";
import { fromBufferPromise } from "yauzl";
import { GuestImportCsvError, validateGuestImportRecords, type GuestImportRow } from "./guest-import-csv.js";

export const guestWorkbookMaxBytes = 256 * 1024;
export const guestWorkbookMaxRow = 1_048_576;
const maxParts = 128;
const maxWorksheets = 32;
const maxXmlBytes = 4 * 1024 * 1024;
const worksheetPath = /^xl\/worksheets\/[\w.-]+\.xml$/u;
const workbookParts = new Set(["xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/sharedStrings.xml"]);
const spreadsheetNamespaces = new Set([
  "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
  "http://purl.oclc.org/ooxml/spreadsheetml/main",
]);
const relationshipNamespaces = new Set([
  "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
  "http://purl.oclc.org/ooxml/officeDocument/relationships",
]);

export class GuestImportWorkbookError extends Error {}

function invalidWorkbook(): never {
  throw new GuestImportWorkbookError("Use a valid XLSX workbook within the guest import limits.");
}

async function unpackWorkbook(bytes: Buffer): Promise<Map<string, Buffer>> {
  if (bytes.length === 0 || bytes.length > guestWorkbookMaxBytes) invalidWorkbook();
  try {
    const archive = await fromBufferPromise(bytes, { strictFileNames: true, validateEntrySizes: true });
    if (archive.entryCount > maxParts) invalidWorkbook();
    const parsed = new Map<string, Buffer>();
    const names = new Set<string>();
    let total = 0;
    for await (const entry of archive.eachEntry()) {
      total += entry.uncompressedSize;
      if (total > maxXmlBytes || names.has(entry.fileName)) invalidWorkbook();
      names.add(entry.fileName);
      if (!workbookParts.has(entry.fileName) && !worksheetPath.test(entry.fileName)) continue;
      const reader = await archive.openReadStreamPromise(entry);
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of reader as AsyncIterable<Buffer>) {
        size += chunk.length;
        if (size > entry.uncompressedSize) invalidWorkbook();
        chunks.push(chunk);
      }
      parsed.set(entry.fileName, Buffer.concat(chunks, size));
    }
    return parsed;
  } catch {
    invalidWorkbook();
  }
}

function attribute(tag: SaxesTagNS, name: string): string | undefined {
  return tag.attributes[name]?.value;
}

function readXml(
  input: Buffer | undefined, root: string,
  open: (tag: SaxesTagNS, path: string) => void,
  text?: (content: string, path: string) => void,
  close?: (path: string) => void,
): void {
  if (!input) invalidWorkbook();
  const parser = new SaxesParser({ xmlns: true });
  const path: string[] = [];
  let elements = 0;
  parser.on("doctype", invalidWorkbook);
  parser.on("opentag", (tag) => {
    if (tag.local.length > 128 || path.length >= 48 || ++elements > 100_000) invalidWorkbook();
    if (path.length === 0 && tag.local !== root) invalidWorkbook();
    if (root !== "Relationships" && !spreadsheetNamespaces.has(tag.uri)) {
      path.push("");
      return;
    }
    path.push(tag.local);
    open(tag, path.join("/"));
  });
  parser.on("text", (content) => text?.(content, path.join("/")));
  parser.on("cdata", (content) => text?.(content, path.join("/")));
  parser.on("closetag", () => {
    close?.(path.join("/"));
    path.pop();
  });
  try {
    parser.write(new TextDecoder("utf-8", { fatal: true }).decode(input)).close();
  } catch {
    invalidWorkbook();
  }
}

interface WorkbookSheet {
  index: number;
  name: string;
  file: string;
}

function workbookSheets(parts: Map<string, Buffer>): WorkbookSheet[] {
  const relationships = new Map<string, string>();
  readXml(parts.get("xl/_rels/workbook.xml.rels"), "Relationships", (tag, path) => {
    if (path !== "Relationships/Relationship" || attribute(tag, "TargetMode") === "External") return;
    const type = attribute(tag, "Type");
    if (!type || ![...relationshipNamespaces].some((namespace) => type === `${namespace}/worksheet`)) return;
    const id = attribute(tag, "Id");
    const target = attribute(tag, "Target");
    if (!id || !target || relationships.has(id)) invalidWorkbook();
    const file = target.startsWith("/") ? target.slice(1) : posix.join("xl", target);
    if (!worksheetPath.test(file)) invalidWorkbook();
    relationships.set(id, file);
  });

  const sheets: WorkbookSheet[] = [];
  readXml(parts.get("xl/workbook.xml"), "workbook", (tag, path) => {
    if (path !== "workbook/sheets/sheet") return;
    const id = Object.values(tag.attributes).find((item) => item.local === "id" && relationshipNamespaces.has(item.uri))?.value;
    const file = id && relationships.get(id);
    const name = attribute(tag, "name");
    if (!file) return; // Chart sheets and other non-worksheet workbook entries.
    if (!name || name.length > 128 || !parts.has(file) || sheets.length === maxWorksheets) invalidWorkbook();
    const state = attribute(tag, "state");
    if (state === "hidden" || state === "veryHidden") return;
    sheets.push({ index: sheets.length + 1, name, file });
  });
  if (!sheets.length) invalidWorkbook();
  return sheets;
}

function sharedStrings(part?: Buffer): string[] {
  if (!part) return [];
  const strings: string[] = [];
  let value = "";
  readXml(part, "sst", (_tag, path) => {
    if (path === "sst/si") value = "";
  }, (text, path) => {
    if (path === "sst/si/t" || path === "sst/si/r/t") value += text;
  }, (path) => {
    if (path === "sst/si") strings.push(value);
  });
  return strings;
}

interface Cell {
  text: string;
  invalid: boolean;
}
interface SheetRow {
  rowNumber: number;
  cells: Map<number, Cell>;
}

function worksheetRows(input: Buffer | undefined, strings: string[], headerRow: number): SheetRow[] {
  const rows: SheetRow[] = [];
  let current: SheetRow = { rowNumber: 0, cells: new Map() };
  let column = 0;
  let cellType = "";
  let formula = false;
  let value = "";
  const rowPath = "worksheet/sheetData/row";
  const cellPath = `${rowPath}/c`;

  readXml(input, "worksheet", (tag, path) => {
    if (path === rowPath) {
      const rowNumber = Number(attribute(tag, "r") ?? current.rowNumber + 1);
      if (!Number.isInteger(rowNumber) || rowNumber <= current.rowNumber || rowNumber > guestWorkbookMaxRow) invalidWorkbook();
      current = { rowNumber, cells: new Map() };
      column = 0;
    } else if (path === cellPath && current.rowNumber >= headerRow) {
      const address = attribute(tag, "r");
      if (address === undefined) {
        if (++column > 16_384) invalidWorkbook();
      } else {
        const parsed = /^([A-Z]{1,3})([1-9]\d*)$/u.exec(address);
        if (!parsed || Number(parsed[2]) !== current.rowNumber) invalidWorkbook();
        const nextColumn = [...parsed[1]!].reduce((index, letter) => index * 26 + letter.charCodeAt(0) - 64, 0);
        if (nextColumn <= column || nextColumn > 16_384) invalidWorkbook();
        column = nextColumn;
      }
      formula = false;
      cellType = attribute(tag, "t") ?? "n";
      value = "";
    } else if (path === `${cellPath}/f`) {
      formula = true;
    }
  }, (text, path) => {
    if (current.rowNumber >= headerRow && (path === `${cellPath}/v` ||
        path === `${cellPath}/is/t` || path === `${cellPath}/is/r/t`)) value += text;
  }, (path) => {
    if (path === cellPath && current.rowNumber >= headerRow) {
      if (!formula && !value && cellType !== "s") return;
      const sharedIndex = /^\d+$/u.test(value) ? Number(value) : -1;
      if (!formula && cellType === "s" && strings[sharedIndex] === undefined) invalidWorkbook();
      const inline = cellType === "inlineStr" || cellType === "str";
      const text = cellType === "s" ? strings[sharedIndex] ?? "" : inline ? value : "";
      const invalid = formula || (!inline && cellType !== "s") || Buffer.byteLength(text) > 1024;
      if (invalid || text.trim()) current.cells.set(column, { text: invalid ? "" : text, invalid });
    } else if (path === rowPath && current.rowNumber >= headerRow && current.cells.size) {
      rows.push(current);
      if (rows.length > 501) invalidWorkbook();
    }
  });
  return rows;
}

export async function inspectGuestWorkbook(bytes: Buffer): Promise<{ index: number; name: string }[]> {
  return workbookSheets(await unpackWorkbook(bytes)).map(({ index, name }) => ({ index, name }));
}

export async function parseGuestWorkbook(bytes: Buffer, sheetIndex: number, headerRow: number): Promise<GuestImportRow[]> {
  const parts = await unpackWorkbook(bytes);
  const sheet = workbookSheets(parts).find(({ index }) => index === sheetIndex);
  if (!sheet) invalidWorkbook();
  const rows = worksheetRows(parts.get(sheet.file), sharedStrings(parts.get("xl/sharedStrings.xml")), headerRow);
  const [header, ...records] = rows;
  if (!header || header.rowNumber !== headerRow || header.cells.size > 4 ||
      [...header.cells.values()].some(({ invalid }) => invalid)) invalidWorkbook();
  const columns = Array.from({ length: header.cells.size }, (_, index) => header.cells.get(index + 1)?.text.trim() ?? "");
  try {
    return validateGuestImportRecords(columns, records.map(({ rowNumber, cells }) => {
      const source = columns.map((_name, index) => cells.get(index + 1)?.text ?? "");
      if ([...cells.keys()].some((index) => index > columns.length)) source.push("");
      const errors = [...cells.values()].some(({ invalid }) => invalid) ? ["cell_not_text"] : [];
      return { rowNumber, source, errors };
    }));
  } catch (error) {
    if (error instanceof GuestImportCsvError) throw new GuestImportWorkbookError(error.message);
    throw error;
  }
}
