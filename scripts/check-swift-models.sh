#!/usr/bin/env bash
#
# Type-checks every golden Swift model (LF-PaperTests/SwiftModel/Golden/*.swift.golden) in Swift 6
# mode, so the code JSON › Generate Swift Model writes is known to compile. The unit tests compare
# the generator's output with these files; this script can't be a unit test because the sandboxed
# test host can't run the compiler.
#
# Usage: scripts/check-swift-models.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
GOLDEN_DIR="LF-PaperTests/SwiftModel/Golden"

shopt -s nullglob
goldens=("$GOLDEN_DIR"/*.swift.golden)
if (( ${#goldens[@]} == 0 )); then
  echo "error: no golden files in $GOLDEN_DIR" >&2
  exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failed=0
for golden in "${goldens[@]}"; do
  name="$(basename "$golden" .golden)"
  # Each file on its own: every model declares its own root type.
  cp "$golden" "$work_dir/$name"
  if xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors "$work_dir/$name"; then
    echo "ok   $name"
  else
    echo "FAIL $name" >&2
    failed=$((failed + 1))
  fi
done

if (( failed > 0 )); then
  echo "$failed of ${#goldens[@]} generated models don't compile" >&2
  exit 1
fi
echo "All ${#goldens[@]} generated models compile."
