import { computed, reactive, ref, type Ref } from "vue";
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes" | "forms" | "settings";
import type { BookingApprovalPolicy, BookingApprovalRule } from "../../api";
interface Dependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  activeTab: Ref<StaffTab>; clearMessages: () => void; showError: (error: unknown) => void; translate: (key: string, params?: Record<string, string | number>) => string;
}
export function useBookingApprovalPolicies({ api, busy, pageError, pageNotice, activeTab, clearMessages, showError, translate }: Dependencies) {
const approvalPolicies = ref<BookingApprovalPolicy[]>([]);
const selectedApprovalPolicyId = ref("");
const approvalPolicyCreateForm = reactive({ code: "", name: "" });
const approvalPolicyRulesJson = ref("[]");
const selectedApprovalPolicy = computed(() =>
  approvalPolicies.value.find((policy) => policy.policyId === selectedApprovalPolicyId.value) ?? null,
);
const selectedApprovalPolicyLatestRevision = computed(() => {
  const policy = selectedApprovalPolicy.value;
  return policy?.revisions.find((revision) => revision.revisionId === policy.latestRevisionId)
    ?? policy?.revisions[0]
    ?? null;
});
async function loadBookingApprovalPolicies(): Promise<void> {
  const result = await api.getBookingApprovalPolicies();
  approvalPolicies.value = result.data;
  if (selectedApprovalPolicyId.value && !result.data.some((policy) => policy.policyId === selectedApprovalPolicyId.value)) {
    selectedApprovalPolicyId.value = "";
  }
  if (!selectedApprovalPolicyId.value && result.data.length) {
    selectedApprovalPolicyId.value = result.data[0]!.policyId;
  }
  const revision = selectedApprovalPolicyLatestRevision.value;
  approvalPolicyRulesJson.value = JSON.stringify(revision?.rules ?? [], null, 2);
}

async function openBookingApprovalPolicies(): Promise<void> {
  activeTab.value = "approvals";
  clearMessages();
  busy.value = true;
  try {
    await loadBookingApprovalPolicies();
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

function selectBookingApprovalPolicy(policyId: string): void {
  selectedApprovalPolicyId.value = policyId;
  const revision = selectedApprovalPolicyLatestRevision.value;
  approvalPolicyRulesJson.value = JSON.stringify(revision?.rules ?? [], null, 2);
}

async function createBookingApprovalPolicy(): Promise<void> {
  const code = approvalPolicyCreateForm.code.trim();
  const name = approvalPolicyCreateForm.name.trim();
  if (code.length < 2 || code.length > 80 || name.length < 1 || name.length > 250) {
    pageError.value = translate("commercialConfiguration.approvalFields");
    return;
  }
  if (!window.confirm(translate("commercialConfiguration.approvalCreateConfirm"))) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.createBookingApprovalPolicy({ code, name });
    approvalPolicyCreateForm.code = "";
    approvalPolicyCreateForm.name = "";
    selectedApprovalPolicyId.value = result.data.policyId;
    await loadBookingApprovalPolicies();
    pageNotice.value = translate("commercialConfiguration.approvalCreated");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function createBookingApprovalPolicyRevision(): Promise<void> {
  const policy = selectedApprovalPolicy.value;
  if (!policy || policy.status !== "active") return;
  let parsed: unknown;
  try {
    parsed = JSON.parse(approvalPolicyRulesJson.value);
    if (!Array.isArray(parsed)) throw new Error(translate("commercialConfiguration.approvalArray"));
    if (parsed.length > 50) throw new Error(translate("commercialConfiguration.approvalLimit"));
    for (const item of parsed) {
      if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error(translate("commercialConfiguration.approvalObject"));
      const rule = item as Record<string, unknown>;
      if (typeof rule.code !== "string" || typeof rule.condition !== "object" || !rule.condition ||
          typeof rule.requiredApprovals !== "number" || typeof rule.permission !== "string" ||
          typeof rule.separationOfDuties !== "boolean") {
        throw new Error(translate("commercialConfiguration.approvalRuleFields"));
      }
    }
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : translate("commercialConfiguration.approvalInvalid");
    return;
  }
  const latest = selectedApprovalPolicyLatestRevision.value;
  if (!window.confirm(
    latest?.state === "draft"
      ? translate("commercialConfiguration.approvalSaveDraftConfirm")
      : translate("commercialConfiguration.approvalSuccessorConfirm"),
  )) return;
  clearMessages();
  busy.value = true;
  try {
    const result = latest?.state === "draft"
      ? await api.updateBookingApprovalPolicyDraftRevision(policy.policyId, latest.revisionId, parsed as BookingApprovalRule[])
      : await api.createBookingApprovalPolicyRevision(policy.policyId, parsed as BookingApprovalRule[]);
    await loadBookingApprovalPolicies();
    pageNotice.value = translate("commercialConfiguration.approvalSaved", { revision: result.data.revisionNumber ?? 0 });
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function publishBookingApprovalPolicyRevision(): Promise<void> {
  const policy = selectedApprovalPolicy.value;
  const revision = selectedApprovalPolicyLatestRevision.value;
  if (!policy || !revision || revision.state !== "draft") return;
  if (!window.confirm(translate("commercialConfiguration.approvalPublishConfirm", { revision: revision.revisionNumber }))) return;
  clearMessages();
  busy.value = true;
  try {
    await api.publishBookingApprovalPolicyRevision(policy.policyId, revision.revisionId);
    await loadBookingApprovalPolicies();
    pageNotice.value = translate("commercialConfiguration.approvalPublished");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}
return { approvalPolicies, selectedApprovalPolicyId, approvalPolicyCreateForm, approvalPolicyRulesJson, selectedApprovalPolicy, selectedApprovalPolicyLatestRevision, loadBookingApprovalPolicies, openBookingApprovalPolicies, selectBookingApprovalPolicy, createBookingApprovalPolicy, createBookingApprovalPolicyRevision, publishBookingApprovalPolicyRevision };
}
