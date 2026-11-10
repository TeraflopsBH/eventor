# Contributing

Eventor is being developed in small, reviewable increments. The repository's design baseline and project state take precedence over assumptions made in chat or issue discussions.

## Before starting

- Read `AGENTS.md`, `docs/PROJECT_STATE.md`, and relevant architecture decisions.
- Check existing issues and avoid duplicating work.
- Identify dependencies and acceptance criteria before implementation.
- Use synthetic data only.

## Branches and commits

- Use short descriptive branches, for example `feat/guest-rsvp`, `fix/invitation-token-validation`, or `docs/booking-workflow`.
- Keep commits focused and use imperative messages with a conventional prefix where practical: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Do not commit directly to `main` for normal feature work once branch protections and review workflow are configured.

## Pull requests

A PR should include:
- Problem and intended behavior.
- Scope and notable design choices.
- Database migration and API contract impact.
- Authorization, privacy and audit implications.
- Tests added and exact verification commands/results.
- Screenshots for material UI changes, using synthetic data.

Do not mark a PR complete while required migrations, contract updates, tests or documentation are missing.

## Architectural decisions

Material architectural or domain decisions belong in an ADR under `docs/decisions/`. Include context, decision, alternatives, consequences, and status. Supersede an ADR rather than rewriting history.

## Definition of done

- Acceptance criteria are met.
- Validation and authorization are enforced server-side.
- Relevant tests pass, or unrun tests are explicitly identified.
- Migrations/contracts/docs are synchronized.
- No secrets, real guest PII or sensitive venue material are included.
- Operational and failure behavior is documented where relevant.
