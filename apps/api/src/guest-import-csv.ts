import { parse } from "csv-parse/sync";

const supportedHeaders = ["first_name", "last_name", "display_name", "preferred_name"] as const;
const maxBytes = 64 * 1024;
const maxRows = 500;

export interface ImportNames {
  firstName: string;
  lastName: string;
  displayName: string | null;
  preferredName: string | null;
}

export interface GuestImportRow {
  rowNumber: number;
  source: string[];
  names: ImportNames;
  errors: string[];
}

export type GuestImportRecord = Pick<GuestImportRow, "rowNumber" | "source" | "errors">;

export class GuestImportCsvError extends Error {}

export function parseGuestImportCsv(csv: string): GuestImportRow[] {
  if (Buffer.byteLength(csv, "utf8") > maxBytes || csv.includes("\0")) {
    throw new GuestImportCsvError("Use a UTF-8 CSV file of up to 64 KiB.");
  }
  let records: string[][];
  try {
    records = parse(csv, {
      bom: true, trim: true, skip_empty_lines: true, relax_column_count: true,
      max_record_size: 4096, to: maxRows + 2,
    }) as string[][];
  } catch {
    throw new GuestImportCsvError("CSV quoting or record size is invalid.");
  }
  const [header, ...body] = records;
  return validateGuestImportRecords(header, body.map((source, index) => ({ rowNumber: index + 2, source, errors: [] })));
}

export function validateGuestImportRecords(header: string[] | undefined, body: GuestImportRecord[]): GuestImportRow[] {
  if (!header || new Set(header).size !== header.length ||
      !["first_name", "last_name"].every((name) => header.includes(name)) ||
      header.some((name) => !supportedHeaders.some((supported) => supported === name))) {
    throw new GuestImportCsvError("Use first_name and last_name headers, with optional display_name and preferred_name.");
  }
  if (body.length < 1 || body.length > maxRows) {
    throw new GuestImportCsvError("Include between 1 and 500 guest rows.");
  }
  const index = new Map(header.map((name, field) => [name, field]));
  const byName = new Map<string, GuestImportRow[]>();
  const rows = body.map(({ source, rowNumber, errors: sourceErrors }): GuestImportRow => {
    const field = (name: typeof supportedHeaders[number]) => source[index.get(name) ?? -1]?.trim() ?? "";
    const names: ImportNames = {
      firstName: field("first_name"), lastName: field("last_name"),
      displayName: field("display_name") || null, preferredName: field("preferred_name") || null,
    };
    const errors = [...sourceErrors];
    if (source.length !== header.length) errors.push("column_count");
    if (!names.firstName || !names.lastName) errors.push("name_required");
    if (Array.from(names.firstName).length > 200 || Array.from(names.lastName).length > 200 ||
        Array.from(names.displayName ?? "").length > 250 || Array.from(names.preferredName ?? "").length > 200 ||
        Object.values(names).some((value) => value !== null && /[\p{Cc}\p{Cs}]/u.test(value))) {
      errors.push("name_invalid");
    }
    const row = { rowNumber, source, names, errors };
    if (errors.length === 0) {
      const key = JSON.stringify([names.firstName.toLowerCase(), names.lastName.toLowerCase()]);
      const matches = byName.get(key) ?? [];
      matches.push(row);
      byName.set(key, matches);
    }
    return row;
  });
  for (const matches of byName.values()) {
    if (matches.length > 1) {
      for (const row of matches) row.errors.push("duplicate_in_file");
    }
  }
  return rows;
}
