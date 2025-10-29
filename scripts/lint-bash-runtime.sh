#!/usr/bin/env bash
# Detect direct `bash` invocations that bypass the configured runtime.
# Ensures child processes inherit the Homebrew bash (>=4).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT_ROOT="$PROJECT_ROOT" python3 <<'PY'
import pathlib
import re
import sys
import os

project_root = pathlib.Path(os.environ["PROJECT_ROOT"]).resolve()
target_dir = project_root / "src"

violations = []

bash_runtime_patterns = (
    "bash ${CCONDUCTOR_BASH_RUNTIME",
    "bash ${BASH_RUNTIME",
    "bash $CCONDUCTOR_BASH_RUNTIME",
    "bash $BASH_RUNTIME",
)

for path in sorted(target_dir.rglob("*.sh")):
    text = path.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), 1):
        if not re.search(r"\bbash\s+", line):
            continue

        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("#!"):
            continue
        if "command -v bash" in line:
            continue
        if "brew install bash" in line:
            continue
        if "| bash" in line:
            continue

        in_single = False
        in_double = False
        prev = ""
        idx = 0
        while idx < len(line):
            ch = line[idx]
            if ch == "'" and not in_double and prev != "\\":
                in_single = not in_single
            elif ch == '"' and not in_single and prev != "\\":
                in_double = not in_double
            elif (
                ch == "b"
                and not in_single
                and not in_double
                and line.startswith("bash", idx)
            ):
                before = line[idx - 1] if idx > 0 else ""
                after = line[idx + 4] if idx + 4 < len(line) else ""
                if (
                    not re.match(r"[A-Za-z0-9_]", before or " ")
                    and not re.match(r"[A-Za-z0-9_]", after or " ")
                ):
                    token_rest = line[idx:]
                    if not token_rest.startswith(bash_runtime_patterns):
                        violations.append(f"{path.relative_to(project_root)}:{lineno}:{line.rstrip()}")
                        break
                idx += 3
            prev = ch
            idx += 1

if violations:
    print("bash runtime lint: found direct 'bash' invocations;", file=sys.stderr)
    print('use "${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}" instead.', file=sys.stderr)
    for violation in violations:
        print(violation, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
