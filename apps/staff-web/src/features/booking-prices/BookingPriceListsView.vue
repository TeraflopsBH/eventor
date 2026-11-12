<script setup lang="ts">
import type { Ref } from "vue";
import { useI18n } from "vue-i18n";
import { useInquiryPresentation } from "../booking-inquiries/useInquiryPresentation";
import type { useBookingPriceLists } from "./useBookingPriceLists";

type Workspace = ReturnType<typeof useBookingPriceLists> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();
const { formatDate } = useInquiryPresentation();
const { t } = useI18n();
const statusLabel = (value: string) => t(`commercialConfiguration.viewValues.${value}`) === `commercialConfiguration.viewValues.${value}` ? value : t(`commercialConfiguration.viewValues.${value}`);
const enumLabel = (value: string) => statusLabel(value);

const {
  bookingPriceLists,
  selectedPriceListId,
  priceListCreateForm,
  priceList{{ t("commercialConfiguration.priceView.revision") }}Form,
  priceListItemsJson,
  priceListTaxProfile{{ t("commercialConfiguration.priceView.revision") }}Id,
  selectedPriceList,
  selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }},
  compatibleTaxProfile{{ t("commercialConfiguration.priceView.revision") }}s,
  loadBookingPriceLists,
  selectBookingPriceList,
  createBookingPriceList,
  createBookingPriceList{{ t("commercialConfiguration.priceView.revision") }},
  saveBookingPriceListDraft,
  publishBookingPriceList{{ t("commercialConfiguration.priceView.revision") }},
  busy,
} = props.workspace;
</script>

<template>
<section class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading">
          <div>
            <p class="eyebrow">{{ t("commercialConfiguration.priceView.organization_commercial_configuration") }}</p>
            <h2>{{ t("commercialConfiguration.priceView.price_lists") }}</h2>
            <p class="muted">{{ t("commercialConfiguration.priceView.manage_versioned_prices_for_bookable_services_drafts_c") }}</p>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingPriceLists">{{ t("commercialConfiguration.priceView.refresh_price_lists") }}</button>
        </div>
        <div class="inquiry-detail-grid">
          <section class="inquiry-card">
            <h4>{{ t("commercialConfiguration.priceView.create_organization_price_list") }}</h4>
            <form class="draft-revision-form" @submit.prevent="createBookingPriceList">
              <label>{{ t("commercialConfiguration.priceView.code") }}<input v-model="priceListCreateForm.code" type="text" required minlength="2" maxlength="80"  :placeholder="t('commercialConfiguration.priceView.price_placeholder_code')" /></label>
              <label>{{ t("commercialConfiguration.priceView.name") }}<input v-model="priceListCreateForm.name" type="text" required maxlength="250"  :placeholder="t('commercialConfiguration.priceView.price_placeholder_name')" /></label>
              <label>{{ t("commercialConfiguration.priceView.currency") }}<input v-model="priceListCreateForm.currency" type="text" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
              <label>{{ t("commercialConfiguration.priceView.tax_basis") }}
                <select v-model="priceListCreateForm.taxBasis">
                  <option value="to_be_confirmed">{{ t("commercialConfiguration.priceView.to_be_confirmed") }}</option>
                  <option value="inclusive">{{ t("commercialConfiguration.priceView.tax_inclusive") }}</option>
                  <option value="exclusive">{{ t("commercialConfiguration.priceView.tax_exclusive") }}</option>
                  <option value="not_applicable">{{ t("commercialConfiguration.priceView.not_applicable") }}</option>
                </select>
              </label>
              <button class="button button-primary" type="submit" :disabled="busy || priceListCreateForm.code.trim().length < 2 || !priceListCreateForm.name.trim()">{{ t("commercialConfiguration.priceView.create_price_list") }}</button>
              <p class="fine-print">{{ t("commercialConfiguration.priceView.currency") }} and tax basis are explicit organization inputs. Eventor does not assume GHB prices or tax treatment.</p>
            </form>
          </section>
          <section class="inquiry-card">
            <h4>{{ t("commercialConfiguration.priceView.existing_price_lists") }}</h4>
            <label>{{ t("commercialConfiguration.priceView.select_price_list") }}
              <select v-model="selectedPriceListId" @change="selectBookingPriceList(selectedPriceListId)">
                <option value="">{{ t("commercialConfiguration.priceView.choose_a_price_list") }}</option>
                <option v-for="priceList in bookingPriceLists" :key="priceList.priceListId" :value="priceList.priceListId">
                  {{ priceList.code }} · {{ priceList.name }} ({{ statusLabel(priceList.status) }})
                </option>
              </select>
            </label>
            <p v-if="!bookingPriceLists.length" class="muted">{{ t("commercialConfiguration.priceView.no_price_lists_are_configured_for_this_organization") }}</p>
            <div v-if="selectedPriceList" class="policy-summary">
              <strong>{{ selectedPriceList.name }}</strong>
              <span>{{ selectedPriceList.code }} · {{ selectedPriceList.scopeKind }} · {{ statusLabel(selectedPriceList.status) }}</span>
              <small class="mono">{{ selectedPriceList.priceListId }}</small>
            </div>
          </section>
        </div>
        <template v-if="selectedPriceList">
          <div class="divider"></div>
          <div class="policy-revision-heading">
            <div>
              <h3>{{ t("commercialConfiguration.priceView.revision_editor") }} · {{ selectedPriceList.name }}</h3>
              <p class="fine-print">{{ t("commercialConfiguration.priceView.edit_the_latest_draft_or_create_a_successor_draft_afte") }}</p>
            </div>
            <span class="pill" :class="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state === 'published' ? 'pill-success' : 'pill-warning'">
              {{ t("commercialConfiguration.priceView.latest") }} {{ selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state ?? "{{ t("commercialConfiguration.priceView.no_revision") }}" }}
            </span>
          </div>
          <div v-if="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}" class="policy-revision-meta">
            <span>{{ t("commercialConfiguration.priceView.revision") }} {{ selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.revisionNumber }}</span>
            <span>{{ selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.currency }} · {{ selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.taxBasis.replaceAll("_", " ") }}</span>
            <span>{{ t("commercialConfiguration.priceView.created") }} {{ formatDate(selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.createdAt) }}</span>
            <span>{{ t("commercialConfiguration.priceView.published") }} {{ formatDate(selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.publishedAt) }}</span>
            <span class="mono">{{ selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}.revisionId }}</span>
          </div>
          <div class="field-grid">
            <label>{{ t("commercialConfiguration.priceView.currency") }}<input v-model="priceList{{ t("commercialConfiguration.priceView.revision") }}Form.currency" type="text" required minlength="3" maxlength="3" pattern="[A-Z]{3}" /></label>
            <label>{{ t("commercialConfiguration.priceView.tax_basis") }}
              <select v-model="priceList{{ t("commercialConfiguration.priceView.revision") }}Form.taxBasis">
                <option value="to_be_confirmed">{{ t("commercialConfiguration.priceView.to_be_confirmed") }}</option>
                <option value="inclusive">{{ t("commercialConfiguration.priceView.tax_inclusive") }}</option>
                <option value="exclusive">{{ t("commercialConfiguration.priceView.tax_exclusive") }}</option>
                <option value="not_applicable">{{ t("commercialConfiguration.priceView.not_applicable") }}</option>
              </select>
            </label>
            <label>{{ t("commercialConfiguration.priceView.effective_from") }}<input v-model="priceList{{ t("commercialConfiguration.priceView.revision") }}Form.effectiveFrom" type="datetime-local" /></label>
            <label>{{ t("commercialConfiguration.priceView.effective_until") }}<input v-model="priceList{{ t("commercialConfiguration.priceView.revision") }}Form.effectiveUntil" type="datetime-local" /></label>
          </div>
          <label>{{ t("commercialConfiguration.priceView.published") }} tax-profile revision
            <select v-model="priceListTaxProfile{{ t("commercialConfiguration.priceView.revision") }}Id" :disabled="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state !== 'draft'">
              <option value="">{{ t("commercialConfiguration.priceView.no_tax_profile_selected") }}</option>
              <option v-for="tax{{ t("commercialConfiguration.priceView.revision") }} in compatibleTaxProfile{{ t("commercialConfiguration.priceView.revision") }}s" :key="tax{{ t("commercialConfiguration.priceView.revision") }}.revisionId" :value="tax{{ t("commercialConfiguration.priceView.revision") }}.revisionId">{{ tax{{ t("commercialConfiguration.priceView.revision") }}.profile{{ t("commercialConfiguration.priceView.code") }} }} · {{ tax{{ t("commercialConfiguration.priceView.revision") }}.profile{{ t("commercialConfiguration.priceView.name") }} }} · rev {{ tax{{ t("commercialConfiguration.priceView.revision") }}.revisionNumber }}</option>
            </select>
          </label>
          <p class="fine-print">A selected tax profile must match the price-list currency and tax basis. Every price item must use a tax{{ t("commercialConfiguration.priceView.code") }} from its catalogue; not-applicable profiles require null tax{{ t("commercialConfiguration.priceView.code") }} values. The selected revision is copied into each offer's immutable terms snapshot.</p>
          <label>{{ t("commercialConfiguration.priceView.price_items_json_array") }}
            <textarea v-model="priceListItemsJson" rows="16" spellcheck="false" :disabled="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state !== 'draft'"></textarea>
          </label>
          <div class="policy-rule-reference">
            <strong>{{ t("commercialConfiguration.priceView.item_format") }}</strong>
            <p class="fine-print">Each item has a stable item{{ t("commercialConfiguration.priceView.code") }}, customer-facing label, unit, unitAmount, optional tax{{ t("commercialConfiguration.priceView.code") }}, quantityMin (default 1) and quantityMax (optional). Amounts are non-negative decimal values.</p>
            <pre>[
  {
    "item{{ t("commercialConfiguration.priceView.code") }}": "MAIN_HALL_DAY",
    "label": "Main hall · full day",
    "unit": "day",
    "unitAmount": 0,
    "tax{{ t("commercialConfiguration.priceView.code") }}": null,
    "quantityMin": 1,
    "quantityMax": 1
  }
]</pre>
            <p class="fine-print">{{ t("commercialConfiguration.priceView.the_zero_amount_above_is_a_format_example_only_not_a_s") }}</p>
          </div>
          <div class="form-actions">
            <button v-if="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state !== 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="createBookingPriceList{{ t("commercialConfiguration.priceView.revision") }}">{{ t("commercialConfiguration.priceView.create_successor_draft_revision") }}</button>
            <button v-if="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="saveBookingPriceListDraft">{{ t("commercialConfiguration.priceView.save_draft") }}</button>
            <button v-if="selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.state === 'draft'" class="button button-primary" type="button" :disabled="busy || !selectedPriceListLatest{{ t("commercialConfiguration.priceView.revision") }}?.items.length" @click="publishBookingPriceList{{ t("commercialConfiguration.priceView.revision") }}">{{ t("commercialConfiguration.priceView.publish_revision") }}</button>
          </div>
          <div v-if="selectedPriceList.revisions.length" class="draft-revision-history">
            <h5>{{ t("commercialConfiguration.priceView.revision") }} history</h5>
            <ol class="history-list">
              <li v-for="revision in selectedPriceList.revisions" :key="revision.revisionId">
                <strong>{{ t("commercialConfiguration.priceView.revision") }} {{ revision.revisionNumber }} · {{ statusLabel(revision.state) }} · {{ revision.items.length }} {{ t("commercialConfiguration.priceView.item_s") }}</strong>
                <span>{{ revision.currency }} · {{ enumLabel(revision.taxBasis) }}</span>
                <small>{{ t("commercialConfiguration.priceView.created") }} {{ formatDate(revision.createdAt) }} · {{ t("commercialConfiguration.priceView.published") }} {{ formatDate(revision.publishedAt) }}</small>
              </li>
            </ol>
          </div>
        </template>
        <p v-else class="inquiry-detail-empty">
          <span class="brand-mark">E</span>
          <strong>{{ t("commercialConfiguration.priceView.select_or_create_a_price_list") }}</strong>
          <span class="muted">{{ t("commercialConfiguration.priceView.price_list_management_requires_the_organization_level_") }}</span>
        </p>
      </section>
</template>
