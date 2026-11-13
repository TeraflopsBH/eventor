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


## Incremental extraction record

The first extraction moves booking-inquiry presentation logic into `src/features/booking-inquiries/presentation.ts`: answer-value formatting, assignee display-name resolution, inquiry date display and booking-money display. The module depends only on the API's inquiry data types and explicit inputs; it does not own network calls or authorization decisions. Existing behavior is preserved while the root component delegates to the feature module. Next extraction should move inquiry state and API orchestration into a focused composable, then isolate the inquiry view, rather than attempting a wholesale rewrite.


The next extraction after presentation helpers moves booking-inquiry state and command orchestration into `src/features/booking-inquiries/useBookingInquiries.ts`. The composable receives shared application dependencies explicitly and exposes state/actions to the root composition layer. The existing inquiry template remains in `App.vue` at this stage; a dedicated feature view is a later step. Server-side authorization remains authoritative, with capability checks retained in the client for presentation and interaction gating.


The next extraction moves booking-inquiry state and command orchestration into `src/features/booking-inquiries/useBookingInquiries.ts`. The composable receives shared application dependencies explicitly and exposes state/actions to the root composition layer. The existing inquiry template remains in `App.vue`; a dedicated feature view is a later step. Server-side authorization remains authoritative, with capability checks retained in the client for presentation and interaction gating.


The next extraction isolates the booking-inquiry workspace presentation in `src/features/booking-inquiries/BookingInquiryView.vue`. The view receives the feature composable's state and actions through an explicit workspace prop and emits the action that opens the booking draft. The inquiry inbox/detail/review/annotation/history UI is feature-owned. Booking-draft editing and commercial offer/approval/confirmation markup remain in the root composition layer and are supplied through named slots, avoiding an accidental expansion of this view extraction into the separate commercial workflow. The root retains shared session lifecycle, booking-draft state and offer orchestration.


Booking-draft workflow state and commands form a separate feature module at `src/features/booking-drafts/useBookingDraft.ts`. It owns the selected draft and revision editor state, capability-derived editability, loading/refresh, revision creation and reset. The root composition layer supplies shared dependencies and coordinates the selected inquiry's draft reference. Offer preparation, delivery, approvals and confirmation remain a distinct commercial-offer workflow and should be extracted separately rather than coupled into the booking-draft composable.

The commercial offer lifecycle is extracted into `src/features/booking-offers/useBookingOffers.ts`. This cohesive feature owns offer preparation and successor revisions, issuance, customer capability handling, SMTP delivery queue/reconciliation/retry, approval decisions and explicit booking confirmation. It receives the shared API/session/message state and booking-draft/inquiry refresh dependencies from the root composition layer. Price-list, cancellation-policy and tax-profile administration remain separate configuration workflows; this extraction does not change their API behavior or the server's authority over permissions and final availability.

Commercial configuration is split by domain rather than collected in one generic composable: price lists, tax profiles, approval policies and cancellation policies each have a dedicated feature composable under `src/features/`. The price-list feature consumes the tax feature's published-revision projection through an explicit dependency to filter compatible currency/tax-basis revisions. The root component remains the composition boundary for shared API/session/busy/message state and currently hosts the corresponding workspace markup; feature view components can be extracted separately without coupling domain state or API orchestration.


The four commercial-configuration workspace templates are extracted into feature-owned views under their corresponding feature directories. Each view receives the matching composable return contract through a typed `workspace` prop and the shared busy reference; it owns presentation only and does not instantiate an API client or duplicate workflow state. `App.vue` composes the views by active workspace and retains only the cross-feature tax-profile projection needed by price-list configuration. This keeps the four domains independently reviewable while preserving the existing UI and command boundaries.


Campaign review and delivery reporting follow the same boundary: `features/campaigns/useCampaigns.ts` owns campaign and delivery state/commands, while `CampaignWorkspaceView.vue` renders the workspace from an explicit typed contract. Shared session messages, busy state and SMTP readiness remain application-level dependencies passed into the feature. The root no longer owns campaign lookup, delivery reconciliation/retry, or campaign lifecycle command implementations.


The organization email-delivery workspace is extracted into `src/features/email-delivery/useEmailDelivery.ts` and `EmailDeliveryView.vue`. The composable owns SMTP configuration state, write-only credentials, explicit credential clearing, revision save/test behavior and the optional Resend callback lifecycle. The view owns the existing readiness/configuration UI and receives a typed workspace contract. `App.vue` retains session-level composition and shares the email configuration readiness with campaign operations. This does not make Resend a required sending provider: organization-owned SMTP remains the generic delivery interface, while Resend callbacks are conditionally available for the Resend SMTP host.


The application shell and staff session lifecycle are extracted into `src/features/application-shell/`: `useStaffSession.ts` owns principal/session restoration, sign-in/out, selected-organization display and centralized API error handling, while `StaffApplicationShell.vue` owns the shared login/authenticated shell, locale selector, navigation, notices and footer. Session error/sign-out cleanup is delegated through an explicit reset callback to keep feature lifecycle ownership in the feature modules. The public customer offer capability-link flow is separately rendered in `src/features/public-booking-offers/PublicBookingOfferPage.vue`; it is not nested in the staff workspace shell. `App.vue` is the composition boundary for public-route selection and staff feature composition.


The booking-draft editor and commercial offer workspace presentation are extracted into `src/features/booking-drafts/CommercialBookingWorkspaceView.vue`. The view provides separate `draft-editor` and `offer-workspace` modes to fit the existing named slots in `BookingInquiryView.vue`, and consumes a typed intersection of the draft and offer composable contracts. It owns no API client or workflow state. `App.vue` now only composes the draft and offer composables and passes their combined workspace to the view; immutable draft revisions, offer issuance/delivery, approval decisions and explicit booking confirmation remain in their existing feature composables.


The inquiry presentation helpers now require explicit locale and timezone inputs. A feature-owned `useInquiryPresentation.ts` composable bridges Vue I18n's active locale and the browser-resolved local timezone into the pure date/currency formatting functions, and resolves the empty-date label from the common catalogue. All booking inquiry and commercial configuration views that display these values use the shared presentation composable. Locale changes therefore affect presentation reactively; stored timestamps, ISO currency codes, exact monetary values and domain calculations remain unchanged.


The booking inquiry and commercial booking workspace views consume feature-scoped `bookingInquiry` and `commercialBooking` namespaces from both locale catalogues. Domain status values remain the untranslated `value` of controls and API payloads; only their displayed labels are localized. Commercial identifiers, codes, currency values, tax-allocation method tokens, immutable snapshots and user-entered text are not translated. This keeps language selection strictly at the presentation boundary.


The public booking-offer capability page uses the `publicOffer` feature namespace and an explicit customer language choice rather than inferring language from customer identity or location. Locale-aware date/number formatting follows that choice; customer-entered and organization-authored commercial terms remain untouched.


Booking workflow composables receive a typed translation function from `App.vue` rather than owning or importing a locale runtime. Client-owned validation, confirmation prompts, success/error notices and JSON parsing feedback use the feature catalogues. This keeps locale selection at the application boundary and makes workflow copy react to locale changes without changing domain values, API behavior or server-originated error messages.

Commercial-configuration workflow composables follow the same localization boundary as inquiry and offer workflows: `App.vue` supplies the active translator, while each feature composable owns its domain validation and command orchestration. Client-owned confirmations, validation feedback and success notices resolve through the `commercialConfiguration` catalogue in English and Bosnian. The composables remain independent of Vue I18n runtime imports; domain values and server-originated API errors are not rewritten. Static view-copy localization remains a separate presentation concern.
