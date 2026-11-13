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
