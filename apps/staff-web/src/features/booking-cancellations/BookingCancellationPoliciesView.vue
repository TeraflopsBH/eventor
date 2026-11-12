<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";
import type { useBookingCancellationPolicies } from "./useBookingCancellationPolicies";

type Workspace = ReturnType<typeof useBookingCancellationPolicies> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();
const { formatDate } = useInquiryPresentation();
const { t } = useI18n();
const statusLabel = (value: string) => { const key = `commercialConfiguration.viewValues.${value}`; const translated = t(key); return translated === key ? value : translated; };
const enumLabel = (value: string) => statusLabel(value);

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
        <div class="section-heading"><div><p class="eyebrow">{{ t("commercialConfiguration.cancelView.organization_commercial_controls") }}</p><h2>{{ t("commercialConfiguration.cancelView.booking_cancellation_policies") }}</h2>
          <p class="muted">{{ t("commercialConfiguration.cancelView.configure_customer_facing_terms_and_rules_offers_and_co") }}</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingCancellationPolicies">{{ t("commercialConfiguration.cancelView.refresh_policies") }}</button></div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card"><h4>{{ t("commercialConfiguration.cancelView.create_cancellation_policy") }}</h4><form class="draft-revision-form" @submit.prevent="createBookingCancellationPolicy">
            <label>{{ t("commercialConfiguration.cancelView.policy_code") }}<input v-model="cancellationPolicyCreateForm.code" required minlength="2" maxlength="80" /></label>
            <label>{{ t("commercialConfiguration.cancelView.policy_name") }}<input v-model="cancellationPolicyCreateForm.name" required maxlength="250" /></label>
            <button class="button button-primary" type="submit" :disabled="busy">{{ t("commercialConfiguration.cancelView.create_policy") }}</button></form></section>
          <section class="inquiry-card"><h4>{{ t("commercialConfiguration.cancelView.existing_policies") }}</h4><label>{{ t("commercialConfiguration.cancelView.select_policy") }}<select v-model="selectedCancellationPolicyId" @change="selectBookingCancellationPolicy(selectedCancellationPolicyId)">
            <option value="">{{ t("commercialConfiguration.cancelView.choose_a_policy") }}</option><option v-for="policy in cancellationPolicies" :key="policy.policyId" :value="policy.policyId">{{ policy.code }} · {{ policy.name }} ({{ statusLabel(policy.status) }})</option>
          </select></label><p v-if="!cancellationPolicies.length" class="muted">{{ t("commercialConfiguration.cancelView.no_cancellation_policies_are_configured") }}</p>
          <div v-if="selectedCancellationPolicy" class="policy-summary"><strong>{{ selectedCancellationPolicy.name }}</strong><span>{{ selectedCancellationPolicy.code }} · {{ statusLabel(selectedCancellationPolicy.status) }}</span></div></section>
        </div>
        <template v-if="selectedCancellationPolicy"><div class="divider"></div>
          <div class="policy-revision-heading"><div><h3>{{ t("commercialConfiguration.cancelView.revision_editor") }} · {{ selectedCancellationPolicy.name }}</h3><p class="fine-print">{{ t("commercialConfiguration.cancelView.edit_the_latest_draft_or_create_a_successor_after_publi") }}</p></div>
            <span class="pill" :class="selectedCancellationPolicyLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">{{ t("commercialConfiguration.cancelView.latest") }} {{ statusLabel(selectedCancellationPolicyLatestRevision?.state ?? 'noRevision') }}</span></div>
          <div v-if="selectedCancellationPolicyLatestRevision" class="policy-revision-meta"><span>{{ t("commercialConfiguration.cancelView.revision") }} {{ selectedCancellationPolicyLatestRevision.revisionNumber }}</span>
            <span>{{ t("commercialConfiguration.cancelView.created") }} {{ formatDate(selectedCancellationPolicyLatestRevision.createdAt) }}</span><span>{{ t("commercialConfiguration.cancelView.published") }} {{ formatDate(selectedCancellationPolicyLatestRevision.publishedAt) }}</span></div>
          <label>{{ t("commercialConfiguration.cancelView.customer_cancellation_mode") }}<select v-model="cancellationPolicyCustomerMode"><option value="request_only">{{ t("commercialConfiguration.cancelView.request_only") }}</option><option value="approval_required">{{ t("commercialConfiguration.cancelView.approval_required") }}</option><option value="self_service">{{ t("commercialConfiguration.cancelView.self_service") }}</option></select></label>
          <label>{{ t("commercialConfiguration.cancelView.customer_facing_terms") }}<textarea v-model="cancellationPolicyPublicTerms" rows="6" maxlength="10000"  :placeholder="t('commercialConfiguration.cancelView.enter_the_exact_terms_shown_to_customers')"></textarea></label>
          <div class="field-grid"><label>{{ t("commercialConfiguration.cancelView.approval_rules_json_object") }}<textarea v-model="cancellationPolicyApprovalRulesJson" rows="7" spellcheck="false"></textarea></label>
            <label>{{ t("commercialConfiguration.cancelView.commercial_consequences_json_object") }}<textarea v-model="cancellationPolicyCommercialRulesJson" rows="7" spellcheck="false"></textarea></label></div>
          <label>{{ t("commercialConfiguration.cancelView.notice_rules_json_object") }}<textarea v-model="cancellationPolicyNoticeRulesJson" rows="7" spellcheck="false"></textarea></label>
          <p class="fine-print">{{ t("commercialConfiguration.cancelView.rule_objects_are_organization_defined_no_notice_periods") }}</p>
          <div class="form-actions"><button class="button button-secondary" type="button" :disabled="busy || selectedCancellationPolicy.status !== 'active'" @click="saveBookingCancellationPolicyRevision">
            {{ selectedCancellationPolicyLatestRevision?.state === "draft" ? t("commercialConfiguration.cancelView.save_draft_revision") : selectedCancellationPolicy.revisions.length ? t("commercialConfiguration.cancelView.create_successor_draft_revision") : t("commercialConfiguration.cancelView.create_first_draft_revision") }}</button>
            <button v-if="selectedCancellationPolicyLatestRevision?.state === 'draft'" class="button button-primary" type="button" :disabled="busy" @click="publishBookingCancellationPolicyRevision">{{ t("commercialConfiguration.cancelView.publish_latest_revision") }}</button></div>
          <div v-if="selectedCancellationPolicy.revisions.length" class="draft-revision-history"><h5>{{ t("commercialConfiguration.cancelView.revision_history") }}</h5><ol class="history-list">
            <li v-for="revision in selectedCancellationPolicy.revisions" :key="revision.revisionId"><strong>{{ t("commercialConfiguration.cancelView.revision") }} {{ revision.revisionNumber }} · {{ statusLabel(revision.state) }} · {{ enumLabel(revision.customerMode) }}</strong>
              <span>{{ t("commercialConfiguration.cancelView.created") }} {{ formatDate(revision.createdAt) }}</span><small>{{ t("commercialConfiguration.cancelView.published") }} {{ formatDate(revision.publishedAt) }} · {{ revision.revisionId }}</small></li></ol></div>
        </template><p v-else class="inquiry-detail-empty"><span class="brand-mark">E</span><strong>{{ t("commercialConfiguration.cancelView.select_or_create_a_cancellation_policy") }}</strong><span class="muted">{{ t("commercialConfiguration.cancelView.requires_organization_level_booking_manage_permission") }}</span></p>
      </section>
</template>
