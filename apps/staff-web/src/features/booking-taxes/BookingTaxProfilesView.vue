<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";
import type { useBookingTaxProfiles } from "./useBookingTaxProfiles";

type Workspace = ReturnType<typeof useBookingTaxProfiles> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();
const { formatDate } = useInquiryPresentation();
const { t } = useI18n();
const statusLabel = (value: string) => { const key = `commercialConfiguration.viewValues.${value}`; const translated = t(key); return translated === key ? value : translated; };
const enumLabel = (value: string) => statusLabel(value);

const {
  bookingTaxProfiles,
  selectedTaxProfileId,
  taxProfileCreateForm,
  taxProfileRevisionForm,
  taxCodesJson,
  selectedTaxProfile,
  selectedTaxProfileLatestRevision,
  loadBookingTaxProfiles,
  selectBookingTaxProfile,
  createBookingTaxProfile,
  createBookingTaxProfileRevision,
  saveBookingTaxProfileDraft,
  publishBookingTaxProfileRevision,
  busy,
} = props.workspace;
</script>

<template>
<section class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading"><div><p class="eyebrow">{{ t("commercialConfiguration.taxView.organization_commercial_configuration") }}</p><h2>{{ t("commercialConfiguration.taxView.tax_profiles") }}</h2>
          <p class="muted">{{ t("commercialConfiguration.taxView.maintain_jurisdiction_neutral_tax_identifiers_tax_codes") }}</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingTaxProfiles">{{ t("commercialConfiguration.taxView.refresh_profiles") }}</button></div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card"><h4>{{ t("commercialConfiguration.taxView.create_tax_profile") }}</h4><form class="draft-revision-form" @submit.prevent="createBookingTaxProfile">
            <label>{{ t("commercialConfiguration.taxView.profile_code") }}<input v-model="taxProfileCreateForm.code" required minlength="2" maxlength="80" /></label>
            <label>{{ t("commercialConfiguration.taxView.profile_name") }}<input v-model="taxProfileCreateForm.name" required maxlength="250" /></label>
            <label>{{ t("commercialConfiguration.taxView.jurisdiction_authority_identifier") }}<input v-model="taxProfileCreateForm.jurisdictionCode" maxlength="100" placeholder="Organization-defined identifier" /></label>
            <label>{{ t("commercialConfiguration.taxView.tax_registration_identifier") }}<input v-model="taxProfileCreateForm.registrationIdentifier" maxlength="120" /></label>
            <label>{{ t("commercialConfiguration.taxView.currency") }}<input v-model="taxProfileCreateForm.currency" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>{{ t("commercialConfiguration.taxView.tax_basis") }}<select v-model="taxProfileCreateForm.taxBasis"><option value="inclusive">{{ t("commercialConfiguration.taxView.inclusive") }}</option><option value="exclusive">{{ t("commercialConfiguration.taxView.exclusive") }}</option><option value="not_applicable">{{ t("commercialConfiguration.taxView.not_applicable") }}</option></select></label>
            <button class="button button-primary" type="submit" :disabled="busy">{{ t("commercialConfiguration.taxView.create_profile") }}</button></form></section>
          <section class="inquiry-card"><h4>{{ t("commercialConfiguration.taxView.existing_profiles") }}</h4><label>{{ t("commercialConfiguration.taxView.select_profile") }}<select v-model="selectedTaxProfileId" @change="selectBookingTaxProfile(selectedTaxProfileId)">
            <option value="">{{ t("commercialConfiguration.taxView.choose_a_profile") }}</option><option v-for="profile in bookingTaxProfiles" :key="profile.taxProfileId" :value="profile.taxProfileId">{{ profile.code }} · {{ profile.name }} ({{ statusLabel(profile.status) }})</option>
          </select></label><p v-if="!bookingTaxProfiles.length" class="muted">{{ t("commercialConfiguration.taxView.no_tax_profiles_are_configured") }}</p>
            <div v-if="selectedTaxProfile" class="policy-summary"><strong>{{ selectedTaxProfile.name }}</strong><span>{{ selectedTaxProfile.code }} · {{ statusLabel(selectedTaxProfile.status) }}</span></div></section>
        </div>
        <template v-if="selectedTaxProfile"><div class="divider"></div>
          <div class="policy-revision-heading"><div><h3>{{ t("commercialConfiguration.taxView.revision_editor") }} · {{ selectedTaxProfile.name }}</h3><p class="fine-print">{{ t("commercialConfiguration.taxView.published_revisions_are_immutable_create_a_successor_to") }}</p></div>
            <span class="pill" :class="selectedTaxProfileLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">{{ t("commercialConfiguration.taxView.latest") }} {{ statusLabel(selectedTaxProfileLatestRevision?.state ?? 'noRevision') }}</span></div>
          <div v-if="selectedTaxProfileLatestRevision" class="policy-revision-meta"><span>{{ t("commercialConfiguration.taxView.revision") }} {{ selectedTaxProfileLatestRevision.revisionNumber }}</span><span>{{ selectedTaxProfileLatestRevision.currency }} · {{ enumLabel(selectedTaxProfileLatestRevision.taxBasis) }}</span><span>{{ t("commercialConfiguration.taxView.created") }} {{ formatDate(selectedTaxProfileLatestRevision.createdAt) }}</span><span>{{ t("commercialConfiguration.taxView.published") }} {{ formatDate(selectedTaxProfileLatestRevision.publishedAt) }}</span></div>
          <div class="field-grid">
            <label>{{ t("commercialConfiguration.taxView.jurisdiction_authority_identifier") }}<input v-model="taxProfileRevisionForm.jurisdictionCode" maxlength="100" /></label>
            <label>{{ t("commercialConfiguration.taxView.tax_registration_identifier") }}<input v-model="taxProfileRevisionForm.registrationIdentifier" maxlength="120" /></label>
            <label>{{ t("commercialConfiguration.taxView.currency") }}<input v-model="taxProfileRevisionForm.currency" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>{{ t("commercialConfiguration.taxView.tax_basis") }}<select v-model="taxProfileRevisionForm.taxBasis"><option value="inclusive">{{ t("commercialConfiguration.taxView.inclusive") }}</option><option value="exclusive">{{ t("commercialConfiguration.taxView.exclusive") }}</option><option value="not_applicable">{{ t("commercialConfiguration.taxView.not_applicable") }}</option></select></label>
            <label>{{ t("commercialConfiguration.taxView.rounding_method") }}<select v-model="taxProfileRevisionForm.roundingMethod"><option value="per_line">{{ t("commercialConfiguration.taxView.per_line") }}</option><option value="per_tax_code">{{ t("commercialConfiguration.taxView.per_tax_code") }}</option><option value="invoice_total">{{ t("commercialConfiguration.taxView.invoice_total") }}</option></select></label>
            <label>{{ t("commercialConfiguration.taxView.rounding_decimal_places") }}<input v-model.number="taxProfileRevisionForm.roundingScale" type="number" min="0" max="4" /></label>
            <label>{{ t("commercialConfiguration.taxView.effective_from") }}<input v-model="taxProfileRevisionForm.effectiveFrom" type="datetime-local" /></label>
            <label>{{ t("commercialConfiguration.taxView.effective_until") }}<input v-model="taxProfileRevisionForm.effectiveUntil" type="datetime-local" /></label>
          </div>
          <label>{{ t("commercialConfiguration.taxView.tax_code_catalogue_json_array") }}<textarea v-model="taxCodesJson" rows="14" spellcheck="false" :disabled="selectedTaxProfileLatestRevision?.state !== 'draft'"></textarea></label>
          <div class="policy-rule-reference"><strong>{{ t("commercialConfiguration.taxView.tax_code_format") }}</strong><p class="fine-print">{{ t("commercialConfiguration.taxView.each_entry_has_taxcode_label_treatment_and_rate_treatme") }}</p>
            <pre>[{"taxCode":"STANDARD","label":"Standard rate","treatment":"percentage","rate":0}]</pre><p class="fine-print">{{ t("commercialConfiguration.taxView.the_zero_rate_is_a_format_example_only_not_a_suggested_") }}</p></div>
          <p class="fine-print">{{ t("commercialConfiguration.taxView.no_country_tax_authority_registration_status_rate_exemp") }}</p>
          <div class="form-actions"><button v-if="selectedTaxProfileLatestRevision?.state !== 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="createBookingTaxProfileRevision">{{ t("commercialConfiguration.taxView.create_successor_draft_revision") }}</button>
            <button v-if="selectedTaxProfileLatestRevision?.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="saveBookingTaxProfileDraft">{{ t("commercialConfiguration.taxView.save_draft") }}</button>
            <button v-if="selectedTaxProfileLatestRevision?.state === 'draft'" class="button button-primary" type="button" :disabled="busy" @click="publishBookingTaxProfileRevision">{{ t("commercialConfiguration.taxView.publish_revision") }}</button></div>
          <div v-if="selectedTaxProfile.revisions.length" class="draft-revision-history"><h5>{{ t("commercialConfiguration.taxView.revision_history") }}</h5><ol class="history-list"><li v-for="revision in selectedTaxProfile.revisions" :key="revision.revisionId"><strong>{{ t("commercialConfiguration.taxView.revision") }} {{ revision.revisionNumber }} · {{ statusLabel(revision.state) }} · {{ revision.taxCodes.length }} {{ t("commercialConfiguration.taxView.tax_code_s") }}</strong><span>{{ revision.currency }} · {{ enumLabel(revision.taxBasis) }} · {{ enumLabel(revision.roundingMethod) }}</span><small>{{ t("commercialConfiguration.taxView.published") }} {{ formatDate(revision.publishedAt) }} · {{ revision.revisionId }}</small></li></ol></div>
        </template>
        <p v-else class="inquiry-detail-empty"><span class="brand-mark">E</span><strong>{{ t("commercialConfiguration.taxView.select_or_create_a_tax_profile") }}</strong><span class="muted">{{ t("commercialConfiguration.taxView.requires_organization_level_booking_manage_permission") }}</span></p>
      </section>
</template>
