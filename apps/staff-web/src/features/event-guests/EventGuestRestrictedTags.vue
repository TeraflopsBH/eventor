<script setup lang="ts">
import { generatedReferenceCode } from "../../reference-code";
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestRow, type EventGuestTag, type RestrictedEventGuestTags } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; guest?: EventGuestRow }>();
const emit = defineEmits<{ close: []; revision: [revision: number] }>();
const { t } = useI18n();
const data = ref<RestrictedEventGuestTags | null>(null);
const selected = ref<string[]>([]);
const code = ref("");
const label = ref("");
const error = ref("");
const busy = ref(false);
const displayedTags = computed(() => {
  const tags = data.value?.tags ?? [];
  if (!props.guest) return tags;
  const assigned = data.value?.assignedTagIds ?? [];
  return data.value?.canManage ? tags.filter((tag) => !tag.retired || assigned.includes(tag.tagId))
    : tags.filter((tag) => assigned.includes(tag.tagId));
});
const changed = computed(() => {
  const assigned = data.value?.assignedTagIds ?? [];
  return selected.value.length !== assigned.length || selected.value.some((id) => !assigned.includes(id));
});

async function load(): Promise<void> {
  data.value = (await api.listRestrictedEventGuestTags(props.eventId, props.guest?.participationId)).data;
  selected.value = [...data.value.assignedTagIds];
  if (data.value.revision !== null) emit("revision", data.value.revision);
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403, 412].includes(failure.status)) {
      data.value = null;
      selected.value = [];
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.restrictedTags.failed");
  } finally {
    busy.value = false;
  }
}

function create(): void {
  const normalizedCode = code.value.trim().toUpperCase() || (code.value = generatedReferenceCode("TAG"));
  const normalizedLabel = label.value.trim();
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(normalizedCode) || !normalizedLabel) {
    error.value = t("eventGuests.tags.invalid");
    return;
  }
  void run(async () => {
    await api.createRestrictedEventGuestTag(props.eventId, { code: normalizedCode, label: normalizedLabel });
    code.value = "";
    label.value = "";
    await load();
  });
}

function retire(tag: EventGuestTag): void {
  if (!window.confirm(t("eventGuests.tags.confirmRetire", { label: tag.label }))) return;
  void run(async () => {
    await api.retireRestrictedEventGuestTag(props.eventId, tag.tagId);
    await load();
  });
}

function save(): void {
  const guest = props.guest;
  const revision = data.value?.revision;
  if (!guest || revision == null || !changed.value) return;
  void run(async () => {
    const result = await api.setRestrictedEventGuestTags(props.eventId, guest.participationId, selected.value, revision);
    emit("revision", result.data.revision);
    await load();
  });
}

onMounted(() => run(load));
</script>

<template>
  <section class="restricted-event-tags" aria-labelledby="restricted-event-tags-title">
    <div class="restricted-tag-actions">
      <h3 id="restricted-event-tags-title">{{ guest
        ? t("eventGuests.restrictedTags.forGuest", { name: guest.displayName })
        : t("eventGuests.restrictedTags.title") }}</h3>
      <button class="button button-secondary" type="button" @click="emit('close')">{{ t("common.close") }}</button>
    </div>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <button v-if="error && !data" class="button button-secondary" type="button" :disabled="busy" @click="run(load)">
      {{ t("common.refresh") }}
    </button>
    <template v-if="data">
      <form v-if="guest && data.canManage && displayedTags.length" class="restricted-event-tags" @submit.prevent="save">
        <fieldset :disabled="busy" class="restricted-event-tags">
          <legend>{{ t("eventGuests.restrictedTags.assign") }}</legend>
          <label v-for="tag in displayedTags" :key="tag.tagId">
            <input v-model="selected" type="checkbox" :value="tag.tagId">
            {{ tag.retired ? t("eventGuests.tags.retiredOption", { label: tag.label }) : tag.label }}
          </label>
        </fieldset>
        <button class="button button-primary" type="submit" :disabled="busy || !changed">{{ t("common.save") }}</button>
      </form>
      <template v-else>
        <form v-if="!guest && data.canManage" class="restricted-tag-actions" @submit.prevent="create">
          <label>{{ t("eventGuests.restrictedTags.code") }} <input v-model="code" :placeholder="t('common.generatedCode')" maxlength="40" :disabled="busy"></label>
          <label>{{ t("eventGuests.tags.label") }} <input v-model="label" required maxlength="120" :disabled="busy"></label>
          <button class="button button-primary" type="submit" :disabled="busy">{{ t("eventGuests.tags.add") }}</button>
        </form>
        <ul v-if="displayedTags.length">
          <li v-for="tag in displayedTags" :key="tag.tagId">
            {{ tag.label }}<span v-if="!guest"> ({{ tag.code }})</span>
            <span v-if="tag.retired" class="muted"> · {{ t("eventGuests.tags.retired") }}</span>
            <button v-else-if="!guest && data.canManage" class="button button-secondary" type="button" :disabled="busy"
              :aria-label="t('eventGuests.tags.retireNamed', { label: tag.label })" @click="retire(tag)">
              {{ t("eventGuests.tags.retire") }}
            </button>
          </li>
        </ul>
        <p v-else>{{ t("eventGuests.restrictedTags.empty") }}</p>
      </template>
    </template>
  </section>
</template>

<style scoped>
.restricted-event-tags { display: grid; gap: 0.75rem; justify-items: start; }
.restricted-tag-actions { display: flex; gap: 0.75rem; align-items: end; flex-wrap: wrap; }
.restricted-event-tags li button { margin-inline-start: 0.5rem; }
</style>
