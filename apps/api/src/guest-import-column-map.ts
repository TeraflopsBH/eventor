export const guestImportMaxColumns = 64;
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

export function mappedNameColumns(mapping: GuestImportColumnMapping, available: readonly GuestImportColumn[]) {
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
  return { headers, indices };
}

export function previewColumnLabel(label: string): string {
  return [...label.replace(/[\p{Cc}\p{Cs}]/gu, " ").trim()].slice(0, 200).join("");
}
