#!/usr/bin/env bash
# Offline test of tools/persist-export.sh against a local bare "origin" (called from
# tests/testthat/test-persist-export.R). Prints "PASS <case>" per case, exits non-zero on the first failure.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/tools/persist-export.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export PERSIST_REMOTE=origin PERSIST_BRANCH=main

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "PASS $*"; }
g() { git -c user.name=seed -c user.email=seed@example.invalid -c init.defaultBranch=main "$@"; }

# --- fixtures ---------------------------------------------------------------------------------
mkdir "$root/origin.git" && g init -q --bare "$root/origin.git"
g clone -q "$root/origin.git" "$root/seed" 2> /dev/null
(
  cd "$root/seed"
  mkdir -p export/data export/dq export/trackx tools
  echo "old" > export/data/jahr.csv
  echo "old" > export/dq/dq_verlauf.csv
  echo "stale" > export/dq/gone.csv
  echo "x" > export/trackx/wetter_effekt.csv
  echo "code" > R_code.R
  g add -A && g commit -q -m "seed" && g push -q origin HEAD:main
)

make_artifact() {   # make_artifact <dir>: a valid artifact with changed data and a different trackx
  local a="$1"
  mkdir -p "$a/export/data" "$a/export/dq" "$a/export/trackx"
  echo "new" > "$a/export/data/jahr.csv"
  printf 'old\nnew\n' > "$a/export/dq/dq_verlauf.csv"
  echo "TAMPERED" > "$a/export/trackx/wetter_effekt.csv"
  (cd "$a" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
}

fresh_clone() {     # fresh_clone <name>: work tree as the checkout step leaves it
  g clone -q "$root/origin.git" "$root/$1" 2> /dev/null
  echo "$root/$1"
}

head_files() { g -C "$root/origin.git" ls-tree -r --name-only main | LC_ALL=C sort | tr '\n' ' '; }

# --- 1 normal run: replaces export/, keeps trackx, commits as the bot, touches nothing else ------
w=$(fresh_clone w1); make_artifact "$root/a1"
(cd "$w" && bash "$script" "$root/a1") > /dev/null
[ "$(g -C "$root/origin.git" show main:export/data/jahr.csv)" = "new" ] || fail "export not replaced"
[ "$(g -C "$root/origin.git" show main:export/trackx/wetter_effekt.csv)" = "x" ] || fail "trackx changed"
g -C "$root/origin.git" cat-file -e main:export/dq/gone.csv 2> /dev/null && fail "stale export file kept"
[ "$(g -C "$root/origin.git" show main:R_code.R)" = "code" ] || fail "file outside export/ touched"
msg=$(g -C "$root/origin.git" log -1 --format=%s main)
[[ "$msg" =~ ^chore\(data\):\ refresh\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ \[skip\ ci\]$ ]] || fail "bad message: $msg"
[ "$(g -C "$root/origin.git" log -1 --format=%an main)" = "github-actions[bot]" ] || fail "bad author"
ok "normal run replaces export/, restores trackx, bot commit, nothing outside export/"

# --- 2 unchanged export: no commit ----------------------------------------------------------------
before=$(g -C "$root/origin.git" rev-parse main)
w=$(fresh_clone w2)
(cd "$w" && bash "$script" "$root/a1") > /dev/null
[ "$(g -C "$root/origin.git" rev-parse main)" = "$before" ] || fail "empty refresh committed"
ok "unchanged export/ creates no commit"

# --- 3 main moved after checkout: reset to new main first, their commit survives -----------------
w=$(fresh_clone w3)
g clone -q "$root/origin.git" "$root/other" 2> /dev/null
(cd "$root/other" && echo "docs" > NOTES.md && g add -A && g commit -q -m "docs: note" && g push -q origin HEAD:main)
rm -rf "$root/a3"; make_artifact "$root/a3"; echo "newer" > "$root/a3/export/data/jahr.csv"
(cd "$root/a3" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
(cd "$w" && bash "$script" "$root/a3") > /dev/null
[ "$(g -C "$root/origin.git" show main:NOTES.md)" = "docs" ] || fail "concurrent commit lost"
[ "$(g -C "$root/origin.git" show main:export/data/jahr.csv)" = "newer" ] || fail "export not applied on new main"
ok "main moved since checkout: applied on top of the new main"

# --- 4 push race: first push is rejected, second attempt succeeds ---------------------------------
cat > "$root/origin.git/hooks/pre-receive" << EOF
#!/bin/sh
if [ ! -e "$root/rejected-once" ]; then touch "$root/rejected-once"; echo "simulated race" >&2; exit 1; fi
EOF
chmod +x "$root/origin.git/hooks/pre-receive"
w=$(fresh_clone w4); rm -rf "$root/a4"; make_artifact "$root/a4"; echo "retry" > "$root/a4/export/data/jahr.csv"
(cd "$root/a4" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
(cd "$w" && bash "$script" "$root/a4") > /dev/null 2>&1
[ "$(g -C "$root/origin.git" show main:export/data/jahr.csv)" = "retry" ] || fail "retry did not land"
rm "$root/origin.git/hooks/pre-receive"
ok "lost push race is retried once"

# --- 5 permanent push failure fails the job -------------------------------------------------------
printf '#!/bin/sh\nexit 1\n' > "$root/origin.git/hooks/pre-receive"; chmod +x "$root/origin.git/hooks/pre-receive"
w=$(fresh_clone w5); rm -rf "$root/a5"; make_artifact "$root/a5"; echo "never" > "$root/a5/export/data/jahr.csv"
(cd "$root/a5" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
if (cd "$w" && bash "$script" "$root/a5") > /dev/null 2>&1; then fail "two failed pushes did not fail"; fi
rm "$root/origin.git/hooks/pre-receive"
ok "two failed pushes fail the job"

# --- 6 rejected artifacts: nothing is pushed ------------------------------------------------------
before=$(head_files)
reject() {          # reject <case> <artifact-dir>
  w=$(fresh_clone "w_$1")
  if (cd "$w" && bash "$script" "$2") > /dev/null 2>&1; then fail "artifact accepted: $1"; fi
  [ "$(head_files)" = "$before" ] || fail "tree changed after rejecting $1"
  ok "rejected: $1"
}
make_artifact "$root/b1"; echo "tamper" >> "$root/b1/export/data/jahr.csv"; reject "checksum mismatch" "$root/b1"
make_artifact "$root/b2"; echo "extra" > "$root/b2/export/data/extra.csv"; reject "file not in SHA256SUMS" "$root/b2"
make_artifact "$root/b3"; mkdir "$root/b3/outside"; echo "x" > "$root/b3/export/README.md"
(cd "$root/b3" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS); reject "unexpected top-level path" "$root/b3"
make_artifact "$root/b4"; echo "id,t" > "$root/b4/export/data/unfaelle_roh.csv"
(cd "$root/b4" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS); reject "accident-level csv" "$root/b4"
make_artifact "$root/b5"; ln -s /etc/passwd "$root/b5/export/data/link.csv"
(cd "$root/b5" && find export -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS 2> /dev/null || true); reject "symlink" "$root/b5"
make_artifact "$root/b6"; rm "$root/b6/SHA256SUMS"; reject "missing SHA256SUMS" "$root/b6"

echo "ALL OK"
