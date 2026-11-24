<script setup lang="ts">
import { generatedReferenceCode } from "../../reference-code";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, guestGroupKinds, guestGroupPlacementPreferences, type EventGuestGroup, type GuestGroupPlacementPreference, type GuestListOption } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

type Option = GuestListOption & Partial<Pick<EventGuestGroup, "kind" | "parentGroupId" | "revision" | "placementPreference" | "expectedSize">>;
const props = defineProps<{ eventId: string; kind: "categories" | "tags" | "groups"; options: Option[] }>();
const emit = defineEmits<{ changed: [] }>();
const { t, te } = useI18n();
const message = (key: string) => `eventGuests.${props.kind}.${key}`;
const createOption = { categories: api.createEventGuestCategory, tags: api.createEventGuestTag };
const retireOption = { categories: api.retireEventGuestCategory, tags: api.retireEventGuestTag, groups: api.retireEventGuestGroup };
const code = ref("");
const label = ref("");
const groupKind = ref("custom");
const parentGroupId = ref("");
const placementPreference = ref<GuestGroupPlacementPreference | "">("");
const expectedSize = ref<number | "">("");
const editing = ref<Option | null>(null);
const byId = computed(() => new Map(props.options.map((option) => [option.id, option])));
const parentOptions = computed(() => props.options.filter((option) => {
  if (option.retired && option.id !== editing.value?.parentGroupId) return false;
  const visited = new Set<string>();
  let ancestor: Option | undefined = option;
  while (ancestor) {
    if (ancestor.id === editing.value?.id || visited.has(ancestor.id)) return false;
    visited.add(ancestor.id);
    ancestor = ancestor.parentGroupId ? byId.value.get(ancestor.parentGroupId) : undefined;
  }
  return true;
}));
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

function groupKindLabel(kind: string): string {
  const key = message(`kinds.${kind}`);
  return te(key) ? t(key) : kind;
}

function resetForm(): void {
  editing.value = null;
  code.value = "";
  label.value = "";
  groupKind.value = "custom";
  parentGroupId.value = "";
  placementPreference.value = "";
  expectedSize.value = "";
  error.value = "";
}

function beginEdit(option: Option): void {
  editing.value = option;
  code.value = option.code;
  label.value = option.label;
  groupKind.value = option.kind ?? "custom";
  parentGroupId.value = option.parentGroupId ?? "";
  placementPreference.value = option.placementPreference ?? "";
  expectedSize.value = option.expectedSize ?? "";
  error.value = "";
}

function save(): void {
  const normalizedCode = code.value.trim().toUpperCase() || (code.value = generatedReferenceCode({ categories: "CAT", tags: "TAG", groups: "GRP" }[props.kind]));
  const normalizedLabel = label.value.trim();
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(normalizedCode) || !normalizedLabel) {
    error.value = t(message("invalid"));
    return;
  }
  const option = editing.value;
  void run(async () => {
    if (props.kind === "groups") {
      const kind = guestGroupKinds.find((value) => value === groupKind.value);
      const details = {
        label: normalizedLabel, ...(kind ? { kind } : {}), parentGroupId: parentGroupId.value || null,
        placementPreference: placementPreference.value || null, expectedSize: expectedSize.value === "" ? null : expectedSize.value,
      };
      if (option?.revision !== undefined) {
        await api.updateEventGuestGroup(props.eventId, option.id, { ...details, expectedRevision: option.revision });
      } else {
        await api.createEventGuestGroup(props.eventId, { code: normalizedCode, ...details });
      }
    } else {
      await createOption[props.kind](props.eventId, { code: normalizedCode, label: normalizedLabel });
    }
    resetForm();
  });
}

function retire(option: GuestListOption): void {
  if (!window.confirm(t(message("confirmRetire"), { label: option.label }))) return;
  void run(async () => {
    await retireOption[props.kind](props.eventId, option.id);
    if (editing.value?.id === option.id) resetForm();
  });
}
</script>

<template>
  <section class="guest-options" :aria-labelledby="`guest-${kind}-heading`">
    <h3 :id="`guest-${kind}-heading`">{{ t(message("manage")) }}</h3>
    <form class="option-form" @submit.prevent="save">
      <label>{{ t(message("code")) }} <input v-model="code" :placeholder="t('common.generatedCode')" maxlength="40" :disabled="busy || !!editing"></label>
      <label>{{ t(message("label")) }} <input v-model="label" required maxlength="120" :disabled="busy"></label>
      <template v-if="kind === 'groups'">
        <div class="group-metadata-field">
          <label for="event-guest-group-kind">{{ t(message("groupKind")) }}</label>
          <select id="event-guest-group-kind" v-model="groupKind" :disabled="busy">
            <option v-if="!guestGroupKinds.some((value) => value === groupKind)" :value="groupKind" disabled>{{ groupKindLabel(groupKind) }}</option>
            <option v-for="value in guestGroupKinds" :key="value" :value="value">{{ groupKindLabel(value) }}</option>
          </select>
        </div>
        <div class="group-metadata-field">
          <label for="event-guest-parent-group">{{ t(message("parentGroup")) }}</label>
          <select id="event-guest-parent-group" v-model="parentGroupId" :disabled="busy">
            <option value="">{{ t(message("noParentGroup")) }}</option>
            <option v-for="parent in parentOptions" :key="parent.id" :value="parent.id">
              {{ parent.retired ? t(message("retiredOption"), { label: parent.label }) : parent.label }}
            </option>
          </select>
        </div>
        <div class="group-metadata-field">
          <label for="guest-group-placement">{{ t(message("placementPreference")) }}</label>
          <select id="guest-group-placement" v-model="placementPreference" :disabled="busy">
            <option value="">{{ t(message("noPlacementPreference")) }}</option>
            <option v-for="preference in guestGroupPlacementPreferences" :key="preference" :value="preference">
              {{ t(message(`placement.${preference}`)) }}
            </option>
          </select>
        </div>
        <div class="group-metadata-field">
          <label for="guest-group-expected-size">{{ t(message("expectedSize")) }}</label>
          <input id="guest-group-expected-size" v-model.number="expectedSize" type="number" min="1" max="2147483647" :disabled="busy">
        </div>
      </template>
      <button class="button button-primary" type="submit" :disabled="busy">{{ t(editing ? "common.save" : message("add")) }}</button>
      <button v-if="editing" class="button button-secondary" type="button" :disabled="busy" @click="resetForm">{{ t("common.cancel") }}</button>
    </form>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <ul v-if="options.length">
      <li v-for="option in options" :key="option.id">
        <span>{{ option.label }} ({{ option.code }})</span>
        <span v-if="option.kind && option.kind !== 'custom'">· {{ groupKindLabel(option.kind) }}</span>
        <span v-if="option.parentGroupId">· {{ t(message("parentGroupLabel"), { parent: byId.get(option.parentGroupId)?.label ?? "" }) }}</span>
        <span v-if="option.placementPreference">· {{ t(message(`placement.${option.placementPreference}`)) }}</span>
        <span v-if="option.expectedSize">· {{ t(message("plannedSize"), { count: option.expectedSize }) }}</span>
        <button v-if="kind === 'groups' && !option.retired" class="button button-secondary" type="button" :disabled="busy"
          :aria-label="t(message('editNamed'), { label: option.label })" @click="beginEdit(option)">{{ t(message("edit")) }}</button>
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
.group-metadata-field { display: grid; gap: 0.25rem; }
.guest-options li > :not(:first-child) { margin-inline-start: 0.5rem; }
</style>
