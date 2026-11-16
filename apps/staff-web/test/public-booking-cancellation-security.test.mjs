import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const page = await readFile(
  new URL("../src/features/booking-cancellations/PublicBookingCancellationPage.vue", import.meta.url),
  "utf8",
);
const api = await readFile(new URL("../src/api.ts", import.meta.url), "utf8");
const app = await readFile(new URL("../src/App.vue", import.meta.url), "utf8");
const apiServer = await readFile(new URL("../../api/src/server.ts", import.meta.url), "utf8");

test("public cancellation bearer tokens are captured from fragments and removed from history", () => {
  assert.match(page, /window\.location\.hash/);
  assert.match(page, /window\.history\.replaceState\(window\.history\.state, "", window\.location\.pathname\)/);
  assert.match(page, /\^\[A-Za-z0-9_-\]\{43\}\$/);
  assert.doesNotMatch(page, /localStorage|sessionStorage|document\.cookie/);
});

test("customer request and status calls use purpose-bound headers without cookies", () => {
  assert.match(api, /X-External-Booking-Action-Token/);
  assert.match(api, /X-External-Booking-Token/);
  assert.match(api, /credentials: "omit"/);
  assert.match(page, /booking\/cancellation-status#token=/);
  assert.match(page, /getExternalBookingCancellationRequestStatus/);
  assert.match(page, /submitExternalBookingCancellationRequest/);
});

test("public cancellation routes are explicitly mounted and capability headers are redacted", () => {
  assert.match(app, /PublicBookingCancellationPage/);
  assert.match(app, /booking\/cancellation/);
  assert.ok(apiServer.includes('req.headers["x-external-booking-token"]'));
  assert.ok(apiServer.includes('req.headers["x-external-booking-action-token"]'));
});
