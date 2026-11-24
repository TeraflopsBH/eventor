// Store only display preferences, never credentials or session tokens.
const localeKey = "eventor.staff.locale";
const pendingKey = "eventor.staff.pendingLocale";
type Locale = "bs-BA" | "en";
export interface PendingStaffLocale { id: string; locale: Locale; userId: string | null }
function storage(): Storage | null {
  try { return typeof localStorage === "undefined" ? null : localStorage; } catch { return null; }
}
function validLocale(value: unknown): value is Locale { return value === "bs-BA" || value === "en"; }
export function storedStaffLocale(): Locale | null {
  try { const value = storage()?.getItem(localeKey); return validLocale(value) ? value : null; } catch { return null; }
}
export function rememberStaffLocale(locale: Locale): void {
  try { storage()?.setItem(localeKey, locale); } catch { /* Browser storage is optional. */ }
}
export function queueStaffLocale(locale: Locale, userId: string | null): PendingStaffLocale {
  const pending = { id: globalThis.crypto.randomUUID(), locale, userId };
  rememberStaffLocale(locale);
  try { storage()?.setItem(pendingKey, JSON.stringify(pending)); } catch { /* Keep live UI usable. */ }
  return pending;
}
export function pendingStaffLocale(userId: string): PendingStaffLocale | null {
  try {
    const raw = storage()?.getItem(pendingKey);
    if (!raw) return null;
    const value: unknown = JSON.parse(raw);
    if (!value || typeof value !== "object") return null;
    const candidate = value as Partial<PendingStaffLocale>;
    return typeof candidate.id === "string" && validLocale(candidate.locale)
      && (candidate.userId === null || candidate.userId === userId) ? candidate as PendingStaffLocale : null;
  } catch { return null; }
}
export function acknowledgeStaffLocale(pending: PendingStaffLocale): void {
  try {
    const current = storage()?.getItem(pendingKey);
    if (current && JSON.parse(current).id === pending.id) storage()?.removeItem(pendingKey);
  } catch { /* A later refresh may safely retry the same preference. */ }
}
