import assert from "node:assert/strict";
import test from "node:test";
import argon2 from "argon2";
import type { FastifyRequest } from "fastify";
import type { Pool, QueryResultRow } from "pg";
import {
  PostgresStaffSessionAuth,
  SessionAuthError,
  STAFF_CSRF_COOKIE,
  STAFF_SESSION_COOKIE,
} from "../src/session-auth.js";

const userId = "20000000-0000-0000-0000-00000000000b";
const organizationId = "22222222-2222-4222-8222-222222222222";
const membershipId = "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb";
const sessionId = "96000000-0000-4000-8000-000000000001";
const origin = "https://staff.example.test";

function request(headers: Record<string, string> = {}): FastifyRequest {
  return {
    headers: { origin, ...headers },
    ip: "198.51.100.24",
  } as unknown as FastifyRequest;
}

function makePool(passwordHash: string, blocked = false) {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  let tokenHash: string | null = null;
  let csrfHash: string | null = null;

  const pool = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, " ").trim();
      calls.push({ sql: normalized, values });
      if (normalized.startsWith("INSERT INTO eogp.auth_login_attempts")) {
        return { rows: [{ blocked }], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT account.id AS user_id")) {
        return {
          rows: [{
            user_id: userId,
            password_hash: passwordHash,
            user_status: "active",
            membership_id: membershipId,
            membership_status: "active",
            organization_id: organizationId,
            organization_status: "active",
          }],
          rowCount: 1,
        };
      }
      if (normalized.startsWith("INSERT INTO eogp.user_sessions")) {
        tokenHash = String(values[3]);
        csrfHash = String(values[4]);
        return { rows: [{ id: sessionId }], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT session.id AS session_id")) {
        if (!tokenHash || values[0] !== tokenHash) return { rows: [], rowCount: 0 };
        return {
          rows: [{
            session_id: sessionId,
            user_id: userId,
            organization_id: organizationId,
            membership_id: membershipId,
            csrf_token_sha256: csrfHash,
          }],
          rowCount: 1,
        };
      }
      if (normalized.startsWith("SELECT csrf_token_sha256")) {
        return { rows: [{ csrf_token_sha256: csrfHash }], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT locale_preference FROM eogp.users")) {
        return { rows: [{ locale_preference: null }], rowCount: 1 };
      }
      if (normalized.startsWith("UPDATE eogp.users")) {
        return { rows: [], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT membership.id AS membership_id")) {
        return {
          rows: [{
            membership_id: membershipId,
            organization_id: organizationId,
            organization_slug: "event-owner",
            organization_name: "Event Owner",
            default_locale: "bs-BA",
          }],
          rowCount: 1,
        };
      }
      return { rows: [], rowCount: 1 };
    },
  };

  return {
    pool: pool as unknown as Pool,
    calls,
    get tokenHash() { return tokenHash; },
    get csrfHash() { return csrfHash; },
  };
}

test("staff login stores only hashed opaque session/CSRF tokens and authenticates the active membership", async () => {
  const passwordHash = await argon2.hash("correct horse battery staple", { type: argon2.argon2id });
  const mock = makePool(passwordHash);
  const auth = new PostgresStaffSessionAuth(mock.pool, {
    allowedOrigins: [origin],
    fingerprintKey: Buffer.alloc(32, 9),
  });

  const created = await auth.createStaffSession(request(), {
    email: " STAFF@EXAMPLE.TEST ",
    password: "correct horse battery staple",
    organizationSlug: "event-owner",
  });

  assert.equal(created.principal.userId, userId);
  assert.equal(created.principal.organizationId, organizationId);
  assert.equal(created.principal.membershipId, membershipId);
  assert.equal(created.principal.sessionId, sessionId);
  assert.notEqual(mock.tokenHash, created.sessionToken);
  assert.notEqual(mock.csrfHash, created.csrfToken);
  assert.equal(mock.tokenHash?.length, 64);
  assert.equal(mock.csrfHash?.length, 64);

  const reservationIndex = mock.calls.findIndex((call) =>
    call.sql.startsWith("INSERT INTO eogp.auth_login_attempts"));
  const identityIndex = mock.calls.findIndex((call) =>
    call.sql.startsWith("SELECT account.id AS user_id"));
  assert.ok(reservationIndex >= 0 && reservationIndex < identityIndex,
    "login attempt must be reserved before identity lookup and password verification");
  const reservation = mock.calls[reservationIndex];
  assert.ok(reservation, "the login attempt reservation query must be recorded");
  const reservationSql = reservation.sql;
  assert.match(reservationSql, /ON CONFLICT \(email_fingerprint, source_fingerprint\) DO UPDATE SET/);
  assert.match(reservationSql, /failed_attempts \+ 1 > \$4/,
    "the atomic reservation must set the block threshold after the configured number of attempts");

  const cookies = [
    STAFF_SESSION_COOKIE + "=" + created.sessionToken,
    STAFF_CSRF_COOKIE + "=" + created.csrfToken,
  ].join("; ");
  const authenticated = await auth.authenticateStaff(request({ cookie: cookies }));
  assert.deepEqual(authenticated, created.principal);

  const validMutation = await auth.verifyMutationOrigin(
    request({
      cookie: cookies,
      "x-csrf-token": created.csrfToken,
    }),
    created.principal,
  );
  assert.equal(validMutation, true);

  const mismatchedMutation = await auth.verifyMutationOrigin(
    request({
      cookie: cookies,
      "x-csrf-token": "A".repeat(43),
    }),
    created.principal,
  );
  assert.equal(mismatchedMutation, false);

  const principal = await auth.getCurrentPrincipal(created.principal);
  assert.equal(principal.userLocale, null);
  assert.equal(principal.organizationDefaultLocale, "bs-BA");
  assert.deepEqual(principal.memberships, [{
    membershipId,
    organizationId,
    organizationSlug: "event-owner",
    organizationName: "Event Owner",
    selected: true,
  }]);

  await auth.updateUserLocale(created.principal, "en");
  assert.ok(mock.calls.some((call) => call.sql.startsWith("UPDATE eogp.users") && call.values[1] === "en"));
  await auth.updateUserLocale(created.principal, null);
  assert.ok(mock.calls.some((call) => call.sql.startsWith("UPDATE eogp.users") && call.values[1] === null));

  await auth.revokeStaffSession(created.principal);
  assert.ok(mock.calls.some((call) => call.sql.startsWith("UPDATE eogp.user_sessions")));
});

test("failed staff login consumes exactly one atomic rate-limit reservation", async () => {
  const passwordHash = await argon2.hash("correct horse battery staple", { type: argon2.argon2id });
  const mock = makePool(passwordHash);
  const auth = new PostgresStaffSessionAuth(mock.pool, {
    allowedOrigins: [origin],
    fingerprintKey: Buffer.alloc(32, 7),
  });

  await assert.rejects(
    auth.createStaffSession(request(), {
      email: "staff@example.test",
      password: "incorrect horse battery staple",
      organizationSlug: "event-owner",
    }),
    (error: unknown) => error instanceof SessionAuthError && error.status === 401,
  );

  assert.equal(
    mock.calls.filter((call) => call.sql.startsWith("INSERT INTO eogp.auth_login_attempts")).length,
    1,
    "the failed request must be counted by its initial reservation, not a second post-verification write",
  );
  assert.equal(
    mock.calls.some((call) => call.sql.startsWith("UPDATE eogp.auth_login_attempts")),
    false,
    "a failed login must not clear its reserved attempt",
  );
});

test("staff login rejects a non-allow-listed origin", async () => {
  const mock = makePool("not-used");
  const auth = new PostgresStaffSessionAuth(mock.pool, {
    allowedOrigins: [origin],
    fingerprintKey: Buffer.alloc(32, 4),
  });
  assert.equal(auth.verifyLoginOrigin(request({ origin: "https://evil.example" })), false);
  assert.equal(auth.verifyLoginOrigin(request()), true);
});

test("staff login throttles after database-recorded failed attempts", async () => {
  const passwordHash = await argon2.hash("correct horse battery staple", { type: argon2.argon2id });
  const mock = makePool(passwordHash, true);
  const auth = new PostgresStaffSessionAuth(mock.pool, {
    allowedOrigins: [origin],
    fingerprintKey: Buffer.alloc(32, 2),
  });

  await assert.rejects(
    auth.createStaffSession(request(), {
      email: "staff@example.test",
      password: "correct horse battery staple",
      organizationSlug: "event-owner",
    }),
    (error: unknown) => error instanceof SessionAuthError && error.status === 429,
  );
  assert.equal(mock.calls.some((call) => call.sql.startsWith("SELECT account.id AS user_id")), false);
});

test("email-only login selects a single membership without an organization slug",async()=>{
 const mock=makePool(await argon2.hash("correct horse battery staple",{type:argon2.argon2id}));
 const auth=new PostgresStaffSessionAuth(mock.pool,{allowedOrigins:[origin],fingerprintKey:Buffer.alloc(32,9)});
 const result=await auth.createStaffSession(request(),{email:"staff@example.test",password:"correct horse battery staple"});
 assert.ok("principal" in result);assert.equal(result.principal.organizationId,organizationId);
});

test("multiple memberships are disclosed only after password verification and require an explicit valid choice",async()=>{
 const mock=makePool(await argon2.hash("correct horse battery staple",{type:argon2.argon2id}));
 const choices=[{membership_id:membershipId,organization_id:organizationId,organization_slug:"event-owner",organization_name:"Event Owner",default_locale:"en"},
  {membership_id:"bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb",organization_id:"11111111-1111-4111-8111-111111111111",organization_slug:"other-owner",organization_name:"Other Owner",default_locale:"en"}];
 let discoveries=0;
 const pool={query:async(sql:string,values:unknown[]=[])=>{
  if(sql.replace(/\s+/g," ").trim().startsWith("SELECT membership.id AS membership_id")){discoveries++;return{rows:choices,rowCount:2};}
  return mock.pool.query(sql,values);
 }} as unknown as Pool;
 const auth=new PostgresStaffSessionAuth(pool,{allowedOrigins:[origin],fingerprintKey:Buffer.alloc(32,9)});
 await assert.rejects(auth.createStaffSession(request(),{email:"staff@example.test",password:"invalid password fixture"}),error=>error instanceof SessionAuthError&&error.code==="INVALID_CREDENTIALS");
 assert.equal(discoveries,0,"invalid password disclosed memberships");
 const result=await auth.createStaffSession(request(),{email:"staff@example.test",password:"correct horse battery staple"});
 assert.ok("organizationSelectionRequired" in result);assert.deepEqual(result.organizations,choices.map(choice=>({organizationId:choice.organization_id,organizationName:choice.organization_name})));
 assert.equal(mock.calls.filter(call=>call.sql.startsWith("INSERT INTO eogp.user_sessions")).length,0,"selection issued an authenticated cookie prematurely");
 await assert.rejects(auth.createStaffSession(request(),{email:"staff@example.test",password:"correct horse battery staple",organizationId:"33333333-3333-4333-8333-333333333333"}),error=>error instanceof SessionAuthError&&error.code==="INVALID_CREDENTIALS");
 const selected=await auth.createStaffSession(request(),{email:"staff@example.test",password:"correct horse battery staple",organizationId:choices[1]!.organization_id});
 assert.ok("principal" in selected);assert.equal(selected.principal.organizationId,choices[1]!.organization_id);
});
