import assert from "node:assert/strict";
import test from "node:test";
import argon2 from "argon2";
import { Pool } from "pg";
import { buildApi } from "../src/server.js";
import {
  PostgresStaffSessionAuth,
  STAFF_CSRF_COOKIE,
  STAFF_SESSION_COOKIE,
} from "../src/session-auth.js";

const databaseUrl = process.env.AUTH_URL;

test("real PostgreSQL staff sessions survive HTTP cookie round-trips and enforce expiry, CSRF and logout", {
  skip: !databaseUrl ? "AUTH_URL is only configured in the PostgreSQL integration job" : false,
}, async () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2 });
  const origin = "https://staff.example.test";
  const fingerprintKey = Buffer.alloc(32, 0x5a);
  const userId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const auth = new PostgresStaffSessionAuth(pool, {
    allowedOrigins: [origin],
    fingerprintKey,
    sessionTtlSeconds: 3600,
  });
  const password = "CI-only integration password; never used outside this disposable database";
  const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
  let app: ReturnType<typeof buildApi> | undefined;

  try {
    // migration_smoke.sql creates this synthetic identity and its active membership.
    await pool.query(
      "UPDATE eogp.users SET password_hash=$2 WHERE id=$1 AND status='active'",
      [userId, passwordHash],
    );

    app = buildApi({
      pool,
      authenticateStaff: (request) => auth.authenticateStaff(request),
      verifyMutationOrigin: (request, principal) => auth.verifyMutationOrigin(request, principal),
      verifyLoginOrigin: (request) => auth.verifyLoginOrigin(request),
      createStaffSession: (request, body) => auth.createStaffSession(request, body),
      revokeStaffSession: (principal) => auth.revokeStaffSession(principal),
      getCurrentPrincipal: (principal) => auth.getCurrentPrincipal(principal),
      updateUserLocale: (principal, locale) => auth.updateUserLocale(principal, locale),
    });

    const login = () => app!.inject({
      method: "POST",
      url: "/auth/session",
      headers: { origin },
      payload: {
        email: "ci-b@example.invalid",
        password,
        organizationSlug: "ci-venue-b",
      },
    });

    const loginResponse = await login();
    assert.equal(loginResponse.statusCode, 200, loginResponse.body);
    const setCookies = loginResponse.headers["set-cookie"];
    const cookieLines = Array.isArray(setCookies) ? setCookies : [setCookies];
    const sessionLine = cookieLines.find((line) => line?.startsWith(STAFF_SESSION_COOKIE + "="));
    const csrfLine = cookieLines.find((line) => line?.startsWith(STAFF_CSRF_COOKIE + "="));
    assert.ok(sessionLine, "login must set the session cookie");
    assert.ok(csrfLine, "login must set the CSRF cookie");
    assert.match(sessionLine, /HttpOnly/);
    assert.match(sessionLine, /Secure/);
    assert.match(sessionLine, /SameSite=Strict/);
    assert.match(csrfLine, /Secure/);
    assert.match(csrfLine, /SameSite=Strict/);

    const sessionToken = decodeURIComponent(sessionLine.split(";", 1)[0]!.split("=").slice(1).join("="));
    const csrfToken = decodeURIComponent(csrfLine.split(";", 1)[0]!.split("=").slice(1).join("="));
    const cookie = `${STAFF_SESSION_COOKIE}=${sessionToken}; ${STAFF_CSRF_COOKIE}=${csrfToken}`;

    const authenticated = await auth.authenticateStaff({
      headers: { cookie },
      ip: "127.0.0.1",
    } as never);
    assert.ok(authenticated, "the stored SHA-256 session hash must authenticate the raw browser token");
    assert.equal(authenticated.userId, userId);

    const me = await app.inject({ method: "GET", url: "/me", headers: { cookie } });
    assert.equal(me.statusCode, 200, me.body);
    assert.equal(me.json().data.userId, userId);
    assert.equal(me.json().data.organizationId, "22222222-2222-4222-8222-222222222222");
    assert.equal(me.json().data.memberships[0].selected, true);

    const csrfRejected = await app.inject({
      method: "PATCH",
      url: "/me/preferences",
      headers: { origin, cookie },
      payload: { locale: "en" },
    });
    assert.equal(csrfRejected.statusCode, 403, csrfRejected.body);

    const csrfAccepted = await app.inject({
      method: "PATCH",
      url: "/me/preferences",
      headers: { origin, cookie, "x-csrf-token": csrfToken },
      payload: { locale: "en" },
    });
    assert.equal(csrfAccepted.statusCode, 200, csrfAccepted.body);

    const expiredLogin = await login();
    assert.equal(expiredLogin.statusCode, 200, expiredLogin.body);
    const expiredCookies = expiredLogin.headers["set-cookie"];
    const expiredLines = Array.isArray(expiredCookies) ? expiredCookies : [expiredCookies];
    const expiredSessionLine = expiredLines.find((line) => line?.startsWith(STAFF_SESSION_COOKIE + "="));
    assert.ok(expiredSessionLine);
    const expiredToken = decodeURIComponent(expiredSessionLine.split(";", 1)[0]!.split("=").slice(1).join("="));
    const expiredPrincipal = await auth.authenticateStaff({
      headers: { cookie: `${STAFF_SESSION_COOKIE}=${expiredToken}` },
      ip: "127.0.0.1",
    } as never);
    assert.ok(expiredPrincipal?.sessionId);
    await pool.query(
      "UPDATE eogp.user_sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE id=$1",
      [expiredPrincipal.sessionId],
    );
    const expiredResponse = await app.inject({
      method: "GET",
      url: "/me",
      headers: { cookie: `${STAFF_SESSION_COOKIE}=${expiredToken}` },
    });
    assert.equal(expiredResponse.statusCode, 401, expiredResponse.body);

    const logout = await app.inject({
      method: "DELETE",
      url: "/auth/session",
      headers: { origin, cookie, "x-csrf-token": csrfToken },
    });
    assert.equal(logout.statusCode, 204, logout.body);
    const cleared = logout.headers["set-cookie"];
    const clearedLines = Array.isArray(cleared) ? cleared : [cleared];
    assert.ok(clearedLines.some((line) => line?.startsWith(STAFF_SESSION_COOKIE + "=") && /Max-Age=0/.test(line)));
    const reuse = await app.inject({ method: "GET", url: "/me", headers: { cookie } });
    assert.equal(reuse.statusCode, 401, reuse.body);
  } finally {
    if (app) await app.close();
    await pool.query("UPDATE eogp.users SET password_hash=NULL WHERE id=$1", [userId]).catch(() => undefined);
    await pool.end();
  }
});
