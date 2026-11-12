import { computed, ref, type ComputedRef, type Ref } from "vue";
import { ApiError, api, type BookingDraftDetail } from "../../api";
import { formatBookingAnswerItems } from "../booking-inquiries/presentation";

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
  const spaceLinesJson = ref("[]");
  const resourceLinesJson = ref("[]");
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
    spaceLinesJson.value = JSON.stringify(
      (revision?.spaceLines ?? []).map((line) => ({
        venueSpaceId: line.venueSpaceId,
        startsAt: line.startsAt,
        endsAt: line.endsAt,
        blockKind: line.blockKind,
        ...(line.requestedCapacity === null ? {} : { requestedCapacity: line.requestedCapacity }),
      })),
      null,
      2,
    );
    resourceLinesJson.value = JSON.stringify(
      (revision?.resourceLines ?? []).map((line) => ({
        resourceTypeId: line.resourceTypeId,
        requestedQuantity: line.requestedQuantity,
        values: line.values,
      })),
      null,
      2,
    );
    requestedStart.value = revision?.requestedStart ?? "";
    requestedEnd.value = revision?.requestedEnd ?? "";
    timezone.value = revision?.timezone ?? "Europe/Sarajevo";
    changeReason.value = "";
  }

  function reset(): void {
    detail.value = null;
    editorOpen.value = false;
    valuesJson.value = "{}";
    spaceLinesJson.value = "[]";
    resourceLinesJson.value = "[]";
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
      const result = await bookingApi.getBookingDraft(draftId);
      detail.value = result.data;
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
    const result = await bookingApi.getBookingDraft(draftId);
    detail.value = result.data;
    populateEditor(result.data);
  }

  async function saveRevision(): Promise<void> {
    const draft = detail.value;
    const revision = draft?.currentRevision;
    if (!draft || !revision || !canManage.value) return;

    let values: Record<string, unknown>;
    let spaceLines: Array<Record<string, unknown>>;
    let resourceLines: Array<Record<string, unknown>>;
    try {
      const parsedValues: unknown = JSON.parse(valuesJson.value);
      const parsedSpaces: unknown = JSON.parse(spaceLinesJson.value);
      const parsedResources: unknown = JSON.parse(resourceLinesJson.value);
      if (!parsedValues || typeof parsedValues !== "object" || Array.isArray(parsedValues)) {
        throw new Error(t("commercialBooking.jsonObjectRequired"));
      }
      if (!Array.isArray(parsedSpaces) || !Array.isArray(parsedResources)) {
        throw new Error(t("commercialBooking.jsonArraysRequired"));
      }
      values = parsedValues as Record<string, unknown>;
      spaceLines = parsedSpaces as Array<Record<string, unknown>>;
      resourceLines = parsedResources as Array<Record<string, unknown>>;
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
        spaceLines: spaceLines as Array<{
          venueSpaceId: string;
          startsAt: string;
          endsAt: string;
          blockKind: "setup" | "rehearsal" | "event_use" | "teardown" | "buffer";
          requestedCapacity?: number;
        }>,
        resourceLines: resourceLines as Array<{
          resourceTypeId: string;
          requestedQuantity: number;
          values?: Record<string, unknown>;
        }>,
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
    spaceLinesJson,
    resourceLinesJson,
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
