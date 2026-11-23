# Local development on Zorin OS

This workflow keeps the API and staff web native for fast editing and uses
Docker only for disposable PostgreSQL 18.6 development infrastructure. It does
not replace the native Linux or production Docker Compose installers required
for release.

## Resume an interrupted session

Start with the checkout and current handoff:

```bash
git status --short --branch
git log -5 --oneline
git fetch origin
git log -3 --oneline origin/main
```

Read [current project state](../PROJECT_STATE.md), then the active issue and
relevant design/ADR. Inspect local changes and named stashes before applying
saved work; preserve them when reconciling a squash-merged branch. Verify the
current PR SHA and its CI results. Historical receipts remain in the linked
state archive and need reading only when a particular decision or evidence
is missing. Keep new status updates in the short current handoff.

Use focused checks for the changed behavior and full checks before submitting
application changes. Logs under `.eventor-dev/logs/` retain diagnostics between
runs. After a new login or Docker group change, the doctor verifies access from
the current process before attempting database/browser tests.

## Safe workstation inspection

Run the repository doctor on the development host; it makes no privileged or
system-wide changes:

```bash
mkdir -p ~/Development
cd ~/Development
git clone https://github.com/TeraflopsBH/eventor.git
cd eventor
./scripts/dev/doctor.sh --remote
```

If the checkout already exists, inspect `git status --short --branch` before
switching branches or pulling. Never reset local changes to make setup pass.

The verified parity versions are Node.js 22.16.0, PostgreSQL 18.6 and Python
3.12. The doctor enforces presence and warns about version drift; setup requires
the exact Node pin. `.nvmrc` and `.node-version` pin Node. Docker Compose v2 supplies
PostgreSQL, so no host PostgreSQL installation is required. Python is used by
the full OpenAPI checks. Obtain missing system packages through the supported
Zorin/Ubuntu or vendor installation method; review privileged installation
commands before running them.

## One-time setup

Activate Node 22.16.0 with the user-level version manager of your choice, then:

```bash
./scripts/dev/setup.sh
./scripts/dev/db.sh up
./scripts/dev/check.sh quick
```

`setup.sh` installs both committed npm lockfiles and a Python virtual
environment. `db.sh up` generates local credentials in the ignored
`.eventor-dev/dev.env`, starts PostgreSQL on `127.0.0.1:55432`, reconciles the
least-privilege roles, and applies checksum-verified migrations. It is safe to
run again after pulling new migrations.

The database is deliberately bound to loopback. Do not reuse its generated
credentials or Compose file for a shared or production system.

The staff workspace applies a checksum-pinned local guard to Picomatch 4.0.7
during dependency installation. Until an upstream release fixes
[GHSA-fc5q-39xc-vjpf](https://github.com/advisories/GHSA-fc5q-39xc-vjpf),
the staff audit accepts that one finding only when it verifies the exact patched
parser. All other high and critical findings still fail CI. When updating
Picomatch, verify the upstream fix and remove the local guard and audit handling.

## Short development commands

```bash
./scripts/dev/check.sh quick
./scripts/dev/check.sh api
./scripts/dev/check.sh api 'organizer event administration'
./scripts/dev/check.sh web
./scripts/dev/check.sh db ROLE path/to/fixture.sql
./scripts/dev/check.sh full
```

Commands keep full output in `.eventor-dev/logs/` and print a short result plus
the relevant log tail on failure. This makes routine development and automated
agent sessions cheaper to inspect while preserving complete diagnostics.
Database fixtures often depend on earlier CI fixture steps; run a focused SQL
file only after preparing the prerequisites it documents.

Start processes in separate terminals:

```bash
./scripts/dev/run.sh api
./scripts/dev/run.sh web
```

Use `./scripts/dev/run.sh api-debug` to expose the Node inspector only on
`127.0.0.1:9229`. The API builds before starting; restart it after TypeScript
changes. Use `./scripts/dev/run.sh worker` for the notification worker.

## Browser smoke tests on Linux

The CI smoke runner uses the pinned Playwright image for Chromium, Firefox and their system libraries. The API and staff preview run on the Linux host. Install the matching Playwright client in `apps/api` and start the relevant synthetic services before running a check.

```bash
npm --prefix apps/api install --no-save --package-lock=false playwright@1.56.1
EVENTOR_BROWSER_BASE_URL=http://localhost:8080 bash scripts/dev/run-browser-smoke.sh session
EVENTOR_GUEST_BROWSER_BASE_URL=http://localhost:4173 bash scripts/dev/run-browser-smoke.sh guest-invitation
```

The session check expects the synthetic login fixture with the test password configured on the API database. The invitation check uses the built staff preview and browser-side test responses. The runner uses Linux host networking so the browser sees the same loopback URLs as the host. Update the client version and image pin together when upgrading Playwright.

## Database lifecycle

```bash
./scripts/dev/db.sh status
./scripts/dev/db.sh psql eventor_migrator
./scripts/dev/db.sh down
```

`down` preserves data. `reset --yes` removes only the `eventor-dev` PostgreSQL
Compose volume and is intended for an explicitly requested clean disposable
database. It retains the ignored local credential file. Never aim the reset or
test fixtures at a non-disposable database.

## Validation sequence

Use focused local checks during development, then run `check.sh full` before a
pull request. This is the full application check, not complete CI parity.
GitHub Actions additionally runs dependency audits, PostgreSQL integration and
concurrency, browser acceptance, systemd validation and secret-history scans;
it remains the exact-head integration authority. The
`eventor-acceptance` VM remains reserved for the final integrated product and
both installation modes.

The CI browser suite checks authentication, the guest invitation view and organization access administration in Chromium and Firefox using the pinned Playwright image. The organization access workflow uses `tests/database/organization_access_browser_fixture.sql` and the synthetic staff accounts. Run it against an isolated test database and staff frontend with `EVENTOR_ACCESS_BROWSER_BASE_URL=http://localhost:4173 bash scripts/dev/run-browser-smoke.sh organization-access`. The test creates role presets, assigns and revokes event grants, retires presets and verifies command retries.

### Isolated native PostgreSQL checks

With PostgreSQL 18's postgres, initdb, pg_ctl, psql and createdb binaries on PATH, run the following command. This needs a regular user account and the PostgreSQL extensions used by the migrations.

    bash scripts/dev/test-native-postgres.sh

The command initializes a fresh temporary cluster, accepts connections through its private Unix socket, bootstraps the application roles, rehearses populated upgrades and runs the database constraint, RLS, concurrency and authentication privilege tests. It stops and removes its temporary cluster on exit. Logs remain under .eventor-dev/logs/native-postgres.*.

Use scripts/dev/check.sh full for the application checks. GitHub CI adds the broader database integration and browser suites.
