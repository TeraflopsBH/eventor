<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestInvitation } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { setLocale } from "../../i18n";

const { locale } = useI18n();
const token = ref(new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "");
const invitation = ref<GuestInvitation | null>(null);
const loading = ref(true);
const busy = ref(false);
const error = ref("");
const response = ref<"accepted" | "declined" | "tentative">("accepted");
const note = ref("");
const submitted = ref(false);
const submissionKey = ref("");
const submissionSignature = computed(() => JSON.stringify({
  response: response.value,
  note: note.value.trim(),
}));

const bs = computed(() => locale.value === "bs-BA");
const labels = computed(() => bs.value ? {
  invitation: "Pozivnica",
  loading: "Učitavanje pozivnice…",
  unavailable: "Pozivnica nije dostupna",
  secure: "Sigurna lična veza",
  starts: "Početak",
  ends: "Završetak",
  venue: "Mjesto održavanja",
  directions: "Upute",
  accessibility: "Pristupačnost",
  additional: "Dodatne informacije",
  yourResponse: "Vaš odgovor",
  accepted: "Dolazim",
  declined: "Ne mogu doći",
  tentative: "Još nisam siguran/na",
  note: "Napomena (opcionalno)",
  submit: "Pošalji odgovor",
  submitting: "Slanje odgovora…",
  saved: "Vaš odgovor je zabilježen.",
  changeNotAllowed: "Odgovor je već evidentiran i izmjene nisu dozvoljene putem ove veze.",
  deadline: "Rok za odgovor",
  host: "Organizator",
  invalidLink: "Veza pozivnice nije potpuna ili nije ispravna.",
  tryAgain: "Pokušajte ponovo.",
} : {
  invitation: "Event invitation",
  loading: "Loading your invitation…",
  unavailable: "Invitation unavailable",
  secure: "Secure personal link",
  starts: "Starts",
  ends: "Ends",
  venue: "Venue",
  directions: "Directions",
  accessibility: "Accessibility",
  additional: "Additional information",
  yourResponse: "Your response",
  accepted: "I will attend",
  declined: "I cannot attend",
  tentative: "I am not sure yet",
  note: "Note (optional)",
  submit: "Submit response",
  submitting: "Submitting response…",
  saved: "Your response has been recorded.",
  changeNotAllowed: "A response is already recorded and changes are not allowed through this link.",
  deadline: "Response deadline",
  host: "Organizer",
  invalidLink: "The invitation link is incomplete or invalid.",
  tryAgain: "Please try again.",
});

function formatError(value: unknown): string {
  if (value instanceof ApiError) {
    if (value.status === 404 || value.status === 410) {
      return bs.value ? "Ova pozivnica je istekla, opozvana ili više nije dostupna." : "This invitation has expired, been revoked, or is no longer available.";
    }
    return formatApiError(value, (key) => key);
  }
  return value instanceof Error ? value.message : labels.value.tryAgain;
}

function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  try {
    return new Intl.DateTimeFormat(locale.value, {
      dateStyle: "long",
      timeStyle: "short",
      timeZone: invitation.value?.timezone,
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat(locale.value, { dateStyle: "long", timeStyle: "short" }).format(date);
  }
}

async function loadInvitation(): Promise<void> {
  loading.value = true;
  error.value = "";
  if (!/^[A-Za-z0-9_-]{43}$/.test(token.value)) {
    error.value = labels.value.invalidLink;
    loading.value = false;
    return;
  }
  try {
    const result = await api.getGuestInvitation(token.value);
    invitation.value = result.data;
    setLocale(result.data.locale);
    response.value = result.data.currentResponse ?? "accepted";
    submitted.value = false;
  } catch (value) {
    error.value = formatError(value);
  } finally {
    loading.value = false;
  }
}

watch(submissionSignature, () => {
  submissionKey.value = "";
});

async function submitResponse(): Promise<void> {
  if (!invitation.value || !token.value || busy.value) return;
  if (!invitation.value.allowedResponses.includes(response.value)) {
    error.value = bs.value ? "Odabrani odgovor nije dozvoljen." : "That response is not available.";
    return;
  }
  if (!submissionKey.value) submissionKey.value = globalThis.crypto.randomUUID();
  busy.value = true;
  error.value = "";
  try {
    await api.submitGuestInvitationRsvp(
      token.value,
      { response: response.value, ...(note.value.trim() ? { note: note.value.trim() } : {}) },
      submissionKey.value,
    );
    submitted.value = true;
    submissionKey.value = "";
    const refreshed = await api.getGuestInvitation(token.value);
    invitation.value = refreshed.data;
    response.value = refreshed.data.currentResponse ?? response.value;
  } catch (value) {
    error.value = formatError(value);
  } finally {
    busy.value = false;
  }
}

function changeLocale(event: Event): void {
  setLocale((event.target as HTMLSelectElement).value);
}

onMounted(() => { void loadInvitation(); });
</script>

<template>
  <main class="public-offer-shell">
    <header class="public-offer-header">
      <a class="brand" href="/" aria-label="Eventor"><span class="brand-mark">E</span><span>EVENTOR <small>{{ labels.invitation }}</small></span></a>
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
    <section v-else-if="error && !invitation" class="public-offer-panel" role="alert">
      <p class="eyebrow">{{ labels.invitation }}</p>
      <h1>{{ labels.unavailable }}</h1>
      <p class="muted">{{ error }}</p>
    </section>

    <template v-else-if="invitation">
      <section class="public-offer-hero">
        <p class="eyebrow">{{ labels.invitation }}</p>
        <h1>{{ invitation.eventTitle }}</h1>
        <p v-if="invitation.presentationSnapshot.greeting" class="muted">{{ invitation.presentationSnapshot.greeting }}</p>
        <p v-if="invitation.presentationSnapshot.hostDisplayName" class="muted">{{ labels.host }}: {{ invitation.presentationSnapshot.hostDisplayName }}</p>
        <span class="pill" :class="invitation.currentResponse ? 'pill-success' : 'pill-warning'">
          {{ invitation.currentResponse ? (bs ? "Odgovor evidentiran" : "Response recorded") : (bs ? "Čeka se vaš odgovor" : "Awaiting your response") }}
        </span>
      </section>

      <section class="public-offer-panel">
        <div class="public-offer-summary">
          <div><span>{{ labels.starts }}</span><strong>{{ formatDate(invitation.startsAt) }}</strong></div>
          <div><span>{{ labels.ends }}</span><strong>{{ formatDate(invitation.endsAt) }}</strong></div>
          <div v-if="invitation.responseDeadline"><span>{{ labels.deadline }}</span><strong>{{ formatDate(invitation.responseDeadline) }}</strong></div>
        </div>
        <div v-if="invitation.presentationSnapshot.venueName || invitation.presentationSnapshot.venueAddress">
          <h2>{{ labels.venue }}</h2>
          <p><strong>{{ invitation.presentationSnapshot.venueName }}</strong></p>
          <p v-if="invitation.presentationSnapshot.venueAddress" class="muted">{{ invitation.presentationSnapshot.venueAddress }}</p>
        </div>
        <div v-if="invitation.presentationSnapshot.directions">
          <h2>{{ labels.directions }}</h2>
          <p class="public-cancellation-terms">{{ invitation.presentationSnapshot.directions }}</p>
        </div>
        <div v-if="invitation.presentationSnapshot.accessibility">
          <h2>{{ labels.accessibility }}</h2>
          <p class="public-cancellation-terms">{{ invitation.presentationSnapshot.accessibility }}</p>
        </div>
        <div v-if="invitation.presentationSnapshot.additionalInfo">
          <h2>{{ labels.additional }}</h2>
          <p class="public-cancellation-terms">{{ invitation.presentationSnapshot.additionalInfo }}</p>
        </div>
      </section>

      <section class="public-offer-panel public-offer-actions">
        <div>
          <p class="eyebrow">{{ labels.yourResponse }}</p>
          <h2>{{ bs ? "Molimo potvrdite dolazak" : "Please let the organizer know" }}</h2>
        </div>
        <p v-if="submitted" class="pill pill-success" role="status">{{ labels.saved }}</p>
        <p v-else-if="invitation.currentResponse && !invitation.responseChangeAllowed" class="muted">{{ labels.changeNotAllowed }}</p>
        <form v-else @submit.prevent="submitResponse">
          <label>
            {{ labels.yourResponse }}
            <select v-model="response" :disabled="busy">
              <option v-if="invitation.allowedResponses.includes('accepted')" value="accepted">{{ labels.accepted }}</option>
              <option v-if="invitation.allowedResponses.includes('declined')" value="declined">{{ labels.declined }}</option>
              <option v-if="invitation.allowedResponses.includes('tentative')" value="tentative">{{ labels.tentative }}</option>
            </select>
          </label>
          <label>
            {{ labels.note }}
            <textarea v-model="note" maxlength="1000" rows="3" :disabled="busy"></textarea>
          </label>
          <p v-if="error" class="muted" role="alert">{{ error }}</p>
          <button class="button button-primary" type="submit" :disabled="busy">
            {{ busy ? labels.submitting : labels.submit }}
          </button>
        </form>
      </section>
    </template>
  </main>
</template>
