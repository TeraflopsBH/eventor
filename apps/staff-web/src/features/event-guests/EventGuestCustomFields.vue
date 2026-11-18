<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestRow, type GuestFieldDefinition, type GuestFieldEntry, type GuestFieldType, type GuestFieldValue } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; guest?: EventGuestRow; canManage: boolean }>();
const emit = defineEmits<{ close: []; revision: [number] }>();
const { t } = useI18n();
const definitions = ref<GuestFieldDefinition[] | null>(null);
const values = ref<{ revision: number; fields: GuestFieldEntry[] } | null>(null);
const fieldTypes = ["text", "integer", "boolean"] as const;
const code = ref("");
const label = ref("");
const valueType = ref<GuestFieldType>("text");
const editingField = ref<GuestFieldEntry | null>(null);
const draft = ref("");
const busy = ref(false);
const error = ref("");

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      definitions.value = null;
      values.value = null;
      editingField.value = null;
      draft.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("eventGuests.fields.failed");
  } finally {
    busy.value = false;
  }
}

async function load(): Promise<void> {
  if (props.guest) {
    values.value = (await api.listGuestFieldValues(props.eventId, props.guest.participationId)).data;
    emit("revision", values.value.revision);
  } else {
    definitions.value = (await api.listGuestFieldDefinitions(props.eventId)).data;
  }
}

function create(): void {
  const normalized = code.value.trim().toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(normalized) || !label.value.trim()) {
    error.value = t("eventGuests.fields.invalidDefinition");
    return;
  }
  void run(async () => {
    await api.createGuestFieldDefinition(props.eventId, { code: normalized, label: label.value.trim(), valueType: valueType.value });
    code.value = "";
    label.value = "";
    await load();
  });
}

function retire(field: GuestFieldDefinition): void {
  if (!window.confirm(t("eventGuests.fields.confirmRetire", { label: field.label }))) return;
  void run(async () => {
    await api.retireGuestFieldDefinition(props.eventId, field.fieldId);
    await load();
  });
}

function edit(field: GuestFieldEntry): void {
  editingField.value = field;
  draft.value = field.value === null ? "" : String(field.value);
}

function write(field: GuestFieldEntry, value: GuestFieldValue): void {
  const guest = props.guest;
  const current = values.value;
  if (!guest || !current) return;
  void run(async () => {
    const { data } = await api.setGuestFieldValue(props.eventId, guest.participationId, field.fieldId,
      { expectedRevision: current.revision, value });
    emit("revision", data.revision);
    editingField.value = null;
    draft.value = "";
    await load();
  });
}

function save(): void {
  const field = editingField.value;
  if (!field) return;
  const text = draft.value.trim();
  let value: GuestFieldValue = text;
  if (text === "") value = null;
  else if (field.valueType === "boolean") value = text === "true";
  else if (field.valueType === "integer") {
    if (!/^-?\d+$/.test(text) || !Number.isSafeInteger(Number(text))) {
      error.value = t("eventGuests.fields.invalidInteger");
      return;
    }
    value = Number(text);
  }
  if (value !== field.value) write(field, value);
  else editingField.value = null;
}

function display(value: GuestFieldValue): string {
  if (value === null) return "—";
  return typeof value === "boolean" ? t(value ? "eventGuests.fields.yes" : "eventGuests.fields.no") : String(value);
}

onMounted(() => run(load));
</script>

<template>
  <section class="guest-custom-fields" aria-labelledby="guest-custom-fields-heading">
    <div class="field-controls">
      <h3 id="guest-custom-fields-heading">
        {{ guest ? t("eventGuests.fields.guestTitle", { name: guest.displayName }) : t("eventGuests.fields.manage") }}
      </h3>
      <button class="button button-secondary" type="button" :disabled="busy" @click="emit('close')">{{ t("common.close") }}</button>
    </div>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <template v-if="guest && values">
      <p v-if="!values.fields.length" class="muted">{{ t("eventGuests.fields.empty") }}</p>
      <ul v-else>
        <li v-for="field in values.fields" :key="field.fieldId">
          <strong>{{ field.label }}</strong> · {{ display(field.value) }}
          <span v-if="field.retired"> · {{ t("eventGuests.fields.retired") }}</span>
          <template v-if="canManage && guest.status !== 'cancelled'">
            <form v-if="editingField?.fieldId === field.fieldId" class="field-controls" @submit.prevent="save">
              <label v-if="field.valueType !== 'boolean'">
                {{ t("eventGuests.fields.value") }}
                <input v-model="draft" :maxlength="field.valueType === 'text' ? 500 : 17"
                  :inputmode="field.valueType === 'integer' ? 'numeric' : 'text'" :disabled="busy">
              </label>
              <div v-else>
                <label for="guest-field-boolean">{{ t("eventGuests.fields.value") }}</label>
                <select id="guest-field-boolean" v-model="draft" :disabled="busy">
                  <option value="">{{ t("eventGuests.fields.unset") }}</option>
                  <option value="true">{{ t("eventGuests.fields.yes") }}</option>
                  <option value="false">{{ t("eventGuests.fields.no") }}</option>
                </select>
              </div>
              <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
              <button class="button button-secondary" type="button" :disabled="busy" @click="editingField = null">{{ t("common.cancel") }}</button>
            </form>
            <button v-else-if="!field.retired" class="button button-secondary" type="button" :disabled="busy"
              :aria-label="t('eventGuests.fields.editNamed', { label: field.label })" @click="edit(field)">{{ t("common.edit") }}</button>
            <button v-else-if="field.value !== null" class="button button-secondary" type="button" :disabled="busy"
              :aria-label="t('eventGuests.fields.clearNamed', { label: field.label })" @click="write(field, null)">{{ t("eventGuests.fields.clear") }}</button>
          </template>
        </li>
      </ul>
    </template>
    <template v-else-if="definitions">
      <form v-if="canManage" class="field-controls" @submit.prevent="create">
        <label>{{ t("eventGuests.fields.code") }} <input v-model="code" maxlength="40" required :disabled="busy"></label>
        <label>{{ t("eventGuests.fields.label") }} <input v-model="label" maxlength="120" required :disabled="busy"></label>
        <div>
          <label for="guest-field-type">{{ t("eventGuests.fields.type") }}</label>
          <select id="guest-field-type" v-model="valueType" :disabled="busy">
            <option v-for="type in fieldTypes" :key="type" :value="type">{{ t(`eventGuests.fields.types.${type}`) }}</option>
          </select>
        </div>
        <button class="button button-primary" type="submit" :disabled="busy">{{ t("eventGuests.fields.add") }}</button>
      </form>
      <p v-if="!definitions.length" class="muted">{{ t("eventGuests.fields.empty") }}</p>
      <ul v-else>
        <li v-for="field in definitions" :key="field.fieldId">
          {{ field.label }} ({{ field.code }}) · {{ t(`eventGuests.fields.types.${field.valueType}`) }}
          <span v-if="field.retired"> · {{ t("eventGuests.fields.retired") }}</span>
          <button v-else-if="canManage" class="button button-secondary" type="button" :disabled="busy"
            :aria-label="t('eventGuests.fields.retireNamed', { label: field.label })" @click="retire(field)">{{ t("eventGuests.fields.retire") }}</button>
        </li>
      </ul>
    </template>
  </section>
</template>

<style scoped>
.guest-custom-fields { display: grid; gap: 0.75rem; }
.field-controls { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
.guest-custom-fields li > button { margin-inline-start: 0.5rem; }
</style>
