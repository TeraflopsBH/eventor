# ADR 0002: Self-hosted deployment without mandatory container or cloud dependencies

- **Status:** Accepted as the initial deployment constraint
- **Date:** 2026-11-10

## Context

The target environment is organization-controlled Linux infrastructure. The platform should remain usable without a cloud subscription and should not force Docker or a managed external service into the deployment.

## Decision

Design for self-hosted Linux deployment. Native service management (for example systemd) and a reverse proxy are valid deployment mechanisms. Containers may be offered as an optional packaging/deployment convenience, not as a mandatory runtime architecture. Do not require a cloud service, Redis/Valkey or Docker without a future ADR and explicit operational justification.

## Consequences

- Deployment, upgrades, backup and restore must be documented for the supported self-hosted path.
- Background jobs and realtime delivery need clear local infrastructure requirements.
- Optional container support must not become the only tested or documented deployment route.
