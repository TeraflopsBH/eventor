# API documentation

- [OpenAPI v0.2 draft](../implementation-design/v0.2/eogp_openapi_v0.2.yaml) — historical first contract snapshot.
- [API Contract Review v0.2](API_CONTRACT_REVIEW_v0.2.md) — historical structural review and successor gaps.
- [OpenAPI Successor Contract Design v0.3](API_DESIGN_v0.3.md) — route, principal/security and command semantics.
- [OpenAPI v0.3 YAML](openapi.v0.3.yaml) — canonical OpenAPI 3.1.1 contract draft.
- [Strict structural/security validator](../../scripts/validate_openapi.py) and [pinned validation dependencies](../../requirements-dev.txt).

The v0.2 contract remains unchanged. The v0.3 contract is a draft and its latest CI run passed the strict Eventor checks, pinned OpenAPI 3.1.1 validator and Redocly lint. API route implementations, generated-client verification and route-level contract tests remain outstanding.
