import type { BookingFormSchema, BookingFormField } from "../../api";

export interface DraftIssue {
  code: string;
  messageKey: string;
  fieldCode?: string;
}

const fieldCodePattern = /^[a-z][a-z0-9_]{0,79}$/;
const fieldTypes = new Set(["text", "textarea", "email", "phone", "number", "date", "datetime", "time", "select", "multiselect", "checkbox"]);
const translatedProperties = ["label", "placeholder", "description", "helpText"] as const;

export function validateBookingFormDraft(schema: BookingFormSchema): DraftIssue[] {
  const issues: DraftIssue[] = [];
  const fields = schema.fields;
  if (!Array.isArray(fields) || fields.length < 1 || fields.length > 100) {
    issues.push({ code: "field_count", messageKey: "bookingForms.validation.fieldCount" });
    return issues;
  }
  const codes = new Set<string>();
  for (const field of fields) {
    if (!fieldCodePattern.test(field.code) || codes.has(field.code)) {
      issues.push({ code: "field_code", fieldCode: field.code, messageKey: "bookingForms.validation.fieldCode" });
    }
    codes.add(field.code);
    if (!fieldTypes.has(field.type)) {
      issues.push({ code: "field_type", fieldCode: field.code, messageKey: "bookingForms.validation.fieldType" });
    }
    for (const key of ["label", "placeholder"] as const) {
      if (field[key] !== undefined && (field[key]!.length > 200)) {
        issues.push({ code: key, fieldCode: field.code, messageKey: "bookingForms.validation.shortTextLength" });
      }
    }
    for (const key of ["description", "helpText"] as const) {
      if (field[key] !== undefined && field[key]!.length > 1000) {
        issues.push({ code: key, fieldCode: field.code, messageKey: "bookingForms.validation.longTextLength" });
      }
    }
    if (["text", "textarea", "email", "phone"].includes(field.type)) {
      const min = field.minLength ?? 0, max = field.maxLength ?? 5000;
      if (!Number.isInteger(min) || !Number.isInteger(max) || min < 0 || min > 5000 || max < 1 || max > 5000 || min > max) {
        issues.push({ code: "length", fieldCode: field.code, messageKey: "bookingForms.validation.lengthRange" });
      }
    } else if (field.minLength !== undefined || field.maxLength !== undefined) {
      issues.push({ code: "length_type", fieldCode: field.code, messageKey: "bookingForms.validation.unsupportedConstraint" });
    }
    if (field.type === "number") {
      if ((field.min !== undefined && !Number.isFinite(field.min)) ||
          (field.max !== undefined && !Number.isFinite(field.max)) ||
          (field.min !== undefined && field.max !== undefined && field.min > field.max)) {
        issues.push({ code: "number_range", fieldCode: field.code, messageKey: "bookingForms.validation.numberRange" });
      }
    } else if (field.min !== undefined || field.max !== undefined || field.integer !== undefined) {
      issues.push({ code: "number_type", fieldCode: field.code, messageKey: "bookingForms.validation.unsupportedConstraint" });
    }
    if (field.type === "select" || field.type === "multiselect") {
      const options = field.options ?? [];
      const values = new Set<string>();
      if (options.length < 1 || options.length > 250 ||
          options.some(option => !option.value.trim() || option.value.length > 200 ||
            !option.label.trim() || option.label.length > 200 || values.has(option.value) || !values.add(option.value))) {
        issues.push({ code: "options", fieldCode: field.code, messageKey: "bookingForms.validation.options" });
      }
      if (field.type === "multiselect") {
        const min = field.minItems ?? 0, max = field.maxItems ?? options.length;
        if (!Number.isInteger(min) || !Number.isInteger(max) || min < 0 || max < 1 || min > max || max > options.length) {
          issues.push({ code: "multi_range", fieldCode: field.code, messageKey: "bookingForms.validation.multiRange" });
        }
      } else if (field.minItems !== undefined || field.maxItems !== undefined) {
        issues.push({ code: "multi_type", fieldCode: field.code, messageKey: "bookingForms.validation.unsupportedConstraint" });
      }
    } else if (field.options !== undefined || field.minItems !== undefined || field.maxItems !== undefined) {
      issues.push({ code: "options_type", fieldCode: field.code, messageKey: "bookingForms.validation.unsupportedConstraint" });
    }
  }
  for (const [locale, translation] of Object.entries(schema.contentTranslations ?? {})) {
    if (locale !== "bs-BA" && locale !== "en") {
      issues.push({ code: "locale", messageKey: "bookingForms.validation.locale" }); continue;
    }
    if (!translation.formName.trim() || translation.formName.length > 200) {
      issues.push({ code: "form_name", messageKey: "bookingForms.validation.translationName" });
    }
    for (const [code, translatedField] of Object.entries(translation.fields ?? {})) {
      const field = fields.find(item => item.code === code);
      if (!field) {
        issues.push({ code: "unknown_translation_field", messageKey: "bookingForms.validation.unknownTranslationField" }); continue;
      }
      for (const key of translatedProperties) {
        const value = translatedField[key];
        const limit = key === "description" || key === "helpText" ? 1000 : 200;
        if (value !== undefined && (!value.trim() || value.length > limit)) {
          issues.push({ code: key, fieldCode: code, messageKey: "bookingForms.validation.translationText" });
        }
      }
      if (translatedField.options) {
        const values = new Set((field.options ?? []).map(option => option.value));
        if (!["select", "multiselect"].includes(field.type) ||
            Object.entries(translatedField.options).some(([value, label]) => !values.has(value) || !label.trim() || label.length > 200)) {
          issues.push({ code: "translation_options", fieldCode: code, messageKey: "bookingForms.validation.translationOptions" });
        }
      }
    }
  }
  return issues;
}

export function moveBookingFormField(fields: BookingFormField[], index: number, offset: -1 | 1): void {
  const target = index + offset;
  if (index < 0 || index >= fields.length || target < 0 || target >= fields.length) return;
  [fields[index], fields[target]] = [fields[target]!, fields[index]!];
}
