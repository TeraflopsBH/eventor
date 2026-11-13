import { computed, reactive, ref, type Ref } from "vue";
import type { CampaignListItem, CampaignProgress, CampaignReview, DeliveryAttempt, PageMeta } from "../../api";

interface CampaignsDependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
}

export function useCampaigns({ api, busy, pageError, pageNotice, clearMessages, showError }: CampaignsDependencies) {
  const campaignId = ref("");
  const campaign = ref<CampaignReview | null>(null);
  const campaignProgress = ref<CampaignProgress | null>(null);
  const deliveryAttempts = ref<DeliveryAttempt[]>([]);
  const deliveryMeta = ref<PageMeta | null>(null);
  const deliveryStatusFilter = ref("");
  const deliveryOffset = ref(0);
  const campaigns = ref<CampaignListItem[]>([]);
  const campaignListMeta = ref<PageMeta | null>(null);
  const campaignListOffset = ref(0);
  const operatorResolution = reactive<Record<string, string>>({});
  const operatorReason = reactive<Record<string, string>>({});

  const canQueue = computed(() => campaign.value?.status === "confirmed");
  const canConfirm = computed(() => campaign.value?.status === "previewed");
  const canCancel = computed(() => campaign.value?.status === "queued");

  async function loadCampaign(): Promise<void> {
    clearMessages();
    const id = campaignId.value.trim();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
      pageError.value = "Enter a valid campaign UUID.";
      return;
    }
    busy.value = true;
    try {
      const result = await api.getCampaignReview(id);
      campaign.value = result.data;
      deliveryOffset.value = 0;
      deliveryStatusFilter.value = "";
      await refreshCampaignDeliveryData();
      pageNotice.value = "Campaign review and delivery report loaded. Recipient contact details are intentionally not exposed here.";
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function loadCampaignList(offset = 0): Promise<void> {
    clearMessages();
    busy.value = true;
    try {
      const result = await api.getCampaigns({ limit: 25, offset });
      campaigns.value = result.data;
      campaignListMeta.value = result.meta;
      campaignListOffset.value = offset;
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function openListedCampaign(item: CampaignListItem): Promise<void> {
    campaignId.value = item.campaignId;
    await loadCampaign();
  }

  async function refreshCampaignDeliveryData(): Promise<void> {
    if (!campaign.value) return;
    const [progress, deliveries] = await Promise.all([
      api.getCampaignProgress(campaign.value.campaignId),
      api.getCampaignDeliveries(campaign.value.campaignId, {
        status: deliveryStatusFilter.value || undefined,
        limit: 25,
        offset: deliveryOffset.value,
      }),
    ]);
    campaignProgress.value = progress.data;
    deliveryAttempts.value = deliveries.data;
    deliveryMeta.value = deliveries.meta;
  }

  async function reconcileDeliveryAttempt(attempt: DeliveryAttempt): Promise<void> {
    const resolution = operatorResolution[attempt.attemptId] ?? "";
    const reason = (operatorReason[attempt.attemptId] ?? "").trim();
    if (!resolution) {
      pageError.value = "Choose the verified delivery outcome before reconciling this attempt.";
      return;
    }
    if (reason.length < 3) {
      pageError.value = "Enter an audit reason of at least 3 characters.";
      return;
    }
    const labels: Record<string, string> = {
      confirmed_sent: "confirmed SMTP/provider acceptance",
      confirmed_not_sent: "confirmed not accepted",
      confirmed_delivered: "confirmed delivered",
      confirmed_bounced: "confirmed bounced",
    };
    if (!window.confirm(`Record that this attempt was ${labels[resolution]}? This records an audited decision and does not send a message.`)) return;
    clearMessages();
    busy.value = true;
    try {
      await api.reconcileDeliveryAttempt(attempt.attemptId, { resolution, reason });
      await refreshCampaignDeliveryData();
      pageNotice.value = "The delivery attempt was reconciled. No message was sent.";
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function retryDeliveryAttempt(attempt: DeliveryAttempt): Promise<void> {
    const reason = (operatorReason[attempt.attemptId] ?? "").trim();
    if (reason.length < 3) {
      pageError.value = "Enter an audit reason of at least 3 characters before retrying.";
      return;
    }
    if (!window.confirm("Authorize a new delivery attempt? This may send another message. Only use it after confirming the previous attempt was not accepted.")) return;
    clearMessages();
    busy.value = true;
    try {
      await api.retryDeliveryAttempt(attempt.attemptId, reason);
      await refreshCampaignDeliveryData();
      pageNotice.value = "A distinct retry attempt was queued under your authorization.";
    } catch (error) {
      showError(error);
    } finally {
      busy.value = false;
    }
  }

  async function runCampaignAction(action: "confirm" | "queue" | "cancel"): Promise<void> {
    if (!campaign.value) return;
    const labels = {
      confirm: "Confirm this reviewed campaign? This records authorization but does not send messages.",
      queue: "Queue this confirmed campaign for delivery? The worker may begin sending immediately.",
      cancel: "Cancel this queued campaign? This is only possible before the first delivery attempt starts.",
    };
    if (!window.confirm(labels[action])) return;

    clearMessages();
    busy.value = true;
    try {
      if (action === "confirm") await api.confirmCampaign(campaign.value.campaignId);
      if (action === "queue") await api.queueCampaign(campaign.value.campaignId);
      if (action === "cancel") await api.cancelCampaign(campaign.value.campaignId);
      const result = await api.getCampaignReview(campaign.value.campaignId);
      campaign.value = result.data;
      await refreshCampaignDeliveryData();
      pageNotice.value = action === "confirm"
        ? "Campaign confirmed. No messages have been queued or sent."
        : action === "queue"
          ? "Campaign queued. Delivery is handled asynchronously by the worker."
          : "Campaign cancelled before sending began.";
    } catch (error) {
      showError(error);
      try {
        const result = await api.getCampaignReview(campaign.value.campaignId);
        campaign.value = result.data;
      } catch {
        // Keep the original command error visible.
      }
    } finally {
      busy.value = false;
    }
  }

  function reset(): void {
    campaign.value = null;
  }

  return {
    campaignId, campaign, campaignProgress, deliveryAttempts, deliveryMeta,
    deliveryStatusFilter, deliveryOffset, campaigns, campaignListMeta, campaignListOffset,
    operatorResolution, operatorReason, canQueue, canConfirm, canCancel,
    loadCampaign, loadCampaignList, openListedCampaign, refreshCampaignDeliveryData,
    reconcileDeliveryAttempt, retryDeliveryAttempt, runCampaignAction, reset,
  };
}
