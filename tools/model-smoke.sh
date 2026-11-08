#!/bin/sh
# Budget smoke run for the severity ladder. Inside the project container, repo root as cwd, with the host's
# /usr/bin/time mounted (podman run ... -v /usr/bin/time:/usr/bin/time:ro). Writes config/modell_smoke.json.
# Usage: tools/model-smoke.sh [fraction]   (default 0.2; set ZH_THREADS to the thread count to project for)
set -eu
frac="${1:-0.2}"
tmp="$(mktemp -d)"
for phase in tuning bootstrap; do
  /usr/bin/time -v -o "$tmp/$phase.time" Rscript tools/model_smoke.R "$phase" "$frac" "$tmp/$phase.json"
  # cgroup peak covers all worker processes of the container
  cat /sys/fs/cgroup/memory.peak > "$tmp/$phase.cg" 2>/dev/null || echo 0 > "$tmp/$phase.cg"
done
Rscript tools/model_smoke_merge.R "$tmp" "$frac"
