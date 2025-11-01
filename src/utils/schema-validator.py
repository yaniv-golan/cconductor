#!/usr/bin/env python3
"""Lightweight JSON schema validator for artifact contracts.

Supports the subset of JSON Schema used by CConductor artifact definitions:
- type checks for object, array, string, number, integer, boolean
- required field enforcement (recursive for nested objects)
- array item validation when an object schema is supplied
- allOf composition (shallow)

Returns exit code 0 when validation passes, non-zero otherwise.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List

JsonObj = Dict[str, Any]


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"schema-validator: file not found: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"schema-validator: invalid JSON in {path}: {exc}")


def type_name(value: Any) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    return "string"


def ensure_sequence(value: Any) -> List[Any]:
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def validate(schema: JsonObj, data: Any, path: str = "") -> List[str]:
    errors: List[str] = []

    # Handle type declaration for the current node
    expected_type = schema.get("type")
    if expected_type:
        type_matches = {
            "object": isinstance(data, dict),
            "array": isinstance(data, list),
            "string": isinstance(data, str),
            "boolean": isinstance(data, bool),
            "number": isinstance(data, (int, float)) and not isinstance(data, bool),
            "integer": isinstance(data, int) and not isinstance(data, bool),
            "null": data is None,
        }
        if expected_type in type_matches and not type_matches[expected_type]:
            actual = type_name(data)
            errors.append(f"{path or '<root>'}: expected {expected_type}, got {actual}")
            # Bail early if type mismatch prevents deeper inspection
            return errors

    # Required (objects)
    required_fields = ensure_sequence(schema.get("required"))
    if required_fields and not isinstance(data, dict):
        errors.append(f"{path or '<root>'}: required fields defined but value is not object")
        return errors

    for field in required_fields:
        if not isinstance(data, dict) or field not in data or data[field] is None:
            errors.append(f"{path + '.' if path else ''}{field}: missing required field")

    # Properties (objects)
    if isinstance(data, dict):
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for field, subschema in properties.items():
                if field not in data:
                    continue
                sub_path = f"{path + '.' if path else ''}{field}"
                errors.extend(validate(subschema, data[field], sub_path))

    # Array items
    if isinstance(data, list):
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for idx, item in enumerate(data):
                sub_path = f"{path}[{idx}]" if path else f"[{idx}]"
                errors.extend(validate(item_schema, item, sub_path))

    # allOf composition
    for subschema in ensure_sequence(schema.get("allOf")):
        if isinstance(subschema, dict):
            errors.extend(validate(subschema, data, path))

    return errors


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: schema-validator.py <schema-path> <data-path>")

    schema_path = Path(sys.argv[1])
    data_path = Path(sys.argv[2])

    schema = load_json(schema_path)
    data = load_json(data_path)

    errors = validate(schema, data)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
