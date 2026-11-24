<script setup lang="ts">
import { formatDateTime } from "../../i18n/format";
import { onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type RegistryContact, type RegistryContactConsent, type RegistryContactDirectory, type RegistryContactVerification } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ personId: string; active: boolean }>();
const { t, locale } = useI18n();
const directory = ref<RegistryContactDirectory | null>(null);
const busy = ref(false);
const error = ref("");
const editorOpen = ref(false);
const editing = ref<RegistryContact | null>(null);
const verifying = ref<RegistryContact | null>(null);
const verificationMethod = ref<RegistryContactVerification>("in_person");
const consents: RegistryContactConsent[] = ["unknown", "permitted", "restricted", "withdrawn"];
const form = reactive<{ kind: RegistryContact["kind"]; value: string; consent: RegistryContactConsent; primary: boolean }>({
  kind: "email", value: "", consent: "unknown", primary: false,
});

async function load(): Promise<void> {
  directory.value = (await api.getGuestRegistryContacts(props.personId)).data;
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  try {
    await operation();
  } catch (failure) {
    if (failure instanceof ApiError && [401, 403].includes(failure.status)) {
      directory.value = null;
      closeEditor();
      verifying.value = null;
    }
    error.value = failure instanceof ApiError ? formatApiError(failure, t) : t("registry.contacts.failed");
  } finally {
    busy.value = false;
  }
}

function openEditor(contact: RegistryContact | null): void {
  editing.value = contact;
  Object.assign(form, {
    kind: contact?.kind ?? "email", value: "",
    consent: contact?.consent ?? "unknown", primary: contact?.primary ?? false,
  });
  editorOpen.value = true;
}

function closeEditor(): void {
  form.value = "";
  editing.value = null;
  editorOpen.value = false;
}

function save(): Promise<void> {
  const preferences = { consent: form.consent, primary: form.primary && form.consent !== "withdrawn" };
  return run(async () => {
    if (editing.value) {
      await api.updateGuestRegistryContact(props.personId, editing.value.contactId, {
        ...preferences, expectedRevision: editing.value.revision,
      });
    } else {
      await api.createGuestRegistryContact(props.personId, { ...preferences, value: form.value.trim(), kind: form.kind });
    }
    closeEditor();
    await load();
  });
}

function openVerification(contact: RegistryContact): void {
  verifying.value = contact;
  verificationMethod.value = "in_person";
}

function recordVerification(): Promise<void> {
  const contact = verifying.value;
  if (!contact) return Promise.resolve();
  return run(async () => {
    await api.setGuestRegistryContactVerification(props.personId, contact.contactId, contact.revision, verificationMethod.value);
    verifying.value = null;
    await load();
  });
}

function revokeVerification(contact: RegistryContact): void {
  if (!window.confirm(t("registry.contacts.confirmRevokeVerification"))) return;
  void run(async () => {
    await api.setGuestRegistryContactVerification(props.personId, contact.contactId, contact.revision, null);
    await load();
  });
}

function verificationTime(value: string): string {
  return formatDateTime(value, locale.value);
}

onMounted(() => run(load));
</script>

<template>
  <section class="registry-contacts" aria-labelledby="registry-contacts-heading">
    <h4 id="registry-contacts-heading">{{ t("registry.contacts.title") }}</h4>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="directory && !directory.contacts.length" class="muted">{{ t("registry.contacts.none") }}</p>
    <div v-else-if="directory" class="table-scroll">
      <table class="data-table">
        <thead><tr>
          <th scope="col">{{ t("registry.contacts.kind") }}</th>
          <th scope="col">{{ t("registry.contacts.value") }}</th>
          <th scope="col">{{ t("registry.contacts.consent") }}</th>
          <th scope="col">{{ t("common.actions") }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="contact in directory.contacts" :key="contact.contactId">
            <td>{{ t(`registry.contacts.${contact.kind}`) }}</td>
            <td>{{ contact.value }}
              <small v-if="contact.primary">{{ t("registry.contacts.primary") }}</small>
              <small v-if="!contact.verified">{{ t("registry.contacts.unverified") }}</small>
              <small v-else-if="contact.verification">
                {{ t("registry.contacts.confirmedWith", {
                  method: t(`registry.contacts.method.${contact.verification.method}`),
                  time: verificationTime(contact.verification.at),
                }) }}
              </small>
              <small v-else>{{ t("registry.contacts.verified") }}</small>
            </td>
            <td>{{ t(`registry.contacts.consentValue.${contact.consent}`) }}</td>
            <td><div class="contact-actions">
              <button v-if="active && directory.canManage" type="button" class="button button-secondary"
                :disabled="busy || editorOpen || !!verifying" @click="openEditor(contact)">{{ t("common.edit") }}</button>
              <template v-if="active && directory.canVerify">
                <button v-if="contact.verified" type="button" class="button button-secondary"
                  :disabled="busy || editorOpen || !!verifying" @click="revokeVerification(contact)">
                  {{ t("registry.contacts.revokeVerification") }}
                </button>
                <button v-else-if="contact.consent !== 'withdrawn' && !verifying" type="button" class="button button-secondary"
                  :disabled="busy || editorOpen" @click="openVerification(contact)">
                  {{ t("registry.contacts.verify") }}
                </button>
              </template>
            </div></td>
          </tr>
        </tbody>
      </table>
    </div>
    <button v-if="active && directory?.canManage && !editorOpen && !verifying" class="button button-primary" type="button" :disabled="busy" @click="openEditor(null)">{{ t("registry.contacts.add") }}</button>
    <form v-if="verifying" class="registry-contacts" @submit.prevent="recordVerification">
      <p>{{ t("registry.contacts.verificationPrompt", { value: verifying.value }) }}</p>
      <div>
        <label for="contact-verification-method">{{ t("registry.contacts.verificationMethod") }}</label>
        <select id="contact-verification-method" v-model="verificationMethod" :disabled="busy">
          <option value="in_person">{{ t("registry.contacts.method.in_person") }}</option>
          <option v-if="verifying.kind === 'phone'" value="callback">{{ t("registry.contacts.method.callback") }}</option>
        </select>
      </div>
      <div class="contact-actions">
        <button class="button button-primary" type="submit" :disabled="busy">{{ t("registry.contacts.recordVerification") }}</button>
        <button class="button button-secondary" type="button" :disabled="busy" @click="verifying = null">{{ t("common.cancel") }}</button>
      </div>
    </form>
    <form v-if="editorOpen" class="registry-contacts" @submit.prevent="save">
      <div v-if="!editing">
        <label for="contact-kind">{{ t("registry.contacts.kind") }}</label>
        <select id="contact-kind" v-model="form.kind">
          <option value="email">{{ t("registry.contacts.email") }}</option>
          <option value="phone">{{ t("registry.contacts.phone") }}</option>
        </select>
        <label for="contact-value">{{ t("registry.contacts.value") }}</label>
        <input id="contact-value" v-model="form.value" :type="form.kind === 'email' ? 'email' : 'tel'" required maxlength="320">
      </div>
      <div>
        <label for="contact-consent">{{ t("registry.contacts.consent") }}</label>
        <select id="contact-consent" v-model="form.consent">
          <option v-for="consent in consents" :key="consent" :value="consent">{{ t(`registry.contacts.consentValue.${consent}`) }}</option>
        </select>
      </div>
      <label><input v-model="form.primary" type="checkbox" :disabled="form.consent === 'withdrawn'"> {{ t("registry.contacts.primary") }}</label>
      <div class="contact-actions">
        <button class="button button-primary" type="submit" :disabled="busy">{{ t("common.save") }}</button>
        <button class="button button-secondary" type="button" :disabled="busy" @click="closeEditor">{{ t("common.cancel") }}</button>
      </div>
    </form>
  </section>
</template>

<style scoped>
.registry-contacts { display: grid; gap: 0.75rem; }
.contact-actions { display: flex; flex-wrap: wrap; gap: 0.5rem; }
</style>
