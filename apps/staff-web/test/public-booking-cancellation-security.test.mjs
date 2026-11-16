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
  assert.ok(page.includes("window.location.hash"));
  assert.ok(page.includes('window.history.replaceState(window.history.state, "", window.location.pathname + window.location.search)'));
  assert.ok(page.includes("^[A-Za-z0-9_-]{43}$"));
  assert.ok(!page.includes("localStorage"));
  assert.ok(!page.includes("sessionStorage"));
  assert.ok(!page.includes("document.cookie"));
});

test("customer request and status calls use purpose-bound headers without cookies", () => {
  assert.ok(api.includes("X-External-Booking-Action-Token"));
  assert.ok(api.includes("X-External-Booking-Token"));
  assert.ok(api.includes('credentials: "omit"'));
  assert.ok(page.includes("booking/cancellation-status#token="));
  assert.ok(page.includes("getExternalBookingCancellationRequestStatus"));
  assert.ok(page.includes("submitExternalBookingCancellationRequest"));
});

test("public cancellation routes are mounted and capability headers are redacted", () => {
  assert.ok(app.includes("PublicBookingCancellationPage"));
  assert.ok(app.includes("cancellation-status"));
  assert.ok(apiServer.includes('req.headers["x-external-booking-token"]'));
  assert.ok(apiServer.includes('req.headers["x-external-booking-action-token"]'));
});
