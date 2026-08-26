#!/usr/bin/env bash
# spike_sweep.sh — render the diorama spike across a parameter sweep, so the
# S0 composition question is judged from evidence rather than from one framing
# that happened to be checked in.
#
#   ./tools/spike_sweep.sh                     # ticket #17 AC12 set
#   ./tools/spike_sweep.sh --out docs/shots/s0 # write somewhere else
#   ./tools/spike_sweep.sh --only hero         # one frame while iterating
#   ./tools/spike_sweep.sh --list              # names, render nothing
#
# It inherits capture.sh's hard-won rules rather than reinventing them:
#
#  1. `--headless` rasterises nothing while still writing valid PNGs, so every
#     frame goes through tools/spike_shot.gd's blank-frame guard and a run is
#     failed, not warned about, when a frame comes back empty.
#  2. Frames are committed to the branch, so the run is byte-capped and cleans
#     up after itself rather than leaving a half-set next to a warning.
#  3. A hung Godot is worse than a failed one. Every render is bounded.
#
# What it adds over capture.sh: parameter overrides per frame (spike_shot.gd
# takes key=value), and a build-time line per frame, because AC10 wants the
# cost reported and a sweep is where regressions in it show up first.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
OUT="docs/shots/s0-spike"
WIDTH=1280
HEIGHT=720
MAX_BYTES="${SPIKE_MAX_BYTES:-6291456}"
TIMEOUT_SECS="${SPIKE_TIMEOUT:-300}"
ONLY=""
LIST_ONLY=0

# --- the sweep ---------------------------------------------------------------
# name|description|overrides
# Ordered so the canonical framing is frame 1: a reviewer who looks at exactly
# one image should be looking at the one the ticket is actually asking about.
SHOTS=(
  "canonical|the gameplay framing, default parameters|"
  "exaggeration-low|elevation_exaggeration 0.6 — relief nearly flat|elevation_exaggeration=0.6"
  "exaggeration-high|elevation_exaggeration 2.6 — relief pushed hard|elevation_exaggeration=2.6"
  "fov-15|long lens, narrow end of the intent's 15-30 range|fov_horizontal_deg=15.0"
  "fov-30|wide end of the intent's range|fov_horizontal_deg=30.0"
  "hero|framing where the hero structure dominates|camera_focus_hero=true camera_distance=26.0 camera_pitch_deg=20.0 fov_horizontal_deg=20.0"
)

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [ "$LIST_ONLY" -eq 1 ]; then
  for entry in "${SHOTS[@]}"; do
    IFS='|' read -r name desc _ <<<"$entry"
    printf '  %-18s %s\n' "$name" "$desc"
  done
  exit 0
fi

# `timeout` is coreutils and absent on a stock macOS; gtimeout if brewed.
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT=(timeout "$TIMEOUT_SECS")
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT=(gtimeout "$TIMEOUT_SECS")
else
  # `env` is a no-op prefix: keeps the call site uniform, and an empty array
  # would trip `set -u` on the bash 3.2 that ships with macOS.
  TIMEOUT=(env)
  echo "[spike-sweep] note: no timeout(1); a hung render will not be bounded" >&2
fi

mkdir -p "$OUT"
written=()
failed=0

cleanup_partial() {
  echo "[spike-sweep] removing this run's frames rather than leaving a partial set" >&2
  for f in "${written[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
}

for entry in "${SHOTS[@]}"; do
  IFS='|' read -r name desc overrides <<<"$entry"
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  path="$OUT/spike-$name.png"
  echo "[spike-sweep] $name — $desc"
  # shellcheck disable=SC2086
  if ! out=$("${TIMEOUT[@]}" "$GODOT" --path . --resolution "${WIDTH}x${HEIGHT}" \
        -s tools/spike_shot.gd -- "$path" $overrides 2>&1); then
    echo "[spike-sweep] FAILED: $name" >&2
    echo "$out" | grep -E 'SPIKE-FAIL|ERROR' >&2 || echo "$out" | tail -5 >&2
    failed=1
    break
  fi
  if ! grep -q '^SPIKE-SHOT ' <<<"$out"; then
    echo "[spike-sweep] FAILED: $name produced no verified frame" >&2
    grep -E 'SPIKE-FAIL' <<<"$out" >&2 || true
    failed=1
    break
  fi
  grep -E '^SPIKE-(BUILD-MS|FRAME-MS)' <<<"$out" | sed 's/^/    /'
  written+=("$path")
done

if [ "$failed" -ne 0 ]; then
  cleanup_partial
  exit 1
fi

total=0
for f in "${written[@]:-}"; do
  [ -n "$f" ] || continue
  size=$(wc -c <"$f")
  total=$((total + size))
done
if [ "$total" -gt "$MAX_BYTES" ]; then
  echo "[spike-sweep] $total bytes exceeds the ${MAX_BYTES}-byte cap." >&2
  cleanup_partial
  exit 1
fi

echo "[spike-sweep] ${#written[@]} frame(s), $total bytes, in $OUT"
echo "[spike-sweep] frames are not committed yet — commit them, then:"
echo "               ./tools/shot_links.sh $OUT"
