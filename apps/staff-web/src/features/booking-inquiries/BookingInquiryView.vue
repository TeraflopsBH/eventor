<script setup lang="ts">
import type { ComputedRef, Ref } from "vue";
import type { Principal } from "../../api";
import { formatInquiryDate, resolveInquiryAssigneeName } from "./presentation";
import type { useBookingInquiries } from "./useBookingInquiries";

type BookingInquiryWorkspace = ReturnType<typeof useBookingInquiries> & {
  principal: Ref<Principal | null>;
  busy: Ref<boolean>;
  canReadBookingDraft: ComputedRef<boolean>;
};

const props = defineProps<{ workspace: BookingInquiryWorkspace }>();
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
            <p class="eyebrow">VENUE BOOKING</p>
            <h2>Booking inquiries</h2>
            <p class="muted">Review public requests, assign ownership, record decisions and keep internal notes.</p>
          </div>
          <span class="pill pill-neutral">Permission controlled</span>
        </div>

        <div class="inquiry-toolbar">
          <div class="inquiry-filters">
            <label>Status
              <select v-model="inquiryFilters.status" @change="loadInquiryList(0)">
                <option value="">All statuses</option>
                <option value="received">Received</option>
                <option value="under_review">Under review</option>
                <option value="converted">Converted</option>
                <option value="declined">Declined</option>
                <option value="withdrawn">Withdrawn</option>
                <option value="spam">Spam</option>
              </select>
            </label>
            <label v-if="inquiryCapabilities.canAssign">Assigned to
              <select v-model="inquiryFilters.assignedToMembershipId" @change="loadInquiryList(0)">
                <option value="">All staff</option>
                <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                  {{ member.displayName }}
                </option>
              </select>
            </label>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadInquiryList(inquiryOffset)">
            Refresh inbox
          </button>
        </div>

        <div class="inquiry-layout">
          <aside class="inquiry-inbox">
            <div class="inquiry-inbox-heading">
              <strong>Inbox</strong>
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
                  >{{ item.status.replaceAll("_", " ") }}</span>
                </span>
                <strong class="inquiry-requester">{{ item.requesterName }}</strong>
                <span class="inquiry-list-meta">
                  {{ item.requestedStart ? formatInquiryDate(item.requestedStart) : "Date not specified" }}
                </span>
                <span class="inquiry-list-meta">Assigned: {{ resolveInquiryAssigneeName(item.assignedToMembershipId, principal?.membershipId, inquiryAssignees) }}</span>
              </button>
            </div>
            <p v-else class="muted inquiry-empty">No inquiries match these filters.</p>
            <div class="pagination inquiry-pagination">
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || inquiryOffset === 0"
                @click="loadInquiryList(Math.max(0, inquiryOffset - 25))"
              >Previous</button>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} inquiries</span>
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || !inquiryMeta || inquiryOffset + 25 >= inquiryMeta.totalCount"
                @click="loadInquiryList(inquiryOffset + 25)"
              >Next</button>
            </div>
          </aside>

          <div v-if="inquiryDetail" class="inquiry-detail">
            <div class="inquiry-detail-heading">
              <div>
                <p class="eyebrow">INQUIRY DETAIL</p>
                <h3>{{ inquiryDetail.publicReference }}</h3>
                <p class="fine-print">Received {{ formatInquiryDate(inquiryDetail.submittedAt) }} · Updated {{ formatInquiryDate(inquiryDetail.updatedAt) }}</p>
              </div>
              <div class="inquiry-detail-actions">
                <span
                  class="pill"
                  :class="inquiryDetail.status === 'declined' || inquiryDetail.status === 'spam' ? 'pill-danger' : inquiryDetail.status === 'under_review' ? 'pill-warning' : 'pill-neutral'"
                >{{ inquiryDetail.status.replaceAll("_", " ") }}</span>
                <button class="button button-quiet" type="button" :disabled="busy" @click="refreshInquiryDetail">Refresh detail</button>
              </div>
            </div>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>Requester</h4>
                <dl>
                  <dt>Name</dt><dd>{{ inquiryDetail.requesterName }}</dd>
                  <dt>Email</dt><dd>{{ inquiryDetail.requesterEmail ?? "Not supplied" }}</dd>
                  <dt>Phone</dt><dd>{{ inquiryDetail.requesterPhone ?? "Not supplied" }}</dd>
                </dl>
              </section>
              <section class="inquiry-card">
                <h4>Requested booking</h4>
                <dl>
                  <dt>Start</dt><dd>{{ formatInquiryDate(inquiryDetail.submittedValues.requested?.startAt ?? inquiryDetail.requestedStart) }}</dd>
                  <dt>End</dt><dd>{{ formatInquiryDate(inquiryDetail.submittedValues.requested?.endAt ?? inquiryDetail.requestedEnd) }}</dd>
                  <dt>Timezone</dt><dd>{{ inquiryDetail.submittedValues.requested?.timezone ?? inquiryDetail.requestedTimezone ?? "—" }}</dd>
                  <dt>Spaces</dt><dd>{{ inquiryDetail.submittedValues.requested?.spaceCodes?.join(", ") || "Not specified" }}</dd>
                </dl>
              </section>
            </div>

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>Submitted form answers</h4>
                <span class="fine-print">Form revision {{ inquiryDetail.formRevisionId.slice(0, 8) }}</span>
              </div>
              <dl v-if="inquiryAnswerItems.length" class="answer-list">
                <template v-for="answer in inquiryAnswerItems" :key="answer.code">
                  <dt>{{ answer.label }}</dt><dd>{{ answer.value }}</dd>
                </template>
              </dl>
              <p v-else class="muted">No additional form answers were submitted.</p>
            </section>

            <div class="inquiry-detail-grid">
              <section v-if="canEditInquiryAssignment" class="inquiry-card">
                <h4>Assignment</h4>
                <label>Responsible staff member
                  <select v-model="inquiryAssignmentChoice">
                    <option value="unassigned">Unassigned</option>
                    <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                      {{ member.displayName }}{{ member.membershipId === principal?.membershipId ? " (you)" : "" }}
                    </option>
                  </select>
                </label>
                <p class="fine-print">Only active members of this organization can be assigned.</p>
                <button class="button button-secondary" type="button" :disabled="busy" @click="saveInquiryAssignment">Save assignment</button>
              </section>

              <section v-if="inquiryCapabilities.canManage && inquiryStatusTargets.length" class="inquiry-card">
                <h4>Review status</h4>
                <label>New status
                  <select v-model="inquiryStatusChoice">
                    <option disabled value="">Choose next status…</option>
                    <option v-for="status in inquiryStatusTargets" :key="status" :value="status">
                      {{ status.replaceAll("_", " ") }}
                    </option>
                  </select>
                </label>
                <label>Audit reason
                  <textarea v-model="inquiryStatusReason" rows="3" maxlength="1000" placeholder="Explain the review decision or status change…"></textarea>
                </label>
                <p v-if="inquiryStatusChoice === 'declined' || inquiryStatusChoice === 'spam'" class="fine-print text-warning">
                  This is a terminal status. The inquiry cannot be reopened or reassigned afterward.
                </p>
                <button class="button button-primary" type="button" :disabled="busy || inquiryStatusReason.trim().length < 3" @click="saveInquiryStatus">
                  Save status change
                </button>
              </section>

              <section v-if="canConvertInquiry" class="inquiry-card">
                <h4>Convert to booking draft</h4>
                <p class="fine-print">
                  Creates a separate draft and immutable revision 1 from the submitted request. The original inquiry is retained.
                  This step does not issue an offer, hold availability or confirm a booking.
                </p>
                <button class="button button-primary" type="button" :disabled="busy" @click="saveInquiryConversion">
                  Create booking draft
                </button>
              </section>

              <section v-if="inquiryDetail.bookingDraft" class="inquiry-card">
                <div class="inquiry-card-heading">
                  <h4>Booking draft</h4>
                  <span class="pill pill-neutral">{{ inquiryDetail.bookingDraft.status }} · revision {{ inquiryDetail.bookingDraft.currentRevisionNumber }}</span>
                </div>
                <p class="fine-print">
                  This draft is separate from the original inquiry. Its revisions are immutable; editing creates a new revision.
                  No offer, availability hold or booking confirmation is implied.
                </p>
                <button
                  v-if="canReadBookingDraft"
                  class="button button-secondary"
                  type="button"
                  :disabled="busy"
                  @click="emit('open-booking-draft')"
                >
                  Open booking draft
                </button>
                <p v-else class="fine-print">Your membership does not have permission to read this booking draft.</p>
              </section>
            </div>

            <slot name="booking-draft-editor" />

            <slot name="booking-offer-workspace" />

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>Internal staff notes</h4>
                <span class="pill pill-neutral">Staff only</span>
              </div>
              <div v-if="inquiryDetail.annotations.length" class="inquiry-note-list">
                <article v-for="note in inquiryDetail.annotations" :key="note.annotationId" class="inquiry-note">
                  <p>{{ note.annotation }}</p>
                  <span>{{ formatInquiryDate(note.createdAt) }}</span>
                </article>
              </div>
              <p v-else class="muted">No internal notes have been added.</p>
              <form v-if="inquiryCapabilities.canAnnotate" class="inquiry-note-form" @submit.prevent="saveInquiryAnnotation">
                <label>Add an internal note
                  <textarea v-model="inquiryAnnotationText" rows="3" maxlength="4000" placeholder="Record an internal observation or follow-up…"></textarea>
                </label>
                <div class="form-actions">
                  <button class="button button-secondary" type="submit" :disabled="busy || !inquiryAnnotationText.trim()">Add note</button>
                  <span class="fine-print">{{ inquiryAnnotationText.length }} / 4,000</span>
                </div>
              </form>
              <p v-else class="fine-print">Your membership does not have permission to add internal notes.</p>
            </section>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>Status history</h4>
                <ol v-if="inquiryDetail.statusHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.statusHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ history.previousStatus ?? "Created" }} → {{ history.newStatus }}</strong>
                    <span>{{ history.reason ?? "No reason supplied" }}</span>
                    <small>{{ history.actorKind }} · {{ formatInquiryDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">No status changes recorded.</p>
              </section>
              <section class="inquiry-card">
                <h4>Assignment history</h4>
                <ol v-if="inquiryDetail.assignmentHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.assignmentHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ resolveInquiryAssigneeName(history.previousAssigneeMembershipId, principal?.membershipId, inquiryAssignees) }} → {{ resolveInquiryAssigneeName(history.newAssigneeMembershipId, principal?.membershipId, inquiryAssignees) }}</strong>
                    <small>{{ formatInquiryDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">No assignment changes recorded.</p>
              </section>
            </div>
          </div>
          <div v-else class="inquiry-detail-empty">
            <span class="brand-mark">E</span>
            <h3>Select an inquiry</h3>
            <p class="muted">Choose a request from the inbox to inspect requester details, submitted answers, history and permitted actions.</p>
          </div>
        </div>
      </section>
</template>
