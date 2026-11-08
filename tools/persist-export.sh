#!/usr/bin/env bash
# Persist the export/ of a successful scheduled run into main (job `persist`, .github/workflows/pipeline.yml).
#
#   persist-export.sh <artifact-dir>
#
# <artifact-dir> holds `export/` and `SHA256SUMS` as staged by the build job AFTER lint, tests, the DQ gate,
# the privacy gate and the Track X check had passed. This script
#   1. verifies the artifact byte for byte against SHA256SUMS and against a path allowlist,
#   2. resets the work tree to the current origin/main (main may have moved since checkout),
#   3. replaces export/ (never export/trackx), commits and pushes, only if export/ changed,
#   4. refuses to commit anything outside export/,
#   5. retries once from step 2 if the push loses a race.
#
# Environment (defaults are the CI values; the test overrides them):
#   PERSIST_REMOTE  git remote            (origin)
#   PERSIST_BRANCH  branch to update      (main)
set -euo pipefail

art="${1:?usage: persist-export.sh <artifact-dir>}"
remote="${PERSIST_REMOTE:-origin}"
branch="${PERSIST_BRANCH:-main}"
allowed_top='data dq meta modell trackx'

die() { echo "persist: $*" >&2; exit 1; }

verify_artifact() {
  [ -d "$art/export" ] || die "artifact has no export/ directory"
  [ -f "$art/SHA256SUMS" ] || die "artifact has no SHA256SUMS"
  # integrity: exactly the content the build job staged after its gates
  (cd "$art" && sha256sum --check --strict --quiet SHA256SUMS) || die "checksum mismatch"
  local listed found
  listed=$(sed 's/^[0-9a-f]\{64\}  //' "$art/SHA256SUMS" | LC_ALL=C sort)
  found=$(cd "$art" && find export -type f | LC_ALL=C sort)
  [ "$listed" = "$found" ] || die "artifact files differ from SHA256SUMS"
  # no symlinks, devices, sockets
  [ -z "$(cd "$art" && find export ! -type f ! -type d)" ] || die "artifact contains non-regular files"
  # allowlist: known top-level directories only
  local top
  while IFS= read -r top; do
    case " $allowed_top " in *" $top "*) ;; *) die "unexpected path in artifact: export/$top";; esac
  done < <(cd "$art/export" && ls -A)
  # privacy shape guards (the full privacy gate ran in the build job on the same bytes)
  local bad
  bad=$(cd "$art" && find export -type f \( -iname '*unfaelle*.csv' -o -name '*.duckdb' -o -name '*.duckdb.wal' \
        -o -name '*.rds' -o -name '*.db' \) | head -5)
  [ -z "$bad" ] || die "forbidden file(s) in artifact: $bad"
  echo "persist: artifact verified ($(wc -l < "$art/SHA256SUMS") files)"
}

apply_artifact() {
  git fetch --quiet "$remote" "$branch"
  git checkout --quiet -B "$branch" "$remote/$branch"
  git reset --quiet --hard "$remote/$branch"
  mkdir -p export
  # replace everything except Track X (private-derived, committed, never touched by CI)
  find export -mindepth 1 -maxdepth 1 ! -name trackx -exec rm -rf {} +
  local d
  for d in "$art"/export/*/; do
    [ "$(basename "$d")" = trackx ] && continue
    cp -a "$d" "export/$(basename "$d")"
  done
  # belt and braces: Track X is byte-identical to the checkout
  if git ls-files --error-unmatch export/trackx > /dev/null 2>&1; then
    git checkout "$remote/$branch" -- export/trackx
  fi
  git clean -fdq -- export/trackx
  git diff --quiet "$remote/$branch" -- export/trackx || die "export/trackx differs from main"
}

commit_and_push() {
  if [ -z "$(git status --porcelain -- export/)" ]; then
    echo "persist: export/ unchanged, nothing to commit"
    return 2
  fi
  git add -A -- export || return 1
  # nothing but export/ may be part of the commit or left dirty in the work tree
  local outside
  outside=$(git status --porcelain --untracked-files=all | sed 's/^...//' | grep -v '^export/' || true)
  [ -z "$outside" ] || die "changes outside export/: $outside"
  local staged
  staged=$(git diff --cached --name-only | grep -v '^export/' || true)
  [ -z "$staged" ] || die "staged paths outside export/: $staged"
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit --quiet -m "chore(data): refresh $(date -u +%F) [skip ci]" || return 1
  git push --quiet "$remote" "HEAD:$branch"
}

verify_artifact
for attempt in 1 2; do
  apply_artifact
  rc=0
  commit_and_push || rc=$?
  case "$rc" in
    0) echo "persist: pushed (attempt $attempt)"; exit 0 ;;
    2) exit 0 ;;
    *) echo "persist: push failed (attempt $attempt), re-applying on the new $branch" >&2 ;;
  esac
done
die "push failed twice"
