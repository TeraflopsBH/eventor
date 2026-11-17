<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type GuestListOption } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; kind: "categories" | "tags" | "groups"; options: GuestListOption[] }>();
const emit = defineEmits<{ changed: [] }>();
const { t } = useI18n();
const message = (key: string) => `eventGuests.${props.kind}.${key}`;
const createOption = { categories: api.createEventGuestCategory, tags: api.createEventGuestTag, groups: api.createEventGuestGroup };
const retireOption = { categories: api.retireEventGuestCategory, tags: api.retireEventGuestTag, groups: api.retireEventGuestGroup };
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
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t(message("failed"));
  } finally {
    busy.value = false;
  }
}

function create(): void {
  const normalizedCode = code.value.trim().toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(normalizedCode) || !label.value.trim()) {
    error.value = t(message("invalid"));
    return;
  }
  void run(async () => {
    const body = { code: normalizedCode, label: label.value.trim() };
    await createOption[props.kind](props.eventId, body);
    code.value = "";
    label.value = "";
  });
}

function retire(option: GuestListOption): void {
  if (!window.confirm(t(message("confirmRetire"), { label: option.label }))) return;
  void run(async () => {
    await retireOption[props.kind](props.eventId, option.id);
  });
}
</script>

<template>
  <section class="guest-options" :aria-labelledby="`guest-${kind}-heading`">
    <h3 :id="`guest-${kind}-heading`">{{ t(message("manage")) }}</h3>
    <form class="option-form" @submit.prevent="create">
      <label>{{ t(message("code")) }} <input v-model="code" required maxlength="40" :disabled="busy"></label>
      <label>{{ t(message("label")) }} <input v-model="label" required maxlength="120" :disabled="busy"></label>
      <button class="button button-primary" type="submit" :disabled="busy">{{ t(message("add")) }}</button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <ul v-if="options.length">
      <li v-for="option in options" :key="option.id">
        <span>{{ option.label }} ({{ option.code }})</span>
        <span v-if="option.retired" class="muted">{{ t(message("retired")) }}</span>
        <button v-else class="button button-secondary" type="button" :disabled="busy"
          :aria-label="t(message('retireNamed'), { label: option.label })" @click="retire(option)">
          {{ t(message("retire")) }}
        </button>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.guest-options { display: grid; gap: 0.75rem; margin-top: 0.75rem; }
.option-form { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
.guest-options li > :not(:first-child) { margin-inline-start: 0.5rem; }
</style>
