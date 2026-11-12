import assert from "node:assert/strict";
import test from "node:test";
import { formatBookingAnswerItems } from "../src/features/booking-inquiries/presentation.ts";

test("interprets converted draft answers using the pinned source revision schema", () => {
  const sourceRevisionId = "12121212-1212-4121-8121-121212121212";
  const draft = {
    currentRevision: {
      sourceFormRevisionId: sourceRevisionId,
      fieldSchema: {
        schemaVersion: 1,
        fields: [
          { code: "event_date", type: "date", label: "Event date" },
          { code: "event_name", type: "text", label: "Event name" },
          {
            code: "equipment",
            type: "multiselect",
            label: "Equipment",
            options: [
              { value: "projector", label: "Projector" },
              { value: "microphone", label: "Microphone" },
            ],
          },
          { code: "accept_terms", type: "checkbox", label: "Terms accepted" },
        ],
      },
      values: {
        answers: {
          event_date: "2027-01-18",
          event_name: "Community lecture",
          equipment: ["projector", "microphone"],
          accept_terms: true,
        },
      },
    },
  };

  assert.equal(draft.currentRevision.sourceFormRevisionId, sourceRevisionId);
  assert.deepEqual(
    formatBookingAnswerItems(draft.currentRevision.fieldSchema, draft.currentRevision.values.answers),
    [
      { code: "event_date", label: "Event date", type: "date", value: "2027-01-18" },
      { code: "event_name", label: "Event name", type: "text", value: "Community lecture" },
      { code: "equipment", label: "Equipment", type: "multiselect", value: "Projector, Microphone" },
      { code: "accept_terms", label: "Terms accepted", type: "checkbox", value: "Yes" },
    ],
  );
});

test("keeps unknown legacy answer keys visible instead of silently dropping them", () => {
  assert.deepEqual(
    formatBookingAnswerItems({ fields: [{ code: "known_field", type: "text", label: "Known field" }] }, {
      known_field: "Value",
      legacy_answer: "Preserved value",
    }),
    [
      { code: "known_field", label: "Known field", type: "text", value: "Value" },
      { code: "legacy_answer", label: "legacy answer", type: "unknown", value: "Preserved value" },
    ],
  );
});

test("returns an empty answer list when a converted draft has no submitted answers", () => {
  assert.deepEqual(formatBookingAnswerItems({ fields: [] }, {}), []);
  assert.deepEqual(formatBookingAnswerItems(null, null), []);
});
