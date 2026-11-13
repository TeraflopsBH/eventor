import assert from "node:assert/strict";
import test from "node:test";
import {
  validateBookingDraftAllocations,
  formatBookingDraftSpaceLines,
  formatBookingDraftResourceLines,
} from "../src/features/booking-drafts/bookingDraftAllocations.ts";

const options = {
  spaces: [{
    venueSpaceId: "11111111-1111-4111-8111-111111111111",
    venueId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    venueName: "Main venue",
    code: "HALL",
    name: "Main hall",
    spaceKind: "room",
    capacity: 120,
  }],
  resources: [{
    resourceTypeId: "22222222-2222-4222-8222-222222222222",
    code: "CHAIR",
    name: "Chair",
    unitLabel: "pcs",
    capacity: 300,
  }],
};

const space = (overrides = {}) => ({
  venueSpaceId: options.spaces[0].venueSpaceId,
  startsAt: "2027-01-18T09:00:00+01:00",
  endsAt: "2027-01-18T13:00:00+01:00",
  blockKind: "event_use",
  ...overrides,
});
const resource = (overrides = {}) => ({
  resourceTypeId: options.resources[0].resourceTypeId,
  requestedQuantity: 50,
  values: {},
  ...overrides,
});

test("accepts allocations backed by active catalogue definitions", () => {
  assert.equal(validateBookingDraftAllocations([space()], [resource()], options), null);
});

test("rejects spaces not present in the active venue catalogue", () => {
  assert.deepEqual(
    validateBookingDraftAllocations([space({ venueSpaceId: "missing" })], [], options),
    { kind: "spaceUnavailable", index: 0 },
  );
});

test("requires explicit offsets and a positive scheduling interval", () => {
  assert.deepEqual(
    validateBookingDraftAllocations([space({ startsAt: "2027-01-18T09:00:00" })], [], options),
    { kind: "spaceIntervalInvalid", index: 0 },
  );
  assert.deepEqual(
    validateBookingDraftAllocations([space({ endsAt: "2027-01-18T08:00:00+01:00" })], [], options),
    { kind: "spaceIntervalInvalid", index: 0 },
  );
});

test("enforces venue capacity and prevents duplicate identical space blocks", () => {
  assert.deepEqual(
    validateBookingDraftAllocations([space({ requestedCapacity: 121 })], [], options),
    { kind: "spaceCapacityExceeded", index: 0, capacity: 120 },
  );
  assert.deepEqual(
    validateBookingDraftAllocations([space(), space()], [], options),
    { kind: "spaceDuplicate", index: 1 },
  );
});

test("enforces resource catalogue membership, positive integer quantity and pool capacity", () => {
  assert.deepEqual(
    validateBookingDraftAllocations([], [resource({ resourceTypeId: "missing" })], options),
    { kind: "resourceUnavailable", index: 0 },
  );
  assert.deepEqual(
    validateBookingDraftAllocations([], [resource({ requestedQuantity: 1.5 })], options),
    { kind: "resourceQuantityInvalid", index: 0 },
  );
  assert.deepEqual(
    validateBookingDraftAllocations([], [resource({ requestedQuantity: 301 })], options),
    { kind: "resourceCapacityExceeded", index: 0, capacity: 300 },
  );
});

test("prevents duplicate resource-type lines and normalizes stored allocations", () => {
  assert.deepEqual(
    validateBookingDraftAllocations([], [resource(), resource()], options),
    { kind: "resourceDuplicate", index: 1 },
  );
  const existingSpace = {
    spaceLineId: "line-space",
    ...space(),
    requestedCapacity: null,
  };
  const existingResource = {
    resourceLineId: "line-resource",
    lineCode: "CHAIR-01",
    label: "Chair",
    ...resource(),
  };
  assert.deepEqual(formatBookingDraftSpaceLines([existingSpace]), [space()]);
  assert.deepEqual(formatBookingDraftResourceLines([existingResource]), [resource()]);
});
