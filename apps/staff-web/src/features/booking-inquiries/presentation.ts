import type { BookingInquiryAssignee, BookingInquiryDetail } from "../../api";
import type { SupportedLocale } from "../../i18n";

export function formatInquiryAnswer(
  field: BookingInquiryDetail["fieldSchema"]["fields"][number] | undefined,
  value: unknown,
): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if ((field?.type === "select" || field?.type === "multiselect") && typeof value === "string") {
    return field.options?.find((option) => option.value === value)?.label ?? value;
  }
  if (value && typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export function resolveInquiryAssigneeName(
  membershipId: string | null,
  currentMembershipId: string | null | undefined,
  assignees: readonly BookingInquiryAssignee[],
): string {
  if (!membershipId) return "Unassigned";
  if (membershipId === currentMembershipId) return "You";
  return assignees.find((item) => item.membershipId === membershipId)?.displayName ?? "Assigned member";
}

export function formatInquiryDate(
  value: string | null | undefined,
  locale: SupportedLocale,
  timeZone: string,
  emptyLabel: string,
): string {
  if (!value) return emptyLabel;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone,
  }).format(parsed);
}

export function formatBookingMoney(
  value: string | number,
  currency: string,
  locale: SupportedLocale,
): string {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return String(value) + " " + currency;
  try {
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency,
      maximumFractionDigits: 4,
    }).format(amount);
  } catch {
    return amount.toFixed(2) + " " + currency;
  }
}

export interface BookingAnswerFieldSchema {
  fields: readonly {
    code: string;
    type: string;
    label?: string;
    options?: readonly { value: string; label: string }[];
  }[];
}

export interface BookingAnswerItem {
  code: string;
  label: string;
  type: string;
  value: string;
}

/**
 * Interpret stored answer values only with the schema pinned to their source
 * form revision. This is used for both inquiry review and converted drafts.
 */
export function formatBookingAnswerItems(
  fieldSchema: BookingAnswerFieldSchema | null | undefined,
  answers: Readonly<Record<string, unknown>> | null | undefined,
): BookingAnswerItem[] {
  if (!answers) return [];
  const fields = new Map((fieldSchema?.fields ?? []).map((field) => [field.code, field]));
  return Object.entries(answers).map(([code, value]) => {
    const field = fields.get(code);
    const displayValue = Array.isArray(value)
      ? value.map((item) => formatInquiryAnswer(field, item)).join(", ")
      : formatInquiryAnswer(field, value);
    return {
      code,
      label: field?.label?.trim() || code.replaceAll("_", " "),
      type: field?.type ?? "unknown",
      value: displayValue,
    };
  });
}
