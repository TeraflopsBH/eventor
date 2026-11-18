<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestRegistryMergeHistory, type GuestRegistryMergePreview, type GuestRegistryProfile } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string; source: GuestRegistryProfile | null }>();
const emit = defineEmits<{ changed: [] }>();
const { t, locale } = useI18n();
const fullName = (profile: GuestRegistryProfile) => `${profile.firstName} ${profile.lastName}`;
const sourceName = props.source ? fullName(props.source) : "";
const query = ref(Array.from(sourceName).length <= 200 ? sourceName : props.source?.lastName ?? "");
const appliedQuery = ref(query.value);
const candidates = ref<GuestRegistryProfile[] | null>(null);
const preview = ref<GuestRegistryMergePreview | null>(null);
const history = ref<GuestRegistryMergeHistory | null>(null);
const offset = ref(0);
const nextOffset = ref<number | null>(null);
const busy = ref(false);
const error = ref("");
const nameFields = ["firstName", "lastName", "displayName", "preferredName"] as const;

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      candidates.value = null;
      preview.value = null;
      history.value = null;
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("registry.merge.failed");
  } finally {
    busy.value = false;
  }
}

async function load(pageOffset: number): Promise<void> {
  if (props.source) {
    const { data } = await api.searchGuestRegistry(props.organizationId, { query: appliedQuery.value, archived: false, offset: pageOffset });
    candidates.value = data.people.filter(({ personId }) => personId !== props.source?.personId);
    nextOffset.value = data.nextOffset;
  } else {
    const { data } = await api.getGuestRegistryMerges(props.organizationId, pageOffset);
    history.value = data;
    nextOffset.value = data.nextOffset;
  }
  offset.value = pageOffset;
}

function search(): void {
  appliedQuery.value = query.value.trim();
  preview.value = null;
  void run(() => load(0));
}

function review(destination: GuestRegistryProfile): void {
  const source = props.source;
  if (!source) return;
  void run(async () => {
    preview.value = null;
    preview.value = (await api.previewGuestRegistryMerge(source.personId, destination.personId)).data;
  });
}

function merge(): void {
  const resolution = preview.value;
  if (!resolution || resolution.blocker ||
      !window.confirm(t("registry.merge.confirm", { source: fullName(resolution.source), destination: fullName(resolution.destination) }))) return;
  void run(async () => {
    await api.commitGuestRegistryMerge(resolution);
    emit("changed");
  });
}

function restore(entry: GuestRegistryMergeHistory["merges"][number]): void {
  if (!window.confirm(t("registry.merge.confirmRestore", { source: entry.sourceName }))) return;
  void run(async () => {
    await api.restoreGuestRegistryMerge(props.organizationId, entry.mergeId);
    await load(offset.value);
    emit("changed");
  });
}

function formatTime(value: string): string {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

onMounted(() => run(() => load(0)));
</script>

<template>
  <section class="registry-merge" aria-labelledby="registry-merge-heading">
    <h3 id="registry-merge-heading">{{ t(source ? "registry.merge.review" : "registry.merge.history") }}</h3>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <template v-if="source">
      <form @submit.prevent="search">
        <label>{{ t("registry.merge.destinationSearch") }} <input v-model="query" maxlength="200" :disabled="busy"></label>
        <button class="button button-secondary" type="submit" :disabled="busy">{{ t("registry.search") }}</button>
      </form>
      <ul v-if="candidates?.length">
        <li v-for="candidate in candidates" :key="candidate.personId">
          <span>{{ fullName(candidate) }}<template v-if="candidate.displayName"> · {{ candidate.displayName }}</template></span>
          <button class="button button-secondary" type="button" :disabled="busy"
            :aria-label="t('registry.merge.compareNamed', { name: candidate.displayName || fullName(candidate) })" @click="review(candidate)">
            {{ t("registry.merge.compare") }}
          </button>
        </li>
      </ul>
      <p v-else-if="candidates" class="muted">{{ t("registry.merge.noCandidates") }}</p>
      <div v-if="preview" class="table-scroll">
        <table class="data-table">
          <caption>{{ t("registry.merge.comparison") }}</caption>
          <thead><tr><th scope="col">{{ t("registry.merge.field") }}</th>
            <th scope="col">{{ t("registry.merge.source") }}</th>
            <th scope="col">{{ t("registry.merge.destination") }}</th></tr></thead>
          <tbody>
            <tr v-for="field in nameFields" :key="field">
              <th scope="row">{{ t(`registry.${field}`) }}</th>
              <td>{{ preview.source[field] ?? "—" }}</td>
              <td>{{ preview.destination[field] ?? "—" }}</td>
            </tr>
          </tbody>
        </table>
        <p v-if="preview.blocker" role="status">{{ t(`registry.merge.blocker.${preview.blocker}`) }}</p>
        <template v-else>
          <p>{{ t("registry.merge.resolution") }}</p>
          <template v-if="preview.historicalCount">
            <h4>{{ t("registry.merge.historicalEvents") }}</h4>
            <p>{{ t("registry.merge.historicalImpact") }}</p>
            <ul>
              <li v-for="item in preview.historicalEvents" :key="item.eventId">
                {{ item.eventTitle }} ({{ item.eventCode }})
                · {{ t(`events.status.${item.eventStatus}`) }}
                · {{ t(`registry.participationStatus.${item.status}`) }}
              </li>
            </ul>
            <p v-if="preview.historicalCount > preview.historicalEvents.length">
              {{ t("registry.merge.moreHistoricalEvents", { shown: preview.historicalEvents.length, total: preview.historicalCount }) }}
            </p>
          </template>
          <button class="button button-primary" type="button" :disabled="busy" @click="merge">{{ t("registry.merge.commit") }}</button>
        </template>
      </div>
    </template>
    <template v-else-if="history">
      <p v-if="!history.merges.length" class="muted">{{ t("registry.merge.noMerges") }}</p>
      <div v-else class="table-scroll">
        <table class="data-table">
          <thead><tr>
            <th scope="col">{{ t("registry.merge.source") }}</th>
            <th scope="col">{{ t("registry.merge.destination") }}</th>
            <th scope="col">{{ t("registry.merge.when") }}</th>
            <th scope="col">{{ t("common.actions") }}</th>
          </tr></thead>
          <tbody><tr v-for="entry in history.merges" :key="entry.mergeId">
            <td>{{ entry.sourceName }}</td>
            <td>{{ entry.destinationName }}</td>
            <td>{{ formatTime(entry.mergedAt) }}</td>
            <td>
              <span v-if="entry.restoredAt">{{ t("registry.merge.restored", { time: formatTime(entry.restoredAt) }) }}</span>
              <button v-else class="button button-secondary" type="button" :disabled="busy" @click="restore(entry)">
                {{ t("registry.merge.restore") }}
              </button>
            </td>
          </tr></tbody>
        </table>
      </div>
    </template>
    <div v-if="offset > 0 || nextOffset !== null">
      <button class="button button-secondary" type="button" :disabled="busy || offset === 0" @click="run(() => load(Math.max(0, offset - 50)))">
        {{ t("registry.previous") }}
      </button>
      <button class="button button-secondary" type="button" :disabled="busy || nextOffset === null" @click="run(() => load(nextOffset ?? 0))">
        {{ t("registry.next") }}
      </button>
    </div>
  </section>
</template>

<style scoped>
.registry-merge { display: grid; gap: 0.75rem; margin-top: 1rem; }
.registry-merge li > button { margin-inline-start: 0.5rem; }
</style>
