# Local development on Zorin OS

This workflow keeps the API and staff web native for fast editing and uses
Docker only for disposable PostgreSQL 18.6 development infrastructure. It does
not replace the native Linux or production Docker Compose installers required
for release.

## Safe workstation inspection

The Cloud development environment cannot inspect a physical workstation. Run
the repository doctor on the Zorin machine; it makes no privileged or
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
