<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestCategory } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; categories: EventGuestCategory[] }>();
const emit = defineEmits<{ changed: [] }>();
const { t } = useI18n();
const code = ref("");
const label = ref("");
const busy = ref(false);
const error = ref("");

async function run(command: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await command();
    emit("changed");
  } catch (failure) {
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.categories.failed");
  } finally {
    busy.value = false;
  }
}

function create(): void {
  const normalizedCode = code.value.trim().toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(normalizedCode) || !label.value.trim()) {
    error.value = t("eventGuests.categories.invalid");
    return;
  }
  void run(async () => {
    await api.createEventGuestCategory(props.eventId, { code: normalizedCode, label: label.value.trim() });
    code.value = "";
    label.value = "";
  });
}

function retire(category: EventGuestCategory): void {
  if (!window.confirm(t("eventGuests.categories.confirmRetire", { label: category.label }))) return;
  void run(async () => { await api.retireEventGuestCategory(props.eventId, category.categoryId); });
}
</script>

<template>
  <section class="event-categories" aria-labelledby="guest-categories-heading">
    <h3 id="guest-categories-heading">{{ t("eventGuests.categories.manage") }}</h3>
    <form class="category-form" @submit.prevent="create">
      <label>{{ t("eventGuests.categories.code") }} <input v-model="code" required maxlength="40" :disabled="busy"></label>
      <label>{{ t("eventGuests.categories.label") }} <input v-model="label" required maxlength="120" :disabled="busy"></label>
      <button class="button button-primary" type="submit" :disabled="busy">{{ t("eventGuests.categories.add") }}</button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <ul v-if="categories.length">
      <li v-for="category in categories" :key="category.categoryId">
        <span>{{ category.label }} ({{ category.code }})</span>
        <span v-if="category.retired" class="muted">{{ t("eventGuests.categories.retired") }}</span>
        <button v-else class="button button-secondary" type="button" :disabled="busy"
          :aria-label="t('eventGuests.categories.retireNamed', { label: category.label })" @click="retire(category)">
          {{ t("eventGuests.categories.retire") }}
        </button>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.event-categories { display: grid; gap: 0.75rem; margin-top: 0.75rem; }
.category-form { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
.event-categories li > :not(:first-child) { margin-inline-start: 0.5rem; }
</style>
