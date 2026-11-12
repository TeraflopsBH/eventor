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
const inquiry{{ t('bookingInquiry.status') }}Label = (status: string) => t(`bookingInquiry.${({ received: "received", under_review: "underReview", converted: "converted", declined: "declined", withdrawn: "withdrawn", spam: "spam" } as Record<string, string>)[status] ?? status}`);
const emit = defineEmits<{ (event: "open-booking-draft"): void }>();

const {
  inquiryRows, inquiryMeta, inquiryOffset, inquiryFilters, inquiryDetail, inquiryAssignees,
  inquiryCapabilities, selectedInquiryId, inquiry{{ t('bookingInquiry.assignment') }}Choice, inquiry{{ t('bookingInquiry.status') }}Choice,
  inquiry{{ t('bookingInquiry.status') }}Reason, inquiryAnnotationText, inquiry{{ t('bookingInquiry.status') }}Targets, inquiryAnswerItems,
  canEditInquiry{{ t('bookingInquiry.assignment') }}, canConvertInquiry, loadInquiryList, openInquiry, refreshInquiryDetail,
  saveInquiry{{ t('bookingInquiry.assignment') }}, saveInquiry{{ t('bookingInquiry.status') }}, saveInquiryConversion, saveInquiryAnnotation,
  principal, busy, canReadBookingDraft,
} = props.workspace;
</script>

<template>
      <section class="panel inquiry-panel">
        <div class="section-heading">
          <div>
            <p class="eyebrow">{{ t('bookingInquiry.venueBooking') }}</p>
            <h2>{{ t('bookingInquiry.bookingInquiries') }}</h2>
            <p class="muted">{{ t('bookingInquiry.inquiryDescription') }}</p>
          </div>
          <span class="pill pill-neutral">{{ t('bookingInquiry.permissionControlled') }}</span>
        </div>

        <div class="inquiry-toolbar">
          <div class="inquiry-filters">
            <label>{{ t('bookingInquiry.status') }}
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
            <label v-if="inquiryCapabilities.canAssign">{{ t('bookingInquiry.assignedTo') }}
              <select v-model="inquiryFilters.assignedToMembershipId" @change="loadInquiryList(0)">
                <option value="">{{ t('bookingInquiry.allStaff') }}</option>
                <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                  {{ member.displayName }}
                </option>
              </select>
            </label>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadInquiryList(inquiryOffset)">
            {{ t('bookingInquiry.refresh{{ t('bookingInquiry.inbox') }}') }}
          </button>
        </div>

        <div class="inquiry-layout">
          <aside class="inquiry-inbox">
            <div class="inquiry-inbox-heading">
              <strong>{{ t('bookingInquiry.inbox') }}</strong>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} total</span>
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
                  {{ item.requested{{ t('bookingInquiry.start') }} ? formatDate(item.requested{{ t('bookingInquiry.start') }}) : "{{ t('bookingInquiry.dateNotSpecified') }}" }}
                </span>
                <span class="inquiry-list-meta">{{ t('bookingInquiry.assigned') }} {{ resolveInquiryAssigneeName(item.assignedToMembershipId, principal?.membershipId, inquiryAssignees) }}</span>
              </button>
            </div>
            <p v-else class="muted inquiry-empty">{{ t('bookingInquiry.noInquiries') }}</p>
            <div class="pagination inquiry-pagination">
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || inquiryOffset === 0"
                @click="loadInquiryList(Math.max(0, inquiryOffset - 25))"
              >{{ t('bookingInquiry.previous') }}</button>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} inquiries</span>
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
                <p class="eyebrow">{{ t('bookingInquiry.inquiryDetail') }}</p>
                <h3>{{ inquiryDetail.publicReference }}</h3>
                <p class="fine-print">{{ t('bookingInquiry.received') }} {{ formatDate(inquiryDetail.submittedAt) }} · Updated {{ formatDate(inquiryDetail.updatedAt) }}</p>
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
                  <dt>Name</dt><dd>{{ inquiryDetail.requesterName }}</dd>
                  <dt>Email</dt><dd>{{ inquiryDetail.requesterEmail ?? "{{ t('bookingInquiry.notSupplied') }}" }}</dd>
                  <dt>Phone</dt><dd>{{ inquiryDetail.requesterPhone ?? "{{ t('bookingInquiry.notSupplied') }}" }}</dd>
                </dl>
              </section>
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.requestedBooking') }}</h4>
                <dl>
                  <dt>{{ t('bookingInquiry.start') }}</dt><dd>{{ formatDate(inquiryDetail.submittedValues.requested?.startAt ?? inquiryDetail.requested{{ t('bookingInquiry.start') }}) }}</dd>
                  <dt>{{ t('bookingInquiry.end') }}</dt><dd>{{ formatDate(inquiryDetail.submittedValues.requested?.endAt ?? inquiryDetail.requested{{ t('bookingInquiry.end') }}) }}</dd>
                  <dt>{{ t('bookingInquiry.timezone') }}</dt><dd>{{ inquiryDetail.submittedValues.requested?.timezone ?? inquiryDetail.requested{{ t('bookingInquiry.timezone') }} ?? "—" }}</dd>
                  <dt>{{ t('bookingInquiry.spaces') }}</dt><dd>{{ inquiryDetail.submittedValues.requested?.spaceCodes?.join(", ") || "{{ t('bookingInquiry.notSpecified') }}" }}</dd>
                </dl>
              </section>
            </div>

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>{{ t('bookingInquiry.submittedAnswers') }}</h4>
                <span class="fine-print">{{ t('bookingInquiry.formRevision') }} {{ inquiryDetail.formRevisionId.slice(0, 8) }}</span>
              </div>
              <dl v-if="inquiryAnswerItems.length" class="answer-list">
                <template v-for="answer in inquiryAnswerItems" :key="answer.code">
                  <dt>{{ answer.label }}</dt><dd>{{ answer.value }}</dd>
                </template>
              </dl>
              <p v-else class="muted">{{ t('bookingInquiry.noAnswers') }}</p>
            </section>

            <div class="inquiry-detail-grid">
              <section v-if="canEditInquiry{{ t('bookingInquiry.assignment') }}" class="inquiry-card">
                <h4>{{ t('bookingInquiry.assignment') }}</h4>
                <label>{{ t('bookingInquiry.responsibleStaff') }}
                  <select v-model="inquiry{{ t('bookingInquiry.assignment') }}Choice">
                    <option value="unassigned">{{ t('bookingInquiry.unassigned') }}</option>
                    <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                      {{ member.displayName }}{{ member.membershipId === principal?.membershipId ? " {{ t('bookingInquiry.you') }}" : "" }}
                    </option>
                  </select>
                </label>
                <p class="fine-print">{{ t('bookingInquiry.activeMembersOnly') }}</p>
                <button class="button button-secondary" type="button" :disabled="busy" @click="saveInquiry{{ t('bookingInquiry.assignment') }}">{{ t('bookingInquiry.saveAssignment') }}</button>
              </section>

              <section v-if="inquiryCapabilities.canManage && inquiry{{ t('bookingInquiry.status') }}Targets.length" class="inquiry-card">
                <h4>{{ t('bookingInquiry.reviewStatus') }}</h4>
                <label>{{ t('bookingInquiry.newStatus') }}
                  <select v-model="inquiry{{ t('bookingInquiry.status') }}Choice">
                    <option disabled value="">{{ t('bookingInquiry.chooseNextStatus') }}</option>
                    <option v-for="status in inquiry{{ t('bookingInquiry.status') }}Targets" :key="status" :value="status">
                      {{ inquiryStatusLabel(status) }}
                    </option>
                  </select>
                </label>
                <label>{{ t('bookingInquiry.auditReason') }}
                  <textarea v-model="inquiry{{ t('bookingInquiry.status') }}Reason" rows="3" maxlength="1000" placeholder="{{ t('bookingInquiry.explainStatus') }}"></textarea>
                </label>
                <p v-if="inquiry{{ t('bookingInquiry.status') }}Choice === 'declined' || inquiry{{ t('bookingInquiry.status') }}Choice === 'spam'" class="fine-print text-warning">
                  {{ t('bookingInquiry.terminalStatus') }}
                </p>
                <button class="button button-primary" type="button" :disabled="busy || inquiry{{ t('bookingInquiry.status') }}Reason.trim().length < 3" @click="saveInquiry{{ t('bookingInquiry.status') }}">
                  {{ t('bookingInquiry.saveStatus') }}
                </button>
              </section>

              <section v-if="canConvertInquiry" class="inquiry-card">
                <h4>{{ t('bookingInquiry.convertDraft') }}</h4>
                <p class="fine-print">
                  {{ t('bookingInquiry.conversionInfo') }}
                </p>
                <button class="button button-primary" type="button" :disabled="busy" @click="saveInquiryConversion">
                  {{ t('bookingInquiry.createDraft') }}
                </button>
              </section>

              <section v-if="inquiryDetail.bookingDraft" class="inquiry-card">
                <div class="inquiry-card-heading">
                  <h4>{{ t('bookingInquiry.bookingDraft') }}</h4>
                  <span class="pill pill-neutral">{{ inquiryDetail.bookingDraft.status }} · revision {{ inquiryDetail.bookingDraft.currentRevisionNumber }}</span>
                </div>
                <p class="fine-print">
                  {{ t('bookingInquiry.draftInfo') }}
                </p>
                <button
                  v-if="canReadBookingDraft"
                  class="button button-secondary"
                  type="button"
                  :disabled="busy"
                  @click="emit('open-booking-draft')"
                >
                  {{ t('bookingInquiry.openDraft') }}
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
                <label>{{ t('bookingInquiry.addInternalNote') }}
                  <textarea v-model="inquiryAnnotationText" rows="3" maxlength="4000" placeholder="{{ t('bookingInquiry.notePlaceholder') }}"></textarea>
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
                <h4>{{ t('bookingInquiry.status') }} history</h4>
                <ol v-if="inquiryDetail.statusHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.statusHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ history.previous{{ t('bookingInquiry.status') }} ?? "{{ t('bookingInquiry.created') }}" }} → {{ history.new{{ t('bookingInquiry.status') }} }}</strong>
                    <span>{{ history.reason ?? "{{ t('bookingInquiry.noReason') }}" }}</span>
                    <small>{{ history.actorKind }} · {{ formatDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">{{ t('bookingInquiry.noStatusChanges') }}</p>
              </section>
              <section class="inquiry-card">
                <h4>{{ t('bookingInquiry.assignment') }} history</h4>
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
