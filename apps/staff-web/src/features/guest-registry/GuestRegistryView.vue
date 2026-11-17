<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestRegistryDirectory, type GuestRegistryProfile } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string }>();
const { t } = useI18n();
const directory = ref<GuestRegistryDirectory | null>(null);
const profile = ref<GuestRegistryProfile | null>(null);
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
      editing.value = false;
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("registry.failed");
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
  editing.value = false;
  Object.assign(filters, { query: query.value.trim(), archived: archived.value });
  return run(() => load(0));
}

function showProfile(personId: string): Promise<void> {
  editing.value = false;
  return run(async () => {
    profile.value = (await api.getGuestRegistryProfile(personId)).data;
  });
}

function edit(person: GuestRegistryProfile | null): void {
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

function archive(person: GuestRegistryProfile): void {
  if (!window.confirm(t("registry.confirmArchive", { name: `${person.firstName} ${person.lastName}` }))) return;
  void run(async () => {
    await api.archiveGuestRegistryProfile(person.personId, person.revision);
    profile.value = null;
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
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
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
        <button class="button button-secondary" :disabled="busy" @click="profile = null">{{ t("common.close") }}</button>
      </div>
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
