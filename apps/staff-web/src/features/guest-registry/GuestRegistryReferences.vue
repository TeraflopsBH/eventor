<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestRegistryReference, type GuestRegistryReferences } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ personId: string; active: boolean }>();
const emit = defineEmits<{ changed: [] }>();
const { t } = useI18n();
const directory = ref<GuestRegistryReferences | null>(null);
const editor = ref<{ referenceId: string | null; source: string; value: string } | null>(null);
const busy = ref(false);
const error = ref("");

async function fetchReferences(): Promise<void> {
  directory.value = (await api.getGuestRegistryReferences(props.personId)).data;
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      directory.value = null;
      editor.value = null;
    }
    if (failure instanceof ApiError && failure.status === 412) {
      directory.value = null;
      editor.value = null;
      error.value = t("registry.references.stale");
    } else {
      error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("registry.references.failed");
    }
  } finally {
    busy.value = false;
  }
}

function edit(reference?: GuestRegistryReference): void {
  editor.value = reference ? { ...reference } : { referenceId: null, source: "", value: "" };
}

function save(): void {
  const current = directory.value;
  if (!editor.value || !current) return;
  const { referenceId } = editor.value;
  const source = editor.value.source.trim();
  const value = editor.value.value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$/.test(source) || !/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/.test(value)) {
    error.value = t("registry.references.invalid");
    return;
  }
  void run(async () => {
    const body = { source, value, expectedRevision: current.profileRevision };
    await (referenceId
      ? api.updateGuestRegistryReference(props.personId, referenceId, body)
      : api.createGuestRegistryReference(props.personId, body));
    emit("changed");
    editor.value = null;
    await fetchReferences();
  });
}

function remove(reference: GuestRegistryReference): void {
  const current = directory.value;
  if (!current || !window.confirm(t("registry.references.confirmRemove", { source: reference.source }))) return;
  void run(async () => {
    await api.removeGuestRegistryReference(props.personId, reference.referenceId, current.profileRevision);
    emit("changed");
    await fetchReferences();
  });
}

onMounted(() => run(fetchReferences));
</script>

<template>
  <section class="registry-references" aria-labelledby="registry-references-heading">
    <h4 id="registry-references-heading">{{ t("registry.references.title") }}</h4>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <button v-if="!directory && error" class="button button-secondary" type="button" :disabled="busy" @click="run(fetchReferences)">
      {{ t("registry.references.reload") }}
    </button>
    <p v-if="directory && !directory.references.length" class="muted">{{ t("registry.references.empty") }}</p>
    <div v-else-if="directory" class="table-scroll">
      <table class="data-table">
        <thead><tr>
          <th scope="col">{{ t("registry.references.source") }}</th>
          <th scope="col">{{ t("registry.references.value") }}</th>
          <th v-if="active && directory.canManage" scope="col">{{ t("common.actions") }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="reference in directory.references" :key="reference.referenceId">
            <td>{{ reference.source }}</td>
            <td>{{ reference.value }}</td>
            <td v-if="active && directory.canManage">
              <button class="button button-secondary" type="button" :disabled="busy || !!editor" @click="edit(reference)">{{ t("common.edit") }}</button>
              <button class="button button-secondary" type="button" :disabled="busy || !!editor" @click="remove(reference)">{{ t("registry.references.remove") }}</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <button v-if="active && directory?.canManage && !editor" class="button button-primary" type="button" :disabled="busy" @click="edit()">
      {{ t("registry.references.add") }}
    </button>
    <form v-if="editor" class="registry-references" @submit.prevent="save">
      <div>
        <label for="registry-reference-source">{{ t("registry.references.source") }}</label>
        <input id="registry-reference-source" v-model="editor.source" required maxlength="40" :disabled="busy">
      </div>
      <div>
        <label for="registry-reference-value">{{ t("registry.references.value") }}</label>
        <input id="registry-reference-value" v-model="editor.value" required maxlength="128" :disabled="busy">
      </div>
      <div class="reference-actions">
        <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
        <button class="button button-secondary" type="button" :disabled="busy" @click="editor = null">{{ t("common.cancel") }}</button>
      </div>
    </form>
  </section>
</template>

<style scoped>
.registry-references { display: grid; gap: 0.75rem; }
.reference-actions { display: flex; gap: 0.5rem; }
</style>
