import { createI18n } from "vue-i18n";
import en from "./messages/en";
import bsBA from "./messages/bs-BA";

export const supportedLocales = ["bs-BA", "en"] as const;
export type SupportedLocale = (typeof supportedLocales)[number];

export function isSupportedLocale(value: unknown): value is SupportedLocale {
  return typeof value === "string" && supportedLocales.includes(value as SupportedLocale);
}

export function resolveLocale(value: unknown): SupportedLocale {
  return isSupportedLocale(value) ? value : "en";
}

export const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: "en",
  fallbackLocale: "en",
  messages: {
    en,
    "bs-BA": bsBA,
  },
  missingWarn: import.meta.env.DEV,
  fallbackWarn: import.meta.env.DEV,
});

export function setLocale(value: unknown): SupportedLocale {
  const locale = resolveLocale(value);
  i18n.global.locale.value = locale;
  if (typeof document !== "undefined") document.documentElement.lang = locale;
  return locale;
}
