// A technical reference for creation forms, not a business numbering policy.
// Once persisted, the existing server commands keep codes stable.
export function generatedReferenceCode(prefix: string): string {
  return `${prefix}-${globalThis.crypto.randomUUID().replaceAll("-", "").slice(0,16).toUpperCase()}`;
}
