<script setup lang="ts">
import { formatDateTime } from "../../i18n/format";
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, guestRegistryRelationshipKinds, type GuestRegistryProfile,
  type GuestRegistryRelationship, type GuestRegistryRelationshipKind, type GuestRegistryRelationships } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string; personId: string; active: boolean }>();
const { t, locale } = useI18n();
const directory = ref<GuestRegistryRelationships | null>(null);
const candidates = ref<GuestRegistryProfile[] | null>(null);
const query = ref("");
const relatedPersonId = ref("");
const kind = ref<GuestRegistryRelationshipKind>("family");
const directionality = ref<"mutual" | "directed">("mutual");
const busy = ref(false);
const error = ref("");

async function load(): Promise<void> {
  directory.value = (await api.getGuestRegistryRelationships(props.personId)).data;
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      directory.value = null;
      candidates.value = null;
      relatedPersonId.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("registry.relationships.failed");
  } finally {
    busy.value = false;
  }
}

function search(): void {
  const name = query.value.trim();
  if (!name) return;
  relatedPersonId.value = "";
  void run(async () => {
    const { data } = await api.searchGuestRegistry(props.organizationId, { query: name, archived: false, offset: 0 });
    candidates.value = data.people.filter(({ personId, status }) => personId !== props.personId && status === "active");
  });
}

function save(): void {
  if (!relatedPersonId.value) return;
  void run(async () => {
    await api.createGuestRegistryRelationship(props.personId, {
      relatedPersonId: relatedPersonId.value, kind: kind.value, directionality: directionality.value,
    });
    relatedPersonId.value = "";
    query.value = "";
    candidates.value = null;
    await load();
  });
}

function end(relationship: GuestRegistryRelationship): void {
  if (!window.confirm(t("registry.relationships.confirmEnd", { name: relationship.relatedDisplayName }))) return;
  void run(async () => {
    await api.endGuestRegistryRelationship(props.personId, relationship.relationshipId);
    await load();
  });
}

function personLabel(profile: GuestRegistryProfile): string {
  const fullName = `${profile.firstName} ${profile.lastName}`;
  return profile.displayName && profile.displayName !== fullName ? `${fullName} · ${profile.displayName}` : fullName;
}

function formatTime(value: string): string {
  return formatDateTime(value, locale.value, { dateStyle: "medium" });
}

onMounted(() => run(load));
</script>

<template>
  <section class="registry-relationships" aria-labelledby="registry-relationships-title">
    <h4 id="registry-relationships-title">{{ t("registry.relationships.title") }}</h4>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <template v-if="directory">
      <p v-if="!directory.relationships.length">{{ t("registry.relationships.empty") }}</p>
      <ul v-else>
        <li v-for="relationship in directory.relationships" :key="relationship.relationshipId">
          <strong>{{ relationship.relatedDisplayName }}</strong>
          · {{ t(`registry.relationships.kind.${relationship.kind}`) }}
          · {{ t(`registry.relationships.direction.${relationship.direction}`) }}
          <span v-if="relationship.relatedStatus !== 'active'">
            · {{ t(`registry.relationships.state.${relationship.relatedStatus}`) }}
          </span>
          <span v-if="relationship.endedAt">
            · {{ t("registry.relationships.ended", { date: formatTime(relationship.endedAt) }) }}
          </span>
          <button v-else-if="directory.canManage" type="button" class="button button-secondary" :disabled="busy"
            :aria-label="t('registry.relationships.endNamed', { name: relationship.relatedDisplayName })" @click="end(relationship)">
            {{ t("registry.relationships.end") }}
          </button>
        </li>
      </ul>
      <template v-if="active && directory.canManage">
        <form class="relationship-fields" @submit.prevent="search">
          <label for="registry-relationship-query">{{ t("registry.relationships.searchLabel") }}</label>
          <input id="registry-relationship-query" v-model="query" required maxlength="200" :disabled="busy"
            @input="candidates = null; relatedPersonId = ''">
          <button class="button button-secondary" type="submit" :disabled="busy">{{ t("registry.search") }}</button>
        </form>
        <p v-if="candidates?.length === 0">{{ t("registry.relationships.noMatches") }}</p>
        <form v-else-if="candidates" class="relationship-fields" @submit.prevent="save">
          <div>
            <label for="registry-related-person">{{ t("registry.relationships.relatedPerson") }}</label>
            <select id="registry-related-person" v-model="relatedPersonId" required :disabled="busy">
              <option value="" disabled>{{ t("registry.relationships.choosePerson") }}</option>
              <option v-for="profile in candidates" :key="profile.personId" :value="profile.personId">{{ personLabel(profile) }}</option>
            </select>
          </div>
          <div>
            <label for="registry-relationship-kind">{{ t("registry.relationships.relationshipKind") }}</label>
            <select id="registry-relationship-kind" v-model="kind" :disabled="busy">
              <option v-for="choice in guestRegistryRelationshipKinds" :key="choice" :value="choice">
                {{ t(`registry.relationships.kind.${choice}`) }}
              </option>
            </select>
          </div>
          <div>
            <label for="registry-relationship-direction">{{ t("registry.relationships.relationshipDirection") }}</label>
            <select id="registry-relationship-direction" v-model="directionality" :disabled="busy">
              <option value="mutual">{{ t("registry.relationships.direction.mutual") }}</option>
              <option value="directed">{{ t("registry.relationships.direction.outgoing") }}</option>
            </select>
          </div>
          <button class="button button-primary" type="submit" :disabled="busy || !relatedPersonId">
            {{ t("registry.relationships.add") }}
          </button>
        </form>
      </template>
    </template>
  </section>
</template>

<style scoped>
.registry-relationships { display: grid; gap: 0.75rem; }
.relationship-fields { display: flex; flex-wrap: wrap; align-items: end; gap: 0.5rem; }
.registry-relationships li button { margin-inline-start: 0.5rem; }
</style>
