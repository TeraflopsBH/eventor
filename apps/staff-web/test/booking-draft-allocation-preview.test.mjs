import assert from "node:assert/strict";
import test from "node:test";
import { computed, ref } from "vue";
import { useBookingDraft } from "../src/features/booking-drafts/useBookingDraft.ts";

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function createWorkspace(preview) {
  const draft = {
    draftId: "draft-1",
    status: "draft",
    currentRevisionNumber: 1,
    currentRevision: {
      revisionNumber: 1,
      values: {},
      spaceLines: [],
      resourceLines: [],
      requestedStart: null,
      requestedEnd: null,
      timezone: "Europe/Sarajevo",
    },
  };
  const state = {
    busy: ref(false),
    pageError: ref(""),
    pageNotice: ref(""),
    errors: [],
  };
  const workspace = useBookingDraft({
    api: {
      async getBookingDraft() { return { data: draft }; },
      async getBookingDraftAllocationOptions() { return { data: { spaces: [], resources: [] } }; },
      previewBookingDraftAllocationAvailability: preview,
    },
    busy: state.busy,
    pageError: state.pageError,
    pageNotice: state.pageNotice,
    canManageDraftPermission: computed(() => true),
    clearMessages() {
      state.pageError.value = "";
      state.pageNotice.value = "";
    },
    showError(error) { state.errors.push(error); },
    async refreshInquiryDetail() {},
    translate(key) { return key; },
  });
  return { workspace, state };
}

test("discards an allocation preview response after its inputs change", async () => {
  const pending = deferred();
  const { workspace, state } = createWorkspace(() => pending.promise);
  await workspace.open("draft-1", true);

  const request = workspace.previewAvailability();
  assert.equal(workspace.allocationAvailabilityPreviewBusy.value, true);

  workspace.requestedStart.value = "2026-12-01T18:00:00+01:00";
  assert.equal(workspace.allocationAvailabilityPreviewBusy.value, false);

  pending.resolve({ data: { requestId: "stale" } });
  await request;

  assert.equal(workspace.allocationAvailabilityPreview.value, null);
  assert.equal(workspace.allocationAvailabilityPreviewIsCurrent.value, false);
  assert.deepEqual(state.errors, []);
});

test("only the latest overlapping allocation preview can update the workspace", async () => {
  const first = deferred();
  const second = deferred();
  let call = 0;
  const { workspace } = createWorkspace(() => (++call === 1 ? first.promise : second.promise));
  await workspace.open("draft-1", true);

  const firstRequest = workspace.previewAvailability();
  workspace.requestedStart.value = "2026-12-02T18:00:00+01:00";
  const secondRequest = workspace.previewAvailability();

  second.resolve({ data: { requestId: "latest" } });
  await secondRequest;
  assert.equal(workspace.allocationAvailabilityPreview.value.requestId, "latest");
  assert.equal(workspace.allocationAvailabilityPreviewIsCurrent.value, true);
  assert.equal(workspace.allocationAvailabilityPreviewBusy.value, false);

  first.resolve({ data: { requestId: "outdated" } });
  await firstRequest;

  assert.equal(workspace.allocationAvailabilityPreview.value.requestId, "latest");
  assert.equal(workspace.allocationAvailabilityPreviewIsCurrent.value, true);
  assert.equal(workspace.allocationAvailabilityPreviewBusy.value, false);
});
