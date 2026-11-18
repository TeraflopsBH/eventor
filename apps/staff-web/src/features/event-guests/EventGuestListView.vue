<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import EventGuestImportPreview from "./EventGuestImportPreview.vue";
import EventGuestOptions from "./EventGuestOptions.vue";
import EventGuestRelationships from "./EventGuestRelationships.vue";
import EventGuestCustomFields from "./EventGuestCustomFields.vue";
import { api, ApiError, type EventGuestCategory, type EventGuestGroup, type EventGuestList, type EventGuestRow, type EventGuestTag, type EventGuestWorkspace, type ManagedParticipationStatus } from "../../api";
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
const nameInput = ref("");
const nameFilter = ref("");
const statuses: ManagedParticipationStatus[] = ["eligible", "waitlisted", "ineligible", "withdrawn"];
const editing = ref<EventGuestRow | null>(null);
const relationshipGuest = ref<EventGuestRow | null>(null);
const fieldPanel = ref<EventGuestRow | "definitions" | null>(null);
const nextStatus = ref<ManagedParticipationStatus>("eligible");
const busy = ref(false);
const showImport = ref(false);
const showCategories = ref(false);
const showTags = ref(false);
const showGroups = ref(false);
const categories = ref<EventGuestCategory[]>([]);
const tags = ref<EventGuestTag[]>([]);
const groups = ref<EventGuestGroup[]>([]);
const activeCategories = computed(() => categories.value.filter((category) => !category.retired));
const categoryNames = computed(() => new Map(categories.value.map((category) => [category.categoryId, category.label])));
const categoryOptions = computed(() => categories.value.map(({ categoryId, ...option }) => ({ id: categoryId, ...option })));
const membershipKinds = ["tags", "groups"] as const;
type MembershipKind = typeof membershipKinds[number];
const membershipOptions = computed(() => ({
  tags: tags.value.map(({ tagId, ...option }) => ({ id: tagId, ...option })),
  groups: groups.value.map(({ groupId, ...option }) => ({ id: groupId, ...option })),
}));
const categoryEdit = ref<{ row: EventGuestRow; original: string; selected: string } | null>(null);
const membershipEdit = ref<{ row: EventGuestRow; kind: MembershipKind; selected: string[] } | null>(null);
const membershipChanged = computed(() => {
  const edit = membershipEdit.value;
  if (!edit) return false;
  const original = membershipIds(edit.row, edit.kind);
  return edit.selected.length !== original.length || edit.selected.some((id) => !original.includes(id));
});
const rowEditing = computed(() => !!(editing.value || categoryEdit.value || membershipEdit.value));
const selectedGuests = ref<string[]>([]);
const bulkCategory = ref<string | null>(null);
const bulkResult = ref<{ processedCount: number; updatedCount: number } | null>(null);
const selectableGuests = computed(() => (roster.value?.people ?? []).filter((row) => row.status !== "cancelled"));
const allGuestsSelected = computed(() => selectableGuests.value.length > 0
  && selectedGuests.value.length === selectableGuests.value.length);
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
      relationshipGuest.value = null;
      fieldPanel.value = null;
      categories.value = [];
      tags.value = [];
      groups.value = [];
      categoryEdit.value = null;
      membershipEdit.value = null;
    }
    error.value = failure instanceof ApiError && failure.code === "GUEST_ROSTER_EXPORT_LIMIT"
      ? t("eventGuests.exportLimit")
      : failure instanceof ApiError ? formatApiError(failure, t) : t("registry.failed");
  } finally {
    busy.value = false;
  }
}

async function loadPage(pageOffset: number): Promise<void> {
  selectedGuests.value = [];
  bulkCategory.value = null;
  editing.value = null;
  relationshipGuest.value = null;
  fieldPanel.value = null;
  categoryEdit.value = null;
  membershipEdit.value = null;
  if (!eventId.value) return;
  roster.value = (await api.getEventGuestList(eventId.value, pageOffset, status.value, categoryFilter.value, nameFilter.value)).data;
  offset.value = pageOffset;
}

async function loadCategories(): Promise<void> {
  categories.value = (await api.listEventGuestCategories(eventId.value)).data;
}

async function loadTags(): Promise<void> {
  tags.value = (await api.listEventGuestTags(eventId.value)).data;
}

async function loadGroups(): Promise<void> {
  groups.value = (await api.listEventGuestGroups(eventId.value)).data;
}

function chooseEvent(): void {
  selectedGuests.value = [];
  bulkCategory.value = null;
  bulkResult.value = null;
  showImport.value = false;
  showCategories.value = false;
  showTags.value = false;
  showGroups.value = false;
  categories.value = [];
  tags.value = [];
  groups.value = [];
  status.value = "";
  categoryFilter.value = "";
  nameInput.value = "";
  nameFilter.value = "";
  roster.value = null;
  relationshipGuest.value = null;
  fieldPanel.value = null;
  void run(async () => {
    if (!eventId.value) return;
    const [page, catalogue, tagList, groupList] = await Promise.all([
      api.getEventGuestList(eventId.value, 0, status.value), api.listEventGuestCategories(eventId.value),
      api.listEventGuestTags(eventId.value), api.listEventGuestGroups(eventId.value),
    ]);
    editing.value = null;
    categoryEdit.value = null;
    membershipEdit.value = null;
    roster.value = page.data;
    categories.value = catalogue.data;
    tags.value = tagList.data;
    groups.value = groupList.data;
    offset.value = 0;
  });
}

function applyFilters(): void {
  bulkResult.value = null;
  roster.value = null;
  void run(() => loadPage(0));
}

function togglePageSelection(): void {
  bulkResult.value = null;
  selectedGuests.value = allGuestsSelected.value ? [] : selectableGuests.value.map((row) => row.participationId);
}

function saveBulkCategory(): void {
  const category = bulkCategory.value;
  const selected = new Set(selectedGuests.value);
  const guests = selectableGuests.value.filter((row) => selected.has(row.participationId))
    .map((row) => ({ participationId: row.participationId, expectedRevision: row.revision }));
  if (category === null || guests.length === 0) return;
  const label = category ? categoryNames.value.get(category) : t("eventGuests.categories.unassigned");
  if (!label || !window.confirm(t("eventGuests.bulk.confirmCategory", { count: guests.length, label }))) return;
  void run(async () => {
    bulkResult.value = (await api.setEventGuestBulkCategory(eventId.value, category || null, guests)).data;
    await loadPage(offset.value);
  });
}

function applyNameSearch(): void {
  nameFilter.value = nameInput.value.trim();
  applyFilters();
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

function toggleRelationships(row: EventGuestRow): void {
  fieldPanel.value = null;
  relationshipGuest.value = relationshipGuest.value?.participationId === row.participationId ? null : row;
}

function showFields(target: EventGuestRow | "definitions"): void {
  relationshipGuest.value = null;
  fieldPanel.value = fieldPanel.value === target ? null : target;
}

function updateFieldRevision(revision: number): void {
  if (fieldPanel.value && fieldPanel.value !== "definitions") {
    fieldPanel.value.revision = Math.max(fieldPanel.value.revision, revision);
  }
}

function saveCategory(): Promise<void> {
  const edit = categoryEdit.value;
  if (!edit || edit.selected === edit.original) return Promise.resolve();
  return run(async () => {
    await api.setEventGuestCategory(eventId.value, edit.row.participationId, edit.selected || null, edit.row.revision);
    await loadPage(offset.value);
  });
}

function membershipIds(row: EventGuestRow, kind: MembershipKind): string[] {
  return kind === "tags" ? row.tagIds : row.groupIds;
}

function editMemberships(row: EventGuestRow, kind: MembershipKind): void {
  membershipEdit.value = { row, kind, selected: [...membershipIds(row, kind)] };
}

function saveMemberships(): Promise<void> {
  const edit = membershipEdit.value;
  if (!edit || !membershipChanged.value) return Promise.resolve();
  const command = edit.kind === "tags" ? api.setEventGuestTags : api.setEventGuestGroups;
  return run(async () => {
    await command(eventId.value, edit.row.participationId, edit.selected, edit.row.revision);
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
    const { data } = await api.getEventGuestExport(eventId.value, status.value, category, nameFilter.value);
    const rows = [
      ["event_display_name", "participation_status", "category_code"],
      ...data.people.map((guest) => [guest.displayName, guest.status, guest.categoryCode]),
    ];
    const categoryCode = categories.value.find((item) => item.categoryId === category)?.code ?? category;
    const suffix = categoryCode ? `-${categoryCode}` : "";
    const nameSuffix = nameFilter.value ? "-search" : "";
    const filename = `event-guests-${eventId.value}-${status.value || "all"}${suffix}${nameSuffix}.${format}`;
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
      <form v-if="eventId" class="guest-list-controls" @submit.prevent="applyNameSearch">
        <div>
          <label for="roster-name-search">{{ t("registry.nameSearch") }}</label>
          <input id="roster-name-search" v-model="nameInput" type="search" maxlength="200" :disabled="busy">
        </div>
        <button class="button button-secondary" type="submit" :disabled="busy">{{ t("registry.search") }}</button>
      </form>
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
      <EventGuestOptions v-if="showTags" :key="eventId" :event-id="eventId" kind="tags" :options="membershipOptions.tags" @changed="run(loadTags)" />
    </div>
    <div v-if="roster?.canManage">
      <button class="button button-secondary" type="button" :disabled="busy" :aria-expanded="showGroups" @click="showGroups = !showGroups">
        {{ t("eventGuests.groups.manage") }}
      </button>
      <EventGuestOptions v-if="showGroups" :key="eventId" :event-id="eventId" kind="groups" :options="membershipOptions.groups"
        @changed="run(loadGroups)" />
    </div>
    <div v-if="roster?.canViewCustomFields">
      <button class="button button-secondary" type="button" :disabled="busy || rowEditing"
        :aria-expanded="fieldPanel === 'definitions'" @click="showFields('definitions')">{{ t("eventGuests.fields.manage") }}</button>
    </div>
    <EventGuestCustomFields v-if="roster?.canViewCustomFields && fieldPanel"
      :key="fieldPanel === 'definitions' ? eventId : fieldPanel.participationId" :event-id="eventId"
      :guest="fieldPanel === 'definitions' ? undefined : fieldPanel" :can-manage="roster.canManage"
      @close="fieldPanel = null" @revision="updateFieldRevision" />
    <EventGuestRelationships v-if="roster?.canViewRelationships && relationshipGuest" :key="relationshipGuest.participationId"
      :event-id="eventId" :guest="relationshipGuest" :can-manage="roster.canManage" @close="relationshipGuest = null" />
    <form v-if="roster?.canManage && selectedGuests.length" class="guest-list-controls" @submit.prevent="saveBulkCategory">
      <p>{{ t("eventGuests.bulk.selected", { count: selectedGuests.length }) }}</p>
      <div>
        <label for="roster-bulk-category">{{ t("eventGuests.bulk.category") }}</label>
        <select id="roster-bulk-category" v-model="bulkCategory" :disabled="busy || rowEditing">
          <option :value="null" disabled>{{ t("eventGuests.bulk.chooseCategory") }}</option>
          <option value="">{{ t("eventGuests.categories.unassigned") }}</option>
          <option v-for="category in activeCategories" :key="category.categoryId" :value="category.categoryId">{{ category.label }}</option>
        </select>
      </div>
      <button class="button button-primary" type="submit" :disabled="busy || rowEditing || bulkCategory === null">{{ t("eventGuests.bulk.apply") }}</button>
    </form>
    <p v-if="bulkResult" role="status">{{ t("eventGuests.bulk.result", { updated: bulkResult.updatedCount, count: bulkResult.processedCount }) }}</p>
    <p v-if="roster && !roster.people.length" class="muted">{{ t("eventGuests.noGuests") }}</p>
    <div v-else-if="roster" class="table-scroll">
      <table class="data-table">
        <thead><tr>
          <th v-if="roster.canManage" scope="col">
            <input type="checkbox" :aria-label="t('eventGuests.bulk.selectPage')" :checked="allGuestsSelected"
              :indeterminate="selectedGuests.length > 0 && !allGuestsSelected" :disabled="busy || rowEditing || !selectableGuests.length"
              @change="togglePageSelection">
          </th>
          <th scope="col">{{ t("registry.displayName") }}</th>
          <th scope="col">{{ t("registry.linkStatus") }}</th>
          <th scope="col">{{ t("eventGuests.category") }}</th>
          <th v-for="kind in membershipKinds" :key="kind" scope="col">{{ t(`eventGuests.${kind}.heading`) }}</th>
          <th scope="col" v-if="roster.canManage || roster.canViewRelationships || roster.canViewCustomFields">{{ t("common.actions") }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="row in roster.people" :key="row.participationId">
            <td v-if="roster.canManage">
              <input v-if="row.status !== 'cancelled'" v-model="selectedGuests" type="checkbox" :value="row.participationId"
                :aria-label="t('eventGuests.bulk.selectGuest', { name: row.displayName })" :disabled="busy || rowEditing" @change="bulkResult = null">
            </td>
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
            <td v-for="kind in membershipKinds" :key="kind">
              <form v-if="membershipEdit?.row.participationId === row.participationId && membershipEdit.kind === kind"
                @submit.prevent="saveMemberships">
                <fieldset class="roster-memberships" :disabled="busy">
                  <legend>{{ t(`eventGuests.${kind}.change`) }}</legend>
                  <label v-for="option in membershipOptions[kind].filter((item) => !item.retired || membershipIds(row, kind).includes(item.id))"
                    :key="option.id">
                    <input v-model="membershipEdit.selected" type="checkbox" :value="option.id">
                    {{ option.retired ? t(`eventGuests.${kind}.retiredOption`, { label: option.label }) : option.label }}
                  </label>
                </fieldset>
                <button class="button button-primary" type="submit" :disabled="busy || !membershipChanged">{{ t("common.save") }}</button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="membershipEdit = null">{{ t("common.cancel") }}</button>
              </form>
              <ul v-else-if="membershipIds(row, kind).length" class="roster-membership-list">
                <li v-for="option in membershipOptions[kind].filter((item) => membershipIds(row, kind).includes(item.id))"
                  :key="option.id">{{ option.label }}</li>
              </ul>
              <span v-else>—</span>
            </td>
            <td v-if="roster.canManage || roster.canViewRelationships || roster.canViewCustomFields">
              <form v-if="editing?.participationId === row.participationId" @submit.prevent="save">
                <label for="roster-next-status">{{ t("registry.linkStatus") }}</label>
                <select id="roster-next-status" v-model="nextStatus">
                  <option v-for="option in statuses" :key="option" :value="option">{{ t(`registry.participationStatus.${option}`) }}</option>
                </select>
                <p v-if="nextStatus !== 'eligible'" class="muted">{{ t("registry.revokeBeforeChange") }}</p>
                <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="editing = null">{{ t("common.cancel") }}</button>
              </form>
              <template v-else-if="roster.canManage && row.status !== 'cancelled'">
                <button class="button button-secondary" type="button" :disabled="busy || rowEditing" @click="startEdit(row)">
                  {{ t("registry.editParticipation") }}
                </button>
                <button class="button button-secondary" type="button" :disabled="busy || rowEditing"
                  @click="editCategory(row)">
                  {{ t("eventGuests.categories.change") }}
                </button>
                <template v-for="kind in membershipKinds" :key="kind">
                  <button v-if="membershipIds(row, kind).length || membershipOptions[kind].some((option) => !option.retired)"
                    class="button button-secondary" type="button" :disabled="busy || rowEditing" @click="editMemberships(row, kind)">
                    {{ t(`eventGuests.${kind}.change`) }}
                  </button>
                </template>
              </template>
              <button v-if="roster.canViewRelationships" class="button button-secondary" type="button" :disabled="busy || rowEditing"
                :aria-expanded="relationshipGuest?.participationId === row.participationId" @click="toggleRelationships(row)">
                {{ t("eventGuests.relationships.open") }}
              </button>
              <button v-if="roster.canViewCustomFields" class="button button-secondary" type="button" :disabled="busy || rowEditing"
                :aria-expanded="fieldPanel === row" @click="showFields(row)">{{ t("eventGuests.fields.open") }}</button>
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
.roster-memberships { display: grid; gap: 0.25rem; }
.roster-membership-list { margin: 0; padding-inline-start: 1rem; }
</style>
