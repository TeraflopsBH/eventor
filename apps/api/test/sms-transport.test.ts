import assert from "node:assert/strict";
import test from "node:test";
import { resolveSmsTransport, type SmsTransportAdapter } from "../src/sms-transport.js";

test("SMS adapter registry resolves only an explicitly installed matching provider", () => {
  const adapter: SmsTransportAdapter = {
    providerCode: "example-adapter",
    async verify() {},
    async send(_settings, _credentials, request) {
      return { providerMessageReference: request.idempotencyKey, accepted: true };
    },
    classifyFailure() { return "temporary"; },
  };
  const registry = new Map([[adapter.providerCode, adapter]]);
  assert.equal(resolveSmsTransport(registry, "example-adapter"), adapter);
  assert.throws(() => resolveSmsTransport(registry, "unconfigured-provider"), /No SMS transport adapter is installed/);
});
