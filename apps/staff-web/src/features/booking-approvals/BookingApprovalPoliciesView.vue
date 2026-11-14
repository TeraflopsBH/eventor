<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";
import type { useBookingApprovalPolicies } from "./useBookingApprovalPolicies";

type Workspace = ReturnType<typeof useBookingApprovalPolicies> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();
const { formatDate } = useInquiryPresentation();
const { t } = useI18n();
const statusLabel = (value: string) => { const key = `commercialConfiguration.viewValues.${value}`; const translated = t(key as never) as string; return translated === key ? value : translated; };

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
            <p class="eyebrow">{{ t("commercialConfiguration.approvalView.organization_commercial_controls") }}</p>
            <h2>{{ t("commercialConfiguration.approvalView.booking_approval_policies") }}</h2>
            <p class="muted">{{ t("commercialConfiguration.approvalView.create_versioned_rules_that_determine_which_offers_requ") }}</p>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingApprovalPolicies">{{ t("commercialConfiguration.approvalView.refresh_policies") }}</button>
        </div>

        <div class="inquiry-detail-grid">
          <section class="inquiry-card">
            <h4>{{ t("commercialConfiguration.approvalView.create_approval_policy") }}</h4>
            <form class="draft-revision-form" @submit.prevent="createBookingApprovalPolicy">
              <label>{{ t("commercialConfiguration.approvalView.policy_code") }}
                <input v-model="approvalPolicyCreateForm.code" type="text" required minlength="2" maxlength="80"  :placeholder="t('commercialConfiguration.approvalView.approval_placeholder_code')" />
              </label>
              <label>{{ t("commercialConfiguration.approvalView.policy_name") }}
                <input v-model="approvalPolicyCreateForm.name" type="text" required maxlength="250"  :placeholder="t('commercialConfiguration.approvalView.approval_placeholder_name')" />
              </label>
              <button class="button button-primary" type="submit" :disabled="busy || approvalPolicyCreateForm.code.trim().length < 2 || !approvalPolicyCreateForm.name.trim()">{{ t("commercialConfiguration.approvalView.create_policy") }}</button>
            </form>
          </section>
          <section class="inquiry-card">
            <h4>{{ t("commercialConfiguration.approvalView.existing_policies") }}</h4>
            <label>{{ t("commercialConfiguration.approvalView.select_policy") }}
              <select v-model="selectedApprovalPolicyId" @change="selectBookingApprovalPolicy(selectedApprovalPolicyId)">
                <option value="">{{ t("commercialConfiguration.approvalView.choose_a_policy") }}</option>
                <option v-for="policy in approvalPolicies" :key="policy.policyId" :value="policy.policyId">
                  {{ policy.code }} · {{ policy.name }} ({{ statusLabel(policy.status) }})
                </option>
              </select>
            </label>
            <p v-if="!approvalPolicies.length" class="muted">{{ t("commercialConfiguration.approvalView.no_approval_policies_are_configured_for_this_organizati") }}</p>
            <div v-if="selectedApprovalPolicy" class="policy-summary">
              <strong>{{ selectedApprovalPolicy.name }}</strong>
              <span>{{ selectedApprovalPolicy.code }} · {{ statusLabel(selectedApprovalPolicy.status) }}</span>
              <small class="mono">{{ selectedApprovalPolicy.policyId }}</small>
            </div>
          </section>
        </div>

        <template v-if="selectedApprovalPolicy">
          <div class="divider"></div>
          <div class="policy-revision-heading">
            <div>
              <h3>{{ t("commercialConfiguration.approvalView.rule_editor") }} · {{ selectedApprovalPolicy.name }}</h3>
              <p class="fine-print">{{ t("commercialConfiguration.approvalView.edit_the_latest_draft_revision_or_start_the_next_revisi") }}</p>
            </div>
            <span class="pill" :class="selectedApprovalPolicyLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">
              {{ t("commercialConfiguration.approvalView.latest") }} {{ statusLabel(selectedApprovalPolicyLatestRevision?.state ?? 'noRevision') }}
            </span>
          </div>
          <div v-if="selectedApprovalPolicyLatestRevision" class="policy-revision-meta">
            <span>{{ t("commercialConfiguration.approvalView.revision") }} {{ selectedApprovalPolicyLatestRevision.revisionNumber }}</span>
            <span>{{ t("commercialConfiguration.approvalView.created") }} {{ formatDate(selectedApprovalPolicyLatestRevision.createdAt) }}</span>
            <span>{{ t("commercialConfiguration.approvalView.published") }} {{ formatDate(selectedApprovalPolicyLatestRevision.publishedAt) }}</span>
            <span class="mono">{{ selectedApprovalPolicyLatestRevision.revisionId }}</span>
          </div>
          <label>{{ t("commercialConfiguration.approvalView.approval_rules_json_array") }}
            <textarea v-model="approvalPolicyRulesJson" rows="16" spellcheck="false"></textarea>
          </label>
          <div class="policy-rule-reference">
            <strong>{{ t("commercialConfiguration.approvalView.supported_conditions") }}</strong>
            <ul>
              <li><code>always</code> {{ t("commercialConfiguration.approvalView.every_offer_using_the_policy_triggers_the_requirement") }}</li>
              <li><code>total_at_least</code> {{ t("commercialConfiguration.approvalView.requires") }} <code>amount</code> {{ t("commercialConfiguration.approvalView.and_matching_three_letter") }} <code>currency</code>.</li>
              <li><code>discount_at_least</code> {{ t("commercialConfiguration.approvalView.triggers_when_discounts_and_credits_reach_the_configure") }}</li>
              <li><code>adjustment_present</code> {{ t("commercialConfiguration.approvalView.triggers_when_any_adjustment_or_a_selected_fee_discount") }}</li>
            </ul>
            <p class="fine-print">{{ t("commercialConfiguration.approvalView.each_rule_must_define_a_unique_code_requiredapprovals_1") }} <code>booking.approve</code>, {{ t("commercialConfiguration.approvalView.and_separation_of_duties") }} separationOfDuties (true/false). {{ t("commercialConfiguration.approvalView.no_role_assignments_or_monetary_thresholds_are_preconfi") }}</p>
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
              {{ selectedApprovalPolicyLatestRevision?.state === "draft" ? t("commercialConfiguration.approvalView.save_draft_revision") : selectedApprovalPolicy.revisions.length ? t("commercialConfiguration.approvalView.create_successor_draft_revision") : t("commercialConfiguration.approvalView.create_first_draft_revision") }}
            </button>
            <button
              v-if="selectedApprovalPolicyLatestRevision?.state === 'draft'"
              class="button button-primary"
              type="button"
              :disabled="busy"
              @click="publishBookingApprovalPolicyRevision"
            >
              {{ t("commercialConfiguration.approvalView.publish_latest_revision") }}
            </button>
          </div>
          <div v-if="selectedApprovalPolicy.revisions.length" class="draft-revision-history">
            <h5>{{ t("commercialConfiguration.approvalView.revision_history") }}</h5>
            <ol class="history-list">
              <li v-for="revision in selectedApprovalPolicy.revisions" :key="revision.revisionId">
                <strong>{{ t("commercialConfiguration.approvalView.revision") }} {{ revision.revisionNumber }} · {{ statusLabel(revision.state) }} · {{ revision.rules.length }} {{ t("commercialConfiguration.approvalView.rule_s") }}</strong>
                <span>{{ t("commercialConfiguration.approvalView.created") }} {{ formatDate(revision.createdAt) }}</span>
                <small>{{ t("commercialConfiguration.approvalView.published") }} {{ formatDate(revision.publishedAt) }} · {{ revision.revisionId }}</small>
              </li>
            </ol>
          </div>
        </template>
        <p v-else class="inquiry-detail-empty">
          <span class="brand-mark">E</span>
          <strong>{{ t("commercialConfiguration.approvalView.select_or_create_an_approval_policy") }}</strong>
          <span class="muted">{{ t("commercialConfiguration.approvalView.policy_management_requires_the_organization_level_booki") }}</span>
        </p>
      </section>
</template>
