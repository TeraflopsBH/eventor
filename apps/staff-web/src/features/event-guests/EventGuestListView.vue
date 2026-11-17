<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import EventGuestImportPreview from "./EventGuestImportPreview.vue";
import EventGuestOptions from "./EventGuestOptions.vue";
import { api, ApiError, type EventGuestCategory, type EventGuestList, type EventGuestRow, type EventGuestTag, type EventGuestWorkspace, type ManagedParticipationStatus } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { downloadGuestCsv, downloadGuestXlsx, formatGuestCsv } from "../../guest-export";

const props = defineProps<{ organizationId: string }>();
const { t } = useI18n();
const events = ref<EventGuestWorkspace[] | null>(null);
const eventId = ref("");
const roster = ref<EventGuestList | null>(null);
const offset = ref(0);
const status = ref<EventGuestRow["status"] | "">("");
const categoryFilter = ref("");
const statuses: ManagedParticipationStatus[] = ["eligible", "waitlisted", "ineligible", "withdrawn"];
const editing = ref<EventGuestRow | null>(null);
const nextStatus = ref<ManagedParticipationStatus>("eligible");
const busy = ref(false);
const showImport = ref(false);
const showCategories = ref(false);
const showTags = ref(false);
const categories = ref<EventGuestCategory[]>([]);
const tags = ref<EventGuestTag[]>([]);
const activeCategories = computed(() => categories.value.filter((category) => !category.retired));
const categoryNames = computed(() => new Map(categories.value.map((category) => [category.categoryId, category.label])));
const categoryOptions = computed(() => categories.value.map(({ categoryId, ...option }) => ({ id: categoryId, ...option })));
const tagOptions = computed(() => tags.value.map(({ tagId, ...option }) => ({ id: tagId, ...option })));
const categoryEdit = ref<{ row: EventGuestRow; original: string; selected: string } | null>(null);
const tagEdit = ref<{ row: EventGuestRow; selected: string[] } | null>(null);
const tagSelectionChanged = computed(() => {
  const edit = tagEdit.value;
  return !!edit && (edit.selected.length !== edit.row.tagIds.length || edit.selected.some((id) => !edit.row.tagIds.includes(id)));
});
const rowEditing = computed(() => !!(editing.value || categoryEdit.value || tagEdit.value));
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
      categories.value = [];
      tags.value = [];
      categoryEdit.value = null;
      tagEdit.value = null;
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
  categoryEdit.value = null;
  tagEdit.value = null;
  if (!eventId.value) return;
  roster.value = (await api.getEventGuestList(eventId.value, pageOffset, status.value, categoryFilter.value)).data;
  offset.value = pageOffset;
}

async function loadCategories(): Promise<void> {
  categories.value = (await api.listEventGuestCategories(eventId.value)).data;
}

async function loadTags(): Promise<void> {
  tags.value = (await api.listEventGuestTags(eventId.value)).data;
}

function chooseEvent(): void {
  showImport.value = false;
  showCategories.value = false;
  showTags.value = false;
  categories.value = [];
  tags.value = [];
  status.value = "";
  categoryFilter.value = "";
  roster.value = null;
  void run(async () => {
    if (!eventId.value) return;
    const [page, catalogue, tagList] = await Promise.all([
      api.getEventGuestList(eventId.value, 0, status.value), api.listEventGuestCategories(eventId.value),
      api.listEventGuestTags(eventId.value),
    ]);
    editing.value = null;
    categoryEdit.value = null;
    tagEdit.value = null;
    roster.value = page.data;
    categories.value = catalogue.data;
    tags.value = tagList.data;
    offset.value = 0;
  });
}

function applyFilters(): void {
  roster.value = null;
  void run(() => loadPage(0));
}

function startEdit(row: EventGuestRow): void {
  if (row.status === "cancelled") return;
  editing.value = row;
  nextStatus.value = row.status;
}

function categoryName(row: EventGuestRow): string | null {
  return (row.categoryId && categoryNames.value.get(row.categoryId)) || row.categoryCode;
}

function editCategory(row: EventGuestRow): void {
  const original = row.categoryId ?? (row.categoryCode === null ? "" : "legacy");
  categoryEdit.value = { row, original, selected: original };
}

function saveCategory(): Promise<void> {
  const edit = categoryEdit.value;
  if (!edit || edit.selected === edit.original) return Promise.resolve();
  return run(async () => {
    await api.setEventGuestCategory(eventId.value, edit.row.participationId, edit.selected || null, edit.row.revision);
    await loadPage(offset.value);
  });
}

function editTags(row: EventGuestRow): void {
  tagEdit.value = { row, selected: [...row.tagIds] };
}

function saveTags(): Promise<void> {
  const edit = tagEdit.value;
  if (!edit || !tagSelectionChanged.value) return Promise.resolve();
  return run(async () => {
    await api.setEventGuestTags(eventId.value, edit.row.participationId, edit.selected, edit.row.revision);
    await loadPage(offset.value);
  });
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
    const category = categoryFilter.value;
    const { data } = await api.getEventGuestExport(eventId.value, status.value, category);
    const rows = [
      ["event_display_name", "participation_status", "category_code"],
      ...data.people.map((guest) => [guest.displayName, guest.status, guest.categoryCode]),
    ];
    const categoryCode = categories.value.find((item) => item.categoryId === category)?.code ?? category;
    const suffix = categoryCode ? `-${categoryCode}` : "";
    const filename = `event-guests-${eventId.value}-${status.value || "all"}${suffix}.${format}`;
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
        <select id="roster-filter" v-model="status" :disabled="busy" @change="applyFilters">
          <option value="">{{ t("eventGuests.allStatuses") }}</option>
          <option v-for="option in [...statuses, 'cancelled']" :key="option" :value="option">{{ t(`registry.participationStatus.${option}`) }}</option>
        </select>
      </div>
      <div v-if="eventId">
        <label for="roster-filter-category">{{ t("eventGuests.category") }}</label>
        <select id="roster-filter-category" v-model="categoryFilter" :disabled="busy" @change="applyFilters">
          <option value="">{{ t("eventGuests.categories.all") }}</option>
          <option value="unassigned">{{ t("eventGuests.categories.unassigned") }}</option>
          <option v-for="category in categories" :key="category.categoryId" :value="category.categoryId">
            {{ category.retired ? t("eventGuests.categories.retiredOption", { label: category.label }) : category.label }}
          </option>
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
    <div v-if="roster?.canManage">
      <button class="button button-secondary" type="button" :disabled="busy" :aria-expanded="showCategories"
        @click="showCategories = !showCategories">
        {{ t("eventGuests.categories.manage") }}
      </button>
      <EventGuestOptions v-if="showCategories" :key="eventId" :event-id="eventId" kind="categories" :options="categoryOptions"
        @changed="run(loadCategories)" />
    </div>
    <div v-if="roster?.canManage">
      <button class="button button-secondary" type="button" :disabled="busy" :aria-expanded="showTags" @click="showTags = !showTags">
        {{ t("eventGuests.tags.manage") }}
      </button>
      <EventGuestOptions v-if="showTags" :key="eventId" :event-id="eventId" kind="tags" :options="tagOptions" @changed="run(loadTags)" />
    </div>
    <p v-if="roster && !roster.people.length" class="muted">{{ t("eventGuests.noGuests") }}</p>
    <div v-else-if="roster" class="table-scroll">
      <table class="data-table">
        <thead><tr>
          <th scope="col">{{ t("registry.displayName") }}</th>
          <th scope="col">{{ t("registry.linkStatus") }}</th>
          <th scope="col">{{ t("eventGuests.category") }}</th>
          <th scope="col">{{ t("eventGuests.tags.heading") }}</th>
          <th scope="col" v-if="roster.canManage">{{ t("common.actions") }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="row in roster.people" :key="row.participationId">
            <td>{{ row.displayName }}</td>
            <td>{{ t(`registry.participationStatus.${row.status}`) }}</td>
            <td>
              <form v-if="categoryEdit?.row.participationId === row.participationId" @submit.prevent="saveCategory">
                <label for="roster-next-category">{{ t("eventGuests.category") }}</label>
                <select id="roster-next-category" v-model="categoryEdit.selected" :disabled="busy">
                  <option value="">{{ t("eventGuests.categories.unassigned") }}</option>
                  <option v-if="categoryEdit.original && !activeCategories.some((item) => item.categoryId === categoryEdit?.original)"
                    :value="categoryEdit.original" disabled>{{ categoryName(row) }}</option>
                  <option v-for="category in activeCategories" :key="category.categoryId" :value="category.categoryId">
                    {{ category.label }}
                  </option>
                </select>
                <button class="button button-primary" type="submit" :disabled="busy || categoryEdit.selected === categoryEdit.original">
                  {{ t("common.save") }}
                </button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="categoryEdit = null">
                  {{ t("common.cancel") }}
                </button>
              </form>
              <span v-else>{{ categoryName(row) ?? "—" }}</span>
            </td>
            <td>
              <form v-if="tagEdit?.row.participationId === row.participationId" @submit.prevent="saveTags">
                <fieldset class="roster-tags" :disabled="busy">
                  <legend>{{ t("eventGuests.tags.change") }}</legend>
                  <label v-for="tag in tags.filter((item) => !item.retired || row.tagIds.includes(item.tagId))" :key="tag.tagId">
                    <input v-model="tagEdit.selected" type="checkbox" :value="tag.tagId">
                    {{ tag.retired ? t("eventGuests.tags.retiredOption", { label: tag.label }) : tag.label }}
                  </label>
                </fieldset>
                <button class="button button-primary" type="submit" :disabled="busy || !tagSelectionChanged">{{ t("common.save") }}</button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="tagEdit = null">{{ t("common.cancel") }}</button>
              </form>
              <ul v-else-if="row.tagIds.length" class="roster-tag-list">
                <li v-for="tag in tags.filter((item) => row.tagIds.includes(item.tagId))" :key="tag.tagId">{{ tag.label }}</li>
              </ul>
              <span v-else>—</span>
            </td>
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
              <template v-else-if="row.status !== 'cancelled'">
                <button class="button button-secondary" type="button" :disabled="busy || rowEditing" @click="startEdit(row)">
                  {{ t("registry.editParticipation") }}
                </button>
                <button class="button button-secondary" type="button" :disabled="busy || rowEditing"
                  @click="editCategory(row)">
                  {{ t("eventGuests.categories.change") }}
                </button>
                <button v-if="row.tagIds.length || tags.some((tag) => !tag.retired)" class="button button-secondary" type="button"
                  :disabled="busy || rowEditing" @click="editTags(row)">{{ t("eventGuests.tags.change") }}</button>
              </template>
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
.roster-tags { display: grid; gap: 0.25rem; }
.roster-tag-list { margin: 0; padding-inline-start: 1rem; }
</style>
