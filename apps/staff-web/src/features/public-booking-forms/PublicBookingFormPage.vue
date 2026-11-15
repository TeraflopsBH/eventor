<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { setLocale, type SupportedLocale } from "../../i18n";
import { api, ApiError, type PublicBookingForm, type PublicBookingFormField } from "../../api";
import {
  buildPublicBookingInquirySubmission,
  initializePublicBookingAnswers,
  publicBookingContentHasFallback,
  publicBookingFieldText,
  publicBookingFormName,
  publicBookingOptionLabel,
  selectedPublicBookingValues,
  togglePublicBookingOption,
  validatePublicBookingChoices,
} from "./publicBookingForm";

const { locale, t } = useI18n();
const match = window.location.pathname.match(/^\/book\/([A-Za-z0-9][A-Za-z0-9-]{1,79})\/([A-Za-z0-9][A-Za-z0-9_-]{1,79})\/?$/);
const organizationSlug = match?.[1] ?? "";
const formCode = match?.[2] ?? "";
const form = ref<PublicBookingForm | null>(null);
const loading = ref(true);
const submitting = ref(false);
const error = ref("");
const submittedReference = ref("");
const requester = ref({ displayName: "", email: "", phone: "" });
const answers = ref<Record<string, unknown>>({});
const localeOptions: Array<{ value: SupportedLocale; label: string }> = [
  { value: "bs-BA", label: "Bosanski" },
  { value: "en", label: "English" },
];
const localizedFormName = computed(() => form.value
  ? publicBookingFormName(form.value, locale.value as SupportedLocale)
  : "");
const contentLocaleDiffers = computed(() => Boolean(form.value &&
  publicBookingContentHasFallback(form.value, locale.value as SupportedLocale)));

function fieldLabel(field: PublicBookingFormField): string {
  return form.value
    ? publicBookingFieldText(form.value, field, locale.value as SupportedLocale, "label")
    : field.label || field.code;
}

function fieldDescription(field: PublicBookingFormField): string {
  return form.value
    ? publicBookingFieldText(form.value, field, locale.value as SupportedLocale, "description")
    : field.description || "";
}

function fieldHelpText(field: PublicBookingFormField): string {
  return form.value
    ? publicBookingFieldText(form.value, field, locale.value as SupportedLocale, "helpText")
    : field.helpText || "";
}

function fieldPlaceholder(field: PublicBookingFormField): string | undefined {
  return (form.value
    ? publicBookingFieldText(form.value, field, locale.value as SupportedLocale, "placeholder")
    : field.placeholder) || undefined;
}

function optionLabel(field: PublicBookingFormField, value: string, fallback: string): string {
  return form.value
    ? publicBookingOptionLabel(form.value, field, locale.value as SupportedLocale, value, fallback)
    : fallback;
}

watch(locale, value => {
  document.documentElement.lang = value;
}, { immediate: true });

function inputType(type: string): string {
  if (type === "email") return "email";
  if (type === "phone") return "tel";
  if (type === "number") return "number";
  if (type === "date") return "date";
  if (type === "time") return "time";
  return "text";
}

function selectedValues(code: string): string[] {
  return selectedPublicBookingValues(answers.value, code);
}

function toggleOption(code: string, option: string, checked: boolean): void {
  togglePublicBookingOption(answers.value, code, option, checked);
}

function localizedApiError(value: unknown): string {
  if (value instanceof ApiError && value.status === 429) return t("publicBookingForm.rateLimited");
  if (value instanceof ApiError && value.status === 409) return t("publicBookingForm.formChanged");
  return t("publicBookingForm.submitFailed");
}

async function loadForm(): Promise<void> {
  loading.value = true;
  error.value = "";
  if (!organizationSlug || !formCode) {
    error.value = t("publicBookingForm.invalidAddress");
    loading.value = false;
    return;
  }
  try {
    const result = await api.getPublicBookingForm(organizationSlug, formCode);
    form.value = result.data;
    setLocale(result.data.defaultLocale);
    answers.value = initializePublicBookingAnswers(result.data.fieldSchema.fields);
  } catch {
    error.value = t("publicBookingForm.unavailable");
  } finally {
    loading.value = false;
  }
}

async function submitInquiry(): Promise<void> {
  if (!form.value || submitting.value) return;
  const invalidChoice = validatePublicBookingChoices(form.value.fieldSchema.fields, answers.value);
  if (invalidChoice) {
    const field = form.value.fieldSchema.fields.find(item => item.code === invalidChoice.code);
    error.value = invalidChoice.kind === "minimum"
      ? t("publicBookingForm.selectMinimum", {
          field: field ? fieldLabel(field) : invalidChoice.code,
          count: invalidChoice.minimum,
        })
      : t("publicBookingForm.selectMaximum", {
          field: field ? fieldLabel(field) : invalidChoice.code,
          count: invalidChoice.maximum,
        });
    return;
  }
  submitting.value = true;
  error.value = "";
  const payload = buildPublicBookingInquirySubmission(
    form.value,
    locale.value as SupportedLocale,
    requester.value,
    answers.value,
  );
  try {
    const result = await api.submitPublicBookingInquiry(organizationSlug, payload);
    submittedReference.value = result.data.publicReference;
  } catch (cause) {
    error.value = localizedApiError(cause);
  } finally {
    submitting.value = false;
  }
}

onMounted(() => { void loadForm(); });
</script>

<template>
  <main class="public-booking-page">
    <header class="public-booking-header">
      <a class="brand" href="/" aria-label="Eventor">
        <span class="brand-mark">E</span>
        <span>EVENTOR<small>BOOKING INQUIRY</small></span>
      </a>
      <label class="public-language">
        <span>{{ t("publicBookingForm.language") }}</span>
        <select :value="locale" @change="setLocale(($event.target as HTMLSelectElement).value)">
          <option v-for="option in localeOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
        </select>
      </label>
    </header>

    <section class="public-booking-content">
      <p class="eyebrow">{{ t("publicBookingForm.eyebrow") }}</p>
      <template v-if="loading">
        <h1>{{ t("publicBookingForm.loading") }}</h1>
      </template>
      <template v-else-if="submittedReference">
        <div class="panel public-booking-panel">
          <p class="eyebrow">{{ t("publicBookingForm.received") }}</p>
          <h1>{{ t("publicBookingForm.thankYou") }}</h1>
          <p>{{ t("publicBookingForm.reference") }}</p>
          <strong class="public-reference">{{ submittedReference }}</strong>
          <p class="muted">{{ t("publicBookingForm.confirmationNote") }}</p>
        </div>
      </template>
      <template v-else-if="form">
        <p class="muted">{{ form.organizationName }}</p>
        <h1>{{ localizedFormName }}</h1>
        <p class="muted">{{ t("publicBookingForm.intro") }}</p>
        <p v-if="contentLocaleDiffers" class="public-language-note">
          {{ t("publicBookingForm.contentLanguageNote", { language: form.locale === "bs-BA" ? "Bosanski" : "English" }) }}
        </p>

        <form class="panel public-booking-panel" @submit.prevent="submitInquiry">
          <h2>{{ t("publicBookingForm.contactDetails") }}</h2>
          <label>
            {{ t("publicBookingForm.fullName") }} *
            <input v-model="requester.displayName" name="displayName" required maxlength="250" autocomplete="name" />
          </label>
          <label>
            {{ t("publicBookingForm.email") }}
            <input v-model="requester.email" name="email" type="email" maxlength="320" autocomplete="email" />
          </label>
          <label>
            {{ t("publicBookingForm.phone") }}
            <input v-model="requester.phone" name="phone" type="tel" maxlength="50" autocomplete="tel" />
          </label>

          <template v-for="field in form.fieldSchema.fields" :key="field.code">
            <label v-if="field.type === 'textarea'">
              {{ fieldLabel(field) }}{{ field.required ? " *" : "" }}
              <textarea :value="String(answers[field.code] ?? '')" :name="field.code" :required="field.required" :minlength="field.minLength" :maxlength="field.maxLength" :placeholder="fieldPlaceholder(field)" rows="4" @input="answers[field.code] = ($event.target as HTMLTextAreaElement).value" />
              <small v-if="fieldDescription(field) || fieldHelpText(field)" class="muted">{{ fieldDescription(field) || fieldHelpText(field) }}</small>
            </label>
            <label v-else-if="field.type === 'select'">
              {{ fieldLabel(field) }}{{ field.required ? " *" : "" }}
              <select v-model="answers[field.code]" :name="field.code" :required="field.required">
                <option value="">{{ t("publicBookingForm.chooseOption") }}</option>
                <option v-for="option in field.options || []" :key="option.value" :value="option.value">{{ optionLabel(field, option.value, option.label) }}</option>
              </select>
              <small v-if="fieldDescription(field) || fieldHelpText(field)" class="muted">{{ fieldDescription(field) || fieldHelpText(field) }}</small>
            </label>
            <fieldset v-else-if="field.type === 'multiselect'" class="public-choice-group">
              <legend>{{ fieldLabel(field) }}{{ field.required ? " *" : "" }}</legend>
              <label v-for="option in field.options || []" :key="option.value" class="public-choice">
                <input type="checkbox" :checked="selectedValues(field.code).includes(option.value)" @change="toggleOption(field.code, option.value, ($event.target as HTMLInputElement).checked)" />
                {{ optionLabel(field, option.value, option.label) }}
              </label>
              <small v-if="fieldDescription(field) || fieldHelpText(field)" class="muted">{{ fieldDescription(field) || fieldHelpText(field) }}</small>
            </fieldset>
            <label v-else-if="field.type === 'checkbox'" class="public-checkbox">
              <input v-model="answers[field.code]" type="checkbox" :name="field.code" :required="field.required" />
              <span>{{ fieldLabel(field) }}{{ field.required ? " *" : "" }}</span>
            </label>
            <label v-else>
              {{ fieldLabel(field) }}{{ field.required ? " *" : "" }}
              <input
                v-model="answers[field.code]"
                :name="field.code"
                :type="inputType(field.type)"
                :required="field.required"
                :min="field.min"
                :max="field.max"
                :minlength="field.minLength"
                :maxlength="field.maxLength"
                :step="field.integer ? 1 : 'any'"
                :placeholder="fieldPlaceholder(field) || (field.type === 'datetime' ? 'YYYY-MM-DDTHH:mm:ss+01:00' : undefined)"
              />
              <small v-if="field.type === 'datetime'" class="muted">{{ t("publicBookingForm.dateTimeOffsetHelp") }}</small>
              <small v-if="fieldDescription(field) || fieldHelpText(field)" class="muted">{{ fieldDescription(field) || fieldHelpText(field) }}</small>
            </label>
          </template>

          <p v-if="error" class="public-form-error" role="alert">{{ error }}</p>
          <button class="button button-primary full-width" type="submit" :disabled="submitting">
            {{ submitting ? t("publicBookingForm.submitting") : t("publicBookingForm.submit") }}
          </button>
          <p class="fine-print">{{ t("publicBookingForm.privacyNote") }}</p>
        </form>
      </template>
      <div v-else class="panel public-booking-panel">
        <h1>{{ t("publicBookingForm.unavailable") }}</h1>
        <p v-if="error" class="public-form-error" role="alert">{{ error }}</p>
      </div>
    </section>
  </main>
</template>
