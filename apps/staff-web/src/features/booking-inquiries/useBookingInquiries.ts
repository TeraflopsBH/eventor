import { computed, reactive, ref, type Ref } from "vue";
import type { BookingInquiryAssignee, BookingInquiryCapabilities, BookingInquiryDetail, BookingInquiryListItem, PageMeta, Principal } from "../../api";
import { api as defaultApi } from "../../api";
import { formatBookingAnswerItems, resolveInquiryAssigneeName } from "./presentation";

type InquiryStatusCommand = "received" | "under_review" | "declined" | "spam";
type ApiClient = typeof defaultApi;
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
interface BookingInquiriesOptions {
  principal: Ref<Principal | null>; busy: Ref<boolean>; activeTab: Ref<StaffTab>;
  pageError: Ref<string>; pageNotice: Ref<string>; api: ApiClient;
  clearMessages: () => void; showError: (error: unknown) => void;
  clearBookingDraftState: () => void;
  translate: (key: string, params?: Record<string, string | number>) => string;
}

export function useBookingInquiries(options: BookingInquiriesOptions) {
  const t = options.translate;
  const inquiryRows = ref<BookingInquiryListItem[]>([]);
  const inquiryMeta = ref<PageMeta | null>(null);
  const inquiryOffset = ref(0);
  const inquiryFilters = reactive({ status: "", assignedToMembershipId: "" });
  const inquiryDetail = ref<BookingInquiryDetail | null>(null);
  const inquiryAssignees = ref<BookingInquiryAssignee[]>([]);
  const inquiryCapabilities = ref<BookingInquiryCapabilities>({
    canAssign: false, canManage: false, canAnnotate: false, canConvert: false, canReadDraft: false, canManageDraft: false,
  });
  const selectedInquiryId = ref("");
  const inquiryAssignmentChoice = ref("unassigned");
  const inquiryStatusChoice = ref<InquiryStatusCommand | "">("");
  const inquiryStatusReason = ref("");
  const inquiryAnnotationText = ref("");

  const canEditInquiryAssignment = computed(() => inquiryCapabilities.value.canAssign &&
    (inquiryDetail.value?.status === "received" || inquiryDetail.value?.status === "under_review"));
  const canConvertInquiry = computed(() => inquiryCapabilities.value.canConvert &&
    (inquiryDetail.value?.status === "received" || inquiryDetail.value?.status === "under_review"));
  const inquiryStatusTargets = computed<InquiryStatusCommand[]>(() => {
    if (inquiryDetail.value?.status === "received") return ["under_review", "declined", "spam"];
    if (inquiryDetail.value?.status === "under_review") return ["received", "declined", "spam"];
    return [];
  });
  const inquiryAnswerItems = computed(() => {
    const detail = inquiryDetail.value;
    return detail
      ? formatBookingAnswerItems(detail.fieldSchema, detail.submittedValues?.answers)
      : [];
  });

  async function refreshInquiryListData(offset = inquiryOffset.value): Promise<void> {
    if (!options.principal.value) return;
    const organizationId = options.principal.value.organizationId;
    const [list, capabilities] = await Promise.all([
      options.api.getBookingInquiries(organizationId, {
        status: inquiryFilters.status || undefined,
        assignedToMembershipId: inquiryFilters.assignedToMembershipId || undefined,
        limit: 25, offset,
      }),
      options.api.getBookingInquiryCapabilities(organizationId),
    ]);
    inquiryRows.value = list.data; inquiryMeta.value = list.meta; inquiryOffset.value = offset;
    inquiryCapabilities.value = capabilities.data;
    if (!capabilities.data.canReadDraft) options.clearBookingDraftState();
    inquiryAssignees.value = capabilities.data.canAssign
      ? (await options.api.getBookingInquiryAssignees(organizationId)).data : [];
  }
  async function refreshInquiryDetailData(): Promise<void> {
    if (!selectedInquiryId.value) return;
    const result = await options.api.getBookingInquiry(selectedInquiryId.value);
    inquiryDetail.value = result.data;
    if (!result.data.bookingDraft) options.clearBookingDraftState();
    inquiryAssignmentChoice.value = result.data.assignedToMembershipId ?? "unassigned";
    inquiryStatusChoice.value = "";
  }
  async function loadInquiryList(offset = 0): Promise<void> {
    options.clearMessages(); options.busy.value = true;
    try { await refreshInquiryListData(offset); } catch (error) { options.showError(error); }
    finally { options.busy.value = false; }
  }
  async function openInquiryWorkspace(): Promise<void> { options.activeTab.value = "inquiries"; await loadInquiryList(0); }
  async function openInquiry(item: BookingInquiryListItem): Promise<void> {
    options.clearMessages(); selectedInquiryId.value = item.inquiryId;
    inquiryStatusReason.value = ""; inquiryAnnotationText.value = "";
    options.clearBookingDraftState(); options.busy.value = true;
    try { await refreshInquiryDetailData(); } catch (error) { options.showError(error); }
    finally { options.busy.value = false; }
  }
  async function refreshInquiryDetail(): Promise<void> {
    if (!selectedInquiryId.value) return;
    options.busy.value = true;
    try { await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]); }
    catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  async function saveInquiryAssignment(): Promise<void> {
    const detail = inquiryDetail.value;
    if (!detail || !inquiryCapabilities.value.canAssign) return;
    const membershipId = inquiryAssignmentChoice.value === "unassigned" ? null : inquiryAssignmentChoice.value;
    if (membershipId === detail.assignedToMembershipId) { options.pageNotice.value = t("bookingInquiry.assignmentUnchanged"); return; }
    const name = resolveInquiryAssigneeName(membershipId, options.principal.value?.membershipId, inquiryAssignees.value);
    if (!window.confirm(t("bookingInquiry.confirmAssign", { reference: detail.publicReference, name }))) return;
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.assignBookingInquiry(detail.inquiryId, membershipId);
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = t("bookingInquiry.assignmentSaved");
    } catch (error) { options.showError(error); inquiryAssignmentChoice.value = detail.assignedToMembershipId ?? "unassigned"; }
    finally { options.busy.value = false; }
  }
  async function saveInquiryStatus(): Promise<void> {
    const detail = inquiryDetail.value, status = inquiryStatusChoice.value, reason = inquiryStatusReason.value.trim();
    if (!detail || !inquiryCapabilities.value.canManage || !status) return;
    if (reason.length < 3) { options.pageError.value = t("bookingInquiry.auditReasonMin"); return; }
    const statusLabel = t(`bookingInquiry.${({ received: "received", under_review: "underReview", declined: "declined", spam: "spam" } as Record<string, string>)[status] ?? "received"}`);
    const confirmation = status === "declined" || status === "spam" ? t("bookingInquiry.confirmTerminalStatus", { reference: detail.publicReference, status: statusLabel }) : t("bookingInquiry.confirmStatusChange", { reference: detail.publicReference, status: statusLabel });
    if (!window.confirm(confirmation)) return;
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.changeBookingInquiryStatus(detail.inquiryId, { status, reason });
      inquiryStatusReason.value = "";
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = t("bookingInquiry.statusChanged", { status: statusLabel });
    } catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  async function saveInquiryConversion(): Promise<void> {
    const detail = inquiryDetail.value;
    if (!detail || !canConvertInquiry.value) return;
    if (!window.confirm(t("bookingInquiry.confirmConversion", { reference: detail.publicReference }))) return;
    options.clearMessages(); options.busy.value = true;
    try {
      const result = await options.api.convertBookingInquiryToDraft(detail.inquiryId);
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = result.data.changed ? t("bookingInquiry.conversionCreated", { revision: result.data.revisionNumber, id: result.data.draftId }) : t("bookingInquiry.conversionAlreadyDone", { id: result.data.draftId });
    } catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  async function saveInquiryAnnotation(): Promise<void> {
    const detail = inquiryDetail.value, annotation = inquiryAnnotationText.value.trim();
    if (!detail || !inquiryCapabilities.value.canAnnotate) return;
    if (annotation.length < 1 || annotation.length > 4000) { options.pageError.value = t("bookingInquiry.annotationLength"); return; }
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.addBookingInquiryAnnotation(detail.inquiryId, annotation);
      inquiryAnnotationText.value = ""; await refreshInquiryDetailData();
      options.pageNotice.value = t("bookingInquiry.annotationSaved");
    } catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  function reset(): void {
    inquiryRows.value = []; inquiryMeta.value = null; inquiryOffset.value = 0;
    inquiryFilters.status = ""; inquiryFilters.assignedToMembershipId = "";
    inquiryDetail.value = null; inquiryAssignees.value = []; selectedInquiryId.value = "";
    inquiryAssignmentChoice.value = "unassigned"; inquiryStatusChoice.value = "";
    inquiryStatusReason.value = ""; inquiryAnnotationText.value = "";
    inquiryCapabilities.value = { canAssign: false, canManage: false, canAnnotate: false, canConvert: false, canReadDraft: false, canManageDraft: false };
    options.clearBookingDraftState();
  }
  return {
    inquiryRows, inquiryMeta, inquiryOffset, inquiryFilters, inquiryDetail, inquiryAssignees, inquiryCapabilities,
    selectedInquiryId, inquiryAssignmentChoice, inquiryStatusChoice, inquiryStatusReason, inquiryAnnotationText,
    inquiryStatusTargets, inquiryAnswerItems, canEditInquiryAssignment, canConvertInquiry,
    refreshInquiryListData, refreshInquiryDetailData, loadInquiryList, openInquiryWorkspace, openInquiry,
    refreshInquiryDetail, saveInquiryAssignment, saveInquiryStatus, saveInquiryConversion, saveInquiryAnnotation, reset,
  };
}
