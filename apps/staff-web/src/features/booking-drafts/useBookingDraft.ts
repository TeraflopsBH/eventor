import { computed, ref, type ComputedRef, type Ref } from "vue";
import { ApiError, api, type BookingDraftAllocationOptions, type BookingDraftDetail, type BookingDraftSpaceLine, type PublicBookingFormField } from "../../api";
import { initializePublicBookingAnswers, mergePublicBookingAnswers, validatePublicBookingAnswers } from "../public-booking-forms/publicBookingForm";
import { formatBookingAnswerItems } from "../booking-inquiries/presentation";
import {
  formatBookingDraftResourceLines,
  formatBookingDraftSpaceLines,
  validateBookingDraftAllocations,
  type BookingDraftResourceAllocationInput,
  type BookingDraftSpaceAllocationInput,
} from "./bookingDraftAllocations";

type BookingDraftApi = typeof api;

interface BookingDraftDependencies {
  api: BookingDraftApi;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  canManageDraftPermission: ComputedRef<boolean>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
  refreshInquiryDetail: () => Promise<void>;
  translate: (key: string, params?: Record<string, string | number>) => string;
}

export function useBookingDraft(dependencies: BookingDraftDependencies) {
  const {
    api: bookingApi,
    busy,
    pageError,
    pageNotice,
    canManageDraftPermission,
    clearMessages,
    showError,
    refreshInquiryDetail,
    translate: t,
  } = dependencies;

  const detail = ref<BookingDraftDetail | null>(null);
  const editorOpen = ref(false);
  const valuesJson = ref("{}");
  const draftAnswers = ref<Record<string, unknown>>({});
  const sourceFormFields = computed<PublicBookingFormField[]>(() => detail.value?.currentRevision?.fieldSchema?.fields ?? []);
  const allocationOptions = ref<BookingDraftAllocationOptions>({ spaces: [], resources: [] });
  const spaceLines = ref<BookingDraftSpaceAllocationInput[]>([]);
  const resourceLines = ref<BookingDraftResourceAllocationInput[]>([]);
  const requestedStart = ref("");
  const requestedEnd = ref("");
  const timezone = ref("Europe/Sarajevo");
  const changeReason = ref("");

  const sourceAnswerItems = computed(() => {
    const revision = detail.value?.currentRevision;
    return formatBookingAnswerItems(revision?.fieldSchema, revision?.values?.answers);
  });

  const canManage = computed(() =>
    canManageDraftPermission.value &&
    detail.value?.status === "draft" &&
    Boolean(detail.value.currentRevision),
  );

  function populateEditor(draft: BookingDraftDetail): void {
    const revision = draft.currentRevision;
    valuesJson.value = JSON.stringify(revision?.values ?? {}, null, 2);
    const storedAnswers = revision?.values?.answers;
    draftAnswers.value = {
      ...initializePublicBookingAnswers(revision?.fieldSchema?.fields ?? []),
      ...(storedAnswers && typeof storedAnswers === "object" && !Array.isArray(storedAnswers)
        ? storedAnswers as Record<string, unknown>
        : {}),
    };
    spaceLines.value = formatBookingDraftSpaceLines(revision?.spaceLines ?? []);
    resourceLines.value = formatBookingDraftResourceLines(revision?.resourceLines ?? []);
    requestedStart.value = revision?.requestedStart ?? "";
    requestedEnd.value = revision?.requestedEnd ?? "";
    timezone.value = revision?.timezone ?? "Europe/Sarajevo";
    changeReason.value = "";
  }

  function reset(): void {
    detail.value = null;
    editorOpen.value = false;
    valuesJson.value = "{}";
    draftAnswers.value = {};
    allocationOptions.value = { spaces: [], resources: [] };
    spaceLines.value = [];
    resourceLines.value = [];
    requestedStart.value = "";
    requestedEnd.value = "";
    timezone.value = "Europe/Sarajevo";
    changeReason.value = "";
  }

  async function open(draftId: string | null | undefined, canRead: boolean): Promise<void> {
    if (!draftId || !canRead) return;
    clearMessages();
    busy.value = true;
    try {
      const [result, options] = await Promise.all([
        bookingApi.getBookingDraft(draftId),
        bookingApi.getBookingDraftAllocationOptions(draftId),
      ]);
      detail.value = result.data;
      allocationOptions.value = options.data;
      populateEditor(result.data);
      editorOpen.value = true;
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function refresh(): Promise<void> {
    const draftId = detail.value?.draftId;
    if (!draftId) return;
    const [result, options] = await Promise.all([
      bookingApi.getBookingDraft(draftId),
      bookingApi.getBookingDraftAllocationOptions(draftId),
    ]);
    detail.value = result.data;
    allocationOptions.value = options.data;
    populateEditor(result.data);
  }

  async function saveRevision(): Promise<void> {
    const draft = detail.value;
    const revision = draft?.currentRevision;
    if (!draft || !revision || !canManage.value) return;

    let values: Record<string, unknown>;
    let normalizedSpaceLines: Array<Omit<BookingDraftSpaceLine, "spaceLineId">>;
    let normalizedResourceLines: BookingDraftResourceAllocationInput[];
    try {
      const allocationIssue = validateBookingDraftAllocations(
        spaceLines.value,
        resourceLines.value,
        allocationOptions.value,
      );
      if (allocationIssue) {
        pageError.value = t("commercialBooking.allocationValidation." + allocationIssue.kind, {
          index: "index" in allocationIssue ? allocationIssue.index + 1 : 0,
          capacity: "capacity" in allocationIssue ? allocationIssue.capacity : 0,
        });
        return;
      }
      normalizedSpaceLines = spaceLines.value.map(({ requestedCapacity, ...line }) => ({
        ...line,
        ...(requestedCapacity === "" || requestedCapacity === 0 || requestedCapacity === null || requestedCapacity === undefined
          ? {}
          : { requestedCapacity }),
      }));
      normalizedResourceLines = resourceLines.value.map((line) => ({ ...line, values: { ...(line.values ?? {}) } }));
      if (sourceFormFields.value.length) {
        const issue = validatePublicBookingAnswers(sourceFormFields.value, draftAnswers.value);
        if (issue) {
          const field = sourceFormFields.value.find((item) => item.code === issue.code);
          const label = field?.label?.trim() || issue.code;
          const messageKey = "bookingInquiry.answerValidation." + issue.kind;
          pageError.value = t(messageKey, { field: label, limit: "limit" in issue ? issue.limit : 0 });
          return;
        }
        values = {
          ...revision.values,
          answers: mergePublicBookingAnswers(sourceFormFields.value, draftAnswers.value),
        };
      } else {
        const parsedValues: unknown = JSON.parse(valuesJson.value);
        if (!parsedValues || typeof parsedValues !== "object" || Array.isArray(parsedValues)) {
          throw new Error(t("commercialBooking.jsonObjectRequired"));
        }
        values = parsedValues as Record<string, unknown>;
      }

    } catch (error) {
      pageError.value = error instanceof SyntaxError ? t("commercialBooking.draftJsonInvalid") : error instanceof Error ? error.message : t("commercialBooking.draftJsonInvalid");
      return;
    }

    const reason = changeReason.value.trim();
    if (reason.length < 3) {
      pageError.value = t("commercialBooking.changeReasonMin");
      return;
    }
    const nextRevision = draft.currentRevisionNumber + 1;
    if (!window.confirm(t("commercialBooking.confirmSaveDraftRevision", { next: nextRevision, current: draft.currentRevisionNumber }))) return;

    clearMessages();
    busy.value = true;
    try {
      const result = await bookingApi.createBookingDraftRevision(draft.draftId, {
        expectedRevisionNumber: draft.currentRevisionNumber,
        values,
        requestedStart: requestedStart.value.trim() || null,
        requestedEnd: requestedEnd.value.trim() || null,
        timezone: timezone.value.trim(),
        spaceLines: normalizedSpaceLines,
        resourceLines: normalizedResourceLines,
        changeReason: reason,
      });
      await Promise.all([refresh(), refreshInquiryDetail()]);
      pageNotice.value = t("commercialBooking.draftRevisionCreated", { revision: result.data.revisionNumber });
    } catch (error) {
      showError(error);
      if (error instanceof ApiError && error.status === 412) {
        try {
          await refresh();
        } catch {
          // Retain the original stale-revision message.
        }
      }
    } finally {
      busy.value = false;
    }
  }

  return {
    detail,
    sourceAnswerItems,
    editorOpen,
    valuesJson,
    draftAnswers,
    sourceFormFields,
    allocationOptions,
    spaceLines,
    resourceLines,
    addSpaceLine: () => spaceLines.value.push({
      venueSpaceId: "",
      startsAt: requestedStart.value,
      endsAt: requestedEnd.value,
      blockKind: "event_use",
    }),
    removeSpaceLine: (index: number) => spaceLines.value.splice(index, 1),
    addResourceLine: () => resourceLines.value.push({ resourceTypeId: "", requestedQuantity: 1, values: {} }),
    removeResourceLine: (index: number) => resourceLines.value.splice(index, 1),
    requestedStart,
    requestedEnd,
    timezone,
    changeReason,
    canManage,
    open,
    refresh,
    saveRevision,
    reset,
  };
}
