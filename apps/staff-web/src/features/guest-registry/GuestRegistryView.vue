<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import GuestRegistryContacts from "./GuestRegistryContacts.vue";
import GuestRegistryReferences from "./GuestRegistryReferences.vue";
import GuestRegistryMerges from "./GuestRegistryMerges.vue";
import { api, ApiError, type GuestRegistryDirectory, type GuestRegistryHistory, type GuestRegistryProfile, type ManagedParticipationStatus, type RegistryLinkableEvent } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { downloadGuestCsv, downloadGuestXlsx, formatGuestCsv } from "../../guest-export";

const props = defineProps<{ organizationId: string }>();
const { t, locale } = useI18n();
const directory = ref<GuestRegistryDirectory | null>(null);
const profile = ref<GuestRegistryProfile | null>(null);
const history = ref<GuestRegistryHistory | null>(null);
const historyOffset = ref(0);
const editableParticipationStatuses: ManagedParticipationStatus[] = ["eligible", "waitlisted", "ineligible", "withdrawn"];
const editingParticipation = ref<GuestRegistryHistory["participations"][number] | null>(null);
const participationStatus = ref<ManagedParticipationStatus>("eligible");
const linkableEvents = ref<RegistryLinkableEvent[] | null>(null);
const linkEventId = ref("");
const linkStatus = ref<"eligible" | "waitlisted" | "ineligible">("eligible");
const showContacts = ref(false);
const showReferences = ref(false);
const showMergeReview = ref(false);
const showMergeHistory = ref(false);
const busy = ref(false);
const error = ref("");
const editing = ref(false);
const query = ref("");
const archived = ref(false);
const filters = reactive({ query: "", archived: false, offset: 0 });
const form = reactive({ firstName: "", lastName: "", displayName: "", preferredName: "" });

async function run(operation: () => Promise<void>): Promise<void> {
  error.value = "";
  busy.value = true;
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      directory.value = null;
      profile.value = null;
      history.value = null;
      showContacts.value = false;
      showReferences.value = false;
      showMergeReview.value = false;
      showMergeHistory.value = false;
      editingParticipation.value = null;
      linkableEvents.value = null;
      editing.value = false;
    }
    error.value = failure instanceof ApiError && failure.code === "GUEST_REGISTRY_EXPORT_LIMIT"
      ? t("registry.exportLimit")
      : failure instanceof ApiError ? formatApiError(failure, t) : t("registry.failed");
  } finally {
    busy.value = false;
  }
}

async function load(offset: number): Promise<void> {
  const result = await api.searchGuestRegistry(props.organizationId, { ...filters, offset });
  directory.value = result.data;
  filters.offset = offset;
}

function search(): Promise<void> {
  profile.value = null;
  history.value = null;
  showContacts.value = false;
  showReferences.value = false;
  showMergeReview.value = false;
  editingParticipation.value = null;
  linkableEvents.value = null;
  editing.value = false;
  Object.assign(filters, { query: query.value.trim(), archived: archived.value });
  return run(() => load(0));
}

function downloadRegistry(format: "csv" | "xlsx"): Promise<void> {
  return run(async () => {
    const { query, archived } = filters;
    const { data } = await api.exportGuestRegistry(props.organizationId, { query, archived });
    const rows = [
      ["first_name", "last_name", "display_name", "preferred_name", "profile_status"],
      ...data.people.map((person) => [person.firstName, person.lastName, person.displayName, person.preferredName, person.status]),
    ];
    const filename = `guest-registry-${archived ? "archived" : "active"}.${format}`;
    if (format === "csv") {
      downloadGuestCsv(filename, `\uFEFF${formatGuestCsv(rows)}`);
    } else {
      await downloadGuestXlsx(filename, t("navigation.guestRegistry"), rows, [26, 28, 36, 28, 18]);
    }
  });
}

function showProfile(personId: string): Promise<void> {
  history.value = null;
  showContacts.value = false;
  showReferences.value = false;
  showMergeReview.value = false;
  editingParticipation.value = null;
  linkableEvents.value = null;
  editing.value = false;
  return run(async () => {
    profile.value = (await api.getGuestRegistryProfile(personId)).data;
  });
}

function refreshReferenceProfile(personId: string): Promise<void> {
  return run(async () => {
    const { data } = await api.getGuestRegistryProfile(personId);
    if (profile.value?.personId === personId) profile.value = data;
  });
}

function edit(person: GuestRegistryProfile | null): void {
  history.value = null;
  showContacts.value = false;
  showReferences.value = false;
  showMergeReview.value = false;
  editingParticipation.value = null;
  linkableEvents.value = null;
  profile.value = person;
  Object.assign(form, {
    firstName: person?.firstName ?? "", lastName: person?.lastName ?? "",
    displayName: person?.displayName ?? "", preferredName: person?.preferredName ?? "",
  });
  editing.value = true;
}

function save(): Promise<void> {
  const names = {
    firstName: form.firstName.trim(), lastName: form.lastName.trim(),
    displayName: form.displayName.trim() || null, preferredName: form.preferredName.trim() || null,
  };
  return run(async () => {
    const response = profile.value
      ? await api.updateGuestRegistryProfile(profile.value.personId, { ...names, expectedRevision: profile.value.revision })
      : await api.createGuestRegistryProfile(props.organizationId, names);
    editing.value = false;
    profile.value = (await api.getGuestRegistryProfile(response.data.personId)).data;
    await load(filters.offset);
  });
}

function closeProfile(): void {
  profile.value = null;
  history.value = null;
  showContacts.value = false;
  showReferences.value = false;
  showMergeReview.value = false;
  editingParticipation.value = null;
  linkableEvents.value = null;
}

function toggleMergeReview(): void {
  showMergeHistory.value = false;
  showMergeReview.value = !showMergeReview.value;
}

function toggleMergeHistory(): void {
  showMergeReview.value = false;
  showMergeHistory.value = !showMergeHistory.value;
}

function refreshAfterMerge(): Promise<void> {
  if (showMergeReview.value) {
    closeProfile();
    showMergeHistory.value = true;
  }
  return run(() => load(0));
}

function loadHistory(personId: string, offset = 0): Promise<void> {
  editingParticipation.value = null;
  return run(async () => {
    history.value = (await api.getGuestRegistryHistory(personId, offset)).data;
    historyOffset.value = offset;
  });
}

function formatTime(value: string): string {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function showEventLink(personId: string): Promise<void> {
  return run(async () => {
    linkableEvents.value = (await api.getRegistryLinkableEvents(personId)).data;
    linkEventId.value = "";
    linkStatus.value = "eligible";
  });
}

function linkToEvent(person: GuestRegistryProfile): Promise<void> {
  return run(async () => {
    await api.linkGuestRegistryProfile(linkEventId.value, person.personId, linkStatus.value);
    linkableEvents.value = null;
    history.value = (await api.getGuestRegistryHistory(person.personId, 0)).data;
    historyOffset.value = 0;
  });
}

function startParticipationEdit(item: GuestRegistryHistory["participations"][number]): void {
  if (item.status === "cancelled") return;
  editingParticipation.value = item;
  participationStatus.value = item.status;
}

function saveParticipation(personId: string, item: GuestRegistryHistory["participations"][number]): Promise<void> {
  return run(async () => {
    await api.updateGuestParticipationStatus(item.eventId, item.participationId, participationStatus.value, item.revision);
    editingParticipation.value = null;
    history.value = (await api.getGuestRegistryHistory(personId, historyOffset.value)).data;
  });
}

function archive(person: GuestRegistryProfile): void {
  if (!window.confirm(t("registry.confirmArchive", { name: `${person.firstName} ${person.lastName}` }))) return;
  void run(async () => {
    await api.archiveGuestRegistryProfile(person.personId, person.revision);
    profile.value = null;
    history.value = null;
    showContacts.value = false;
    showReferences.value = false;
    editingParticipation.value = null;
    linkableEvents.value = null;
    await load(filters.offset);
  });
}

onMounted(search);
</script>

<template>
  <section class="panel registry">
    <h2>{{ t("navigation.guestRegistry") }}</h2>
    <form class="registry-toolbar" @submit.prevent="search">
      <label>{{ t("registry.nameSearch") }}<input v-model="query" maxlength="200"></label>
      <label><input v-model="archived" type="checkbox"> {{ t("registry.archived") }}</label>
      <button class="button button-secondary" type="submit" :disabled="busy || editing">{{ t("registry.search") }}</button>
      <button v-if="directory?.canManage" class="button button-primary" type="button" :disabled="busy" @click="edit(null)">
        {{ t("registry.add") }}
      </button>
      <template v-if="directory?.canExport">
        <button class="button button-secondary" type="button" :disabled="busy || editing" @click="downloadRegistry('csv')">
          {{ t("registry.exportCsv") }}
        </button>
        <button class="button button-secondary" type="button" :disabled="busy || editing" @click="downloadRegistry('xlsx')">
          {{ t("registry.exportXlsx") }}
        </button>
      </template>
      <button v-if="directory?.canMerge" class="button button-secondary" type="button" :disabled="busy || editing"
        :aria-expanded="showMergeHistory" @click="toggleMergeHistory">{{ t("registry.merge.history") }}</button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <GuestRegistryMerges v-if="showMergeHistory && directory?.canMerge" :organization-id="organizationId" :source="null"
      @changed="refreshAfterMerge" />
    <form v-if="editing" class="registry-form" @submit.prevent="save">
      <h3>{{ profile ? t("registry.edit") : t("registry.add") }}</h3>
      <label>{{ t("registry.firstName") }}<input v-model="form.firstName" required maxlength="200"></label>
      <label>{{ t("registry.lastName") }}<input v-model="form.lastName" required maxlength="200"></label>
      <label>{{ t("registry.displayName") }}<input v-model="form.displayName" maxlength="250"></label>
      <label>{{ t("registry.preferredName") }}<input v-model="form.preferredName" maxlength="200"></label>
      <div class="registry-toolbar">
        <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
        <button class="button button-secondary" type="button" :disabled="busy" @click="editing = false">{{ t("common.cancel") }}</button>
      </div>
    </form>
    <section v-else-if="profile" class="registry-form" aria-labelledby="registry-profile-heading">
      <h3 id="registry-profile-heading">{{ profile.firstName }} {{ profile.lastName }}</h3>
      <dl>
        <dt v-if="profile.displayName">{{ t("registry.displayName") }}</dt><dd v-if="profile.displayName">{{ profile.displayName }}</dd>
        <dt v-if="profile.preferredName">{{ t("registry.preferredName") }}</dt><dd v-if="profile.preferredName">{{ profile.preferredName }}</dd>
      </dl>
      <div class="registry-toolbar">
        <button v-if="directory?.canManage && profile.status === 'active'" class="button button-secondary" :disabled="busy" @click="edit(profile)">{{ t("common.edit") }}</button>
        <button v-if="directory?.canManage && profile.status === 'active'" class="button button-danger" :disabled="busy" @click="archive(profile)">{{ t("registry.archive") }}</button>
        <button v-if="profile.status === 'active'" class="button button-secondary" :disabled="busy" @click="showEventLink(profile.personId)">{{ t("registry.addToEvent") }}</button>
        <button v-if="directory?.canMerge && profile.status === 'active'" class="button button-secondary" type="button"
          :disabled="busy" :aria-expanded="showMergeReview" @click="toggleMergeReview">{{ t("registry.merge.review") }}</button>
        <button class="button button-secondary" :disabled="busy" :aria-expanded="showContacts" @click="showContacts = !showContacts">
          {{ t("registry.contacts.title") }}
        </button>
        <button class="button button-secondary" :disabled="busy" :aria-expanded="showReferences" @click="showReferences = !showReferences">
          {{ t("registry.references.title") }}
        </button>
        <button class="button button-secondary" :disabled="busy" @click="loadHistory(profile.personId)">{{ t("registry.history") }}</button>
        <button class="button button-secondary" :disabled="busy" @click="closeProfile">{{ t("common.close") }}</button>
      </div>
      <GuestRegistryMerges v-if="showMergeReview && directory?.canMerge" :key="`merge-${profile.personId}`" :organization-id="organizationId" :source="profile"
        @changed="refreshAfterMerge" />
      <GuestRegistryContacts v-if="showContacts" :key="`contacts-${profile.personId}`" :person-id="profile.personId" :active="profile.status === 'active'" />
      <GuestRegistryReferences v-if="showReferences" :key="`references-${profile.personId}`" :person-id="profile.personId" :active="profile.status === 'active'"
        @changed="refreshReferenceProfile(profile.personId)" />
      <form v-if="linkableEvents?.length" class="registry-form" @submit.prevent="linkToEvent(profile)">
        <div>
          <label for="registry-link-event">{{ t("registry.event") }}</label>
          <select id="registry-link-event" v-model="linkEventId" required>
            <option value="" disabled>{{ t("registry.chooseEvent") }}</option>
            <option v-for="event in linkableEvents" :key="event.eventId" :value="event.eventId">
              {{ event.title }} ({{ event.eventCode }})
            </option>
          </select>
        </div>
        <div>
          <label for="registry-link-status">{{ t("registry.linkStatus") }}</label>
          <select id="registry-link-status" v-model="linkStatus">
            <option value="eligible">{{ t("registry.participationStatus.eligible") }}</option>
            <option value="waitlisted">{{ t("registry.participationStatus.waitlisted") }}</option>
            <option value="ineligible">{{ t("registry.participationStatus.ineligible") }}</option>
          </select>
        </div>
        <div class="registry-toolbar">
          <button class="button button-primary" type="submit" :disabled="busy">{{ t("registry.addToEvent") }}</button>
          <button class="button button-secondary" type="button" :disabled="busy" @click="linkableEvents = null">{{ t("common.cancel") }}</button>
        </div>
      </form>
      <p v-else-if="linkableEvents" class="muted">{{ t("registry.noLinkableEvents") }}</p>
      <template v-if="history">
        <h4>{{ t("registry.participationHistory") }}</h4>
        <ul v-if="history.participations.length">
          <li v-for="item in history.participations" :key="item.participationId">
            <strong>{{ item.eventTitle }}</strong> ({{ item.eventCode }})
            · {{ t(`registry.participationStatus.${item.status}`) }}
            · {{ t(`events.status.${item.eventStatus}`) }}
            <span v-if="item.fromMergedProfile"> · {{ t("registry.merge.fromMergedProfile") }}</span>
            <time v-if="item.eventStartsAt" :datetime="item.eventStartsAt"> · {{ formatTime(item.eventStartsAt) }}</time>
            <button
              v-if="item.canManage && profile.status === 'active' && !editingParticipation"
              class="button button-secondary" type="button" :disabled="busy"
              @click="startParticipationEdit(item)"
            >{{ t("registry.editParticipation") }}</button>
            <form v-if="editingParticipation?.participationId === item.participationId"
              class="registry-form" @submit.prevent="saveParticipation(profile.personId, editingParticipation)">
              <div>
                <label for="registry-edit-participation-status">{{ t("registry.linkStatus") }}</label>
                <select id="registry-edit-participation-status" v-model="participationStatus">
                  <option v-for="option in editableParticipationStatuses" :key="option" :value="option">
                    {{ t(`registry.participationStatus.${option}`) }}
                  </option>
                </select>
              </div>
              <p v-if="participationStatus !== 'eligible'" class="muted">{{ t("registry.revokeBeforeChange") }}</p>
              <div class="registry-toolbar">
                <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
                <button class="button button-secondary" type="button" :disabled="busy" @click="editingParticipation = null">{{ t("common.cancel") }}</button>
              </div>
            </form>
          </li>
        </ul>
        <p v-else class="muted">{{ t("registry.noParticipations") }}</p>
        <h4>{{ t("registry.changeHistory") }}</h4>
        <ul v-if="history.changes.length">
          <li v-for="change in history.changes" :key="change.auditId">
            {{ t(`registry.historyAction.${change.action.split(".").at(-1)}`) }}
            · <time :datetime="change.at">{{ formatTime(change.at) }}</time>
          </li>
        </ul>
        <p v-else class="muted">{{ t("registry.noChanges") }}</p>
        <div v-if="historyOffset > 0 || history.nextOffset !== null" class="registry-toolbar">
          <button class="button button-secondary" :disabled="busy || historyOffset === 0" @click="loadHistory(profile.personId, Math.max(0, historyOffset - 50))">{{ t("registry.previous") }}</button>
          <button class="button button-secondary" :disabled="busy || history.nextOffset === null" @click="loadHistory(profile.personId, history.nextOffset ?? 0)">{{ t("registry.next") }}</button>
        </div>
      </template>
    </section>
    <p v-if="directory && !directory.people.length" class="muted">{{ t("registry.empty") }}</p>
    <div v-else-if="directory" class="table-scroll">
      <table class="data-table">
        <thead><tr><th scope="col">{{ t("registry.lastName") }}</th><th scope="col">{{ t("registry.firstName") }}</th><th scope="col">{{ t("registry.displayName") }}</th><th scope="col">{{ t("common.actions") }}</th></tr></thead>
        <tbody><tr v-for="person in directory.people" :key="person.personId">
          <td>{{ person.lastName }}</td><td>{{ person.firstName }}</td><td>{{ person.displayName }}</td>
          <td><button class="button button-secondary" :disabled="busy || editing" @click="showProfile(person.personId)">{{ t("registry.view") }}</button></td>
        </tr></tbody>
      </table>
    </div>
    <div v-if="directory && (filters.offset > 0 || directory.nextOffset !== null)" class="registry-toolbar">
      <button class="button button-secondary" :disabled="busy || editing || filters.offset === 0" @click="run(() => load(Math.max(0, filters.offset - 50)))">{{ t("registry.previous") }}</button>
      <button class="button button-secondary" :disabled="busy || editing || directory.nextOffset === null" @click="run(() => load(directory?.nextOffset ?? 0))">{{ t("registry.next") }}</button>
    </div>
  </section>
</template>

<style scoped>
.registry, .registry-form { display: grid; gap: 1rem; }
.registry-toolbar { display: flex; align-items: end; flex-wrap: wrap; gap: 0.75rem; }
.registry-form { max-width: 34rem; }
</style>
