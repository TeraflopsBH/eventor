export const guestImportMaxColumns = 64;
export const sourceCodePattern = "^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$";
export const sourceReferencePattern = "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$";
const nameHeaders = [
  ["firstName", "first_name"], ["lastName", "last_name"], ["displayName", "display_name"], ["preferredName", "preferred_name"],
] as const;

export interface GuestImportColumnMapping {
  firstName: number;
  lastName: number;
  displayName?: number;
  preferredName?: number;
}

export interface GuestImportColumn {
  index: number;
  label: string;
}

export class GuestImportColumnError extends Error {}

export function mappedGuestColumns(
  mapping: GuestImportColumnMapping, available: readonly GuestImportColumn[], referenceColumn?: number,
) {
  const columns = new Set(available.map(({ index }) => index));
  const selected = new Set<number>();
  const headers: string[] = [];
  const indices: number[] = [];
  for (const [field, header] of nameHeaders) {
    const index = mapping[field];
    if (index === undefined && (field === "displayName" || field === "preferredName")) continue;
    if (index === undefined || !columns.has(index) || selected.has(index)) {
      throw new GuestImportColumnError("Select distinct available columns for the guest name fields.");
    }
    selected.add(index);
    headers.push(header);
    indices.push(index);
  }
  if (referenceColumn !== undefined) {
    if (!columns.has(referenceColumn) || selected.has(referenceColumn)) {
      throw new GuestImportColumnError("Select a separate available column for the source reference.");
    }
    headers.push("source_reference");
    indices.push(referenceColumn);
  }
  return { headers, indices };
}

export function previewColumnLabel(label: string): string {
  return [...label.replace(/[\p{Cc}\p{Cs}]/gu, " ").trim()].slice(0, 200).join("");
}
