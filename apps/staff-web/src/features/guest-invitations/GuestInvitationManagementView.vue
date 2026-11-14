<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { api, type GuestInvitationEvent, type GuestInvitationParticipation } from "../../api";

const props = defineProps<{ organizationId: string }>();
const { t, locale } = useI18n();
const events = ref<GuestInvitationEvent[]>([]);
const participants = ref<GuestInvitationParticipation[]>([]);
const selectedEventId = ref("");
const loading = ref(false);
const error = ref("");
const notice = ref("");
const selectedEvent = computed(() => events.value.find((event) => event.eventId === selectedEventId.value) ?? null);
const localeValue = computed<"bs-BA" | "en">(() => locale.value === "en" ? "en" : "bs-BA");

async function loadEvents(): Promise<void> {
  if (!props.organizationId) return;
  loading.value = true; error.value = ""; notice.value = "";
  try {
    const result = await api.getGuestInvitationEvents(props.organizationId);
    events.value = result.data;
    if (!selectedEventId.value && events.value.length) selectedEventId.value = events.value[0]!.eventId;
    if (selectedEventId.value && !events.value.some((event) => event.eventId === selectedEventId.value)) {
      selectedEventId.value = events.value[0]?.eventId ?? "";
    }
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : t("guestInvitations.loadFailed");
  } finally { loading.value = false; }
}

async function loadParticipants(): Promise<void> {
  if (!selectedEventId.value) { participants.value = []; return; }
  loading.value = true; error.value = ""; notice.value = "";
  try {
    participants.value = (await api.getGuestInvitationParticipations(selectedEventId.value)).data;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : t("guestInvitations.loadFailed");
  } finally { loading.value = false; }
}

async function issue(participation: GuestInvitationParticipation): Promise<void> {
  const event = selectedEvent.value;
  if (!event?.scheduleRevisionId || !event.rsvpPolicyRevisionId || !participation.emailReady) return;
  const isReissue = Boolean(participation.invitationId && ["active", "draft"].includes(participation.invitationStatus ?? ""));
  const message = isReissue ? t("guestInvitations.confirmReissue", { name: participation.displayName }) : t("guestInvitations.confirmIssue", { name: participation.displayName });
  if (!window.confirm(message)) return;
  loading.value = true; error.value = ""; notice.value = "";
  try {
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    await api.issueGuestInvitation(event.eventId, participation.participationId, {
      ...(isReissue && participation.invitationId ? { invitationId: participation.invitationId } : {}),
      scheduleRevisionId: event.scheduleRevisionId,
      rsvpPolicyRevisionId: event.rsvpPolicyRevisionId,
      locale: localeValue.value,
      expiresAt,
      presentationSnapshot: {},
    });
    notice.value = t(isReissue ? "guestInvitations.reissued" : "guestInvitations.issued", { name: participation.displayName });
    await loadParticipants();
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : t("guestInvitations.issueFailed");
  } finally { loading.value = false; }
}

async function revoke(participation: GuestInvitationParticipation): Promise<void> {
  if (!participation.invitationId || !window.confirm(t("guestInvitations.confirmRevoke", { name: participation.displayName }))) return;
  loading.value = true; error.value = ""; notice.value = "";
  try {
    await api.revokeGuestInvitation(participation.invitationId, "staff_revoked");
    notice.value = t("guestInvitations.revoked", { name: participation.displayName });
    await loadParticipants();
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : t("guestInvitations.revokeFailed");
  } finally { loading.value = false; }
}

watch(selectedEventId, () => { void loadParticipants(); });
onMounted(() => { void loadEvents(); });
</script>

<template>
  <section class="panel">
    <div class="section-heading">
      <div>
        <p class="eyebrow">{{ t("guestInvitations.eyebrow") }}</p>
        <h2>{{ t("guestInvitations.title") }}</h2>
        <p class="muted">{{ t("guestInvitations.description") }}</p>
      </div>
      <button class="button button-quiet" :disabled="loading" @click="loadEvents">{{ t("guestInvitations.refresh") }}</button>
    </div>

    <label class="field-label">
      {{ t("guestInvitations.event") }}
      <select v-model="selectedEventId" :disabled="loading || events.length === 0">
        <option value="" disabled>{{ t("guestInvitations.chooseEvent") }}</option>
        <option v-for="event in events" :key="event.eventId" :value="event.eventId">{{ event.title }} · {{ event.status }}</option>
      </select>
    </label>

    <p v-if="error" class="message message-error" role="alert">{{ error }}</p>
    <p v-if="notice" class="message message-success" role="status">{{ notice }}</p>
    <p v-if="loading" class="muted" aria-live="polite">{{ t("guestInvitations.loading") }}</p>
    <p v-else-if="events.length === 0" class="muted">{{ t("guestInvitations.noEvents") }}</p>
    <template v-else-if="selectedEvent">
      <div class="muted">
        {{ t("guestInvitations.eventSummary", { eligible: selectedEvent.eligibleParticipationCount, invitations: selectedEvent.invitationCount }) }}
      </div>
      <p v-if="!selectedEvent.scheduleRevisionId || !selectedEvent.rsvpPolicyRevisionId" class="message message-error">
        {{ t("guestInvitations.eventNotReady") }}
      </p>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>{{ t("guestInvitations.guest") }}</th>
              <th>{{ t("guestInvitations.participation") }}</th>
              <th>{{ t("guestInvitations.invitation") }}</th>
              <th>{{ t("guestInvitations.delivery") }}</th>
              <th>{{ t("guestInvitations.rsvp") }}</th>
              <th>{{ t("guestInvitations.actions") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="person in participants" :key="person.participationId">
              <td>
                <strong>{{ person.displayName }}</strong>
                <small v-if="!person.emailReady" class="muted">{{ t("guestInvitations.emailNotReady") }}</small>
              </td>
              <td>{{ person.status }}</td>
              <td>{{ person.invitationStatus ?? t("guestInvitations.notIssued") }}</td>
              <td>{{ person.deliveryStatus ?? "—" }}</td>
              <td>{{ person.currentResponse ?? "—" }}</td>
              <td class="action-cell">
                <button
                  v-if="person.status === 'eligible' && person.emailReady && selectedEvent.scheduleRevisionId && selectedEvent.rsvpPolicyRevisionId && (!person.invitationId || ['active', 'draft'].includes(person.invitationStatus ?? ''))"
                  class="button button-primary"
                  :disabled="loading"
                  @click="issue(person)"
                >{{ person.invitationId ? t("guestInvitations.reissue") : t("guestInvitations.issue") }}</button>
                <button
                  v-if="person.invitationId && ['active', 'draft'].includes(person.invitationStatus ?? '')"
                  class="button button-quiet"
                  :disabled="loading"
                  @click="revoke(person)"
                >{{ t("guestInvitations.revoke") }}</button>
              </td>
            </tr>
            <tr v-if="participants.length === 0"><td colspan="6" class="muted">{{ t("guestInvitations.noParticipants") }}</td></tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>
