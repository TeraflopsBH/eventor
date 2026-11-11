export type PublicFormFieldType =
  | "text"
  | "textarea"
  | "email"
  | "phone"
  | "number"
  | "date"
  | "datetime"
  | "time"
  | "select"
  | "multiselect"
  | "checkbox";

export class PublicFormSchemaError extends Error {
  constructor() {
    super("The published booking form has an unsupported field schema.");
    this.name = "PublicFormSchemaError";
  }
}

export class PublicFormAnswersError extends Error {
  constructor() {
    super("Submitted answers do not match the published booking form.");
    this.name = "PublicFormAnswersError";
  }
}

interface PublicFormOption {
  readonly value: string;
}

interface PublicFormField {
  readonly code: string;
  readonly type: PublicFormFieldType;
  readonly required: boolean;
  readonly options: readonly PublicFormOption[];
  readonly minLength?: number;
  readonly maxLength?: number;
  readonly min?: number;
  readonly max?: number;
  readonly integer?: boolean;
  readonly minItems?: number;
  readonly maxItems?: number;
}

const supportedTypes = new Set<PublicFormFieldType>([
  "text", "textarea", "email", "phone", "number", "date",
  "datetime", "time", "select", "multiselect", "checkbox",
]);
const codePattern = /^[a-z][a-z0-9_]{0,79}$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum;
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number(value.slice(0, 4)) < 1) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function isDateTime(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return false;
  }
  const datePart = value.slice(0, 10);
  return isCalendarDate(datePart) && Number.isFinite(Date.parse(value));
}

function parseSchema(fieldSchema: unknown): readonly PublicFormField[] {
  if (!isRecord(fieldSchema)) throw new PublicFormSchemaError();
  const version = fieldSchema.schemaVersion === undefined ? 1 : fieldSchema.schemaVersion;
  const schemaProperties = new Set(["schemaVersion", "fields"]);
  if (version !== 1 || !Array.isArray(fieldSchema.fields) || fieldSchema.fields.length > 100 ||
      Object.keys(fieldSchema).some((key) => !schemaProperties.has(key))) {
    throw new PublicFormSchemaError();
  }

  const seenCodes = new Set<string>();
  const fieldProperties = new Set([
    "code", "type", "label", "description", "helpText", "placeholder", "required",
    "options", "minLength", "maxLength", "min", "max", "integer", "minItems", "maxItems",
  ]);
  const fields: PublicFormField[] = [];

  for (const raw of fieldSchema.fields) {
    if (!isRecord(raw) || Object.keys(raw).some((key) => !fieldProperties.has(key)) ||
        typeof raw.code !== "string" || !codePattern.test(raw.code) ||
        seenCodes.has(raw.code) || typeof raw.type !== "string" ||
        !supportedTypes.has(raw.type as PublicFormFieldType) ||
        (raw.required !== undefined && typeof raw.required !== "boolean")) {
      throw new PublicFormSchemaError();
    }
    for (const property of ["label", "placeholder"]) {
      if (raw[property] !== undefined &&
          (typeof raw[property] !== "string" || raw[property].length > 200)) {
        throw new PublicFormSchemaError();
      }
    }
    for (const property of ["description", "helpText"]) {
      if (raw[property] !== undefined &&
          (typeof raw[property] !== "string" || raw[property].length > 1000)) {
        throw new PublicFormSchemaError();
      }
    }
    seenCodes.add(raw.code);

    const type = raw.type as PublicFormFieldType;
    const required = raw.required === true;
    const field: {
      code: string;
      type: PublicFormFieldType;
      required: boolean;
      options: PublicFormOption[];
      minLength?: number;
      maxLength?: number;
      min?: number;
      max?: number;
      integer?: boolean;
      minItems?: number;
      maxItems?: number;
    } = { code: raw.code, type, required, options: [] };

    if (["text", "textarea", "email", "phone"].includes(type)) {
      const minLength = raw.minLength ?? 0;
      const maxLength = raw.maxLength ?? 5000;
      if (!isIntegerInRange(minLength, 0, 5000) ||
          !isIntegerInRange(maxLength, 1, 5000) ||
          minLength > maxLength) throw new PublicFormSchemaError();
      field.minLength = minLength;
      field.maxLength = maxLength;
    } else if (raw.minLength !== undefined || raw.maxLength !== undefined) {
      throw new PublicFormSchemaError();
    }

    if (type === "number") {
      if (raw.min !== undefined && (typeof raw.min !== "number" || !Number.isFinite(raw.min))) {
        throw new PublicFormSchemaError();
      }
      if (raw.max !== undefined && (typeof raw.max !== "number" || !Number.isFinite(raw.max))) {
        throw new PublicFormSchemaError();
      }
      if (typeof raw.min === "number" && typeof raw.max === "number" && raw.min > raw.max) {
        throw new PublicFormSchemaError();
      }
      if (raw.integer !== undefined && typeof raw.integer !== "boolean") {
        throw new PublicFormSchemaError();
      }
      if (typeof raw.min === "number") field.min = raw.min;
      if (typeof raw.max === "number") field.max = raw.max;
      if (typeof raw.integer === "boolean") field.integer = raw.integer;
    } else if (raw.min !== undefined || raw.max !== undefined || raw.integer !== undefined) {
      throw new PublicFormSchemaError();
    }

    if (type === "select" || type === "multiselect") {
      if (!Array.isArray(raw.options) || raw.options.length < 1 || raw.options.length > 250) {
        throw new PublicFormSchemaError();
      }
      const optionValues = new Set<string>();
      for (const rawOption of raw.options) {
        if (!isRecord(rawOption) || Object.keys(rawOption).some((key) => !["value", "label"].includes(key)) ||
            typeof rawOption.value !== "string" || rawOption.value.length < 1 || rawOption.value.length > 200 ||
            typeof rawOption.label !== "string" || rawOption.label.trim().length < 1 ||
            rawOption.label.length > 200 || optionValues.has(rawOption.value)) {
          throw new PublicFormSchemaError();
        }
        optionValues.add(rawOption.value);
        field.options.push({ value: rawOption.value });
      }
      if (type === "multiselect") {
        const minItems = raw.minItems ?? 0;
        const maxItems = raw.maxItems ?? field.options.length;
        if (!isIntegerInRange(minItems, 0, field.options.length) ||
            !isIntegerInRange(maxItems, 1, field.options.length) ||
            minItems > maxItems) throw new PublicFormSchemaError();
        field.minItems = minItems;
        field.maxItems = maxItems;
      } else if (raw.minItems !== undefined || raw.maxItems !== undefined) {
        throw new PublicFormSchemaError();
      }
    } else if (raw.options !== undefined || raw.minItems !== undefined || raw.maxItems !== undefined) {
      throw new PublicFormSchemaError();
    }

    fields.push(field);
  }

  return fields;
}

function validateFieldAnswer(field: PublicFormField, value: unknown): boolean {
  switch (field.type) {
    case "text":
    case "textarea":
      return typeof value === "string" &&
        value.length >= (field.minLength ?? 0) &&
        value.length <= (field.maxLength ?? 5000);
    case "email":
      return typeof value === "string" &&
        value.length >= (field.minLength ?? 0) &&
        value.length <= (field.maxLength ?? 5000) &&
        /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
    case "phone":
      return typeof value === "string" &&
        value.length >= Math.max(3, field.minLength ?? 0) &&
        value.length <= Math.min(50, field.maxLength ?? 50) &&
        /^[+0-9().\s-]+$/.test(value) && (value.match(/[0-9]/g)?.length ?? 0) >= 3;
    case "number":
      return typeof value === "number" && Number.isFinite(value) &&
        (field.min === undefined || value >= field.min) &&
        (field.max === undefined || value <= field.max) &&
        (field.integer !== true || Number.isInteger(value));
    case "date":
      return typeof value === "string" && isCalendarDate(value);
    case "datetime":
      return typeof value === "string" && isDateTime(value);
    case "time":
      return typeof value === "string" &&
        /^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(value);
    case "select":
      return typeof value === "string" && field.options.some((option) => option.value === value);
    case "multiselect":
      return Array.isArray(value) &&
        value.length >= (field.minItems ?? 0) &&
        value.length <= (field.maxItems ?? field.options.length) &&
        value.every((item) => typeof item === "string" &&
          field.options.some((option) => option.value === item)) &&
        new Set(value).size === value.length;
    case "checkbox":
      return typeof value === "boolean" && (!field.required || value === true);
  }
}

/**
 * Validates answer values against the immutable field_schema of the exact
 * published booking-form revision. Missing schemaVersion is treated as v1 for
 * compatibility with revisions published before this contract was formalized.
 */
export function validatePublicFormAnswers(fieldSchema: unknown, answers: unknown): void {
  const fields = parseSchema(fieldSchema);
  if (!isRecord(answers)) throw new PublicFormAnswersError();

  const fieldsByCode = new Map(fields.map((field) => [field.code, field]));
  for (const code of Object.keys(answers)) {
    if (!fieldsByCode.has(code)) throw new PublicFormAnswersError();
  }

  for (const field of fields) {
    const value = answers[field.code];
    const isMissing = value === null || value === undefined ||
      (typeof value === "string" && value.trim().length === 0) ||
      (Array.isArray(value) && value.length === 0 && field.type !== "multiselect");
    if (isMissing) {
      if (field.required) throw new PublicFormAnswersError();
      continue;
    }
    if (field.type === "multiselect" && Array.isArray(value) && value.length === 0 && field.required) {
      throw new PublicFormAnswersError();
    }
    if (!validateFieldAnswer(field, value)) throw new PublicFormAnswersError();
  }
}
