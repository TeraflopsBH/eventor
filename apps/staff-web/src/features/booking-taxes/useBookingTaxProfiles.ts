import { computed, reactive, ref, type Ref } from "vue";
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
import type { BookingTaxProfile, BookingTaxProfileRevisionInput, BookingTaxCode } from "../../api";
interface Dependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  activeTab: Ref<StaffTab>; clearMessages: () => void; showError: (error: unknown) => void;
}
export function useBookingTaxProfiles({ api, busy, pageError, pageNotice, activeTab, clearMessages, showError }: Dependencies) {
const bookingTaxProfiles = ref<BookingTaxProfile[]>([]);
const selectedTaxProfileId = ref("");
const taxProfileCreateForm = reactive({
  code: "", name: "", jurisdictionCode: "", registrationIdentifier: "", currency: "", taxBasis: "exclusive" as "inclusive" | "exclusive" | "not_applicable",
});
const taxProfileRevisionForm = reactive({
  jurisdictionCode: "", registrationIdentifier: "", currency: "",
  taxBasis: "exclusive" as "inclusive" | "exclusive" | "not_applicable",
  roundingMethod: "invoice_total" as "per_line" | "per_tax_code" | "invoice_total",
  roundingScale: 2, effectiveFrom: "", effectiveUntil: "",
});
const taxCodesJson = ref("[]");
const selectedTaxProfile = computed(() =>
  bookingTaxProfiles.value.find((profile) => profile.taxProfileId === selectedTaxProfileId.value) ?? null,
);
const selectedTaxProfileLatestRevision = computed(() => {
  const profile = selectedTaxProfile.value;
  return profile?.revisions.find((revision) => revision.revisionId === profile.latestRevisionId) ?? profile?.revisions[0] ?? null;
});
const publishedTaxProfileRevisions = computed(() => bookingTaxProfiles.value.flatMap((profile) =>
  profile.status === "active" ? profile.revisions.filter((revision) => revision.state === "published").map((revision) => ({
    ...revision, profileCode: profile.code, profileName: profile.name, profileId: profile.taxProfileId,
  })) : [],
));


function syncTaxProfileEditor(): void {
  const revision = selectedTaxProfileLatestRevision.value;
  taxProfileRevisionForm.jurisdictionCode = revision?.jurisdictionCode ?? "";
  taxProfileRevisionForm.registrationIdentifier = revision?.registrationIdentifier ?? "";
  taxProfileRevisionForm.currency = revision?.currency ?? "";
  taxProfileRevisionForm.taxBasis = revision?.taxBasis ?? "exclusive";
  taxProfileRevisionForm.roundingMethod = revision?.roundingMethod ?? "invoice_total";
  taxProfileRevisionForm.roundingScale = revision?.roundingScale ?? 2;
  taxProfileRevisionForm.effectiveFrom = revision?.effectiveFrom ? revision.effectiveFrom.slice(0,16) : "";
  taxProfileRevisionForm.effectiveUntil = revision?.effectiveUntil ? revision.effectiveUntil.slice(0,16) : "";
  taxCodesJson.value = JSON.stringify(revision?.taxCodes ?? [], null, 2);
}

async function loadBookingTaxProfiles(): Promise<void> {
  const result = await api.getBookingTaxProfiles();
  bookingTaxProfiles.value = result.data;
  if (selectedTaxProfileId.value && !result.data.some(profile => profile.taxProfileId === selectedTaxProfileId.value)) selectedTaxProfileId.value = "";
  if (!selectedTaxProfileId.value && result.data.length) selectedTaxProfileId.value = result.data[0]!.taxProfileId;
  syncTaxProfileEditor();
}

async function openBookingTaxProfiles(): Promise<void> {
  activeTab.value = "taxes"; clearMessages(); busy.value = true;
  try { await loadBookingTaxProfiles(); } catch (error) { showError(error); } finally { busy.value = false; }
}

function selectBookingTaxProfile(id: string): void { selectedTaxProfileId.value = id; syncTaxProfileEditor(); }

function taxProfileRevisionPayload(): BookingTaxProfileRevisionInput {
  if (!/^[A-Z]{3}$/.test(taxProfileRevisionForm.currency.trim().toUpperCase())) throw new Error("Currency must be a three-letter uppercase code.");
  if (!Number.isInteger(taxProfileRevisionForm.roundingScale) || taxProfileRevisionForm.roundingScale < 0 || taxProfileRevisionForm.roundingScale > 4) throw new Error("Rounding decimal places must be an integer from 0 to 4.");
  const taxCodes: unknown = JSON.parse(taxCodesJson.value);
  if (!Array.isArray(taxCodes) || taxCodes.length > 200) throw new Error("Tax codes must be a JSON array with at most 200 entries.");
  const seen = new Set<string>();
  for (const value of taxCodes) {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Each tax code must be an object.");
    const row = value as Record<string, unknown>;
    if (typeof row.taxCode !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(row.taxCode) ||
        typeof row.label !== "string" || !row.label.trim() ||
        !["percentage","zero_rated","exempt","out_of_scope","manual"].includes(String(row.treatment)) ||
        !(row.rate === null || (typeof row.rate === "number" && Number.isFinite(row.rate) && row.rate >= 0 && row.rate <= 100))) {
      throw new Error("Each tax code needs a valid taxCode, label, treatment and numeric/null rate.");
    }
    if (seen.has(row.taxCode)) throw new Error("Tax codes must be unique within a profile revision.");
    seen.add(row.taxCode);
    if ((row.treatment === "percentage" && typeof row.rate !== "number") ||
        (row.treatment !== "percentage" && row.rate !== null)) throw new Error("Only percentage tax codes may have a rate.");
  }
  if (taxProfileRevisionForm.taxBasis === "not_applicable" && taxCodes.length > 0) throw new Error("A not-applicable tax profile cannot contain tax codes.");
  return {
    jurisdictionCode: taxProfileRevisionForm.jurisdictionCode.trim() || null,
    registrationIdentifier: taxProfileRevisionForm.registrationIdentifier.trim() || null,
    currency: taxProfileRevisionForm.currency.trim().toUpperCase(),
    taxBasis: taxProfileRevisionForm.taxBasis,
    roundingMethod: taxProfileRevisionForm.roundingMethod,
    roundingScale: taxProfileRevisionForm.roundingScale,
    effectiveFrom: taxProfileRevisionForm.effectiveFrom ? new Date(taxProfileRevisionForm.effectiveFrom).toISOString() : null,
    effectiveUntil: taxProfileRevisionForm.effectiveUntil ? new Date(taxProfileRevisionForm.effectiveUntil).toISOString() : null,
    taxCodes: taxCodes as BookingTaxCode[],
  };
}

async function createBookingTaxProfile(): Promise<void> {
  const code=taxProfileCreateForm.code.trim(), name=taxProfileCreateForm.name.trim();
  if (code.length<2 || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(code) || !name || !/^[A-Z]{3}$/.test(taxProfileCreateForm.currency)) {
    pageError.value="Enter a valid profile code, name and three-letter currency."; return;
  }
  if (!window.confirm("Create an organization tax profile with an unpublished first revision?")) return;
  clearMessages(); busy.value=true;
  try {
    const result=await api.createBookingTaxProfile({
      code,name,jurisdictionCode:taxProfileCreateForm.jurisdictionCode.trim()||null,
      registrationIdentifier:taxProfileCreateForm.registrationIdentifier.trim()||null,
      currency:taxProfileCreateForm.currency.toUpperCase(),taxBasis:taxProfileCreateForm.taxBasis,
    });
    selectedTaxProfileId.value=result.data.taxProfileId;
    taxProfileCreateForm.code=""; taxProfileCreateForm.name="";
    await loadBookingTaxProfiles();
    pageNotice.value="Tax profile created. Add its tax codes and publish the first revision.";
  } catch(error){showError(error);} finally{busy.value=false;}
}

async function createBookingTaxProfileRevision(): Promise<void> {
  const profile=selectedTaxProfile.value, latest=selectedTaxProfileLatestRevision.value;
  if(!profile || profile.status!=="active" || latest?.state==="draft")return;
  if(!window.confirm("Create a successor draft revision? Existing price lists and offers keep their currently pinned tax revision."))return;
  clearMessages();busy.value=true;
  try{
    await api.createBookingTaxProfileRevision(profile.taxProfileId,{
      jurisdictionCode:taxProfileRevisionForm.jurisdictionCode.trim()||null,
      registrationIdentifier:taxProfileRevisionForm.registrationIdentifier.trim()||null,
      currency:taxProfileRevisionForm.currency.trim().toUpperCase(),taxBasis:taxProfileRevisionForm.taxBasis,
      roundingMethod:taxProfileRevisionForm.roundingMethod,roundingScale:taxProfileRevisionForm.roundingScale,
      effectiveFrom:taxProfileRevisionForm.effectiveFrom?new Date(taxProfileRevisionForm.effectiveFrom).toISOString():null,
      effectiveUntil:taxProfileRevisionForm.effectiveUntil?new Date(taxProfileRevisionForm.effectiveUntil).toISOString():null,
    });
    await loadBookingTaxProfiles();pageNotice.value="Successor tax profile draft created. Review its copied tax codes before saving.";
  }catch(error){showError(error);}finally{busy.value=false;}
}

async function saveBookingTaxProfileDraft(): Promise<void> {
  const profile=selectedTaxProfile.value,revision=selectedTaxProfileLatestRevision.value;
  if(!profile||!revision||revision.state!=="draft")return;
  let body:BookingTaxProfileRevisionInput;
  try{body=taxProfileRevisionPayload();}catch(error){pageError.value=error instanceof Error?error.message:"Invalid tax profile revision.";return;}
  if(!window.confirm("Save this tax profile draft? It remains inactive until explicitly published."))return;
  clearMessages();busy.value=true;
  try{
    const result=await api.updateBookingTaxProfileDraftRevision(profile.taxProfileId,revision.revisionId,body);
    await loadBookingTaxProfiles();pageNotice.value="Tax profile revision "+result.data.revisionNumber+" saved as draft.";
  }catch(error){showError(error);}finally{busy.value=false;}
}

async function publishBookingTaxProfileRevision(): Promise<void> {
  const profile=selectedTaxProfile.value,revision=selectedTaxProfileLatestRevision.value;
  if(!profile||!revision||revision.state!=="draft")return;
  if(!window.confirm("Publish this exact tax profile revision? It becomes immutable and can be selected by compatible price lists."))return;
  clearMessages();busy.value=true;
  try{
    const result=await api.publishBookingTaxProfileRevision(profile.taxProfileId,revision.revisionId);
    await loadBookingTaxProfiles();pageNotice.value="Tax profile revision "+result.data.revisionNumber+" published.";
  }catch(error){showError(error);}finally{busy.value=false;}
}
return { bookingTaxProfiles, selectedTaxProfileId, taxProfileCreateForm, taxProfileRevisionForm, taxCodesJson, selectedTaxProfile, selectedTaxProfileLatestRevision, publishedTaxProfileRevisions, syncTaxProfileEditor, loadBookingTaxProfiles, openBookingTaxProfiles, selectBookingTaxProfile, taxProfileRevisionPayload, createBookingTaxProfile, createBookingTaxProfileRevision, saveBookingTaxProfileDraft, publishBookingTaxProfileRevision };
}
