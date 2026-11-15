#!/usr/bin/env python3
"""Strict structural/security checks for Eventor's OpenAPI 3.1 contract.

Run with: python3 scripts/validate_openapi.py [path]
Requires PyYAML 6.0.x.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate mapping keys."""


def construct_mapping(loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            mark = key_node.start_mark
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate key {key!r}",
                mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping
)


def fail(message: str) -> None:
    raise ValueError(message)


def resolve_pointer(document: Any, ref: str) -> Any:
    if not ref.startswith("#/"):
        fail(f"Only local component references are allowed: {ref}")
    current = document
    for raw in ref[2:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            try:
                current = current[int(token)]
            except (ValueError, IndexError):
                fail(f"Unresolved JSON pointer: {ref}")
        elif isinstance(current, dict) and token in current:
            current = current[token]
        else:
            fail(f"Unresolved JSON pointer: {ref}")
    return current


def dereference(document: dict[str, Any], value: Any) -> Any:
    seen: set[str] = set()
    while isinstance(value, dict) and "$ref" in value:
        ref = value["$ref"]
        if not isinstance(ref, str) or ref in seen:
            fail(f"Invalid or cyclic $ref: {ref}")
        seen.add(ref)
        value = resolve_pointer(document, ref)
    return value


def iter_refs(value: Any):
    if isinstance(value, dict):
        if "$ref" in value:
            yield value["$ref"]
        for child in value.values():
            yield from iter_refs(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_refs(child)


def operation_security(
    root_security: list[Any], operation: dict[str, Any]
) -> list[Any]:
    return operation.get("security", root_security)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/api/openapi.v0.3.yaml")
    document = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
    if not isinstance(document, dict):
        fail("OpenAPI document root must be a mapping")
    if document.get("openapi") != "3.1.1":
        fail(f"Expected OpenAPI 3.1.1, got {document.get('openapi')!r}")

    paths = document.get("paths")
    if not isinstance(paths, dict) or not paths:
        fail("paths must be a non-empty mapping")
    components = document.get("components")
    if not isinstance(components, dict):
        fail("components mapping is missing")

    # Resolve every local reference and reject remote or malformed references.
    refs = list(iter_refs(document))
    for ref in refs:
        if not isinstance(ref, str):
            fail(f"$ref must be a string, got {ref!r}")
        resolve_pointer(document, ref)

    root_security = document.get("security", [])
    if not isinstance(root_security, list):
        fail("root security must be an array")

    operation_ids: set[str] = set()
    operation_count = 0
    methods = {"get", "post", "put", "patch", "delete", "options", "head", "trace"}

    for route, path_item_raw in paths.items():
        if not isinstance(route, str) or not route.startswith("/"):
            fail(f"Invalid path key: {route!r}")
        path_item = dereference(document, path_item_raw)
        if not isinstance(path_item, dict):
            fail(f"Path item {route} must be a mapping")

        placeholders = set(re.findall(r"{([^{}]+)}", route))
        path_level_parameters = path_item.get("parameters", [])
        for method, operation_raw in path_item.items():
            if method.lower() not in methods:
                continue
            operation_count += 1
            operation = dereference(document, operation_raw)
            if not isinstance(operation, dict):
                fail(f"{method.upper()} {route}: operation must be a mapping")

            op_id = operation.get("operationId")
            if not isinstance(op_id, str) or not op_id.strip():
                fail(f"{method.upper()} {route}: operationId is required")
            if op_id in operation_ids:
                fail(f"Duplicate operationId: {op_id}")
            operation_ids.add(op_id)

            responses = operation.get("responses")
            if not isinstance(responses, dict) or not responses:
                fail(f"{method.upper()} {route}: non-empty responses mapping required")

            parameters = list(path_level_parameters or []) + list(operation.get("parameters", []) or [])
            resolved_parameters = [dereference(document, p) for p in parameters]
            path_parameters = {
                p.get("name")
                for p in resolved_parameters
                if isinstance(p, dict) and p.get("in") == "path"
            }
            missing = placeholders - path_parameters
            extra = path_parameters - placeholders
            if missing:
                fail(f"{method.upper()} {route}: missing path parameters {sorted(missing)}")
            if extra:
                fail(f"{method.upper()} {route}: extra path parameters {sorted(extra)}")
            for param in resolved_parameters:
                if isinstance(param, dict) and param.get("in") == "path" and param.get("required") is not True:
                    fail(f"{method.upper()} {route}: path parameter {param.get('name')} must be required")

            security = operation_security(root_security, operation)
            if not isinstance(security, list):
                fail(f"{method.upper()} {route}: security must be an array")
            schemes = set()
            for requirement in security:
                if not isinstance(requirement, dict):
                    fail(f"{method.upper()} {route}: malformed security requirement")
                schemes.update(requirement.keys())

            # Public intake and explicit capability routes must not inherit staff login.
            if (route.startswith("/public/") and route != "/public/booking-offers/{offerId}") or (route == "/auth/session" and method.lower() == "post"):
                if operation.get("security") != []:
                    fail(f"{method.upper()} {route}: anonymous public route must explicitly declare security: []")
            if route == "/public/booking-offers/{offerId}" and schemes != {"BookingActionCapability"}:
                fail(f"{method.upper()} {route}: public offer review must require only BookingActionCapability")

            if route.startswith("/external/booking-actions/"):
                expected = (
                    {"BookingActionBootstrap"}
                    if route == "/external/booking-actions/resolve"
                    else {"BookingActionCapability"}
                )
                if schemes != expected:
                    fail(f"{method.upper()} {route}: expected only {sorted(expected)}")
            if route == "/booking-offers/{offerId}/accept" and schemes != {"BookingActionCapability"}:
                fail(f"{method.upper()} {route}: must use only BookingActionCapability")

            if route.startswith("/guest/invitation/"):
                expected = (
                    {"GuestInvitationBootstrap"}
                    if route == "/guest/invitation/resolve"
                    else {"GuestInvitationCapability"}
                )
                if schemes != expected:
                    fail(f"{method.upper()} {route}: expected only {sorted(expected)}")

            if route.startswith("/guest-portal/"):
                expected = (
                    {"GuestPortalBootstrap"}
                    if route == "/guest-portal/access/resolve"
                    else {"GuestPortalCapability"}
                )
                if schemes != expected:
                    fail(f"{method.upper()} {route}: expected only {sorted(expected)}")

            if (route.startswith("/guest/") or route.startswith("/guest-portal/")) and "StaffSession" in schemes:
                fail(f"{method.upper()} {route}: guest route must not accept staff session as authority")

    # These separate principal types are security invariants of the contract.
    security_schemes = components.get("securitySchemes", {})
    expected_schemes = {
        "StaffSession",
        "GuestInvitationCapability",
        "GuestInvitationBootstrap",
        "GuestPortalCapability",
        "GuestPortalBootstrap",
        "BookingActionCapability",
        "BookingActionBootstrap",
    }
    missing_schemes = expected_schemes - set(security_schemes)
    if missing_schemes:
        fail(f"Missing security schemes: {sorted(missing_schemes)}")

    print(
        f"OpenAPI {document['openapi']}: {len(paths)} paths, "
        f"{operation_count} operations, {len(operation_ids)} unique operationIds, "
        f"{len(refs)} resolved references."
    )
    print("Path parameters, response declarations and public/guest capability boundaries passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, yaml.YAMLError) as exc:
        print(f"OpenAPI validation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
