<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type EventGuestGroup, type GuestGroupPlacementRule,
  type GuestGroupPlacementRuleInput, type GuestGroupPlacementRules } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ eventId: string; groups: EventGuestGroup[] }>();
const { t } = useI18n();
const data = ref<GuestGroupPlacementRules | null>(null);
const busy = ref(false);
const error = ref("");
const groupsById = computed(() => new Map(props.groups.map((group) => [group.groupId, group])));
const activeGroups = computed(() => props.groups.filter((group) => !group.retired));
const form = reactive<GuestGroupPlacementRuleInput>({
  firstGroupId: "", secondGroupId: "", scope: "table", condition: "together", priority: "preferred",
});
const validGroups = computed(() => form.firstGroupId !== form.secondGroupId
  && groupsById.value.get(form.firstGroupId)?.retired === false && groupsById.value.get(form.secondGroupId)?.retired === false);
const message = (key: string) => `eventGuests.groupRules.${key}`;

async function load(): Promise<void> {
  data.value = (await api.listGuestGroupPlacementRules(props.eventId)).data;
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) data.value = null;
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t(message("failed"));
  } finally {
    busy.value = false;
  }
}

function save(): void {
  if (!validGroups.value) return;
  void run(async () => {
    await api.createGuestGroupPlacementRule(props.eventId, { ...form });
    form.firstGroupId = "";
    form.secondGroupId = "";
    await load();
  });
}

function retire(rule: GuestGroupPlacementRule): void {
  if (!window.confirm(t(message("confirmRetire")))) return;
  void run(async () => {
    await api.retireGuestGroupPlacementRule(props.eventId, rule.ruleId);
    await load();
  });
}

onMounted(() => run(load));
</script>

<template>
  <section class="group-placement-rules" aria-labelledby="group-placement-rules-heading">
    <h3 id="group-placement-rules-heading">{{ t(message("title")) }}</h3>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="data">
      <form v-if="data.canManage && activeGroups.length >= 2" class="group-rule-form" @submit.prevent="save">
        <div>
          <label for="group-rule-first">{{ t(message("firstGroup")) }}</label>
          <select id="group-rule-first" v-model="form.firstGroupId" required :disabled="busy">
            <option value="" disabled>{{ t(message("chooseGroup")) }}</option>
            <option v-for="group in activeGroups" :key="group.groupId" :value="group.groupId" :disabled="group.groupId === form.secondGroupId">
              {{ group.label }} ({{ group.code }})
            </option>
          </select>
        </div>
        <div>
          <label for="group-rule-second">{{ t(message("secondGroup")) }}</label>
          <select id="group-rule-second" v-model="form.secondGroupId" required :disabled="busy">
            <option value="" disabled>{{ t(message("chooseGroup")) }}</option>
            <option v-for="group in activeGroups" :key="group.groupId" :value="group.groupId" :disabled="group.groupId === form.firstGroupId">
              {{ group.label }} ({{ group.code }})
            </option>
          </select>
        </div>
        <div>
          <label for="group-rule-condition">{{ t(message("condition")) }}</label>
          <select id="group-rule-condition" v-model="form.condition" :disabled="busy">
            <option value="together">{{ t(message("conditions.together")) }}</option>
            <option value="apart">{{ t(message("conditions.apart")) }}</option>
          </select>
        </div>
        <div>
          <label for="group-rule-scope">{{ t(message("scope")) }}</label>
          <select id="group-rule-scope" v-model="form.scope" :disabled="busy">
            <option v-for="scope in ['table', 'zone', 'room']" :key="scope" :value="scope">{{ t(message(`scopes.${scope}`)) }}</option>
          </select>
        </div>
        <div>
          <label for="group-rule-priority">{{ t(message("priority")) }}</label>
          <select id="group-rule-priority" v-model="form.priority" :disabled="busy">
            <option value="preferred">{{ t(message("priorities.preferred")) }}</option>
            <option value="required">{{ t(message("priorities.required")) }}</option>
          </select>
        </div>
        <button class="button button-primary" type="submit" :disabled="busy || !validGroups">{{ t(message("add")) }}</button>
      </form>
      <p v-if="!data.rules.length">{{ t(message("empty")) }}</p>
      <ul v-else>
        <li v-for="rule in data.rules" :key="rule.ruleId">
          <strong>{{ groupsById.get(rule.firstGroupId)?.label }} · {{ groupsById.get(rule.secondGroupId)?.label }}</strong>
          · {{ t(message(`conditions.${rule.condition}`)) }}
          · {{ t(message(`scopes.${rule.scope}`)) }}
          · {{ t(message(`priorities.${rule.priority}`)) }}
          <span v-if="rule.retiredAt">· {{ t(message("retired")) }}</span>
          <span v-else-if="!rule.applicable || groupsById.get(rule.firstGroupId)?.retired || groupsById.get(rule.secondGroupId)?.retired">
            · {{ t(message("groupRetired")) }}
          </span>
          <button v-if="data.canManage && !rule.retiredAt" class="button button-secondary" type="button" :disabled="busy"
            @click="retire(rule)">{{ t(message("retire")) }}</button>
        </li>
      </ul>
    </template>
  </section>
</template>

<style scoped>
.group-placement-rules { display: grid; gap: 0.75rem; }
.group-rule-form { display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; }
.group-rule-form > div { display: grid; gap: 0.25rem; }
.group-placement-rules li button { margin-inline-start: 0.5rem; }
</style>
