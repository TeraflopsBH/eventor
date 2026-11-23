// Match the canonical text of UUID identifiers accepted by the database.
export const uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
const uuidExpression = new RegExp(uuidPattern);

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && uuidExpression.test(value);
}
