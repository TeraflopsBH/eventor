# ADR 0007: Make internationalization a cross-cutting platform capability

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related:** ADR 0001, ADR 0004, [Project state](../PROJECT_STATE.md)

## Context

Eventor is a self-hosted, multi-organization product. The reference deployment is in Bosnia and Herzegovina, but the platform is intended for organizations and customers who may use different languages. The current staff workspace is a Vue 3 application with user-visible strings embedded directly in a large component. The API returns a principal and organization memberships, but neither the organization model nor the staff principal currently exposes a locale preference. Organization records have a default timezone; timezone is not a substitute for locale.

Adding translations after the staff and customer interfaces expand would require invasive changes and risk mixing translated labels with stable business values. Customer communications also need to be understandable in the recipient's language without changing the immutable commercial terms accepted by the customer.

## Decision

### 1. Locale identifiers and initial languages

1. Use canonical BCP 47 language tags, not translated names or arbitrary short codes, as locale identifiers.
2. Initial reference locales are `bs-BA` (Bosnian as used in Bosnia and Herzegovina) and `en` (English).
3. Keep locale identifiers separate from stable domain codes, database enum values, permission codes, API field names and workflow states. Translated display labels must never be used as identifiers.
4. Store translation catalogs as version-controlled application resources. Do not store application UI labels in tenant-editable database rows.

### 2. Staff locale resolution

Resolve the staff interface locale in this order:

1. Explicit, valid user preference.
2. Selected organization's configured default locale.
3. Deployment-wide fallback locale (`en`).

The user's preference is a presentation preference and applies across organizations. An organization default is a tenant configuration fallback, not a forced language. A user's preference must not alter another user's display or the language of a message already issued.

Locale values received from browsers, headers, query parameters or API clients must be validated against the deployment's supported-locale catalogue. Unsupported values fall back; they must not cause arbitrary locale loading or filesystem access.

### 3. Customer-facing locale resolution

Resolve a customer-facing page or communication using:

1. An explicit, validated language choice associated with that customer interaction or communication request.
2. A customer language preference, when one has been collected and is available for that purpose.
3. The owning organization's configured default locale.
4. The deployment fallback locale (`en`).

A public page may accept a locale hint, but the hint is presentation input only and cannot grant access or change the underlying booking/offer. Do not infer language from a person's name, nationality, location or other personal attributes.

### 4. Translation resources and authored content

1. UI translation keys are stable, namespaced identifiers (for example, `booking.offer.accept`); translated strings are resources, not keys.
2. Use a maintained Vue-compatible i18n library for the staff client rather than a home-grown interpolation/pluralization engine. Select the package and version in the implementation PR based on the existing Vue 3 toolchain.
3. Use standards-based locale formatting and plural rules (ECMA-402 `Intl` in JavaScript runtimes). Do not concatenate translated fragments to construct sentences.
4. Vendor-authored content that must be presented in multiple languages (for example, public descriptions, service descriptions, policy text and email templates) is distinct from application UI translation. Model translations as language-tagged content associated with a stable source record and preserve publication/revision semantics. Do not overwrite one language with another.
5. A missing authored-content translation must be visible to staff and follow a documented fallback policy; do not silently generate machine translations.
6. Email templates and other customer communication templates must be language-specific or resolve through a shared translation catalogue. The rendered communication and its locale must be retained with the delivery/audit record when needed to reproduce what was sent.

### 5. Dates, times, numbers and money

1. Locale controls presentation, not domain meaning.
2. Timezone remains an explicit domain value. Use the booking/event timezone for event and booking times; use the organization's timezone only where the domain explicitly calls for it. Never derive timezone from locale.
3. Store timestamps as instants and preserve the relevant IANA timezone separately where local scheduling meaning matters.
4. Store monetary values and ISO 4217 currency codes independently of locale. Locale formatting must not change the amount, currency, tax calculation or rounding.
5. Use locale-aware number, date, time, currency and plural formatting in both browser and server-rendered/customer-communication paths. Ensure server and browser resolve the same explicit locale and timezone to avoid inconsistent output.

### 6. Fallback and quality rules

1. Missing UI keys fall back to the deployment fallback locale and are reported by development/test tooling.
2. Missing customer-authored translation falls back only according to the content type's explicit policy; the interface should identify the language actually being shown where ambiguity matters.
3. Do not fall back to a different locale silently for legal, commercial or policy text where the recipient could reasonably believe the text is authoritative in the requested language. Such content must be explicitly marked unavailable or the communication must use an approved available language.
4. Translation catalogs must be UTF-8 and support full Unicode, including Bosnian Latin diacritics.
5. Tests must cover locale precedence, unsupported locale fallback, pluralization, formatting, missing keys and preservation of stable API/domain codes.

## Consequences

- Organization and user locale preferences require a reviewed schema/API implementation; this ADR does not itself add database columns or alter current API responses.
- The current staff workspace should be migrated incrementally from inline English strings to namespaced translation keys, beginning with shared navigation, authentication and common status/action labels.
- Customer-facing offer, booking inquiry, invitation/RSVP and cancellation communications must resolve and record an explicit locale before broader rollout.
- Vendor-authored translatable content needs a versioned translation model so historical offers, policies and sent messages remain reproducible.
- The reference deployment can begin with Bosnian and English without constraining future deployments to those languages.
- Locale and timezone remain separate configuration concerns; the existing `Europe/Sarajevo` timezone default is not a locale default.
- No database migration, API contract change or frontend dependency is introduced by this decision-only slice. Those changes belong in subsequent implementation PRs with migration, API, unit and database regression coverage.

## Implementation sequence

1. Add supported-locale catalogues and staff-client i18n runtime, migrate shared shell/authentication strings, and test fallback/plural/formatting behavior.
2. Add organization default locale and user preference persistence, expose them through permission-appropriate API projections and settings commands, and test cross-tenant behavior.
3. Add locale resolution to public booking forms/offers and customer communication jobs; record the resolved locale and rendered template/content revision with delivery evidence.
4. Add versioned translations for vendor-authored public descriptions, policy text and reusable templates as those administration workflows are implemented.
5. Extend the same locale contract to guest portal, invitations/RSVP, cancellation notices, check-in and operational interfaces.

Each step must remain independently reviewable. Do not translate the entire interface in one change or combine locale behavior with unrelated commercial workflow changes.
