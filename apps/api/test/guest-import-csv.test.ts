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
