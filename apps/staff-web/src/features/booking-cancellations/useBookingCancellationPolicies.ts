import { computed, reactive, ref, type Ref } from "vue";
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
import type { BookingCancellationPolicy, BookingCancellationPolicyRevisionInput } from "../../api";
interface Dependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  activeTab: Ref<StaffTab>; clearMessages: () => void; showError: (error: unknown) => void; translate: (key: string, params?: Record<string, string | number>) => string;
}
export function useBookingCancellationPolicies({ api, busy, pageError, pageNotice, activeTab, clearMessages, showError, translate }: Dependencies) {
const cancellationPolicies = ref<BookingCancellationPolicy[]>([]);
const selectedCancellationPolicyId = ref("");
const cancellationPolicyCreateForm = reactive({ code: "", name: "" });
const cancellationPolicyCustomerMode = ref<"request_only" | "approval_required" | "self_service">("request_only");
const cancellationPolicyPublicTerms = ref("");
const cancellationPolicyApprovalRulesJson = ref("{}");
const cancellationPolicyCommercialRulesJson = ref("{}");
const cancellationPolicyNoticeRulesJson = ref("{}");
const selectedCancellationPolicy = computed(() => cancellationPolicies.value.find((policy) => policy.policyId === selectedCancellationPolicyId.value) ?? null);
const selectedCancellationPolicyLatestRevision = computed(() => {
  const policy = selectedCancellationPolicy.value;
  return policy?.revisions.find((revision) => revision.revisionId === policy.latestRevisionId) ?? policy?.revisions[0] ?? null;
});
function loadCancellationPolicyEditor(): void {
  const revision = selectedCancellationPolicyLatestRevision.value;
  cancellationPolicyCustomerMode.value = revision?.customerMode ?? "request_only";
  cancellationPolicyPublicTerms.value = revision?.publicTerms ?? "";
  cancellationPolicyApprovalRulesJson.value = JSON.stringify(revision?.approvalRules ?? {}, null, 2);
  cancellationPolicyCommercialRulesJson.value = JSON.stringify(revision?.commercialRules ?? {}, null, 2);
  cancellationPolicyNoticeRulesJson.value = JSON.stringify(revision?.noticeRules ?? {}, null, 2);
}

async function loadBookingCancellationPolicies(): Promise<void> {
  const result = await api.getBookingCancellationPolicies();
  cancellationPolicies.value = result.data;
  if (selectedCancellationPolicyId.value && !result.data.some((policy) => policy.policyId === selectedCancellationPolicyId.value)) selectedCancellationPolicyId.value = "";
  if (!selectedCancellationPolicyId.value && result.data.length) selectedCancellationPolicyId.value = result.data[0]!.policyId;
  loadCancellationPolicyEditor();
}

async function openBookingCancellationPolicies(): Promise<void> {
  activeTab.value = "cancellations"; clearMessages(); busy.value = true;
  try { await loadBookingCancellationPolicies(); } catch (error) { showError(error); } finally { busy.value = false; }
}

function selectBookingCancellationPolicy(policyId: string): void { selectedCancellationPolicyId.value = policyId; loadCancellationPolicyEditor(); }

async function createBookingCancellationPolicy(): Promise<void> {
  const code = cancellationPolicyCreateForm.code.trim(), name = cancellationPolicyCreateForm.name.trim();
  if (code.length < 2 || code.length > 80 || !name || name.length > 250) { pageError.value = translate("commercialConfiguration.cancelFields"); return; }
  if (!window.confirm(translate("commercialConfiguration.cancelCreateConfirm"))) return;
  clearMessages(); busy.value = true;
  try {
    const result = await api.createBookingCancellationPolicy({ code, name });
    cancellationPolicyCreateForm.code = ""; cancellationPolicyCreateForm.name = "";
    selectedCancellationPolicyId.value = result.data.policyId;
    await loadBookingCancellationPolicies(); pageNotice.value = translate("commercialConfiguration.cancelCreated");
  } catch (error) { showError(error); } finally { busy.value = false; }
}

async function saveBookingCancellationPolicyRevision(): Promise<void> {
  const policy = selectedCancellationPolicy.value; if (!policy || policy.status !== "active") return;
  let body: BookingCancellationPolicyRevisionInput;
  try {
    const parseObject = (value: string, label: string): Record<string, unknown> => {
      const parsed: unknown = JSON.parse(value);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error(label + " must be a JSON object.");
      return parsed as Record<string, unknown>;
    };
    body = { customerMode: cancellationPolicyCustomerMode.value, publicTerms: cancellationPolicyPublicTerms.value.trim(),
      approvalRules: parseObject(cancellationPolicyApprovalRulesJson.value, "Approval rules"),
      commercialRules: parseObject(cancellationPolicyCommercialRulesJson.value, "Commercial rules"),
      noticeRules: parseObject(cancellationPolicyNoticeRulesJson.value, "Notice rules") };
    if (!body.publicTerms || body.publicTerms.length > 10000) throw new Error(translate("commercialConfiguration.cancelTerms"));
  } catch (error) { pageError.value = error instanceof Error ? error.message : translate("commercialConfiguration.cancelInvalid"); return; }
  const latest = selectedCancellationPolicyLatestRevision.value;
  if (!window.confirm(latest?.state === "draft" ? translate("commercialConfiguration.cancelSaveConfirm") : translate("commercialConfiguration.cancelSuccessorConfirm"))) return;
  clearMessages(); busy.value = true;
  try {
    const result = latest?.state === "draft" ? await api.updateBookingCancellationPolicyDraftRevision(policy.policyId, latest.revisionId, body) : await api.createBookingCancellationPolicyRevision(policy.policyId, body);
    await loadBookingCancellationPolicies(); pageNotice.value = translate("commercialConfiguration.cancelSaved", { revision: result.data.revisionNumber });
  } catch (error) { showError(error); } finally { busy.value = false; }
}

async function publishBookingCancellationPolicyRevision(): Promise<void> {
  const policy = selectedCancellationPolicy.value, revision = selectedCancellationPolicyLatestRevision.value;
  if (!policy || !revision || revision.state !== "draft") return;
  if (!window.confirm(translate("commercialConfiguration.cancelPublishConfirm"))) return;
  clearMessages(); busy.value = true;
  try { const result = await api.publishBookingCancellationPolicyRevision(policy.policyId, revision.revisionId); await loadBookingCancellationPolicies(); pageNotice.value = translate("commercialConfiguration.cancelPublished", { revision: result.data.revisionNumber }); }
  catch (error) { showError(error); } finally { busy.value = false; }
}
return { cancellationPolicies, selectedCancellationPolicyId, cancellationPolicyCreateForm, cancellationPolicyCustomerMode, cancellationPolicyPublicTerms, cancellationPolicyApprovalRulesJson, cancellationPolicyCommercialRulesJson, cancellationPolicyNoticeRulesJson, selectedCancellationPolicy, selectedCancellationPolicyLatestRevision, loadCancellationPolicyEditor, loadBookingCancellationPolicies, openBookingCancellationPolicies, selectBookingCancellationPolicy, createBookingCancellationPolicy, saveBookingCancellationPolicyRevision, publishBookingCancellationPolicyRevision };
}
