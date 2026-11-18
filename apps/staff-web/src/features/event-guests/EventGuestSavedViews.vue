<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestSavedView, type EventGuestViewFilters } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; filters: EventGuestViewFilters; disabled: boolean }>();
const emit = defineEmits<{ apply: [EventGuestViewFilters] }>();
const { t } = useI18n();
const views = ref<EventGuestSavedView[]>([]);
const selectedId = ref("");
const selected = computed(() => views.value.find(({ viewId }) => viewId === selectedId.value));
const name = ref("");
const busy = ref(false);
const error = ref("");

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      views.value = [];
      selectedId.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.savedViews.failed");
  } finally {
    busy.value = false;
  }
}

async function load(): Promise<void> {
  views.value = (await api.listEventGuestSavedViews(props.eventId)).data;
  if (!selected.value) selectedId.value = "";
}

function save(): void {
  const label = name.value.trim();
  if (!label || props.disabled) return;
  void run(async () => {
    const { data } = await api.createEventGuestSavedView(props.eventId, label, props.filters);
    name.value = "";
    selectedId.value = data.viewId;
    await load();
  });
}

function apply(): void {
  if (selected.value && !props.disabled) emit("apply", selected.value);
}

function deleteView(): void {
  const view = selected.value;
  if (!view || props.disabled || !window.confirm(t("eventGuests.savedViews.confirmDelete", { label: view.label }))) return;
  void run(async () => {
    await api.deleteEventGuestSavedView(props.eventId, view.viewId);
    await load();
  });
}

onMounted(() => run(load));
</script>

<template>
  <section class="saved-views" aria-labelledby="guest-saved-views-heading">
    <h3 id="guest-saved-views-heading">{{ t("eventGuests.savedViews.title") }}</h3>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <div v-if="views.length" class="saved-view-controls">
      <div>
        <label for="guest-saved-view">{{ t("eventGuests.savedViews.choose") }}</label>
        <select id="guest-saved-view" v-model="selectedId" :disabled="disabled || busy">
          <option value="">{{ t("eventGuests.savedViews.placeholder") }}</option>
          <option v-for="view in views" :key="view.viewId" :value="view.viewId">{{ view.label }}</option>
        </select>
      </div>
      <button class="button button-secondary" type="button" :disabled="disabled || busy || !selected" @click="apply">
        {{ t("eventGuests.savedViews.apply") }}
      </button>
      <button class="button button-secondary" type="button" :disabled="disabled || busy || !selected" @click="deleteView">
        {{ t("eventGuests.savedViews.remove") }}
      </button>
    </div>
    <form class="saved-view-controls" @submit.prevent="save">
      <label>{{ t("eventGuests.savedViews.name") }} <input v-model="name" maxlength="80" required :disabled="disabled || busy"></label>
      <button class="button button-primary" type="submit" :disabled="disabled || busy || !name.trim()">{{ t("eventGuests.savedViews.save") }}</button>
    </form>
  </section>
</template>

<style scoped>
.saved-views { display: grid; gap: 0.75rem; margin-top: 0.75rem; }
.saved-view-controls { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
</style>
