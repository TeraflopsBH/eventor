<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import type { EmailConfiguration } from "../../api";
import type { useCampaigns } from "./useCampaigns";

type Workspace = ReturnType<typeof useCampaigns> & {
  busy: Ref<boolean>;
  configuration: Ref<EmailConfiguration | null>;
};

const props = defineProps<{ workspace: Workspace }>();
const { t } = useI18n();
function statusLabel(status: string): string {
  const known = ["previewed", "confirmed", "queued", "sending", "completed", "failed", "cancelled", "uncertain", "sent", "delivered", "bounced", "suppressed", "pending", "draft", "published", "retired"];
  return known.includes(status) ? (t(`campaignWorkspace.status.${status}` as never) as string) : status.replaceAll("_", " ");
}

const {
  campaignId,
  campaign,
  campaignProgress,
  deliveryAttempts,
  deliveryMeta,
  deliveryStatusFilter,
  deliveryOffset,
  campaigns,
  campaignListMeta,
  campaignListOffset,
  operatorResolution,
  operatorReason,
  canQueue,
  canConfirm,
  canCancel,
  loadCampaign,
  loadCampaignList,
  openListedCampaign,
  refreshCampaignDeliveryData,
  reconcileDeliveryAttempt,
  retryDeliveryAttempt,
  runCampaignAction,
  busy,
  configuration,
} = props.workspace;
</script>

<template>
<section class="panel campaign-panel">
        <div class="section-heading">
          <div><p class="eyebrow">{{ $t("campaignWorkspace.eyebrow") }}</p><h2>{{ $t("campaignWorkspace.title") }}</h2></div>
          <span class="pill pill-neutral">{{ $t("campaignWorkspace.humanApproval") }}</span>
        </div>
        <div class="campaign-list-header">
          <div><h3>{{ $t("campaignWorkspace.authorizedCampaigns") }}</h3><p class="muted">{{ $t("campaignWorkspace.previewPermission") }}</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadCampaignList(0)">{{ $t("campaignWorkspace.refreshList") }}</button>
        </div>
        <div v-if="campaigns.length" class="campaign-list">
          <div v-for="item in campaigns" :key="item.campaignId" class="campaign-list-row">
            <div>
              <strong>{{ item.purpose.replaceAll("_", " ") }}</strong>
              <span>{{ statusLabel(item.status) }} · {{ item.actualRecipientCount }} recipients · {{ new Date(item.createdAt).toLocaleString() }}</span>
              <small class="mono">{{ item.campaignId }}</small>
            </div>
            <button class="button button-secondary" type="button" :disabled="busy" @click="openListedCampaign(item)">{{ $t("campaignWorkspace.open") }}</button>
          </div>
          <div class="pagination">
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset === 0" @click="loadCampaignList(Math.max(0, campaignListOffset - 25))">{{ $t("campaignWorkspace.previous") }}</button>
            <span>{{ campaignListMeta?.totalCount ?? 0 }} {{ $t("campaignWorkspace.campaigns") }}</span>
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset + 25 >= campaignListMeta.totalCount" @click="loadCampaignList(campaignListOffset + 25)">{{ $t("campaignWorkspace.next") }}</button>
          </div>
        </div>
        <p v-else class="muted">{{ $t("campaignWorkspace.noCampaigns") }}</p>
        <div class="divider"></div>
        <p class="muted">{{ $t("campaignWorkspace.directLookup") }}</p>
        <form class="campaign-lookup" @submit.prevent="loadCampaign">
          <label>{{ $t("campaignWorkspace.campaignUuid") }}<input v-model="campaignId" type="text" required maxlength="36" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /></label>
          <button class="button button-primary" type="submit" :disabled="busy">{{ $t("campaignWorkspace.loadReview") }}</button>
        </form>

        <template v-if="campaign">
          <div class="campaign-summary">
            <div><span class="eyebrow">{{ $t("campaignWorkspace.campaignStatus") }}</span><h3>{{ statusLabel(campaign.status) }}</h3></div>
            <span class="pill" :class="campaign.status === 'completed' ? 'pill-success' : campaign.status === 'failed' ? 'pill-danger' : 'pill-neutral'">{{ campaign.status }}</span>
          </div>
          <div class="metric-grid">
            <div class="metric"><span>{{ $t("campaignWorkspace.recipients") }}</span><strong>{{ campaign.recipientCount }}</strong><small>{{ $t("campaignWorkspace.snapshotCount") }}</small></div>
            <div class="metric"><span>{{ $t("campaignWorkspace.email") }}</span><strong>{{ campaign.recipientsByChannel.email ?? 0 }}</strong><small>{{ $t("campaignWorkspace.queuedSmtp") }}</small></div>
            <div class="metric"><span>{{ $t("campaignWorkspace.sms") }}</span><strong>{{ campaign.recipientsByChannel.sms ?? 0 }}</strong><small>{{ $t("campaignWorkspace.smsSuppressed") }}</small></div>
            <div class="metric"><span>{{ $t("campaignWorkspace.excluded") }}</span><strong>{{ campaign.exclusionCount }}</strong><small>{{ $t("campaignWorkspace.notIncluded") }}</small></div>
          </div>
          <div class="review-grid">
            <div class="review-card">
              <h4>{{ $t("campaignWorkspace.campaignDetails") }}</h4>
              <dl>
                <dt>{{ $t("campaignWorkspace.purpose") }}</dt><dd>{{ campaign.purpose }}</dd>
                <dt>{{ $t("campaignWorkspace.audience") }}</dt><dd>{{ campaign.audienceKind }}</dd>
                <dt>{{ $t("campaignWorkspace.eventId") }}</dt><dd class="mono">{{ campaign.eventId }}</dd>
                <dt>{{ $t("campaignWorkspace.decisionId") }}</dt><dd class="mono">{{ campaign.eventDecisionId }}</dd>
                <dt>{{ $t("campaignWorkspace.actualRecipients") }}</dt><dd>{{ campaign.actualRecipientCount }}</dd>
                <dt>{{ $t("campaignWorkspace.created") }}</dt><dd>{{ new Date(campaign.createdAt).toLocaleString() }}</dd>
                <dt>{{ $t("campaignWorkspace.confirmed") }}</dt><dd>{{ campaign.confirmedAt ? new Date(campaign.confirmedAt).toLocaleString() : $t("campaignWorkspace.notYetConfirmed") }}</dd>
              </dl>
            </div>
            <div class="review-card">
              <h4>Message template · {{ campaign.template.locale }}</h4>
              <p class="template-subject">{{ campaign.template.subjectTemplate }}</p>
              <pre class="template-body">{{ campaign.template.bodyTemplate }}</pre>
              <p class="fine-print">Template revision {{ campaign.template.revisionNumber }} · {{ statusLabel(campaign.template.state) }}</p>
            </div>
          </div>
          <div class="review-card exclusion-card">
            <h4>{{ $t("campaignWorkspace.exclusionsByReason") }}</h4>
            <div v-if="Object.keys(campaign.exclusionsByReason).length" class="reason-list">
              <div v-for="(count, reason) in campaign.exclusionsByReason" :key="reason"><span>{{ reason.replaceAll("_", " ") }}</span><strong>{{ count }}</strong></div>
            </div>
            <p v-else class="muted">{{ $t("campaignWorkspace.noExclusions") }}</p>
          </div>
          <div class="campaign-actions">
            <button v-if="canConfirm" class="button button-secondary" :disabled="busy" @click="runCampaignAction('confirm')">{{ $t("campaignWorkspace.confirmCampaign") }}</button>
            <button v-if="canQueue" class="button button-primary" :disabled="busy || !configuration?.deliveryEnabled" @click="runCampaignAction('queue')">{{ $t("campaignWorkspace.authorizeQueue") }}</button>
            <button v-if="canCancel" class="button button-danger" :disabled="busy" @click="runCampaignAction('cancel')">{{ $t("campaignWorkspace.cancelBeforeSending") }}</button>
            <span v-if="campaign.status === 'confirmed' && !configuration?.deliveryEnabled" class="fine-print">{{ $t("campaignWorkspace.smtpRequired") }}</span>
            <span v-if="campaign.status === 'sending' || campaign.status === 'uncertain'" class="fine-print">{{ $t("campaignWorkspace.unsafeCancel") }}</span>
          </div>
          <div v-if="campaignProgress" class="review-card delivery-report">
            <div class="section-heading">
              <div><h4>{{ $t("campaignWorkspace.deliveryProgress") }}</h4><p class="fine-print">{{ campaignProgress.attemptCount }} {{ $t("campaignWorkspace.totalAttempts") }}</p></div>
              <button class="button button-secondary" type="button" :disabled="busy" @click="refreshCampaignDeliveryData">{{ $t("campaignWorkspace.refreshStatus") }}</button>
            </div>
            <div class="metric-grid compact-metrics">
              <div class="metric"><span>{{ $t("campaignWorkspace.queued") }}</span><strong>{{ campaignProgress.deliveryCounts.queued }}</strong></div>
              <div class="metric"><span>{{ $t("campaignWorkspace.sentDelivered") }}</span><strong>{{ campaignProgress.deliveryCounts.sent }}</strong></div>
              <div class="metric"><span>{{ $t("campaignWorkspace.failed") }}</span><strong>{{ campaignProgress.deliveryCounts.failed }}</strong></div>
              <div class="metric"><span>{{ $t("campaignWorkspace.uncertain") }}</span><strong>{{ campaignProgress.deliveryCounts.uncertain }}</strong></div>
            </div>
            <div class="delivery-toolbar">
              <label>{{ $t("campaignWorkspace.filterStatus") }}
                <select v-model="deliveryStatusFilter" @change="deliveryOffset = 0; refreshCampaignDeliveryData()">
                  <option value="">{{ $t("campaignWorkspace.allStatuses") }}</option>
                  <option v-for="status in ['queued','sending','sent','delivered','failed','bounced','uncertain','suppressed']" :key="status" :value="status">{{ statusLabel(status) }}</option>
                </select>
              </label>
            </div>
            <div v-if="deliveryAttempts.length" class="delivery-attempt-list">
              <article v-for="attempt in deliveryAttempts" :key="attempt.attemptId" class="delivery-attempt">
                <div class="delivery-attempt-heading">
                  <div><strong>{{ attempt.channel }} · {{ $t("campaignWorkspace.attempt") }} {{ attempt.attemptNumber }}</strong><span class="mono">{{ attempt.recipientReference }}</span></div>
                  <span class="pill" :class="attempt.status === 'sent' || attempt.status === 'delivered' ? 'pill-success' : attempt.status === 'failed' || attempt.status === 'bounced' ? 'pill-danger' : attempt.status === 'uncertain' ? 'pill-warning' : 'pill-neutral'">{{ statusLabel(attempt.status) }}</span>
                </div>
                <div class="delivery-meta">
                  <span>Provider: {{ attempt.provider ?? "—" }}</span>
                  <span>Failure: {{ attempt.failureCode ?? "—" }}</span>
                  <span>Retry scheduled: {{ attempt.retryScheduled ? $t("campaignWorkspace.yes") : $t("campaignWorkspace.no") }}</span>
                  <span>Completed: {{ attempt.completedAt ? new Date(attempt.completedAt).toLocaleString() : "—" }}</span>
                </div>
                <div v-if="attempt.status === 'uncertain' || (attempt.status === 'failed' && !attempt.retryScheduled)" class="operator-controls">
                  <label>{{ $t("campaignWorkspace.verifiedOutcome") }}
                    <select v-model="operatorResolution[attempt.attemptId]">
                      <option disabled value="">{{ $t("campaignWorkspace.chooseOutcome") }}</option>
                      <option value="confirmed_sent">{{ $t("campaignWorkspace.outcomeProviderAccepted") }}</option>
                      <option value="confirmed_not_sent">{{ $t("campaignWorkspace.outcomeNotAccepted") }}</option>
                      <option value="confirmed_delivered">{{ $t("campaignWorkspace.outcomeDelivered") }}</option>
                      <option value="confirmed_bounced">{{ $t("campaignWorkspace.outcomeBounced") }}</option>
                    </select>
                  </label>
                  <label>{{ $t("campaignWorkspace.auditReason") }}
                    <textarea v-model="operatorReason[attempt.attemptId]" rows="2" maxlength="1000" placeholder="Record how the outcome was verified…"></textarea>
                  </label>
                  <button class="button button-secondary" type="button" :disabled="busy" @click="reconcileDeliveryAttempt(attempt)">{{ $t("campaignWorkspace.recordReconciliation") }}</button>
                </div>
                <div v-if="attempt.status === 'failed' && !attempt.retryScheduled" class="operator-controls">
                  <p class="fine-print">{{ $t("campaignWorkspace.retryWarning") }}</p>
                  <button class="button button-danger" type="button" :disabled="busy" @click="retryDeliveryAttempt(attempt)">{{ $t("campaignWorkspace.authorizeRetry") }}</button>
                </div>
              </article>
            </div>
            <p v-else class="muted">{{ $t("campaignWorkspace.noAttempts") }}</p>
            <div class="pagination">
              <button class="button button-quiet" type="button" :disabled="busy || deliveryOffset === 0" @click="deliveryOffset = Math.max(0, deliveryOffset - 25); refreshCampaignDeliveryData()">{{ $t("campaignWorkspace.previous") }}</button>
              <span>{{ deliveryMeta?.totalCount ?? 0 }} {{ $t("campaignWorkspace.attempts") }}</span>
              <button class="button button-quiet" type="button" :disabled="busy || !deliveryMeta || deliveryOffset + 25 >= deliveryMeta.totalCount" @click="deliveryOffset += 25; refreshCampaignDeliveryData()">{{ $t("campaignWorkspace.next") }}</button>
            </div>
            <p class="fine-print">{{ $t("campaignWorkspace.privacyNote") }}</p>
          </div>
          <p class="fine-print">{{ $t("campaignWorkspace.workflowNote") }}</p>
        </template>
      </section>
</template>
