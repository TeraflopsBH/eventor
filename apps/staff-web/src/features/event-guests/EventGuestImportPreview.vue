<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestImportCommit, type GuestImportPreview } from "../../api";
import { formatApiError } from "../../i18n/api-errors";
import { downloadGuestCsv, formatGuestCsv } from "../../guest-export";

const props = defineProps<{ eventId: string }>();
const emit = defineEmits<{ committed: [] }>();
const { t } = useI18n();
const file = ref<File | null>(null);
const isWorkbook = computed(() => file.value?.name.toLowerCase().endsWith(".xlsx") ?? false);
const workbook = ref<{ xlsx: string; sheets: { index: number; name: string }[] } | null>(null);
const sheetIndex = ref(1);
const headerRow = ref(1);
const preview = ref<GuestImportPreview | null>(null);
const error = ref("");
const committed = ref<GuestImportCommit | null>(null);
const selected = ref<Record<number, string>>({});
const cleanCount = computed(() => preview.value?.rows.filter((row) => !row.errors.length && !row.duplicateCount).length ?? 0);
const reuse = computed(() => (preview.value?.rows ?? []).flatMap(({ rowNumber, matches }) => {
  const match = matches.find(({ personId }) => personId === selected.value[rowNumber]);
  return match ? [{ rowNumber, personId: match.personId, expectedRevision: match.revision }] : [];
}));
const importCount = computed(() => cleanCount.value + reuse.value.length);
const busy = ref(false);

function clearPreview(): void {
  preview.value = null;
  selected.value = {};
  committed.value = null;
  error.value = "";
}

function selectFile(event: Event): void {
  file.value = (event.target as HTMLInputElement).files?.[0] ?? null;
  workbook.value = null;
  sheetIndex.value = 1;
  headerRow.value = 1;
  clearPreview();
}

async function encodeWorkbook(input: File): Promise<string> {
  const bytes = new Uint8Array(await input.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x4000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x4000));
  }
  return btoa(binary);
}

async function prepare(): Promise<void> {
  const input = file.value;
  if (!input) return;
  const xlsxFile = isWorkbook.value;
  const sizeLimit = xlsxFile ? 256 * 1024 : 64 * 1024;
  if (input.size > sizeLimit || input.size === 0 || (!xlsxFile && !input.name.toLowerCase().endsWith(".csv"))) {
    error.value = t("eventGuests.import.invalidFile");
    return;
  }

  clearPreview();
  busy.value = true;
  try {
    let batchId: string;
    if (xlsxFile) {
      if (!workbook.value) {
        const xlsx = await encodeWorkbook(input);
        const { data } = await api.inspectGuestWorkbook(props.eventId, xlsx);
        workbook.value = { xlsx, sheets: data.sheets };
        sheetIndex.value = data.sheets[0]!.index;
        return;
      }
      const { data } = await api.prepareGuestWorkbookPreview(props.eventId, workbook.value.xlsx, sheetIndex.value, headerRow.value);
      batchId = data.batchId;
    } else {
      let csv: string;
      try {
        csv = new TextDecoder("utf-8", { fatal: true }).decode(await input.arrayBuffer());
      } catch {
        error.value = t("eventGuests.import.invalidFile");
        return;
      }
      const { data } = await api.prepareGuestImportPreview(props.eventId, csv);
      batchId = data.batchId;
    }
    preview.value = (await api.getGuestImportPreview(props.eventId, batchId)).data;
  } catch (failure) {
    if (failure instanceof ApiError && failure.code === "GUEST_IMPORT_XLSX_INVALID") {
      error.value = t("eventGuests.import.invalidWorkbook");
    } else if (failure instanceof ApiError && failure.code === "GUEST_IMPORT_CSV_INVALID") {
      error.value = t("eventGuests.import.invalidCsv");
    } else {
      error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.import.failed");
    }
  } finally {
    busy.value = false;
  }
}
async function commit(): Promise<void> {
  const batch = preview.value;
  if (!batch || !importCount.value || !window.confirm(t("eventGuests.import.confirmCommit", {
    created: cleanCount.value, reused: reuse.value.length,
  }))) return;
  busy.value = true;
  error.value = "";
  try {
    committed.value = (await api.commitGuestImport(props.eventId, batch.batchId, reuse.value)).data;
    emit("committed");
  } catch (failure) {
    error.value = failure instanceof ApiError
      ? (failure.status === 412 ? t("eventGuests.import.refreshPreview") : formatApiError(failure, t))
      : t("eventGuests.import.commitFailed");
  } finally {
    busy.value = false;
  }
}

async function downloadReport(): Promise<void> {
  if (!preview.value) return;
  busy.value = true;
  error.value = "";
  try {
    const { data: report } = await api.getGuestImportReport(props.eventId, preview.value.batchId);
    const csv = formatGuestCsv([
      ["preview_row", "outcome", "issues", "possible_registry_matches"],
      ...report.rows.map((row) => [row.rowNumber, row.outcome, row.errors.join("|"), row.duplicateCount]),
    ]);
    downloadGuestCsv(`guest-import-${report.state === "ready" ? "preview" : "result"}-${report.batchId}.csv`, csv);
  } catch (failure) {
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.import.reportFailed");
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
      <label for="guest-import-file">{{ t("eventGuests.import.file") }}</label>
      <input id="guest-import-file" type="file" accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        :disabled="busy" @change="selectFile">
      <template v-if="workbook">
        <label for="guest-import-sheet">{{ t("eventGuests.import.worksheet") }}</label>
        <select id="guest-import-sheet" v-model.number="sheetIndex" :disabled="busy" @change="clearPreview">
          <option v-for="sheet in workbook.sheets" :key="sheet.index" :value="sheet.index">{{ sheet.name }}</option>
        </select>
        <label for="guest-import-header">{{ t("eventGuests.import.headerRow") }}</label>
        <input id="guest-import-header" v-model.number="headerRow" type="number" min="1" max="1048575" required
          :disabled="busy" @input="clearPreview">
      </template>
      <button class="button button-primary" type="submit" :disabled="busy || !file">
        {{ t(isWorkbook && !workbook ? "eventGuests.import.chooseWorksheet" : "eventGuests.import.preview") }}
      </button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="preview">
      <p v-if="committed" role="status">{{ t("eventGuests.import.committed", { imported: committed.importedCount, skipped: committed.skippedCount }) }}</p>
      <template v-else>
        <p role="status">{{ t("eventGuests.import.ready", { count: preview.rows.length }) }}</p>
      </template>
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
              </ul><span v-else>{{ t("eventGuests.import.clear") }}</span>
                <label v-if="!committed && row.matches.length">
                  {{ t("eventGuests.import.reuse", { row: row.rowNumber }) }}
                  <select :value="selected[row.rowNumber] ?? ''" :disabled="busy"
                    @change="selected[row.rowNumber] = ($event.target as HTMLSelectElement).value">
                    <option value="">{{ t("eventGuests.import.skip") }}</option>
                    <option v-for="match in row.matches" :key="match.personId" :value="match.personId">
                      {{ [...new Set([match.name, match.displayName, match.preferredName].filter(Boolean))].join(" · ") }}
                    </option>
                  </select>
                </label>
                <p v-else-if="!committed && row.duplicateCount && !row.errors.length" class="muted">
                  {{ t("eventGuests.import.noLinkableMatches") }}
                </p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <template v-if="!committed">
        <button v-if="importCount" class="button button-primary" type="button" :disabled="busy" @click="commit">
          {{ t("eventGuests.import.commit", { count: importCount }) }}
        </button>
        <p v-else class="muted">{{ t("eventGuests.import.noCleanRows") }}</p>
      </template>
      <div>
        <button class="button button-secondary" type="button" :disabled="busy" @click="downloadReport">
          {{ t("eventGuests.import.downloadReport") }}
        </button>
      </div>
    </template>
  </section>
</template>

<style scoped>
.guest-import { display: grid; gap: 0.75rem; margin-top: 1rem; }
.guest-import td { overflow-wrap: anywhere; }
</style>
