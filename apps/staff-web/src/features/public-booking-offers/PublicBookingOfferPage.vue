<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { setLocale } from "../../i18n";
import { api, ApiError, type PublicBookingOffer } from "../../api";

const { t, locale } = useI18n();

function changePublicLocale(event: Event): void {
  const value = (event.target as HTMLSelectElement).value;
  setLocale(value);
}

const publicOfferMatch = window.location.pathname.match(/^\/offers\/([0-9a-fA-F-]{36})\/?$/);
const publicOfferId = publicOfferMatch?.[1] ?? "";
const publicOfferToken = ref(new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "");
const publicOffer = ref<PublicBookingOffer | null>(null);
const publicOfferLoading = ref(true);
const publicOfferError = ref("");
const publicOfferDecision = ref<"accepted" | "rejected" | null>(null);
const publicAcceptanceName = ref("");
const publicAcceptanceNote = ref("");
const publicRejectionReason = ref("");
const publicRejectionNote = ref("");
const publicDecisionBusy = ref(false);
const publicDecisionKey = ref("");
const publicDecisionKind = ref<"accepted" | "rejected" | null>(null);

function createPublicDecisionKey(): string {
  return globalThis.crypto.randomUUID();
}

async function loadPublicBookingOffer(): Promise<void> {
  publicOfferLoading.value = true;
  publicOfferError.value = "";
  if (!publicOfferId || !/^[0-9a-fA-F-]{36}$/.test(publicOfferId)) {
    publicOfferError.value = t("publicOffer.invalidLink");
    publicOfferLoading.value = false;
    return;
  }
  if (!/^[A-Za-z0-9_-]{43}$/.test(publicOfferToken.value)) {
    publicOfferError.value = t("publicOffer.incompleteLink");
    publicOfferLoading.value = false;
    return;
  }
  try {
    const result = await api.getPublicBookingOffer(publicOfferId, publicOfferToken.value);
    publicOffer.value = result.data;
  } catch (error) {
    publicOfferError.value = error instanceof ApiError && error.status === 410
      ? t("publicOffer.expired")
      : error instanceof Error ? error.message : t("publicOffer.couldNotLoad");
  } finally {
    publicOfferLoading.value = false;
  }
}

async function submitPublicOfferAcceptance(): Promise<void> {
  const name = publicAcceptanceName.value.trim();
  if (!name) {
    publicOfferError.value = t("publicOffer.enterName");
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
    publicOfferError.value = error instanceof Error ? error.message : t("publicOffer.acceptanceNotRecorded");
  } finally {
    publicDecisionBusy.value = false;
  }
}

async function submitPublicOfferRejection(): Promise<void> {
  const reason = publicRejectionReason.value.trim();
  if (reason.length < 3) {
    publicOfferError.value = t("publicOffer.rejectionReasonMin");
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
    publicOfferError.value = error instanceof Error ? error.message : t("publicOffer.rejectionNotRecorded");
  } finally {
    publicDecisionBusy.value = false;
  }
}

function formatPublicDate(value: string | null | undefined, timezone?: string | null): string {
  if (!value) return t("publicOffer.notSpecified");
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  try {
    return new Intl.DateTimeFormat(locale.value, {
      dateStyle: "medium", timeStyle: "short",
      ...(timezone ? { timeZone: timezone } : {}),
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(date);
  }
}


onMounted(() => { void loadPublicBookingOffer(); });
</script>

<template>
<main class="public-offer-shell">
    <header class="public-offer-header">
      <a class="brand" href="/" aria-label="Eventor"><span class="brand-mark">E</span><span>EVENTOR <small>{{$t('publicOffer.bookingOffer')}}</small></span></a>
      <label class="public-language-choice">{{ t("publicOffer.language") }} <select :value="locale" @change="changePublicLocale"><option value="en">{{ t("publicOffer.english") }}</option><option value="bs-BA">{{ t("publicOffer.bosnian") }}</option></select></label>
      <span class="public-security-note">{{$t('publicOffer.secureLink')}}</span>
    </header>
    <section v-if="publicOfferLoading" class="public-offer-panel" aria-live="polite">
      <span class="spinner"></span><p>{{$t('publicOffer.loading')}}</p>
    </section>
    <section v-else-if="publicOfferError && !publicOffer" class="public-offer-panel">
      <p class="eyebrow">{{$t('publicOffer.bookingOffer')}}</p><h1>{{$t('publicOffer.unavailable')}}</h1><p class="muted">{{ publicOfferError }}</p>
    </section>
    <template v-else-if="publicOffer">
      <section class="public-offer-hero">
        <p class="eyebrow">{{ t("publicOffer.bookingOffer") }} · {{ t("publicOffer.revision") }} {{ publicOffer.revisionNumber }}</p>
        <h1>{{$t('publicOffer.reviewTitle')}}</h1>
        <p class="muted">{{$t('publicOffer.reviewInstructions')}}</p>
        <span class="pill" :class="publicOffer.status === 'expired' ? 'pill-warning' : 'pill-success'">{{ publicOffer.status === "expired" ? t("publicOffer.expired") : t("publicOffer.awaitingDecision") }}</span>
      </section>
      <section class="public-offer-panel">
        <div class="public-offer-summary">
          <div><span>{{$t('publicOffer.validUntil')}}</span><strong>{{ formatPublicDate(publicOffer.validUntil) }}</strong></div>
          <div><span>{{$t('publicOffer.requestedStart')}}</span><strong>{{ formatPublicDate(publicOffer.terms.requestedStart, publicOffer.terms.timezone) }}</strong></div>
          <div><span>{{$t('publicOffer.requestedEnd')}}</span><strong>{{ formatPublicDate(publicOffer.terms.requestedEnd, publicOffer.terms.timezone) }}</strong></div>
        </div>
        <h2>{{$t('publicOffer.venueResources')}}</h2>
        <div v-if="publicOffer.terms.spaces.length" class="public-offer-list">
          <div v-for="(space, index) in publicOffer.terms.spaces" :key="index" class="public-offer-line">
            <div><strong>{{ space.name }}</strong><span>{{ space.blockKind.replaceAll("_", " ") }} · {{ formatPublicDate(space.startsAt, publicOffer.terms.timezone) }} – {{ formatPublicDate(space.endsAt, publicOffer.terms.timezone) }}</span></div>
            <span v-if="space.requestedCapacity">{{ t("publicOffer.capacity") }} {{ space.requestedCapacity }}</span>
          </div>
        </div>
        <p v-else class="muted">{{$t('publicOffer.noVenueItems')}}</p>
        <div v-if="publicOffer.terms.resources.length" class="public-offer-list">
          <div v-for="(resource, index) in publicOffer.terms.resources" :key="index" class="public-offer-line">
            <strong>{{ resource.label }}</strong><span>{{ t("publicOffer.quantity") }} {{ resource.requestedQuantity }}</span>
          </div>
        </div>
        <h2>{{$t('publicOffer.priceBreakdown')}}</h2>
        <div class="public-offer-list">
          <div v-for="(line, index) in publicOffer.terms.lineItems" :key="index" class="public-offer-line">
            <div><strong>{{ line.label }}</strong><span>{{ line.quantity }} {{ line.unit }} × {{ line.unitAmount.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 4 }) }} {{ publicOffer.currency }}</span></div>
            <strong>{{ line.lineTotal.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong>
          </div>
          <div v-for="(adjustment, index) in publicOffer.terms.adjustments" :key="'adjustment-' + index" class="public-offer-line">
            <span>{{ adjustment.label }} ({{ adjustment.kind }})</span><strong>{{ adjustment.amount.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong>
          </div>
          <div class="public-offer-total"><span>{{$t('publicOffer.total')}}</span><strong>{{ publicOffer.totalAmount.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</strong></div>
        </div>
        <h2>{{$t('publicOffer.cancellationTerms')}}</h2>
        <p class="public-cancellation-terms">{{ publicOffer.terms.cancellationTerms || t("publicOffer.noCancellationTerms") }}</p>
        <p class="fine-print">{{ t("publicOffer.taxBasis") }}: {{ publicOffer.terms.taxBasis }} · {{ t("publicOffer.taxAmount") }}: {{ publicOffer.taxAmount.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }} {{ publicOffer.currency }}</p>
      </section>
      <section v-if="publicOffer.status === 'issued' && !publicOfferDecision" class="public-offer-panel public-offer-actions">
        <div><p class="eyebrow">{{$t('publicOffer.yourDecision')}}</p><h2>{{$t('publicOffer.acceptThisOffer')}}</h2></div>
        <form @submit.prevent="submitPublicOfferAcceptance">
          <label>{{$t('publicOffer.fullName')}}<input v-model="publicAcceptanceName" required maxlength="250" autocomplete="name" /></label>
          <label>{{$t('publicOffer.optionalNote')}}<textarea v-model="publicAcceptanceNote" maxlength="1000" rows="3"></textarea></label>
          <button class="button button-primary" type="submit" :disabled="publicDecisionBusy">{{ publicDecisionBusy ? t("publicOffer.recording") : t("publicOffer.acceptOffer") }}</button>
        </form>
        <div class="public-reject">
          <h3>{{$t('publicOffer.declineThisOffer')}}</h3>
          <form @submit.prevent="submitPublicOfferRejection">
            <label>{{$t('publicOffer.reason')}}<textarea v-model="publicRejectionReason" required minlength="3" maxlength="2000" rows="3"></textarea></label>
            <label>{{$t('publicOffer.optionalNote')}}<textarea v-model="publicRejectionNote" maxlength="1000" rows="2"></textarea></label>
            <button class="button button-quiet" type="submit" :disabled="publicDecisionBusy">{{ publicDecisionBusy ? t("publicOffer.recording") : t("publicOffer.declineOffer") }}</button>
          </form>
        </div>
      </section>
      <section v-else-if="publicOfferDecision" class="public-offer-panel">
        <h2>{{ publicOfferDecision === "accepted" ? t("publicOffer.acceptanceRecorded") : t("publicOffer.responseRecorded") }}</h2>
        <p class="muted">{{ publicOfferDecision === "accepted" ? t("publicOffer.thanksAcceptance") : t("publicOffer.thanksRejection") }}</p>
      </section>
      <p v-if="publicOfferError" class="public-offer-error" role="alert">{{ publicOfferError }}</p>
      <footer class="public-offer-footer">{{$t('publicOffer.privateLinkFooter')}}</footer>
    </template>
</main>
</template>
