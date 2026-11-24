import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_BULK_GROUPS_BROWSER_BASE_URL ?? "http://localhost:4173";
const org = "10000000-0000-0000-0000-00000000000a";
for (const engine of [chromium, firefox]) {
  const browser = await engine.launch();
  try {
    const context = await browser.newContext({ locale: "en" });
    const login = await context.request.post(`${baseUrl}/api/auth/session`, {
      headers: { origin: baseUrl }, data: { email: "ci-extended-a@example.invalid", organizationSlug: "ci-tenant-a", password: "CI-only-password-2026" },
    });
    assert.equal(login.status(), 200, await login.text());
    const csrf = (await login.json()).data.csrfToken;
    const write = async (path, data, method = "post", key = randomUUID()) => {
      const response = await context.request[method](`${baseUrl}/api${path}`, {
        headers: { origin: baseUrl, "x-csrf-token": csrf, "idempotency-key": key }, data,
      });
      assert.ok(response.ok(), `${path}: ${response.status()} ${await response.text()}`);
      return (await response.json()).data;
    };
    const get = async path => {
      const response = await context.request.get(`${baseUrl}/api${path}`);
      assert.equal(response.status(), 200, await response.text());
      return (await response.json()).data;
    };
    const tag = randomUUID().slice(0, 8);
    const event = await write(`/organizations/${org}/events`, { eventCode: `BULK-${tag}`, title: `Bulk groups ${tag}`,
      startsAt: "2027-03-01T10:00:00Z", endsAt: "2027-03-01T12:00:00Z", timezoneName: "UTC" });
    const eventId = event.eventId;
    await write(`/events/${eventId}/guest-registry/enable`);
    const root = `/events/${eventId}`;
    const group = await write(`${root}/guest-groups`, { code: "BULK", label: `Bulk group ${tag}` });
    const keep = await write(`${root}/guest-groups`, { code: "KEEP", label: `Keep group ${tag}` });
    const ids = [];
    for (const name of ["First", "Second"]) {
      const person = await write(`/organizations/${org}/persons`, { firstName: name, lastName: `Bulk ${tag}`, displayName: `${name} Bulk ${tag}`, preferredName: null });
      const guest = await write(`${root}/participations`, { personId: person.personId, status: "eligible" });
      ids.push(guest.participationId);
    }
    await write(`${root}/participations/${ids[0]}/groups`, { groupIds: [group.groupId, keep.groupId],
      groupRoles: { [group.groupId]: "assistant", [keep.groupId]: "lead" }, expectedRevision: 1 }, "patch");
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    await page.goto(baseUrl);
    await page.getByRole("button", { name: "Event guests", exact: true }).click();
    await page.locator("#roster-event").selectOption(eventId);
    await page.getByRole("checkbox", { name: "Select all editable guests on this page" }).check();
    await page.getByLabel("Group for selected guests", { exact: true }).selectOption(group.groupId);
    page.once("dialog", dialog => { assert.ok(dialog.message().includes("Existing roles are preserved")); return dialog.accept(); });
    const changed = page.waitForResponse(response => response.request().method() === "PATCH" && response.url().endsWith("/bulk/groups"));
    await page.getByRole("button", { name: "Add group to selected", exact: true }).click();
    const response = await changed;
    assert.equal(response.status(), 200, await response.text());
    assert.deepEqual((await response.json()).data, { processedCount: 2, updatedCount: 1 });
    await page.getByRole("status").filter({ hasText: "Updated 1 of 2 selected guests." }).waitFor();
    const appliedRequest = response.request();
    const replay = await context.request.patch(appliedRequest.url(), { headers: await appliedRequest.allHeaders(), data: appliedRequest.postDataJSON() });
    assert.equal(replay.status(), 200, await replay.text());
    assert.deepEqual(await replay.json(), await response.json());
    let roster = await get(`${root}/participations`);
    assert.equal(roster.people.find(row => row.participationId === ids[0]).groupRoles[group.groupId], "assistant");
    assert.equal(roster.people.find(row => row.participationId === ids[0]).groupRoles[keep.groupId], "lead");
    assert.equal(roster.people.find(row => row.participationId === ids[1]).groupRoles[group.groupId], "member");
    // Retired memberships remain removable through the bulk selector.
    await write(`${root}/guest-groups/${group.groupId}/retire`);
    await page.reload();
    await page.getByRole("button", { name: "Event guests", exact: true }).click();
    await page.locator("#roster-event").selectOption(eventId);
    await page.getByRole("checkbox", { name: "Select all editable guests on this page" }).check();
    await page.getByLabel("Group for selected guests", { exact: true }).selectOption(group.groupId);
    assert.equal(await page.getByRole("button", { name: "Add group to selected", exact: true }).isDisabled(), true);
    page.once("dialog", dialog => dialog.accept());
    const removed = page.waitForResponse(item => item.request().method() === "PATCH" && item.url().endsWith("/bulk/groups"));
    await page.getByRole("button", { name: "Remove group from selected", exact: true }).click();
    const removal = await removed;
    assert.equal(removal.status(), 200, await removal.text());
    await page.getByRole("status").filter({ hasText: "Updated 2 of 2 selected guests." }).waitFor();
    roster = await get(`${root}/participations`);
    assert.ok(roster.people.every(row => !row.groupIds.includes(group.groupId)));
    assert.equal(roster.people.find(row => row.participationId === ids[0]).groupRoles[keep.groupId], "lead");
    await context.close();
    console.log(`PASS ${engine.name()} bulk group add/remove, role preservation, retired removal and idempotent replay`);
  } finally { await browser.close(); }
}
