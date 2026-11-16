<script setup lang="ts">
import { computed, reactive, ref, type Ref } from "vue";
import type { useOrganizerEvents } from "./useOrganizerEvents";
import type { CreateOrganizerEventInput, OrganizerEvent } from "../../api";

type Workspace = ReturnType<typeof useOrganizerEvents> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace; t: (key: string, params?: Record<string, string | number>) => string }>();
const { events, busy, canArchive, refresh, createEvent, updateEvent, archiveEvent } = props.workspace;
const createOpen = ref(false);
const editingEventId = ref("");
const createForm = reactive({
  eventCode: "",
  title: "",
  descriptionInternal: "",
  startsAt: "",
  endsAt: "",
  timezoneName: "Europe/Sarajevo",
});
const editForm = reactive({ title: "", descriptionInternal: "" });
const sortedEvents = computed(() => [...events.value].sort((a, b) => {
  const left = a.startsAt ? Date.parse(a.startsAt) : Number.MAX_SAFE_INTEGER;
  const right = b.startsAt ? Date.parse(b.startsAt) : Number.MAX_SAFE_INTEGER;
  return left - right;
}));
const editingEvent = computed(() => props.events.find((event) => event.eventId === editingEventId.value) ?? null);

function toIso(value: string): string {
  return new Date(value).toISOString();
}
function formatDate(value?: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}
function statusLabel(status: OrganizerEvent["status"]): string {
  return props.t(`events.status.${status}`);
}
function resetCreate(): void {
  Object.assign(createForm, {
    eventCode: "",
    title: "",
    descriptionInternal: "",
    startsAt: "",
    endsAt: "",
    timezoneName: "Europe/Sarajevo",
  });
  createOpen.value = false;
}
function submitCreate(): void {
  if (!createForm.eventCode.trim() || !createForm.title.trim() || !createForm.startsAt || !createForm.endsAt) return;
  const startsAt = toIso(createForm.startsAt);
  const endsAt = toIso(createForm.endsAt);
  if (Date.parse(endsAt) <= Date.parse(startsAt)) return;
  createEvent({
    eventCode: createForm.eventCode.trim(),
    title: createForm.title.trim(),
    descriptionInternal: createForm.descriptionInternal.trim() || null,
    startsAt,
    endsAt,
    timezoneName: createForm.timezoneName.trim(),
    venueSummary: {},
    scheduleSnapshot: {},
  });
  resetCreate();
}
function startEdit(event: OrganizerEvent): void {
  editingEventId.value = event.eventId;
  editForm.title = event.title;
  editForm.descriptionInternal = event.descriptionInternal ?? "";
}
function cancelEdit(): void {
  editingEventId.value = "";
  editForm.title = "";
  editForm.descriptionInternal = "";
}
function submitUpdate(): void {
  const event = editingEvent.value;
  if (!event || !editForm.title.trim()) return;
  updateEvent(event, {
    title: editForm.title.trim(),
    descriptionInternal: editForm.descriptionInternal.trim() || null,
  });
  cancelEdit();
}
</script>

<template>
  <section class="panel event-management">
    <header class="workspace-heading">
      <div>
        <p class="eyebrow">{{ t("events.eyebrow") }}</p>
        <h2>{{ t("events.title") }}</h2>
        <p class="muted">{{ t("events.description") }}</p>
      </div>
      <div class="toolbar">
        <button class="button button-secondary" type="button" :disabled="busy" @click="refresh">
          {{ t("common.refresh") }}
        </button>
        <button class="button button-primary" type="button" :disabled="workspace.busy" @click="createOpen = !createOpen">
          {{ createOpen ? t("common.close") : t("events.create") }}
        </button>
      </div>
    </header>

    <form v-if="createOpen" class="event-form" @submit.prevent="submitCreate">
      <h3>{{ t("events.createTitle") }}</h3>
      <div class="form-grid">
        <label>
          <span>{{ t("events.eventCode") }}</span>
          <input v-model="createForm.eventCode" required minlength="2" maxlength="80" autocomplete="off">
        </label>
        <label>
          <span>{{ t("events.eventTitle") }}</span>
          <input v-model="createForm.title" required minlength="2" maxlength="250">
        </label>
        <label>
          <span>{{ t("events.startsAt") }}</span>
          <input v-model="createForm.startsAt" type="datetime-local" required>
        </label>
        <label>
          <span>{{ t("events.endsAt") }}</span>
          <input v-model="createForm.endsAt" type="datetime-local" required>
        </label>
        <label>
          <span>{{ t("events.timezone") }}</span>
          <input v-model="createForm.timezoneName" required maxlength="80">
        </label>
        <label class="form-wide">
          <span>{{ t("events.internalDescription") }}</span>
          <textarea v-model="createForm.descriptionInternal" rows="2" maxlength="10000" />
        </label>
      </div>
      <div class="toolbar">
        <button class="button button-primary" type="submit" :disabled="workspace.busy">{{ t("events.saveCreate") }}</button>
        <button class="button button-secondary" type="button" @click="resetCreate">{{ t("common.cancel") }}</button>
      </div>
    </form>

    <div v-if="!workspace.events.length" class="empty-state">
      <h3>{{ t("events.emptyTitle") }}</h3>
      <p>{{ t("events.emptyDescription") }}</p>
    </div>

    <div v-else class="table-scroll">
      <table class="data-table">
        <thead>
          <tr>
            <th>{{ t("events.eventTitle") }}</th>
            <th>{{ t("events.eventCode") }}</th>
            <th>{{ t("events.schedule") }}</th>
            <th>{{ t("events.statusLabel") }}</th>
            <th>{{ t("events.revision") }}</th>
            <th>{{ t("common.actions") }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="event in sortedEvents" :key="event.eventId">
            <td>
              <strong>{{ event.title }}</strong>
              <small v-if="event.descriptionInternal" class="muted block">{{ event.descriptionInternal }}</small>
            </td>
            <td><code>{{ event.eventCode }}</code></td>
            <td>{{ formatDate(event.startsAt) }} – {{ formatDate(event.endsAt) }}</td>
            <td><span class="status-pill">{{ statusLabel(event.status) }}</span></td>
            <td>{{ event.detailsRevision }}</td>
            <td>
              <div class="toolbar compact">
                <button class="button button-secondary button-small" type="button" :disabled="workspace.busy || event.status === 'archived'" @click="startEdit(event)">
                  {{ t("common.edit") }}
                </button>
                <button class="button button-danger button-small" type="button" :disabled="workspace.busy || !canArchive(event)" @click="archiveEvent(event)">
                  {{ t("events.archive") }}
                </button>
              </div>
              <form v-if="editingEventId === event.eventId" class="inline-edit" @submit.prevent="submitUpdate">
                <label>
                  <span>{{ t("events.eventTitle") }}</span>
                  <input v-model="editForm.title" required minlength="2" maxlength="250">
                </label>
                <label>
                  <span>{{ t("events.internalDescription") }}</span>
                  <textarea v-model="editForm.descriptionInternal" rows="2" maxlength="10000" />
                </label>
                <div class="toolbar compact">
                  <button class="button button-primary button-small" type="submit" :disabled="workspace.busy">{{ t("common.save") }}</button>
                  <button class="button button-secondary button-small" type="button" @click="cancelEdit">{{ t("common.cancel") }}</button>
                </div>
              </form>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.event-management { display: grid; gap: 22px; }
.workspace-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 18px; }
.workspace-heading h2 { margin-bottom: 8px; }
.toolbar { display: flex; align-items: center; gap: 9px; flex-wrap: wrap; }
.toolbar.compact { gap: 6px; }
.button-small { padding: 7px 10px; font-size: 11px; }
.event-form { padding: 20px; border: 1px solid var(--border); border-radius: 12px; background: #171717; display: grid; gap: 18px; }
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.form-wide { grid-column: 1 / -1; }
.event-management textarea { width: 100%; min-width: 0; resize: vertical; color: #f1f1f1; background: #141414; border: 1px solid #414141; border-radius: 8px; padding: 11px 12px; font: inherit; font-size: 13px; }
.event-management textarea:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px #f5863420; }
.table-scroll { overflow-x: auto; border: 1px solid var(--border); border-radius: 11px; }
.data-table { width: 100%; min-width: 850px; border-collapse: collapse; font-size: 12px; }
.data-table th, .data-table td { padding: 13px 14px; border-bottom: 1px solid var(--border); text-align: left; vertical-align: top; }
.data-table th { color: var(--muted); background: #191919; font-size: 10px; text-transform: uppercase; letter-spacing: .08em; }
.data-table tr:last-child td { border-bottom: 0; }
.data-table small.block { display: block; margin-top: 5px; max-width: 280px; }
.status-pill { display: inline-flex; padding: 4px 8px; border-radius: 999px; background: #f5863418; color: #f5b27f; font-size: 10px; font-weight: 750; }
.inline-edit { display: grid; gap: 10px; min-width: 240px; margin-top: 12px; padding: 12px; border: 1px solid var(--border); border-radius: 9px; background: #171717; }
.empty-state { padding: 34px; text-align: center; border: 1px dashed var(--border); border-radius: 12px; }
.empty-state h3 { margin-bottom: 8px; }
.empty-state p { margin-bottom: 0; color: var(--muted); font-size: 13px; }
@media (max-width: 720px) {
  .workspace-heading { flex-direction: column; }
  .form-grid { grid-template-columns: 1fr; }
  .form-wide { grid-column: auto; }
}
</style>
