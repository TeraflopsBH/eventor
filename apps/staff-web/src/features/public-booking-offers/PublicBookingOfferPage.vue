<script setup lang="ts">
import { onMounted, ref } from "vue";
import { api, ApiError, type PublicBookingOffer } from "../../api";

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


onMounted(() => { void loadPublicBookingOffer(); });
</script>

<template>
<main class="public-offer-shell">
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
</template>
