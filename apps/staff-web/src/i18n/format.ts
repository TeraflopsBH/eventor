import type { SupportedLocale } from "./index";

export function formatDateTime(value: string | Date | null | undefined, locale: string, timeZoneOrOptions?: string | Intl.DateTimeFormatOptions): string {
  if (value === null || value === undefined || value === "") return "—";
  const options: Intl.DateTimeFormatOptions = typeof timeZoneOrOptions === "string" ? { timeZone: timeZoneOrOptions } : timeZoneOrOptions ?? {};
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) return "—";
  if (locale === "bs-BA") {
    const formatter = new Intl.DateTimeFormat("bs-BA", {
      year: "numeric", month: "2-digit", day: "2-digit",
      ...(options.timeStyle === undefined && options.dateStyle && !options.hour ? {} : { hour: "2-digit", minute: "2-digit", hourCycle: "h23" as const }),
      ...(options.timeZone ? { timeZone: options.timeZone } : {}),
    });
    const parts = Object.fromEntries(formatter.formatToParts(date).map(part => [part.type, part.value]));
    return `${parts.day}.${parts.month}.${parts.year}${parts.hour ? ` ${parts.hour}:${parts.minute}` : ""}`;
  }
  const dateOnly = options.dateStyle && !options.timeStyle && !options.hour;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", ...(dateOnly ? {} : { timeStyle: "short" as const }), ...options }).format(date);
}

export function formatMoney(
  value: string | number,
  currency: string,
  locale: SupportedLocale,
): string {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return `${String(value)} ${currency}`;
  try {
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency,
      maximumFractionDigits: 4,
    }).format(amount);
  } catch {
    return `${amount.toFixed(2)} ${currency}`;
  }
}

export function formatNumber(
  value: number,
  locale: SupportedLocale,
  options: Intl.NumberFormatOptions = {},
): string {
  return new Intl.NumberFormat(locale, options).format(value);
}
