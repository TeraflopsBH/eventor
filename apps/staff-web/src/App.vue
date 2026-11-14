<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import type { SupportedLocale } from "./i18n";
import PublicBookingOfferPage from "./features/public-booking-offers/PublicBookingOfferPage.vue";
import PublicBookingFormPage from "./features/public-booking-forms/PublicBookingFormPage.vue";
import GuestInvitationPage from "./features/guest-invitations/GuestInvitationPage.vue";
import StaffApplicationShell from "./features/application-shell/StaffApplicationShell.vue";
import OrganizationLocaleView from "./features/application-shell/OrganizationLocaleView.vue";
import { useStaffSession } from "./features/application-shell/useStaffSession";
import { useBookingInquiries } from "./features/booking-inquiries/useBookingInquiries";
import { useBookingDraft } from "./features/booking-drafts/useBookingDraft";
import { useBookingOffers } from "./features/booking-offers/useBookingOffers";
import { useBookingPriceLists } from "./features/booking-prices/useBookingPriceLists";
import { useBookingTaxProfiles } from "./features/booking-taxes/useBookingTaxProfiles";
import { useBookingApprovalPolicies } from "./features/booking-approvals/useBookingApprovalPolicies";
import { useBookingCancellationPolicies } from "./features/booking-cancellations/useBookingCancellationPolicies";
import BookingInquiryView from "./features/booking-inquiries/BookingInquiryView.vue";
import BookingPriceListsView from "./features/booking-prices/BookingPriceListsView.vue";
import BookingTaxProfilesView from "./features/booking-taxes/BookingTaxProfilesView.vue";
import BookingApprovalPoliciesView from "./features/booking-approvals/BookingApprovalPoliciesView.vue";
import BookingCancellationPoliciesView from "./features/booking-cancellations/BookingCancellationPoliciesView.vue";
import { useCampaigns } from "./features/campaigns/useCampaigns";
import CampaignWorkspaceView from "./features/campaigns/CampaignWorkspaceView.vue";
import { useEmailDelivery } from "./features/email-delivery/useEmailDelivery";
import EmailDeliveryView from "./features/email-delivery/EmailDeliveryView.vue";
import CommercialBookingWorkspaceView from "./features/booking-drafts/CommercialBookingWorkspaceView.vue";
import { api } from "./api";
import { useBookingForms } from "./features/booking-forms/useBookingForms";
import BookingFormsView from "./features/booking-forms/BookingFormsView.vue";

const { locale, t } = useI18n();
const translate = (key: string, params?: Record<string, string | number>): string => t(key as never, params as never);
watch(locale, (value) => { document.documentElement.lang = value; }, { immediate: true });
const localeOptions: Array<{ value: SupportedLocale; label: string }> = [
  { value: "bs-BA", label: "Bosanski" },
  { value: "en", label: "English" },
];

const isPublicOfferPage = /^\/offers\/[0-9a-fA-F-]{36}\/?$/.test(window.location.pathname);
const isPublicBookingFormPage = /^\/book\/[A-Za-z0-9][A-Za-z0-9-]{1,79}\/[A-Za-z0-9][A-Za-z0-9_-]{1,79}\/?$/.test(window.location.pathname);
const isGuestInvitationPage = /(?:^|\/)guest\/invitation\/?$/.test(window.location.pathname);
const activeTab = ref<"delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes" | "forms" | "settings">("delivery");
const busy = ref(false);
const pageError = ref("");
const pageNotice = ref("");

let loadEmailConfiguration: () => Promise<void> = async () => {};
let resetWorkspace: () => void = () => {};
const staffSessionState = useStaffSession({
  api, busy, pageError, pageNotice, clearMessages,
  loadConfiguration: () => loadEmailConfiguration(),
  resetWorkspace: () => resetWorkspace(),
  translate,
  applyLocale: (value) => { locale.value = value as SupportedLocale; },
});
const { principal, showError, refreshSession } = staffSessionState;

function applyOrganizationDefaultLocale(value: SupportedLocale): void {
  if (principal.value?.userLocale === null) locale.value = value;
}
const organizationLocaleWorkspace = { busy, pageNotice };


const canReadBookingDraft = computed(() =>
  inquiryCapabilities.value.canReadDraft && Boolean(inquiryDetail.value?.bookingDraft),
);

function clearMessages(): void {
  pageError.value = "";
  pageNotice.value = "";
}

let resetBookingDraftState = (): void => {};

function clearBookingDraftState(): void {
  resetBookingDraftState();
  bookingOfferState.reset();
}

const bookingInquiryState = useBookingInquiries({
  principal, busy, activeTab, pageError, pageNotice, api,
  clearMessages, showError, clearBookingDraftState, translate,
});
const bookingInquiryWorkspace = { ...bookingInquiryState, principal, busy, canReadBookingDraft };
const {
  inquiryDetail, inquiryCapabilities, refreshInquiryDetailData, openInquiryWorkspace,
  reset: resetBookingInquiries,
} = bookingInquiryState;

const bookingDraftState = useBookingDraft({
  api,
  busy,
  pageError,
  pageNotice,
  canManageDraftPermission: computed(() => inquiryCapabilities.value.canManageDraft),
  clearMessages,
  showError,
  refreshInquiryDetail: refreshInquiryDetailData,
  translate,
});
resetBookingDraftState = bookingDraftState.reset;


const bookingDraftDetail = bookingDraftState.detail;
const refreshBookingDraft = bookingDraftState.refresh;
const bookingOfferState = useBookingOffers({
  api, busy, pageError, pageNotice, principal, bookingDraftDetail,
  clearMessages, showError, refreshBookingDraft, refreshInquiryDetail: refreshInquiryDetailData, translate,
});
const commercialBookingWorkspace = { ...bookingDraftState, ...bookingOfferState, busy };

const bookingTaxProfileState = useBookingTaxProfiles({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError, translate,
});
const bookingTaxProfilesWorkspace = { ...bookingTaxProfileState, busy };
const { publishedTaxProfileRevisions, loadBookingTaxProfiles } = bookingTaxProfileState;

const bookingPriceListState = useBookingPriceLists({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
  publishedTaxProfileRevisions, loadBookingTaxProfiles, translate,
});
const bookingPriceListsWorkspace = { ...bookingPriceListState, busy };


const bookingApprovalPolicyState = useBookingApprovalPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError, translate,
});
const bookingApprovalPoliciesWorkspace = { ...bookingApprovalPolicyState, busy };


const bookingFormState = useBookingForms({ api, busy, pageError, pageNotice, clearMessages, showError, translate });
const bookingFormsWorkspace = { ...bookingFormState, busy };

const bookingCancellationPolicyState = useBookingCancellationPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError, translate,
});
const bookingCancellationPoliciesWorkspace = { ...bookingCancellationPolicyState, busy };

const campaignState = useCampaigns({
  api, busy, pageError, pageNotice, clearMessages, showError, translate,
});
const emailDeliveryState = useEmailDelivery({
  api, busy, pageError, pageNotice, clearMessages, showError, translate,
});
const { configuration, loadConfiguration } = emailDeliveryState;
loadEmailConfiguration = loadConfiguration;
resetWorkspace = (): void => {
  emailDeliveryState.reset();
  campaignState.reset();
  resetBookingInquiries();
};
const staffShellWorkspace = {
  ...staffSessionState, busy, pageError, pageNotice, activeTab, locale, localeOptions,
  openInquiryWorkspace,
  openBookingApprovalPolicies: bookingApprovalPolicyState.openBookingApprovalPolicies,
  openBookingPriceLists: bookingPriceListState.openBookingPriceLists,
  openBookingCancellationPolicies: bookingCancellationPolicyState.openBookingCancellationPolicies,
  openBookingTaxProfiles: bookingTaxProfileState.openBookingTaxProfiles,
  openBookingForms: async () => { activeTab.value = "forms"; await bookingFormState.open(); },
};
const campaignWorkspace = { ...campaignState, busy, configuration };
const emailDeliveryWorkspace = { ...emailDeliveryState, busy };



async function openBookingDraft(): Promise<void> {
  const draftReference = inquiryDetail.value?.bookingDraft;
  await bookingDraftState.open(draftReference?.draftId, inquiryCapabilities.value.canReadDraft);
}






























onMounted(() => {
  if (!isPublicOfferPage && !isPublicBookingFormPage && !isGuestInvitationPage) void refreshSession();
});

</script>


<template>
  <PublicBookingFormPage v-if="isPublicBookingFormPage" />
  <PublicBookingOfferPage v-else-if="isPublicOfferPage" />
  <GuestInvitationPage v-else-if="isGuestInvitationPage" />
  <StaffApplicationShell v-else :workspace="staffShellWorkspace">
    <EmailDeliveryView v-if="activeTab === 'delivery'" :workspace="emailDeliveryWorkspace" />
    <BookingInquiryView
        v-else-if="activeTab === 'inquiries'"
        :workspace="bookingInquiryWorkspace"
        @open-booking-draft="openBookingDraft"
      >
        <template #booking-draft-editor>
          <CommercialBookingWorkspaceView section="draft-editor" :workspace="commercialBookingWorkspace" />
        </template>
        <template #booking-offer-workspace>
          <CommercialBookingWorkspaceView section="offer-workspace" :workspace="commercialBookingWorkspace" />
        </template>
      </BookingInquiryView>


      <BookingFormsView v-else-if="activeTab === 'forms'" :workspace="bookingFormsWorkspace" />

      <BookingPriceListsView v-else-if="activeTab === 'prices'" :workspace="bookingPriceListsWorkspace" />

      <BookingApprovalPoliciesView v-else-if="activeTab === 'approvals'" :workspace="bookingApprovalPoliciesWorkspace" />

      <BookingTaxProfilesView v-else-if="activeTab === 'taxes'" :workspace="bookingTaxProfilesWorkspace" />

      <BookingCancellationPoliciesView v-else-if="activeTab === 'cancellations'" :workspace="bookingCancellationPoliciesWorkspace" />

      <OrganizationLocaleView v-else-if="activeTab === 'settings'" :busy="organizationLocaleWorkspace.busy" :page-notice="organizationLocaleWorkspace.pageNotice" :show-error="showError" :translate="translate" :on-default-locale-changed="applyOrganizationDefaultLocale" />

      <CampaignWorkspaceView v-else :workspace="campaignWorkspace" />
    
  </StaffApplicationShell>
</template>
