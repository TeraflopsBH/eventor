import { computed, reactive, ref, type Ref } from "vue";
import type { BookingForm, BookingFormField, BookingFormSchema, BookingFormTranslation } from "../../api";
import { moveBookingFormField, validateBookingFormDraft } from "./validateBookingFormDraft";

type Locale = "bs-BA" | "en";
type Translate = (key: string, params?: Record<string, string | number>) => string;
interface Dependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
  translate: Translate;
}
const emptySchema = (): BookingFormSchema => ({ schemaVersion: 1, fields: [] });
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

export function useBookingForms({ api, busy, pageError, pageNotice, clearMessages, showError, translate }: Dependencies) {
  const forms = ref<BookingForm[]>([]);
  const selectedFormId = ref("");
  const createForm = reactive({ code: "", name: "", locale: "bs-BA" as Locale });
  const schema = ref<BookingFormSchema>(emptySchema());
  const baseLocale = ref<Locale>("bs-BA");
  const selectedFieldCode = ref("");
  const previewLocale = ref<Locale>("bs-BA");
  const dirty = ref(false);
  const selectedForm = computed(() => forms.value.find(item => item.formId === selectedFormId.value) ?? null);
  const latestRevision = computed(() => selectedForm.value?.revisions[0] ?? null);
  const editable = computed(() => latestRevision.value?.state === "draft");
  const selectedField = computed(() => schema.value.fields.find(field => field.code === selectedFieldCode.value) ?? null);
  const translation = (locale: Locale): BookingFormTranslation =>
    schema.value.contentTranslations?.[locale] ?? { formName: "", fields: {} };
  function setFormTranslationName(locale: Locale, value: string): void {
    schema.value.contentTranslations ??= {};
    schema.value.contentTranslations[locale] ??= { formName: "", fields: {} };
    schema.value.contentTranslations[locale]!.formName = value;
    markDirty();
  }
  function updateFieldCode(field: BookingFormField, nextCode: string): void {
    const previous = field.code;
    if (previous === nextCode || !/^[a-z][a-z0-9_]{0,79}$/.test(nextCode) ||
        schema.value.fields.some(item => item !== field && item.code === nextCode)) return;
    field.code = nextCode;
    if (selectedFieldCode.value === previous) selectedFieldCode.value = nextCode;
    for (const locale of ["bs-BA", "en"] as Locale[]) {
      const translatedFields = schema.value.contentTranslations?.[locale]?.fields;
      if (translatedFields?.[previous]) {
        translatedFields[nextCode] = translatedFields[previous]!;
        delete translatedFields[previous];
      }
    }
    markDirty();
  }
  function updateOptionValue(field: BookingFormField, previous: string, next: string): void {
    if (!field.options || !next.trim() || next.length > 200 ||
        field.options.some(option => option.value === next && option.value !== previous)) return;
    const option = field.options.find(item => item.value === previous);
    if (!option) return;
    option.value = next;
    for (const locale of ["bs-BA", "en"] as Locale[]) {
      const translatedOptions = schema.value.contentTranslations?.[locale]?.fields[field.code]?.options;
      if (translatedOptions?.[previous] !== undefined) {
        translatedOptions[next] = translatedOptions[previous]!;
        delete translatedOptions[previous];
      }
    }
    markDirty();
  }
  function moveField(index: number, offset: -1 | 1): void {
    if (!editable.value) return;
    moveBookingFormField(schema.value.fields, index, offset);
    markDirty();
  }
  function markDirty(): void { dirty.value = true; }
  function syncRevision(): void {
    const revision = latestRevision.value;
    schema.value = revision ? clone(revision.fieldSchema) : emptySchema();
    baseLocale.value = revision?.locale ?? "bs-BA";
    previewLocale.value = baseLocale.value;
    selectedFieldCode.value = schema.value.fields[0]?.code ?? "";
    dirty.value = false;
  }
  async function load(): Promise<void> {
    const result = await api.getBookingForms();
    forms.value = result.data;
    if (!forms.value.some(item => item.formId === selectedFormId.value)) selectedFormId.value = forms.value[0]?.formId ?? "";
    syncRevision();
  }
  async function open(): Promise<void> {
    clearMessages(); busy.value = true;
    try { await load(); } catch (error) { showError(error); } finally { busy.value = false; }
  }
  function selectForm(id: string): void { selectedFormId.value = id; syncRevision(); }
  async function create(): Promise<void> {
    const code = createForm.code.trim();
    const name = createForm.name.trim();
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{1,79}$/.test(code) || !name || name.length > 250) {
      pageError.value = translate("bookingForms.invalidIdentity"); return;
    }
    clearMessages(); busy.value = true;
    try {
      const result = await api.createBookingForm({ code, name, locale: createForm.locale, fieldSchema: emptySchema() });
      createForm.code = ""; createForm.name = "";
      await load(); selectedFormId.value = result.data.formId; syncRevision();
      pageNotice.value = translate("bookingForms.created");
    } catch (error) { showError(error); } finally { busy.value = false; }
  }
  async function createRevision(): Promise<void> {
    const form = selectedForm.value;
    if (!form || editable.value) return;
    clearMessages(); busy.value = true;
    try {
      await api.createBookingFormRevision(form.formId);
      await load(); pageNotice.value = translate("bookingForms.revisionCreated");
    } catch (error) { showError(error); } finally { busy.value = false; }
  }
  function addField(): void {
    if (!editable.value || schema.value.fields.length >= 100) return;
    let code = "new_field", suffix = 2;
    while (schema.value.fields.some(field => field.code === code)) code = `new_field_${suffix++}`;
    schema.value.fields.push({ code, type: "text", label: translate("bookingForms.newField"), required: false });
    selectedFieldCode.value = code; markDirty();
  }
  function removeField(code: string): void {
    if (!editable.value) return;
    schema.value.fields = schema.value.fields.filter(field => field.code !== code);
    for (const locale of ["bs-BA", "en"] as Locale[]) delete schema.value.contentTranslations?.[locale]?.fields[code];
    selectedFieldCode.value = schema.value.fields[0]?.code ?? ""; markDirty();
  }
  function addOption(field: BookingFormField): void {
    field.options ??= [];
    let value = "option", suffix = 2;
    while (field.options.some(item => item.value === value)) value = `option_${suffix++}`;
    field.options.push({ value, label: translate("bookingForms.newOption") }); markDirty();
  }
  function fieldText(locale: Locale, field: BookingFormField, key: "label" | "description" | "helpText" | "placeholder"): string {
    const translated = translation(locale).fields[field.code]?.[key];
    const base = field[key] ?? "";
    if (locale === baseLocale.value) return base;
    return translated ?? base;
  }
  function setFieldText(locale: Locale, field: BookingFormField, key: "label" | "description" | "helpText" | "placeholder", value: string): void {
    if (locale === baseLocale.value) {
      field[key] = value;
      markDirty();
      return;
    }
    const content = translation(locale);
    content.fields[field.code] ??= {};
    content.fields[field.code]![key] = value;
    markDirty();
  }
  function optionText(locale: Locale, field: BookingFormField, value: string, fallback: string): string {
    return (locale === baseLocale.value ? fallback : translation(locale).fields[field.code]?.options?.[value]) ?? fallback;
  }
  function setOptionText(locale: Locale, field: BookingFormField, value: string, label: string): void {
    if (locale === baseLocale.value) {
      const option = field.options?.find(item => item.value === value);
      if (option) option.label = label;
      markDirty();
      return;
    }
    const content = translation(locale);
    content.fields[field.code] ??= {};
    content.fields[field.code]!.options ??= {};
    content.fields[field.code]!.options![value] = label; markDirty();
  }
  function completeness(locale: Locale): { complete: number; total: number } {
    const content = schema.value.contentTranslations?.[locale];
    const required: string[] = [];
    if (locale !== baseLocale.value) required.push("formName");
    for (const field of schema.value.fields) {
      if (locale === baseLocale.value) continue;
      for (const key of ["label", "description", "helpText", "placeholder"] as const) if (field[key]) required.push(`${field.code}.${key}`);
      for (const option of field.options ?? []) required.push(`${field.code}.options.${option.value}`);
    }
    const complete = required.filter(key => {
      if (key === "formName") return Boolean(content?.formName?.trim());
      const [code, keyName, value] = key.split(".");
      const item = content?.fields[code!];
      if (keyName === "options") return Boolean(item?.options?.[value!]?.trim());
      return Boolean(item?.[keyName as "label" | "description" | "helpText" | "placeholder"]?.trim());
    }).length;
    return { complete, total: required.length };
  }
  function previewFieldLabel(locale: Locale, field: BookingFormField): string {
    return translation(locale).fields[field.code]?.label || field.label || field.code;
  }
  function previewOptionLabel(locale: Locale, field: BookingFormField, option: { value: string; label: string }): string {
    return optionText(locale, field, option.value, option.label);
  }
  async function save(): Promise<void> {
    const form = selectedForm.value, revision = latestRevision.value;
    if (!form || !revision || !editable.value) return;
    const issues = validateBookingFormDraft(schema.value);
    if (issues.length) {
      pageError.value = translate(issues[0]!.messageKey);
      return;
    }
    clearMessages(); busy.value = true;
    try {
      await api.updateBookingFormDraftRevision(form.formId, revision.revisionId, { locale: baseLocale.value, fieldSchema: schema.value });
      await load(); pageNotice.value = translate("bookingForms.saved");
    } catch (error) { showError(error); } finally { busy.value = false; }
  }
  async function publish(): Promise<void> {
    const form = selectedForm.value, revision = latestRevision.value;
    if (!form || !revision || !editable.value) return;
    const issues = validateBookingFormDraft(schema.value);
    if (issues.length) { pageError.value = translate(issues[0]!.messageKey); return; }
    if (dirty.value) { pageError.value = translate("bookingForms.saveBeforePublish"); return; }
    if (!window.confirm(translate("bookingForms.publishConfirm"))) return;
    clearMessages(); busy.value = true;
    try {
      await api.publishBookingFormRevision(form.formId, revision.revisionId);
      await load(); pageNotice.value = translate("bookingForms.published");
    } catch (error) { showError(error); } finally { busy.value = false; }
  }
  return { forms, selectedFormId, createForm, schema, baseLocale, previewLocale, selectedForm, latestRevision, editable, selectedFieldCode, selectedField, dirty, translation, setFormTranslationName, updateFieldCode, updateOptionValue, moveField, completeness, fieldText, setFieldText, optionText, setOptionText, previewFieldLabel, previewOptionLabel, load, open, selectForm, create, createRevision, addField, removeField, addOption, markDirty, save, publish };
}
