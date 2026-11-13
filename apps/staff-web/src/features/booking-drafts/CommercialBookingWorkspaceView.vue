<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import type { useBookingDraft } from "./useBookingDraft";
import type { useBookingOffers } from "../booking-offers/useBookingOffers";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";

type Workspace = ReturnType<typeof useBookingDraft> & ReturnType<typeof useBookingOffers> & {
  busy: Ref<boolean>;
};

const props = defineProps<{
  section: "draft-editor" | "offer-workspace";
  workspace: Workspace;
}>();
const { formatDate, formatMoney } = useInquiryPresentation();
const { t } = useI18n();
const inquiryStatusLabel = (status: string): string => {
  const keys: Record<string, string> = { received: "received", under_review: "underReview", converted: "converted", declined: "declined", withdrawn: "withdrawn", spam: "spam" };
  return keys[status] ? t(`bookingInquiry.${keys[status]}`) : status.replaceAll("_", " ");
};
const commercialStatusLabel = (value: string): string => {
  const labels: Record<string, () => string> = {
    draft: () => t("commercialBooking.stateDraft"),
    offered: () => t("commercialBooking.stateOffered"),
    confirmed: () => t("commercialBooking.stateConfirmed"),
    cancelled: () => t("commercialBooking.stateCancelled"),
    issued: () => t("commercialBooking.stateIssued"),
    accepted: () => t("commercialBooking.stateAccepted"),
    rejected: () => t("commercialBooking.stateRejected"),
    expired: () => t("commercialBooking.stateExpired"),
    superseded: () => t("commercialBooking.stateSuperseded"),
    queued: () => t("commercialBooking.stateQueued"),
    sending: () => t("commercialBooking.stateSending"),
    sent: () => t("commercialBooking.stateSent"),
    failed: () => t("commercialBooking.stateFailed"),
    uncertain: () => t("commercialBooking.stateUncertain"),
    approved: () => t("commercialBooking.stateApproved"),
    returned_for_changes: () => t("commercialBooking.stateReturnedForChanges"),
    confirmed_sent: () => t("commercialBooking.stateConfirmedSent"),
    confirmed_not_sent: () => t("commercialBooking.stateConfirmedNotSent"),
  };
  return labels[value]?.() ?? value.replaceAll("_", " ");
};

const {
  detail: bookingDraftDetail,
  editorOpen: bookingDraftEditorOpen,
  valuesJson: bookingDraftValuesJson,
  spaceLinesJson: bookingDraftSpaceLinesJson,
  resourceLinesJson: bookingDraftResourceLinesJson,
  requestedStart: bookingDraftRequestedStart,
  requestedEnd: bookingDraftRequestedEnd,
  timezone: bookingDraftTimezone,
  changeReason: bookingDraftChangeReason,
  canManage: canManageBookingDraft,
  saveRevision: saveBookingDraftRevision,
} = props.workspace;

const {
  bookingOffer, bookingOfferApprovalStatus, bookingOfferIdInput, bookingOfferAcceptanceToken,
  bookingOfferConfirmationReason, bookingOfferEmailDeliveries, bookingOfferEmailMeta,
  bookingOfferEmailStatusFilter, bookingOfferEmailOffset, bookingOfferEmailResolution,
  bookingOfferEmailReason, bookingOfferEmailReference, bookingOfferEmailRetryReason,
  bookingOfferSupersedeCurrent, bookingOfferValidUntil, bookingOfferTaxAmount,
  bookingOfferInternalReason, bookingOfferCreateForm, bookingOfferLineItemsJson,
  bookingOfferAdjustmentsJson, bookingOfferApprovalDecisions, bookingOfferApprovalReasons,
  canManageBookingOffer, canConfirmBookingOffer, refreshBookingOfferEmailData,
  loadBookingOffer, saveBookingOfferRevision, issueBookingOffer, emailBookingOffer,
  reconcileBookingOfferEmail, retryBookingOfferEmail, copyBookingOfferCapability,
  canDecideBookingOfferRequirement, decideBookingOfferApproval, confirmBookingFromAcceptedOffer,
} = props.workspace;

const { busy } = props.workspace;
</script>

<template>
  <template v-if="props.section === 'draft-editor'">

            <section v-if="bookingDraftDetail && bookingDraftEditorOpen" class="inquiry-card booking-draft-editor">
              <div class="inquiry-card-heading">
                <div>
                  <h4>{{ t("commercialBooking.bookingDraftTitle", { id: bookingDraftDetail.draftId.slice(0, 8) }) }}</h4>
                  <p class="fine-print">{{ t("commercialBooking.currentRevisionStatus", { revision: bookingDraftDetail.currentRevisionNumber, status: commercialStatusLabel(bookingDraftDetail.status) }) }}</p>
                </div>
                <button class="button button-quiet" type="button" :disabled="busy" @click="bookingDraftEditorOpen = false">{{ t('commercialBooking.close') }}</button>
              </div>

              <div v-if="bookingDraftDetail.revisionHistory.length" class="draft-revision-history">
                <h5>{{ t('commercialBooking.revisionHistory') }}</h5>
                <ol class="history-list">
                  <li v-for="history in bookingDraftDetail.revisionHistory" :key="history.revisionId">
                    <strong>{{ t("commercialBooking.revisionNumber", { number: history.revisionNumber }) }}</strong>
                    <span>{{ history.changeReason ?? t("commercialBooking.noChangeReasonRecorded") }}</span>
                    <small>{{ history.createdByDisplayName }} · {{ formatDate(history.createdAt) }}</small>
                  </li>
                </ol>
              </div>

              <template v-if="canManageBookingDraft">
                <p class="fine-print">
                  {{ t("commercialBooking.draftImmutableInfo") }}
                </p>
                <form class="draft-revision-form" @submit.prevent="saveBookingDraftRevision">
                  <label>{{$t('commercialBooking.valuesSnapshot')}}<textarea v-model="bookingDraftValuesJson" rows="8" spellcheck="false"></textarea>
                  </label>
                  <div class="field-grid">
                    <label>{{$t('commercialBooking.requestedStart')}}<input v-model="bookingDraftRequestedStart" type="text" maxlength="80" placeholder="2027-01-18T09:00:00+01:00" />
                    </label>
                    <label>{{$t('commercialBooking.requestedEnd')}}<input v-model="bookingDraftRequestedEnd" type="text" maxlength="80" placeholder="2027-01-18T13:00:00+01:00" />
                    </label>
                    <label>{{$t('commercialBooking.timezone')}}<input v-model="bookingDraftTimezone" type="text" maxlength="80" required />
                    </label>
                  </div>
                  <label>{{$t('commercialBooking.spaceLines')}}<textarea v-model="bookingDraftSpaceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>{{$t('commercialBooking.resourceLines')}}<textarea v-model="bookingDraftResourceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>{{$t('commercialBooking.changeReason')}}<textarea v-model="bookingDraftChangeReason" rows="2" maxlength="2000" required  :placeholder="t('commercialBooking.changeReasonPlaceholder')"></textarea>
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || bookingDraftChangeReason.trim().length < 3">
                      {{ t("commercialBooking.saveRevision") }} {{ bookingDraftDetail.currentRevisionNumber + 1 }}
                    </button>
                    <span class="fine-print">{{ t("commercialBooking.revisionUnchangedWithNumber", { revision: bookingDraftDetail.currentRevisionNumber }) }}</span>
                  </div>
                </form>
              </template>
              <p v-else class="fine-print">{{ t('commercialBooking.readOnly') }}</p>
            </section>
  </template>
  <template v-else>

            <section v-if="bookingDraftDetail" class="inquiry-card booking-offer-workspace">
              <div class="inquiry-card-heading">
                <div>
                  <h4>{{ t('commercialBooking.offerWorkspace') }}</h4>
                  <p class="fine-print">{{ t('commercialBooking.offerWorkspaceInfo') }}</p>
                </div>
                <span class="pill pill-neutral">{{ t('commercialBooking.explicitActions') }}</span>
              </div>

              <div class="offer-load-row">
                <label>{{$t('commercialBooking.offerUuid')}}<input v-model="bookingOfferIdInput" type="text" maxlength="36"  :placeholder="t('commercialBooking.loadOfferPlaceholder')" />
                </label>
                <button class="button button-secondary" type="button" :disabled="busy || !bookingOfferIdInput.trim()" @click="loadBookingOffer">{{ t('commercialBooking.loadOffer') }}</button>
              </div>

              <div v-if="canManageBookingOffer" class="offer-preparation">
                <h5>{{ bookingOffer ? t('commercialBooking.prepareSuccessor') : t('commercialBooking.prepareFirst') }}</h5>
                <p class="fine-print">{{$t('commercialBooking.offerPreparationInfo')}}</p>
                <form class="draft-revision-form" @submit.prevent="saveBookingOfferRevision">
                  <div class="field-grid">
                    <label>{{$t('commercialBooking.priceListRevision')}}<input v-model="bookingOfferCreateForm.priceListRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>{{$t('commercialBooking.cancellationRevision')}}<input v-model="bookingOfferCreateForm.cancellationPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>{{$t('commercialBooking.approvalRevision')}}<input v-model="bookingOfferCreateForm.approvalPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>{{$t('commercialBooking.currency')}}<input v-model="bookingOfferCreateForm.currency" type="text" required maxlength="3"  :placeholder="t('commercialBooking.currencyExamplePlaceholder')" />
                    </label>
                    <label>{{$t('commercialBooking.taxTreatment')}}<select v-model="bookingOfferCreateForm.taxBasis" required>
                        <option value="">{{ t('commercialBooking.chooseTax') }}</option>
                        <option value="inclusive">{{ t('commercialBooking.taxInclusive') }}</option>
                        <option value="exclusive">{{ t('commercialBooking.taxExclusive') }}</option>
                        <option value="not_applicable">{{ t('commercialBooking.notApplicable') }}</option>
                        <option value="to_be_confirmed">{{ t('commercialBooking.toBeConfirmed') }}</option>
                      </select>
                    </label>
                    <label>{{$t('commercialBooking.validUntil')}}<input v-model="bookingOfferValidUntil" type="datetime-local" required />
                    </label>
                    <label>{{$t('commercialBooking.offerTaxAmount')}}
                      <input v-model="bookingOfferTaxAmount" type="number" min="0" step="0.0001" required />
                    </label>
                  </div>
                  <label>{{$t('commercialBooking.priceLineItems')}}<textarea v-model="bookingOfferLineItemsJson" rows="5" spellcheck="false" placeholder='[{"itemCode":"published-item-code","quantity":1}]'></textarea>
                  </label>
                  <label>{{$t('commercialBooking.manualAdjustments')}}<textarea v-model="bookingOfferAdjustmentsJson" rows="5" spellcheck="false" placeholder='[{"code":"adjustment-code","label":"Reasoned adjustment","kind":"discount","amount":0.01,"allocationMethod":"proportional_to_lines"}]'></textarea>
                    <small>{{$t('commercialBooking.taxAllocationHelp')}}</small>
                  </label>
                  <label>{{$t('commercialBooking.internalTaxReason')}}<textarea v-model="bookingOfferInternalReason" rows="2" maxlength="2000" required  :placeholder="t('commercialBooking.internalTaxReasonPlaceholder')"></textarea>
                  </label>
                  <label v-if="bookingOffer" class="check-row">
                    <input v-model="bookingOfferSupersedeCurrent" type="checkbox" />
                    {{ t("commercialBooking.supersedeCurrent") }}
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || !bookingOfferValidUntil || !bookingOfferTaxAmount.trim()">
                      {{ bookingOffer ? t('commercialBooking.createSuccessor') : t('commercialBooking.prepareOffer') }}
                    </button>
                  </div>
                </form>
              </div>
              <p v-else class="fine-print">{{ t('commercialBooking.cannotPrepare') }}</p>

              <template v-if="bookingOffer">
                <div class="offer-summary-grid">
                  <div class="metric"><span>{{ t('commercialBooking.offerStatus') }}</span><strong>{{ commercialStatusLabel(bookingOffer.status) }}</strong><small>{{ t("commercialBooking.offerLabel", { id: bookingOffer.offerId }) }}</small></div>
                  <div class="metric"><span>{{ t('commercialBooking.offerRevision') }}</span><strong>{{ bookingOffer.currentRevision.revisionNumber }}</strong><small>{{ commercialStatusLabel(bookingOffer.currentRevision.state) }}</small></div>
                  <div class="metric"><span>{{ t('commercialBooking.subtotal') }}</span><strong>{{ formatMoney(bookingOffer.currentRevision.subtotal, bookingOffer.currentRevision.currency) }}</strong></div>
                  <div class="metric"><span>{{ t('commercialBooking.total') }}</span><strong>{{ formatMoney(bookingOffer.currentRevision.totalAmount, bookingOffer.currentRevision.currency) }}</strong><small>{{ t('commercialBooking.tax') }} {{ formatMoney(bookingOffer.currentRevision.taxAmount, bookingOffer.currentRevision.currency) }}</small></div>
                </div>
                <dl class="offer-reference-list">
                  <dt>{{ t('commercialBooking.draftRevision') }}</dt><dd class="mono">{{ bookingOffer.currentRevision.draftRevisionId }}</dd>
                  <dt>{{ t('commercialBooking.priceListRevisionLabel') }}</dt><dd class="mono">{{ bookingOffer.currentRevision.priceListRevisionId }}</dd>
                  <dt>{{ t('commercialBooking.cancellationPolicy') }}</dt><dd class="mono">{{ bookingOffer.currentRevision.cancellationPolicyRevisionId }}</dd>
                  <dt>{{ t('commercialBooking.approvalPolicy') }}</dt><dd class="mono">{{ bookingOffer.currentRevision.approvalPolicyRevisionId }}</dd>
                  <dt>{{ t('commercialBooking.validUntilLabel') }}</dt><dd>{{ formatDate(bookingOffer.currentRevision.validUntil) }}</dd>
                  <dt>{{ t('commercialBooking.issued') }}</dt><dd>{{ formatDate(bookingOffer.currentRevision.issuedAt) }}</dd>
                  <dt>{{ t('commercialBooking.customerAccepted') }}</dt><dd>{{ formatDate(bookingOffer.currentRevision.acceptedAt) }}</dd>
                </dl>
                <details class="offer-terms-details">
                  <summary>{{ t('commercialBooking.inspectSnapshot') }}</summary>
                  <pre>{{ JSON.stringify(bookingOffer.currentRevision.terms, null, 2) }}</pre>
                </details>

                <div class="offer-command-row">
                  <button v-if="bookingOffer.currentRevision.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="issueBookingOffer">{{ t('commercialBooking.issueToCustomer') }}</button>
                  <span v-else class="pill pill-neutral">{{ t("commercialBooking.thisRevisionState", { state: commercialStatusLabel(bookingOffer.currentRevision.state) }) }}</span>
                  <button class="button button-quiet" type="button" :disabled="busy" @click="loadBookingOffer">{{ t('commercialBooking.refreshOffer') }}</button>
                </div>

                <div v-if="bookingOfferAcceptanceToken" class="offer-capability-box">
                  <strong>{{ t('commercialBooking.customerLink') }}</strong>
                  <p class="fine-print">{{$t('commercialBooking.bearerSecretInfo')}}</p>
                  <input :value="bookingOfferAcceptanceToken" type="password" readonly autocomplete="off" />
                  <div class="offer-command-row"><button class="button button-secondary" type="button" @click="copyBookingOfferCapability">{{ t('commercialBooking.copyCustomerLink') }}</button><button v-if="bookingOffer.currentRevision.state === 'issued'" class="button button-secondary" type="button" :disabled="busy" @click="emailBookingOffer">{{ t('commercialBooking.queueOfferEmail') }}</button></div>
                </div>

                <section class="offer-approval-list offer-email-history">
                  <div class="inquiry-card-heading">
                    <div>
                      <h5>{{ t('commercialBooking.emailHistory') }}</h5>
                      <p class="fine-print">{{ t('commercialBooking.smtpCaveat') }}</p>
                    </div>
                    <button class="button button-quiet" type="button" :disabled="busy" @click="refreshBookingOfferEmailData">{{ t('commercialBooking.refreshDelivery') }}</button>
                  </div>
                  <div class="metric-grid compact-metrics">
                    <div class="metric"><span>{{$t('commercialBooking.emailCountsQueued')}}</span><strong>{{ bookingOfferEmailMeta?.counts.queued ?? 0 }}</strong></div>
                    <div class="metric"><span>{{$t('commercialBooking.emailCountsSending')}}</span><strong>{{ bookingOfferEmailMeta?.counts.sending ?? 0 }}</strong></div>
                    <div class="metric"><span>{{$t('commercialBooking.emailCountsSent')}}</span><strong>{{ bookingOfferEmailMeta?.counts.sent ?? 0 }}</strong></div>
                    <div class="metric"><span>{{$t('commercialBooking.emailCountsUncertain')}}</span><strong>{{ bookingOfferEmailMeta?.counts.uncertain ?? 0 }}</strong></div>
                    <div class="metric"><span>{{$t('commercialBooking.emailCountsFailed')}}</span><strong>{{ bookingOfferEmailMeta?.counts.failed ?? 0 }}</strong></div>
                  </div>
                  <div class="delivery-toolbar">
                    <label>{{$t('commercialBooking.filterEmail')}}<select v-model="bookingOfferEmailStatusFilter" @change="bookingOfferEmailOffset = 0; refreshBookingOfferEmailData()">
                        <option value="">{{$t('commercialBooking.allStatuses')}}</option>
                        <option v-for="status in ['queued','sending','sent','failed','uncertain']" :key="status" :value="status">{{ commercialStatusLabel(status) }}</option>
                      </select>
                    </label>
                  </div>
                  <div v-if="bookingOfferEmailDeliveries.length" class="delivery-attempt-list">
                    <article v-for="delivery in bookingOfferEmailDeliveries" :key="delivery.deliveryId" class="delivery-attempt">
                      <div class="delivery-attempt-heading">
                        <div>
                          <strong>{{ t("commercialBooking.offerRevisionPrefix", { id: delivery.offerRevisionId }) }}</strong>
                          <span class="mono">{{ t("commercialBooking.deliveryPrefix", { id: delivery.deliveryId }) }}</span>
                        </div>
                        <span class="pill" :class="delivery.status === 'sent' ? 'pill-success' : delivery.status === 'failed' ? 'pill-danger' : delivery.status === 'uncertain' ? 'pill-warning' : 'pill-neutral'">{{ commercialStatusLabel(delivery.status) }}</span>
                      </div>
                      <div class="delivery-meta">
                        <span>{{ t("commercialBooking.smtpAttemptsCount", { count: delivery.attemptCount }) }}</span>
                        <span>{{ t("commercialBooking.manualRetriesCount", { count: delivery.manualRetryCount }) }}</span>
                        <span>{{ t("commercialBooking.queuedDate", { date: formatDate(delivery.createdAt) }) }}</span>
                        <span>{{ t("commercialBooking.lastUpdateDate", { date: formatDate(delivery.updatedAt) }) }}</span>
                        <span v-if="delivery.status === 'queued'">{{ t("commercialBooking.nextAttemptDate", { date: formatDate(delivery.nextAttemptAt) }) }}</span>
                        <span v-if="delivery.sentAt">{{ t("commercialBooking.smtpAcceptedDate", { date: formatDate(delivery.sentAt) }) }}</span>
                        <span v-if="delivery.lastFailureCode">{{ t("commercialBooking.failureValue", { value: delivery.lastFailureCode }) }}</span>
                        <span v-if="delivery.lastOperatorResolution">{{ t("commercialBooking.operatorResolutionValue", { value: commercialStatusLabel(delivery.lastOperatorResolution) }) }}</span>
                        <span v-if="delivery.lastOperatorReason">{{ t("commercialBooking.auditReasonValue", { value: delivery.lastOperatorReason }) }}</span>
                        <span v-if="delivery.lastOperatorAt">{{ t("commercialBooking.reconciledDate", { date: formatDate(delivery.lastOperatorAt) }) }}</span>
                      </div>
                      <div v-if="delivery.canReconcile" class="operator-controls">
                        <label>{{$t('commercialBooking.verifiedOutcome')}}
                          <select v-model="bookingOfferEmailResolution[delivery.deliveryId]">
                            <option disabled value="">{{$t('commercialBooking.chooseOutcome')}}</option>
                            <option value="confirmed_sent">{{$t('commercialBooking.smtpServerAccepted')}}</option>
                            <option value="confirmed_not_sent">{{$t('commercialBooking.smtpServerRejected')}}</option>
                          </select>
                        </label>
                        <label v-if="bookingOfferEmailResolution[delivery.deliveryId] === 'confirmed_sent'">{{$t('commercialBooking.providerReference')}}
                          <input v-model="bookingOfferEmailReference[delivery.deliveryId]" maxlength="998"  :placeholder="t('commercialBooking.messageReferencePlaceholder')" />
                        </label>
                        <label>{{$t('commercialBooking.auditReasonLabel')}}
                          <textarea v-model="bookingOfferEmailReason[delivery.deliveryId]" rows="2" maxlength="1000"  :placeholder="t('commercialBooking.smtpVerifyPlaceholder')"></textarea>
                        </label>
                        <button class="button button-secondary" type="button" :disabled="busy" @click="reconcileBookingOfferEmail(delivery)">{{ t("commercialBooking.recordReconciliation") }}</button>
                      </div>
                      <div v-if="delivery.canRetry" class="operator-controls">
                        <p class="fine-print">{{$t('commercialBooking.retryOnceInfo')}}</p>
                        <label>{{$t('commercialBooking.retryReasonLabel')}}
                          <textarea v-model="bookingOfferEmailRetryReason[delivery.deliveryId]" rows="2" maxlength="1000"  :placeholder="t('commercialBooking.retrySafePlaceholder')"></textarea>
                        </label>
                        <button class="button button-danger" type="button" :disabled="busy" @click="retryBookingOfferEmail(delivery)">{{$t('commercialBooking.retryOnceAction')}}</button>
                      </div>
                    </article>
                  </div>
                  <p v-else class="muted">{{ t('commercialBooking.noDeliveries') }}</p>
                  <div class="pagination">
                    <button class="button button-quiet" type="button" :disabled="busy || bookingOfferEmailOffset === 0" @click="bookingOfferEmailOffset = Math.max(0, bookingOfferEmailOffset - 25); refreshBookingOfferEmailData()">{{ t("commercialBooking.previousPage") }}</button>
                    <span>{{ bookingOfferEmailMeta?.totalCount ?? 0 }} {{ t("commercialBooking.deliveryCount") }}</span>
                    <button class="button button-quiet" type="button" :disabled="busy || !bookingOfferEmailMeta || bookingOfferEmailOffset + 25 >= bookingOfferEmailMeta.totalCount" @click="bookingOfferEmailOffset += 25; refreshBookingOfferEmailData()">{{ t("commercialBooking.nextPage") }}</button>
                  </div>
                  <p class="fine-print">{{$t('commercialBooking.historyPrivacy')}}</p>
                </section>

                <div v-if="bookingOfferApprovalStatus" class="offer-approval-list">
                  <h5>{{ t('commercialBooking.approvalRequirements') }}</h5>
                  <p v-if="!bookingOfferApprovalStatus.requirements.length" class="muted">{{ t('commercialBooking.noApprovalRules') }}</p>
                  <article v-for="requirement in bookingOfferApprovalStatus.requirements" :key="requirement.ruleCode" class="offer-approval-item">
                    <div class="inquiry-card-heading">
                      <div>
                        <strong>{{ requirement.ruleCode }}</strong>
                        <p class="fine-print">{{ t("commercialBooking.approvalSummary", { approved: requirement.approvedCount, required: requirement.requiredApprovals, separation: requirement.separationOfDuties ? t("commercialBooking.required") : t("commercialBooking.notRequired") }) }}</p>
                      </div>
                      <span class="pill" :class="requirement.blocked ? 'pill-danger' : requirement.approvedCount >= requirement.requiredApprovals ? 'pill-success' : 'pill-warning'">
                        {{ requirement.blocked ? t("commercialBooking.blocked") : requirement.approvedCount >= requirement.requiredApprovals ? t("commercialBooking.satisfied") : t("commercialBooking.pending") }}
                      </span>
                    </div>
                    <ol v-if="requirement.decisions.length" class="history-list">
                      <li v-for="(decision, index) in requirement.decisions" :key="decision.membershipId + '-' + index">
                        <strong>{{ commercialStatusLabel(decision.decision) }}</strong>
                        <span>{{ decision.reason }}</span>
                        <small>{{ decision.membershipId }} · {{ formatDate(decision.decidedAt) }}</small>
                      </li>
                    </ol>
                    <div v-if="canDecideBookingOfferRequirement(requirement)" class="operator-controls offer-approval-controls">
                      <label>{{$t('commercialBooking.decision')}}<select v-model="bookingOfferApprovalDecisions[requirement.ruleCode]">
                          <option value="approved">{{ t('commercialBooking.approve') }}</option>
                          <option value="rejected">{{ t('commercialBooking.reject') }}</option>
                          <option value="returned_for_changes">{{ t('commercialBooking.returnChanges') }}</option>
                        </select>
                      </label>
                      <label>{{$t('commercialBooking.decisionReasonLabel')}}
                        <textarea v-model="bookingOfferApprovalReasons[requirement.ruleCode]" rows="2" maxlength="2000"  :placeholder="t('commercialBooking.decisionReasonPlaceholder')"></textarea>
                      </label>
                      <button class="button button-secondary" type="button" :disabled="busy || (bookingOfferApprovalReasons[requirement.ruleCode] ?? '').trim().length < 3" @click="decideBookingOfferApproval(requirement)">{{ t('commercialBooking.recordDecision') }}</button>
                    </div>
                  </article>
                </div>

                <div v-if="canConfirmBookingOffer" class="offer-confirm-box">
                  <h5>{{ t('commercialBooking.confirmAccepted') }}</h5>
                  <p class="fine-print">{{$t('commercialBooking.confirmationInfo')}}</p>
                  <label>{{ t("commercialBooking.bookingConfirmationReason") }}
                    <textarea v-model="bookingOfferConfirmationReason" rows="2" maxlength="2000"  :placeholder="t('commercialBooking.bookingConfirmationReasonPlaceholder')"></textarea>
                  </label>
                  <button class="button button-primary" type="button" :disabled="busy || bookingOfferConfirmationReason.trim().length < 3" @click="confirmBookingFromAcceptedOffer">{{ t('commercialBooking.confirmBooking') }}</button>
                </div>
                <p v-else-if="bookingOffer.currentRevision.state === 'accepted'" class="fine-print text-warning">{{ t('commercialBooking.confirmationUnavailable') }}</p>

                <div v-if="bookingOffer.revisionHistory.length" class="draft-revision-history">
                  <h5>{{$t('commercialBooking.offerHistory')}}</h5>
                  <ol class="history-list">
                    <li v-for="history in bookingOffer.revisionHistory" :key="history.offerRevisionId">
                      <strong>Offer revision {{ history.revisionNumber }} · {{ commercialStatusLabel(history.state) }}</strong>
                      <span>{{ t("commercialBooking.draftRevision") }} {{ history.draftRevisionId }}</span>
                      <small>{{ formatDate(history.createdAt) }} · {{ t("commercialBooking.issuedDate", { date: formatDate(history.issuedAt) }) }}</small>
                    </li>
                  </ol>
                </div>
              </template>
            </section>
  </template>
</template>
