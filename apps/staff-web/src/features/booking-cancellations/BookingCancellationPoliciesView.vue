<script setup lang="ts">
import type { Ref } from "vue";
import { formatInquiryDate } from "../booking-inquiries/presentation";
import type { useBookingCancellationPolicies } from "./useBookingCancellationPolicies";

type Workspace = ReturnType<typeof useBookingCancellationPolicies> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();

const {
  cancellationPolicies,
  selectedCancellationPolicyId,
  cancellationPolicyCreateForm,
  cancellationPolicyCustomerMode,
  cancellationPolicyPublicTerms,
  cancellationPolicyApprovalRulesJson,
  cancellationPolicyCommercialRulesJson,
  cancellationPolicyNoticeRulesJson,
  selectedCancellationPolicy,
  selectedCancellationPolicyLatestRevision,
  loadBookingCancellationPolicies,
  selectBookingCancellationPolicy,
  createBookingCancellationPolicy,
  saveBookingCancellationPolicyRevision,
  publishBookingCancellationPolicyRevision,
  busy,
} = props.workspace;
</script>

<template>
<section class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading"><div><p class="eyebrow">ORGANIZATION COMMERCIAL CONTROLS</p><h2>Booking cancellation policies</h2>
          <p class="muted">Configure customer-facing terms and rules. Offers and confirmed bookings retain the exact policy revision they were issued with.</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingCancellationPolicies">Refresh policies</button></div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card"><h4>Create cancellation policy</h4><form class="draft-revision-form" @submit.prevent="createBookingCancellationPolicy">
            <label>Policy code<input v-model="cancellationPolicyCreateForm.code" required minlength="2" maxlength="80" /></label>
            <label>Policy name<input v-model="cancellationPolicyCreateForm.name" required maxlength="250" /></label>
            <button class="button button-primary" type="submit" :disabled="busy">Create policy</button></form></section>
          <section class="inquiry-card"><h4>Existing policies</h4><label>Select policy<select v-model="selectedCancellationPolicyId" @change="selectBookingCancellationPolicy(selectedCancellationPolicyId)">
            <option value="">Choose a policy…</option><option v-for="policy in cancellationPolicies" :key="policy.policyId" :value="policy.policyId">{{ policy.code }} · {{ policy.name }} ({{ policy.status }})</option>
          </select></label><p v-if="!cancellationPolicies.length" class="muted">No cancellation policies are configured.</p>
          <div v-if="selectedCancellationPolicy" class="policy-summary"><strong>{{ selectedCancellationPolicy.name }}</strong><span>{{ selectedCancellationPolicy.code }} · {{ selectedCancellationPolicy.status }}</span></div></section>
        </div>
        <template v-if="selectedCancellationPolicy"><div class="divider"></div>
          <div class="policy-revision-heading"><div><h3>Revision editor · {{ selectedCancellationPolicy.name }}</h3><p class="fine-print">Edit the latest draft or create a successor after publication. Published revisions are immutable.</p></div>
            <span class="pill" :class="selectedCancellationPolicyLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">Latest: {{ selectedCancellationPolicyLatestRevision?.state ?? 'No revision' }}</span></div>
          <div v-if="selectedCancellationPolicyLatestRevision" class="policy-revision-meta"><span>Revision {{ selectedCancellationPolicyLatestRevision.revisionNumber }}</span>
            <span>Created {{ formatInquiryDate(selectedCancellationPolicyLatestRevision.createdAt) }}</span><span>Published {{ formatInquiryDate(selectedCancellationPolicyLatestRevision.publishedAt) }}</span></div>
          <label>Customer cancellation mode<select v-model="cancellationPolicyCustomerMode"><option value="request_only">Request only</option><option value="approval_required">Approval required</option><option value="self_service">Self-service</option></select></label>
          <label>Customer-facing terms<textarea v-model="cancellationPolicyPublicTerms" rows="6" maxlength="10000" placeholder="Enter the exact terms shown to customers."></textarea></label>
          <div class="field-grid"><label>Approval rules (JSON object)<textarea v-model="cancellationPolicyApprovalRulesJson" rows="7" spellcheck="false"></textarea></label>
            <label>Commercial consequences (JSON object)<textarea v-model="cancellationPolicyCommercialRulesJson" rows="7" spellcheck="false"></textarea></label></div>
          <label>Notice rules (JSON object)<textarea v-model="cancellationPolicyNoticeRulesJson" rows="7" spellcheck="false"></textarea></label>
          <p class="fine-print">Rule objects are organization-defined. No notice periods, refund percentages, fees, deposits or legal terms are assumed or prefilled.</p>
          <div class="form-actions"><button class="button button-secondary" type="button" :disabled="busy || selectedCancellationPolicy.status !== 'active'" @click="saveBookingCancellationPolicyRevision">
            {{ selectedCancellationPolicyLatestRevision?.state === 'draft' ? 'Save draft revision' : selectedCancellationPolicy.revisions.length ? 'Create successor draft revision' : 'Create first draft revision' }}</button>
            <button v-if="selectedCancellationPolicyLatestRevision?.state === 'draft'" class="button button-primary" type="button" :disabled="busy" @click="publishBookingCancellationPolicyRevision">Publish latest revision</button></div>
          <div v-if="selectedCancellationPolicy.revisions.length" class="draft-revision-history"><h5>Revision history</h5><ol class="history-list">
            <li v-for="revision in selectedCancellationPolicy.revisions" :key="revision.revisionId"><strong>Revision {{ revision.revisionNumber }} · {{ revision.state }} · {{ revision.customerMode.replaceAll('_', ' ') }}</strong>
              <span>Created {{ formatInquiryDate(revision.createdAt) }}</span><small>Published {{ formatInquiryDate(revision.publishedAt) }} · {{ revision.revisionId }}</small></li></ol></div>
        </template><p v-else class="inquiry-detail-empty"><span class="brand-mark">E</span><strong>Select or create a cancellation policy</strong><span class="muted">Requires organization-level booking.manage permission.</span></p>
      </section>
</template>
