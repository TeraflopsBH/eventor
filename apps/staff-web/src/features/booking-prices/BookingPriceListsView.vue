<script setup lang="ts">
import type { Ref } from "vue";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";
import type { useBookingPriceLists } from "./useBookingPriceLists";

type Workspace = ReturnType<typeof useBookingPriceLists> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();
const { formatDate } = useInquiryPresentation();

const {
  bookingPriceLists,
  selectedPriceListId,
  priceListCreateForm,
  priceListRevisionForm,
  priceListItemsJson,
  priceListTaxProfileRevisionId,
  selectedPriceList,
  selectedPriceListLatestRevision,
  compatibleTaxProfileRevisions,
  loadBookingPriceLists,
  selectBookingPriceList,
  createBookingPriceList,
  createBookingPriceListRevision,
  saveBookingPriceListDraft,
  publishBookingPriceListRevision,
  busy,
} = props.workspace;
</script>

<template>
<section class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading">
          <div>
            <p class="eyebrow">ORGANIZATION COMMERCIAL CONFIGURATION</p>
            <h2>Price lists</h2>
            <p class="muted">Manage versioned prices for bookable services. Drafts can be edited; published revisions are immutable and remain pinned to offers that use them.</p>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingPriceLists">Refresh price lists</button>
        </div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card">
            <h4>Create organization price list</h4>
            <form class="draft-revision-form" @submit.prevent="createBookingPriceList">
              <label>Code<input v-model="priceListCreateForm.code" type="text" required minlength="2" maxlength="80" placeholder="venue_services" /></label>
              <label>Name<input v-model="priceListCreateForm.name" type="text" required maxlength="250" placeholder="Venue services" /></label>
              <label>Currency<input v-model="priceListCreateForm.currency" type="text" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
              <label>Tax basis
                <select v-model="priceListCreateForm.taxBasis">
                  <option value="to_be_confirmed">To be confirmed</option>
                  <option value="inclusive">Tax inclusive</option>
                  <option value="exclusive">Tax exclusive</option>
                  <option value="not_applicable">Not applicable</option>
                </select>
              </label>
              <button class="button button-primary" type="submit" :disabled="busy || priceListCreateForm.code.trim().length < 2 || !priceListCreateForm.name.trim()">Create price list</button>
              <p class="fine-print">Currency and tax basis are explicit organization inputs. Eventor does not assume GHB prices or tax treatment.</p>
            </form>
          </section>
          <section class="inquiry-card">
            <h4>Existing price lists</h4>
            <label>Select price list
              <select v-model="selectedPriceListId" @change="selectBookingPriceList(selectedPriceListId)">
                <option value="">Choose a price list…</option>
                <option v-for="priceList in bookingPriceLists" :key="priceList.priceListId" :value="priceList.priceListId">
                  {{ priceList.code }} · {{ priceList.name }} ({{ priceList.status }})
                </option>
              </select>
            </label>
            <p v-if="!bookingPriceLists.length" class="muted">No price lists are configured for this organization.</p>
            <div v-if="selectedPriceList" class="policy-summary">
              <strong>{{ selectedPriceList.name }}</strong>
              <span>{{ selectedPriceList.code }} · {{ selectedPriceList.scopeKind }} · {{ selectedPriceList.status }}</span>
              <small class="mono">{{ selectedPriceList.priceListId }}</small>
            </div>
          </section>
        </div>
        <template v-if="selectedPriceList">
          <div class="divider"></div>
          <div class="policy-revision-heading">
            <div>
              <h3>Revision editor · {{ selectedPriceList.name }}</h3>
              <p class="fine-print">Edit the latest draft, or create a successor draft after publication. Save replaces the full draft item set. Publication is a separate, irreversible action.</p>
            </div>
            <span class="pill" :class="selectedPriceListLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">
              Latest: {{ selectedPriceListLatestRevision?.state ?? "No revision" }}
            </span>
          </div>
          <div v-if="selectedPriceListLatestRevision" class="policy-revision-meta">
            <span>Revision {{ selectedPriceListLatestRevision.revisionNumber }}</span>
            <span>{{ selectedPriceListLatestRevision.currency }} · {{ selectedPriceListLatestRevision.taxBasis.replaceAll("_", " ") }}</span>
            <span>Created {{ formatDate(selectedPriceListLatestRevision.createdAt) }}</span>
            <span>Published {{ formatDate(selectedPriceListLatestRevision.publishedAt) }}</span>
            <span class="mono">{{ selectedPriceListLatestRevision.revisionId }}</span>
          </div>
          <div class="field-grid">
            <label>Currency<input v-model="priceListRevisionForm.currency" type="text" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>Tax basis
              <select v-model="priceListRevisionForm.taxBasis">
                <option value="to_be_confirmed">To be confirmed</option>
                <option value="inclusive">Tax inclusive</option>
                <option value="exclusive">Tax exclusive</option>
                <option value="not_applicable">Not applicable</option>
              </select>
            </label>
            <label>Effective from<input v-model="priceListRevisionForm.effectiveFrom" type="datetime-local" /></label>
            <label>Effective until<input v-model="priceListRevisionForm.effectiveUntil" type="datetime-local" /></label>
          </div>
          <label>Published tax-profile revision
            <select v-model="priceListTaxProfileRevisionId" :disabled="selectedPriceListLatestRevision?.state !== 'draft'">
              <option value="">No tax profile selected</option>
              <option v-for="taxRevision in compatibleTaxProfileRevisions" :key="taxRevision.revisionId" :value="taxRevision.revisionId">{{ taxRevision.profileCode }} · {{ taxRevision.profileName }} · rev {{ taxRevision.revisionNumber }}</option>
            </select>
          </label>
          <p class="fine-print">A selected tax profile must match the price-list currency and tax basis. Every price item must use a taxCode from its catalogue; not-applicable profiles require null taxCode values. The selected revision is copied into each offer's immutable terms snapshot.</p>
          <label>Price items (JSON array)
            <textarea v-model="priceListItemsJson" rows="16" spellcheck="false" :disabled="selectedPriceListLatestRevision?.state !== 'draft'"></textarea>
          </label>
          <div class="policy-rule-reference">
            <strong>Item format</strong>
            <p class="fine-print">Each item has a stable itemCode, customer-facing label, unit, unitAmount, optional taxCode, quantityMin (default 1) and quantityMax (optional). Amounts are non-negative decimal values.</p>
            <pre>[
  {
    "itemCode": "MAIN_HALL_DAY",
    "label": "Main hall · full day",
    "unit": "day",
    "unitAmount": 0,
    "taxCode": null,
    "quantityMin": 1,
    "quantityMax": 1
  }
]</pre>
            <p class="fine-print">The zero amount above is a format example only, not a suggested or seeded price.</p>
          </div>
          <div class="form-actions">
            <button v-if="selectedPriceListLatestRevision?.state !== 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="createBookingPriceListRevision">Create successor draft revision</button>
            <button v-if="selectedPriceListLatestRevision?.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="saveBookingPriceListDraft">Save draft</button>
            <button v-if="selectedPriceListLatestRevision?.state === 'draft'" class="button button-primary" type="button" :disabled="busy || !selectedPriceListLatestRevision?.items.length" @click="publishBookingPriceListRevision">Publish revision</button>
          </div>
          <div v-if="selectedPriceList.revisions.length" class="draft-revision-history">
            <h5>Revision history</h5>
            <ol class="history-list">
              <li v-for="revision in selectedPriceList.revisions" :key="revision.revisionId">
                <strong>Revision {{ revision.revisionNumber }} · {{ revision.state }} · {{ revision.items.length }} item(s)</strong>
                <span>{{ revision.currency }} · {{ revision.taxBasis.replaceAll("_", " ") }}</span>
                <small>Created {{ formatDate(revision.createdAt) }} · Published {{ formatDate(revision.publishedAt) }}</small>
              </li>
            </ol>
          </div>
        </template>
        <p v-else class="inquiry-detail-empty">
          <span class="brand-mark">E</span>
          <strong>Select or create a price list</strong>
          <span class="muted">Price-list management requires the organization-level booking.manage permission.</span>
        </p>
      </section>
</template>
