<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type OrganizationProfile } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string }>();
const emit = defineEmits<{ saved: [] }>();
const { t } = useI18n();
const profile = ref<OrganizationProfile | null>(null);
const name = ref("");
const operatingProfile = ref<OrganizationProfile["operatingProfile"]>("event_organizer");
const timezone = ref("");
const busy = ref(false);
const error = ref("");
const notice = ref("");
const changed = computed(() => profile.value && (
  name.value.trim() !== profile.value.name || operatingProfile.value !== profile.value.operatingProfile
  || timezone.value.trim() !== profile.value.defaultTimezone
));

function apply(value: OrganizationProfile): void {
  profile.value = value;
  name.value = value.name;
  operatingProfile.value = value.operatingProfile;
  timezone.value = value.defaultTimezone;
}

function showError(failure: unknown): void {
  if (failure instanceof ApiError && [401,403].includes(failure.status)) profile.value = null;
  error.value = failure instanceof ApiError ? formatApiError(failure,t) : t("organizationSettings.failed");
}

async function load(): Promise<void> {
  busy.value = true;
  error.value = "";
  try { apply((await api.getOrganizationProfile(props.organizationId)).data); }
  catch (failure) { showError(failure); }
  finally { busy.value = false; }
}

async function save(): Promise<void> {
  if (busy.value || !profile.value?.canManage || !changed.value) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    apply((await api.updateOrganizationProfile(props.organizationId,{
      name:name.value.trim(),operatingProfile:operatingProfile.value,
      defaultTimezone:timezone.value.trim(),expectedRevision:profile.value.revision,
    })).data);
    notice.value = t("organizationSettings.saved");
    emit("saved");
  } catch (failure) { showError(failure); }
  finally { busy.value = false; }
}

onMounted(load);
</script>

<template>
  <section class="panel" aria-labelledby="organization-settings-heading" :aria-busy="busy">
    <h3 id="organization-settings-heading">{{ t("organizationSettings.title") }}</h3>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <button v-if="!profile && !busy" class="button button-secondary" type="button" @click="load">{{ t("organizationAccess.retry") }}</button>
    <form v-if="profile" class="form-grid" @submit.prevent="save">
      <label>{{ t("organizationSettings.name") }}<input v-model="name" required maxlength="250" :disabled="busy || !profile.canManage"></label>
      <label for="organization-operating-profile">{{ t("organizationSettings.operatingProfile") }}</label>
      <select id="organization-operating-profile" v-model="operatingProfile" :disabled="busy || !profile.canManage">
        <option value="venue_provider">{{ t("organizationSettings.profiles.venue_provider") }}</option>
        <option value="event_organizer">{{ t("organizationSettings.profiles.event_organizer") }}</option>
        <option value="hybrid">{{ t("organizationSettings.profiles.hybrid") }}</option>
      </select>
      <label>{{ t("organizationSettings.timezone") }}
        <input v-model="timezone" required maxlength="100" :disabled="busy || !profile.canManage" aria-describedby="organization-timezone-help">
      </label>
      <p id="organization-timezone-help">{{ t("organizationSettings.timezoneHelp") }}</p>
      <button v-if="profile.canManage" class="button button-primary" type="submit" :disabled="busy || !changed || !name.trim() || !timezone.trim()">
        {{ t("organizationSettings.save") }}
      </button>
    </form>
  </section>
</template>
