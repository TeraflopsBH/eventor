import assert from "node:assert/strict";
import test from "node:test";
import { formatGuestCsv } from "../src/guest-export.ts";

test("CSV export preserves columns and protects formula-like values", () => {
  const payload = [
    ["=1+2", "  +1", "-1", "@SUM(A1)", "＝1+2"],
    ['Čengić, Ana "A"', 'safe";=1+2', "\n=1+2", "A\nB", null],
    ["ordinary-name", 7],
  ];
  assert.equal(formatGuestCsv(payload), [
    '"\t=1+2","\t  +1","\t-1","\t@SUM(A1)","\t＝1+2"',
    '"Čengić, Ana ""A""","safe"";=1+2","\t\n=1+2","A\nB",',
    "ordinary-name,7",
    "",
  ].join("\r\n"));
});
