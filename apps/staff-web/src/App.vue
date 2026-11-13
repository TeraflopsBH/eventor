<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import type { SupportedLocale } from "./i18n";
import PublicBookingOfferPage from "./features/public-booking-offers/PublicBookingOfferPage.vue";
import StaffApplicationShell from "./features/application-shell/StaffApplicationShell.vue";
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

const { locale } = useI18n();
watch(locale, (value) => { document.documentElement.lang = value; }, { immediate: true });
const localeOptions: Array<{ value: SupportedLocale; label: string }> = [
  { value: "bs-BA", label: "Bosanski" },
  { value: "en", label: "English" },
];

const isPublicOfferPage = /^\/offers\/[0-9a-fA-F-]{36}\/?$/.test(window.location.pathname);
const activeTab = ref<"delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes">("delivery");
const busy = ref(false);
const pageError = ref("");
const pageNotice = ref("");

let loadEmailConfiguration: () => Promise<void> = async () => {};
let resetWorkspace: () => void = () => {};
const staffSessionState = useStaffSession({
  api, busy, pageError, pageNotice, clearMessages,
  loadConfiguration: () => loadEmailConfiguration(),
  resetWorkspace: () => resetWorkspace(),
});
const { principal, showError, refreshSession } = staffSessionState;

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
  clearMessages, showError, clearBookingDraftState,
});
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
});
resetBookingDraftState = bookingDraftState.reset;


const bookingDraftDetail = bookingDraftState.detail;
const refreshBookingDraft = bookingDraftState.refresh;
const bookingOfferState = useBookingOffers({
  api, busy, pageError, pageNotice, principal, bookingDraftDetail,
  clearMessages, showError, refreshBookingDraft, refreshInquiryDetail: refreshInquiryDetailData,
});
const commercialBookingWorkspace = { ...bookingDraftState, ...bookingOfferState, busy };

const bookingTaxProfileState = useBookingTaxProfiles({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});
const { publishedTaxProfileRevisions, loadBookingTaxProfiles } = bookingTaxProfileState;

const bookingPriceListState = useBookingPriceLists({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
  publishedTaxProfileRevisions, loadBookingTaxProfiles,
});


const bookingApprovalPolicyState = useBookingApprovalPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});


const bookingCancellationPolicyState = useBookingCancellationPolicies({
  api, busy, pageError, pageNotice, activeTab, clearMessages, showError,
});

const campaignState = useCampaigns({
  api, busy, pageError, pageNotice, clearMessages, showError,
});
const emailDeliveryState = useEmailDelivery({
  api, busy, pageError, pageNotice, clearMessages, showError,
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
};
const campaignWorkspace = { ...campaignState, busy, configuration };
const emailDeliveryWorkspace = { ...emailDeliveryState, busy };



async function openBookingDraft(): Promise<void> {
  const draftReference = inquiryDetail.value?.bookingDraft;
  await bookingDraftState.open(draftReference?.draftId, inquiryCapabilities.value.canReadDraft);
}






























onMounted(() => {
  if (!isPublicOfferPage) void refreshSession();
});

</script>


<template>
  <PublicBookingOfferPage v-if="isPublicOfferPage" />
  <StaffApplicationShell v-else :workspace="staffShellWorkspace">
    <EmailDeliveryView v-if="activeTab === 'delivery'" :workspace="emailDeliveryWorkspace" />
    <BookingInquiryView
        v-else-if="activeTab === 'inquiries'"
        :workspace="{ ...bookingInquiryState, principal, busy, canReadBookingDraft }"
        @open-booking-draft="openBookingDraft"
      >
        <template #booking-draft-editor>
          <CommercialBookingWorkspaceView section="draft-editor" :workspace="commercialBookingWorkspace" />
        </template>
        <template #booking-offer-workspace>
          <CommercialBookingWorkspaceView section="offer-workspace" :workspace="commercialBookingWorkspace" />
        </template>
      </BookingInquiryView>


      <BookingPriceListsView v-else-if="activeTab === 'prices'" :workspace="{ ...bookingPriceListState, busy }" />

      <BookingApprovalPoliciesView v-else-if="activeTab === 'approvals'" :workspace="{ ...bookingApprovalPolicyState, busy }" />

      <BookingTaxProfilesView v-else-if="activeTab === 'taxes'" :workspace="{ ...bookingTaxProfileState, busy }" />

      <BookingCancellationPoliciesView v-else-if="activeTab === 'cancellations'" :workspace="{ ...bookingCancellationPolicyState, busy }" />

      <CampaignWorkspaceView v-else :workspace="campaignWorkspace" />
    
  </StaffApplicationShell>
</template>
