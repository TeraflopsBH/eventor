<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import type { useBookingCancellationRequests } from "./useBookingCancellationRequests";

type Workspace = ReturnType<typeof useBookingCancellationRequests> & { busy: Ref<boolean> };
const props = defineProps<{ workspace: Workspace }>();
const { t } = useI18n();
const dateLabel = (value: string | null): string => value
  ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))
  : "—";
const statusLabel = (value: string): string => {
  const key = `cancellationRequests.status.${value}`;
  const translated = t(key as never) as string;
  return translated === key ? value.replaceAll("_", " ") : translated;
};
const decisionLabel = (value: string): string => {
  const key = `cancellationRequests.decision.${value}`;
  const translated = t(key as never) as string;
  return translated === key ? value.replaceAll("_", " ") : translated;
};
const {
  busy, queueItems, queueTotal, queueStatusFilter, selectedRequest, selectedRequestId,
  selectedQueueItem, decisionReason, preview, executionResult, canDecide, canExecute,
  refresh, selectRequest, applyDecision, previewCancellation, executeCancellation,
} = props.workspace;
</script>

<template>
  <section class="panel inquiry-panel cancellation-request-workspace">
    <div class="section-heading">
      <div>
        <p class="eyebrow">{{ t("cancellationRequests.eyebrow") }}</p>
        <h2>{{ t("cancellationRequests.title") }}</h2>
        <p class="muted">{{ t("cancellationRequests.description") }}</p>
      </div>
      <div class="form-actions">
        <label class="compact-field">
          <span>{{ t("cancellationRequests.filter") }}</span>
          <select v-model="queueStatusFilter" :disabled="busy" @change="refresh">
            <option value="">{{ t("cancellationRequests.unresolved") }}</option>
            <option value="submitted">{{ statusLabel("submitted") }}</option>
            <option value="under_review">{{ statusLabel("under_review") }}</option>
            <option value="approved">{{ statusLabel("approved") }}</option>
            <option value="rejected">{{ statusLabel("rejected") }}</option>
            <option value="effective">{{ statusLabel("effective") }}</option>
          </select>
        </label>
        <button class="button button-secondary" type="button" :disabled="busy" @click="refresh">{{ t("cancellationRequests.refresh") }}</button>
      </div>
    </div>

    <div class="cancellation-request-grid">
      <section class="inquiry-card cancellation-request-list">
        <div class="inquiry-card-heading">
          <h3>{{ t("cancellationRequests.queue") }}</h3>
          <span class="pill">{{ queueTotal }}</span>
        </div>
        <button
          v-for="item in queueItems"
          :key="item.requestId"
          type="button"
          class="cancellation-request-item"
          :class="{ 'is-selected': selectedRequestId === item.requestId }"
          :disabled="busy"
          @click="selectRequest(item)"
        >
          <span class="cancellation-request-item-heading">
            <strong>{{ item.bookingCode }}</strong>
            <span class="pill" :class="item.status === 'approved' ? 'pill-success' : 'pill-warning'">{{ statusLabel(item.status) }}</span>
          </span>
          <span>{{ item.reasonCode.replaceAll("_", " ") }}</span>
          <small>{{ item.requesterKind.replaceAll("_", " ") }} · {{ dateLabel(item.requestedAt) }}</small>
        </button>
        <p v-if="!queueItems.length" class="muted">{{ t("cancellationRequests.empty") }}</p>
      </section>

      <section class="inquiry-card cancellation-request-detail">
        <template v-if="selectedRequest">
          <div class="inquiry-card-heading">
            <div>
              <h3>{{ selectedQueueItem?.bookingCode ?? selectedRequest.bookingId }}</h3>
              <p class="fine-print">{{ t("cancellationRequests.requestReference", { id: selectedRequest.requestId.slice(0, 8) }) }}</p>
            </div>
            <span class="pill" :class="selectedRequest.status === 'approved' ? 'pill-success' : 'pill-warning'">{{ statusLabel(selectedRequest.status) }}</span>
          </div>

          <dl class="answer-list">
            <dt>{{ t("cancellationRequests.requester") }}</dt><dd>{{ selectedRequest.requesterKind.replaceAll("_", " ") }}</dd>
            <dt>{{ t("cancellationRequests.reasonCode") }}</dt><dd>{{ selectedRequest.reasonCode.replaceAll("_", " ") }}</dd>
            <dt>{{ t("cancellationRequests.requestedAt") }}</dt><dd>{{ dateLabel(selectedRequest.requestedAt) }}</dd>
            <dt>{{ t("cancellationRequests.policyRevision") }}</dt><dd>{{ selectedRequest.policyRevisionId ?? "—" }}</dd>
            <dt>{{ t("cancellationRequests.explanation") }}</dt><dd>{{ selectedRequest.explanation || t("cancellationRequests.noExplanation") }}</dd>
          </dl>

          <div v-if="selectedRequest.decisions.length" class="draft-revision-history">
            <h4>{{ t("cancellationRequests.decisionHistory") }}</h4>
            <ol class="history-list">
              <li v-for="(decision, index) in selectedRequest.decisions" :key="`${decision.decidedAt}-${index}`">
                <strong>{{ decisionLabel(decision.decision) }}</strong>
                <span>{{ decision.reason }}</span>
                <small>{{ dateLabel(decision.decidedAt) }}</small>
              </li>
            </ol>
          </div>

          <div v-if="canDecide" class="cancellation-request-actions">
            <label>{{ t("cancellationRequests.decisionReason") }}<textarea v-model="decisionReason" rows="3" maxlength="1000" :placeholder="t('cancellationRequests.decisionReasonPlaceholder')"></textarea></label>
            <div class="form-actions">
              <button class="button button-primary" type="button" :disabled="busy || decisionReason.trim().length < 3" @click="applyDecision('approved')">{{ t("cancellationRequests.approve") }}</button>
              <button class="button button-secondary" type="button" :disabled="busy || decisionReason.trim().length < 3" @click="applyDecision('returned_for_changes')">{{ t("cancellationRequests.return") }}</button>
              <button class="button button-danger" type="button" :disabled="busy || decisionReason.trim().length < 3" @click="applyDecision('rejected')">{{ t("cancellationRequests.reject") }}</button>
            </div>
          </div>

          <div v-if="selectedRequest.status === 'approved'" class="cancellation-request-actions">
            <div class="form-actions">
              <button class="button button-secondary" type="button" :disabled="busy" @click="previewCancellation">{{ t("cancellationRequests.preview") }}</button>
              <button v-if="canExecute" class="button button-primary" type="button" :disabled="busy" @click="executeCancellation">{{ t("cancellationRequests.execute") }}</button>
            </div>
            <section v-if="preview" class="cancellation-preview">
              <h4>{{ t("cancellationRequests.previewTitle") }}</h4>
              <p>{{ t("cancellationRequests.pinnedPolicy") }}: {{ preview.policyRevisionId }} · {{ preview.customerMode }}</p>
              <p>{{ t("cancellationRequests.reservationsToRelease", {
                resources: preview.reservationRelease.resourceReservationCount,
                spaces: preview.reservationRelease.spaceReservationCount,
                total: preview.reservationRelease.totalReservationCount,
              }) }}</p>
              <p class="notice notice-warning">{{ preview.commercialEvaluation.note }}</p>
              <p class="fine-print">{{ t("cancellationRequests.noMoneyMovement") }}</p>
            </section>
          </div>
        </template>
        <p v-else class="muted">{{ t("cancellationRequests.selectRequest") }}</p>
      </section>
    </div>
    <p v-if="executionResult" class="notice notice-success">
      {{ t("cancellationRequests.executionResult", { released: executionResult.reservationsReleased }) }}
    </p>
  </section>
</template>
