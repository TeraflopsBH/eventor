import type {
  BookingDraftAllocationOptions,
  BookingDraftSpaceLine,
  BookingDraftResourceLine,
} from "../../api";

export type BookingDraftSpaceAllocationInput = Omit<BookingDraftSpaceLine, "spaceLineId" | "requestedCapacity"> & { requestedCapacity?: number | "" | null };
export type BookingDraftResourceAllocationInput = Omit<BookingDraftResourceLine, "resourceLineId" | "lineCode" | "label">;

export type BookingDraftAllocationIssue =
  | { kind: "spaceRequired" }
  | { kind: "spaceUnavailable"; index: number }
  | { kind: "spaceIntervalInvalid"; index: number }
  | { kind: "spaceBlockKindInvalid"; index: number }
  | { kind: "spaceCapacityInvalid"; index: number }
  | { kind: "spaceCapacityExceeded"; index: number; capacity: number }
  | { kind: "spaceDuplicate"; index: number }
  | { kind: "resourceUnavailable"; index: number }
  | { kind: "resourceQuantityInvalid"; index: number }
  | { kind: "resourceCapacityExceeded"; index: number; capacity: number }
  | { kind: "resourceDuplicate"; index: number };

const blockKinds = new Set(["setup", "rehearsal", "event_use", "teardown", "buffer"]);
const hasExplicitOffset = (value: string): boolean =>
  /(?:Z|[+-](?:0\d|1\d|2[0-3]):?[0-5]\d)$/i.test(value.trim());

export function validateBookingDraftAllocations(
  spaces: BookingDraftSpaceAllocationInput[],
  resources: BookingDraftResourceAllocationInput[],
  options: BookingDraftAllocationOptions,
): BookingDraftAllocationIssue | null {
  const knownSpaces = new Map(options.spaces.map((space) => [space.venueSpaceId, space]));
  const seenSpaceIntervals = new Set<string>();

  for (let index = 0; index < spaces.length; index += 1) {
    const line = spaces[index];
    const space = knownSpaces.get(line.venueSpaceId);
    if (!space) return { kind: "spaceUnavailable", index };
    if (!hasExplicitOffset(line.startsAt) || !hasExplicitOffset(line.endsAt) ||
        !Number.isFinite(Date.parse(line.startsAt)) || !Number.isFinite(Date.parse(line.endsAt)) ||
        Date.parse(line.endsAt) <= Date.parse(line.startsAt)) {
      return { kind: "spaceIntervalInvalid", index };
    }
    if (!blockKinds.has(line.blockKind)) return { kind: "spaceBlockKindInvalid", index };
    if (line.requestedCapacity !== undefined && line.requestedCapacity !== null && line.requestedCapacity !== "") {
      if (!Number.isInteger(line.requestedCapacity) || line.requestedCapacity < 1) {
        return { kind: "spaceCapacityInvalid", index };
      }
      if (space.capacity !== null && line.requestedCapacity > space.capacity) {
        return { kind: "spaceCapacityExceeded", index, capacity: space.capacity };
      }
    }
    const identity = [line.venueSpaceId, line.blockKind, line.startsAt, line.endsAt].join("|");
    if (seenSpaceIntervals.has(identity)) return { kind: "spaceDuplicate", index };
    seenSpaceIntervals.add(identity);
  }

  const knownResources = new Map(options.resources.map((resource) => [resource.resourceTypeId, resource]));
  const seenResources = new Set<string>();
  for (let index = 0; index < resources.length; index += 1) {
    const line = resources[index];
    const resource = knownResources.get(line.resourceTypeId);
    if (!resource || resource.capacity < 1) return { kind: "resourceUnavailable", index };
    if (!Number.isInteger(line.requestedQuantity) || line.requestedQuantity < 1) {
      return { kind: "resourceQuantityInvalid", index };
    }
    if (line.requestedQuantity > resource.capacity) {
      return { kind: "resourceCapacityExceeded", index, capacity: resource.capacity };
    }
    if (seenResources.has(line.resourceTypeId)) return { kind: "resourceDuplicate", index };
    seenResources.add(line.resourceTypeId);
  }
  return null;
}

export function formatBookingDraftSpaceLines(
  lines: BookingDraftSpaceLine[],
): BookingDraftSpaceAllocationInput[] {
  return lines.map(({ venueSpaceId, startsAt, endsAt, blockKind, requestedCapacity }) => ({
    venueSpaceId, startsAt, endsAt, blockKind,
    ...(requestedCapacity === null || requestedCapacity === 0 ? {} : { requestedCapacity }),
  }));
}

export function formatBookingDraftResourceLines(
  lines: BookingDraftResourceLine[],
): BookingDraftResourceAllocationInput[] {
  return lines.map(({ resourceTypeId, requestedQuantity, values }) => ({
    resourceTypeId, requestedQuantity, values: { ...values },
  }));
}
