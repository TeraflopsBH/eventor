import assert from "node:assert/strict";
import { createHash, createHmac } from "node:crypto";
import test from "node:test";
import type { Pool, PoolClient } from "pg";
import { buildApi, type StaffPrincipal } from "../src/server.js";
import { encryptDeliveryCredentialBundle } from "../src/delivery-credentials-crypto.js";
import { decryptContactValue, encryptContactValue } from "../src/contact-crypto.js";
import type { SmtpTransportFactory } from "../src/smtp-transport.js";

const resendWebhookSigningSecret = `whsec_${Buffer.from("eventor-resend-webhook-test-secret-32-bytes").toString("base64")}`;

const principal: StaffPrincipal = {
  userId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  organizationId: "22222222-2222-4222-8222-222222222222",
  membershipId: "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb",
};
const inquiryTestContactKey = Buffer.alloc(32, 10);
const inquiryNameCiphertext = encryptContactValue(
  "Jane Example", inquiryTestContactKey,
  { organizationId: principal.organizationId, contactKind: "other" },
).toString("base64");
const inquiryEmailCiphertext = encryptContactValue(
  "jane@example.test", inquiryTestContactKey,
  { organizationId: principal.organizationId, contactKind: "email" },
).toString("base64");
const inquiryPhoneCiphertext = encryptContactValue(
  "+38761123456", inquiryTestContactKey,
  { organizationId: principal.organizationId, contactKind: "phone" },
).toString("base64");
const inquiryValuesCiphertext = encryptContactValue(
  JSON.stringify({
    requested: { timezone: "Europe/Sarajevo", spaceCodes: ["MAIN-HALL"] },
    answers: { event_date: "2027-01-18", event_name: "Community Lecture", estimated_guests: 120 },
  }),
  inquiryTestContactKey,
  { organizationId: principal.organizationId, contactKind: "other" },
).toString("base64");
const bookingDraftValues = {
  requested: { timezone: "Europe/Sarajevo", spaceCodes: ["MAIN-HALL"] },
  answers: { event_date: "2027-01-18", event_name: "Community Lecture", estimated_guests: 120 },
};
const bookingDraftValuesCiphertext = encryptContactValue(
  JSON.stringify(bookingDraftValues),
  inquiryTestContactKey,
  { organizationId: principal.organizationId, contactKind: "other" },
).toString("base64");

interface StoredIdempotency {
  requestHash: string;
  responseStatus: number | null;
  responseBody: Record<string, unknown> | null;
}

function makePool() {
  const idempotency = new Map<string, StoredIdempotency>();
  const commandCalls: Array<{ sql: string; values: unknown[] }> = [];
  let reservationCalls = 0;
  let changeCalls = 0;
  let campaignReviewCalls = 0;
  let campaignListCalls = 0;
  let campaignProgressCalls = 0;
  let campaignDeliveryListCalls = 0;
  let campaignConfirmCalls = 0;
  let deliveryConfigCalls = 0;
  let deliveryTestBegins = 0;
  let deliveryTestCompletions = 0;
  let campaignQueueCalls = 0;
  let campaignCancelCalls = 0;
  let deliveryReconcileCalls = 0;
  let deliveryRetryCalls = 0;
  let resendWebhookPrepareCalls = 0;
  let resendWebhookActivateCalls = 0;
  let resendWebhookResolveCalls = 0;
  let resendWebhookRecordCalls = 0;
  let publicBookingFormCalls = 0;
  let publicBookingInquiryCalls = 0;
  let bookingInquiryListCalls = 0;
  let bookingInquiryGetCalls = 0;
  let bookingInquiryCapabilitiesCalls = 0;
  let bookingInquiryAssigneeRosterCalls = 0;
  let bookingInquiryAssignCalls = 0;
  let bookingInquiryStatusCalls = 0;
  let bookingInquiryAnnotationCalls = 0;
  let bookingInquiryConversionCalls = 0;
  let bookingDraftGetCalls = 0;
  let bookingDraftAllocationPreviewCalls = 0;
  let bookingDraftRevisionCalls = 0;
  let bookingOfferPrepareCalls = 0;
  let bookingOfferSuccessorCalls = 0;
  let bookingOfferGetCalls = 0;
  let bookingOfferIssueCalls = 0;
  let bookingOfferEmailQueueCalls = 0;
  let bookingOfferEmailListCalls = 0;
  let bookingOfferEmailReconcileCalls = 0;
  let bookingOfferEmailRetryCalls = 0;
  let customerOfferDecisionCalls = 0;
  let publicBookingOfferViewCalls = 0;
  let bookingOfferApprovalDecisionCalls = 0;
  let bookingOfferApprovalStatusCalls = 0;
  let bookingConfirmationCalls = 0;
  let bookingApprovalPolicyListCalls = 0;
  let bookingApprovalPolicyCreateCalls = 0;
  let bookingApprovalPolicyRevisionCalls = 0;
  let bookingApprovalPolicyRevisionUpdateCalls = 0;
  let bookingApprovalPolicyPublishCalls = 0;
  const customerOfferDecisionReplays = new Map<string, { requestHash: string; response: Record<string, unknown> }>();
  const deliveryTests = new Map<string, string>();

  const client = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, " ").trim();
      if (normalized === "BEGIN" || normalized === "COMMIT" || normalized === "ROLLBACK") {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.startsWith("SELECT set_config(")) return { rows: [], rowCount: 1 };
      if (normalized.includes("eogp.get_published_public_booking_form(") || normalized.includes("eogp.get_public_booking_form_revision(")) {
        publicBookingFormCalls += 1;
        commandCalls.push({ sql: normalized, values });
        const isExactRevisionLookup = normalized.includes("eogp.get_public_booking_form_revision(");
        const formExists = values[1] === "venue-rental";
        const revisionMatches = !isExactRevisionLookup ||
          values[2] === "12121212-1212-4121-8121-121212121212";
        const result = formExists && revisionMatches ? {
          organizationId: "11111111-1111-4111-8111-111111111111",
          organizationSlug: values[0],
          organizationName: "GHB",
          defaultLocale: "en",
          defaultTimezone: "Europe/Sarajevo",
          formCode: values[1],
          formName: "Venue rental inquiry",
          formRevisionId: "12121212-1212-4121-8121-121212121212",
          revisionNumber: 3,
          locale: "bs-BA",
          fieldSchema: {
            fields: [
            { code: "event_date", type: "date", required: true },
            { code: "event_name", type: "text", required: true, minLength: 2, maxLength: 120 },
            { code: "estimated_guests", type: "number", required: true, integer: true, min: 1, max: 5000 },
            ],
            contentTranslations: {
              "bs-BA": {
                formName: "Upit za iznajmljivanje prostora",
                fields: { event_date: { label: "Datum događaja" } },
              },
            },
          },
          publishedAt: "2026-11-11T12:00:00.000Z",
        } : null;
        return { rows: [{ result }], rowCount: 1 };
      }
      if (normalized.includes("eogp.submit_public_booking_inquiry_with_locale(")) {
        publicBookingInquiryCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          inquiryId: "13131313-1313-4131-8131-131313131313",
          publicReference: "INQ-AB12CD34EF56AB78",
          status: "received",
          replayed: false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_inquiry_capabilities(")) {
        bookingInquiryCapabilitiesCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          canAssign: true, canManage: true, canAnnotate: true, canConvert: true,
          canReadDraft: true, canManageDraft: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.preview_booking_draft_allocation_availability(")) {
        bookingDraftAllocationPreviewCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          spaces: [{
            index: 1,
            venueSpaceId: "44444444-4444-4444-8444-444444444444",
            available: false,
            reason: "space_conflict",
            conflicts: [{
              kind: "confirmed_booking",
              status: "confirmed",
              startsAt: "2027-01-18T10:00:00.000Z",
              endsAt: "2027-01-18T11:00:00.000Z",
            }],
          }],
          resources: [{
            index: 1,
            resourceTypeId: "55555555-5555-4555-8555-555555555555",
            requestedQuantity: 10,
            totalRequestedQuantity: 10,
            availableQuantity: 4,
            checked: true,
            available: false,
            reason: "resource_capacity_conflict",
          }],
          resourceIntervalChecked: true,
          spaceAlternatives: [{
            index: 1,
            alternatives: [{
              venueSpaceId: "66666666-6666-4666-8666-666666666666",
              venueId: "77777777-7777-4777-8777-777777777777",
              venueName: "Main Venue",
              code: "ROOM-B",
              name: "Room B",
              capacity: 120,
            }],
          }],
          resourcePools: [{
            index: 1,
            pools: [{
              resourcePoolId: "88888888-8888-4888-8888-888888888888",
              code: "CHAIRS-A",
              name: "Chair pool A",
              venueName: "Main Venue",
              capacity: 20,
              availableQuantity: 4,
            }],
          }],
          advisoryOnly: true,
          checkedAt: "2026-11-12T12:00:00.000Z",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_draft(")) {
        bookingDraftGetCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          draftId: "15151515-1515-4151-8151-151515151515",
          sourceInquiryId: "14141414-1414-4141-8141-141414141414",
          status: "draft",
          currentRevisionNumber: 1,
          createdAt: "2026-11-12T10:00:00.000Z",
          updatedAt: "2026-11-12T10:00:00.000Z",
          currentRevision: {
            revisionId: "16161616-1616-4161-8161-161616161616",
            revisionNumber: 1,
            sourceFormRevisionId: "12121212-1212-4121-8121-121212121212",
            fieldSchema: { fields: [
              { code: "event_date", type: "date", required: true },
              { code: "event_name", type: "text", required: true, minLength: 2, maxLength: 120 },
              { code: "estimated_guests", type: "number", required: true, integer: true, min: 1, max: 5000 },
            ] },
            valuesSnapshot: {
              schemaVersion: 1,
              encryption: "ECP1",
              contactKind: "other",
              ciphertextBase64: bookingDraftValuesCiphertext,
            },
            requestedStart: "2027-01-18T09:00:00.000Z",
            requestedEnd: "2027-01-18T12:00:00.000Z",
            timezone: "Europe/Sarajevo",
            changeReason: "converted_from_public_inquiry",
            createdAt: "2026-11-12T10:00:00.000Z",
            createdByMembershipId: principal.membershipId,
            spaceLines: [],
            resourceLines: [],
          },
          revisionHistory: [{
            revisionId: "16161616-1616-4161-8161-161616161616",
            revisionNumber: 1,
            changeReason: "converted_from_public_inquiry",
            createdAt: "2026-11-12T10:00:00.000Z",
            createdByMembershipId: principal.membershipId,
            createdByDisplayName: "Jane Operator",
          }],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.create_booking_draft_revision(")) {
        bookingDraftRevisionCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          draftId: values[1],
          revisionId: "17171717-1717-4171-8171-171717171717",
          revisionNumber: 2,
          previousRevisionNumber: 1,
          status: "draft",
          changed: true,
        } }], rowCount: 1 };
      }

      if (normalized.includes("eogp.confirm_booking_from_offer(")) {
        bookingConfirmationCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          bookingId: "24242424-2424-4242-8242-242424242424",
          bookingCode: "BKG-ABCDEF123456",
          status: "confirmed",
          offerId: "18181818-1818-4181-8181-181818181818",
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
          draftRevisionId: values[1],
          confirmedAt: "2026-11-12T13:00:00.000Z",
          spaceReservationsConfirmed: 1,
          resourceReservationsConfirmed: 2,
          replayed: false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.decide_booking_offer_approval(")) {
        bookingOfferApprovalDecisionCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          offerId: values[1],
          offerRevisionId: values[2],
          ruleCode: values[4],
          decision: values[5],
          approvedCount: values[5] === "approved" ? 1 : 0,
          requiredApprovals: 2,
          satisfied: false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_offer_approval_status(")) {
        bookingOfferApprovalStatusCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          offerId: values[1],
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
          requirements: [{
            ruleCode: "high_value",
            condition: { kind: "total_at_least", amount: 1000, currency: "BAM" },
            requiredApprovals: 2,
            separationOfDuties: true,
            approvedCount: 1,
            blocked: false,
            decisions: [{ membershipId: "cccccccc-2222-4222-8222-cccccccccccc", decision: "approved", reason: "Reviewed amount.", decidedAt: "2026-11-12T12:30:00.000Z" }],
          }],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_public_booking_offer_with_capability(")) {
        publicBookingOfferViewCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          offerId: values[0],
          status: "issued",
          revisionNumber: 1,
          currency: "BAM",
          subtotal: 250,
          taxAmount: 25,
          totalAmount: 275,
          validUntil: "2026-12-01T12:00:00.000Z",
          terms: {
            requestedStart: "2027-01-18T09:00:00.000Z",
            requestedEnd: "2027-01-18T12:00:00.000Z",
            timezone: "Europe/Sarajevo",
            taxBasis: "exclusive",
            lineItems: [{ label: "Hall rental", unit: "hour", quantity: 3, unitAmount: 83.33, lineTotal: 250 }],
            adjustments: [],
            spaces: [{ code: "MAIN-HALL", name: "Main Hall", blockKind: "event_use" }],
            resources: [{ label: "Chairs", requestedQuantity: 120 }],
            cancellationTerms: "Cancellation terms as published.",
          },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.resolve_booking_offer_capability(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          organizationId: principal.organizationId,
          offerId: values[0],
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.decide_booking_offer_with_capability(")) {
        customerOfferDecisionCalls += 1;
        commandCalls.push({ sql: normalized, values });
        const replayKey = String(values[1]) + "|" + String(values[3]);
        const stored = customerOfferDecisionReplays.get(replayKey);
        if (stored) {
          if (stored.requestHash !== String(values[4])) {
            throw Object.assign(new Error("idempotency conflict"), { code: "55000" });
          }
          return { rows: [{ result: { ...stored.response, replayed: true } }], rowCount: 1 };
        }
        const response = {
          offerId: values[0],
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
          decision: values[2],
          decidedAt: "2026-11-12T12:00:00.000Z",
          replayed: false,
        };
        customerOfferDecisionReplays.set(replayKey, { requestHash: String(values[4]), response });
        return { rows: [{ result: response }], rowCount: 1 };
      }
      if (normalized.includes("eogp.save_booking_offer_revision(")) {
        commandCalls.push({ sql: normalized, values });
        if (values[3] !== null) bookingOfferSuccessorCalls += 1;
        else bookingOfferPrepareCalls += 1;
        return { rows: [{ result: {
          offerId: "18181818-1818-4181-8181-181818181818",
          offerRevisionId: values[3] !== null ? "19191919-1919-4191-8191-191919191919" : "18181818-1818-4181-8181-181818181819",
          draftRevisionId: values[1],
          revisionNumber: values[3] !== null ? 2 : 1,
          state: "draft",
          currency: values[7],
          taxBasis: values[8],
          subtotal: 250,
          taxAmount: values[12],
          totalAmount: 275,
          validUntil: values[9],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_offer(")) {
        bookingOfferGetCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          offerId: values[1],
          status: "prepared",
          currentRevision: {
            offerRevisionId: "18181818-1818-4181-8181-181818181819",
            revisionNumber: 1,
            state: "draft",
            currency: "BAM",
            subtotal: 250,
            taxAmount: 25,
            totalAmount: 275,
            terms: { lineItems: [{ itemCode: "HALL-RENTAL", label: "Hall rental", quantity: 1, unitAmount: 250, lineTotal: 250 }] },
          },
          revisionHistory: [],
          decisionHistory: [],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.list_booking_offer_email_deliveries(")) {
        bookingOfferEmailListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            deliveryId: "21212121-2121-4121-8121-212121212121",
            offerRevisionId: "18181818-1818-4181-8181-181818181819",
            status: "uncertain", attemptCount: 1, manualRetryCount: 0,
            nextAttemptAt: "2026-11-12T06:00:00.000Z",
            createdAt: "2026-11-12T05:00:00.000Z", updatedAt: "2026-11-12T06:00:00.000Z",
            sentAt: null, lastFailureCode: "SMTP_UNKNOWN",
            lastOperatorResolution: null, lastOperatorAt: null,
            canReconcile: true, canRetry: false,
          }],
          page: { limit: values[4], offset: values[5], total: 1 },
          counts: { uncertain: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.reconcile_booking_offer_email_delivery(")) {
        bookingOfferEmailReconcileCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { deliveryId: values[1], previousStatus: "uncertain", status: "failed", canRetry: true } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.retry_booking_offer_email_delivery(")) {
        bookingOfferEmailRetryCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { deliveryId: values[1], status: "queued", manualRetryCount: 1 } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.queue_booking_offer_email_delivery(")) {
        bookingOfferEmailQueueCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          deliveryId: "21212121-2121-4121-8121-212121212121",
          offerId: values[1],
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
          status: "queued",
          created: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.issue_booking_offer(")) {
        bookingOfferIssueCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          offerId: values[1],
          offerRevisionId: "18181818-1818-4181-8181-181818181819",
          revisionNumber: 1,
          state: "issued",
          validUntil: "2026-12-01T12:00:00.000Z",
          capabilityId: "20202020-2020-4020-8020-202020202020",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.convert_booking_inquiry_to_draft(")) {
        bookingInquiryConversionCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          inquiryId: values[1],
          draftId: "15151515-1515-4151-8151-151515151515",
          revisionId: "16161616-1616-4161-8161-161616161616",
          revisionNumber: 1,
          status: "converted",
          changed: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.list_booking_inquiry_assignees(")) {
        bookingInquiryAssigneeRosterCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { items: [
          { membershipId: principal.membershipId, displayName: "Jane Operator" },
          { membershipId: "cccccccc-2222-4222-8222-cccccccccccc", displayName: "Alex Assignee" },
        ] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.list_booking_inquiries(")) {
        bookingInquiryListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            inquiryId: "14141414-1414-4141-8141-141414141414",
            publicReference: "INQ-1234567890ABCDEF",
            status: "received",
            formRevisionId: "12121212-1212-4121-8121-121212121212",
            requesterNameCiphertextBase64: inquiryNameCiphertext,
            requestedStart: "2027-01-18T09:00:00.000Z",
            requestedEnd: "2027-01-18T12:00:00.000Z",
            requestedTimezone: "Europe/Sarajevo",
            assignedToMembershipId: null,
            submittedAt: "2026-11-11T12:00:00.000Z",
            updatedAt: "2026-11-11T12:00:00.000Z",
          }],
          page: { limit: values[4], offset: values[5], total: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_inquiry(")) {
        bookingInquiryGetCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          inquiryId: "14141414-1414-4141-8141-141414141414",
          publicReference: "INQ-1234567890ABCDEF",
          status: "under_review",
          formRevisionId: "12121212-1212-4121-8121-121212121212",
          fieldSchema: { fields: [
            { code: "event_date", type: "date", required: true },
            { code: "event_name", type: "text", required: true, minLength: 2, maxLength: 120 },
            { code: "estimated_guests", type: "number", required: true, integer: true, min: 1, max: 5000 },
          ] },
          requesterNameCiphertextBase64: inquiryNameCiphertext,
          requesterEmailCiphertextBase64: inquiryEmailCiphertext,
          requesterPhoneCiphertextBase64: inquiryPhoneCiphertext,
          submittedValuesCiphertextBase64: inquiryValuesCiphertext,
          requestedStart: "2027-01-18T09:00:00.000Z",
          requestedEnd: "2027-01-18T12:00:00.000Z",
          requestedTimezone: "Europe/Sarajevo",
          assignedToMembershipId: "cccccccc-2222-4222-8222-cccccccccccc",
          submittedAt: "2026-11-11T12:00:00.000Z",
          updatedAt: "2026-11-11T12:15:00.000Z",
          bookingDraft: bookingInquiryConversionCalls > 0 ? {
            draftId: "15151515-1515-4151-8151-151515151515",
            status: "draft",
            currentRevisionNumber: 1,
          } : null,
          annotations: [{
            annotationId: "15151515-1515-4151-8151-151515151515",
            annotation: "Call to confirm setup access.",
            visibility: "internal",
            actorMembershipId: principal.membershipId,
            createdAt: "2026-11-11T12:10:00.000Z",
          }],
          statusHistory: [{
            previousStatus: "received", newStatus: "under_review", reason: "Assigned for review",
            actorKind: "membership", actorMembershipId: principal.membershipId,
            occurredAt: "2026-11-11T12:15:00.000Z",
          }],
          assignmentHistory: [{
            previousAssigneeMembershipId: null,
            newAssigneeMembershipId: "cccccccc-2222-4222-8222-cccccccccccc",
            actorMembershipId: principal.membershipId,
            occurredAt: "2026-11-11T12:05:00.000Z",
          }],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.assign_booking_inquiry(")) {
        bookingInquiryAssignCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          inquiryId: values[1],
          assignedToMembershipId: values[3],
          changed: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.change_booking_inquiry_status(")) {
        bookingInquiryStatusCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          inquiryId: values[1],
          previousStatus: "received",
          status: values[3],
          changed: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.add_booking_inquiry_annotation(")) {
        bookingInquiryAnnotationCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          annotationId: "16161616-1616-4161-8161-161616161616",
          inquiryId: values[1],
          visibility: "internal",
          createdAt: "2026-11-11T12:20:00.000Z",
        } }], rowCount: 1 };
      }
      if (normalized.startsWith("DELETE FROM eogp.idempotency_records")) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.startsWith("SELECT request_sha256")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        const found = idempotency.get(key);
        return {
          rows: found ? [{
            request_sha256: found.requestHash,
            response_status: found.responseStatus,
            response_body: found.responseBody,
          }] : [],
          rowCount: found ? 1 : 0,
        };
      }
      if (normalized.startsWith("INSERT INTO eogp.idempotency_records")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        if (idempotency.has(key)) return { rows: [], rowCount: 0 };
        idempotency.set(key, {
          requestHash: String(values[4]),
          responseStatus: null,
          responseBody: null,
        });
        return { rows: [{ id: "idempotency-row" }], rowCount: 1 };
      }
      if (normalized.startsWith("UPDATE eogp.idempotency_records")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        const found = idempotency.get(key);
        if (found) {
          found.responseStatus = 201;
          found.responseBody = JSON.parse(String(values[5])) as Record<string, unknown>;
        }
        return { rows: [], rowCount: found ? 1 : 0 };
      }
      if (normalized.includes("eogp.list_event_notification_campaigns(")) {
        campaignListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            campaignId: "94900000-0000-4000-8000-000000000001",
            eventId: "94000000-0000-4000-8000-000000000001",
            purpose: "event_cancellation", audienceKind: "all_previously_invited",
            status: "queued", recipientCount: 2, actualRecipientCount: 2,
            createdAt: "2026-11-11T09:00:00.000Z", confirmedAt: null,
            queuedAt: "2026-11-11T09:01:00.000Z", deliveryStartedAt: null,
            deliveryCompletedAt: null,
          }],
          page: { limit: values[3], offset: values[4], total: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_event_notification_campaign_progress(")) {
        campaignProgressCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], eventId: "94000000-0000-4000-8000-000000000001",
          status: "sending", purpose: "event_cancellation", recipientCount: 2,
          attemptCount: 3,
          deliveryCounts: { queued: 1, sending: 0, sent: 1, failed: 0, uncertain: 0, suppressed: 0 },
          createdAt: "2026-11-11T09:00:00.000Z", confirmedAt: null,
          queuedAt: "2026-11-11T09:01:00.000Z", deliveryStartedAt: "2026-11-11T09:02:00.000Z",
          deliveryCompletedAt: null,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.list_event_notification_campaign_deliveries(")) {
        campaignDeliveryListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            attemptId: "95000000-0000-4000-8000-000000000001",
            recipientReference: "95100000-0000-4000-8000-000000000001",
            channel: "email", attemptNumber: 1, status: "failed",
            failureCode: "SMTP_4XX", provider: "smtp",
            queuedForAt: "2026-11-11T09:01:00.000Z", sendingAt: "2026-11-11T09:02:00.000Z",
            completedAt: "2026-11-11T09:03:00.000Z", retryScheduled: true,
          }],
          page: { limit: values[4], offset: values[5], total: 1 },
          counts: { failed: 1, queued: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_event_notification_campaign_review(")) {
        campaignReviewCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "previewed", recipientCount: 2,
          actualRecipientCount: 2, recipients: [{ participationId: "p1", channel: "email" }],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.confirm_event_notification_campaign(")) {
        campaignConfirmCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "confirmed", recipientCount: 2,
          deliveryQueued: false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.begin_organization_email_delivery_test(")) {
        deliveryTestBegins += 1;
        const idempotencyHash = String(values[2]);
        const existing = deliveryTests.get(idempotencyHash);
        if (existing) {
          return { rows: [{ result: {
            requestId: existing, status: "succeeded", created: false,
            configRevisionId: "dddddddd-4444-4444-8444-dddddddddddd",
          } }], rowCount: 1 };
        }
        const requestId = "eeeeeeee-5555-4555-8555-eeeeeeeeeeee";
        deliveryTests.set(idempotencyHash, requestId);
        return { rows: [{ result: {
          requestId, status: "pending", created: true,
          configRevisionId: "dddddddd-4444-4444-8444-dddddddddddd",
          settings: {
            host: "smtp.example.test", port: 587, transportSecurity: "starttls",
            authMode: "none", senderEmail: "events@example.test",
            senderName: "Eventor", connectionTimeoutMs: 15000,
          },
          credentialsCiphertextBase64: null,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.complete_organization_email_delivery_test(")) {
        deliveryTestCompletions += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          requestId: values[2], status: values[3] ? "succeeded" : "failed",
          deliveryEnabled: Boolean(values[3]),
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.queue_event_notification_campaign(")) {
        campaignQueueCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "queued",
          emailRecipientCount: 2, smsSuppressedCount: 1,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.cancel_queued_event_notification_campaign(")) {
        campaignCancelCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "cancelled", suppressedAttempts: 2,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.reconcile_notification_delivery_attempt(")) {
        deliveryReconcileCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { attemptId: values[1], previousStatus: "uncertain", status: "sent", campaignStatus: "partial" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.retry_failed_notification_delivery_attempt(")) {
        deliveryRetryCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { attemptId: "95200000-0000-4000-8000-000000000001", previousAttemptId: values[1], attemptNumber: 2, status: "queued" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_organization_resend_webhook_configuration(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: "95300000-0000-4000-8000-000000000001", configured: true, updatedAt: "2026-11-11T12:00:00.000Z" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.prepare_organization_resend_webhook_endpoint(")) {
        resendWebhookPrepareCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: values[2], enabled: false } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.activate_organization_resend_webhook_endpoint(")) {
        resendWebhookActivateCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: values[2], enabled: true, updatedAt: "2026-11-11T12:00:00.000Z" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.resolve_organization_resend_webhook_endpoint(")) {
        resendWebhookResolveCalls += 1;
        const ciphertext = encryptDeliveryCredentialBundle(
          { signingSecret: resendWebhookSigningSecret },
          Buffer.alloc(32, 9),
          { organizationId: principal.organizationId, channel: "email" },
        );
        return { rows: [{ result: {
          organizationId: principal.organizationId,
          signingSecretCiphertextBase64: ciphertext.toString("base64"),
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.record_verified_resend_delivery_webhook(")) {
        resendWebhookRecordCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { accepted: true, duplicate: false, attemptId: "95000000-0000-4000-8000-000000000001", status: values[4] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_approval_policies(")) {
        bookingApprovalPolicyListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: [{
          policyId: "27272727-2727-4727-8727-272727272727",
          code: "venue_bookings",
          name: "Venue booking approvals",
          status: "active",
          latestRevisionId: "28282828-2828-4828-8828-282828282828",
          revisions: [{
            revisionId: "28282828-2828-4828-8828-282828282828",
            revisionNumber: 1,
            state: "published",
            rules: [],
            publishedAt: "2026-11-12T12:00:00.000Z",
            createdAt: "2026-11-12T11:00:00.000Z",
          }],
        }] }], rowCount: 1 };
      }
      if (normalized.includes("eogp.create_booking_approval_policy(")) {
        bookingApprovalPolicyCreateCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          policyId: "27272727-2727-4727-8727-272727272727",
          state: "active",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.create_booking_approval_policy_revision(")) {
        bookingApprovalPolicyRevisionCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          policyId: values[1],
          revisionId: "28282828-2828-4828-8828-282828282828",
          revisionNumber: 1,
          state: "draft",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.update_booking_approval_policy_draft_revision(")) {
        bookingApprovalPolicyRevisionUpdateCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          policyId: values[1],
          revisionId: values[2],
          revisionNumber: 1,
          state: "draft",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.publish_booking_approval_policy_revision(")) {
        bookingApprovalPolicyPublishCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          policyId: values[1],
          revisionId: values[2],
          revisionNumber: 1,
          state: "published",
          publishedAt: "2026-11-12T12:00:00.000Z",
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_organization_locale_settings(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { defaultLocale: "bs-BA", canManage: true } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.set_organization_default_locale(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { defaultLocale: values[2] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_organization_email_delivery_config(")) {
        return { rows: [{ result: {
          channel: "email", provider: "smtp", revision: 2,
          settings: { host: "smtp.example.test", port: 587, transportSecurity: "starttls", authMode: "password" },
          credentialsConfigured: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.set_organization_email_delivery_config(")) {
        deliveryConfigCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          channel: "email", provider: "smtp", revision: 3,
          settings: JSON.parse(String(values[2])),
          credentialsConfigured: Boolean(values[4]) || Boolean(values[5]) === false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.release_booking_reservations(")) {
        reservationCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ released_count: "2" }], rowCount: 1 };
      }
      if (normalized.includes("eogp.submit_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return {
          rows: [{
            result: {
              changeRequestId: "91500000-0000-4000-8000-000000000001",
              eventId: values[1],
              status: "submitted",
            },
          }],
          rowCount: 1,
        };
      }
      if (normalized.includes("eogp.decide_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { status: values[3] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.execute_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { status: "cancelled", notificationState: "queued_for_dispatch" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_booking_forms(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: [{ formId: "31313131-3131-4131-8131-313131313131", formCode: "venue-rental", status: "active", revisions: [] }] }], rowCount: 1 };
      }
      if (normalized.includes("eogp.create_booking_form(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { formId: "31313131-3131-4131-8131-313131313131", revisionId: "32323232-3232-4232-8232-323232323232", revisionNumber: 1, state: "draft" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.create_booking_form_revision(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { formId: values[1], revisionId: "33333333-3333-4333-8333-333333333333", revisionNumber: 2, state: "draft" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.save_booking_form_draft(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { formId: values[1], revisionId: values[2], revisionNumber: 2, state: "draft" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.publish_booking_form_revision(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { formId: values[1], revisionId: values[2], revisionNumber: 2, state: "published", publishedAt: "2026-11-12T12:00:00.000Z" } }], rowCount: 1 };
      }
      throw new Error("Unexpected SQL in route test: " + normalized);
    },
    release() { /* no-op for the test pool */ },
  };

  const pool = {
    async connect() {
      return client as unknown as PoolClient;
    },
  } as unknown as Pool;

  return {
    pool,
    commandCalls,
    get reservationCalls() { return reservationCalls; },
    get changeCalls() { return changeCalls; },
    get campaignReviewCalls() { return campaignReviewCalls; },
    get campaignListCalls() { return campaignListCalls; },
    get campaignProgressCalls() { return campaignProgressCalls; },
    get campaignDeliveryListCalls() { return campaignDeliveryListCalls; },
    get campaignConfirmCalls() { return campaignConfirmCalls; },
    get deliveryConfigCalls() { return deliveryConfigCalls; },
    get deliveryTestBegins() { return deliveryTestBegins; },
    get deliveryTestCompletions() { return deliveryTestCompletions; },
    get campaignQueueCalls() { return campaignQueueCalls; },
    get campaignCancelCalls() { return campaignCancelCalls; },
    get deliveryReconcileCalls() { return deliveryReconcileCalls; },
    get deliveryRetryCalls() { return deliveryRetryCalls; },
    get resendWebhookPrepareCalls() { return resendWebhookPrepareCalls; },
    get resendWebhookActivateCalls() { return resendWebhookActivateCalls; },
    get resendWebhookResolveCalls() { return resendWebhookResolveCalls; },
    get resendWebhookRecordCalls() { return resendWebhookRecordCalls; },
    get publicBookingFormCalls() { return publicBookingFormCalls; },
    get publicBookingInquiryCalls() { return publicBookingInquiryCalls; },
    get bookingInquiryListCalls() { return bookingInquiryListCalls; },
    get bookingInquiryGetCalls() { return bookingInquiryGetCalls; },
    get bookingInquiryCapabilitiesCalls() { return bookingInquiryCapabilitiesCalls; },
    get bookingInquiryAssigneeRosterCalls() { return bookingInquiryAssigneeRosterCalls; },
    get bookingInquiryAssignCalls() { return bookingInquiryAssignCalls; },
    get bookingInquiryStatusCalls() { return bookingInquiryStatusCalls; },
    get bookingInquiryAnnotationCalls() { return bookingInquiryAnnotationCalls; },
    get bookingInquiryConversionCalls() { return bookingInquiryConversionCalls; },
    get bookingDraftGetCalls() { return bookingDraftGetCalls; },
    get bookingDraftAllocationPreviewCalls() { return bookingDraftAllocationPreviewCalls; },
    get bookingDraftRevisionCalls() { return bookingDraftRevisionCalls; },
    get bookingOfferPrepareCalls() { return bookingOfferPrepareCalls; },
    get bookingOfferSuccessorCalls() { return bookingOfferSuccessorCalls; },
    get bookingOfferGetCalls() { return bookingOfferGetCalls; },
    get bookingOfferIssueCalls() { return bookingOfferIssueCalls; },
    get bookingOfferEmailQueueCalls() { return bookingOfferEmailQueueCalls; },
    get bookingOfferEmailListCalls() { return bookingOfferEmailListCalls; },
    get bookingOfferEmailReconcileCalls() { return bookingOfferEmailReconcileCalls; },
    get bookingOfferEmailRetryCalls() { return bookingOfferEmailRetryCalls; },
    get customerOfferDecisionCalls() { return customerOfferDecisionCalls; },
    get publicBookingOfferViewCalls() { return publicBookingOfferViewCalls; },
    get bookingOfferApprovalDecisionCalls() { return bookingOfferApprovalDecisionCalls; },
    get bookingOfferApprovalStatusCalls() { return bookingOfferApprovalStatusCalls; },
    get bookingConfirmationCalls() { return bookingConfirmationCalls; },
    get bookingApprovalPolicyListCalls() { return bookingApprovalPolicyListCalls; },
    get bookingApprovalPolicyCreateCalls() { return bookingApprovalPolicyCreateCalls; },
    get bookingApprovalPolicyRevisionCalls() { return bookingApprovalPolicyRevisionCalls; },
    get bookingApprovalPolicyRevisionUpdateCalls() { return bookingApprovalPolicyRevisionUpdateCalls; },
    get bookingApprovalPolicyPublishCalls() { return bookingApprovalPolicyPublishCalls; },
  };
}

function makeApi(
  pool: Pool,
  options: {
    authenticated?: boolean;
    originValid?: boolean;
    encryptionKey?: Buffer;
    loginOriginValid?: boolean;
    withSessionCallbacks?: boolean;
    smtpTransportFactory?: SmtpTransportFactory;
    publicApiBaseUrl?: string;
    contactEncryptionKey?: Buffer;
    bookingCapabilityKey?: Buffer;
    publicInquiryFingerprintKey?: Buffer;
  } = {},
) {
  return buildApi({
    pool,
    authenticateStaff: async () => options.authenticated === false ? null : principal,
    verifyMutationOrigin: async () => options.originValid !== false,
    verifyLoginOrigin: () => options.loginOriginValid !== false,
    ...(options.withSessionCallbacks ? {
      createStaffSession: async () => ({
        principal,
        sessionToken: "S".repeat(43),
        csrfToken: "C".repeat(43),
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      }),
      revokeStaffSession: async () => undefined,
      getCurrentPrincipal: async () => ({ ...principal, userLocale: null, organizationDefaultLocale: "bs-BA", memberships: [] }),
      updateUserLocale: async () => undefined,
    } : {}),
    privateFieldEncryptionKey: options.encryptionKey ?? Buffer.alloc(32, 7),
    contactEncryptionKey: options.contactEncryptionKey ?? Buffer.alloc(32, 10),
    bookingCapabilityKey: options.bookingCapabilityKey ?? Buffer.alloc(32, 12),
    publicInquiryFingerprintKey: options.publicInquiryFingerprintKey ?? Buffer.alloc(32, 11),
    deliveryCredentialsEncryptionKey: Buffer.alloc(32, 9),
    publicApiBaseUrl: options.publicApiBaseUrl ?? "https://eventor.example.test/api",
    ...(options.smtpTransportFactory ? { smtpTransportFactory: options.smtpTransportFactory } : {}),
  });
}


test("staff and organization locale preferences are validated and organization writes are tenant-scoped", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { withSessionCallbacks: true });
  t.after(async () => app.close());

  const current = await app.inject({ method: "GET", url: "/me" });
  assert.equal(current.statusCode, 200);
  assert.equal(current.json().data.organizationDefaultLocale, "bs-BA");

  const userPreference = await app.inject({
    method: "PATCH", url: "/me/preferences", payload: { locale: "en" },
  });
  assert.equal(userPreference.statusCode, 200);
  assert.deepEqual(userPreference.json().data, { userLocale: "en" });

  const resetUserPreference = await app.inject({
    method: "PATCH", url: "/me/preferences", payload: { locale: null },
  });
  assert.equal(resetUserPreference.statusCode, 200);
  assert.deepEqual(resetUserPreference.json().data, { userLocale: null });

  const unsupportedUserLocale = await app.inject({
    method: "PATCH", url: "/me/preferences", payload: { locale: "fr" },
  });
  assert.equal(unsupportedUserLocale.statusCode, 400);

  const organization = await app.inject({ method: "GET", url: "/organization/locale" });
  assert.equal(organization.statusCode, 200);
  assert.deepEqual(organization.json().data, { defaultLocale: "bs-BA", canManage: true });

  const update = await app.inject({
    method: "PATCH", url: "/organization/locale", payload: { defaultLocale: "en" },
  });
  assert.equal(update.statusCode, 200);
  assert.deepEqual(update.json().data, { defaultLocale: "en" });
  const command = mock.commandCalls.find((call) => call.sql.includes("eogp.set_organization_default_locale("));
  assert.deepEqual(command?.values, [principal.organizationId, principal.membershipId, "en"]);

  const unsupportedOrganizationLocale = await app.inject({
    method: "PATCH", url: "/organization/locale", payload: { defaultLocale: "fr" },
  });
  assert.equal(unsupportedOrganizationLocale.statusCode, 400);
  assert.equal(mock.commandCalls.filter((call) => call.sql.includes("eogp.set_organization_default_locale(")).length, 1);
});

test("staff booking form authoring API validates schemas and exposes idempotent tenant-scoped commands", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());

  const list = await app.inject({ method: "GET", url: "/organization/booking-forms" });
  assert.equal(list.statusCode, 200);
  assert.equal(list.json().data[0].formCode, "venue-rental");

  const invalid = await app.inject({
    method: "POST", url: "/organization/booking-forms",
    headers: { "idempotency-key": "booking-form-invalid-0001" },
    payload: { code: "venue-rental", name: "Venue rental", locale: "en",
      fieldSchema: { schemaVersion: 1, fields: [], contentTranslations: { fr: { formName: "Form", fields: {} } } } },
  });
  assert.equal(invalid.statusCode, 422);
  assert.equal(mock.commandCalls.filter(call => call.sql.includes("eogp.create_booking_form(")).length, 0);

  const create = await app.inject({
    method: "POST", url: "/organization/booking-forms",
    headers: { "idempotency-key": "booking-form-create-0001" },
    payload: { code: "venue-rental", name: "Venue rental", locale: "en",
      fieldSchema: { schemaVersion: 1, fields: [{ code: "event_name", type: "text", label: "Event name" }],
        contentTranslations: { "bs-BA": { formName: "Upit", fields: { event_name: { label: "Naziv događaja" } } } } } },
  });
  assert.equal(create.statusCode, 201);
  assert.equal(create.json().data.state, "draft");
  const createCall = mock.commandCalls.find(call => call.sql.includes("eogp.create_booking_form("));
  assert.deepEqual(createCall?.values.slice(0, 5), [principal.organizationId, principal.membershipId, "venue-rental", "Venue rental", "en"]);
  assert.equal(JSON.parse(String(createCall?.values[5])).contentTranslations["bs-BA"].formName, "Upit");

  const revision = await app.inject({
    method: "POST", url: "/booking-forms/31313131-3131-4131-8131-313131313131/revisions",
    headers: { "idempotency-key": "booking-form-revision-0001" },
  });
  assert.equal(revision.statusCode, 201);
  assert.equal(revision.json().data.revisionNumber, 2);

  const save = await app.inject({
    method: "PUT", url: "/booking-forms/31313131-3131-4131-8131-313131313131/revisions/33333333-3333-4333-8333-333333333333",
    headers: { "idempotency-key": "booking-form-save-0001" },
    payload: { locale: "bs-BA", fieldSchema: { schemaVersion: 1, fields: [{ code: "event_name", type: "text" }] } },
  });
  assert.equal(save.statusCode, 201);
  assert.equal(save.json().data.state, "draft");

  const publish = await app.inject({
    method: "POST", url: "/booking-forms/31313131-3131-4131-8131-313131313131/revisions/33333333-3333-4333-8333-333333333333/publish",
    headers: { "idempotency-key": "booking-form-publish-0001" },
  });
  assert.equal(publish.statusCode, 201);
  assert.equal(publish.json().data.state, "published");

  const calls = mock.commandCalls.filter(call => /eogp\.(?:get_booking_forms|create_booking_form|create_booking_form_revision|save_booking_form_draft|publish_booking_form_revision)\(/.test(call.sql));
  assert.equal(calls.length, 5);
  for (const call of calls) assert.equal(call.values[0], principal.organizationId);
});

test("public booking intake exposes only published forms and stores anonymous inquiries encrypted and idempotently", async (t) => {
  const mock = makePool();
  const contactKey = Buffer.alloc(32, 10);
  const app = makeApi(mock.pool, { authenticated: false, contactEncryptionKey: contactKey });
  t.after(async () => app.close());

  const formResponse = await app.inject({
    method: "GET",
    url: "/public/organizations/ghb/booking-forms/venue-rental",
  });
  assert.equal(formResponse.statusCode, 200);
  assert.equal(formResponse.headers["cache-control"], "public, max-age=60");
  const form = formResponse.json<{
    data: {
      organizationId: string;
      organizationSlug: string;
      organizationName: string;
      defaultLocale: "bs-BA" | "en";
      formCode: string;
      formRevisionId: string;
      fieldSchema: {
        fields: Array<{ code: string }>;
        contentTranslations?: Partial<Record<"bs-BA" | "en", {
          formName: string;
          fields: Record<string, { label?: string }>;
        }>>;
      };
    };
  }>().data;
  assert.equal(form.organizationSlug, "ghb");
  assert.equal(form.organizationName, "GHB");
  assert.equal(form.defaultLocale, "en");
  assert.equal(form.formCode, "venue-rental");
  assert.equal(form.formRevisionId, "12121212-1212-4121-8121-121212121212");
  assert.equal(form.fieldSchema.fields[0]?.code, "event_date");
  assert.equal(form.fieldSchema.contentTranslations?.["bs-BA"]?.formName, "Upit za iznajmljivanje prostora");
  assert.equal(form.fieldSchema.contentTranslations?.["bs-BA"]?.fields.event_date?.label, "Datum događaja");

  const inquiryBody = {
    formCode: "venue-rental",
    formRevisionId: form.formRevisionId,
    customerLocale: "bs-BA" as const,
    requester: {
      displayName: "Jane Example",
      email: "jane@example.test",
      phone: "+38761123456",
    },
    requested: {
      startAt: "2027-01-18T10:00:00+01:00",
      endAt: "2027-01-18T13:00:00+01:00",
      timezone: "Europe/Sarajevo",
      spaceCodes: ["MAIN-HALL"],
    },
    answers: {
      event_date: "2027-01-18",
      event_name: "Annual meeting",
      estimated_guests: 120,
    },
  };
  const submit = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries",
    headers: { "idempotency-key": "anonymous-inquiry-0001" },
    payload: inquiryBody,
  });
  assert.equal(submit.statusCode, 201);
  assert.equal(submit.headers["cache-control"], "no-store");
  const submitData = submit.json<{ data: { inquiryId: string; publicReference: string; status: string; replayed: boolean } }>().data;
  assert.equal(submitData.inquiryId, "13131313-1313-4131-8131-131313131313");
  assert.equal(submitData.publicReference, "INQ-AB12CD34EF56AB78");
  assert.equal(submitData.status, "received");
  assert.equal(submitData.replayed, false);
  assert.equal(mock.publicBookingFormCalls, 2);
  assert.equal(mock.publicBookingInquiryCalls, 1);
  const exactRevisionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.get_public_booking_form_revision("));
  assert.ok(exactRevisionCall);
  assert.deepEqual(exactRevisionCall.values, ["ghb", "venue-rental", form.formRevisionId]);

  const invalidAnswerRequests: Array<Record<string, unknown>> = [
    { ...inquiryBody.answers, event_name: undefined },
    { ...inquiryBody.answers, estimated_guests: "120" },
    { ...inquiryBody.answers, room_layout: "unpublished-value" },
    { ...inquiryBody.answers, internal_price_override: 0 },
  ];
  for (const [index, answers] of invalidAnswerRequests.entries()) {
    const invalid = await app.inject({
      method: "POST",
      url: "/public/organizations/ghb/booking-inquiries",
      headers: { "idempotency-key": `anonymous-inquiry-invalid-${index + 1}` },
      payload: { ...inquiryBody, answers },
    });
    assert.equal(invalid.statusCode, 422);
    assert.equal(invalid.json<{ code: string }>().code, "PUBLIC_FORM_ANSWERS_INVALID");
  }
  assert.equal(mock.publicBookingInquiryCalls, 1);

  const unsupportedLocale = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries",
    headers: { "idempotency-key": "anonymous-inquiry-locale-01" },
    payload: { ...inquiryBody, customerLocale: "fr" },
  });
  assert.equal(unsupportedLocale.statusCode, 400);
  assert.equal(mock.publicBookingInquiryCalls, 1);

  const staleRevision = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries",
    headers: { "idempotency-key": "anonymous-inquiry-stale-01" },
    payload: { ...inquiryBody, formRevisionId: "99999999-9999-4999-8999-999999999999" },
  });
  assert.equal(staleRevision.statusCode, 409);
  assert.equal(staleRevision.json<{ code: string }>().code, "PUBLIC_FORM_REVISION_UNAVAILABLE");

  const missingForm = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries",
    headers: { "idempotency-key": "anonymous-inquiry-missing-01" },
    payload: { ...inquiryBody, formCode: "unknown-form" },
  });
  assert.equal(missingForm.statusCode, 404);
  assert.equal(missingForm.json<{ code: string }>().code, "PUBLIC_BOOKING_FORM_NOT_FOUND");
  assert.equal(mock.publicBookingInquiryCalls, 1);

  const submissionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.submit_public_booking_inquiry_with_locale("));
  assert.ok(submissionCall);
  assert.equal(submissionCall.values[0], "ghb");
  assert.equal(submissionCall.values[1], "venue-rental");
  assert.equal(submissionCall.values[2], form.formRevisionId);
  assert.match(String(submissionCall.values[3]), /^[0-9a-f]{64}$/);
  assert.match(String(submissionCall.values[4]), /^[0-9a-f]{64}$/);
  assert.match(String(submissionCall.values[5]), /^[0-9a-f]{64}$/);
  assert.ok(Buffer.isBuffer(submissionCall.values[6]));
  assert.ok(Buffer.isBuffer(submissionCall.values[7]));
  assert.ok(Buffer.isBuffer(submissionCall.values[9]));
  assert.ok(Buffer.isBuffer(submissionCall.values[11]));
  assert.equal(submissionCall.values[15], "bs-BA");
  assert.notEqual(submissionCall.values[8], "jane@example.test");
  assert.notEqual(submissionCall.values[10], "+38761123456");
  assert.equal(
    decryptContactValue(submissionCall.values[7] as Buffer, contactKey, {
      organizationId: form.organizationId,
      contactKind: "other",
    }),
    "Jane Example",
  );
  assert.equal(
    decryptContactValue(submissionCall.values[9] as Buffer, contactKey, {
      organizationId: form.organizationId,
      contactKind: "email",
    }),
    "jane@example.test",
  );
  assert.equal(
    decryptContactValue(submissionCall.values[11] as Buffer, contactKey, {
      organizationId: form.organizationId,
      contactKind: "phone",
    }),
    "+38761123456",
  );
  const encryptedSubmission = JSON.parse(
    decryptContactValue(submissionCall.values[6] as Buffer, contactKey, {
      organizationId: form.organizationId,
      contactKind: "other",
    }),
  ) as { answers: Record<string, unknown>; requested: { spaceCodes: string[] } };
  assert.equal(encryptedSubmission.answers.event_name, "Annual meeting");
  assert.deepEqual(encryptedSubmission.requested.spaceCodes, ["MAIN-HALL"]);
  assert.ok(!submissionCall.values.includes("Jane Example"));
  assert.ok(!submissionCall.values.includes("jane@example.test"));
  assert.ok(!submissionCall.values.includes("+38761123456"));

  const unsupportedAttachment = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries",
    headers: { "idempotency-key": "anonymous-inquiry-0002" },
    payload: { ...inquiryBody, attachmentReferences: ["upload-token-1"] },
  });
  assert.equal(unsupportedAttachment.statusCode, 422);
  assert.equal(mock.publicBookingInquiryCalls, 1);

  const staffProjection = await app.inject({ method: "GET", url: "/me" });
  assert.equal(staffProjection.statusCode, 401);
  const nonAllowListedPublicPath = await app.inject({
    method: "POST",
    url: "/public/organizations/ghb/booking-inquiries/extra",
    payload: inquiryBody,
  });
  assert.equal(nonAllowListedPublicPath.statusCode, 401);
  assert.equal(mock.publicBookingInquiryCalls, 1);
});

test("staff inquiry inbox decrypts authorized projections and routes assignment, status and internal-note commands", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());

  const capabilities = await app.inject({
    method: "GET",
    url: `/organizations/${principal.organizationId}/booking-inquiry-capabilities`,
  });
  assert.equal(capabilities.statusCode, 200);
  assert.deepEqual(capabilities.json<{ data: {
    canAssign: boolean; canManage: boolean; canAnnotate: boolean; canConvert: boolean;
    canReadDraft: boolean; canManageDraft: boolean;
  } }>().data, {
    canAssign: true, canManage: true, canAnnotate: true, canConvert: true,
    canReadDraft: true, canManageDraft: true,
  });
  assert.equal(mock.bookingInquiryCapabilitiesCalls, 1);

  const roster = await app.inject({
    method: "GET",
    url: `/organizations/${principal.organizationId}/booking-inquiry-assignees`,
  });
  assert.equal(roster.statusCode, 200);
  assert.deepEqual(roster.json<{ data: Array<{ membershipId: string; displayName: string }> }>().data[1], {
    membershipId: "cccccccc-2222-4222-8222-cccccccccccc",
    displayName: "Alex Assignee",
  });
  assert.equal(mock.bookingInquiryAssigneeRosterCalls, 1);

  const list = await app.inject({
    method: "GET",
    url: `/organizations/${principal.organizationId}/booking-inquiries?status=received&limit=10&offset=0`,
  });
  assert.equal(list.statusCode, 200);
  const listBody = list.json<{
    data: Array<{ inquiryId: string; requesterName: string; publicReference: string }>;
    meta: { limit: number; offset: number; totalCount: number };
  }>();
  assert.equal(listBody.data.length, 1);
  assert.equal(listBody.data[0]?.requesterName, "Jane Example");
  assert.equal(listBody.data[0]?.publicReference, "INQ-1234567890ABCDEF");
  assert.deepEqual(listBody.meta, { limit: 10, offset: 0, totalCount: 1 });
  assert.equal(mock.bookingInquiryListCalls, 1);
  assert.equal(mock.commandCalls.find((call) => call.sql.includes("eogp.list_booking_inquiries("))?.values[2], "received");

  const inquiryId = "14141414-1414-4141-8141-141414141414";
  const detail = await app.inject({
    method: "GET",
    url: `/booking-inquiries/${inquiryId}`,
  });
  assert.equal(detail.statusCode, 200);
  const detailBody = detail.json<{
    data: {
      requesterName: string;
      requesterEmail: string;
      requesterPhone: string;
      submittedValues: { answers: Record<string, unknown> };
      annotations: Array<{ annotation: string; visibility: string }>;
      statusHistory: Array<{ newStatus: string }>;
      assignmentHistory: Array<{ newAssigneeMembershipId: string }>;
    };
  }>().data;
  assert.equal(detailBody.requesterName, "Jane Example");
  assert.equal(detailBody.requesterEmail, "jane@example.test");
  assert.equal(detailBody.requesterPhone, "+38761123456");
  assert.equal(detailBody.submittedValues.answers.estimated_guests, 120);
  assert.equal(detailBody.annotations[0]?.visibility, "internal");
  assert.equal(detailBody.annotations[0]?.annotation, "Call to confirm setup access.");
  assert.equal(detailBody.statusHistory[0]?.newStatus, "under_review");
  assert.equal(detailBody.assignmentHistory[0]?.newAssigneeMembershipId, "cccccccc-2222-4222-8222-cccccccccccc");
  assert.equal(mock.bookingInquiryGetCalls, 1);

  const assignee = "cccccccc-2222-4222-8222-cccccccccccc";
  const assignment = await app.inject({
    method: "POST",
    url: `/booking-inquiries/${inquiryId}/assignment`,
    headers: { "idempotency-key": "assign-inquiry-0001" },
    payload: { assignedToMembershipId: assignee },
  });
  assert.equal(assignment.statusCode, 201);
  assert.equal(assignment.json<{ data: { assignedToMembershipId: string; changed: boolean } }>().data.assignedToMembershipId, assignee);
  assert.equal(mock.bookingInquiryAssignCalls, 1);

  const status = await app.inject({
    method: "POST",
    url: `/booking-inquiries/${inquiryId}/status`,
    headers: { "idempotency-key": "status-inquiry-0001" },
    payload: { status: "under_review", reason: "Assigned to the booking team." },
  });
  assert.equal(status.statusCode, 201);
  assert.equal(status.json<{ data: { status: string } }>().data.status, "under_review");
  assert.equal(mock.bookingInquiryStatusCalls, 1);

  const annotation = await app.inject({
    method: "POST",
    url: `/booking-inquiries/${inquiryId}/annotations`,
    headers: { "idempotency-key": "annotation-inquiry-0001" },
    payload: { annotation: "Call to confirm setup access." },
  });
  assert.equal(annotation.statusCode, 201);
  assert.equal(annotation.json<{ data: { visibility: string } }>().data.visibility, "internal");
  assert.equal(mock.bookingInquiryAnnotationCalls, 1);

  const conversion = await app.inject({
    method: "POST",
    url: `/booking-inquiries/${inquiryId}/create-draft`,
    headers: { "idempotency-key": "convert-inquiry-0001" },
    payload: {},
  });
  assert.equal(conversion.statusCode, 201);
  assert.deepEqual(conversion.json<{ data: Record<string, unknown> }>().data, {
    inquiryId,
    draftId: "15151515-1515-4151-8151-151515151515",
    revisionId: "16161616-1616-4161-8161-161616161616",
    revisionNumber: 1,
    status: "converted",
    changed: true,
  });
  assert.equal(mock.bookingInquiryConversionCalls, 1);
  const conversionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.convert_booking_inquiry_to_draft("));
  assert.ok(conversionCall);
  assert.deepEqual(conversionCall.values, [
    principal.organizationId,
    inquiryId,
    principal.membershipId,
  ]);

  const replay = await app.inject({
    method: "POST",
    url: `/booking-inquiries/${inquiryId}/create-draft`,
    headers: { "idempotency-key": "convert-inquiry-0001" },
    payload: {},
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json(), conversion.json());
  assert.equal(mock.bookingInquiryConversionCalls, 1);

  const draftId = "15151515-1515-4151-8151-151515151515";
  const draft = await app.inject({
    method: "GET",
    url: `/booking-drafts/${draftId}`,
  });
  assert.equal(draft.statusCode, 200);
  const draftData = draft.json<{
    data: {
      draftId: string;
      currentRevisionNumber: number;
      currentRevision: {
        values: Record<string, unknown>;
        revisionNumber: number;
        sourceFormRevisionId: string;
        fieldSchema: { fields: Array<{ code: string; type: string }> };
      };
    };
  }>().data;
  assert.equal(draftData.draftId, draftId);
  assert.equal(draftData.currentRevisionNumber, 1);
  assert.equal(draftData.currentRevision.revisionNumber, 1);
  assert.equal(draftData.currentRevision.sourceFormRevisionId, "21212121-2121-4121-8121-212121212121");
  assert.deepEqual(draftData.currentRevision.fieldSchema.fields.map((field) => field.code), [
    "event_date", "event_name", "estimated_guests",
  ]);
  assert.deepEqual(draftData.currentRevision.values, bookingDraftValues);
  assert.equal("valuesSnapshot" in (draftData.currentRevision as unknown as Record<string, unknown>), false);
  assert.equal(mock.bookingDraftGetCalls, 1);

  const allocationPreview = await app.inject({
    method: "POST",
    url: `/booking-drafts/${draftId}/allocation-availability-preview`,
    payload: {
      spaceLines: [{
        venueSpaceId: "44444444-4444-4444-8444-444444444444",
        startsAt: "2027-01-18T09:00:00.000Z",
        endsAt: "2027-01-18T13:00:00.000Z",
        blockKind: "event_use",
        requestedCapacity: 100,
      }],
      resourceLines: [{
        resourceTypeId: "55555555-5555-4555-8555-555555555555",
        requestedQuantity: 10,
      }],
      resourceStartsAt: "2027-01-18T09:00:00.000Z",
      resourceEndsAt: "2027-01-18T13:00:00.000Z",
    },
  });
  assert.equal(allocationPreview.statusCode, 200);
  const previewData = allocationPreview.json<{
    data: {
      spaces: Array<{ available: boolean; conflicts: Array<{ kind: string }> }>;
      resources: Array<{ available: boolean; availableQuantity: number }>;
      spaceAlternatives: Array<{ alternatives: Array<{ venueSpaceId: string; capacity: number }> }>;
      resourcePools: Array<{ pools: Array<{ availableQuantity: number }> }>;
      advisoryOnly: boolean;
    };
  }>().data;
  assert.equal(previewData.advisoryOnly, true);
  assert.equal(previewData.spaces[0]?.available, false);
  assert.equal(previewData.spaces[0]?.conflicts[0]?.kind, "confirmed_booking");
  assert.equal(previewData.resources[0]?.available, false);
  assert.equal(previewData.resources[0]?.availableQuantity, 4);
  assert.equal(previewData.spaceAlternatives[0]?.alternatives[0]?.venueSpaceId, "66666666-6666-4666-8666-666666666666");
  assert.equal(previewData.resourcePools[0]?.pools[0]?.availableQuantity, 4);
  assert.equal(mock.bookingDraftAllocationPreviewCalls, 1);
  const previewCall = mock.commandCalls.find((call) => call.sql.includes("preview_booking_draft_allocation_availability"));
  assert.ok(previewCall);
  assert.equal(previewCall.values[0], principal.organizationId);
  assert.equal(previewCall.values[1], draftId);
  assert.equal(previewCall.values[2], principal.membershipId);
  assert.equal(JSON.parse(String(previewCall.values[3])).length, 1);
  assert.equal(JSON.parse(String(previewCall.values[3]))[0].requestedCapacity, 100);
  assert.equal(JSON.parse(String(previewCall.values[4])).length, 1);
  assert.equal(previewCall.values[5], "2027-01-18T09:00:00.000Z");
  assert.equal(previewCall.values[6], "2027-01-18T13:00:00.000Z");

  const revisionBody = {
    expectedRevisionNumber: 1,
    values: {
      requested: { timezone: "Europe/Sarajevo", spaceCodes: ["MAIN-HALL"] },
      answers: { event_date: "2027-01-18", event_name: "Updated Community Lecture", estimated_guests: 150 },
    },
    requestedStart: "2027-01-18T09:00:00.000Z",
    requestedEnd: "2027-01-18T13:00:00.000Z",
    timezone: "Europe/Sarajevo",
    spaceLines: [],
    resourceLines: [],
    changeReason: "Updated event title, guest estimate and requested end time.",
  };
  const revision = await app.inject({
    method: "POST",
    url: `/booking-drafts/${draftId}/revisions`,
    headers: { "idempotency-key": "draft-revision-0001" },
    payload: revisionBody,
  });
  assert.equal(revision.statusCode, 201);
  assert.deepEqual(revision.json<{ data: Record<string, unknown> }>().data, {
    draftId,
    revisionId: "17171717-1717-4171-8171-171717171717",
    revisionNumber: 2,
    previousRevisionNumber: 1,
    status: "draft",
    changed: true,
  });
  assert.equal(mock.bookingDraftGetCalls, 2);
  assert.equal(mock.bookingDraftRevisionCalls, 1);

  const offerBody = {
    priceListRevisionId: "21212121-2121-4121-8121-212121212121",
    cancellationPolicyRevisionId: "22222222-2222-4222-8222-222222222222",
    approvalPolicyRevisionId: "23232323-2323-4323-8323-232323232323",
    currency: "BAM",
    taxBasis: "exclusive" as const,
    validUntil: "2026-12-01T12:00:00.000Z",
    lineItems: [{ itemCode: "HALL-RENTAL", quantity: 1 }],
    adjustments: [],
    taxAmount: 25,
  };
  const offerPrepared = await app.inject({
    method: "POST",
    url: "/booking-draft-revisions/16161616-1616-4161-8161-161616161616/offers",
    headers: { "idempotency-key": "prepare-booking-offer-0001" },
    payload: offerBody,
  });
  assert.equal(offerPrepared.statusCode, 201);
  const preparedData = offerPrepared.json<{ data: { offerId: string; offerRevisionId: string; state: string; totalAmount: number } }>().data;
  assert.equal(preparedData.offerId, "18181818-1818-4181-8181-181818181818");
  assert.equal(preparedData.state, "draft");
  assert.equal(preparedData.totalAmount, 275);
  assert.equal(mock.bookingOfferPrepareCalls, 1);
  const prepareCall = mock.commandCalls.find((call) => call.sql.includes("eogp.save_booking_offer_revision("));
  assert.ok(prepareCall);
  assert.deepEqual(prepareCall.values.slice(0, 4), [
    principal.organizationId,
    "16161616-1616-4161-8161-161616161616",
    principal.membershipId,
    null,
  ]);
  assert.deepEqual(JSON.parse(String(prepareCall.values[10])), offerBody.lineItems);
  assert.deepEqual(JSON.parse(String(prepareCall.values[11])), []);

  const offerRead = await app.inject({
    method: "GET",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818",
  });
  assert.equal(offerRead.statusCode, 200);
  assert.equal(
    offerRead.json<{ data: { currentRevision: { state: string; totalAmount: number } } }>().data.currentRevision.state,
    "draft",
  );
  assert.equal(mock.bookingOfferGetCalls, 1);

  const offerIssued = await app.inject({
    method: "POST",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818/issue",
    headers: { "idempotency-key": "issue-booking-offer-0001" },
    payload: {},
  });
  assert.equal(offerIssued.statusCode, 201);
  const issueData = offerIssued.json<{ data: { state: string; acceptanceToken: string } }>().data;
  assert.equal(issueData.state, "issued");
  assert.match(issueData.acceptanceToken, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(mock.bookingOfferIssueCalls, 1);

  const offerIssueReplay = await app.inject({
    method: "POST",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818/issue",
    headers: { "idempotency-key": "issue-booking-offer-0001" },
    payload: {},
  });
  assert.equal(offerIssueReplay.statusCode, 201);
  assert.equal(
    offerIssueReplay.json<{ data: { acceptanceToken: string } }>().data.acceptanceToken,
    issueData.acceptanceToken,
  );
  assert.equal(mock.bookingOfferIssueCalls, 1);

  const offerEmailQueued = await app.inject({
    method: "POST",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818/email",
    headers: { "idempotency-key": "email-booking-offer-0001" },
    payload: { acceptanceToken: issueData.acceptanceToken },
  });
  assert.equal(offerEmailQueued.statusCode, 201);
  assert.equal(offerEmailQueued.json<{ data: { status: string; created: boolean } }>().data.status, "queued");
  assert.equal(mock.bookingOfferEmailQueueCalls, 1);
  const emailQueueCall = mock.commandCalls.find((call) => call.sql.includes("eogp.queue_booking_offer_email_delivery("));
  assert.ok(emailQueueCall);
  assert.equal(emailQueueCall.values[4], createHash("sha256").update(issueData.acceptanceToken, "utf8").digest("hex"));
  assert.ok(Buffer.isBuffer(emailQueueCall.values[5]));
  assert.equal((emailQueueCall.values[5] as Buffer).subarray(0, 4).toString("utf8"), "ECP1");
  assert.notEqual((emailQueueCall.values[5] as Buffer).toString("utf8"), issueData.acceptanceToken);

  const offerEmailHistory = await app.inject({
    method: "GET",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818/email-deliveries?limit=10&offset=0",
  });
  assert.equal(offerEmailHistory.statusCode, 200);
  assert.equal(offerEmailHistory.json<{ data: Array<{ status: string }>; meta: { totalCount: number; counts: Record<string, number> } }>().data[0]?.status, "uncertain");
  assert.equal(offerEmailHistory.json<{ meta: { totalCount: number; counts: Record<string, number> } }>().meta.totalCount, 1);
  assert.equal(mock.bookingOfferEmailListCalls, 1);
  assert.doesNotMatch(JSON.stringify(offerEmailHistory.json()), /customer@example\.test|ciphertext|acceptanceToken/);

  const offerEmailReconciled = await app.inject({
    method: "POST",
    url: "/booking-offer-email-deliveries/21212121-2121-4121-8121-212121212121/reconcile",
    headers: { "idempotency-key": "reconcile-booking-offer-email-0001" },
    payload: { resolution: "confirmed_not_sent", reason: "Checked the SMTP server queue logs." },
  });
  assert.equal(offerEmailReconciled.statusCode, 201);
  assert.equal(offerEmailReconciled.json<{ data: { status: string } }>().data.status, "failed");
  assert.equal(mock.bookingOfferEmailReconcileCalls, 1);
  const offerEmailReconcileReplay = await app.inject({
    method: "POST",
    url: "/booking-offer-email-deliveries/21212121-2121-4121-8121-212121212121/reconcile",
    headers: { "idempotency-key": "reconcile-booking-offer-email-0001" },
    payload: { resolution: "confirmed_not_sent", reason: "Checked the SMTP server queue logs." },
  });
  assert.equal(offerEmailReconcileReplay.statusCode, 201);
  assert.equal(mock.bookingOfferEmailReconcileCalls, 1);

  const offerEmailRetry = await app.inject({
    method: "POST",
    url: "/booking-offer-email-deliveries/21212121-2121-4121-8121-212121212121/retry",
    headers: { "idempotency-key": "retry-booking-offer-email-0001" },
    payload: { reason: "Verified non-acceptance; SMTP configuration is now corrected." },
  });
  assert.equal(offerEmailRetry.statusCode, 201);
  assert.equal(offerEmailRetry.json<{ data: { status: string; manualRetryCount: number } }>().data.status, "queued");
  assert.equal(offerEmailRetry.json<{ data: { manualRetryCount: number } }>().data.manualRetryCount, 1);
  assert.equal(mock.bookingOfferEmailRetryCalls, 1);
  const offerEmailRetryReplay = await app.inject({
    method: "POST",
    url: "/booking-offer-email-deliveries/21212121-2121-4121-8121-212121212121/retry",
    headers: { "idempotency-key": "retry-booking-offer-email-0001" },
    payload: { reason: "Verified non-acceptance; SMTP configuration is now corrected." },
  });
  assert.equal(offerEmailRetryReplay.statusCode, 201);
  assert.equal(mock.bookingOfferEmailRetryCalls, 1);

  const successorOffer = await app.inject({
    method: "POST",
    url: "/booking-offers/18181818-1818-4181-8181-181818181818/revisions",
    headers: { "idempotency-key": "revise-booking-offer-0001" },
    payload: {
      draftRevisionId: "16161616-1616-4161-8161-161616161616",
      ...offerBody,
      internalReason: "Correcting the venue rental rate.",
      supersedeCurrentOffer: true,
    },
  });
  assert.equal(successorOffer.statusCode, 201);
  assert.equal(
    successorOffer.json<{ data: { revisionNumber: number; state: string } }>().data.revisionNumber,
    2,
  );
  assert.equal(mock.bookingOfferSuccessorCalls, 1);
  const revisionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.create_booking_draft_revision("));
  assert.ok(revisionCall);
  assert.deepEqual(revisionCall.values.slice(0, 4), [
    principal.organizationId, draftId, principal.membershipId, 1,
  ]);
  assert.ok(Buffer.isBuffer(revisionCall.values[4]));
  const expectedRevisionValues = {
    ...revisionBody.values,
    requested: {
      ...revisionBody.values.requested,
      startAt: revisionBody.requestedStart,
      endAt: revisionBody.requestedEnd,
      timezone: revisionBody.timezone,
    },
  };
  assert.equal(
    decryptContactValue(revisionCall.values[4] as Buffer, inquiryTestContactKey, {
      organizationId: principal.organizationId,
      contactKind: "other",
    }),
    JSON.stringify(expectedRevisionValues),
  );
  const revisionReplay = await app.inject({
    method: "POST",
    url: `/booking-drafts/${draftId}/revisions`,
    headers: { "idempotency-key": "draft-revision-0001" },
    payload: revisionBody,
  });
  assert.equal(revisionReplay.statusCode, 201);
  assert.deepEqual(revisionReplay.json(), revision.json());
  assert.equal(mock.bookingDraftRevisionCalls, 1);

  const convertedInquiry = await app.inject({
    method: "GET",
    url: `/booking-inquiries/${inquiryId}`,
  });
  assert.equal(convertedInquiry.statusCode, 200);
  assert.equal(
    convertedInquiry.json<{ data: { bookingDraft: { draftId: string; status: string; currentRevisionNumber: number } | null } }>().data.bookingDraft?.draftId,
    draftId,
  );

  const anonymous = makeApi(mock.pool, { authenticated: false });
  t.after(async () => anonymous.close());
  const denied = await anonymous.inject({
    method: "GET",
    url: `/organizations/${principal.organizationId}/booking-inquiries`,
  });
  assert.equal(denied.statusCode, 401);
});




test("explicit booking confirmation requires the exact draft revision and replays idempotently", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const revisionId = "16161616-1616-4161-8161-161616161616";
  const payload = {
    expectedDraftRevisionId: revisionId,
    confirmationReason: "Customer accepted and all required approvals are complete.",
  };
  const headers = { "idempotency-key": "confirm-booking-0001" };

  const mismatch = await app.inject({
    method: "POST",
    url: "/booking-draft-revisions/17171717-1717-4171-8171-171717171717/confirm",
    headers,
    payload,
  });
  assert.equal(mismatch.statusCode, 409);
  assert.equal(mock.bookingConfirmationCalls, 0);

  const confirmed = await app.inject({
    method: "POST",
    url: `/booking-draft-revisions/${revisionId}/confirm`,
    headers,
    payload,
  });
  assert.equal(confirmed.statusCode, 201);
  const data = confirmed.json<{
    data: { bookingId: string; bookingCode: string; status: string; spaceReservationsConfirmed: number; resourceReservationsConfirmed: number; replayed: boolean };
  }>().data;
  assert.equal(data.bookingId, "24242424-2424-4242-8242-242424242424");
  assert.equal(data.bookingCode, "BKG-ABCDEF123456");
  assert.equal(data.status, "confirmed");
  assert.equal(data.spaceReservationsConfirmed, 1);
  assert.equal(data.resourceReservationsConfirmed, 2);
  assert.equal(data.replayed, false);

  const call = mock.commandCalls.find((item) => item.sql.includes("eogp.confirm_booking_from_offer("));
  assert.ok(call);
  assert.deepEqual(call.values, [
    principal.organizationId,
    revisionId,
    principal.membershipId,
    payload.confirmationReason,
  ]);

  const replay = await app.inject({
    method: "POST",
    url: `/booking-draft-revisions/${revisionId}/confirm`,
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json(), confirmed.json());
  assert.equal(mock.bookingConfirmationCalls, 1);
});

test("offer approvals are permission-gated, reasoned and scoped to an exact offer revision", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const offerId = "18181818-1818-4181-8181-181818181818";
  const offerRevisionId = "18181818-1818-4181-8181-181818181819";

  const decision = await app.inject({
    method: "POST",
    url: `/booking-offers/${offerId}/approvals`,
    headers: { "idempotency-key": "offer-approval-0001" },
    payload: {
      offerRevisionId,
      ruleCode: "high_value",
      decision: "approved",
      reason: "Reviewed the pricing and approved the offer.",
    },
  });
  assert.equal(decision.statusCode, 201);
  const decisionData = decision.json<{
    data: { offerId: string; offerRevisionId: string; ruleCode: string; approvedCount: number; requiredApprovals: number; satisfied: boolean };
  }>().data;
  assert.equal(decisionData.offerId, offerId);
  assert.equal(decisionData.offerRevisionId, offerRevisionId);
  assert.equal(decisionData.ruleCode, "high_value");
  assert.equal(decisionData.approvedCount, 1);
  assert.equal(decisionData.requiredApprovals, 2);
  assert.equal(decisionData.satisfied, false);
  assert.equal(mock.bookingOfferApprovalDecisionCalls, 1);
  const approvalCall = mock.commandCalls.find((call) => call.sql.includes("eogp.decide_booking_offer_approval("));
  assert.ok(approvalCall);
  assert.deepEqual(approvalCall.values, [
    principal.organizationId,
    offerId,
    offerRevisionId,
    principal.membershipId,
    "high_value",
    "approved",
    "Reviewed the pricing and approved the offer.",
  ]);

  const status = await app.inject({
    method: "GET",
    url: `/booking-offers/${offerId}/approvals`,
  });
  assert.equal(status.statusCode, 200);
  const statusData = status.json<{ data: { requirements: Array<{ ruleCode: string; approvedCount: number; requiredApprovals: number; blocked: boolean }> } }>().data;
  assert.equal(statusData.requirements[0]?.ruleCode, "high_value");
  assert.equal(statusData.requirements[0]?.approvedCount, 1);
  assert.equal(statusData.requirements[0]?.requiredApprovals, 2);
  assert.equal(statusData.requirements[0]?.blocked, false);
  assert.equal(mock.bookingOfferApprovalStatusCalls, 1);
});


test("organization approval policies are created, versioned and published through audited commands", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());

  const listed = await app.inject({
    method: "GET",
    url: "/organization/booking-approval-policies",
  });
  assert.equal(listed.statusCode, 200);
  const policies = listed.json<{ data: Array<{ policyId: string; latestRevisionId: string; revisions: Array<{ state: string }> }> }>().data;
  assert.equal(policies[0]?.policyId, "27272727-2727-4727-8727-272727272727");
  assert.equal(policies[0]?.revisions[0]?.state, "published");
  assert.equal(mock.bookingApprovalPolicyListCalls, 1);

  const created = await app.inject({
    method: "POST",
    url: "/organization/booking-approval-policies",
    headers: { "idempotency-key": "create-approval-policy-001" },
    payload: { code: "venue_bookings", name: "Venue booking approvals" },
  });
  assert.equal(created.statusCode, 201);
  assert.equal(created.json<{ data: { state: string } }>().data.state, "active");
  const createCall = mock.commandCalls.find((call) => call.sql.includes("eogp.create_booking_approval_policy("));
  assert.ok(createCall);
  assert.deepEqual(createCall.values, [
    principal.organizationId, principal.membershipId, "venue_bookings", "Venue booking approvals",
  ]);

  const rules = [{
    code: "high_value",
    condition: { kind: "total_at_least", amount: 1000, currency: "BAM" },
    requiredApprovals: 2,
    permission: "booking.approve",
    separationOfDuties: true,
  }];
  const policyId = "27272727-2727-4727-8727-272727272727";
  const revision = await app.inject({
    method: "POST",
    url: `/booking-approval-policies/${policyId}/revisions`,
    headers: { "idempotency-key": "create-approval-policy-revision-001" },
    payload: { rules },
  });
  assert.equal(revision.statusCode, 201);
  const revisionData = revision.json<{ data: { revisionNumber: number; state: string } }>().data;
  assert.equal(revisionData.revisionNumber, 1);
  assert.equal(revisionData.state, "draft");
  const revisionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.create_booking_approval_policy_revision("));
  assert.ok(revisionCall);
  assert.deepEqual(revisionCall.values.slice(0, 3), [
    principal.organizationId, policyId, principal.membershipId,
  ]);
  assert.deepEqual(JSON.parse(String(revisionCall.values[3])), rules);

  const revisionId = "28282828-2828-4828-8828-282828282828";
  const revisedRules = [{
    code: "high_value",
    condition: { kind: "total_at_least", amount: 1500, currency: "BAM" },
    requiredApprovals: 2,
    permission: "booking.approve",
    separationOfDuties: true,
  }];
  const draftUpdated = await app.inject({
    method: "PUT",
    url: `/booking-approval-policies/${policyId}/revisions/${revisionId}`,
    headers: { "idempotency-key": "update-approval-policy-draft-001" },
    payload: { rules: revisedRules },
  });
  assert.equal(draftUpdated.statusCode, 201);
  assert.equal(draftUpdated.json<{ data: { revisionId: string; revisionNumber: number; state: string } }>().data.revisionId, revisionId);
  assert.equal(mock.bookingApprovalPolicyRevisionUpdateCalls, 1);
  const updateCall = mock.commandCalls.find((call) => call.sql.includes("eogp.update_booking_approval_policy_draft_revision("));
  assert.ok(updateCall);
  assert.deepEqual(updateCall.values, [
    principal.organizationId, policyId, revisionId, principal.membershipId, JSON.stringify(revisedRules),
  ]);

  const published = await app.inject({
    method: "POST",
    url: `/booking-approval-policies/${policyId}/revisions/${revisionId}/publish`,
    headers: { "idempotency-key": "publish-approval-policy-revision-001" },
    payload: {},
  });
  assert.equal(published.statusCode, 201);
  assert.equal(published.json<{ data: { state: string } }>().data.state, "published");
  const publishCall = mock.commandCalls.find((call) => call.sql.includes("eogp.publish_booking_approval_policy_revision("));
  assert.ok(publishCall);
  assert.deepEqual(publishCall.values, [
    principal.organizationId, policyId, revisionId, principal.membershipId,
  ]);

  const invalid = await app.inject({
    method: "POST",
    url: `/booking-approval-policies/${policyId}/revisions`,
    headers: { "idempotency-key": "invalid-approval-policy-revision-001" },
    payload: { rules: [{
      code: "wrong_permission",
      condition: { kind: "always" },
      requiredApprovals: 1,
      permission: "booking.confirm",
      separationOfDuties: false,
    }] },
  });
  assert.equal(invalid.statusCode, 400);
  assert.equal(mock.bookingApprovalPolicyRevisionCalls, 1);

  const anonymous = makeApi(mock.pool, { authenticated: false });
  t.after(async () => anonymous.close());
  const denied = await anonymous.inject({
    method: "GET",
    url: "/organization/booking-approval-policies",
  });
  assert.equal(denied.statusCode, 401);
});

test("public offer review shows only customer-safe terms using a purpose-bound capability", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { authenticated: false });
  t.after(async () => app.close());
  const offerId = "18181818-1818-4181-8181-181818181818";
  const token = "V".repeat(43);

  const response = await app.inject({
    method: "GET",
    url: `/public/booking-offers/${offerId}`,
    headers: { "x-external-booking-token": token },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["cache-control"], "no-store, private");
  assert.equal(response.headers["referrer-policy"], "no-referrer");
  assert.equal(response.headers["x-robots-tag"], "noindex, nofollow, noarchive");
  const data = response.json<{
    data: {
      offerId: string,
      status: string;
      totalAmount: number;
      terms: { lineItems: Array<{ label: string }>; spaces: Array<{ code: string }>; resources: Array<{ label: string }> };
    };
  }>().data;
  assert.equal(data.offerId, offerId);
  assert.equal(data.status, "issued");
  assert.equal(data.totalAmount, 275);
  assert.equal(data.terms.lineItems[0]?.label, "Hall rental");
  assert.equal(data.terms.spaces[0]?.code, "MAIN-HALL");
  assert.equal(data.terms.resources[0]?.label, "Chairs");
  assert.equal("approvalRequirements" in data, false);
  assert.equal("internalReason" in data.terms, false);
  assert.equal(mock.publicBookingOfferViewCalls, 1);

  const call = mock.commandCalls.find((item) => item.sql.includes("eogp.get_public_booking_offer_with_capability("));
  assert.ok(call);
  assert.equal(call.values[0], offerId);
  assert.equal(call.values[1], createHash("sha256").update(token, "utf8").digest("hex"));

  const missingToken = await app.inject({
    method: "GET",
    url: `/public/booking-offers/${offerId}`,
  });
  assert.equal(missingToken.statusCode, 400);
});

test("customer offer acceptance and rejection use a one-use purpose-bound capability without a staff session", async (t) => {
  const mock = makePool();
  const contactKey = Buffer.alloc(32, 10);
  const app = makeApi(mock.pool, { authenticated: false, contactEncryptionKey: contactKey });
  t.after(async () => app.close());

  const offerId = "18181818-1818-4181-8181-181818181818";
  const token = "A".repeat(43);
  const headers = {
    "x-external-booking-token": token,
    "idempotency-key": "customer-offer-accept-0001",
  };
  const payload = {
    acceptanceName: "Jane Example",
    acceptanceNote: "I accept the stated venue terms.",
  };
  const accepted = await app.inject({
    method: "POST",
    url: `/booking-offers/${offerId}/accept`,
    headers,
    payload,
  });
  assert.equal(accepted.statusCode, 201);
  assert.equal(accepted.json<{ data: { decision: string; replayed: boolean } }>().data.decision, "accepted");
  assert.equal(accepted.json<{ data: { replayed: boolean } }>().data.replayed, false);

  const decisionCall = mock.commandCalls.find((call) => call.sql.includes("eogp.decide_booking_offer_with_capability("));
  assert.ok(decisionCall);
  assert.equal(decisionCall.values[0], offerId);
  assert.equal(decisionCall.values[2], "accepted");
  assert.equal(
    decisionCall.values[1],
    createHash("sha256").update(token, "utf8").digest("hex"),
  );
  assert.ok(Buffer.isBuffer(decisionCall.values[5]));
  assert.equal(
    decryptContactValue(decisionCall.values[5] as Buffer, contactKey, {
      organizationId: principal.organizationId,
      contactKind: "other",
    }),
    "Jane Example",
  );
  assert.equal(
    decryptContactValue(decisionCall.values[6] as Buffer, contactKey, {
      organizationId: principal.organizationId,
      contactKind: "other",
    }),
    "I accept the stated venue terms.",
  );

  const replay = await app.inject({
    method: "POST",
    url: `/booking-offers/${offerId}/accept`,
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(replay.json<{ data: { replayed: boolean } }>().data.replayed, true);

  const conflictingReplay = await app.inject({
    method: "POST",
    url: `/booking-offers/${offerId}/accept`,
    headers,
    payload: { acceptanceName: "Different person" },
  });
  assert.equal(conflictingReplay.statusCode, 409);

  const rejectionToken = "R".repeat(43);
  const rejected = await app.inject({
    method: "POST",
    url: `/booking-offers/${offerId}/reject`,
    headers: {
      "x-external-booking-token": rejectionToken,
      "idempotency-key": "customer-offer-reject-0001",
    },
    payload: {
      reasonCode: "terms_not_accepted",
      reason: "The proposed schedule does not work.",
      note: "Please contact me with alternative dates.",
    },
  });
  assert.equal(rejected.statusCode, 201);
  assert.equal(rejected.json<{ data: { decision: string } }>().data.decision, "rejected");
  assert.equal(mock.customerOfferDecisionCalls, 4);

  const rejectionCall = mock.commandCalls
    .filter((call) => call.sql.includes("eogp.decide_booking_offer_with_capability("))
    .at(-1);
  assert.ok(rejectionCall);
  assert.equal(rejectionCall.values[2], "rejected");
  assert.equal(rejectionCall.values[7], "terms_not_accepted");
  assert.equal(
    JSON.parse(decryptContactValue(rejectionCall.values[8] as Buffer, contactKey, {
      organizationId: principal.organizationId,
      contactKind: "other",
    })).reason,
    "The proposed schedule does not work.",
  );
});

test("reservation release delegates exact selected IDs to the permission-gated database command and replays idempotently", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const payload = {
    reservationIds: [
      "10000000-0000-4000-8000-000000000001",
      "10000000-0000-4000-8000-000000000002",
    ],
    reason: "booking_cancelled",
  };
  const headers = { "idempotency-key": "release-reservation-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { releasedCount: number } }>().data.releasedCount, 2);
  assert.equal(mock.reservationCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[3], principal.membershipId);

  const replay = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.reservationCalls, 1);

  const conflictingReuse = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload: { ...payload, reason: "different_reason" },
  });
  assert.equal(conflictingReuse.statusCode, 409);
  assert.equal(conflictingReuse.json().code, "IDEMPOTENCY_KEY_REUSED");
  assert.equal(mock.reservationCalls, 1);

  const differentBooking = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000002/reservations/release",
    headers,
    payload,
  });
  assert.equal(differentBooking.statusCode, 409);
  assert.equal(differentBooking.json().code, "IDEMPOTENCY_KEY_REUSED");
  assert.equal(mock.reservationCalls, 1);
});

test("event change submission encrypts private reason text before database persistence", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { encryptionKey: Buffer.alloc(32, 3) });
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-cancel-request-01" },
    payload: {
      changeKind: "cancel",
      expectedEventRevision: 1,
      reasonCode: "venue_unavailable",
      reasonInternal: "Confidential internal note",
      publicMessage: "The event has been cancelled.",
    },
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { status: string } }>().data.status, "submitted");
  const ciphertext = mock.commandCalls[0]?.values[6];
  assert.ok(Buffer.isBuffer(ciphertext));
  assert.equal((ciphertext as Buffer).subarray(0, 3).toString("ascii"), "EV1");
  assert.notEqual((ciphertext as Buffer).toString("utf8"), "Confidential internal note");
});

test("event reschedule without a replacement schedule is rejected before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-reschedule-0001" },
    payload: {
      changeKind: "reschedule",
      expectedEventRevision: 1,
      reasonCode: "schedule_change",
    },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(mock.changeCalls, 0);
});

test("postponement without a replacement schedule is rejected before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-postpone-0001" },
    payload: {
      changeKind: "postpone",
      expectedEventRevision: 1,
      reasonCode: "venue_disruption",
    },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(mock.changeCalls, 0);
});

test("custom notification audience requires explicit participation IDs", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/event-change-requests/91500000-0000-4000-8000-000000000001/execute",
    headers: { "idempotency-key": "event-execute-custom-01" },
    payload: { expectedEventRevision: 1, campaignAudience: "custom" },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(response.json<{ code: string }>().code, "CUSTOM_AUDIENCE_REQUIRED");
  assert.equal(mock.changeCalls, 0);
});

test("staff mutations fail closed without a verified session or accepted origin", async (t) => {
  const unauthenticated = makePool();
  const noSessionApi = makeApi(unauthenticated.pool, { authenticated: false });
  t.after(async () => noSessionApi.close());
  const unauthenticatedResponse = await noSessionApi.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-auth-check-01" },
    payload: { changeKind: "cancel", expectedEventRevision: 1, reasonCode: "test" },
  });
  assert.equal(unauthenticatedResponse.statusCode, 401);
  assert.equal(unauthenticated.commandCalls.length, 0);

  const originPool = makePool();
  const noOriginApi = makeApi(originPool.pool, { originValid: false });
  t.after(async () => noOriginApi.close());
  const originResponse = await noOriginApi.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-origin-check-01" },
    payload: { changeKind: "cancel", expectedEventRevision: 1, reasonCode: "test" },
  });
  assert.equal(originResponse.statusCode, 403);
  assert.equal(originPool.commandCalls.length, 0);
});


test("staff login, current-principal and logout routes use cookie sessions and explicit CSRF/origin checks", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { withSessionCallbacks: true });
  t.after(async () => app.close());

  const login = await app.inject({
    method: "POST",
    url: "/auth/session",
    headers: { origin: "https://staff.example.test" },
    payload: {
      email: "staff@example.test",
      password: "correct horse battery staple",
      organizationSlug: "event-owner",
    },
  });
  assert.equal(login.statusCode, 200);
  assert.equal(login.json().data.userId, principal.userId);
  const setCookie = login.headers["set-cookie"];
  assert.ok(Array.isArray(setCookie));
  assert.ok(setCookie.some((value) => value.startsWith("__Host-eventor_session=")));
  assert.ok(setCookie.some((value) => value.startsWith("__Host-eventor_csrf=")));

  const current = await app.inject({
    method: "GET",
    url: "/me",
    headers: { cookie: "__Host-eventor_session=" + "S".repeat(43) },
  });
  assert.equal(current.statusCode, 200);
  assert.equal(current.json().data.userId, principal.userId);

  const logout = await app.inject({
    method: "DELETE",
    url: "/auth/session",
    headers: { cookie: "__Host-eventor_session=" + "S".repeat(43) },
  });
  assert.equal(logout.statusCode, 204);
  const clearCookie = logout.headers["set-cookie"];
  assert.ok(Array.isArray(clearCookie));
  assert.ok(clearCookie.every((value) => value.includes("Max-Age=0")));
});

test("staff login rejects requests without the configured browser origin", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { withSessionCallbacks: true, loginOriginValid: false });
  t.after(async () => app.close());
  const login = await app.inject({
    method: "POST",
    url: "/auth/session",
    payload: {
      email: "staff@example.test",
      password: "correct horse battery staple",
      organizationSlug: "event-owner",
    },
  });
  assert.equal(login.statusCode, 403);
  assert.equal(login.json().code, "ORIGIN_REJECTED");
});


test("Resend webhook endpoint configuration returns a callback URL and stores its signing secret encrypted", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());

  const current = await app.inject({
    method: "GET",
    url: "/organization/delivery/email/resend-webhook",
  });
  assert.equal(current.statusCode, 200);
  assert.equal(current.json<{ data: { configured: boolean; callbackUrl: string } }>().data.configured, true);
  assert.equal(current.json<{ data: { callbackUrl: string } }>().data.callbackUrl,
    "https://eventor.example.test/api/webhooks/resend/95300000-0000-4000-8000-000000000001");

  const prepared = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/resend-webhook/prepare",
    headers: { "idempotency-key": "resend-webhook-prepare-01" },
    payload: {},
  });
  assert.equal(prepared.statusCode, 201);
  assert.equal(prepared.json<{ data: { callbackUrl: string; enabled: boolean } }>().data.enabled, false);
  assert.match(prepared.json<{ data: { callbackUrl: string } }>().data.callbackUrl, /^https:\/\/eventor\.example\.test\/api\/webhooks\/resend\//);
  assert.equal(mock.resendWebhookPrepareCalls, 1);

  const endpointId = "95300000-0000-4000-8000-000000000001";
  const activated = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/resend-webhook/activate",
    headers: { "idempotency-key": "resend-webhook-activate-01" },
    payload: { endpointId, signingSecret: resendWebhookSigningSecret },
  });
  assert.equal(activated.statusCode, 201);
  assert.equal(activated.json<{ data: { enabled: boolean } }>().data.enabled, true);
  assert.equal(mock.resendWebhookActivateCalls, 1);
  const ciphertext = mock.commandCalls.find(call => call.sql.includes("activate_organization_resend_webhook_endpoint"))?.values[3] as Buffer;
  assert.ok(Buffer.isBuffer(ciphertext));
  assert.equal(ciphertext.subarray(0, 4).toString("ascii"), "EDC1");
  assert.notEqual(ciphertext.toString("utf8"), resendWebhookSigningSecret);
});

test("public Resend webhook accepts a valid signature without a staff session and records the normalized delivery event", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { authenticated: false });
  t.after(async () => app.close());
  const endpointId = "95300000-0000-4000-8000-000000000001";
  const svixId = "msg_01JRESEND000000000000000001";
  const timestamp = String(Math.floor(Date.now() / 1000));
  const raw = JSON.stringify({
    type: "email.delivered",
    created_at: "2026-11-11T12:00:00.000Z",
    data: {
      email_id: "f53e1234-1234-4234-8234-123456789012",
      message_id: "<eventor-attempt-1@example.test>",
      to: ["guest@example.test"],
    },
  });
  const signature = createHmac("sha256", Buffer.from(resendWebhookSigningSecret.slice(6), "base64"))
    .update(`${svixId}.${timestamp}.${raw}`, "utf8")
    .digest("base64");
  const response = await app.inject({
    method: "POST",
    url: `/webhooks/resend/${endpointId}`,
    headers: {
      "content-type": "application/json",
      "svix-id": svixId,
      "svix-timestamp": timestamp,
      "svix-signature": `v1,${signature}`,
    },
    payload: raw,
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json<{ status: string; duplicate: boolean }>().status, "delivered");
  assert.equal(mock.resendWebhookResolveCalls, 1);
  assert.equal(mock.resendWebhookRecordCalls, 1);
  const call = mock.commandCalls.find(item => item.sql.includes("record_verified_resend_delivery_webhook"));
  assert.equal(call?.values[0], principal.organizationId);
  assert.equal(call?.values[1], endpointId);
  assert.equal(call?.values[2], svixId);
  assert.equal(call?.values[3], "<eventor-attempt-1@example.test>");
  assert.equal(call?.values[4], "delivered");
});

test("public Resend webhook rejects forged signatures before delivery-event ingestion", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { authenticated: false });
  t.after(async () => app.close());
  const timestamp = String(Math.floor(Date.now() / 1000));
  const raw = JSON.stringify({ type: "email.bounced", data: { message_id: "<eventor-attempt-2@example.test>", to: ["guest@example.test"] } });
  const response = await app.inject({
    method: "POST",
    url: "/webhooks/resend/95300000-0000-4000-8000-000000000001",
    headers: {
      "content-type": "application/json",
      "svix-id": "msg_01JRESEND000000000000000002",
      "svix-timestamp": timestamp,
      "svix-signature": "v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    },
    payload: raw,
  });
  assert.equal(response.statusCode, 401);
  assert.equal(mock.resendWebhookResolveCalls, 1);
  assert.equal(mock.resendWebhookRecordCalls, 0);
});

test("campaign list applies pagination and returns only the database permission projection", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/event-notification-campaigns?status=queued&limit=10&offset=20",
  });
  assert.equal(response.statusCode, 200);
  const payload = response.json<{ data: Array<{ campaignId: string }>; meta: { limit: number; offset: number; totalCount: number } }>();
  assert.equal(payload.data[0]?.campaignId, "94900000-0000-4000-8000-000000000001");
  assert.deepEqual(payload.meta, { limit: 10, offset: 20, totalCount: 1 });
  assert.equal(mock.campaignListCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], principal.membershipId);
  assert.equal(mock.commandCalls[0]?.values[2], "queued");
});

test("campaign progress and delivery report expose only operational attempt metadata", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const campaignId = "94900000-0000-4000-8000-000000000001";
  const progress = await app.inject({
    method: "GET",
    url: `/event-notification-campaigns/${campaignId}`,
  });
  assert.equal(progress.statusCode, 200);
  assert.equal(progress.json<{ data: { deliveryCounts: { sent: number } } }>().data.deliveryCounts.sent, 1);
  assert.equal(mock.campaignProgressCalls, 1);

  const deliveries = await app.inject({
    method: "GET",
    url: `/event-notification-campaigns/${campaignId}/deliveries?status=failed&limit=5&offset=0`,
  });
  assert.equal(deliveries.statusCode, 200);
  const payload = deliveries.json<{
    data: Array<{ status: string; failureCode: string; recipientReference: string }>;
    meta: { totalCount: number; counts: Record<string, number> };
  }>();
  assert.equal(payload.data[0]?.status, "failed");
  assert.equal(payload.data[0]?.failureCode, "SMTP_4XX");
  assert.equal(payload.meta.counts.failed, 1);
  assert.equal("email" in payload.data[0]!, false);
  assert.equal("phone" in payload.data[0]!, false);
  assert.equal("providerMessageReference" in payload.data[0]!, false);
  assert.equal(mock.campaignDeliveryListCalls, 1);
  assert.equal(mock.commandCalls[1]?.values[2], principal.membershipId);
  assert.equal(mock.commandCalls[1]?.values[3], "failed");
});

test("delivery reconciliation is an idempotent permission-gated operator command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const attemptId = "95000000-0000-4000-8000-000000000001";
  const payload = { resolution: "confirmed_sent", reason: "Provider dashboard confirms SMTP acceptance." };
  const headers = { "idempotency-key": "delivery-reconcile-0001" };
  const first = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/reconcile`,
    headers, payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string } }>().data.status, "sent");
  assert.equal(mock.deliveryReconcileCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], attemptId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
  const replay = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/reconcile`,
    headers, payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.deliveryReconcileCalls, 1);
});

test("operator delivery retry is a separate reasoned and idempotent command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const attemptId = "95000000-0000-4000-8000-000000000001";
  const payload = { reason: "Operator verified the remote server did not accept the message." };
  const headers = { "idempotency-key": "delivery-retry-0001" };
  const response = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/retry`,
    headers, payload,
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { status: string; attemptNumber: number } }>().data.status, "queued");
  assert.equal(mock.deliveryRetryCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], attemptId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
});

test("campaign review returns a restricted snapshot projection through the permission-gated database function", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/review",
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json<{ data: { status: string; actualRecipientCount: number } }>().data.status, "previewed");
  assert.equal(response.json<{ data: { actualRecipientCount: number } }>().data.actualRecipientCount, 2);
  assert.equal(mock.campaignReviewCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
});

test("campaign confirmation is idempotent and explicitly does not queue delivery", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "confirm-campaign-0001" };
  const payload = {};
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; deliveryQueued: boolean } }>().data.status, "confirmed");
  assert.equal(first.json<{ data: { deliveryQueued: boolean } }>().data.deliveryQueued, false);
  assert.equal(mock.campaignConfirmCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);

  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.campaignConfirmCalls, 1);
});

test("campaign confirmation rejects an invalid browser origin before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { originValid: false });
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers: { "idempotency-key": "confirm-campaign-0002" },
    payload: {},
  });
  assert.equal(response.statusCode, 403);
  assert.equal(mock.campaignConfirmCalls, 0);
});

test("organization SMTP configuration encrypts credentials before database persistence and is idempotent", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const payload = {
    host: "smtp.example.test",
    port: 587,
    transportSecurity: "starttls",
    authMode: "password",
    senderEmail: "events@example.test",
    senderName: "Eventor",
    credentials: {
      username: "mailer@example.test",
      password: "super-secret-smtp-password",
    },
  };
  const headers = { "idempotency-key": "smtp-config-version-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/configuration",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(mock.deliveryConfigCalls, 1);
  const storedCiphertext = mock.commandCalls[0]?.values[3];
  assert.ok(Buffer.isBuffer(storedCiphertext));
  assert.equal((storedCiphertext as Buffer).subarray(0, 4).toString("ascii"), "EDC1");
  assert.equal((storedCiphertext as Buffer).includes(Buffer.from(payload.credentials.password)), false);
  assert.equal(JSON.stringify(mock.commandCalls[0]?.values).includes(payload.credentials.password), false);

  const replay = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/configuration",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.deliveryConfigCalls, 1);
});

test("organization SMTP configuration projection never returns credentials", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/organization/delivery/email/configuration",
  });
  assert.equal(response.statusCode, 200);
  const data = response.json<{ data: Record<string, unknown> }>().data;
  assert.equal(data.credentialsConfigured, true);
  assert.equal("credentials" in data, false);
  assert.equal("password" in data, false);
});

test("SMTP test sends only to the requested address and idempotent replay does not resend", async (t) => {
  const mock = makePool();
  let verifyCalls = 0;
  let sendCalls = 0;
  let closeCalls = 0;
  const app = makeApi(mock.pool, {
    smtpTransportFactory: () => ({
      async verify() { verifyCalls += 1; return true; },
      async sendMail(message) {
        sendCalls += 1;
        assert.equal(message.to, "operator@example.test");
        return { messageId: "smtp-test-message", accepted: [message.to] };
      },
      close() { closeCalls += 1; },
    }),
  });
  t.after(async () => app.close());
  const headers = { "idempotency-key": "smtp-test-request-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/test",
    headers,
    payload: { recipient: "operator@example.test" },
  });
  assert.equal(first.statusCode, 200);
  assert.equal(first.json<{ data: { status: string; deliveryEnabled: boolean } }>().data.status, "succeeded");
  assert.equal(first.json<{ data: { deliveryEnabled: boolean } }>().data.deliveryEnabled, true);
  assert.equal(verifyCalls, 1);
  assert.equal(sendCalls, 1);
  assert.equal(closeCalls, 1);
  assert.equal(mock.deliveryTestCompletions, 1);

  const replay = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/test",
    headers,
    payload: { recipient: "operator@example.test" },
  });
  assert.equal(replay.statusCode, 200);
  assert.equal(replay.json<{ data: { replayed: boolean } }>().data.replayed, true);
  assert.equal(sendCalls, 1);
  assert.equal(mock.deliveryTestCompletions, 1);
});

test("campaign queueing is an explicit idempotent command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "queue-campaign-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/queue",
    headers,
    payload: {},
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; smsSuppressedCount: number } }>().data.status, "queued");
  assert.equal(first.json<{ data: { smsSuppressedCount: number } }>().data.smsSuppressedCount, 1);
  assert.equal(mock.campaignQueueCalls, 1);
  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/queue",
    headers,
    payload: {},
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.campaignQueueCalls, 1);
});

test("queued notification campaign can be cancelled before delivery starts", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "cancel-campaign-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/cancel",
    headers,
    payload: {},
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; suppressedAttempts: number } }>().data.status, "cancelled");
  assert.equal(first.json<{ data: { suppressedAttempts: number } }>().data.suppressedAttempts, 2);
  assert.equal(mock.campaignCancelCalls, 1);
  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/cancel",
    headers,
    payload: {},
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.campaignCancelCalls, 1);
});
