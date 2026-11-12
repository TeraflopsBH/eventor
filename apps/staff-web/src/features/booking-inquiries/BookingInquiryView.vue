<script setup lang="ts">
import type { ComputedRef, Ref } from "vue";
import { useI18n } from "vue-i18n";
import type { Principal } from "../../api";
import { resolveInquiryAssigneeName } from "./presentation";
import type { useBookingInquiries } from "./useBookingInquiries";
import { useInquiryPresentation } from "./useInquiryPresentation";

type BookingInquiryWorkspace = ReturnType<typeof useBookingInquiries> & {
  principal: Ref<Principal | null>;
  busy: Ref<boolean>;
  canReadBookingDraft: ComputedRef<boolean>;
};

const props = defineProps<{ workspace: BookingInquiryWorkspace }>();
const { formatDate } = useInquiryPresentation();
const { t } = useI18n();
const inquiryStatusLabel = (status: string): string => {
  const labels: Record<string, () => string> = {
    received: () => t("bookingInquiry.received"),
    under_review: () => t("bookingInquiry.underReview"),
    converted: () => t("bookingInquiry.converted"),
    declined: () => t("bookingInquiry.declined"),
    withdrawn: () => t("bookingInquiry.withdrawn"),
    spam: () => t("bookingInquiry.spam"),
  };
  return labels[status]?.() ?? status.replaceAll("_", " ");
};
const emit = defineEmits<{ (event: "open-booking-draft"): void }>();

const {
  inquiryRows, inquiryMeta, inquiryOffset, inquiryFilters, inquiryDetail, inquiryAssignees,
  inquiryCapabilities, selectedInquiryId, inquiryAssignmentChoice, inquiryStatusChoice,
  inquiryStatusReason, inquiryAnnotationText, inquiryStatusTargets, inquiryAnswerItems,
  canEditInquiryAssignment, canConvertInquiry, loadInquiryList, openInquiry, refreshInquiryDetail,
  saveInquiryAssignment, saveInquiryStatus, saveInquiryConversion, saveInquiryAnnotation,
  principal, busy, canReadBookingDraft,
} = props.workspace;
</script>

<template>
      <section class="panel inquiry-panel">
        <div class="section-heading">
          <div>
            <p class="eyebrow">{{ t('bookingInquiry.venueBooking') }}</p>
            <h2>{{ t('bookingInquiry.title') }}</h2>
            <p class="muted">{{ t('bookingInquiry.description') }}</p>
          </div>
          <span class="pill pill-neutral">{{ t('bookingInquiry.permissionControlled') }}</span>
        </div>

        <div class="inquiry-toolbar">
          <div class="inquiry-filters">
            <label>{{$t('bookingInquiry.statusLabel')}}
              <select v-model="inquiryFilters.status" @change="loadInquiryList(0)">
                <option value="">{{ t('bookingInquiry.allStatuses') }}</option>
                <option value="received">{{ t('bookingInquiry.received') }}</option>
                <option value="under_review">{{ t('bookingInquiry.underReview') }}</option>
                <option value="converted">{{ t('bookingInquiry.converted') }}</option>
                <option value="declined">{{ t('bookingInquiry.declined') }}</option>
                <option value="withdrawn">{{ t('bookingInquiry.withdrawn') }}</option>
                <option value="spam">{{ t('bookingInquiry.spam') }}</option>
              </select>
            </label>
            <label v-if="inquiryCapabilities.canAssign">{{$t('bookingInquiry.assignedLabel')}}
              <select v-model="inquiryFilters.assignedToMembershipId" @change="loadInquiryList(0)">
                <option value="">{{ t('bookingInquiry.allStaff') }}</option>
                <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                  {{ member.displayName }}
                </option>
              </select>
            </label>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadInquiryList(inquiryOffset)">{{$t('bookingInquiry.refreshInbox')}}</button>
        </div>

        <div class="inquiry-layout">
          <aside class="inquiry-inbox">
            <div class="inquiry-inbox-heading">
              <strong>{{ t('bookingInquiry.inbox') }}</strong>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} {{ t("bookingInquiry.totalLabel") }}</span>
            </div>
            <div v-if="inquiryRows.length" class="inquiry-list">
              <button
                v-for="item in inquiryRows"
                :key="item.inquiryId"
                type="button"
                class="inquiry-list-row"
                :class="{ selected: selectedInquiryId === item.inquiryId }"
                :disabled="busy"
                @click="openInquiry(item)"
              >
                <span class="inquiry-list-top">
                  <strong>{{ item.publicReference }}</strong>
                  <span
                    class="pill"
                    :class="item.status === 'declined' || item.status === 'spam' ? 'pill-danger' : item.status === 'under_review' ? 'pill-warning' : 'pill-neutral'"
                  >{{ inquiryStatusLabel(item.status) }}</span>
                </span>
                <strong class="inquiry-requester">{{ item.requesterName }}</strong>
                <span class="inquiry-list-meta">
                  {{ item.requestedStart ? formatDate(item.requestedStart) : "Date not specified" }}
                </span>
                <span class="inquiry-list-meta">{{ t("bookingInquiry.assignedPrefix") }} {{ resolveInquiryAssigneeName(item.assignedToMembershipId, principal?.membershipId, inquiryAssignees) }}</span>
              </button>
            </div>
            <p v-else class="muted inquiry-empty">{{ t('bookingInquiry.noMatches') }}</p>
            <div class="pagination inquiry-pagination">
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || inquiryOffset === 0"
                @click="loadInquiryList(Math.max(0, inquiryOffset - 25))"
              >{{ t('bookingInquiry.previous') }}</button>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} {{ t("bookingInquiry.inquiryCount") }}</span>
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || !inquiryMeta || inquiryOffset + 25 >= inquiryMeta.totalCount"
                @click="loadInquiryList(inquiryOffset + 25)"
              >{{ t('bookingInquiry.next') }}</button>
            </div>
          </aside>

          <div v-if="inquiryDetail" class="inquiry-detail">
            <div class="inquiry-detail-heading">
              <div>
                <p class="eyebrow">{{ t('bookingInquiry.detail') }}</p>
                <h3>{{ inquiryDetail.publicReference }}</h3>
                <p class="fine-print">{{ t("bookingInquiry.receivedUpdatedLine", { received: formatDate(inquiryDetail.submittedAt), updated: formatDate(inquiryDetail.updatedAt) }) }}</p>
              </div>
              <div class="inquiry-detail-actions">
                <span
                  class="pill"
                  :class="inquiryDetail.status === 'declined' || inquiryDetail.status === 'spam' ? 'pill-danger' : inquiryDetail.status === 'under_review' ? 'pill-warning' : 'pill-neutral'"
                >{{ inquiryStatusLabel(inquiryDetail.status) }}</span>
                <button class="button button-quiet" type="button" :disabled="busy" @click="refreshInquiryDetail">{{ t('bookingInquiry.refreshDetail') }}</button>
              </div>
            </div>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.requester') }}</h4>
                <dl>
                  <dt>{{ t('bookingInquiry.name') }}</dt><dd>{{ inquiryDetail.requesterName }}</dd>
                  <dt>{{ t('bookingInquiry.email') }}</dt><dd>{{ inquiryDetail.requesterEmail ?? "Not supplied" }}</dd>
                  <dt>{{ t('bookingInquiry.phone') }}</dt><dd>{{ inquiryDetail.requesterPhone ?? "Not supplied" }}</dd>
                </dl>
              </section>
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.requestedBooking') }}</h4>
                <dl>
                  <dt>{{ t('bookingInquiry.start') }}</dt><dd>{{ formatDate(inquiryDetail.submittedValues.requested?.startAt ?? inquiryDetail.requestedStart) }}</dd>
                  <dt>{{ t('bookingInquiry.end') }}</dt><dd>{{ formatDate(inquiryDetail.submittedValues.requested?.endAt ?? inquiryDetail.requestedEnd) }}</dd>
                  <dt>{{ t('bookingInquiry.timezone') }}</dt><dd>{{ inquiryDetail.submittedValues.requested?.timezone ?? inquiryDetail.requestedTimezone ?? "—" }}</dd>
                  <dt>{{ t('bookingInquiry.spaces') }}</dt><dd>{{ inquiryDetail.submittedValues.requested?.spaceCodes?.join(", ") || "Not specified" }}</dd>
                </dl>
              </section>
            </div>

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>{{ t('bookingInquiry.submittedAnswers') }}</h4>
                <span class="fine-print">{{ t("bookingInquiry.formRevisionLabel", { revision: inquiryDetail.formRevisionId.slice(0, 8) }) }}</span>
              </div>
              <dl v-if="inquiryAnswerItems.length" class="answer-list">
                <template v-for="answer in inquiryAnswerItems" :key="answer.code">
                  <dt>{{ answer.label }}</dt><dd>{{ answer.value }}</dd>
                </template>
              </dl>
              <p v-else class="muted">{{ t('bookingInquiry.noAnswers') }}</p>
            </section>

            <div class="inquiry-detail-grid">
              <section v-if="canEditInquiryAssignment" class="inquiry-card">
                <h4>{{ t('bookingInquiry.assignment') }}</h4>
                <label>{{$t('bookingInquiry.responsibleStaff')}}<select v-model="inquiryAssignmentChoice">
                    <option value="unassigned">{{ t('bookingInquiry.unassigned') }}</option>
                    <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                      {{ member.displayName }}{{ member.membershipId === principal?.membershipId ? " (you)" : "" }}
                    </option>
                  </select>
                </label>
                <p class="fine-print">{{ t('bookingInquiry.activeMembersOnly') }}</p>
                <button class="button button-secondary" type="button" :disabled="busy" @click="saveInquiryAssignment">{{ t('bookingInquiry.saveAssignment') }}</button>
              </section>

              <section v-if="inquiryCapabilities.canManage && inquiryStatusTargets.length" class="inquiry-card">
                <h4>{{ t('bookingInquiry.reviewStatus') }}</h4>
                <label>{{$t('bookingInquiry.newStatus')}}<select v-model="inquiryStatusChoice">
                    <option disabled value="">{{ t('bookingInquiry.chooseNextStatus') }}</option>
                    <option v-for="status in inquiryStatusTargets" :key="status" :value="status">
                      {{ inquiryStatusLabel(status) }}
                    </option>
                  </select>
                </label>
                <label>{{$t('bookingInquiry.auditReason')}}<textarea v-model="inquiryStatusReason" rows="3" maxlength="1000" placeholder="Explain the review decision or status change…"></textarea>
                </label>
                <p v-if="inquiryStatusChoice === 'declined' || inquiryStatusChoice === 'spam'" class="fine-print text-warning">
                  {{ t("bookingInquiry.terminalStatus") }}
                </p>
                <button class="button button-primary" type="button" :disabled="busy || inquiryStatusReason.trim().length < 3" @click="saveInquiryStatus">{{$t('bookingInquiry.saveStatus')}}</button>
              </section>

              <section v-if="canConvertInquiry" class="inquiry-card">
                <h4>{{ t('bookingInquiry.convertDraft') }}</h4>
                <p class="fine-print">
                  {{ t("bookingInquiry.conversionDetails") }}
                </p>
                <button class="button button-primary" type="button" :disabled="busy" @click="saveInquiryConversion">{{$t('bookingInquiry.createDraft')}}</button>
              </section>

              <section v-if="inquiryDetail.bookingDraft" class="inquiry-card">
                <div class="inquiry-card-heading">
                  <h4>{{ t('bookingInquiry.bookingDraft') }}</h4>
                  <span class="pill pill-neutral">{{ inquiryDetail.bookingDraft.status }} · revision {{ inquiryDetail.bookingDraft.currentRevisionNumber }}</span>
                </div>
                <p class="fine-print">
                  {{ t("bookingInquiry.draftDetails") }}
                </p>
                <button
                  v-if="canReadBookingDraft"
                  class="button button-secondary"
                  type="button"
                  :disabled="busy"
                  @click="emit('open-booking-draft')"
                >
                  {{ t("bookingInquiry.openDraftButton") }}
                </button>
                <p v-else class="fine-print">{{ t('bookingInquiry.cannotReadDraft') }}</p>
              </section>
            </div>

            <slot name="booking-draft-editor" />

            <slot name="booking-offer-workspace" />

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>{{ t('bookingInquiry.internalNotes') }}</h4>
                <span class="pill pill-neutral">{{ t('bookingInquiry.staffOnly') }}</span>
              </div>
              <div v-if="inquiryDetail.annotations.length" class="inquiry-note-list">
                <article v-for="note in inquiryDetail.annotations" :key="note.annotationId" class="inquiry-note">
                  <p>{{ note.annotation }}</p>
                  <span>{{ formatDate(note.createdAt) }}</span>
                </article>
              </div>
              <p v-else class="muted">{{ t('bookingInquiry.noNotes') }}</p>
              <form v-if="inquiryCapabilities.canAnnotate" class="inquiry-note-form" @submit.prevent="saveInquiryAnnotation">
                <label>{{$t('bookingInquiry.addInternalNote')}}<textarea v-model="inquiryAnnotationText" rows="3" maxlength="4000" placeholder="Record an internal observation or follow-up…"></textarea>
                </label>
                <div class="form-actions">
                  <button class="button button-secondary" type="submit" :disabled="busy || !inquiryAnnotationText.trim()">{{ t('bookingInquiry.addNote') }}</button>
                  <span class="fine-print">{{ inquiryAnnotationText.length }} / 4,000</span>
                </div>
              </form>
              <p v-else class="fine-print">{{ t('bookingInquiry.cannotAnnotate') }}</p>
            </section>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.statusHistory') }}</h4>
                <ol v-if="inquiryDetail.statusHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.statusHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ history.previousStatus ? inquiryStatusLabel(history.previousStatus) : t("bookingInquiry.created") }} → {{ inquiryStatusLabel(history.newStatus) }}</strong>
                    <span>{{ history.reason ?? "No reason supplied" }}</span>
                    <small>{{ history.actorKind }} · {{ formatDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">{{ t('bookingInquiry.noStatusChanges') }}</p>
              </section>
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.assignmentHistory') }}</h4>
                <ol v-if="inquiryDetail.assignmentHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.assignmentHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ resolveInquiryAssigneeName(history.previousAssigneeMembershipId, principal?.membershipId, inquiryAssignees) }} → {{ resolveInquiryAssigneeName(history.newAssigneeMembershipId, principal?.membershipId, inquiryAssignees) }}</strong>
                    <small>{{ formatDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">{{ t('bookingInquiry.noAssignmentChanges') }}</p>
              </section>
            </div>
          </div>
          <div v-else class="inquiry-detail-empty">
            <span class="brand-mark">E</span>
            <h3>{{ t('bookingInquiry.selectInquiry') }}</h3>
            <p class="muted">{{ t('bookingInquiry.selectInquiryHelp') }}</p>
          </div>
        </div>
      </section>
</template>
