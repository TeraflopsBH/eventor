import assert from "node:assert/strict";
import test from "node:test";
import {
  PublicFormAnswersError,
  PublicFormSchemaError,
  validatePublicFormAnswers,
} from "../src/public-form-validation.js";

const fieldSchema = {
  schemaVersion: 1,
  fields: [
    { code: "event_date", type: "date", required: true },
    { code: "event_name", type: "text", required: true, minLength: 2, maxLength: 120 },
    { code: "estimated_guests", type: "number", required: true, integer: true, min: 1, max: 5000 },
    {
      code: "room_layout",
      type: "select",
      required: true,
      options: [
        { value: "theatre", label: "Theatre" },
        { value: "banquet", label: "Banquet" },
      ],
    },
    {
      code: "equipment",
      type: "multiselect",
      required: false,
      minItems: 0,
      maxItems: 2,
      options: [
        { value: "projector", label: "Projector" },
        { value: "microphone", label: "Microphone" },
      ],
    },
    { code: "contact_email", type: "email", required: false, maxLength: 320 },
    { code: "accept_terms", type: "checkbox", required: true },
    { code: "optional_note", type: "textarea", required: false, maxLength: 1000 },
  ],
};

test("public form v1 accepts valid typed values and legacy schemas without an explicit version", () => {
  assert.doesNotThrow(() => validatePublicFormAnswers(fieldSchema, {
    event_date: "2027-01-18",
    event_name: "Annual meeting",
    estimated_guests: 120,
    room_layout: "theatre",
    equipment: ["projector", "microphone"],
    contact_email: "jane@example.test",
    accept_terms: true,
    optional_note: "",
  }));

  assert.doesNotThrow(() => validatePublicFormAnswers({
    fields: [{ code: "event_date", type: "date", required: true }],
  }, { event_date: "2027-01-18" }));
});

test("public form v1 rejects missing required values and unknown answer keys", () => {
  assert.throws(() => validatePublicFormAnswers(fieldSchema, {
    event_name: "Annual meeting",
    estimated_guests: 120,
    room_layout: "theatre",
    accept_terms: true,
  }), PublicFormAnswersError);

  assert.throws(() => validatePublicFormAnswers(fieldSchema, {
    event_date: "2027-01-18",
    event_name: "Annual meeting",
    estimated_guests: 120,
    room_layout: "theatre",
    accept_terms: true,
    internal_price_override: 0,
  }), PublicFormAnswersError);
});

test("public form v1 enforces value types, ranges, formats and pinned option membership", () => {
  const valid = {
    event_date: "2027-01-18",
    event_name: "Annual meeting",
    estimated_guests: 120,
    room_layout: "theatre",
    accept_terms: true,
  };
  const invalidAnswers: Array<Record<string, unknown>> = [
    { ...valid, event_date: "2027-02-30" },
    { ...valid, estimated_guests: "120" },
    { ...valid, estimated_guests: 0 },
    { ...valid, estimated_guests: 120.5 },
    { ...valid, room_layout: "conference" },
    { ...valid, accept_terms: false },
    { ...valid, contact_email: "not-an-email" },
    { ...valid, equipment: ["projector", "projector"] },
    { ...valid, equipment: ["unpublished-option"] },
  ];

  for (const answers of invalidAnswers) {
    assert.throws(() => validatePublicFormAnswers(fieldSchema, answers), PublicFormAnswersError);
  }
});

test("public form schema validation fails closed on unsupported or ambiguous definitions", () => {
  const invalidSchemas: unknown[] = [
    null,
    {},
    { schemaVersion: 2, fields: [] },
    { fields: [{ code: "event_date", type: "unknown" }] },
    { fields: [
      { code: "event_date", type: "date" },
      { code: "event_date", type: "text" },
    ] },
    { fields: [{ code: "layout", type: "select", options: [] }] },
    { fields: [{ code: "layout", type: "multiselect", options: [{ value: "x", label: "X" }], minItems: 2 }] },
  ];

  for (const schema of invalidSchemas) {
    assert.throws(() => validatePublicFormAnswers(schema, {}), PublicFormSchemaError);
  }
});
