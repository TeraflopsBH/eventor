<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import type { SupportedLocale } from "./i18n";
import { useBookingInquiries } from "./features/booking-inquiries/useBookingInquiries";
import { useBookingDraft } from "./features/booking-drafts/useBookingDraft";
import { useBookingOffers } from "./features/booking-offers/useBookingOffers";
import { useBookingPriceLists } from "./features/booking-prices/useBookingPriceLists";
import { useBookingTaxProfiles } from "./features/booking-taxes/useBookingTaxProfiles";
import { useBookingApprovalPolicies } from "./features/booking-approvals/useBookingApprovalPolicies";
import { useBookingCancellationPolicies } from "./features/booking-cancellations/useBookingCancellationPolicies";
import BookingInquiryView from "./features/booking-inquiries/BookingInquiryView.vue";
import BookingPriceListsView from "./features/booking-prices/BookingPriceListsView.vue";
import BookingTaxProfilesView from "./features/booking-taxes/BookingTaxProfilesView.vue";
import BookingApprovalPoliciesView from "./features/booking-approvals/BookingApprovalPoliciesView.vue";
import BookingCancellationPoliciesView from "./features/booking-cancellations/BookingCancellationPoliciesView.vue";
import { useCampaigns } from "./features/campaigns/useCampaigns";
import CampaignWorkspaceView from "./features/campaigns/CampaignWorkspaceView.vue";
import { useEmailDelivery } from "./features/email-delivery/useEmailDelivery";
import EmailDeliveryView from "./features/email-delivery/EmailDeliveryView.vue";
import { formatBookingMoney, formatInquiryDate } from "./features/booking-inquiries/presentation";
import { api, ApiError, type Principal, type PublicBookingOffer } from "./api";

const { locale } = useI18n();
watch(locale, (value) => { document.documentElement.lang = value; }, { immediate: true });
const localeOptions: Array<{ value: SupportedLocale; label: string }> = [
  { value: "bs-BA", label: "Bosanski" },
  { value: "en", label: "English" },
];

const publicOfferMatch = window.location.pathname.match(/^\/offers\/([0-9a-fA-F-]{36})\/?$/);
const isPublicOfferPage = Boolean(publicOfferMatch);
const publicOfferId = publicOfferMatch?.[1] ?? "";
const publicOfferToken = ref(new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "");
const publicOffer = ref<PublicBookingOffer | null>(null);
const publicOfferLoading = ref(isPublicOfferPage);
const publicOfferError = ref("");
const publicOfferDecision = ref<"accepted" | "rejected" | null>(null);
const publicAcceptanceName = ref("");
const publicAcceptanceNote = ref("");
const publicRejectionReason = ref("");
const publicRejectionNote = ref("");
const publicDecisionBusy = ref(false);
const publicDecisionKey = ref("");
const publicDecisionKind = ref<"accepted" | "rejected" | null>(null);
const principal = ref<Principal | null>(null);
const loadingSession = ref(true);
const activeTab = ref<"delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes">("delivery");
const busy = ref(false);
const pageError = ref("");
const pageNotice = ref("");

const loginForm = reactive({ email: "", password: "", organizationSlug: "" });

const selectedOrganization = computed(() =>
  principal.value?.memberships?.find((membership) => membership.selected)?.organizationName
  ?? principal.value?.organizationId
  ?? "",
);
const canReadBookingDraft = computed(() =>
  inquiryCapabilities.value.canReadDraft && Boolean(inquiryDetail.value?.bookingDraft),
);

function clearMessages(): void {
  pageError.value = "";
  pageNotice.value = "";
}

let resetBookingDraftState = (): void => {};

function clearBookingDraftState(): void {
  resetBookingDraftState();
  bookingOfferState.reset();
}

const bookingInquiryState = useBookingInquiries({
  principal, busy, activeTab, pageError, pageNotice, api,
  clearMessages, showError, clearBookingDraftState,
});
const {
  inquiryDetail, inquiryCapabilities, refreshInquiryDetailData, openInquiryWorkspace,
  reset: resetBookingInquiries,
} = bookingInquiryState;

const bookingDraftState = useBookingDraft({
  api,
  busy,
  pageError,
  pageNotice,
  canManageDraftPermission: computed(() => inquiryCapabilities.value.canManageDraft),
  clearMessages,
  showError,
  refreshInquiryDetail: refreshInquiryDetailData,
});
resetBookingDraftState = bookingDraftState.reset;


const {
  detail: bookingDraftDetail,
  editorOpen: bookingDraftEditorOpen,
  valuesJson: bookingDraftValuesJson,
  spaceLinesJson: bookingDraftSpaceLinesJson,
  resourceLinesJson: bookingDraftResourceLinesJson,
  requestedStart: bookingDraftRequestedStart,
  requestedEnd: bookingDraftRequestedEnd,
  timezone: bookingDraftTimezone,
  changeReason: bookingDraftChangeReason,
  canManage: canManageBookingDraft,
  refresh: refreshBookingDraft,
  saveRevision: saveBookingDraftRevision,
} = bookingDraftState;
const bookingOfferState = useBookingOffers({
  api, busy, pageError, pageNotice, principal, bookingDraftDetail,
  clearMessages, showError, refreshBookingDraft, refreshInquiryDetail: refreshInquiryDetailData,
});
const {
  bookingOffer, bookingOfferApprovalStatus, bookingOfferIdInput, bookingOfferAcceptanceToken,
  bookingOfferConfirmationReason, bookingOfferIssueRequestKey, bookingOfferEmailRequestKey,
  bookingOfferEmailDeliveries, bookingOfferEmailMeta, bookingOfferEmailStatusFilter,
  bookingOfferEmailOffset, bookingOfferEmailResolution, bookingOfferEmailReason,
  bookingOfferEmailReference, bookingOfferEmailRetryReason, bookingOfferSupersedeCurrent,
  bookingOfferValidUntil, bookingOfferTaxAmount, bookingOfferInternalReason,
  bookingOfferCreateForm, bookingOfferLineItemsJson, bookingOfferAdjustmentsJson,
  bookingOfferApprovalDecisions, bookingOfferApprovalReasons,
  canManageBookingOffer, canConfirmBookingOffer, refreshBookingOfferData,
  refreshBookingOfferEmailData, loadBookingOffer, saveBookingOfferRevision,
  issueBookingOffer, emailBookingOffer, reconcileBookingOfferEmail, retryBookingOfferEmail,
  copyBookingOfferCapability, canDecideBookingOfferRequirement, decideBookingOfferApproval,
  confirmBookingFromAcceptedOffer,
} = bookingOfferState;

const bookingTaxProfileState = useBookingTaxProfiles({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});
const { publishedTaxProfileRevisions, loadBookingTaxProfiles } = bookingTaxProfileState;

const bookingPriceListState = useBookingPriceLists({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
  publishedTaxProfileRevisions, loadBookingTaxProfiles,
});


const bookingApprovalPolicyState = useBookingApprovalPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});


const bookingCancellationPolicyState = useBookingCancellationPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});

const campaignState = useCampaigns({
  api, busy, pageError, pageNotice, clearMessages, showError,
});
const emailDeliveryState = useEmailDelivery({
  api, busy, pageError, pageNotice, clearMessages, showError,
});
const { configuration, loadConfiguration } = emailDeliveryState;
const campaignWorkspace = { ...campaignState, busy, configuration };
const emailDeliveryWorkspace = { ...emailDeliveryState, busy };



function showError(error: unknown): void {
  if (error instanceof ApiError) {
    if (error.status === 401) {
      principal.value = null;
      emailDeliveryState.reset();
      campaignState.reset();
      resetBookingInquiries();
      pageError.value = "Your session has expired. Please sign in again.";
      return;
    }
    if (error.status === 403) {
      pageError.value = `Permission denied: ${error.message}`;
      return;
    }
    pageError.value = `${error.message} [${error.code}]`;
    return;
  }
  pageError.value = error instanceof Error ? error.message : "An unexpected error occurred.";
}

async function refreshSession(): Promise<void> {
  loadingSession.value = true;
  try {
    const result = await api.me();
    principal.value = result.data;
    await loadConfiguration();
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      principal.value = null;
    } else {
      showError(error);
    }
  } finally {
    loadingSession.value = false;
  }
}

async function signIn(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.login({
      email: loginForm.email.trim(),
      password: loginForm.password,
      organizationSlug: loginForm.organizationSlug.trim(),
    });
    loginForm.password = "";
    await refreshSession();
    if (principal.value) pageNotice.value = "Signed in successfully.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function signOut(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.logout();
    principal.value = null;
    emailDeliveryState.reset();
    campaignState.reset();
    resetBookingInquiries();
    pageNotice.value = "You have been signed out.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function openBookingDraft(): Promise<void> {
  const draftReference = inquiryDetail.value?.bookingDraft;
  await bookingDraftState.open(draftReference?.draftId, inquiryCapabilities.value.canReadDraft);
}






























function createPublicDecisionKey(): string {
  return globalThis.crypto.randomUUID();
}

async function loadPublicBookingOffer(): Promise<void> {
  publicOfferLoading.value = true;
  publicOfferError.value = "";
  if (!publicOfferId || !/^[0-9a-fA-F-]{36}$/.test(publicOfferId)) {
    publicOfferError.value = "This offer link is invalid.";
    publicOfferLoading.value = false;
    return;
  }
  if (!/^[A-Za-z0-9_-]{43}$/.test(publicOfferToken.value)) {
    publicOfferError.value = "This offer link is incomplete. Open the original link supplied by the organization.";
    publicOfferLoading.value = false;
    return;
  }
  try {
    const result = await api.getPublicBookingOffer(publicOfferId, publicOfferToken.value);
    publicOffer.value = result.data;
  } catch (error) {
    publicOfferError.value = error instanceof ApiError && error.status === 410
      ? "This offer has expired."
      : error instanceof Error ? error.message : "The offer could not be loaded.";
  } finally {
    publicOfferLoading.value = false;
  }
}

async function submitPublicOfferAcceptance(): Promise<void> {
  const name = publicAcceptanceName.value.trim();
  if (!name) {
    publicOfferError.value = "Enter your name to record acceptance.";
    return;
  }
  if (!publicOfferId || !publicOfferToken.value || !publicOffer || publicOffer.value.status !== "issued") return;
  publicDecisionBusy.value = true;
  publicOfferError.value = "";
  if (publicDecisionKind.value !== "accepted") {
    publicDecisionKey.value = createPublicDecisionKey();
    publicDecisionKind.value = "accepted";
  }
  try {
    await api.acceptPublicBookingOffer(
      publicOfferId,
      publicOfferToken.value,
      { acceptanceName: name, acceptanceNote: publicAcceptanceNote.value.trim() || undefined },
      publicDecisionKey.value,
    );
    publicOfferDecision.value = "accepted";
  } catch (error) {
    publicOfferError.value = error instanceof Error ? error.message : "Acceptance could not be recorded.";
  } finally {
    publicDecisionBusy.value = false;
  }
}

async function submitPublicOfferRejection(): Promise<void> {
  const reason = publicRejectionReason.value.trim();
  if (reason.length < 3) {
    publicOfferError.value = "Please provide a reason of at least 3 characters.";
    return;
  }
  if (!publicOfferId || !publicOfferToken.value || !publicOffer || publicOffer.value.status !== "issued") return;
  publicDecisionBusy.value = true;
  publicOfferError.value = "";
  if (publicDecisionKind.value !== "rejected") {
    publicDecisionKey.value = createPublicDecisionKey();
    publicDecisionKind.value = "rejected";
  }
  try {
    await api.rejectPublicBookingOffer(
      publicOfferId,
      publicOfferToken.value,
      { reasonCode: "customer_declined", reason, note: publicRejectionNote.value.trim() || undefined },
      publicDecisionKey.value,
    );
    publicOfferDecision.value = "rejected";
  } catch (error) {
    publicOfferError.value = error instanceof Error ? error.message : "Rejection could not be recorded.";
  } finally {
    publicDecisionBusy.value = false;
  }
}

function formatPublicDate(value: string | null | undefined, timezone?: string | null): string {
  if (!value) return "Not specified";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  try {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium", timeStyle: "short",
      ...(timezone ? { timeZone: timezone } : {}),
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
  }
}

onMounted(() => {
  if (isPublicOfferPage) void loadPublicBookingOffer();
  else void refreshSession();
});
</script>

<template>
  <main v-if="isPublicOfferPage" class="public-offer-shell">
    <header class="public-offer-header">
      <a class="brand" href="/" aria-label="Eventor"><span class="brand-mark">E</span><span>EVENTOR <small>BOOKING OFFER</small></span></a>
      <span class="public-security-note">Secure customer link</span>
    </header>
    <section v-if="publicOfferLoading" class="public-offer-panel" aria-live="polite">
      <span class="spinner"></span><p>Loading your offer…</p>
    </section>
    <section v-else-if="publicOfferError && !publicOffer" class="public-offer-panel">
      <p class="eyebrow">BOOKING OFFER</p><h1>Offer unavailable</h1><p class="muted">{{ publicOfferError }}</p>
    </section>
    <template v-else-if="publicOffer">
      <section class="public-offer-hero">
        <p class="eyebrow">BOOKING OFFER · REVISION {{ publicOffer.revisionNumber }}</p>
        <h1>Review your booking offer</h1>
        <p class="muted">Please review the requested arrangements, pricing and cancellation terms before recording your decision.</p>
        <span class="pill" :class="publicOffer.status === 'expired' ? 'pill-warning' : 'pill-success'">{{ publicOffer.status === "expired" ? "Expired" : "Awaiting your decision" }}</span>
      </section>
      <section class="public-offer-panel">
        <div class="public-offer-summary">
          <div><span>Offer valid until</span><strong>{{ formatPublicDate(publicOffer.validUntil) }}</strong></div>
          <div><span>Requested start</span><strong>{{ formatPublicDate(publicOffer.terms.requestedStart, publicOffer.terms.timezone) }}</strong></div>
          <div><span>Requested end</span><strong>{{ formatPublicDate(publicOffer.terms.requestedEnd, publicOffer.terms.timezone) }}</strong></div>
        </div>
        <h2>Venue and resources</h2>
        <div v-if="publicOffer.terms.spaces.length" class="public-offer-list">
          <div v-for="(space, index) in publicOffer.terms.spaces" :key="index" class="public-offer-line">
            <div><strong>{{ space.name }}</strong><span>{{ space.blockKind.replaceAll("_", " ") }} · {{ formatPublicDate(space.startsAt, publicOffer.terms.timezone) }} – {{ formatPublicDate(space.endsAt, publicOffer.terms.timezone) }}</span></div>
            <span v-if="space.requestedCapacity">Capacity {{ space.requestedCapacity }}</span>
          </div>
        </div>
        <p v-else class="muted">No venue-space line items.</p>
        <div v-if="publicOffer.terms.resources.length" class="public-offer-list">
          <div v-for="(resource, index) in publicOffer.terms.resources" :key="index" class="public-offer-line">
            <strong>{{ resource.label }}</strong><span>Quantity {{ resource.requestedQuantity }}</span>
          </div>
        </div>
        <h2>Price breakdown</h2>
        <div class="public-offer-list">
          <div v-for="(line, index) in publicOffer.terms.lineItems" :key="index" class="public-offer-line">
            <div><strong>{{ line.label }}</strong><span>{{ line.quantity }} {{ line.unit }} × {{ line.unitAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }) }} {{ publicOffer.currency }}</span></div>
            <strong>{{ line.lineTotal.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong>
          </div>
          <div v-for="(adjustment, index) in publicOffer.terms.adjustments" :key="'adjustment-' + index" class="public-offer-line">
            <span>{{ adjustment.label }} ({{ adjustment.kind }})</span><strong>{{ adjustment.amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong>
          </div>
          <div class="public-offer-total"><span>Total</span><strong>{{ publicOffer.totalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong></div>
        </div>
        <h2>Cancellation terms</h2>
        <p class="public-cancellation-terms">{{ publicOffer.terms.cancellationTerms || "No cancellation terms were supplied." }}</p>
        <p class="fine-print">Tax basis: {{ publicOffer.terms.taxBasis }} · Tax amount: {{ publicOffer.taxAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</p>
      </section>
      <section v-if="publicOffer.status === 'issued' && !publicOfferDecision" class="public-offer-panel public-offer-actions">
        <div><p class="eyebrow">YOUR DECISION</p><h2>Accept this offer</h2></div>
        <form @submit.prevent="submitPublicOfferAcceptance">
          <label>Your full name<input v-model="publicAcceptanceName" required maxlength="250" autocomplete="name" /></label>
          <label>Optional note<textarea v-model="publicAcceptanceNote" maxlength="1000" rows="3"></textarea></label>
          <button class="button button-primary" type="submit" :disabled="publicDecisionBusy">{{ publicDecisionBusy ? "Recording…" : "Accept offer" }}</button>
        </form>
        <div class="public-reject">
          <h3>Decline this offer</h3>
          <form @submit.prevent="submitPublicOfferRejection">
            <label>Reason<textarea v-model="publicRejectionReason" required minlength="3" maxlength="2000" rows="3"></textarea></label>
            <label>Optional note<textarea v-model="publicRejectionNote" maxlength="1000" rows="2"></textarea></label>
            <button class="button button-quiet" type="submit" :disabled="publicDecisionBusy">{{ publicDecisionBusy ? "Recording…" : "Decline offer" }}</button>
          </form>
        </div>
      </section>
      <section v-else-if="publicOfferDecision" class="public-offer-panel">
        <h2>{{ publicOfferDecision === "accepted" ? "Acceptance recorded" : "Your response was recorded" }}</h2>
        <p class="muted">{{ publicOfferDecision === "accepted" ? "Thank you. Your acceptance has been securely recorded. The organization will complete its internal approval and booking-confirmation steps separately." : "Your decision to decline this offer has been securely recorded." }}</p>
      </section>
      <p v-if="publicOfferError" class="public-offer-error" role="alert">{{ publicOfferError }}</p>
      <footer class="public-offer-footer">This customer link is private. Anyone who has it may be able to act on this offer. Do not forward it.</footer>
    </template>
  </main>
  <main v-else class="app-shell">
    <header class="topbar">
      <a class="brand" href="/" aria-label="Eventor staff home">
        <span class="brand-mark">E</span>
        <span>EVENTOR <small>{{ $t("app.staffWorkspace") }}</small></span>
      </a>
      <label class="locale-picker">Language <select v-model="locale"><option v-for="option in localeOptions" :key="option.value" :value="option.value">{{ option.label }}</option></select></label>
      <div v-if="principal" class="account">
        <div class="account-copy">
          <strong>{{ selectedOrganization }}</strong>
          <span>{{ $t("app.authenticatedSession") }}</span>
        </div>
        <button class="button button-quiet" :disabled="busy" @click="signOut">{{ $t("app.signOut") }}</button>
      </div>
    </header>

    <section v-if="loadingSession" class="loading-panel" aria-live="polite">
      <span class="spinner"></span> {{ $t("app.checkingSession") }}
    </section>

    <section v-else-if="!principal" class="login-layout">
      <div class="intro-panel">
        <p class="eyebrow">{{ $t("auth.platformEyebrow") }}</p>
        <h1>{{ $t("auth.headline") }}</h1>
        <p class="muted">{{ $t("auth.description") }}</p>
        <div class="security-note"><span class="status-dot"></span> {{ $t("auth.security") }}</div>
      </div>
      <form class="panel login-panel" @submit.prevent="signIn">
        <p class="eyebrow">{{ $t("auth.staffAccess") }}</p>
        <h2>{{ $t("auth.signIn") }}</h2>
        <label>{{ $t("auth.email") }}<input v-model="loginForm.email" type="email" autocomplete="username" required maxlength="320" /></label>
        <label>{{ $t("auth.organization") }}<input v-model="loginForm.organizationSlug" autocomplete="organization" required minlength="2" maxlength="80" /></label>
        <label>{{ $t("auth.password") }}<input v-model="loginForm.password" type="password" autocomplete="current-password" required minlength="12" maxlength="1024" /></label>
        <button class="button button-primary full-width" type="submit" :disabled="busy">
          {{ busy ? $t("auth.signingIn") : $t("auth.signInSecurely") }}
        </button>
        <p class="fine-print">{{ $t("auth.passwordNote") }}</p>
      </form>
    </section>

    <template v-else>
      <section class="welcome-row">
        <div>
          <p class="eyebrow">{{ $t("workspace.organization") }}</p>
          <h1>{{ $t("workspace.overview") }}</h1>
          <p class="muted">{{ $t("workspace.description") }}</p>
        </div>
        <div class="session-chip"><span class="status-dot"></span> {{ $t("workspace.active") }}</div>
      </section>

      <nav class="tabs" aria-label="Staff workspace sections">
        <button :class="{ active: activeTab === 'delivery' }" @click="activeTab = 'delivery'">{{ $t("navigation.delivery") }}</button>
        <button :class="{ active: activeTab === 'campaign' }" @click="activeTab = 'campaign'">{{ $t("navigation.campaigns") }}</button>
        <button :class="{ active: activeTab === 'inquiries' }" @click="openInquiryWorkspace">{{ $t("navigation.inquiries") }}</button>
        <button :class="{ active: activeTab === 'approvals' }" @click="openBookingApprovalPolicies">{{ $t("navigation.approvals") }}</button>
        <button :class="{ active: activeTab === 'prices' }" @click="openBookingPriceLists">{{ $t("navigation.prices") }}</button>
        <button :class="{ active: activeTab === 'cancellations' }" @click="openBookingCancellationPolicies">{{ $t("navigation.cancellations") }}</button>
        <button :class="{ active: activeTab === 'taxes' }" @click="openBookingTaxProfiles">{{ $t("navigation.taxes") }}</button>
      </nav>

      <EmailDeliveryView v-if="activeTab === 'delivery'" :workspace="emailDeliveryWorkspace" />

      <BookingInquiryView
        v-else-if="activeTab === 'inquiries'"
        :workspace="{ ...bookingInquiryState, principal, busy, canReadBookingDraft }"
        @open-booking-draft="openBookingDraft"
      >
        <template #booking-draft-editor>
            <section v-if="bookingDraftDetail && bookingDraftEditorOpen" class="inquiry-card booking-draft-editor">
              <div class="inquiry-card-heading">
                <div>
                  <h4>Booking draft · {{ bookingDraftDetail.draftId.slice(0, 8) }}</h4>
                  <p class="fine-print">Current revision {{ bookingDraftDetail.currentRevisionNumber }} · {{ bookingDraftDetail.status }}</p>
                </div>
                <button class="button button-quiet" type="button" :disabled="busy" @click="bookingDraftEditorOpen = false">Close</button>
              </div>

              <div v-if="bookingDraftDetail.revisionHistory.length" class="draft-revision-history">
                <h5>Revision history</h5>
                <ol class="history-list">
                  <li v-for="history in bookingDraftDetail.revisionHistory" :key="history.revisionId">
                    <strong>Revision {{ history.revisionNumber }}</strong>
                    <span>{{ history.changeReason ?? "No change reason recorded" }}</span>
                    <small>{{ history.createdByDisplayName }} · {{ formatInquiryDate(history.createdAt) }}</small>
                  </li>
                </ol>
              </div>

              <template v-if="canManageBookingDraft">
                <p class="fine-print">
                  Saving creates a new immutable revision. The previous revision is retained. If resource or space holds exist
                  against the current revision, they must expire or be released before it can be revised.
                </p>
                <form class="draft-revision-form" @submit.prevent="saveBookingDraftRevision">
                  <label>Values snapshot (JSON)
                    <textarea v-model="bookingDraftValuesJson" rows="8" spellcheck="false"></textarea>
                  </label>
                  <div class="field-grid">
                    <label>Requested start (ISO 8601)
                      <input v-model="bookingDraftRequestedStart" type="text" maxlength="80" placeholder="2027-01-18T09:00:00+01:00" />
                    </label>
                    <label>Requested end (ISO 8601)
                      <input v-model="bookingDraftRequestedEnd" type="text" maxlength="80" placeholder="2027-01-18T13:00:00+01:00" />
                    </label>
                    <label>Timezone
                      <input v-model="bookingDraftTimezone" type="text" maxlength="80" required />
                    </label>
                  </div>
                  <label>Space lines (JSON array)
                    <textarea v-model="bookingDraftSpaceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>Resource lines (JSON array)
                    <textarea v-model="bookingDraftResourceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>Change reason
                    <textarea v-model="bookingDraftChangeReason" rows="2" maxlength="2000" required placeholder="Explain why this revision is being created…"></textarea>
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || bookingDraftChangeReason.trim().length < 3">
                      Save as revision {{ bookingDraftDetail.currentRevisionNumber + 1 }}
                    </button>
                    <span class="fine-print">Revision {{ bookingDraftDetail.currentRevisionNumber }} stays unchanged.</span>
                  </div>
                </form>
              </template>
              <p v-else class="fine-print">This draft is read-only for your current membership, or is no longer editable in draft status.</p>
            </section>
        </template>
        <template #booking-offer-workspace>
            <section v-if="bookingDraftDetail" class="inquiry-card booking-offer-workspace">
              <div class="inquiry-card-heading">
                <div>
                  <h4>Commercial offer and booking confirmation</h4>
                  <p class="fine-print">Customer acceptance, internal approvals and booking confirmation are independent decisions. Capacity is finalized only by the confirmation command.</p>
                </div>
                <span class="pill pill-neutral">Explicit actions</span>
              </div>

              <div class="offer-load-row">
                <label>Offer UUID
                  <input v-model="bookingOfferIdInput" type="text" maxlength="36" placeholder="Load an existing offer for this draft" />
                </label>
                <button class="button button-secondary" type="button" :disabled="busy || !bookingOfferIdInput.trim()" @click="loadBookingOffer">Load offer</button>
              </div>

              <div v-if="canManageBookingOffer" class="offer-preparation">
                <h5>{{ bookingOffer ? "Prepare successor offer revision" : "Prepare first offer revision" }}</h5>
                <p class="fine-print">Use IDs of already published and effective organization configuration. Prices are calculated from the selected price-list revision and item codes by the server. Eventor does not supply default prices, cancellation terms, approval thresholds or tax rates.</p>
                <form class="draft-revision-form" @submit.prevent="saveBookingOfferRevision">
                  <div class="field-grid">
                    <label>Price-list revision UUID
                      <input v-model="bookingOfferCreateForm.priceListRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Cancellation-policy revision UUID
                      <input v-model="bookingOfferCreateForm.cancellationPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Approval-policy revision UUID
                      <input v-model="bookingOfferCreateForm.approvalPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Currency (ISO 4217)
                      <input v-model="bookingOfferCreateForm.currency" type="text" required maxlength="3" placeholder="e.g. BAM" />
                    </label>
                    <label>Tax treatment
                      <select v-model="bookingOfferCreateForm.taxBasis" required>
                        <option value="">Choose tax treatment…</option>
                        <option value="inclusive">Tax inclusive</option>
                        <option value="exclusive">Tax exclusive</option>
                        <option value="not_applicable">Not applicable</option>
                        <option value="to_be_confirmed">To be confirmed</option>
                      </select>
                    </label>
                    <label>Offer valid until (your local time)
                      <input v-model="bookingOfferValidUntil" type="datetime-local" required />
                    </label>
                    <label>Tax amount (zero = calculate from selected tax profile; positive = manual override)
                      <input v-model="bookingOfferTaxAmount" type="number" min="0" step="0.0001" required />
                    </label>
                  </div>
                  <label>Price-list line items (JSON array)
                    <textarea v-model="bookingOfferLineItemsJson" rows="5" spellcheck="false" placeholder='[{"itemCode":"published-item-code","quantity":1}]'></textarea>
                  </label>
                  <label>Manual adjustments (JSON array)
                    <textarea v-model="bookingOfferAdjustmentsJson" rows="5" spellcheck="false" placeholder='[{"code":"adjustment-code","label":"Reasoned adjustment","kind":"discount","amount":0.01,"allocationMethod":"proportional_to_lines"}]'></textarea>
                    <small>When the selected price list has a tax profile, every adjustment must explicitly use allocationMethod "tax_code" with a taxCode, "proportional_to_lines" (allocated by the priced lines' tax-code mix), or "not_applicable" for a not-applicable profile. Eventor never guesses tax treatment. Without a selected profile, the legacy manual tax workflow remains available.</small>
                  </label>
                  <label>Internal reason / tax audit reason
                    <textarea v-model="bookingOfferInternalReason" rows="2" maxlength="2000" required placeholder="Explain manual terms, especially any tax amount or adjustment…"></textarea>
                  </label>
                  <label v-if="bookingOffer" class="check-row">
                    <input v-model="bookingOfferSupersedeCurrent" type="checkbox" />
                    Request superseding the current offer (server validates eligibility)
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || !bookingOfferValidUntil || !bookingOfferTaxAmount.trim()">
                      {{ bookingOffer ? "Create successor revision" : "Prepare offer" }}
                    </button>
                  </div>
                </form>
              </div>
              <p v-else class="fine-print">Your membership cannot prepare or revise offer terms. The server still enforces the separate commercial permissions on each command.</p>

              <template v-if="bookingOffer">
                <div class="offer-summary-grid">
                  <div class="metric"><span>Offer status</span><strong>{{ bookingOffer.status }}</strong><small>Offer {{ bookingOffer.offerId }}</small></div>
                  <div class="metric"><span>Offer revision</span><strong>{{ bookingOffer.currentRevision.revisionNumber }}</strong><small>{{ bookingOffer.currentRevision.state }}</small></div>
                  <div class="metric"><span>Subtotal</span><strong>{{ formatBookingMoney(bookingOffer.currentRevision.subtotal, bookingOffer.currentRevision.currency) }}</strong></div>
                  <div class="metric"><span>Total</span><strong>{{ formatBookingMoney(bookingOffer.currentRevision.totalAmount, bookingOffer.currentRevision.currency) }}</strong><small>Tax {{ formatBookingMoney(bookingOffer.currentRevision.taxAmount, bookingOffer.currentRevision.currency) }}</small></div>
                </div>
                <dl class="offer-reference-list">
                  <dt>Draft revision</dt><dd class="mono">{{ bookingOffer.currentRevision.draftRevisionId }}</dd>
                  <dt>Price-list revision</dt><dd class="mono">{{ bookingOffer.currentRevision.priceListRevisionId }}</dd>
                  <dt>Cancellation policy</dt><dd class="mono">{{ bookingOffer.currentRevision.cancellationPolicyRevisionId }}</dd>
                  <dt>Approval policy</dt><dd class="mono">{{ bookingOffer.currentRevision.approvalPolicyRevisionId }}</dd>
                  <dt>Valid until</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.validUntil) }}</dd>
                  <dt>Issued</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.issuedAt) }}</dd>
                  <dt>Customer accepted</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.acceptedAt) }}</dd>
                </dl>
                <details class="offer-terms-details">
                  <summary>Inspect immutable customer terms snapshot</summary>
                  <pre>{{ JSON.stringify(bookingOffer.currentRevision.terms, null, 2) }}</pre>
                </details>

                <div class="offer-command-row">
                  <button v-if="bookingOffer.currentRevision.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="issueBookingOffer">Issue offer to customer</button>
                  <span v-else class="pill pill-neutral">This revision is {{ bookingOffer.currentRevision.state }}</span>
                  <button class="button button-quiet" type="button" :disabled="busy" @click="loadBookingOffer">Refresh offer</button>
                </div>

                <div v-if="bookingOfferAcceptanceToken" class="offer-capability-box">
                  <strong>Customer link — copy now</strong>
                  <p class="fine-print">This is a bearer secret. It is shown only in this session and is not stored in the database as plaintext. Email delivery is a separate, explicit action and uses the source inquiry email address.</p>
                  <input :value="bookingOfferAcceptanceToken" type="password" readonly autocomplete="off" />
                  <div class="offer-command-row"><button class="button button-secondary" type="button" @click="copyBookingOfferCapability">Copy customer link</button><button v-if="bookingOffer.currentRevision.state === 'issued'" class="button button-secondary" type="button" :disabled="busy" @click="emailBookingOffer">Queue offer email</button></div>
                </div>

                <section class="offer-approval-list offer-email-history">
                  <div class="inquiry-card-heading">
                    <div>
                      <h5>Offer email delivery history</h5>
                      <p class="fine-print">SMTP acceptance is not proof of inbox delivery. Uncertain submissions are never automatically resent.</p>
                    </div>
                    <button class="button button-quiet" type="button" :disabled="busy" @click="refreshBookingOfferEmailData">Refresh delivery status</button>
                  </div>
                  <div class="metric-grid compact-metrics">
                    <div class="metric"><span>Queued</span><strong>{{ bookingOfferEmailMeta?.counts.queued ?? 0 }}</strong></div>
                    <div class="metric"><span>Sending</span><strong>{{ bookingOfferEmailMeta?.counts.sending ?? 0 }}</strong></div>
                    <div class="metric"><span>SMTP accepted</span><strong>{{ bookingOfferEmailMeta?.counts.sent ?? 0 }}</strong></div>
                    <div class="metric"><span>Uncertain</span><strong>{{ bookingOfferEmailMeta?.counts.uncertain ?? 0 }}</strong></div>
                    <div class="metric"><span>Failed</span><strong>{{ bookingOfferEmailMeta?.counts.failed ?? 0 }}</strong></div>
                  </div>
                  <div class="delivery-toolbar">
                    <label>Filter email status
                      <select v-model="bookingOfferEmailStatusFilter" @change="bookingOfferEmailOffset = 0; refreshBookingOfferEmailData()">
                        <option value="">All statuses</option>
                        <option v-for="status in ['queued','sending','sent','failed','uncertain']" :key="status" :value="status">{{ status }}</option>
                      </select>
                    </label>
                  </div>
                  <div v-if="bookingOfferEmailDeliveries.length" class="delivery-attempt-list">
                    <article v-for="delivery in bookingOfferEmailDeliveries" :key="delivery.deliveryId" class="delivery-attempt">
                      <div class="delivery-attempt-heading">
                        <div>
                          <strong>Offer revision · {{ delivery.offerRevisionId }}</strong>
                          <span class="mono">Delivery {{ delivery.deliveryId }}</span>
                        </div>
                        <span class="pill" :class="delivery.status === 'sent' ? 'pill-success' : delivery.status === 'failed' ? 'pill-danger' : delivery.status === 'uncertain' ? 'pill-warning' : 'pill-neutral'">{{ delivery.status }}</span>
                      </div>
                      <div class="delivery-meta">
                        <span>SMTP attempts: {{ delivery.attemptCount }}</span>
                        <span>Manual retries: {{ delivery.manualRetryCount }} / 1</span>
                        <span>Queued: {{ formatInquiryDate(delivery.createdAt) }}</span>
                        <span>Last update: {{ formatInquiryDate(delivery.updatedAt) }}</span>
                        <span v-if="delivery.status === 'queued'">Next attempt: {{ formatInquiryDate(delivery.nextAttemptAt) }}</span>
                        <span v-if="delivery.sentAt">SMTP accepted: {{ formatInquiryDate(delivery.sentAt) }}</span>
                        <span v-if="delivery.lastFailureCode">Failure: {{ delivery.lastFailureCode }}</span>
                        <span v-if="delivery.lastOperatorResolution">Operator resolution: {{ delivery.lastOperatorResolution.replaceAll("_", " ") }}</span>
                        <span v-if="delivery.lastOperatorReason">Audit reason: {{ delivery.lastOperatorReason }}</span>
                        <span v-if="delivery.lastOperatorAt">Reconciled: {{ formatInquiryDate(delivery.lastOperatorAt) }}</span>
                      </div>
                      <div v-if="delivery.canReconcile" class="operator-controls">
                        <label>Verified SMTP outcome
                          <select v-model="bookingOfferEmailResolution[delivery.deliveryId]">
                            <option disabled value="">Choose verified outcome…</option>
                            <option value="confirmed_sent">SMTP server accepted the message</option>
                            <option value="confirmed_not_sent">SMTP server did not accept the message</option>
                          </select>
                        </label>
                        <label v-if="bookingOfferEmailResolution[delivery.deliveryId] === 'confirmed_sent'">Provider message reference (optional)
                          <input v-model="bookingOfferEmailReference[delivery.deliveryId]" maxlength="998" placeholder="Message-ID or SMTP queue reference" />
                        </label>
                        <label>Audit reason
                          <textarea v-model="bookingOfferEmailReason[delivery.deliveryId]" rows="2" maxlength="1000" placeholder="How was the SMTP outcome verified?"></textarea>
                        </label>
                        <button class="button button-secondary" type="button" :disabled="busy" @click="reconcileBookingOfferEmail(delivery)">Record reconciliation</button>
                      </div>
                      <div v-if="delivery.canRetry" class="operator-controls">
                        <p class="fine-print">The previous submission was explicitly recorded as not accepted. Only one manual retry is permitted for this delivery.</p>
                        <label>Retry reason
                          <textarea v-model="bookingOfferEmailRetryReason[delivery.deliveryId]" rows="2" maxlength="1000" placeholder="Explain why retrying is safe…"></textarea>
                        </label>
                        <button class="button button-danger" type="button" :disabled="busy" @click="retryBookingOfferEmail(delivery)">Authorise one-time retry</button>
                      </div>
                    </article>
                  </div>
                  <p v-else class="muted">No offer email deliveries match this filter.</p>
                  <div class="pagination">
                    <button class="button button-quiet" type="button" :disabled="busy || bookingOfferEmailOffset === 0" @click="bookingOfferEmailOffset = Math.max(0, bookingOfferEmailOffset - 25); refreshBookingOfferEmailData()">Previous</button>
                    <span>{{ bookingOfferEmailMeta?.totalCount ?? 0 }} deliveries</span>
                    <button class="button button-quiet" type="button" :disabled="busy || !bookingOfferEmailMeta || bookingOfferEmailOffset + 25 >= bookingOfferEmailMeta.totalCount" @click="bookingOfferEmailOffset += 25; refreshBookingOfferEmailData()">Next</button>
                  </div>
                  <p class="fine-print">Contact addresses and encrypted payloads are never exposed in this history. Reconciliation changes records only; it never sends an email.</p>
                </section>

                <div v-if="bookingOfferApprovalStatus" class="offer-approval-list">
                  <h5>Internal approval requirements</h5>
                  <p v-if="!bookingOfferApprovalStatus.requirements.length" class="muted">No approval rules matched this offer revision. Customer acceptance and explicit booking confirmation are still required.</p>
                  <article v-for="requirement in bookingOfferApprovalStatus.requirements" :key="requirement.ruleCode" class="offer-approval-item">
                    <div class="inquiry-card-heading">
                      <div>
                        <strong>{{ requirement.ruleCode }}</strong>
                        <p class="fine-print">{{ requirement.approvedCount }} / {{ requirement.requiredApprovals }} approvals · separation of duties {{ requirement.separationOfDuties ? "required" : "not required" }}</p>
                      </div>
                      <span class="pill" :class="requirement.blocked ? 'pill-danger' : requirement.approvedCount >= requirement.requiredApprovals ? 'pill-success' : 'pill-warning'">
                        {{ requirement.blocked ? "Blocked" : requirement.approvedCount >= requirement.requiredApprovals ? "Satisfied" : "Pending" }}
                      </span>
                    </div>
                    <ol v-if="requirement.decisions.length" class="history-list">
                      <li v-for="(decision, index) in requirement.decisions" :key="decision.membershipId + '-' + index">
                        <strong>{{ decision.decision.replaceAll("_", " ") }}</strong>
                        <span>{{ decision.reason }}</span>
                        <small>{{ decision.membershipId }} · {{ formatInquiryDate(decision.decidedAt) }}</small>
                      </li>
                    </ol>
                    <div v-if="canDecideBookingOfferRequirement(requirement)" class="operator-controls offer-approval-controls">
                      <label>Decision
                        <select v-model="bookingOfferApprovalDecisions[requirement.ruleCode]">
                          <option value="approved">Approve</option>
                          <option value="rejected">Reject</option>
                          <option value="returned_for_changes">Return for changes</option>
                        </select>
                      </label>
                      <label>Reason
                        <textarea v-model="bookingOfferApprovalReasons[requirement.ruleCode]" rows="2" maxlength="2000" placeholder="Record the decision rationale…"></textarea>
                      </label>
                      <button class="button button-secondary" type="button" :disabled="busy || (bookingOfferApprovalReasons[requirement.ruleCode] ?? '').trim().length < 3" @click="decideBookingOfferApproval(requirement)">Record decision</button>
                    </div>
                  </article>
                </div>

                <div v-if="canConfirmBookingOffer" class="offer-confirm-box">
                  <h5>Confirm accepted booking</h5>
                  <p class="fine-print">The exact draft revision has an accepted customer offer and all pinned approvals are satisfied. Final space and resource availability is rechecked transactionally on confirmation.</p>
                  <label>Booking confirmation reason
                    <textarea v-model="bookingOfferConfirmationReason" rows="2" maxlength="2000" placeholder="Record why this booking is being confirmed…"></textarea>
                  </label>
                  <button class="button button-primary" type="button" :disabled="busy || bookingOfferConfirmationReason.trim().length < 3" @click="confirmBookingFromAcceptedOffer">Confirm booking</button>
                </div>
                <p v-else-if="bookingOffer.currentRevision.state === 'accepted'" class="fine-print text-warning">Confirmation is not available yet. Check that this accepted offer targets the current draft revision and that every approval requirement is satisfied.</p>

                <div v-if="bookingOffer.revisionHistory.length" class="draft-revision-history">
                  <h5>Offer revision history</h5>
                  <ol class="history-list">
                    <li v-for="history in bookingOffer.revisionHistory" :key="history.offerRevisionId">
                      <strong>Offer revision {{ history.revisionNumber }} · {{ history.state }}</strong>
                      <span>Draft revision {{ history.draftRevisionId }}</span>
                      <small>{{ formatInquiryDate(history.createdAt) }} · issued {{ formatInquiryDate(history.issuedAt) }}</small>
                    </li>
                  </ol>
                </div>
              </template>
            </section>
        </template>
      </BookingInquiryView>


      <BookingPriceListsView v-else-if="activeTab === 'prices'" :workspace="{ ...bookingPriceListState, busy }" />

      <BookingApprovalPoliciesView v-else-if="activeTab === 'approvals'" :workspace="{ ...bookingApprovalPolicyState, busy }" />

      <BookingTaxProfilesView v-else-if="activeTab === 'taxes'" :workspace="{ ...bookingTaxProfileState, busy }" />

      <BookingCancellationPoliciesView v-else-if="activeTab === 'cancellations'" :workspace="{ ...bookingCancellationPolicyState, busy }" />

      <CampaignWorkspaceView v-else :workspace="campaignWorkspace" />
    </template>

    <div v-if="pageError" class="message message-error" role="alert">{{ pageError }}</div>
    <div v-if="pageNotice" class="message message-success" role="status">{{ pageNotice }}</div>

    <footer class="footer"><span>EVENTOR · STAFF WORKSPACE</span><span>Self-hosted · Organization-scoped · API-authoritative</span></footer>
  </main>
</template>
