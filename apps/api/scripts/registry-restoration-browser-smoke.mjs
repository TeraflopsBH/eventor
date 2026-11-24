process.env.EVENTOR_MERGE_REFERENCES="1";
process.env.EVENTOR_REVIEWED_RESTORATION="1";
process.env.EVENTOR_CONTACT_MERGE_BROWSER_BASE_URL=process.env.EVENTOR_RESTORATION_BROWSER_BASE_URL ?? "http://localhost:4173";
await import("./registry-contact-merge-browser-smoke.mjs");
