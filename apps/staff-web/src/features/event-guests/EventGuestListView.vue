<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import EventGuestImportPreview from "./EventGuestImportPreview.vue";
import { api, ApiError, type EventGuestList, type EventGuestRow, type EventGuestWorkspace, type ManagedParticipationStatus } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { downloadGuestCsv, downloadGuestXlsx, formatGuestCsv } from "../../guest-export";

const props = defineProps<{ organizationId: string }>();
const { t } = useI18n();
const events = ref<EventGuestWorkspace[] | null>(null);
const eventId = ref("");
const roster = ref<EventGuestList | null>(null);
const offset = ref(0);
const status = ref<EventGuestRow["status"] | "">("");
const statuses: ManagedParticipationStatus[] = ["eligible", "waitlisted", "ineligible", "withdrawn"];
const editing = ref<EventGuestRow | null>(null);
const nextStatus = ref<ManagedParticipationStatus>("eligible");
const busy = ref(false);
const showImport = ref(false);
const error = ref("");

async function run(operation: () => Promise<void>): Promise<void> {
  error.value = "";
  busy.value = true;
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      events.value = null;
      roster.value = null;
      editing.value = null;
    }
    error.value = failure instanceof ApiError && failure.code === "GUEST_ROSTER_EXPORT_LIMIT"
      ? t("eventGuests.exportLimit")
      : failure instanceof ApiError ? formatApiError(failure, t) : t("registry.failed");
  } finally {
    busy.value = false;
  }
}

async function loadPage(pageOffset: number): Promise<void> {
  editing.value = null;
  if (!eventId.value) return;
  roster.value = (await api.getEventGuestList(eventId.value, pageOffset, status.value)).data;
  offset.value = pageOffset;
}

function chooseEvent(): void {
  showImport.value = false;
  status.value = "";
  roster.value = null;
  void run(() => loadPage(0));
}

function selectStatus(): void {
  roster.value = null;
  void run(() => loadPage(0));
}

function startEdit(row: EventGuestRow): void {
  if (row.status === "cancelled") return;
  editing.value = row;
  nextStatus.value = row.status;
}

function save(): Promise<void> {
  const row = editing.value;
  if (!row) return Promise.resolve();
  return run(async () => {
    await api.updateGuestParticipationStatus(eventId.value, row.participationId, nextStatus.value, row.revision);
    await loadPage(offset.value);
  });
}

function downloadRoster(format: "csv" | "xlsx"): Promise<void> {
  return run(async () => {
    const { data } = await api.getEventGuestExport(eventId.value, status.value);
    const rows = [
      ["event_display_name", "participation_status", "category_code"],
      ...data.people.map((guest) => [guest.displayName, guest.status, guest.categoryCode]),
    ];
    const filename = `event-guests-${eventId.value}-${status.value || "all"}.${format}`;
    if (format === "csv") {
      downloadGuestCsv(filename, `\uFEFF${formatGuestCsv(rows)}`);
    } else {
      await downloadGuestXlsx(filename, t("navigation.eventGuests"), rows, [42, 23, 20]);
    }
  });
}

onMounted(() => run(async () => {
  events.value = (await api.listEventGuestWorkspaces(props.organizationId)).data;
}));
</script>

<template>
  <section class="panel guest-list">
    <h2>{{ t("navigation.eventGuests") }}</h2>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <p v-if="events && !events.length" class="muted">{{ t("eventGuests.noLists") }}</p>
    <div v-else-if="events" class="guest-list-controls">
      <div>
        <label for="roster-event">{{ t("registry.event") }}</label>
        <select id="roster-event" v-model="eventId" :disabled="busy" @change="chooseEvent">
          <option value="">{{ t("registry.chooseEvent") }}</option>
          <option v-for="event in events" :key="event.eventId" :value="event.eventId">
            {{ event.title }} ({{ event.eventCode }})
          </option>
        </select>
      </div>
      <div v-if="eventId">
        <label for="roster-filter">{{ t("registry.linkStatus") }}</label>
        <select id="roster-filter" v-model="status" :disabled="busy" @change="selectStatus">
          <option value="">{{ t("eventGuests.allStatuses") }}</option>
          <option v-for="option in [...statuses, 'cancelled']" :key="option" :value="option">{{ t(`registry.participationStatus.${option}`) }}</option>
        </select>
      </div>
      <button v-if="roster" class="button button-secondary" type="button" :disabled="busy" @click="downloadRoster('csv')">
        {{ t("eventGuests.exportCsv") }}
      </button>
      <button v-if="roster" class="button button-secondary" type="button" :disabled="busy" @click="downloadRoster('xlsx')">
        {{ t("eventGuests.exportXlsx") }}
      </button>
    </div>
    <div v-if="roster?.canManage">
      <button class="button button-secondary" type="button" :disabled="busy" :aria-expanded="showImport" @click="showImport = !showImport">
        {{ t("eventGuests.import.title") }}
      </button>
      <EventGuestImportPreview v-if="showImport" :key="eventId" :event-id="eventId" @committed="run(() => loadPage(0))" />
    </div>
    <p v-if="roster && !roster.people.length" class="muted">{{ t("eventGuests.noGuests") }}</p>
    <div v-else-if="roster" class="table-scroll">
      <table class="data-table">
        <thead><tr>
          <th scope="col">{{ t("registry.displayName") }}</th>
          <th scope="col">{{ t("registry.linkStatus") }}</th>
          <th scope="col">{{ t("eventGuests.category") }}</th>
          <th scope="col" v-if="roster.canManage">{{ t("common.actions") }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="row in roster.people" :key="row.participationId">
            <td>{{ row.displayName }}</td>
            <td>{{ t(`registry.participationStatus.${row.status}`) }}</td>
            <td>{{ row.categoryCode ?? "—" }}</td>
            <td v-if="roster.canManage">
              <form v-if="editing?.participationId === row.participationId" @submit.prevent="save">
                <label for="roster-next-status">{{ t("registry.linkStatus") }}</label>
                <select id="roster-next-status" v-model="nextStatus">
                  <option v-for="option in statuses" :key="option" :value="option">{{ t(`registry.participationStatus.${option}`) }}</option>
                </select>
                <p v-if="nextStatus !== 'eligible'" class="muted">{{ t("registry.revokeBeforeChange") }}</p>
                <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="editing = null">{{ t("common.cancel") }}</button>
              </form>
              <button v-else-if="row.status !== 'cancelled'" class="button button-secondary" type="button" :disabled="busy || editing !== null" @click="startEdit(row)">
                {{ t("registry.editParticipation") }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="roster && (offset > 0 || roster.nextOffset !== null)" class="guest-list-controls">
      <button class="button button-secondary" :disabled="busy || offset === 0" @click="run(() => loadPage(Math.max(0, offset - 50)))">{{ t("registry.previous") }}</button>
      <button class="button button-secondary" :disabled="busy || roster.nextOffset === null" @click="run(() => loadPage(roster?.nextOffset ?? 0))">{{ t("registry.next") }}</button>
    </div>
  </section>
</template>

<style scoped>
.guest-list { display: grid; gap: 1rem; }
.guest-list-controls { display: flex; gap: 0.75rem; align-items: end; flex-wrap: wrap; }
</style>
