import argon2 from "argon2";
import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
import type { FastifyRequest } from "fastify";
import type { Pool, QueryResultRow } from "pg";

export const STAFF_SESSION_COOKIE = "__Host-eventor_session";
export const STAFF_CSRF_COOKIE = "__Host-eventor_csrf";

export interface StaffPrincipal {
  readonly userId: string;
  readonly organizationId: string;
  readonly membershipId: string;
  readonly sessionId?: string;
}

export interface SessionAuthConfig {
  readonly allowedOrigins: readonly string[];
  /** Dedicated 32-byte HMAC key for login-throttle fingerprints. */
  readonly fingerprintKey: Buffer;
  readonly sessionTtlSeconds?: number;
  readonly maxFailedLogins?: number;
  readonly loginWindowSeconds?: number;
  readonly loginBlockSeconds?: number;
}

export interface CreatedStaffSession {
  readonly principal: StaffPrincipal;
  readonly sessionToken: string;
  readonly csrfToken: string;
  readonly expiresAt: Date;
}

export interface StaffOrganizationChoice { organizationId: string; organizationName: string }
export interface StaffOrganizationSelection { organizationSelectionRequired: true; organizations: StaffOrganizationChoice[] }
export interface StaffLoginInput { email: string; password: string; organizationSlug?: string; organizationId?: string }
export class SessionAuthError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "SessionAuthError";
  }
}

interface AuthIdentityRow extends QueryResultRow {
  user_id: string;
  password_hash: string | null;
  user_status: string;
  is_platform_admin?: boolean;
  membership_id: string;
  membership_status: string;
  organization_id: string;
  organization_status: string;
}

interface SessionLookupRow extends QueryResultRow {
  session_id: string;
  user_id: string;
  organization_id: string;
  membership_id: string;
  csrf_token_sha256: string;
}

interface MembershipRow extends QueryResultRow {
  membership_id: string;
  organization_id: string;
  organization_slug: string;
  organization_name: string;
  default_locale: string;
}

interface UserLocaleRow extends QueryResultRow {
  locale_preference: string | null;
  is_platform_admin?: boolean;
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function fingerprint(key: Buffer, kind: string, value: string): string {
  return createHmac("sha256", key).update(kind).update("\0").update(value).digest("hex");
}

function parseCookies(header: string | undefined): Map<string, string> {
  const result = new Map<string, string>();
  if (!header) return result;
  for (const part of header.split(";")) {
    const separator = part.indexOf("=");
    if (separator <= 0) continue;
    const name = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (!name || result.has(name)) continue;
    try {
      result.set(name, decodeURIComponent(value));
    } catch {
      // Malformed cookie values are ignored and therefore fail authentication.
    }
  }
  return result;
}

function constantTimeStringEqual(left: string, right: string): boolean {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

function isToken(value: string | undefined): value is string {
  return Boolean(value && /^[A-Za-z0-9_-]{43}$/.test(value));
}

function sessionCookie(token: string, maxAge: number): string {
  return `${STAFF_SESSION_COOKIE}=${encodeURIComponent(token)}; Path=/; Max-Age=${maxAge}; Secure; HttpOnly; SameSite=Strict`;
}

function csrfCookie(token: string, maxAge: number): string {
  return `${STAFF_CSRF_COOKIE}=${encodeURIComponent(token)}; Path=/; Max-Age=${maxAge}; Secure; SameSite=Strict`;
}

export function clearStaffSessionCookies(): string[] {
  const expired = "Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; SameSite=Strict";
  return [
    `${STAFF_SESSION_COOKIE}=; ${expired}; HttpOnly`,
    `${STAFF_CSRF_COOKIE}=; ${expired}`,
  ];
}

export class PostgresStaffSessionAuth {
  private readonly allowedOrigins: Set<string>;
  private readonly ttlSeconds: number;
  private readonly maxFailedLogins: number;
  private readonly loginWindowSeconds: number;
  private readonly loginBlockSeconds: number;
  private readonly dummyHashPromise: Promise<string>;

  constructor(
    private readonly authPool: Pool,
    private readonly config: SessionAuthConfig,
  ) {
    if (config.fingerprintKey.length !== 32) {
      throw new Error("Session authentication fingerprint key must be exactly 32 bytes.");
    }
    const origins = config.allowedOrigins.map((origin) => origin.trim()).filter(Boolean);
    if (origins.length === 0 || origins.some((origin) => {
      try {
        const parsed = new URL(origin);
        return !["https:", "http:"].includes(parsed.protocol)
          || parsed.origin !== origin
          || parsed.username !== ""
          || parsed.password !== "";
      } catch {
        return true;
      }
    })) {
      throw new Error("Configure one or more exact HTTP(S) origins for staff authentication.");
    }
    this.allowedOrigins = new Set(origins);
    this.ttlSeconds = config.sessionTtlSeconds ?? 8 * 60 * 60;
    this.maxFailedLogins = config.maxFailedLogins ?? 5;
    this.loginWindowSeconds = config.loginWindowSeconds ?? 15 * 60;
    this.loginBlockSeconds = config.loginBlockSeconds ?? 15 * 60;
    if (this.ttlSeconds < 300 || this.ttlSeconds > 24 * 60 * 60) {
      throw new Error("Staff session lifetime must be between five minutes and 24 hours.");
    }
    if (this.maxFailedLogins < 3 || this.maxFailedLogins > 20) {
      throw new Error("Login failure threshold must be between 3 and 20.");
    }

    // Used to spend comparable Argon2 work for unknown/disabled identities.
    this.dummyHashPromise = argon2.hash(randomBytes(32).toString("base64url"), {
      type: argon2.argon2id,
    });
  }

  verifyLoginOrigin(request: FastifyRequest): boolean {
    const origin = request.headers.origin;
    return typeof origin === "string" && this.allowedOrigins.has(origin);
  }

  async authenticateStaff(request: FastifyRequest): Promise<StaffPrincipal | null> {
    const token = parseCookies(request.headers.cookie).get(STAFF_SESSION_COOKIE);
    if (!isToken(token)) return null;

    const tokenHash = sha256(token);
    const lookup = await this.authPool.query<SessionLookupRow>(
      `SELECT
         session.id AS session_id,
         session.user_id,
         session.organization_id,
         session.membership_id,
         session.csrf_token_sha256
       FROM eogp.user_sessions AS session
       JOIN eogp.users AS account
         ON account.id = session.user_id
       JOIN eogp.organization_memberships AS membership
         ON membership.organization_id = session.organization_id
        AND membership.id = session.membership_id
        AND membership.user_id = session.user_id
       JOIN eogp.organizations AS organization
         ON organization.id = session.organization_id
       WHERE session.session_token_sha256 = $1
         AND session.revoked_at IS NULL
         AND session.expires_at > clock_timestamp()
         AND account.status = 'active'
         AND membership.status = 'active'
         AND organization.status = 'active'
       LIMIT 1`,
      [tokenHash],
    );
    const row = lookup.rows[0];
    if (!row) return null;

    // Throttle last_seen writes while still retaining useful session activity.
    await this.authPool.query(
      `UPDATE eogp.user_sessions
          SET last_seen_at = clock_timestamp()
        WHERE id = $1
          AND last_seen_at < clock_timestamp() - interval '5 minutes'`,
      [row.session_id],
    );

    return {
      userId: row.user_id,
      organizationId: row.organization_id,
      membershipId: row.membership_id,
      sessionId: row.session_id,
    };
  }

  async verifyMutationOrigin(
    request: FastifyRequest,
    principal: StaffPrincipal,
  ): Promise<boolean> {
    if (!this.verifyLoginOrigin(request) || !principal.sessionId) return false;

    const cookies = parseCookies(request.headers.cookie);
    const csrfCookieValue = cookies.get(STAFF_CSRF_COOKIE);
    const csrfHeader = request.headers["x-csrf-token"];
    if (!isToken(csrfCookieValue) || typeof csrfHeader !== "string"
        || !isToken(csrfHeader)
        || !constantTimeStringEqual(csrfCookieValue, csrfHeader)) {
      return false;
    }

    const expected = await this.authPool.query<QueryResultRow & { csrf_token_sha256: string }>(
      `SELECT csrf_token_sha256
         FROM eogp.user_sessions
        WHERE id = $1
          AND user_id = $2
          AND organization_id = $3
          AND membership_id = $4
          AND revoked_at IS NULL
          AND expires_at > clock_timestamp()`,
      [principal.sessionId, principal.userId, principal.organizationId, principal.membershipId],
    );
    const hash = expected.rows[0]?.csrf_token_sha256;
    return typeof hash === "string" && constantTimeStringEqual(sha256(csrfCookieValue), hash);
  }

  async createStaffSession(request: FastifyRequest, input: StaffLoginInput & {organizationSlug:string}): Promise<CreatedStaffSession>;
  async createStaffSession(request: FastifyRequest, input: StaffLoginInput): Promise<CreatedStaffSession | StaffOrganizationSelection>;
  async createStaffSession(request: FastifyRequest, input: StaffLoginInput): Promise<CreatedStaffSession | StaffOrganizationSelection> {
    const email = input.email.trim().toLowerCase();
    const organizationSlug = input.organizationSlug?.trim().toLowerCase();
    if (email.length > 320 || (organizationSlug !== undefined && (organizationSlug.length < 2 || organizationSlug.length > 80)) || (organizationSlug !== undefined && input.organizationId !== undefined)
        || Buffer.byteLength(input.password, "utf8") > 1024) {
      throw new SessionAuthError(400, "INVALID_LOGIN", "Enter a valid email and password.");
    }

    const emailFingerprint = fingerprint(this.config.fingerprintKey, "email", email);
    const sourceFingerprint = fingerprint(
      this.config.fingerprintKey,
      "source",
      request.ip || "unknown",
    );

    // Reserve this attempt atomically before expensive password verification.
    // The unique-key UPSERT serializes concurrent requests for the same
    // email/source pair, so a burst cannot all pass a stale pre-check.
    const reservation = await this.authPool.query<QueryResultRow & { blocked: boolean }>(
      `INSERT INTO eogp.auth_login_attempts (
         email_fingerprint, source_fingerprint,
         window_started_at, failed_attempts, updated_at
       ) VALUES ($1,$2,clock_timestamp(),1,clock_timestamp())
       ON CONFLICT (email_fingerprint, source_fingerprint)
       DO UPDATE SET
         failed_attempts = CASE
           WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
             THEN eogp.auth_login_attempts.failed_attempts
           WHEN eogp.auth_login_attempts.window_started_at
                < clock_timestamp() - make_interval(secs => $3)
             THEN 1
           ELSE eogp.auth_login_attempts.failed_attempts + 1
         END,
         window_started_at = CASE
           WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
             THEN eogp.auth_login_attempts.window_started_at
           WHEN eogp.auth_login_attempts.window_started_at
                < clock_timestamp() - make_interval(secs => $3)
             THEN clock_timestamp()
           ELSE eogp.auth_login_attempts.window_started_at
         END,
         blocked_until = CASE
           WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
             THEN eogp.auth_login_attempts.blocked_until
           WHEN eogp.auth_login_attempts.window_started_at
                < clock_timestamp() - make_interval(secs => $3)
             THEN NULL
           WHEN eogp.auth_login_attempts.failed_attempts + 1 > $4
             THEN clock_timestamp() + make_interval(secs => $5)
           ELSE NULL
         END,
         updated_at = clock_timestamp()
       RETURNING coalesce(blocked_until > clock_timestamp(), false) AS blocked`,
      [
        emailFingerprint,
        sourceFingerprint,
        this.loginWindowSeconds,
        this.maxFailedLogins,
        this.loginBlockSeconds,
      ],
    );
    if (reservation.rows[0]?.blocked !== false) {
      throw new SessionAuthError(429, "LOGIN_THROTTLED", "Too many failed sign-in attempts. Try again later.");
    }

    const identity = await this.authPool.query<AuthIdentityRow>(
      `SELECT account.id AS user_id, account.password_hash, account.status AS user_status, account.is_platform_admin
         FROM eogp.users AS account WHERE lower(account.email)=$1 LIMIT 1`, [email],
    );
    const row = identity.rows[0];
    const candidateHash = row?.password_hash?.startsWith("$argon2id$")
      ? row.password_hash
      : await this.dummyHashPromise;

    let passwordMatches = false;
    try {
      passwordMatches = await argon2.verify(candidateHash, input.password);
    } catch {
      passwordMatches = false;
    }

    const validIdentity = Boolean(
      row
      && row.user_status === "active"
      && row.password_hash?.startsWith("$argon2id$")
      && passwordMatches,
    );

    if (!validIdentity || !row) {
      throw new SessionAuthError(401, "INVALID_CREDENTIALS", "The supplied sign-in details are not valid.");
    }

    if (row.is_platform_admin) await this.authPool.query("SELECT eogp.refresh_platform_admin_access($1::uuid)",[row.user_id]);
    const organizations = await this.availableOrganizations(row.user_id);
    const selected = input.organizationId ? organizations.find(item=>item.organization_id===input.organizationId)
      : organizationSlug ? organizations.find(item=>item.organization_slug===organizationSlug)
      : organizations.length===1 ? organizations[0] : undefined;
    if (!organizations.length || ((input.organizationId || organizationSlug) && !selected)) {
      throw new SessionAuthError(401,"INVALID_CREDENTIALS","The supplied sign-in details are not valid.");
    }
    await this.authPool.query(
      `UPDATE eogp.auth_login_attempts
          SET failed_attempts = 0,
              blocked_until = NULL,
              window_started_at = clock_timestamp(),
              updated_at = clock_timestamp()
        WHERE email_fingerprint = $1 AND source_fingerprint = $2`,
      [emailFingerprint, sourceFingerprint],
    );

    if (row.password_hash && argon2.needsRehash(row.password_hash)) {
      const upgraded = await argon2.hash(input.password, { type: argon2.argon2id });
      await this.authPool.query(
        `UPDATE eogp.users
            SET password_hash = $2,
                updated_at = clock_timestamp()
          WHERE id = $1 AND status = 'active'`,
        [row.user_id, upgraded],
      );
    }

    if (!selected) return { organizationSelectionRequired: true,
      organizations: organizations.map(item=>({organizationId:item.organization_id,organizationName:item.organization_name})) };
    return this.issueStaffSession(request,{...row,organization_id:selected.organization_id,membership_id:selected.membership_id});
  }

  private async availableOrganizations(userId:string): Promise<MembershipRow[]> {
    const result=await this.authPool.query<MembershipRow>(
      `SELECT membership.id AS membership_id, organization.id AS organization_id,
         organization.slug AS organization_slug,organization.name AS organization_name,organization.default_locale
       FROM eogp.organization_memberships membership JOIN eogp.organizations organization ON organization.id=membership.organization_id
       JOIN eogp.users account ON account.id=membership.user_id
       WHERE membership.user_id=$1 AND membership.status='active' AND organization.status='active' AND account.status='active'
       ORDER BY organization.name,organization.id`,[userId]);
    return result.rows;
  }

  private async issueStaffSession(request:FastifyRequest,row:Pick<AuthIdentityRow,"user_id"|"organization_id"|"membership_id">,database:Pick<Pool,"query">=this.authPool,recordAuthentication=true,existingExpiry?:Date):Promise<CreatedStaffSession> {
    const sessionToken = randomBytes(32).toString("base64url");
    const csrfToken = randomBytes(32).toString("base64url");
    const expiresAt = existingExpiry ?? new Date(Date.now() + this.ttlSeconds * 1000);
    const sourceHash = fingerprint(this.config.fingerprintKey,"source",request.ip || "unknown");
    const userAgent = request.headers["user-agent"];
    const userAgentFingerprint = typeof userAgent === "string"
      ? fingerprint(this.config.fingerprintKey, "user-agent", userAgent.slice(0, 500))
      : null;

    const created = await database.query<QueryResultRow & { id: string }>(
      `INSERT INTO eogp.user_sessions (
         user_id, organization_id, membership_id,
         session_token_sha256, csrf_token_sha256, expires_at,
         source_fingerprint, user_agent_fingerprint
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING id`,
      [
        row.user_id,
        row.organization_id,
        row.membership_id,
        sha256(sessionToken),
        sha256(csrfToken),
        expiresAt,
        sourceHash,
        userAgentFingerprint,
      ],
    );
    const sessionId = created.rows[0]?.id;
    if (!sessionId) {
      throw new SessionAuthError(503, "SESSION_CREATE_FAILED", "The sign-in service is temporarily unavailable.");
    }

    if (recordAuthentication) await database.query(
      `UPDATE eogp.users
          SET last_authenticated_at = clock_timestamp(),
              updated_at = clock_timestamp()
        WHERE id = $1`,
      [row.user_id],
    );

    return {
      principal: {
        userId: row.user_id,
        organizationId: row.organization_id,
        membershipId: row.membership_id,
        sessionId,
      },
      sessionToken,
      csrfToken,
      expiresAt,
    };
  }

  async switchStaffOrganization(request:FastifyRequest,principal:StaffPrincipal,organizationId:string):Promise<CreatedStaffSession> {
    if (!principal.sessionId) throw new SessionAuthError(401,"UNAUTHENTICATED","Sign in again.");
    const client=await this.authPool.connect();
    try {
      await client.query("BEGIN");
      const target=await client.query<AuthIdentityRow>("SELECT user_id,membership_id,organization_id FROM eogp.lock_staff_workspace_membership($1::uuid,$2::uuid)",[principal.userId,organizationId]);
      const row=target.rows[0];
      if (!row) throw new SessionAuthError(403,"FORBIDDEN","This workspace is not available to your account.");
      const current=await client.query<QueryResultRow & {expires_at:Date}>(`SELECT id,expires_at FROM eogp.user_sessions WHERE id=$1 AND user_id=$2 AND organization_id=$3 AND membership_id=$4 AND revoked_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE`,
        [principal.sessionId,principal.userId,principal.organizationId,principal.membershipId]);
      if (!current.rows.length) throw new SessionAuthError(401,"UNAUTHENTICATED","Sign in again.");
      const created=await this.issueStaffSession(request,row,client,false,current.rows[0]!.expires_at);
      await client.query("UPDATE eogp.user_sessions SET revoked_at=clock_timestamp() WHERE id=$1",[principal.sessionId]);
      await client.query("SELECT eogp.record_staff_workspace_switch($1::uuid,$2::uuid,$3::uuid,$4::uuid)",[principal.userId,organizationId,row.membership_id,principal.organizationId]);
      await client.query("COMMIT");return created;
    } catch(error){try{await client.query("ROLLBACK");}catch{/* Preserve error. */}throw error;}finally{client.release();}
  }

  async revokeStaffSession(principal: StaffPrincipal): Promise<void> {
    if (!principal.sessionId) return;
    await this.authPool.query(
      `UPDATE eogp.user_sessions
          SET revoked_at = clock_timestamp()
        WHERE id = $1
          AND user_id = $2
          AND organization_id = $3
          AND membership_id = $4
          AND revoked_at IS NULL`,
      [principal.sessionId, principal.userId, principal.organizationId, principal.membershipId],
    );
  }

  async getCurrentPrincipal(principal: StaffPrincipal): Promise<Record<string, unknown>> {
    await this.authPool.query("SELECT eogp.refresh_platform_admin_access($1::uuid)",[principal.userId]);
    const memberships = await this.authPool.query<MembershipRow>(
      `SELECT
         membership.id AS membership_id,
         organization.id AS organization_id,
         organization.slug AS organization_slug,
         organization.name AS organization_name,
         organization.default_locale
       FROM eogp.organization_memberships AS membership
       JOIN eogp.organizations AS organization
         ON organization.id = membership.organization_id
       WHERE membership.user_id = $1
         AND membership.status = 'active'
         AND organization.status = 'active'
       ORDER BY organization.name, organization.id`,
      [principal.userId],
    );
    const preference = await this.authPool.query<UserLocaleRow>(
      "SELECT locale_preference,is_platform_admin FROM eogp.users WHERE id=$1",
      [principal.userId],
    );
    const selectedMembership = memberships.rows.find((row) =>
      row.organization_id === principal.organizationId && row.membership_id === principal.membershipId
    );
    return {
      userId: principal.userId,
      organizationId: principal.organizationId,
      membershipId: principal.membershipId,
      userLocale: preference.rows[0]?.locale_preference ?? null,
      platformAdmin: preference.rows[0]?.is_platform_admin === true,
      organizationDefaultLocale: selectedMembership?.default_locale ?? "en",
      memberships: memberships.rows.map((row) => ({
        membershipId: row.membership_id,
        organizationId: row.organization_id,
        organizationSlug: row.organization_slug,
        organizationName: row.organization_name,
        selected: row.organization_id === principal.organizationId
          && row.membership_id === principal.membershipId,
      })),
    };
  }


  async updateUserLocale(principal: StaffPrincipal, locale: "bs-BA" | "en" | null): Promise<void> {
    if (locale !== null && locale !== "bs-BA" && locale !== "en") {
      throw new SessionAuthError(400, "INVALID_LOCALE", "Choose a supported language.");
    }
    const updated = await this.authPool.query(
      `UPDATE eogp.users
          SET locale_preference=$2,updated_at=clock_timestamp()
        WHERE id=$1 AND status='active'`,
      [principal.userId,locale],
    );
    if (updated.rowCount !== 1) {
      throw new SessionAuthError(404, "USER_NOT_FOUND", "The staff account is no longer available.");
    }
  }

}
