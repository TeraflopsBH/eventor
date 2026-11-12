import type {
  PublicBookingForm,
  PublicBookingFormField,
  PublicBookingInquirySubmission,
} from "../../api";

export type PublicBookingLocale = PublicBookingForm["locale"];
export type PublicBookingFieldTextKey = "label" | "description" | "helpText" | "placeholder";
export type PublicBookingRequester = {
  displayName: string;
  email: string;
  phone: string;
};

export function localizedPublicBookingContent(
  form: PublicBookingForm,
  locale: PublicBookingLocale,
) {
  return form.fieldSchema.contentTranslations?.[locale];
}

export function publicBookingFormName(
  form: PublicBookingForm,
  locale: PublicBookingLocale,
): string {
  return localizedPublicBookingContent(form, locale)?.formName || form.formName;
}

export function publicBookingFieldText(
  form: PublicBookingForm,
  field: PublicBookingFormField,
  locale: PublicBookingLocale,
  key: PublicBookingFieldTextKey,
): string {
  return localizedPublicBookingContent(form, locale)?.fields[field.code]?.[key] ||
    field[key] || (key === "label" ? field.code : "");
}

export function publicBookingOptionLabel(
  form: PublicBookingForm,
  field: PublicBookingFormField,
  locale: PublicBookingLocale,
  value: string,
  fallback: string,
): string {
  return localizedPublicBookingContent(form, locale)?.fields[field.code]?.options?.[value] || fallback;
}

export function publicBookingContentHasFallback(
  form: PublicBookingForm,
  locale: PublicBookingLocale,
): boolean {
  if (form.locale === locale) return false;
  const translation = localizedPublicBookingContent(form, locale);
  if (!translation?.formName) return true;
  return form.fieldSchema.fields.some((field) => {
    const translated = translation.fields[field.code];
    if (field.label && !translated?.label) return true;
    if (field.description && !translated?.description) return true;
    if (field.helpText && !translated?.helpText) return true;
    if (field.placeholder && !translated?.placeholder) return true;
    return (field.options || []).some((option) => !translated?.options?.[option.value]);
  });
}

export function initializePublicBookingAnswers(
  fields: readonly PublicBookingFormField[],
): Record<string, unknown> {
  const answers: Record<string, unknown> = {};
  for (const field of fields) {
    if (field.type === "multiselect") answers[field.code] = [];
    else if (field.type === "checkbox") answers[field.code] = false;
  }
  return answers;
}

export function selectedPublicBookingValues(
  answers: Readonly<Record<string, unknown>>,
  code: string,
): string[] {
  const value = answers[code];
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

export function togglePublicBookingOption(
  answers: Record<string, unknown>,
  code: string,
  option: string,
  checked: boolean,
): void {
  const current = selectedPublicBookingValues(answers, code);
  answers[code] = checked
    ? current.includes(option) ? current : [...current, option]
    : current.filter((value) => value !== option);
}

export type PublicBookingChoiceIssue =
  | { code: string; kind: "minimum"; count: number; minimum: number }
  | { code: string; kind: "maximum"; count: number; maximum: number };

export function validatePublicBookingChoices(
  fields: readonly PublicBookingFormField[],
  answers: Readonly<Record<string, unknown>>,
): PublicBookingChoiceIssue | null {
  for (const field of fields) {
    if (field.type !== "multiselect") continue;
    const count = selectedPublicBookingValues(answers, field.code).length;
    const minimum = Math.max(field.required ? 1 : 0, field.minItems ?? 0);
    if (count < minimum) return { code: field.code, kind: "minimum", count, minimum };
    if (field.maxItems !== undefined && count > field.maxItems) {
      return { code: field.code, kind: "maximum", count, maximum: field.maxItems };
    }
  }
  return null;
}

export function normalizePublicBookingAnswers(
  fields: readonly PublicBookingFormField[],
  answers: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const normalized: Record<string, unknown> = {};
  for (const field of fields) {
    const value = answers[field.code];
    normalized[field.code] = field.type === "number" &&
      value !== "" && value !== null && value !== undefined
      ? Number(value)
      : value;
  }
  return normalized;
}

export function buildPublicBookingInquirySubmission(
  form: PublicBookingForm,
  locale: PublicBookingLocale,
  requester: PublicBookingRequester,
  answers: Readonly<Record<string, unknown>>,
): PublicBookingInquirySubmission {
  return {
    formCode: form.formCode,
    // Always submit the immutable revision returned with the loaded projection.
    formRevisionId: form.formRevisionId,
    customerLocale: locale,
    requester: {
      displayName: requester.displayName.trim(),
      ...(requester.email.trim() ? { email: requester.email.trim() } : {}),
      ...(requester.phone.trim() ? { phone: requester.phone.trim() } : {}),
    },
    requested: {},
    answers: normalizePublicBookingAnswers(form.fieldSchema.fields, answers),
  };
}
