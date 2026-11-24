<script setup lang="ts">
import { formatDateTime } from "../../i18n/format";
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestRelationship, type EventGuestRow } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; guest: EventGuestRow; canManage: boolean }>();
const emit = defineEmits<{ close: [] }>();
const { t, locale } = useI18n();
const heading = ref<HTMLElement | null>(null);
const relationships = ref<EventGuestRelationship[] | null>(null);
const candidates = ref<EventGuestRow[] | null>(null);
const query = ref("");
const appliedQuery = ref("");
const offset = ref(0);
const nextOffset = ref<number | null>(null);
const related = ref("");
const kind = ref("");
const directionality = ref<"mutual" | "directed">("mutual");
const busy = ref(false);
const error = ref("");

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      relationships.value = null;
      candidates.value = null;
      related.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.relationships.failed");
  } finally {
    busy.value = false;
  }
}

async function load(): Promise<void> {
  relationships.value = (await api.listEventGuestRelationships(props.eventId, props.guest.participationId)).data;
}

async function findGuests(pageOffset: number): Promise<void> {
  const { data } = await api.getEventGuestList(props.eventId, pageOffset, "", "", appliedQuery.value);
  candidates.value = data.people.filter((row) => row.participationId !== props.guest.participationId && row.status !== "cancelled");
  related.value = "";
  offset.value = pageOffset;
  nextOffset.value = data.nextOffset;
}

function search(): void {
  appliedQuery.value = query.value.trim();
  void run(() => findGuests(0));
}

function add(): void {
  if (!related.value || !kind.value.trim()) return;
  void run(async () => {
    await api.createEventGuestRelationship(props.eventId, props.guest.participationId, {
      relatedParticipationId: related.value, kind: kind.value.trim(), directionality: directionality.value,
    });
    related.value = "";
    kind.value = "";
    await load();
  });
}

function retire(link: EventGuestRelationship): void {
  if (!window.confirm(t("eventGuests.relationships.confirmEnd", { name: link.relatedDisplayName }))) return;
  void run(async () => {
    await api.retireEventGuestRelationship(props.eventId, props.guest.participationId, link.relationshipId);
    await load();
  });
}

function formatDate(value: string): string {
  return formatDateTime(value, locale.value);
}

onMounted(() => {
  heading.value?.focus();
  void run(load);
});
</script>

<template>
  <section class="event-relationships" aria-labelledby="event-relationships-heading">
    <div class="relationship-controls">
      <h3 id="event-relationships-heading" ref="heading" tabindex="-1">
        {{ t("eventGuests.relationships.title", { name: guest.displayName }) }}
      </h3>
      <button class="button button-secondary" type="button" :disabled="busy" @click="emit('close')">{{ t("common.close") }}</button>
    </div>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="relationships">
      <p v-if="!relationships.length" class="muted">{{ t("eventGuests.relationships.empty") }}</p>
      <ul v-else class="relationship-list">
        <li v-for="link in relationships" :key="link.relationshipId">
          <span>{{ link.relatedDisplayName }} · {{ link.kind }} · {{ t(`eventGuests.relationships.${link.direction}`) }}</span>
          <span v-if="link.retiredAt" class="muted">{{ t("eventGuests.relationships.ended", { time: formatDate(link.retiredAt) }) }}</span>
          <button v-else-if="canManage" class="button button-secondary" type="button" :disabled="busy"
            :aria-label="t('eventGuests.relationships.endNamed', { name: link.relatedDisplayName })" @click="retire(link)">
            {{ t("eventGuests.relationships.end") }}
          </button>
        </li>
      </ul>
      <template v-if="canManage && guest.status !== 'cancelled'">
        <form class="relationship-controls" @submit.prevent="search">
          <label>{{ t("eventGuests.relationships.search") }} <input v-model="query" type="search" maxlength="200" :disabled="busy"></label>
          <button class="button button-secondary" type="submit" :disabled="busy">{{ t("registry.search") }}</button>
        </form>
        <p v-if="candidates && !candidates.length" class="muted">{{ t("eventGuests.relationships.noCandidates") }}</p>
        <form v-if="candidates?.length" class="relationship-controls" @submit.prevent="add">
          <div>
            <label for="relationship-related-guest">{{ t("eventGuests.relationships.relatedGuest") }}</label>
            <select id="relationship-related-guest" v-model="related" required :disabled="busy">
              <option value="" disabled>{{ t("eventGuests.relationships.chooseGuest") }}</option>
              <option v-for="candidate in candidates" :key="candidate.participationId" :value="candidate.participationId">
                {{ candidate.displayName }}{{ candidate.participationCode ? ` (${candidate.participationCode})` : "" }}
              </option>
            </select>
          </div>
          <label>{{ t("eventGuests.relationships.kind") }} <input v-model="kind" maxlength="80" required :disabled="busy"></label>
          <div>
            <label for="relationship-direction">{{ t("eventGuests.relationships.direction") }}</label>
            <select id="relationship-direction" v-model="directionality" :disabled="busy">
              <option value="mutual">{{ t("eventGuests.relationships.mutual") }}</option>
              <option value="directed">{{ t("eventGuests.relationships.directed") }}</option>
            </select>
          </div>
          <button class="button button-primary" type="submit" :disabled="busy || !related || !kind.trim()">
            {{ t("eventGuests.relationships.add") }}
          </button>
        </form>
        <div v-if="offset > 0 || nextOffset !== null" class="relationship-controls">
          <button class="button button-secondary" type="button" :disabled="busy || offset === 0"
            @click="run(() => findGuests(Math.max(0, offset - 50)))">{{ t("registry.previous") }}</button>
          <button class="button button-secondary" type="button" :disabled="busy || nextOffset === null"
            @click="run(() => findGuests(nextOffset ?? 0))">{{ t("registry.next") }}</button>
        </div>
      </template>
    </template>
  </section>
</template>

<style scoped>
.event-relationships { display: grid; gap: 0.75rem; }
.relationship-controls { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
.relationship-list li > :not(:first-child) { margin-inline-start: 0.5rem; }
</style>
