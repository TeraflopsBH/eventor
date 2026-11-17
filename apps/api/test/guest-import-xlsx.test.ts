import assert from "node:assert/strict";
import test from "node:test";
import { crc32, deflateRawSync } from "node:zlib";
import { GuestImportWorkbookError, inspectGuestWorkbook, parseGuestWorkbook } from "../src/guest-import-xlsx.js";

function zip(parts: Record<string, string>): Buffer {
  const entries: Buffer[] = [];
  const directory: Buffer[] = [];
  let offset = 0;
  for (const [path, value] of Object.entries(parts)) {
    const name = Buffer.from(path);
    const content = Buffer.from(value);
    const compressed = deflateRawSync(content);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(8, 8);
    local.writeUInt32LE(crc32(content), 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(content.length, 22);
    local.writeUInt16LE(name.length, 26);
    entries.push(local, name, compressed);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50);
    local.copy(central, 6, 4, 30);
    central.writeUInt32LE(offset, 42);
    directory.push(central, name);
    offset += local.length + name.length + compressed.length;
  }
  const centralDirectory = Buffer.concat(directory);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(directory.length / 2, 8);
  end.writeUInt16LE(directory.length / 2, 10);
  end.writeUInt32LE(centralDirectory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...entries, centralDirectory, end]);
}

const spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
const relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const sheetData = `<worksheet xmlns="${spreadsheet}"><sheetData>
  <row r="1"><c r="A1" t="inlineStr"><is><t>Workshop guests</t></is></c></row>
  <row r="3"><c r="A3" t="s"><v>0</v></c><c r="B3" t="s"><v>1</v></c></row>
  <row r="503"><c r="A503" t="inlineStr"><is><r><t>Čen</t></r><r><t>gić</t></r></is></c><c r="B503" t="s"><v>2</v></c></row>
  <row r="504"><c r="A504" t="str"><f>NOW()</f><v>Cached name</v></c><c r="B504" t="s"><v>2</v></c></row>
  <row r="508"><c r="A508" t="s"><v>2</v></c><c r="B508"><v>42</v></c></row>
  </sheetData></worksheet>`;
const fixture = {
  "xl/workbook.xml": `<workbook xmlns="${spreadsheet}" xmlns:r="${relationships}"><sheets>
    <sheet name="Info" sheetId="1" r:id="rId1"/>
    <sheet name="Private" sheetId="2" state="hidden" r:id="rId2"/>
    <sheet name="Guests" sheetId="3" r:id="rId3"/>
    </sheets></workbook>`,
  "xl/_rels/workbook.xml.rels": '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    [1,2,3].map((index) => `<Relationship Id="rId${index}" Type="${relationships}/worksheet" Target="worksheets/sheet${index}.xml"/>`).join("") +
    "</Relationships>",
  "xl/sharedStrings.xml": `<sst xmlns="${spreadsheet}"><si><t>first_name</t></si><si><t>last_name</t></si><si><t>Fixture</t></si></sst>`,
  "xl/worksheets/sheet1.xml": `<worksheet xmlns="${spreadsheet}"/>`,
  "xl/worksheets/sheet2.xml": `<worksheet xmlns="${spreadsheet}"/>`,
  "xl/worksheets/sheet3.xml": sheetData,
};

test("guest XLSX import selects visible sheets and keeps worksheet coordinates", async () => {
  const workbook = zip(fixture);
  assert.deepEqual(await inspectGuestWorkbook(workbook), [
    { index: 1, name: "Info" }, { index: 2, name: "Guests" },
  ]);
  const rows = await parseGuestWorkbook(workbook, 2, 3);
  assert.deepEqual(rows.map(({ rowNumber }) => rowNumber), [503, 504, 508]);
  assert.deepEqual(rows[0]?.names, { firstName: "Čengić", lastName: "Fixture", displayName: null, preferredName: null });
  assert.deepEqual(rows[0]?.errors, []);
  assert.deepEqual(rows[1]?.errors, ["cell_not_text", "name_required"]);
  assert.deepEqual(rows[2]?.errors, ["cell_not_text", "name_required"]);
  assert.ok(!JSON.stringify(rows).includes("Cached name"));
  await assert.rejects(parseGuestWorkbook(workbook, 1, 3), GuestImportWorkbookError);
  await assert.rejects(parseGuestWorkbook(workbook, 2, 1), GuestImportWorkbookError);
});

test("guest XLSX import rejects malformed ZIP, oversized inflation and XML doctypes", async () => {
  await assert.rejects(inspectGuestWorkbook(Buffer.from("not a ZIP")), GuestImportWorkbookError);
  const oversized = zip({ ...fixture, "xl/worksheets/sheet3.xml": "A".repeat(4 * 1024 * 1024 + 1) });
  assert.ok(oversized.length < 256 * 1024);
  await assert.rejects(inspectGuestWorkbook(oversized), GuestImportWorkbookError);
  const withDoctype = zip({
    ...fixture,
    "xl/worksheets/sheet3.xml": '<!DOCTYPE worksheet [<!ENTITY example SYSTEM "file:///synthetic-test">]>' + sheetData,
  });
  await assert.rejects(parseGuestWorkbook(withDoctype, 2, 3), GuestImportWorkbookError);
});
