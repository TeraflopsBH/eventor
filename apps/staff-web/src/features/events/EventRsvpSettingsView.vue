<script setup lang="ts">
import { onMounted, ref } from "vue";
import { formatApiError } from "../../i18n/api-errors";
import { api, ApiError, type EventRsvpSettings, type RsvpAnswer } from "../../api";
import { sessionLocalTime, zonedLocalDateTimeToIso } from "../../local-date-time";
const props = defineProps<{ eventId: string; eventTitle: string; readOnly: boolean; t: (key: string, params?: Record<string,string|number>) => string }>();
const settings = ref<EventRsvpSettings | null>(null);
const busy = ref(false); const error = ref(""); const notice = ref("");
const answers = ref<RsvpAnswer[]>([]); const deadline = ref(""); const allowChanges = ref(true);
const responseCodes: RsvpAnswer[] = ["accepted", "declined", "tentative"];
function apply(value: EventRsvpSettings): void {
  settings.value = value;
  answers.value = [...(value.policy?.allowedResponses ?? responseCodes)];
  deadline.value = sessionLocalTime(value.policy?.responseDeadline ?? null, value.timezoneName);
  allowChanges.value = value.policy?.responseChangeAllowed ?? true;
}
async function load(): Promise<void> {
  busy.value = true; error.value = ""; notice.value = "";
  try { apply((await api.getEventRsvpSettings(props.eventId)).data); }
  catch (cause) { error.value = cause instanceof ApiError ? formatApiError(cause, props.t) : props.t("common.unexpectedError"); }
  finally { busy.value = false; }
}
async function publish(): Promise<void> {
  if (!settings.value || busy.value || props.readOnly) return;
  error.value = ""; notice.value = "";
  if (!answers.value.length) { error.value = props.t("events.rsvpAnswerRequired"); return; }
  let responseDeadline: string | null = null;
  try {
    const original = settings.value.policy?.responseDeadline ?? null;
    responseDeadline = deadline.value === sessionLocalTime(original, settings.value.timezoneName)
      ? original : deadline.value ? zonedLocalDateTimeToIso(deadline.value, settings.value.timezoneName) : null;
  } catch { error.value = props.t("events.invalidSchedule"); return; }
  if (!window.confirm(props.t("events.rsvpPublishConfirm"))) return;
  busy.value = true;
  try {
    apply((await api.publishEventRsvpSettings(props.eventId, {
      expectedTimezoneName: settings.value.timezoneName,
      expectedRevisionId: settings.value.policy?.revisionId ?? null,
      allowedResponses: responseCodes.filter(code => answers.value.includes(code)),
      responseDeadline, responseChangeAllowed: allowChanges.value,
    })).data);
    notice.value = props.t("events.rsvpPublished");
  } catch (cause) { error.value = cause instanceof ApiError ? formatApiError(cause, props.t) : props.t("common.unexpectedError"); }
  finally { busy.value = false; }
}
onMounted(load);
</script>

<template>
  <section class="event-form" :aria-label="t('events.rsvpSettings')" :aria-busy="busy">
    <h3>{{ t("events.rsvpSettings") }} · {{ eventTitle }}</h3>
    <p>{{ t("events.rsvpSnapshotHelp") }}</p>
    <p v-if="error" role="alert" class="message message-error">{{ error }}</p>
    <p v-if="notice" role="status" class="message">{{ notice }}</p>
    <button type="button" class="button button-secondary" :disabled="busy" @click="load">{{ t("common.refresh") }}</button>
    <form v-if="settings" @submit.prevent="publish">
      <p>{{ settings.policy ? t("events.rsvpRevision", { revision: settings.policy.revisionNumber }) : t("events.rsvpUnconfigured") }}</p>
      <fieldset :disabled="busy || readOnly">
        <legend>{{ t("events.rsvpAllowedAnswers") }}</legend>
        <label v-for="code in responseCodes" :key="code"><input v-model="answers" type="checkbox" :value="code">{{ t(`events.rsvpAnswers.${code}`) }}</label>
      </fieldset>
      <label><span>{{ t("events.rsvpDeadline", { timezone: settings.timezoneName }) }}</span><input v-model="deadline" type="datetime-local" :disabled="busy || readOnly"></label>
      <label><input v-model="allowChanges" type="checkbox" :disabled="busy || readOnly">{{ t("events.rsvpAllowChanges") }}</label>
      <button type="submit" class="button button-primary" :disabled="busy || readOnly">{{ t("events.rsvpPublish") }}</button>
    </form>
  </section>
</template>
