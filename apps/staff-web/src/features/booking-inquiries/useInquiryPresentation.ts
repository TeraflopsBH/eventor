import { useI18n } from "vue-i18n";
import { resolveLocale } from "../../i18n";
import { formatBookingMoney, formatInquiryDate } from "./presentation";

export function useInquiryPresentation() {
  const { locale, t } = useI18n();
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

  return {
    formatDate(value: string | null | undefined): string {
      return formatInquiryDate(value, resolveLocale(locale.value), timeZone, t("common.notProvided"));
    },
    formatMoney(value: string | number, currency: string): string {
      return formatBookingMoney(value, currency, resolveLocale(locale.value));
    },
  };
}
