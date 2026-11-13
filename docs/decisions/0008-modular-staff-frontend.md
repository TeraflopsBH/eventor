# ADR 0008: Keep staff frontend modular and feature-oriented

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related:** ADR 0001, ADR 0007

## Context

The staff application currently places most application state, API orchestration, formatting helpers and multiple workflows in a single `App.vue`. This makes unrelated features difficult to review independently and creates friction for translation, testing and future contributors. Adding i18n to that file would reinforce the existing concentration of responsibilities.

## Decision

1. Keep `App.vue` as a thin application composition/root component. It may own top-level route selection and compose feature views, but must not become the home for every workflow.
2. Organize substantial product areas as feature modules (for example, booking inquiries, offers, approvals, pricing, cancellation policies, tax configuration and email delivery).
3. Place reusable presentational controls and layout primitives in a shared component area; keep feature-specific components with their owning feature.
4. Move reusable Vue state and behavior into focused composables. Keep API transport and endpoint contracts in API/client modules, not inside presentational components.
5. Keep domain calculations and formatting independent of component templates. Locale-aware formatting belongs in shared i18n/formatting utilities and must receive explicit locale/timezone context.
6. Keep translation catalogues grouped by language and stable feature namespaces. Do not scatter translated strings across components or use translated labels as domain values.
7. Avoid premature fragmentation: split by responsibility and stable feature boundary, not by creating a component for every wrapper or line of markup.
8. New UI work must follow this structure. Existing monolithic sections should be extracted incrementally as they are next modified; do not perform a risky all-at-once rewrite.

## Consequences

- New feature work can be reviewed and tested in smaller units.
- `App.vue` remains temporarily large until existing workflows are extracted; this ADR does not claim that the legacy monolith has already been decomposed.
- The i18n foundation is a first modular boundary: locale catalogues, runtime setup and formatting utilities live outside the root component.
- Subsequent extraction should prioritize feature views and API/state composables, preserving behavior and authorization checks.
