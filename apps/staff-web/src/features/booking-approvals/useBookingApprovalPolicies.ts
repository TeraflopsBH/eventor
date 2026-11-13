import { computed, reactive, ref, type Ref } from "vue";
type StaffTab = "delivery" | "campaign" | "inquiries" | "approvals" | "prices" | "cancellations" | "taxes";
import type { BookingApprovalPolicy, BookingApprovalRule } from "../../api";
interface Dependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  activeTab: Ref<StaffTab>; clearMessages: () => void; showError: (error: unknown) => void;
}
export function useBookingApprovalPolicies({ api, busy, pageError, pageNotice, activeTab, clearMessages, showError }: Dependencies) {
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
    pageError.value = "Enter a policy code (2–80 characters) and name (1–250 characters).";
    return;
  }
  if (!window.confirm("Create a new organization approval policy? It has no revisions yet. You will create and explicitly publish its first rules revision before it can be used for a new offer.")) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.createBookingApprovalPolicy({ code, name });
    approvalPolicyCreateForm.code = "";
    approvalPolicyCreateForm.name = "";
    selectedApprovalPolicyId.value = result.data.policyId;
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy created. Create and publish its first rules revision before selecting it for a new offer.";
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
    if (!Array.isArray(parsed)) throw new Error("Rules must be a JSON array.");
    if (parsed.length > 50) throw new Error("A policy may contain no more than 50 rules.");
    for (const item of parsed) {
      if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error("Each rule must be a JSON object.");
      const rule = item as Record<string, unknown>;
      if (typeof rule.code !== "string" || typeof rule.condition !== "object" || !rule.condition ||
          typeof rule.requiredApprovals !== "number" || typeof rule.permission !== "string" ||
          typeof rule.separationOfDuties !== "boolean") {
        throw new Error("Each rule needs code, condition, requiredApprovals, permission and separationOfDuties.");
      }
    }
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : "Approval policy rules are invalid JSON.";
    return;
  }
  const latest = selectedApprovalPolicyLatestRevision.value;
  if (!window.confirm(
    latest?.state === "draft"
      ? "Save changes to this exact draft revision? The draft remains unpublished until you explicitly publish it."
      : "Create a new immutable draft revision? Any existing offers keep their already-pinned approval requirements.",
  )) return;
  clearMessages();
  busy.value = true;
  try {
    const result = latest?.state === "draft"
      ? await api.updateBookingApprovalPolicyDraftRevision(policy.policyId, latest.revisionId, parsed as BookingApprovalRule[])
      : await api.createBookingApprovalPolicyRevision(policy.policyId, parsed as BookingApprovalRule[]);
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy revision " + result.data.revisionNumber + " saved as a draft. Publish it explicitly when ready.";
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
  if (!window.confirm("Publish approval policy revision " + revision.revisionNumber + "? Published revisions are immutable. Existing offer revisions retain their original approval-rule snapshot.")) return;
  clearMessages();
  busy.value = true;
  try {
    await api.publishBookingApprovalPolicyRevision(policy.policyId, revision.revisionId);
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy revision published. New offer revisions may now pin this policy revision.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}
return { approvalPolicies, selectedApprovalPolicyId, approvalPolicyCreateForm, approvalPolicyRulesJson, selectedApprovalPolicy, selectedApprovalPolicyLatestRevision, loadBookingApprovalPolicies, openBookingApprovalPolicies, selectBookingApprovalPolicy, createBookingApprovalPolicy, createBookingApprovalPolicyRevision, publishBookingApprovalPolicyRevision };
}
