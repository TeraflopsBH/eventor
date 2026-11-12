<script setup lang="ts">
import type { Ref } from "vue";
import { formatInquiryDate } from "../booking-inquiries/presentation";
import type { useBookingTaxProfiles } from "./useBookingTaxProfiles";

type Workspace = ReturnType<typeof useBookingTaxProfiles> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();

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
        <div class="section-heading"><div><p class="eyebrow">ORGANIZATION COMMERCIAL CONFIGURATION</p><h2>Tax profiles</h2>
          <p class="muted">Maintain jurisdiction-neutral tax identifiers, tax codes, rates and rounding settings as immutable revisions.</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingTaxProfiles">Refresh profiles</button></div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card"><h4>Create tax profile</h4><form class="draft-revision-form" @submit.prevent="createBookingTaxProfile">
            <label>Profile code<input v-model="taxProfileCreateForm.code" required minlength="2" maxlength="80" /></label>
            <label>Profile name<input v-model="taxProfileCreateForm.name" required maxlength="250" /></label>
            <label>Jurisdiction / authority identifier<input v-model="taxProfileCreateForm.jurisdictionCode" maxlength="100" placeholder="Organization-defined identifier" /></label>
            <label>Tax registration identifier<input v-model="taxProfileCreateForm.registrationIdentifier" maxlength="120" /></label>
            <label>Currency<input v-model="taxProfileCreateForm.currency" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>Tax basis<select v-model="taxProfileCreateForm.taxBasis"><option value="inclusive">Inclusive</option><option value="exclusive">Exclusive</option><option value="not_applicable">Not applicable</option></select></label>
            <button class="button button-primary" type="submit" :disabled="busy">Create profile</button></form></section>
          <section class="inquiry-card"><h4>Existing profiles</h4><label>Select profile<select v-model="selectedTaxProfileId" @change="selectBookingTaxProfile(selectedTaxProfileId)">
            <option value="">Choose a profile…</option><option v-for="profile in bookingTaxProfiles" :key="profile.taxProfileId" :value="profile.taxProfileId">{{ profile.code }} · {{ profile.name }} ({{ profile.status }})</option>
          </select></label><p v-if="!bookingTaxProfiles.length" class="muted">No tax profiles are configured.</p>
            <div v-if="selectedTaxProfile" class="policy-summary"><strong>{{ selectedTaxProfile.name }}</strong><span>{{ selectedTaxProfile.code }} · {{ selectedTaxProfile.status }}</span></div></section>
        </div>
        <template v-if="selectedTaxProfile"><div class="divider"></div>
          <div class="policy-revision-heading"><div><h3>Revision editor · {{ selectedTaxProfile.name }}</h3><p class="fine-print">Published revisions are immutable. Create a successor to change rates or tax treatment; prior price lists and offers remain pinned.</p></div>
            <span class="pill" :class="selectedTaxProfileLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">Latest: {{ selectedTaxProfileLatestRevision?.state ?? "No revision" }}</span></div>
          <div v-if="selectedTaxProfileLatestRevision" class="policy-revision-meta"><span>Revision {{ selectedTaxProfileLatestRevision.revisionNumber }}</span><span>{{ selectedTaxProfileLatestRevision.currency }} · {{ selectedTaxProfileLatestRevision.taxBasis }}</span><span>Created {{ formatInquiryDate(selectedTaxProfileLatestRevision.createdAt) }}</span><span>Published {{ formatInquiryDate(selectedTaxProfileLatestRevision.publishedAt) }}</span></div>
          <div class="field-grid">
            <label>Jurisdiction / authority identifier<input v-model="taxProfileRevisionForm.jurisdictionCode" maxlength="100" /></label>
            <label>Tax registration identifier<input v-model="taxProfileRevisionForm.registrationIdentifier" maxlength="120" /></label>
            <label>Currency<input v-model="taxProfileRevisionForm.currency" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>Tax basis<select v-model="taxProfileRevisionForm.taxBasis"><option value="inclusive">Inclusive</option><option value="exclusive">Exclusive</option><option value="not_applicable">Not applicable</option></select></label>
            <label>Rounding method<select v-model="taxProfileRevisionForm.roundingMethod"><option value="per_line">Per line</option><option value="per_tax_code">Per tax code</option><option value="invoice_total">Invoice total</option></select></label>
            <label>Rounding decimal places<input v-model.number="taxProfileRevisionForm.roundingScale" type="number" min="0" max="4" /></label>
            <label>Effective from<input v-model="taxProfileRevisionForm.effectiveFrom" type="datetime-local" /></label>
            <label>Effective until<input v-model="taxProfileRevisionForm.effectiveUntil" type="datetime-local" /></label>
          </div>
          <label>Tax-code catalogue (JSON array)<textarea v-model="taxCodesJson" rows="14" spellcheck="false" :disabled="selectedTaxProfileLatestRevision?.state !== 'draft'"></textarea></label>
          <div class="policy-rule-reference"><strong>Tax-code format</strong><p class="fine-print">Each entry has taxCode, label, treatment and rate. Treatments: percentage (rate required, 0–100), zero_rated, exempt, out_of_scope and manual (rate must be null). These are labels/configuration only; tax calculation and legal classification are not performed here.</p>
            <pre>[{"taxCode":"STANDARD","label":"Standard rate","treatment":"percentage","rate":0}]</pre><p class="fine-print">The zero rate is a format example only, not a suggested statutory rate.</p></div>
          <p class="fine-print">No country, tax authority, registration status, rate, exemption or legal treatment is assumed. Validate the profile with the organization's qualified tax adviser before use.</p>
          <div class="form-actions"><button v-if="selectedTaxProfileLatestRevision?.state !== 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="createBookingTaxProfileRevision">Create successor draft revision</button>
            <button v-if="selectedTaxProfileLatestRevision?.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="saveBookingTaxProfileDraft">Save draft</button>
            <button v-if="selectedTaxProfileLatestRevision?.state === 'draft'" class="button button-primary" type="button" :disabled="busy" @click="publishBookingTaxProfileRevision">Publish revision</button></div>
          <div v-if="selectedTaxProfile.revisions.length" class="draft-revision-history"><h5>Revision history</h5><ol class="history-list"><li v-for="revision in selectedTaxProfile.revisions" :key="revision.revisionId"><strong>Revision {{ revision.revisionNumber }} · {{ revision.state }} · {{ revision.taxCodes.length }} tax code(s)</strong><span>{{ revision.currency }} · {{ revision.taxBasis }} · {{ revision.roundingMethod }}</span><small>Published {{ formatInquiryDate(revision.publishedAt) }} · {{ revision.revisionId }}</small></li></ol></div>
        </template>
        <p v-else class="inquiry-detail-empty"><span class="brand-mark">E</span><strong>Select or create a tax profile</strong><span class="muted">Requires organization-level booking.manage permission.</span></p>
      </section>
</template>
