# API documentation

- [OpenAPI v0.2 draft](../implementation-design/v0.2/eogp_openapi_v0.2.yaml) — historical first contract snapshot.
- [API Contract Review v0.2](API_CONTRACT_REVIEW_v0.2.md) — historical structural review and successor gaps.
- [OpenAPI Successor Contract Design v0.3](API_DESIGN_v0.3.md) — route, principal/security and command semantics.
- [OpenAPI v0.3 YAML](openapi.v0.3.yaml) — canonical OpenAPI 3.1.1 contract draft.
- [Strict structural/security validator](../../scripts/validate_openapi.py) and [pinned validation dependencies](../../requirements-dev.txt).

The v0.2 contract remains unchanged. The v0.3 contract is the canonical draft and is checked by the strict Eventor validator, the pinned OpenAPI 3.1.1 validator and Redocly lint. The first Fastify command module is in [apps/api](../../apps/api/README.md): it implements selected booking-reservation release and organizer event-change submit/approve/reject/execute routes, regenerates TypeScript declarations from the OpenAPI YAML, and includes route tests. The module requires a host-supplied verified staff-session authenticator and CSRF/origin verifier; it does not invent an authentication/session store. The transactional outbox records notification dispatch requests only; campaign preparation and delivery workers remain outstanding.
