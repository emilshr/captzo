#!/usr/bin/env bash
# Expand a portable (repo-relative) SwiftLint baseline to absolute file:// URLs
# for the current working directory, then run SwiftLint.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v swiftlint >/dev/null; then
  echo "warning: SwiftLint not installed; run brew install swiftlint."
  exit 0
fi

BASELINE_SRC="${ROOT}/.swiftlint.baseline"
BASELINE_ABS="${TMPDIR:-/tmp}/scratio.swiftlint.baseline.$$.json"

python3 - "$BASELINE_SRC" "$BASELINE_ABS" "$ROOT" <<'PY'
import json, pathlib, sys

src, dst, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
data = json.loads(src.read_text())
for entry in data:
    loc = entry["violation"]["location"]
    file_ref = loc["file"]
    if file_ref.startswith("file://"):
        continue
    loc["file"] = (root / file_ref).resolve().as_uri()
dst.write_text(json.dumps(data, separators=(",", ":")))
PY

cleanup() { rm -f "$BASELINE_ABS"; }
trap cleanup EXIT

swiftlint lint --strict --baseline "$BASELINE_ABS" scratio
