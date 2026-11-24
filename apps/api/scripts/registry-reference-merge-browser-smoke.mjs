// Reuse the complete contact merge journey and add source-reference review, transfer and removal guards.
process.env.EVENTOR_MERGE_REFERENCES = "1";
process.env.EVENTOR_CONTACT_MERGE_BROWSER_BASE_URL = process.env.EVENTOR_REFERENCE_MERGE_BROWSER_BASE_URL ?? "http://localhost:4173";
await import("./registry-contact-merge-browser-smoke.mjs");
