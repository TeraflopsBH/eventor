# systemd service templates

These units supervise the API and notification worker as separate, unprivileged
Linux services. They are deployment templates, not evidence of validation on a
specific target distribution or host.

## Assumptions

- Node.js 22 is installed in the system service `PATH` (normally `/usr/local/bin`
  or `/usr/bin`). The units invoke it through `/usr/bin/env`; do not rely on a
  per-user version manager whose binaries are unavailable to system services.
- A reviewed release is installed at `/opt/eventor/releases/<release-id>`,
  and `/opt/eventor/current` points to that release.
- The release tree is root-owned and readable/traversable, but not writable, by
  either service account.
- API and worker configuration are stored separately in root-managed files.
- PostgreSQL is reachable over TLS with certificate and hostname verification.
- A reverse proxy is configured separately. These units do not expose or
  configure a public listener.

## Install service accounts and directories

Run once as an administrator:

```sh
sudo useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin eventor-api
sudo useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin eventor-worker
sudo install -d -o root -g root -m 0750 /opt/eventor /opt/eventor/releases
sudo install -d -o root -g root -m 0750 /etc/eventor
```

Install a built release under `/opt/eventor/releases/<release-id>`, owned by
root and not writable by service users. Atomically update the `current`
symlink only after the API and staff-web build artifacts have been verified:

```sh
sudo chown -R root:root /opt/eventor/releases/<release-id>
sudo chmod -R u=rwX,go=rX /opt/eventor/releases/<release-id>
sudo ln -sfn /opt/eventor/releases/<release-id> /opt/eventor/current.new
sudo mv -Tf /opt/eventor/current.new /opt/eventor/current
```

The release must contain the complete repository layout, including
`apps/api/dist`, `apps/staff-web/dist`, migrations and operational scripts.
Build the API and staff web from the same reviewed commit as described in the
deployment runbook.

## Configure secrets

Create the two environment files with an editor that does not expose secrets in
shell arguments or history. Start from `apps/api/.env.example`, but include
only variables required by the corresponding process:

- `/etc/eventor/api.env`: runtime/auth database URLs, allowed origins, API
  encryption/fingerprint/capability keys, public API base URL, `HOST`,
  `PORT`, proxy CIDRs and API pool settings.
- `/etc/eventor/worker.env`: worker database URL, contact and delivery
  credential encryption keys, public staff-web base URL and worker tuning.

The API file must not contain the worker database password. The worker file
must not contain runtime, auth or migrator database credentials. Do not put
`DATABASE_URL` or migrator credentials in either file.

Set ownership and permissions so only root and the corresponding service group
can read each file:

```sh
sudo chown root:eventor-api /etc/eventor/api.env
sudo chmod 0640 /etc/eventor/api.env
sudo chown root:eventor-worker /etc/eventor/worker.env
sudo chmod 0640 /etc/eventor/worker.env
```

When the reverse proxy is on the same host, set `HOST=127.0.0.1` in the API
environment file. Otherwise bind only to a private interface and firewall the
port to the exact proxy address. Set trusted proxy CIDRs to the exact proxy
addresses; never use a wildcard.

## Install and start

```sh
sudo install -o root -g root -m 0644 deploy/systemd/eventor-api.service /etc/systemd/system/
sudo install -o root -g root -m 0644 deploy/systemd/eventor-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now eventor-api.service
sudo systemctl enable --now eventor-worker.service
```

Inspect service state and logs:

```sh
systemctl status eventor-api.service eventor-worker.service
journalctl -u eventor-api.service -u eventor-worker.service --since today
```

The worker unit allows 120 seconds for graceful shutdown. Confirm this exceeds
the configured maximum in-flight SMTP/worker operation timeouts on the target
deployment; adjust it deliberately if those limits differ. The API unit allows
45 seconds for shutdown.

## Release updates

Stop the worker before changing the release symlink. Deploy API and static
staff-web assets from the same release commit, atomically switch the symlink,
then start/restart the services. Follow the database backup, migration and
recovery gates in the main deployment runbook. Do not automatically roll back
application code across a schema change without verifying compatibility.

## Validation boundary

These templates have not been exercised on a target host. Before production
use, verify the Node executable path, user/group creation, filesystem traversal,
environment-file permissions, systemd sandbox compatibility, proxy routing,
TLS, restart behavior and graceful shutdown on the selected Linux distribution.
