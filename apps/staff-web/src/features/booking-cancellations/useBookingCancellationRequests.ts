import { computed, ref, type Ref } from "vue";
import type {
  BookingCancellationPreview,
  BookingCancellationRequestDetail,
  BookingCancellationRequestQueueItem,
} from "../../api";

type Decision = "approved" | "rejected" | "returned_for_changes";

interface Dependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
  translate: (key: string, params?: Record<string, string | number>) => string;
}

export function useBookingCancellationRequests({
  api, busy, pageError, pageNotice, clearMessages, showError, translate,
}: Dependencies) {
  const queueItems = ref<BookingCancellationRequestQueueItem[]>([]);
  const queueTotal = ref(0);
  const queueStatusFilter = ref("");
  const selectedRequestId = ref("");
  const selectedRequest = ref<BookingCancellationRequestDetail | null>(null);
  const decisionReason = ref("");
  const preview = ref<BookingCancellationPreview | null>(null);
  const executionResult = ref<Awaited<ReturnType<typeof api.executeBookingCancellation>>["data"] | null>(null);
  const selectedQueueItem = computed(() => queueItems.value.find((item) => item.requestId === selectedRequestId.value) ?? null);
  const canDecide = computed(() => selectedRequest.value !== null
    && ["submitted", "under_review"].includes(selectedRequest.value.status));
  const canExecute = computed(() => selectedRequest.value?.status === "approved" && preview.value !== null);

  async function loadQueue(): Promise<void> {
    const result = await api.getBookingCancellationRequestQueue(queueStatusFilter.value || undefined);
    queueItems.value = result.data.items;
    queueTotal.value = result.data.total;
    if (!queueItems.value.some((item) => item.requestId === selectedRequestId.value)) {
      selectedRequestId.value = queueItems.value[0]?.requestId ?? "";
    }
    if (selectedRequestId.value) {
      const item = queueItems.value.find((entry) => entry.requestId === selectedRequestId.value);
      if (item) await loadRequestDetail(item);
    } else {
      selectedRequest.value = null;
      preview.value = null;
    }
  }

  async function loadRequestDetail(item: BookingCancellationRequestQueueItem): Promise<void> {
    const result = await api.getBookingCancellationRequestsForBooking(item.bookingId);
    selectedRequest.value = result.data.find((request) => request.requestId === item.requestId) ?? null;
    preview.value = null;
    executionResult.value = null;
    decisionReason.value = "";
  }

  async function selectRequest(item: BookingCancellationRequestQueueItem): Promise<void> {
    selectedRequestId.value = item.requestId;
    clearMessages();
    busy.value = true;
    try {
      await loadRequestDetail(item);
      if (!selectedRequest.value) throw new Error(translate("cancellationRequests.detailUnavailable"));
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function refresh(): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      await loadQueue();
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function open(): Promise<void> {
    queueStatusFilter.value = "";
    selectedRequestId.value = "";
    selectedRequest.value = null;
    preview.value = null;
    await refresh();
  }

  async function applyDecision(decision: Decision): Promise<void> {
    const request = selectedRequest.value;
    const item = selectedQueueItem.value;
    const reason = decisionReason.value.trim();
    if (!request || !item || reason.length < 3 || reason.length > 1000) {
      pageError.value = translate("cancellationRequests.reasonRequired");
      return;
    }
    const label = translate(`cancellationRequests.decision.${decision}`);
    if (!window.confirm(translate("cancellationRequests.confirmDecision", { decision: label }))) return;
    clearMessages();
    busy.value = true;
    try {
      await api.decideBookingCancellationRequest(request.bookingId, request.requestId, { decision, reason });
      pageNotice.value = translate("cancellationRequests.decisionSaved");
      await loadQueue();
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function previewCancellation(): Promise<void> {
    const request = selectedRequest.value;
    if (!request) return;
    clearMessages();
    busy.value = true;
    try {
      const result = await api.previewBookingCancellation(request.bookingId, {
        expectedBookingRevision: request.bookingRevision,
        cancellationRequestId: request.requestId,
      });
      preview.value = result.data;
      pageNotice.value = translate("cancellationRequests.previewReady");
    } catch (error) {
      preview.value = null;
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function executeCancellation(): Promise<void> {
    const request = selectedRequest.value;
    const currentPreview = preview.value;
    if (!request || !currentPreview || request.status !== "approved") return;
    if (!window.confirm(translate("cancellationRequests.confirmExecution"))) return;
    clearMessages();
    busy.value = true;
    try {
      const result = await api.executeBookingCancellation(request.bookingId, {
        expectedBookingRevision: currentPreview.bookingRevision,
        cancellationRequestId: request.requestId,
      });
      pageNotice.value = translate("cancellationRequests.executionCompleted");
      preview.value = null;
      await loadQueue();
      executionResult.value = result.data;
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  function reset(): void {
    queueItems.value = [];
    queueTotal.value = 0;
    selectedRequestId.value = "";
    selectedRequest.value = null;
    preview.value = null;
    executionResult.value = null;
    decisionReason.value = "";
  }

  return {
    queueItems, queueTotal, queueStatusFilter, selectedRequestId, selectedRequest,
    selectedQueueItem, decisionReason, preview, executionResult, canDecide, canExecute,
    loadQueue, selectRequest, refresh, open, applyDecision, previewCancellation,
    executeCancellation, reset,
  };
}
