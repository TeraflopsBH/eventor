# Public booking form field schema v1

This document defines the validation contract for the `field_schema` JSONB value stored on an immutable `booking_form_revisions` row and returned by the public booking-form projection.

## Versioning

A new published schema should include `"schemaVersion": 1`. Existing revisions that predate this contract and contain only `{"fields":[...]}` are interpreted as version 1. An explicit `null`, unknown version or unsupported field definition is invalid. Unknown future versions must not be interpreted as version 1.

The public submission API loads the exact revision identified by `formRevisionId`, verifies that it belongs to the requested active form and organization, and validates answers against that revision before encrypting or submitting them. A newer publication does not change an already published revision; a still-published older revision remains submit-capable. The database submission command rechecks that the same revision is still published immediately before creating the inquiry.

## Schema shape

```json
{
  "schemaVersion": 1,
  "fields": [
    {
      "code": "event_date",
      "type": "date",
      "label": "Requested event date",
      "required": true
    },
    {
      "code": "event_name",
      "type": "text",
      "label": "Event name",
      "required": true,
      "minLength": 2,
      "maxLength": 120
    },
    {
      "code": "estimated_guests",
      "type": "number",
      "label": "Estimated guests",
      "required": true,
      "integer": true,
      "min": 1,
      "max": 5000
    },
    {
      "code": "room_layout",
      "type": "select",
      "label": "Preferred room layout",
      "required": true,
      "options": [
        { "value": "theatre", "label": "Theatre" },
        { "value": "banquet", "label": "Banquet" }
      ]
    },
    {
      "code": "equipment",
      "type": "multiselect",
      "label": "Requested equipment",
      "required": false,
      "minItems": 0,
      "maxItems": 2,
      "options": [
        { "value": "projector", "label": "Projector" },
        { "value": "microphone", "label": "Microphone" }
      ]
    },
    {
      "code": "accept_terms",
      "type": "checkbox",
      "label": "I accept the stated terms",
      "required": true
    }
  ]
}
```

Each field has a unique `code` matching `^[a-z][a-z0-9_]{0,79}$`. A schema may contain at most 100 fields. `required` defaults to false. Labels and descriptive presentation properties do not change validation behavior.

## Supported field types

| Type | Submitted JSON value | Validation |
|---|---|---|
| `text` | string | `minLength` / `maxLength`; default maximum 5,000 characters |
| `textarea` | string | Same string-length rules as `text` |
| `email` | string | String-length rules plus a basic email-address format check |
| `phone` | string | 3–50 characters, digits and common international phone punctuation only |
| `number` | JSON number | Finite number; optional `min`, `max`, and `integer: true` constraints |
| `date` | string | Real calendar date in `YYYY-MM-DD` format |
| `datetime` | string | ISO date-time with an explicit `Z` or numeric UTC offset |
| `time` | string | 24-hour `HH:mm` or `HH:mm:ss` |
| `select` | string | Must exactly match one configured option value |
| `multiselect` | array of strings | Every value must match an option; duplicates are rejected; optional `minItems` / `maxItems` apply |
| `checkbox` | boolean | Must be a JSON boolean; a required checkbox must be `true` |

For `select` and `multiselect`, `options` is a non-empty array of unique objects with non-empty `value` and `label` strings (each at most 200 characters). Those values are part of the immutable form revision and are the accepted answer values.

String fields may define integer `minLength` and `maxLength` values from 0 through 5,000, with `maxLength` at least 1 and not less than `minLength`. Numeric `min` and `max` must be finite and `min` cannot exceed `max`. `integer` is valid only for number fields. Multi-select item bounds must be integers within the number of configured options and `minItems` cannot exceed `maxItems`.

## Answer semantics

The `answers` object is keyed by field `code`. Unknown keys are rejected rather than silently stored. Every required field must have a value. For non-checkbox fields, `null`, an empty string (including whitespace-only text), an omitted property and an empty array are treated as unanswered. A required checkbox is only satisfied by `true`; `false` is an explicit negative answer and does not satisfy a required acknowledgement.

Optional fields may be omitted. If a value is supplied, it must match the declared JSON type and every constraint for that field. Numeric strings are not numbers. Choice answers must use the option values from the exact submitted revision; labels are not accepted in place of values.

## Enforcement and boundaries

Validation runs in the Fastify public inquiry route after the exact revision projection is loaded and before ECP1 encryption and the database submission command. Invalid answers return HTTP 422 and do not consume an inquiry rate-limit slot. A malformed or unsupported published schema fails closed with HTTP 500 and is not accepted as valid input.

The database stores the full submitted answer object encrypted with the tenant-bound ECP1 contact codec. The database cannot inspect those ciphertext values; callers must use the API boundary rather than invoking the privileged submission function outside the trusted application.

The v1 public projection currently supports options embedded directly in `field_schema`. Catalogue-bound option expansion, conditional visibility/dependency rules, file-upload fields and attachments are not part of v1. Non-empty attachment references continue to receive HTTP 422 until a separate authorized, malware-scanned upload workflow is implemented.
