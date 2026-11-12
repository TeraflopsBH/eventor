<script setup lang="ts">
import type { Ref } from "vue";
import type { EmailConfiguration } from "../../api";
import type { useCampaigns } from "./useCampaigns";

type Workspace = ReturnType<typeof useCampaigns> & {
  busy: Ref<boolean>;
  configuration: Ref<EmailConfiguration | null>;
};

const props = defineProps<{ workspace: Workspace }>();

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
          <div><p class="eyebrow">EVENT NOTIFICATIONS</p><h2>Campaign review and authorization</h2></div>
          <span class="pill pill-neutral">Human approval required</span>
        </div>
        <div class="campaign-list-header">
          <div><h3>Authorized campaigns</h3><p class="muted">Only campaigns visible to your event-scoped preview permission are listed.</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadCampaignList(0)">Refresh list</button>
        </div>
        <div v-if="campaigns.length" class="campaign-list">
          <div v-for="item in campaigns" :key="item.campaignId" class="campaign-list-row">
            <div>
              <strong>{{ item.purpose.replaceAll("_", " ") }}</strong>
              <span>{{ item.status }} · {{ item.actualRecipientCount }} recipients · {{ new Date(item.createdAt).toLocaleString() }}</span>
              <small class="mono">{{ item.campaignId }}</small>
            </div>
            <button class="button button-secondary" type="button" :disabled="busy" @click="openListedCampaign(item)">Open</button>
          </div>
          <div class="pagination">
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset === 0" @click="loadCampaignList(Math.max(0, campaignListOffset - 25))">Previous</button>
            <span>{{ campaignListMeta?.totalCount ?? 0 }} campaigns</span>
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset + 25 >= campaignListMeta.totalCount" @click="loadCampaignList(campaignListOffset + 25)">Next</button>
          </div>
        </div>
        <p v-else class="muted">No campaigns loaded. Refresh the list to view campaigns you are permitted to preview.</p>
        <div class="divider"></div>
        <p class="muted">You can also open a campaign directly by UUID.</p>
        <form class="campaign-lookup" @submit.prevent="loadCampaign">
          <label>Campaign UUID<input v-model="campaignId" type="text" required maxlength="36" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /></label>
          <button class="button button-primary" type="submit" :disabled="busy">Load review</button>
        </form>

        <template v-if="campaign">
          <div class="campaign-summary">
            <div><span class="eyebrow">CAMPAIGN STATUS</span><h3>{{ campaign.status.replaceAll("_", " ") }}</h3></div>
            <span class="pill" :class="campaign.status === 'completed' ? 'pill-success' : campaign.status === 'failed' ? 'pill-danger' : 'pill-neutral'">{{ campaign.status }}</span>
          </div>
          <div class="metric-grid">
            <div class="metric"><span>Recipients</span><strong>{{ campaign.recipientCount }}</strong><small>Snapshot count</small></div>
            <div class="metric"><span>Email</span><strong>{{ campaign.recipientsByChannel.email ?? 0 }}</strong><small>Queued through SMTP</small></div>
            <div class="metric"><span>SMS</span><strong>{{ campaign.recipientsByChannel.sms ?? 0 }}</strong><small>Not configured · suppressed</small></div>
            <div class="metric"><span>Excluded</span><strong>{{ campaign.exclusionCount }}</strong><small>Not included in send</small></div>
          </div>
          <div class="review-grid">
            <div class="review-card">
              <h4>Campaign details</h4>
              <dl>
                <dt>Purpose</dt><dd>{{ campaign.purpose }}</dd>
                <dt>Audience</dt><dd>{{ campaign.audienceKind }}</dd>
                <dt>Event ID</dt><dd class="mono">{{ campaign.eventId }}</dd>
                <dt>Decision ID</dt><dd class="mono">{{ campaign.eventDecisionId }}</dd>
                <dt>Actual recipients</dt><dd>{{ campaign.actualRecipientCount }}</dd>
                <dt>Created</dt><dd>{{ new Date(campaign.createdAt).toLocaleString() }}</dd>
                <dt>Confirmed</dt><dd>{{ campaign.confirmedAt ? new Date(campaign.confirmedAt).toLocaleString() : "Not yet confirmed" }}</dd>
              </dl>
            </div>
            <div class="review-card">
              <h4>Message template · {{ campaign.template.locale }}</h4>
              <p class="template-subject">{{ campaign.template.subjectTemplate }}</p>
              <pre class="template-body">{{ campaign.template.bodyTemplate }}</pre>
              <p class="fine-print">Template revision {{ campaign.template.revisionNumber }} · {{ campaign.template.state }}</p>
            </div>
          </div>
          <div class="review-card exclusion-card">
            <h4>Exclusions by reason</h4>
            <div v-if="Object.keys(campaign.exclusionsByReason).length" class="reason-list">
              <div v-for="(count, reason) in campaign.exclusionsByReason" :key="reason"><span>{{ reason.replaceAll("_", " ") }}</span><strong>{{ count }}</strong></div>
            </div>
            <p v-else class="muted">No recipients were excluded from this campaign snapshot.</p>
          </div>
          <div class="campaign-actions">
            <button v-if="canConfirm" class="button button-secondary" :disabled="busy" @click="runCampaignAction('confirm')">Confirm reviewed campaign</button>
            <button v-if="canQueue" class="button button-primary" :disabled="busy || !configuration?.deliveryEnabled" @click="runCampaignAction('queue')">Authorize queue and send</button>
            <button v-if="canCancel" class="button button-danger" :disabled="busy" @click="runCampaignAction('cancel')">Cancel before sending</button>
            <span v-if="campaign.status === 'confirmed' && !configuration?.deliveryEnabled" class="fine-print">Test and enable the current SMTP configuration before queueing.</span>
            <span v-if="campaign.status === 'sending' || campaign.status === 'uncertain'" class="fine-print">Delivery has started or has an uncertain outcome. The campaign cannot be cancelled safely.</span>
          </div>
          <div v-if="campaignProgress" class="review-card delivery-report">
            <div class="section-heading">
              <div><h4>Delivery progress</h4><p class="fine-print">{{ campaignProgress.attemptCount }} total attempts</p></div>
              <button class="button button-secondary" type="button" :disabled="busy" @click="refreshCampaignDeliveryData">Refresh status</button>
            </div>
            <div class="metric-grid compact-metrics">
              <div class="metric"><span>Queued</span><strong>{{ campaignProgress.deliveryCounts.queued }}</strong></div>
              <div class="metric"><span>Sent / delivered</span><strong>{{ campaignProgress.deliveryCounts.sent }}</strong></div>
              <div class="metric"><span>Failed</span><strong>{{ campaignProgress.deliveryCounts.failed }}</strong></div>
              <div class="metric"><span>Uncertain</span><strong>{{ campaignProgress.deliveryCounts.uncertain }}</strong></div>
            </div>
            <div class="delivery-toolbar">
              <label>Filter status
                <select v-model="deliveryStatusFilter" @change="deliveryOffset = 0; refreshCampaignDeliveryData()">
                  <option value="">All statuses</option>
                  <option v-for="status in ['queued','sending','sent','delivered','failed','bounced','uncertain','suppressed']" :key="status" :value="status">{{ status }}</option>
                </select>
              </label>
            </div>
            <div v-if="deliveryAttempts.length" class="delivery-attempt-list">
              <article v-for="attempt in deliveryAttempts" :key="attempt.attemptId" class="delivery-attempt">
                <div class="delivery-attempt-heading">
                  <div><strong>{{ attempt.channel }} · attempt {{ attempt.attemptNumber }}</strong><span class="mono">{{ attempt.recipientReference }}</span></div>
                  <span class="pill" :class="attempt.status === 'sent' || attempt.status === 'delivered' ? 'pill-success' : attempt.status === 'failed' || attempt.status === 'bounced' ? 'pill-danger' : attempt.status === 'uncertain' ? 'pill-warning' : 'pill-neutral'">{{ attempt.status }}</span>
                </div>
                <div class="delivery-meta">
                  <span>Provider: {{ attempt.provider ?? "—" }}</span>
                  <span>Failure: {{ attempt.failureCode ?? "—" }}</span>
                  <span>Retry scheduled: {{ attempt.retryScheduled ? "Yes" : "No" }}</span>
                  <span>Completed: {{ attempt.completedAt ? new Date(attempt.completedAt).toLocaleString() : "—" }}</span>
                </div>
                <div v-if="attempt.status === 'uncertain' || (attempt.status === 'failed' && !attempt.retryScheduled)" class="operator-controls">
                  <label>Verified outcome
                    <select v-model="operatorResolution[attempt.attemptId]">
                      <option disabled value="">Choose an outcome…</option>
                      <option value="confirmed_sent">Confirmed accepted by mail provider</option>
                      <option value="confirmed_not_sent">Confirmed not accepted</option>
                      <option value="confirmed_delivered">Confirmed delivered</option>
                      <option value="confirmed_bounced">Confirmed bounced</option>
                    </select>
                  </label>
                  <label>Audit reason
                    <textarea v-model="operatorReason[attempt.attemptId]" rows="2" maxlength="1000" placeholder="Record how the outcome was verified…"></textarea>
                  </label>
                  <button class="button button-secondary" type="button" :disabled="busy" @click="reconcileDeliveryAttempt(attempt)">Record reconciliation</button>
                </div>
                <div v-if="attempt.status === 'failed' && !attempt.retryScheduled" class="operator-controls">
                  <p class="fine-print">Retry creates a new attempt and may send another message. Only proceed after confirming non-acceptance.</p>
                  <button class="button button-danger" type="button" :disabled="busy" @click="retryDeliveryAttempt(attempt)">Authorize separate retry</button>
                </div>
              </article>
            </div>
            <p v-else class="muted">No attempts match this filter.</p>
            <div class="pagination">
              <button class="button button-quiet" type="button" :disabled="busy || deliveryOffset === 0" @click="deliveryOffset = Math.max(0, deliveryOffset - 25); refreshCampaignDeliveryData()">Previous</button>
              <span>{{ deliveryMeta?.totalCount ?? 0 }} attempts</span>
              <button class="button button-quiet" type="button" :disabled="busy || !deliveryMeta || deliveryOffset + 25 >= deliveryMeta.totalCount" @click="deliveryOffset += 25; refreshCampaignDeliveryData()">Next</button>
            </div>
            <p class="fine-print">Recipient references are pseudonymous. No email addresses, phone numbers, or provider message references are shown. SMTP acceptance is not inbox delivery.</p>
          </div>
          <p class="fine-print">Confirmation does not send messages. Queueing is a separate authorization. Cancellation is available only while the campaign remains queued and before the first delivery attempt begins. SMTP acceptance is not proof of inbox delivery.</p>
        </template>
      </section>
</template>
