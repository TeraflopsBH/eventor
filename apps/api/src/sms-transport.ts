/**
 * Provider-neutral SMS contract. Eventor intentionally ships no vendor adapter:
 * an adapter must be explicitly installed and selected by provider code before
 * SMS recipients can be enabled for delivery.
 */
export interface SmsProviderSettings {
  readonly provider: string;
  readonly settings: Readonly<Record<string, string | number | boolean>>;
}

export interface SmsProviderCredentials {
  readonly values: Readonly<Record<string, string>>;
}

export interface SmsSendRequest {
  readonly to: string;
  readonly senderId: string;
  readonly text: string;
  /** Stable per-recipient attempt key for providers that support idempotency. */
  readonly idempotencyKey: string;
}

export interface SmsSendResult {
  readonly providerMessageReference: string;
  readonly accepted: boolean;
}

export type SmsFailureKind = "temporary" | "permanent" | "uncertain";

export interface SmsTransportAdapter {
  readonly providerCode: string;
  verify(
    settings: SmsProviderSettings,
    credentials: SmsProviderCredentials,
  ): Promise<void>;
  send(
    settings: SmsProviderSettings,
    credentials: SmsProviderCredentials,
    request: SmsSendRequest,
  ): Promise<SmsSendResult>;
  classifyFailure(error: unknown): SmsFailureKind;
}

export type SmsTransportRegistry = ReadonlyMap<string, SmsTransportAdapter>;

export function resolveSmsTransport(
  registry: SmsTransportRegistry,
  providerCode: string,
): SmsTransportAdapter {
  const adapter = registry.get(providerCode);
  if (!adapter || adapter.providerCode !== providerCode) {
    throw new Error(`No SMS transport adapter is installed for provider "${providerCode}".`);
  }
  return adapter;
}
