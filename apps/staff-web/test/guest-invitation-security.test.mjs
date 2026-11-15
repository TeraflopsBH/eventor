import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const management = await readFile(
  new URL("../src/features/guest-invitations/GuestInvitationManagementView.vue", import.meta.url),
  "utf8",
);
const guestPage = await readFile(
  new URL("../src/features/guest-invitations/GuestInvitationPage.vue", import.meta.url),
  "utf8",
);

test("a revoked invitation exposes a fresh Issue action", () => {
  assert.match(management, /\['active', 'draft', 'revoked'\]\.includes\(person\.invitationStatus/);
  assert.match(management, /\["active", "draft"\]\.includes\(person\.invitationStatus/);
  assert.match(management, /t\("guestInvitations\.issue"\)/);
});

test("guest bearer token is removed from the current browser history entry", () => {
  assert.match(guestPage, /window\.history\.replaceState\(window\.history\.state, "",/);
  assert.match(guestPage, /window\.location\.pathname/);
  assert.match(guestPage, /window\.location\.search/);
  assert.match(guestPage, /\^\[A-Za-z0-9_-\]\{43\}\$/);
});
