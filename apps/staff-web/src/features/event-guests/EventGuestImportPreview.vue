<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestImportPreview } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string }>();
const { t } = useI18n();
const file = ref<File | null>(null);
const preview = ref<GuestImportPreview | null>(null);
const error = ref("");
const busy = ref(false);

function selectFile(event: Event): void {
  file.value = (event.target as HTMLInputElement).files?.[0] ?? null;
  preview.value = null;
  error.value = "";
}

async function prepare(): Promise<void> {
  const input = file.value;
  if (!input) return;
  if (input.size > 64 * 1024 || !input.name.toLowerCase().endsWith(".csv")) {
    error.value = t("eventGuests.import.invalidFile");
    return;
  }

  error.value = "";
  busy.value = true;
  preview.value = null;
  try {
    let csv: string;
    try {
      csv = new TextDecoder("utf-8", { fatal: true }).decode(await input.arrayBuffer());
    } catch {
      error.value = t("eventGuests.import.invalidFile");
      return;
    }
    const batch = await api.prepareGuestImportPreview(props.eventId, csv);
    preview.value = (await api.getGuestImportPreview(props.eventId, batch.data.batchId)).data;
  } catch (failure) {
    error.value = failure instanceof ApiError
      ? (failure.code === "GUEST_IMPORT_CSV_INVALID" ? t("eventGuests.import.invalidCsv") : formatApiError(failure, t))
      : t("eventGuests.import.failed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section class="guest-import" aria-labelledby="guest-import-heading">
    <h3 id="guest-import-heading">{{ t("eventGuests.import.title") }}</h3>
    <p>{{ t("eventGuests.import.instructions") }}</p>
    <form @submit.prevent="prepare">
      <label for="guest-csv">{{ t("eventGuests.import.file") }}</label>
      <input id="guest-csv" type="file" accept=".csv,text/csv" :disabled="busy" @change="selectFile">
      <button class="button button-primary" type="submit" :disabled="busy || !file">{{ t("eventGuests.import.preview") }}</button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="preview">
      <p role="status">{{ t("eventGuests.import.ready", { count: preview.rows.length }) }}</p>
      <div class="table-scroll">
        <table class="data-table">
          <thead><tr>
            <th scope="col">{{ t("eventGuests.import.row") }}</th>
            <th scope="col">{{ t("registry.firstName") }}</th>
            <th scope="col">{{ t("registry.lastName") }}</th>
            <th scope="col">{{ t("eventGuests.import.review") }}</th>
          </tr></thead>
          <tbody>
            <tr v-for="row in preview.rows" :key="row.rowNumber">
              <td>{{ row.rowNumber }}</td>
              <td>{{ row.names.firstName }}</td>
              <td>{{ row.names.lastName }}</td>
              <td><ul v-if="row.errors.length || row.duplicateCount">
                <li v-for="issue in row.errors" :key="issue">{{ t(`eventGuests.import.issue.${issue}`) }}</li>
                <li v-if="row.duplicateCount">{{ t("eventGuests.import.matches", { count: row.duplicateCount }) }}</li>
              </ul><span v-else>{{ t("eventGuests.import.clear") }}</span></td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>

<style scoped>
.guest-import { display: grid; gap: 0.75rem; margin-top: 1rem; }
.guest-import td { overflow-wrap: anywhere; }
</style>
