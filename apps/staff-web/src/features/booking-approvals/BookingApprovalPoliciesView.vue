<script setup lang="ts">
import type { Ref } from "vue";
import { formatInquiryDate } from "../booking-inquiries/presentation";
import type { useBookingApprovalPolicies } from "./useBookingApprovalPolicies";

type Workspace = ReturnType<typeof useBookingApprovalPolicies> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();

const {
  approvalPolicies,
  selectedApprovalPolicyId,
  approvalPolicyCreateForm,
  approvalPolicyRulesJson,
  selectedApprovalPolicy,
  selectedApprovalPolicyLatestRevision,
  loadBookingApprovalPolicies,
  selectBookingApprovalPolicy,
  createBookingApprovalPolicy,
  createBookingApprovalPolicyRevision,
  publishBookingApprovalPolicyRevision,
  busy,
} = props.workspace;
</script>

<template>
<section class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading">
          <div>
            <p class="eyebrow">ORGANIZATION COMMERCIAL CONTROLS</p>
            <h2>Booking approval policies</h2>
            <p class="muted">Create versioned rules that determine which offers require internal approval. Published revisions are immutable and only affect offers created against that revision.</p>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingApprovalPolicies">Refresh policies</button>
        </div>

        <div class="inquiry-detail-grid">
          <section class="inquiry-card">
            <h4>Create approval policy</h4>
            <form class="draft-revision-form" @submit.prevent="createBookingApprovalPolicy">
              <label>Policy code
                <input v-model="approvalPolicyCreateForm.code" type="text" required minlength="2" maxlength="80" placeholder="venue_booking_approvals" />
              </label>
              <label>Policy name
                <input v-model="approvalPolicyCreateForm.name" type="text" required maxlength="250" placeholder="Venue booking approvals" />
              </label>
              <button class="button button-primary" type="submit" :disabled="busy || approvalPolicyCreateForm.code.trim().length < 2 || !approvalPolicyCreateForm.name.trim()">Create policy</button>
            </form>
          </section>
          <section class="inquiry-card">
            <h4>Existing policies</h4>
            <label>Select policy
              <select v-model="selectedApprovalPolicyId" @change="selectBookingApprovalPolicy(selectedApprovalPolicyId)">
                <option value="">Choose a policy…</option>
                <option v-for="policy in approvalPolicies" :key="policy.policyId" :value="policy.policyId">
                  {{ policy.code }} · {{ policy.name }} ({{ policy.status }})
                </option>
              </select>
            </label>
            <p v-if="!approvalPolicies.length" class="muted">No approval policies are configured for this organization.</p>
            <div v-if="selectedApprovalPolicy" class="policy-summary">
              <strong>{{ selectedApprovalPolicy.name }}</strong>
              <span>{{ selectedApprovalPolicy.code }} · {{ selectedApprovalPolicy.status }}</span>
              <small class="mono">{{ selectedApprovalPolicy.policyId }}</small>
            </div>
          </section>
        </div>

        <template v-if="selectedApprovalPolicy">
          <div class="divider"></div>
          <div class="policy-revision-heading">
            <div>
              <h3>Rule editor · {{ selectedApprovalPolicy.name }}</h3>
              <p class="fine-print">Edit the latest draft revision or start the next revision after publication. Publish it as a separate explicit action. The backend validates rule semantics and permissions.</p>
            </div>
            <span class="pill" :class="selectedApprovalPolicyLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">
              Latest: {{ selectedApprovalPolicyLatestRevision?.state ?? "No revision" }}
            </span>
          </div>
          <div v-if="selectedApprovalPolicyLatestRevision" class="policy-revision-meta">
            <span>Revision {{ selectedApprovalPolicyLatestRevision.revisionNumber }}</span>
            <span>Created {{ formatInquiryDate(selectedApprovalPolicyLatestRevision.createdAt) }}</span>
            <span>Published {{ formatInquiryDate(selectedApprovalPolicyLatestRevision.publishedAt) }}</span>
            <span class="mono">{{ selectedApprovalPolicyLatestRevision.revisionId }}</span>
          </div>
          <label>Approval rules (JSON array)
            <textarea v-model="approvalPolicyRulesJson" rows="16" spellcheck="false"></textarea>
          </label>
          <div class="policy-rule-reference">
            <strong>Supported conditions</strong>
            <ul>
              <li><code>always</code> — every offer using the policy triggers the requirement.</li>
              <li><code>total_at_least</code> — requires <code>amount</code> and matching three-letter <code>currency</code>.</li>
              <li><code>discount_at_least</code> — triggers when discounts and credits reach the configured amount.</li>
              <li><code>adjustment_present</code> — triggers when any adjustment, or a selected fee/discount/credit kind, exists.</li>
            </ul>
            <p class="fine-print">Each rule must define a unique code, requiredApprovals (1–10), permission exactly <code>booking.approve</code>, and separationOfDuties (true/false). No role assignments or monetary thresholds are preconfigured by Eventor.</p>
            <pre>[
  {
    "code": "high_value",
    "condition": { "kind": "total_at_least", "amount": 1000, "currency": "BAM" },
    "requiredApprovals": 2,
    "permission": "booking.approve",
    "separationOfDuties": true
  }
]</pre>
          </div>
          <div class="form-actions">
            <button class="button button-secondary" type="button" :disabled="busy || selectedApprovalPolicy.status !== 'active'" @click="createBookingApprovalPolicyRevision">
              {{ selectedApprovalPolicyLatestRevision?.state === "draft" ? "Save draft revision" : selectedApprovalPolicy.revisions.length ? "Create successor draft revision" : "Create first draft revision" }}
            </button>
            <button
              v-if="selectedApprovalPolicyLatestRevision?.state === 'draft'"
              class="button button-primary"
              type="button"
              :disabled="busy"
              @click="publishBookingApprovalPolicyRevision"
            >
              Publish latest revision
            </button>
          </div>
          <div v-if="selectedApprovalPolicy.revisions.length" class="draft-revision-history">
            <h5>Revision history</h5>
            <ol class="history-list">
              <li v-for="revision in selectedApprovalPolicy.revisions" :key="revision.revisionId">
                <strong>Revision {{ revision.revisionNumber }} · {{ revision.state }} · {{ revision.rules.length }} rule(s)</strong>
                <span>Created {{ formatInquiryDate(revision.createdAt) }}</span>
                <small>Published {{ formatInquiryDate(revision.publishedAt) }} · {{ revision.revisionId }}</small>
              </li>
            </ol>
          </div>
        </template>
        <p v-else class="inquiry-detail-empty">
          <span class="brand-mark">E</span>
          <strong>Select or create an approval policy</strong>
          <span class="muted">Policy management requires the organization-level booking.manage permission.</span>
        </p>
      </section>
</template>
