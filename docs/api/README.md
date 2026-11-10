# API documentation

- [OpenAPI v0.2 draft](../implementation-design/v0.2/eogp_openapi_v0.2.yaml) — historical first contract snapshot.
- [API Contract Review v0.2](API_CONTRACT_REVIEW_v0.2.md) — structural checks, security baseline and successor gaps.
- [OpenAPI Successor Contract Design v0.3](API_DESIGN_v0.3.md) — route/security/command design.
- [OpenAPI v0.3 YAML](../implementation-design/v0.3/eventor_openapi_v0.3.yaml) — concrete 3.1.1 contract draft.
- [Structural guardrails](../../scripts/api/check_openapi.py) and [pinned validator](../../requirements-dev.txt).

The v0.2 contract remains unchanged. The v0.3 YAML is a draft and must pass the pinned full validator and custom security/operation/path-parameter checks in CI before it is considered accepted.
