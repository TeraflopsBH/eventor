import { computed, reactive, ref, type ComputedRef, type Ref } from "vue";
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
import type { BookingPriceList, BookingPriceListItem, BookingTaxProfileRevision } from "../../api";
type PublishedTaxProfileRevision = BookingTaxProfileRevision & { profileCode: string; profileName: string; profileId: string };
interface Dependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  activeTab: Ref<StaffTab>; clearMessages: () => void; showError: (error: unknown) => void;
  publishedTaxProfileRevisions: ComputedRef<PublishedTaxProfileRevision[]>;
  loadBookingTaxProfiles: () => Promise<void>;
}
export function useBookingPriceLists({ api, busy, pageError, pageNotice, activeTab, clearMessages, showError, publishedTaxProfileRevisions, loadBookingTaxProfiles }: Dependencies) {
const bookingPriceLists = ref<BookingPriceList[]>([]);
const selectedPriceListId = ref("");
const priceListCreateForm = reactive({ code: "", name: "", currency: "", taxBasis: "to_be_confirmed" as "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed" });
const priceListRevisionForm = reactive({
  currency: "",
  taxBasis: "to_be_confirmed" as "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed",
  effectiveFrom: "",
  effectiveUntil: "",
});
const priceListItemsJson = ref("[]");
const selectedPriceList = computed(() =>
  bookingPriceLists.value.find((item) => item.priceListId === selectedPriceListId.value) ?? null,
);
const selectedPriceListLatestRevision = computed(() => {
  const priceList = selectedPriceList.value;
  return priceList?.revisions.find((revision) => revision.revisionId === priceList.latestRevisionId)
    ?? priceList?.revisions[0]
    ?? null;
});
const priceListTaxProfileRevisionId = ref("");
const compatibleTaxProfileRevisions = computed(() => publishedTaxProfileRevisions.value.filter((revision) => revision.currency === priceListRevisionForm.currency && revision.taxBasis === priceListRevisionForm.taxBasis));
async function loadBookingPriceLists(): Promise<void> {
  const result = await api.getBookingPriceLists();
  bookingPriceLists.value = result.data;
  if (selectedPriceListId.value && !result.data.some((item) => item.priceListId === selectedPriceListId.value)) selectedPriceListId.value = "";
  if (!selectedPriceListId.value && result.data.length) selectedPriceListId.value = result.data[0]!.priceListId;
  syncSelectedPriceListDraft();
}

function syncSelectedPriceListDraft(): void {
  const revision = selectedPriceListLatestRevision.value;
  priceListRevisionForm.currency = revision?.currency ?? "";
  priceListRevisionForm.taxBasis = revision?.taxBasis ?? "to_be_confirmed";
  priceListRevisionForm.effectiveFrom = revision?.state === "draft" && revision.effectiveFrom ? revision.effectiveFrom.slice(0, 16) : "";
  priceListRevisionForm.effectiveUntil = revision?.state === "draft" && revision.effectiveUntil ? revision.effectiveUntil.slice(0, 16) : "";
  priceListItemsJson.value = JSON.stringify(revision?.items ?? [], null, 2);
  priceListTaxProfileRevisionId.value = revision?.taxProfileRevisionId ?? "";
}

async function openBookingPriceLists(): Promise<void> {
  activeTab.value = "prices";
  clearMessages();
  busy.value = true;
  try { await Promise.all([loadBookingPriceLists(), loadBookingTaxProfiles()]); }
  catch (error) { showError(error); }
  finally { busy.value = false; }
}

function selectBookingPriceList(priceListId: string): void {
  selectedPriceListId.value = priceListId;
  syncSelectedPriceListDraft();
}

async function createBookingPriceList(): Promise<void> {
  const code = priceListCreateForm.code.trim();
  const name = priceListCreateForm.name.trim();
  if (code.length < 2 || code.length > 80 || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(code) || !name) {
    pageError.value = "Enter a valid price-list code and name.";
    return;
  }
  if (!window.confirm("Create this organization price list? It starts as an unpublished draft with no items.")) return;
  clearMessages(); busy.value = true;
  try {
    const result = await api.createBookingPriceList({ code, name, currency: priceListCreateForm.currency, taxBasis: priceListCreateForm.taxBasis });
    priceListCreateForm.code = ""; priceListCreateForm.name = "";
    selectedPriceListId.value = result.data.priceListId;
    await loadBookingPriceLists();
    pageNotice.value = "Price list created. Add line items and explicitly publish the draft before using it in an offer.";
  } catch (error) { showError(error); }
  finally { busy.value = false; }
}

async function createBookingPriceListRevision(): Promise<void> {
  const priceList = selectedPriceList.value;
  const latest = selectedPriceListLatestRevision.value;
  if (!priceList || priceList.status !== "active" || latest?.state === "draft") return;
  if (!window.confirm("Create a successor draft revision? Published revisions and offers using them remain unchanged.")) return;
  clearMessages(); busy.value = true;
  try {
    const result = await api.createBookingPriceListRevision(priceList.priceListId, {
      currency: priceListRevisionForm.currency,
      taxBasis: priceListRevisionForm.taxBasis,
      effectiveFrom: priceListRevisionForm.effectiveFrom ? new Date(priceListRevisionForm.effectiveFrom).toISOString() : null,
      effectiveUntil: priceListRevisionForm.effectiveUntil ? new Date(priceListRevisionForm.effectiveUntil).toISOString() : null,
    });
    await loadBookingPriceLists();
    pageNotice.value = "Draft price-list revision " + result.data.revisionNumber + " created. Add its items before publication.";
  } catch (error) { showError(error); }
  finally { busy.value = false; }
}

async function saveBookingPriceListDraft(): Promise<void> {
  const priceList = selectedPriceList.value;
  const revision = selectedPriceListLatestRevision.value;
  if (!priceList || !revision || revision.state !== "draft") return;
  let items: unknown;
  try {
    items = JSON.parse(priceListItemsJson.value);
    if (!Array.isArray(items) || items.length > 500) throw new Error("Items must be a JSON array containing no more than 500 entries.");
    const codes = new Set<string>();
    for (const item of items) {
      if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error("Each price item must be an object.");
      const row = item as Record<string, unknown>;
      if (typeof row.itemCode !== "string" || typeof row.label !== "string" || typeof row.unit !== "string" ||
          typeof row.unitAmount !== "number" || !Number.isFinite(row.unitAmount) || row.unitAmount < 0) {
        throw new Error("Each item needs itemCode, label, unit and a non-negative numeric unitAmount.");
      }
      if (codes.has(row.itemCode)) throw new Error("Price item codes must be unique within a revision.");
      codes.add(row.itemCode);
    }
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : "Price-list items are invalid JSON.";
    return;
  }
  if (!window.confirm("Replace the complete item set on this draft revision? Published revisions are not affected.")) return;
  clearMessages(); busy.value = true;
  try {
    const result = await api.updateBookingPriceListDraftRevision(priceList.priceListId, revision.revisionId, {
      currency: priceListRevisionForm.currency,
      taxBasis: priceListRevisionForm.taxBasis,
      effectiveFrom: priceListRevisionForm.effectiveFrom ? new Date(priceListRevisionForm.effectiveFrom).toISOString() : null,
      effectiveUntil: priceListRevisionForm.effectiveUntil ? new Date(priceListRevisionForm.effectiveUntil).toISOString() : null,
      items: items as BookingPriceListItem[],
    });
    await api.setBookingPriceListTaxProfileRevision(priceList.priceListId, revision.revisionId, priceListTaxProfileRevisionId.value || null);
    await loadBookingPriceLists();
    pageNotice.value = "Draft saved with " + (result.data.itemCount ?? 0) + " price item(s). It remains unpublished.";
  } catch (error) { showError(error); }
  finally { busy.value = false; }
}

async function publishBookingPriceListRevision(): Promise<void> {
  const priceList = selectedPriceList.value;
  const revision = selectedPriceListLatestRevision.value;
  if (!priceList || !revision || revision.state !== "draft") return;
  if (!window.confirm("Publish this exact price-list revision? It becomes immutable and may be selected for new offers.")) return;
  clearMessages(); busy.value = true;
  try {
    const result = await api.publishBookingPriceListRevision(priceList.priceListId, revision.revisionId);
    await loadBookingPriceLists();
    pageNotice.value = "Price-list revision " + result.data.revisionNumber + " published and locked.";
  } catch (error) { showError(error); }
  finally { busy.value = false; }
}
return { bookingPriceLists, selectedPriceListId, priceListCreateForm, priceListRevisionForm, priceListItemsJson, priceListTaxProfileRevisionId, selectedPriceList, selectedPriceListLatestRevision, compatibleTaxProfileRevisions, loadBookingPriceLists, syncSelectedPriceListDraft, openBookingPriceLists, selectBookingPriceList, createBookingPriceList, createBookingPriceListRevision, saveBookingPriceListDraft, publishBookingPriceListRevision };
}
