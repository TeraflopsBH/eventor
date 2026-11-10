#!/usr/bin/env python3
"""Eventor OpenAPI structural guardrails; semantic validation is run separately."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

SPEC_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "docs/implementation-design/v0.3/eventor_openapi_v0.3.yaml"
)

with SPEC_PATH.open("r", encoding="utf-8") as handle:
    spec = yaml.safe_load(handle)

if not isinstance(spec, dict) or spec.get("openapi") != "3.1.1":
    raise SystemExit("Expected an OpenAPI 3.1.1 document.")

paths = spec.get("paths")
if not isinstance(paths, dict) or not paths:
    raise SystemExit("The OpenAPI document has no paths.")

schemes = set(spec.get("components", {}).get("securitySchemes", {}))
operation_ids: set[str] = set()
errors: list[str] = []

# Public operations are intentionally allow-listed. The two token-resolution
# operations are still authenticated by their dedicated bootstrap capability.
public_allowlist = {
    ("post", "/auth/session"),
    ("get", "/public/organizations/{organizationSlug}/booking-forms/{formCode}"),
    ("post", "/public/organizations/{organizationSlug}/booking-inquiries"),
}

for path, path_item in paths.items():
    placeholders = set(re.findall(r"\{([^}]+)\}", path))
    if not isinstance(path_item, dict):
        errors.append(f"{path}: path item is not an object")
        continue

    for method, operation in path_item.items():
        if method.lower() not in {
            "get", "post", "put", "patch", "delete", "options", "head", "trace"
        }:
            continue
        if not isinstance(operation, dict):
            errors.append(f"{method.upper()} {path}: operation is not an object")
            continue

        label = f"{method.upper()} {path}"
        operation_id = operation.get("operationId")
        if not operation_id:
            errors.append(f"{label}: missing operationId")
        elif operation_id in operation_ids:
            errors.append(f"{label}: duplicate operationId {operation_id}")
        else:
            operation_ids.add(operation_id)

        responses = operation.get("responses")
        if not isinstance(responses, dict) or not responses:
            errors.append(f"{label}: missing responses")

        operation_parameters = operation.get("parameters", [])
        declared_path_parameters = {
            p.get("name")
            for p in operation_parameters
            if isinstance(p, dict)
            and p.get("in") == "path"
            and p.get("required") is True
        }
        # Resolve local parameter references for the path-parameter check.
        parameter_components = spec.get("components", {}).get("parameters", {})
        for parameter in operation_parameters:
            if isinstance(parameter, dict) and "$ref" in parameter:
                ref = parameter["$ref"]
                match = re.fullmatch(r"#/components/parameters/([^/]+)", ref)
                if match:
                    resolved = parameter_components.get(match.group(1), {})
                    if resolved.get("in") == "path" and resolved.get("required") is True:
                        declared_path_parameters.add(resolved.get("name"))

        missing = placeholders - declared_path_parameters
        if missing:
            errors.append(f"{label}: undeclared required path parameter(s): {sorted(missing)}")

        security = operation.get("security")
        key = (method.lower(), path)
        if key in public_allowlist:
            if security != []:
                errors.append(f"{label}: public allow-listed operation must use security: []")
        elif not security:
            errors.append(f"{label}: non-allow-listed operation has no security requirement")

        if isinstance(security, list):
            for requirement in security:
                if not isinstance(requirement, dict):
                    errors.append(f"{label}: malformed security requirement")
                    continue
                unknown = set(requirement) - schemes
                if unknown:
                    errors.append(f"{label}: unknown security scheme(s): {sorted(unknown)}")

        if method.lower() == "post":
            refs = {
                p.get("$ref")
                for p in operation_parameters
                if isinstance(p, dict) and "$ref" in p
            }
            if "#/components/parameters/IdempotencyKey" not in refs:
                errors.append(f"{label}: POST command is missing Idempotency-Key")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print(
    f"OpenAPI structural checks passed: {len(paths)} paths, "
    f"{len(operation_ids)} unique operations, {len(schemes)} security schemes."
)
