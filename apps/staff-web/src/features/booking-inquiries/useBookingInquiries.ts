import { computed, reactive, ref, type Ref } from "vue";
import type { BookingInquiryAssignee, BookingInquiryCapabilities, BookingInquiryDetail, BookingInquiryListItem, PageMeta, Principal } from "../../api";
import { api as defaultApi } from "../../api";
import { formatInquiryAnswer, resolveInquiryAssigneeName } from "./presentation";

type InquiryStatusCommand = "received" | "under_review" | "declined" | "spam";
type ApiClient = typeof defaultApi;
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
interface BookingInquiriesOptions {
  principal: Ref<Principal | null>; busy: Ref<boolean>; activeTab: Ref<StaffTab>;
  pageError: Ref<string>; pageNotice: Ref<string>; api: ApiClient;
  clearMessages: () => void; showError: (error: unknown) => void;
  clearBookingDraftState: () => void;
}

export function useBookingInquiries(options: BookingInquiriesOptions) {
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
    if (!detail) return [];
    const fields = new Map(detail.fieldSchema.fields.map((field) => [field.code, field]));
    return Object.entries(detail.submittedValues?.answers ?? {}).map(([code, value]) => {
      const field = fields.get(code);
      const displayValue = Array.isArray(value)
        ? value.map((item) => formatInquiryAnswer(field, item)).join(", ")
        : formatInquiryAnswer(field, value);
      return { code, label: field?.label?.trim() || code.replaceAll("_", " "), type: field?.type ?? "unknown", value: displayValue };
    });
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
    if (membershipId === detail.assignedToMembershipId) { options.pageNotice.value = "The assignment has not changed."; return; }
    const name = resolveInquiryAssigneeName(membershipId, options.principal.value?.membershipId, inquiryAssignees.value);
    if (!window.confirm(`Assign ${detail.publicReference} to ${name}?`)) return;
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.assignBookingInquiry(detail.inquiryId, membershipId);
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = "Inquiry assignment saved.";
    } catch (error) { options.showError(error); inquiryAssignmentChoice.value = detail.assignedToMembershipId ?? "unassigned"; }
    finally { options.busy.value = false; }
  }
  async function saveInquiryStatus(): Promise<void> {
    const detail = inquiryDetail.value, status = inquiryStatusChoice.value, reason = inquiryStatusReason.value.trim();
    if (!detail || !inquiryCapabilities.value.canManage || !status) return;
    if (reason.length < 3) { options.pageError.value = "Enter an audit reason of at least 3 characters."; return; }
    if (!window.confirm(status === "declined" || status === "spam"
      ? `Move ${detail.publicReference} to ${status}? This is a terminal status and cannot be reopened.`
      : `Change ${detail.publicReference} to ${status.replaceAll("_", " ")}?`)) return;
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.changeBookingInquiryStatus(detail.inquiryId, { status, reason });
      inquiryStatusReason.value = "";
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = `Inquiry status changed to ${status.replaceAll("_", " ")}.`;
    } catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  async function saveInquiryConversion(): Promise<void> {
    const detail = inquiryDetail.value;
    if (!detail || !canConvertInquiry.value) return;
    if (!window.confirm(`Convert ${detail.publicReference} into a separate booking draft? The original inquiry will be preserved, but its status will become converted. This does not issue an offer, reserve resources or confirm a booking.`)) return;
    options.clearMessages(); options.busy.value = true;
    try {
      const result = await options.api.convertBookingInquiryToDraft(detail.inquiryId);
      await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
      options.pageNotice.value = result.data.changed
        ? `Booking draft created (revision ${result.data.revisionNumber}). Draft ID: ${result.data.draftId}. No offer or reservation has been created.`
        : `This inquiry was already converted. Existing draft ID: ${result.data.draftId}.`;
    } catch (error) { options.showError(error); } finally { options.busy.value = false; }
  }
  async function saveInquiryAnnotation(): Promise<void> {
    const detail = inquiryDetail.value, annotation = inquiryAnnotationText.value.trim();
    if (!detail || !inquiryCapabilities.value.canAnnotate) return;
    if (annotation.length < 1 || annotation.length > 4000) { options.pageError.value = "Enter an internal note between 1 and 4,000 characters."; return; }
    options.clearMessages(); options.busy.value = true;
    try {
      await options.api.addBookingInquiryAnnotation(detail.inquiryId, annotation);
      inquiryAnnotationText.value = ""; await refreshInquiryDetailData();
      options.pageNotice.value = "Internal note added. It is visible only to authorized staff.";
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
