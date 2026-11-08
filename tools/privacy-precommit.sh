#!/usr/bin/env bash
# Pre-commit privacy guard: blocks any staged file that could contain the
# private exact-date accident data. Install with: make hooks
set -euo pipefail
PRIVATE_SHA256="1432347342ea0255915bd7c6faf34e56d8e14c3366ba1ab8b13aabbf4e85e8f8"   # sha256 of the private source file (one-way, safe to publish)
fail=0
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in
    *unfaelle*.csv|*.duckdb) echo "privacy: blocked file name: $f"; fail=1; continue;;
  esac
  if [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$PRIVATE_SHA256" ]; then
    echo "privacy: blocked private file (hash match): $f"; fail=1; continue
  fi
  case "$f" in tools/privacy-precommit.sh|tests/*|R/*|sql/*|*.md|*.qmd) continue;; esac
  if grep -qI -e 'timestampOriginal' -e 'ts_lokal' "$f" 2>/dev/null; then
    echo "privacy: blocked file containing exact-timestamp column: $f"; fail=1
  fi
done < <(git diff --cached --name-only --diff-filter=ACM -z)
if [ "$fail" -ne 0 ]; then
  echo "Commit abgebrochen: mögliche geschützte Detaildaten (siehe docs/datenschutz.md)."
  exit 1
fi
