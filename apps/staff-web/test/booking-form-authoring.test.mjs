import assert from "node:assert/strict";
import test from "node:test";
import { ref } from "vue";
import {
  moveBookingFormField,
  validateBookingFormDraft,
} from "../src/features/booking-forms/validateBookingFormDraft.ts";
import { useBookingForms } from "../src/features/booking-forms/useBookingForms.ts";

const validField = (overrides = {}) => ({
  code: "contact_name",
  type: "text",
  label: "Contact name",
  required: true,
  ...overrides,
});

const validSchema = (overrides = {}) => ({
  schemaVersion: 1,
  fields: [validField()],
  ...overrides,
});

const issueCodes = (schema) => validateBookingFormDraft(schema).map((issue) => issue.code);

test("accepts a minimal valid schema-v1 draft", () => {
  assert.deepEqual(validateBookingFormDraft(validSchema()), []);
});

test("rejects empty, oversized and unsupported-version field collections", () => {
  assert.ok(issueCodes(validSchema({ fields: [] })).includes("field_count"));
  assert.ok(issueCodes(validSchema({ fields: Array.from({ length: 101 }, (_, index) => validField({ code: `field_${index}` })) })).includes("field_count"));
  assert.ok(issueCodes(validSchema({ schemaVersion: 2 })).includes("field_count"));
});

test("rejects malformed and duplicate stable field codes", () => {
  const issues = issueCodes(validSchema({ fields: [
    validField({ code: "ContactName" }),
    validField({ code: "contact_name" }),
    validField({ code: "contact_name" }),
  ] }));
  assert.ok(issues.filter((code) => code === "field_code").length >= 2);
});

test("rejects unsupported field types and type-incompatible constraints", () => {
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "file" })] })).includes("field_type"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "date", minLength: 2 })] })).includes("length_type"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "text", min: 1 })] })).includes("number_type"));
});

test("validates text lengths and numeric ranges", () => {
  assert.ok(issueCodes(validSchema({ fields: [validField({ minLength: 8, maxLength: 3 })] })).includes("length"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "number", min: 10, max: 2 })] })).includes("number_range"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "number", min: Number.POSITIVE_INFINITY })] })).includes("number_range"));
});

test("validates select option count, labels and stable values", () => {
  const issues = issueCodes(validSchema({ fields: [validField({
    type: "select",
    options: [
      { value: "morning", label: "Morning" },
      { value: "morning", label: " " },
    ],
  })] }));
  assert.ok(issues.includes("options"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "select", options: [] })] })).includes("options"));
});

test("validates multi-select bounds and rejects those bounds on other field types", () => {
  assert.ok(issueCodes(validSchema({ fields: [validField({
    type: "multiselect",
    options: [{ value: "a", label: "A" }, { value: "b", label: "B" }],
    minItems: 2,
    maxItems: 1,
  })] })).includes("multi_range"));
  assert.ok(issueCodes(validSchema({ fields: [validField({ type: "text", minItems: 1 })] })).includes("options_type"));
});

test("validates translation locale, form name, field references and option references", () => {
  const schema = validSchema({
    fields: [validField({ type: "select", options: [{ value: "morning", label: "Morning" }] })],
    contentTranslations: {
      "fr-FR": { formName: "Formulaire", fields: {} },
      en: {
        formName: " ",
        fields: {
          missing_field: { label: "Unknown" },
          contact_name: { options: { evening: "Evening" } },
        },
      },
    },
  });
  const issues = issueCodes(schema);
  assert.ok(issues.includes("locale"));
  assert.ok(issues.includes("form_name"));
  assert.ok(issues.includes("unknown_translation_field"));
  assert.ok(issues.includes("translation_options"));
});

test("validates translated text and option labels", () => {
  const issues = issueCodes(validSchema({
    contentTranslations: {
      en: {
        formName: "Booking",
        fields: { contact_name: { label: " ", description: "x".repeat(1001) } },
      },
    },
  }));
  assert.ok(issues.includes("label"));
  assert.ok(issues.includes("description"));
});

test("moves fields in either direction without crossing list boundaries", () => {
  const fields = [validField({ code: "first" }), validField({ code: "second" }), validField({ code: "third" })];
  moveBookingFormField(fields, 1, -1);
  assert.deepEqual(fields.map((field) => field.code), ["second", "first", "third"]);
  moveBookingFormField(fields, 1, 1);
  assert.deepEqual(fields.map((field) => field.code), ["second", "third", "first"]);
  moveBookingFormField(fields, 0, -1);
  moveBookingFormField(fields, 3, 1);
  assert.deepEqual(fields.map((field) => field.code), ["second", "third", "first"]);
});

function createWorkspace(initialSchema = validSchema()) {
  const revision = {
    revisionId: "revision-1",
    revisionNumber: 1,
    locale: "bs-BA",
    fieldSchema: structuredClone(initialSchema),
    state: "draft",
    publishedAt: null,
    createdAt: "2026-01-01T00:00:00Z",
  };
  const form = {
    formId: "form-1",
    formCode: "general",
    name: "General",
    scopeKind: "organization",
    scopeVenueId: null,
    scopeSpaceId: null,
    status: "active",
    revisions: [revision],
  };
  const calls = { update: [], publish: [] };
  const api = {
    async getBookingForms() { return { data: [form] }; },
    async updateBookingFormDraftRevision(...args) { calls.update.push(args); return { data: {} }; },
    async publishBookingFormRevision(...args) { calls.publish.push(args); return { data: {} }; },
  };
  const state = {
    busy: ref(false),
    pageError: ref(""),
    pageNotice: ref(""),
    errors: [],
  };
  const workspace = useBookingForms({
    api,
    busy: state.busy,
    pageError: state.pageError,
    pageNotice: state.pageNotice,
    clearMessages() { state.pageError.value = ""; state.pageNotice.value = ""; },
    showError(error) { state.errors.push(error); },
    translate(key) { return key; },
  });
  return { workspace, calls, state, form };
}

test("renaming a field code migrates both locale translation keys", async () => {
  const { workspace } = createWorkspace(validSchema({
    contentTranslations: {
      "bs-BA": { formName: "Obrazac", fields: { contact_name: { label: "Ime" } } },
      en: { formName: "Form", fields: { contact_name: { label: "Name" } } },
    },
  }));
  await workspace.load();
  const field = workspace.schema.value.fields[0];
  workspace.updateFieldCode(field, "requester_name");
  assert.equal(field.code, "requester_name");
  assert.equal(workspace.schema.value.contentTranslations["bs-BA"].fields.requester_name.label, "Ime");
  assert.equal(workspace.schema.value.contentTranslations.en.fields.requester_name.label, "Name");
  assert.equal("contact_name" in workspace.schema.value.contentTranslations.en.fields, false);
});

test("renaming an option value migrates translated option labels", async () => {
  const { workspace } = createWorkspace(validSchema({
    fields: [validField({ type: "select", options: [{ value: "am", label: "Morning" }] })],
    contentTranslations: {
      en: { formName: "Form", fields: { contact_name: { options: { am: "In the morning" } } } },
    },
  }));
  await workspace.load();
  workspace.updateOptionValue(workspace.schema.value.fields[0], "am", "morning");
  assert.equal(workspace.schema.value.fields[0].options[0].value, "morning");
  assert.equal(workspace.schema.value.contentTranslations.en.fields.contact_name.options.morning, "In the morning");
  assert.equal("am" in workspace.schema.value.contentTranslations.en.fields.contact_name.options, false);
});

test("base-language edits update canonical fields while secondary edits stay in translations", async () => {
  const { workspace } = createWorkspace();
  await workspace.load();
  const field = workspace.schema.value.fields[0];
  workspace.setFieldText("bs-BA", field, "label", "Ime");
  workspace.setFieldText("en", field, "label", "Name");
  assert.equal(field.label, "Ime");
  assert.equal(workspace.schema.value.contentTranslations.en.fields.contact_name.label, "Name");
});

test("translation reads do not create or mutate translation state", async () => {
  const { workspace } = createWorkspace();
  await workspace.load();
  const before = structuredClone(workspace.schema.value);
  assert.equal(workspace.fieldText("en", workspace.schema.value.fields[0], "label"), "Contact name");
  assert.deepEqual(workspace.translation("en"), { formName: "", fields: {} });
  assert.deepEqual(workspace.schema.value, before);
  assert.equal(workspace.dirty.value, false);
});

test("translation completeness counts only source content needing translation", async () => {
  const { workspace } = createWorkspace(validSchema({
    fields: [validField({
      description: "Tell us who to contact",
      options: [{ value: "morning", label: "Morning" }],
      type: "select",
    })],
    contentTranslations: {
      en: {
        formName: "Form",
        fields: {
          contact_name: {
            label: "Name",
            description: "Tell us who to contact",
            options: { morning: "Morning" },
          },
        },
      },
    },
  }));
  await workspace.load();
  assert.deepEqual(workspace.completeness("en"), { complete: 4, total: 4 });
  assert.deepEqual(workspace.completeness("bs-BA"), { complete: 0, total: 0 });
});

test("save is blocked before API mutation when draft validation fails", async () => {
  const { workspace, calls, state } = createWorkspace(validSchema({ fields: [] }));
  await workspace.load();
  await workspace.save();
  assert.equal(calls.update.length, 0);
  assert.equal(state.pageError.value, "bookingForms.validation.fieldCount");
  assert.equal(state.busy.value, false);
});

test("publish is blocked while the draft has unsaved edits", async () => {
  const { workspace, calls, state } = createWorkspace();
  await workspace.load();
  workspace.markDirty();
  await workspace.publish();
  assert.equal(calls.publish.length, 0);
  assert.equal(state.pageError.value, "bookingForms.saveBeforePublish");
});
