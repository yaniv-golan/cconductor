#!/usr/bin/env python3
"""
emit-academic-argument-events.py

Generates Argument Event Graph payloads for the academic researcher findings.
"""

import base64
import hashlib
import json
import sys
from pathlib import Path
from typing import Dict, List, Any


def _base32_of_hex(hex_value: str) -> str:
    return base64.b32encode(bytes.fromhex(hex_value)).decode("ascii").lower().rstrip("=")


def make_id(prefix: str, seed: str, mission_step: str = "", length: int = 12) -> str:
    scope = f"{mission_step}::{seed}" if mission_step else seed
    digest = hashlib.sha256(scope.encode("utf-8")).hexdigest()
    return f"{prefix}-{_base32_of_hex(digest)[:length]}"


def clean_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in data.items() if v not in (None, "", [], {})}


def build_events_for_file(path: Path) -> List[Dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    task_id = data.get("task_id") or path.stem.split("-", 1)[-1]
    mission_step = f"S.academic.{task_id}"
    events: List[Dict[str, Any]] = []

    claims = data.get("claims") or []
    for claim in claims:
        statement = (claim.get("statement") or "").strip()
        if not statement:
            continue

        claim_id = make_id("clm", statement, mission_step)
        sources = claim.get("sources") or []
        source_ids: List[str] = []

        for idx, source in enumerate(sources):
            url = (source.get("url") or "").strip()
            seed = url or f"{statement}::{idx}"
            source_id = make_id("src", seed)
            source_ids.append(source_id)

            evidence_seed = f"{statement}::{seed}"
            evidence_id = make_id("evd", evidence_seed, mission_step)

            evidence_payload = clean_dict({
                "evidence_id": evidence_id,
                "claim_id": claim_id,
                "role": source.get("role") or "support",
                "statement": source.get("relevant_quote") or source.get("title") or statement,
                "quality": claim.get("evidence_quality"),
                "source": clean_dict({
                    "source_id": source_id,
                    "url": url or None,
                    "title": source.get("title"),
                    "credibility": source.get("credibility"),
                    "date": source.get("date"),
                })
            })

            events.append({
                "event_type": "evidence",
                "mission_step": mission_step,
                "payload": evidence_payload
            })

        claim_payload = clean_dict({
            "claim_id": claim_id,
            "text": statement,
            "confidence": claim.get("confidence"),
            "evidence_quality": claim.get("evidence_quality"),
            "sources": [{"source_id": sid} for sid in source_ids] if source_ids else None,
            "tags": claim.get("tags"),
            "related_entities": claim.get("related_entities"),
            "metadata": claim.get("source_context")
        })

        events.append({
            "event_type": "claim",
            "mission_step": mission_step,
            "payload": claim_payload
        })

    return events


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: emit-academic-argument-events.py <session_dir>", file=sys.stderr)
        return 1

    session_dir = Path(sys.argv[1])
    findings_dir = session_dir / "work" / "academic-researcher"

    if not findings_dir.exists():
        print("[]")
        return 0

    events: List[Dict[str, Any]] = []
    for findings_file in sorted(findings_dir.glob("findings-*.json")):
        try:
            events.extend(build_events_for_file(findings_file))
        except Exception as exc:  # pylint: disable=broad-except
            print(f"Warning: failed to build events for {findings_file}: {exc}", file=sys.stderr)

    print(json.dumps(events, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
