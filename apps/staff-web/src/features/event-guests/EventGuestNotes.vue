<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestNotes, type EventGuestRow } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; guest: EventGuestRow }>();
const emit = defineEmits<{ close: [] }>();
const { t, locale } = useI18n();
const result = ref<EventGuestNotes | null>(null);
const offset = ref(0);
const text = ref("");
const error = ref("");
const busy = ref(false);

async function load(pageOffset: number): Promise<void> {
  result.value = (await api.listEventGuestNotes(props.eventId, props.guest.participationId, pageOffset)).data;
  offset.value = pageOffset;
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      result.value = null;
      text.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.notes.failed");
  } finally {
    busy.value = false;
  }
}

function add(): void {
  const content = text.value.trim();
  if (!content) return;
  void run(async () => {
    await api.createEventGuestNote(props.eventId, props.guest.participationId, content);
    text.value = "";
    await load(0);
  });
}

function withdraw(noteId: string): void {
  if (!window.confirm(t("eventGuests.notes.confirmWithdraw"))) return;
  void run(async () => {
    await api.withdrawEventGuestNote(props.eventId, props.guest.participationId, noteId);
    await load(offset.value);
  });
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

onMounted(() => run(() => load(0)));
</script>

<template>
  <section class="event-guest-notes" aria-labelledby="guest-notes-heading">
    <div class="guest-note-controls">
      <h3 id="guest-notes-heading">{{ t("eventGuests.notes.forGuest", { name: guest.displayName }) }}</h3>
      <button class="button button-secondary" type="button" @click="emit('close')">{{ t("common.close") }}</button>
    </div>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="result">
      <form v-if="result.canManage" class="event-guest-notes" @submit.prevent="add">
        <label for="event-guest-note-text">{{ t("eventGuests.notes.text") }}</label>
        <textarea id="event-guest-note-text" v-model="text" required maxlength="2000" rows="3" :disabled="busy"></textarea>
        <button class="button button-primary" type="submit" :disabled="busy || !text.trim()">{{ t("eventGuests.notes.add") }}</button>
      </form>
      <p v-if="!result.notes.length">{{ t("eventGuests.notes.empty") }}</p>
      <ul v-else>
        <li v-for="note in result.notes" :key="note.noteId">
          <time :datetime="note.createdAt">{{ formatDate(note.createdAt) }}</time>
          <p v-if="note.text" class="guest-note-text">{{ note.text }}</p>
          <p v-else-if="note.withdrawnAt">{{ t("eventGuests.notes.withdrawn", { time: formatDate(note.withdrawnAt) }) }}</p>
          <button v-if="result.canManage && !note.withdrawnAt" class="button button-secondary" type="button" :disabled="busy"
            @click="withdraw(note.noteId)">{{ t("eventGuests.notes.withdraw") }}</button>
        </li>
      </ul>
      <div v-if="offset > 0 || result.nextOffset !== null" class="guest-note-controls">
        <button class="button button-secondary" type="button" :disabled="busy || offset === 0"
          @click="run(() => load(Math.max(0, offset - 50)))">{{ t("registry.previous") }}</button>
        <button class="button button-secondary" type="button" :disabled="busy || result.nextOffset === null"
          @click="run(() => load(result?.nextOffset ?? 0))">{{ t("registry.next") }}</button>
      </div>
    </template>
  </section>
</template>

<style scoped>
.event-guest-notes { display: grid; gap: 0.75rem; justify-items: start; }
.guest-note-controls { display: flex; align-items: center; flex-wrap: wrap; gap: 0.75rem; }
.guest-note-text { white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
