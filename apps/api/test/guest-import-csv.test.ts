import assert from "node:assert/strict";
import test from "node:test";
import { GuestImportCsvError, parseGuestImportCsv } from "../src/guest-import-csv.js";

test("guest CSV supports UTF-8 BOM, quoted fields, header mapping, and row-level issues", () => {
  const rows = parseGuestImportCsv(
    '\uFEFFlast_name,first_name,display_name\r\n"García, Jr.",Sam,"Example, Sam"\r\nDoe,Ana,\r\nDoe,ana,\r\nOnlyLast,\r\n',
  );
  assert.equal(rows[0]?.names.firstName, "Sam");
  assert.equal(rows[0]?.names.lastName, "García, Jr.");
  assert.equal(rows[0]?.names.displayName, "Example, Sam");
  assert.deepEqual(rows[1]?.errors, ["duplicate_in_file"]);
  assert.deepEqual(rows[2]?.errors, ["duplicate_in_file"]);
  assert.deepEqual(rows[3]?.errors, ["column_count", "name_required"]);
  assert.equal(rows[3]?.rowNumber, 5);
});

test("guest CSV rejects unknown or duplicate headers, broken quoting, and oversized input", () => {
  for (const invalid of [
    "first_name,last_name,email\na,b,c",
    "first_name,last_name,last_name\na,b,c",
    'first_name,last_name\n"unclosed,b',
    `first_name,last_name\n${"a,b\n".repeat(501)}`,
    `first_name,last_name\n${"x".repeat(64 * 1024)}`,
  ]) assert.throws(() => parseGuestImportCsv(invalid), GuestImportCsvError);
});

test("guest CSV mapping selects only the requested source columns", () => {
  const csv = "Surname,Private notes,Given,Nickname\nExample,Ignore this,Ada,Addie\nMissing,Here\n";
  const mapping = { firstName: 3, lastName: 1, preferredName: 4 };
  const rows = parseGuestImportCsv(csv, mapping);
  assert.deepEqual(rows[0]?.names, { firstName: "Ada", lastName: "Example", displayName: null, preferredName: "Addie" });
  assert.deepEqual(rows[0]?.source, ["Ada", "Example", "Addie"]);
  assert.deepEqual(rows[1]?.errors, ["column_count", "name_required"]);
  assert.throws(() => parseGuestImportCsv(csv, { firstName: 1, lastName: 1 }), /distinct available columns/);
});

test("guest CSV reference mapping validates and compares exact keys independently of names", () => {
  const csv = "Given,Surname,Reference\nAna,Doe,Case-001\nAna,Doe,case-001\nNew,Name,Repeated\nOther,Name,Repeated\nBad,Name,contains space\n";
  const mapping = { firstName: 1, lastName: 2 };
  const rows = parseGuestImportCsv(csv, mapping, 3);
  assert.deepEqual(rows.map(({ errors }) => errors), [[], [], ["duplicate_in_file"], ["duplicate_in_file"], ["reference_invalid"]]);
  assert.deepEqual(rows.slice(0, 2).map(({ sourceReference }) => sourceReference), ["Case-001", "case-001"]);
  assert.throws(() => parseGuestImportCsv(csv, mapping, 1), /separate available column/);
  assert.throws(() => parseGuestImportCsv("first_name,last_name,source_reference\nAda,Example,Id"), GuestImportCsvError);
});
