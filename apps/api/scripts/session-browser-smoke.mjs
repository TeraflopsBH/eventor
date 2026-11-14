import assert from "node:assert/strict";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_BROWSER_BASE_URL ?? "http://localhost:8080";
const credentials = {
  email: "ci-a@example.invalid",
  password: "CI-only-password-2026",
  organizationSlug: "ci-venue-a",
};

for (const [name, browserType] of [["chromium", chromium], ["firefox", firefox]]) {
  const browser = await browserType.launch({ headless: true });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" });

    const login = await page.evaluate(async (input) => {
      const response = await fetch("/auth/session", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      });
      return { status: response.status, body: await response.json() };
    }, credentials);
    assert.equal(login.status, 200, `${name}: login failed: ${JSON.stringify(login.body)}`);

    const cookies = await context.cookies(baseUrl);
    const sessionCookie = cookies.find((cookie) => cookie.name === "__Host-eventor_session");
    const csrfCookie = cookies.find((cookie) => cookie.name === "__Host-eventor_csrf");
    assert.ok(sessionCookie, `${name}: session cookie was not stored`);
    assert.equal(sessionCookie.secure, true);
    assert.equal(sessionCookie.httpOnly, true);
    assert.ok(csrfCookie, `${name}: CSRF cookie was not stored`);
    assert.equal(csrfCookie.secure, true);
    assert.equal(csrfCookie.httpOnly, false);

    const me = await page.evaluate(async () => {
      const response = await fetch("/me");
      return { status: response.status, body: await response.json() };
    });
    assert.equal(me.status, 200, `${name}: browser did not restore the session: ${JSON.stringify(me.body)}`);
    assert.equal(me.body.data.assert.equal(me.body.data.organizationId, "11111111-1111-4111-8111-111111111111");

    const csrfToken = login.body?.data?.csrfToken;
    assert.equal(typeof csrfToken, "string");
    const mutation = await page.evaluate(async (token) => {
      const response = await fetch("/me/preferences", {
        method: "PATCH",
        headers: { "content-type": "application/json", "x-csrf-token": token },
        body: JSON.stringify({ locale: "en" }),
      });
      return { status: response.status, body: response.status === 200 ? await response.json() : await response.text() };
    }, csrfToken);
    assert.equal(mutation.status, 200, `${name}: CSRF-protected mutation failed: ${JSON.stringify(mutation.body)}`);

    const logout = await page.evaluate(async (token) => {
      const response = await fetch("/auth/session", {
        method: "DELETE",
        headers: { "x-csrf-token": token },
      });
      return response.status;
    }, csrfToken);
    assert.equal(logout, 204, `${name}: logout did not return 204`);

    const afterLogout = await page.evaluate(async () => (await fetch("/me")).status);
    assert.equal(afterLogout, 401, `${name}: revoked browser session remained usable`);

    process.stdout.write(`${name}: login, cookie persistence, /me, CSRF mutation and logout passed\\n`);
    await context.close();
  } finally {
    await browser.close();
  }
}
