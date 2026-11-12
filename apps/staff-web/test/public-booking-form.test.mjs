import assert from "node:assert/strict";
import test from "node:test";
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
} from "../src/features/public-booking-forms/publicBookingForm.ts";

function makeForm(overrides = {}) {
  return {
    organizationId: "11111111-1111-4111-8111-111111111111",
    organizationSlug: "ghb",
    organizationName: "GHB",
    defaultLocale: "en",
    defaultTimezone: "Europe/Sarajevo",
    formCode: "venue-rental",
    formName: "Venue rental inquiry",
    formRevisionId: "12121212-1212-4121-8121-121212121212",
    revisionNumber: 3,
    locale: "bs-BA",
    fieldSchema: {
      schemaVersion: 1,
      fields: [
        { code: "event_name", type: "text", label: "Naziv događaja", description: "Opis", helpText: "Pomoć", placeholder: "Unesite naziv", required: true, maxLength: 120 },
        {
          code: "equipment",
          type: "multiselect",
          label: "Oprema",
          required: false,
          minItems: 1,
          maxItems: 2,
          options: [
            { value: "projector", label: "Projektor" },
            { value: "microphone", label: "Mikrofon" },
            { value: "speaker", label: "Zvučnik" },
          ],
        },
        { code: "estimated_guests", type: "number", label: "Broj gostiju", min: 1, max: 5000, integer: true },
        { code: "accept_terms", type: "checkbox", label: "Prihvatam uslove", required: true },
      ],
      contentTranslations: {
        en: {
          formName: "Venue rental",
          fields: {
            event_name: {
              label: "Event name",
              description: "Describe the event",
              helpText: "Add useful context",
              placeholder: "Enter a name",
            },
            equipment: {
              label: "Equipment",
              options: { projector: "Projector", microphone: "Microphone", speaker: "Speaker" },
            },
            estimated_guests: { label: "Estimated guests" },
            accept_terms: { label: "I accept the terms" },
          },
        },
      },
    },
    publishedAt: "2026-10-01T10:00:00Z",
    ...overrides,
  };
}

test("renders translated form and field content with per-item fallback to the published source locale", () => {
  const form = makeForm({
    fieldSchema: {
      ...makeForm().fieldSchema,
      contentTranslations: {
        en: {
          formName: "Venue rental",
          fields: {
            event_name: { label: "Event name" },
            equipment: { options: { projector: "Projector" } },
          },
        },
      },
    },
  });
  const field = form.fieldSchema.fields[0];
  const equipment = form.fieldSchema.fields[1];

  assert.equal(publicBookingFormName(form, "en"), "Venue rental");
  assert.equal(publicBookingFieldText(form, field, "en", "label"), "Event name");
  assert.equal(publicBookingFieldText(form, field, "en", "description"), "Opis");
  assert.equal(publicBookingFieldText(form, field, "en", "helpText"), "Pomoć");
  assert.equal(publicBookingFieldText(form, field, "en", "placeholder"), "Unesite naziv");
  assert.equal(publicBookingOptionLabel(form, equipment, "en", "projector", "Projektor"), "Projector");
  assert.equal(publicBookingOptionLabel(form, equipment, "en", "microphone", "Mikrofon"), "Mikrofon");
});

test("reports missing translations only when customer-visible source content falls back", () => {
  const form = makeForm();
  assert.equal(publicBookingContentHasFallback(form, "bs-BA"), false);
  assert.equal(publicBookingContentHasFallback(form, "en"), false);

  form.fieldSchema.contentTranslations.en.fields.event_name.placeholder = undefined;
  assert.equal(publicBookingContentHasFallback(form, "en"), true);

  delete form.fieldSchema.contentTranslations.en;
  assert.equal(publicBookingContentHasFallback(form, "en"), true);
});

test("initializes only controls that need explicit empty values", () => {
  const answers = initializePublicBookingAnswers(makeForm().fieldSchema.fields);
  assert.deepEqual(answers, { equipment: [], accept_terms: false });
});

test("multiselect toggling is idempotent and preserves other selections", () => {
  const answers = { equipment: ["projector"] };
  togglePublicBookingOption(answers, "equipment", "microphone", true);
  togglePublicBookingOption(answers, "equipment", "microphone", true);
  assert.deepEqual(selectedPublicBookingValues(answers, "equipment"), ["projector", "microphone"]);
  togglePublicBookingOption(answers, "equipment", "projector", false);
  assert.deepEqual(selectedPublicBookingValues(answers, "equipment"), ["microphone"]);
  assert.deepEqual(selectedPublicBookingValues({ equipment: ["x", 2, null] }, "equipment"), ["x"]);
});

test("multiselect client validation enforces required, configured minimum and maximum bounds", () => {
  const fields = makeForm().fieldSchema.fields.filter(field => field.code === "equipment");
  assert.deepEqual(validatePublicBookingChoices(fields, { equipment: [] }), {
    code: "equipment", kind: "minimum", count: 0, minimum: 1,
  });
  assert.deepEqual(validatePublicBookingChoices(fields, { equipment: ["projector", "microphone", "speaker"] }), {
    code: "equipment", kind: "maximum", count: 3, maximum: 2,
  });
  assert.equal(validatePublicBookingChoices(fields, { equipment: ["projector", "microphone"] }), null);
});

test("required multiselect cannot be bypassed by a zero configured minimum", () => {
  const fields = [{
    code: "equipment",
    type: "multiselect",
    required: true,
    minItems: 0,
    options: [{ value: "projector", label: "Projector" }],
  }];
  assert.deepEqual(validatePublicBookingChoices(fields, { equipment: [] }), {
    code: "equipment", kind: "minimum", count: 0, minimum: 1,
  });
});

test("normalizes number inputs while preserving optional blank and non-number values", () => {
  const form = makeForm();
  const payload = buildPublicBookingInquirySubmission(
    form,
    "en",
    { displayName: "  Jane Example  ", email: " jane@example.test ", phone: "   " },
    {
      event_name: "Annual meeting",
      equipment: ["projector"],
      estimated_guests: "120",
      accept_terms: true,
      ignored_answer: "not in published schema",
    },
  );
  assert.equal(payload.answers.estimated_guests, 120);
  assert.equal("ignored_answer" in payload.answers, false);
  assert.equal(payload.answers.event_name, "Annual meeting");
});

test("submission pins the exact loaded published revision and selected customer locale", () => {
  const form = makeForm();
  const payload = buildPublicBookingInquirySubmission(
    form,
    "en",
    { displayName: "  Jane Example ", email: " jane@example.test ", phone: " +38761123456 " },
    { event_name: "Annual meeting", equipment: [], estimated_guests: "120", accept_terms: true },
  );

  assert.equal(payload.formCode, "venue-rental");
  assert.equal(payload.formRevisionId, "12121212-1212-4121-8121-121212121212");
  assert.equal(payload.customerLocale, "en");
  assert.deepEqual(payload.requester, {
    displayName: "Jane Example",
    email: "jane@example.test",
    phone: "+38761123456",
  });
  assert.deepEqual(payload.requested, {});
  assert.equal(payload.answers.estimated_guests, 120);
});

test("omits blank optional requester contact details without changing the requester name", () => {
  const payload = buildPublicBookingInquirySubmission(
    makeForm(),
    "bs-BA",
    { displayName: "  Nedim  ", email: " ", phone: "" },
    {},
  );
  assert.deepEqual(payload.requester, { displayName: "Nedim" });
});
