<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type ExternalBookingActionContext, type ExternalBookingCancellationStatus, type ExternalBookingCancellationSubmission } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { setLocale } from "../../i18n";

const props = defineProps<{ mode: "request" | "status" }>();
const { locale } = useI18n();
const hash = new URLSearchParams(window.location.hash.slice(1));
const token = ref(hash.get("token") ?? "");
const requestId = ref(hash.get("requestId") ?? "");
if (/^[A-Za-z0-9_-]{43}$/.test(token.value)) {
  window.history.replaceState(window.history.state, "", window.location.pathname);
}
const loading = ref(true);
const busy = ref(false);
const error = ref("");
const context = ref<ExternalBookingActionContext | null>(null);
const status = ref<ExternalBookingCancellationStatus | null>(null);
const submission = ref<ExternalBookingCancellationSubmission | null>(null);
const explanation = ref("");
const submissionKey = ref("");
const submissionSignature = computed(() => explanation.value.trim());
watch(submissionSignature, () => { submissionKey.value = ""; });
const existingRequestStatus = computed(() => context.value?.latestCancellationRequest?.status ?? "");
const hasOpenRequest = computed(() => {
  const existing = context.value?.latestCancellationRequest;
  return Boolean(existing && ["submitted", "under_review", "approved"].includes(existing.status));
});
const statusLink = computed(() => submission.value
  ? `${window.location.origin}/booking/cancellation-status#token=${encodeURIComponent(submission.value.statusToken)}&requestId=${encodeURIComponent(submission.value.requestId)}`
  : "");

const bs = computed(() => locale.value === "bs-BA");
const labels = computed(() => bs.value ? {
  title: "Zahtjev za otkazivanje rezervacije",
  statusTitle: "Status zahtjeva za otkazivanje",
  loading: "Učitavanje sigurne veze…",
  unavailable: "Veza nije dostupna",
  secure: "Sigurna lična veza",
  invalid: "Veza nije potpuna ili je neispravna.",
  retry: "Pokušajte ponovo.",
  booking: "Rezervacija",
  terms: "Uslovi otkazivanja",
  explanation: "Obrazloženje (opcionalno)",
  explanationPlaceholder: "Navedite dodatne informacije koje mogu pomoći pri razmatranju zahtjeva.",
  submit: "Pošalji zahtjev za otkazivanje",
  submitting: "Slanje zahtjeva…",
  submitted: "Zahtjev je uspješno evidentiran.",
  saveLink: "Sačuvajte ovu sigurnu vezu za praćenje statusa zahtjeva:",
  copy: "Kopiraj vezu",
  copied: "Veza je kopirana.",
  status: "Status",
  requested: "Podneseno",
  resolved: "Riješeno",
  requestOnly: "Vaš zahtjev će pregledati nadležna služba. Slanje zahtjeva ne otkazuje automatski rezervaciju.",
  existingRequest: "Za ovu rezervaciju već postoji otvoren zahtjev za otkazivanje. Nije potrebno slati novi zahtjev.",
  noTerms: "Uslovi otkazivanja nisu dostupni u ovoj vezi.",
  statusSubmitted: "Zahtjev je zaprimljen i čeka pregled.",
  statusUnderReview: "Zahtjev je u razmatranju.",
  statusApproved: "Zahtjev je odobren. Otkazivanje još nije izvršeno.",
  statusRejected: "Zahtjev je odbijen.",
  statusEffective: "Otkazivanje je izvršeno.",
  statusOther: "Status zahtjeva je ažuriran.",
  noRequest: "Nije moguće pronaći zahtjev povezan s ovom sigurnom vezom.",
} : {
  title: "Booking cancellation request",
  statusTitle: "Cancellation request status",
  loading: "Loading your secure link…",
  unavailable: "Link unavailable",
  secure: "Secure personal link",
  invalid: "The link is incomplete or invalid.",
  retry: "Please try again.",
  booking: "Booking",
  terms: "Cancellation terms",
  explanation: "Explanation (optional)",
  explanationPlaceholder: "Add information that may help the venue review your request.",
  submit: "Submit cancellation request",
  submitting: "Submitting request…",
  submitted: "Your request has been recorded.",
  saveLink: "Save this secure link to follow the request status:",
  copy: "Copy link",
  copied: "Link copied.",
  status: "Status",
  requested: "Requested",
  resolved: "Resolved",
  requestOnly: "Your request will be reviewed by the venue. Submitting a request does not automatically cancel the booking.",
  existingRequest: "An open cancellation request already exists for this booking. You do not need to submit another request.",
  noTerms: "Cancellation terms are not available through this link.",
  statusSubmitted: "Your request has been received and is awaiting review.",
  statusUnderReview: "Your request is being reviewed.",
  statusApproved: "Your request was approved. Cancellation has not yet been executed.",
  statusRejected: "Your request was rejected.",
  statusEffective: "The booking cancellation has been completed.",
  statusOther: "The request status has been updated.",
  noRequest: "The request associated with this secure link could not be found.",
});

function formatError(value: unknown): string {
  if (value instanceof ApiError) {
    if (value.status === 404 || value.status === 410) {
      return bs.value
        ? "Ova veza je istekla, opozvana ili više nije dostupna."
        : "This link has expired, been revoked, or is no longer available.";
    }
    return formatApiError(value, (key) => key);
  }
  return value instanceof Error ? value.message : labels.value.retry;
}
function formatDate(value: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(locale.value, { dateStyle: "long", timeStyle: "short" }).format(date);
}
function statusDescription(value: string): string {
  switch (value) {
    case "submitted": return labels.value.statusSubmitted;
    case "under_review": return labels.value.statusUnderReview;
    case "approved": return labels.value.statusApproved;
    case "rejected": return labels.value.statusRejected;
    case "effective": return labels.value.statusEffective;
    default: return labels.value.statusOther;
  }
}
async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  if (!/^[A-Za-z0-9_-]{43}$/.test(token.value)) {
    error.value = labels.value.invalid;
    loading.value = false;
    return;
  }
  try {
    const action = props.mode === "request" ? "booking_cancellation_request" : "booking_cancellation_status";
    const resolved = await api.resolveExternalBookingAction(token.value, action);
    context.value = resolved.data;
    if (props.mode === "status") {
      if (!/^[0-9a-fA-F-]{36}$/.test(requestId.value)) throw new Error(labels.value.noRequest);
      const current = await api.getExternalBookingCancellationRequestStatus(token.value, requestId.value);
      status.value = current.data;
    }
  } catch (value) {
    error.value = formatError(value);
  } finally {
    loading.value = false;
  }
}
async function submit(): Promise<void> {
  if (!token.value || busy.value || props.mode !== "request") return;
  busy.value = true;
  error.value = "";
  try {
    if (!submissionKey.value) submissionKey.value = globalThis.crypto.randomUUID();
    const result = await api.submitExternalBookingCancellationRequest(
      token.value,
      { reasonCode: "customer_request", ...(explanation.value.trim() ? { explanation: explanation.value.trim() } : {}) },
      submissionKey.value,
    );
    submission.value = result.data;
    submissionKey.value = "";
  } catch (value) {
    error.value = formatError(value);
  } finally {
    busy.value = false;
  }
}
async function copyStatusLink(): Promise<void> {
  if (!statusLink.value) return;
  try {
    await navigator.clipboard.writeText(statusLink.value);
  } catch {
    error.value = bs.value ? "Nije moguće kopirati vezu u ovom pregledniku." : "This browser could not copy the link.";
  }
}
function changeLocale(event: Event): void {
  setLocale((event.target as HTMLSelectElement).value);
}
onMounted(() => { void load(); });
</script>

<template>
  <main class="public-offer-shell">
    <header class="public-offer-header">
      <a class="brand" href="/" aria-label="Eventor"><span class="brand-mark">E</span><span>EVENTOR <small>{{ props.mode === "request" ? labels.title : labels.statusTitle }}</small></span></a>
      <label class="public-language-choice">
        {{ bs ? "Jezik" : "Language" }}
        <select :value="locale" @change="changeLocale">
          <option value="bs-BA">Bosanski</option>
          <option value="en">English</option>
        </select>
      </label>
      <span class="public-security-note">{{ labels.secure }}</span>
    </header>

    <section v-if="loading" class="public-offer-panel" aria-live="polite">
      <span class="spinner"></span><p>{{ labels.loading }}</p>
    </section>
    <section v-else-if="error && !context" class="public-offer-panel" role="alert">
      <p class="eyebrow">EVENTOR</p>
      <h1>{{ labels.unavailable }}</h1>
      <p class="muted">{{ error }}</p>
    </section>
    <template v-else-if="context">
      <section class="public-offer-hero">
        <p class="eyebrow">{{ props.mode === "request" ? labels.title : labels.statusTitle }}</p>
        <h1>{{ labels.booking }} {{ context.bookingCode }}</h1>
        <p class="muted">{{ props.mode === "request" ? labels.requestOnly : labels.secure }}</p>
      </section>

      <section v-if="props.mode === 'request' && !submission && hasOpenRequest" class="public-offer-panel">
        <span class="pill pill-warning">{{ statusDescription(existingRequestStatus) }}</span>
        <p>{{ labels.existingRequest }}</p>
      </section>

      <section v-else-if="props.mode === 'request' && !submission" class="public-offer-panel">
        <h2>{{ labels.terms }}</h2>
        <p class="public-offer-copy">{{ context.cancellationTerms || labels.noTerms }}</p>
        <label class="public-form-field">
          <span>{{ labels.explanation }}</span>
          <textarea v-model="explanation" rows="5" maxlength="4000" :placeholder="labels.explanationPlaceholder"></textarea>
        </label>
        <p v-if="error" class="notice notice-error" role="alert">{{ error }}</p>
        <button class="button button-primary" type="button" :disabled="busy" @click="submit">
          {{ busy ? labels.submitting : labels.submit }}
        </button>
      </section>

      <section v-else-if="props.mode === 'request' && submission" class="public-offer-panel">
        <span class="pill pill-success">{{ labels.submitted }}</span>
        <h2>{{ labels.submitted }}</h2>
        <p>{{ labels.saveLink }}</p>
        <code class="public-status-link">{{ statusLink }}</code>
        <button class="button button-primary" type="button" @click="copyStatusLink">{{ labels.copy }}</button>
      </section>

      <section v-else-if="props.mode === 'status' && status" class="public-offer-panel">
        <div class="public-offer-summary">
          <div><span>{{ labels.status }}</span><strong>{{ statusDescription(status.status) }}</strong></div>
          <div><span>{{ labels.requested }}</span><strong>{{ formatDate(status.requestedAt) }}</strong></div>
          <div><span>{{ labels.resolved }}</span><strong>{{ formatDate(status.resolvedAt) }}</strong></div>
        </div>
      </section>
      <p v-if="error && context" class="notice notice-error" role="alert">{{ error }}</p>
    </template>
  </main>
</template>
