import assert from "node:assert/strict";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_GUEST_BROWSER_BASE_URL ?? "http://localhost:4173";
const token = "A".repeat(43);
const invitation = {
  invitationId: "33333333-3333-4333-8333-333333333333",
  invitationRevisionId: "44444444-4444-4444-8444-444444444444",
  eventId: "55555555-5555-4555-8555-555555555555",
  eventTitle: "Community gathering",
  eventStatus: "scheduled",
  startsAt: "2027-03-01T17:00:00.000Z",
  endsAt: "2027-03-01T21:00:00.000Z",
  timezone: "Europe/Sarajevo",
  locale: "en",
  allowedResponses: ["accepted", "declined", "tentative"],
  responseDeadline: null,
  responseChangeAllowed: true,
  currentResponse: null,
  presentationSnapshot: {
    greeting: "We look forward to seeing you.",
    venueName: "Main hall",
  },
};

for (const [name, browserType] of [["chromium", chromium], ["firefox", firefox]]) {
  const browser = await browserType.launch({ headless: true });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    let reads = 0;
    const writes = [];

    await page.route("**/guest/invitation/me", async (route) => {
      if (route.request().method() !== "GET") {
        await route.fallback();
        return;
      }
      reads += 1;
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        headers: {
          "cache-control": "no-store, private",
          "referrer-policy": "no-referrer",
        },
        body: JSON.stringify({ data: invitation }),
      });
    });

    await page.route("**/guest/invitation/me/rsvp", async (route) => {
      if (route.request().method() !== "POST") {
        await route.fallback();
        return;
      }
      writes.push({
        body: route.request().postDataJSON(),
        token: route.request().headers()["x-guest-invitation-token"],
        idempotencyKey: route.request().headers()["idempotency-key"],
      });
      invitation.currentResponse = writes.at(-1).body.response;
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({
          data: {
            invitationId: invitation.invitationId,
            responseId: "66666666-6666-4666-8666-666666666666",
            response: invitation.currentResponse,
            receivedAt: "2026-11-15T18:00:00.000Z",
            replayed: false,
          },
        }),
      });
    });

    await page.goto(`${baseUrl}/guest/invitation#token=${token}`, { waitUntil: "networkidle" });
    await page.getByRole("heading", { name: "Community gathering" }).waitFor();
    assert.equal(new URL(page.url()).hash, "", `${name}: bearer token remained in browser history`);
    assert.ok(reads >= 1, `${name}: invitation was not loaded`);
    assert.equal(writes.length, 0, `${name}: opening the invitation submitted an RSVP`);
    assert.equal(
      await page.evaluate(() => document.documentElement.lang),
      "en",
      `${name}: invitation locale was not applied`,
    );

    await page.getByLabel("Your response").selectOption("declined");
    assert.equal(writes.length, 0, `${name}: selecting an answer submitted it without confirmation`);
    await page.getByRole("button", { name: "Submit response" }).click();
    await page.getByText("Your response has been recorded.").waitFor();

    assert.equal(writes.length, 1, `${name}: expected exactly one explicit RSVP submission`);
    assert.deepEqual(writes[0].body, { response: "declined" });
    assert.equal(writes[0].token, token);
    assert.match(writes[0].idempotencyKey, /^[0-9a-f-]{36}$/i);
    assert.ok(reads >= 2, `${name}: page did not refresh the personal invitation projection`);
    assert.equal(new URL(page.url()).hash, "", `${name}: bearer token reappeared after submission`);

    console.log(`${name}: guest invitation load, token scrubbing, explicit RSVP and confirmation passed`);
    await context.close();
  } finally {
    await browser.close();
  }
}
