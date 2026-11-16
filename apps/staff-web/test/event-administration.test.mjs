import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.vue", import.meta.url), "utf8");
const shell = await readFile(new URL("../src/features/application-shell/StaffApplicationShell.vue", import.meta.url), "utf8");
const view = await readFile(new URL("../src/features/events/EventManagementView.vue", import.meta.url), "utf8");
const api = await readFile(new URL("../src/api.ts", import.meta.url), "utf8");
const english = await readFile(new URL("../src/i18n/messages/en.ts", import.meta.url), "utf8");
const bosnian = await readFile(new URL("../src/i18n/messages/bs-BA.ts", import.meta.url), "utf8");

test("event administration is mounted in the authenticated staff workspace", () => {
  assert.ok(app.includes("useOrganizerEvents"));
  assert.ok(app.includes("EventManagementView"));
  assert.ok(app.includes("activeTab === 'events'"));
  assert.ok(shell.includes("openEvents"));
  assert.ok(shell.includes("navigation.events"));
});

test("event creation interprets local times in the selected IANA time zone", () => {
  assert.ok(view.includes("zonedLocalDateTimeToIso"));
  assert.ok(view.includes("new Intl.DateTimeFormat"));
  assert.ok(view.includes("event.scheduleTimezoneName ?? event.timezoneName"));
  assert.ok(view.includes("events.invalidSchedule"));
});

test("event writes use the idempotent API client and both supported locales", () => {
  assert.ok(api.includes("getOrganizerEvents"));
  assert.ok(api.includes("createOrganizerEvent"));
  assert.ok(api.includes("updateOrganizerEventDetails"));
  assert.ok(api.includes("archiveOrganizerEvent"));
  assert.ok(english.includes('events: {'));
  assert.ok(bosnian.includes('events: {'));
  assert.ok(english.includes('navigation.events:') === false);
  assert.ok(english.includes('events: "Events"') === false);
});
