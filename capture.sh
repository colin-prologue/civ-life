#!/usr/bin/env bash
# capture.sh — take pictures of the game so someone can review it from a phone.
#
#   ./capture.sh --seed 20260815 --turns 0,4,12 --name world
#   ./capture.sh --movie --seed 20260815 --from 0 --to 8 --name growth
#   ./capture.sh --self-test
#
# Deliberately NOT wired into ./test.sh. The suite has to stay runnable on a
# host with no rendering context; this command cannot run on one, and coupling
# them would make every future test run depend on a GPU.
#
# Three things about this are not obvious and cost real time to rediscover:
#
# 1. `--headless` cannot be used. It forces `--display-driver headless` and the
#    `dummy` rendering driver, which rasterizes nothing — and `Image.save_png()`
#    still succeeds, so the obvious implementation writes valid PNG files
#    containing nothing at all. A blank file attached to a pull request is worse
#    than no file: it looks like evidence. Every frame is therefore checked for
#    content before it reaches disk (see tools/frame_check.gd), and
#    `--self-test` runs this command under `--headless` on purpose to prove the
#    check still fires.
#
# 2. Capture is in-engine — the viewport texture is read back and encoded — and
#    never an OS-level screenshot. macOS screen recording needs a TCC grant that
#    an unattended run cannot obtain, and a denied grant yields a black
#    rectangle rather than an error, which is the same silent-blank failure
#    again wearing a different hat.
#
# 3. Frames are committed to the branch, so an unbounded capture bloats the
#    repository permanently. Every invocation is capped (see MAX_BYTES); going
#    over deletes what the run produced rather than leaving it lying next to a
#    warning. Prefer few, well-chosen frames.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

GODOT="${GODOT:-godot}"

# --- knobs -------------------------------------------------------------------
# Total bytes one invocation may write. 6 MiB is roughly two dozen frames of
# this renderer at 1280x720, or one short GIF, and is small enough that a
# handful of capture commits stay invisible against a source repository. It is
# a cap, not a target: if a change makes it bind, the answer is fewer frames.
MAX_BYTES="${CAPTURE_MAX_BYTES:-6291456}"

# A hung Godot is the failure mode that turns "capture broke" into "the agent
# never came back". Bound it.
TIMEOUT_SECS="${CAPTURE_TIMEOUT:-300}"

WIDTH=1280
HEIGHT=720
SEED=20260815
TURNS="0,4,12"
NAME=""
OUT_ROOT="docs/shots"
MODE="stills"
FROM_TURN=0
TO_TURN=8
HOLD=6
FPS=10
GIF_WIDTH=480
SELF_TEST=0

usage() {
  sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options
  --seed N            world seed to generate (default 20260815)
  --turns a,b,c       turn numbers to photograph, stills mode (default 0,4,12)
  --movie             record a span of turns as a GIF instead of stills
  --from N --to N     turn span for --movie (default 0..8)
  --hold N            rendered frames held per turn in --movie (default 6)
  --fps N             capture and playback rate for --movie (default 10)
  --gif-width N       GIF width in pixels (default 480)
  --name NAME         subdirectory under docs/shots/ (default: derived)
  --resolution WxH    render size (default 1280x720)
  --self-test         prove the blank-frame guard fires and frames are stable
  -h, --help          this

Environment
  GODOT               godot binary (default: godot)
  CAPTURE_MAX_BYTES   per-invocation byte cap (default 6291456)
  CAPTURE_TIMEOUT     seconds before a hung capture is killed (default 300)
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --turns) TURNS="$2"; shift 2 ;;
    --movie) MODE="movie"; shift ;;
    --from) FROM_TURN="$2"; shift 2 ;;
    --to) TO_TURN="$2"; shift 2 ;;
    --hold) HOLD="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --gif-width) GIF_WIDTH="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --out) OUT_ROOT="$2"; shift 2 ;;
    --resolution) WIDTH="${2%x*}"; HEIGHT="${2#*x}"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option '$1'" ;;
  esac
done

command -v "$GODOT" >/dev/null \
  || die "'$GODOT' is not on PATH. Install Godot 4 or set GODOT=/path/to/godot"

# --- import cache ------------------------------------------------------------
# Same cold-start problem test.sh documents: a fresh clone has no .godot/, and
# running against an unimported project hangs rather than failing. Two passes,
# because the first one is what creates the artifacts the second one reads.
if [ ! -d .godot/imported ]; then
  echo "[capture] no import cache — building it (two passes)"
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  [ -d .godot/imported ] || die "the import cache did not build; run ./test.sh first"
fi

# --- running Godot with a deadline ------------------------------------------
# `timeout` is coreutils and is not on a stock macOS, which is the host this is
# meant to run on. Poll instead.
#
# Polling `kill -0` in a loop is the shorter version of this and is wrong: a
# finished background child stays visible to `kill -0` until the shell reaps it,
# so the loop can sit there until the deadline on a run that already succeeded.
# Block on `wait` and let a separate watchdog do the killing, leaving a marker
# file behind so a deliberate SIGKILL is distinguishable from a crash.
run_bounded() {
  local log="$1"; shift
  local pid watchdog rc
  rm -f "$log.timeout"
  "$@" >"$log" 2>&1 &
  pid=$!
  ( sleep "$TIMEOUT_SECS"; touch "$log.timeout"; kill -9 "$pid" ) >/dev/null 2>&1 &
  watchdog=$!
  set +e
  wait "$pid"
  rc=$?
  set -e
  kill "$watchdog" >/dev/null 2>&1 || true
  wait "$watchdog" >/dev/null 2>&1 || true
  if [ -f "$log.timeout" ]; then
    rm -f "$log.timeout"
    return 124
  fi
  return "$rc"
}

total_bytes() {
  local dir="$1" sum=0 f
  [ -d "$dir" ] || { echo 0; return; }
  while IFS= read -r f; do
    sum=$((sum + $(wc -c <"$f")))
  done < <(find "$dir" -type f)
  echo "$sum"
}

# Turn a capture run's exit status and log into a verdict. Godot exits 0 on
# plenty of things it complains loudly about, and it exits non-zero for reasons
# that have nothing to do with pixels, so neither the status nor the log alone
# is the check — both are, plus the sentinel the harness prints.
explain_failure() {
  local rc="$1" log="$2"
  if [ "$rc" -eq 124 ]; then
    echo "the capture did not finish within ${TIMEOUT_SECS}s and was killed."
    echo "A rendering context that never comes up can hang rather than error."
    return
  fi
  if grep -q "CAPTURE-FAIL" "$log"; then
    grep "CAPTURE-FAIL" "$log" | sed 's/^/  /'
    return
  fi
  if grep -qiE "Unable to (create|initialize)|No such (display|rendering) driver|Could not create an instance of GPU|failed to create" "$log"; then
    echo "Godot could not open a rendering context on this host:"
    grep -iE "Unable to (create|initialize)|No such (display|rendering) driver|Could not create an instance of GPU|failed to create" "$log" | head -5 | sed 's/^/  /'
    return
  fi
  echo "Godot exited $rc without reporting a capture result. Tail of its output:"
  tail -20 "$log" | sed 's/^/  /'
}

# --- the capture run ---------------------------------------------------------
# $1 output dir (absolute), rest: extra godot argv before -s
capture_stills() {
  local out="$1" seed="$2" turns="$3" log="$4" force_headless="${5:-0}"
  local -a argv
  argv=("$GODOT")
  # An `x && y` one-liner here would be a failing simple command under `set -e`
  # every time the flag is off, which is most of the time.
  if [ "$force_headless" = "1" ]; then
    argv+=(--headless)
  fi
  argv+=(--resolution "${WIDTH}x${HEIGHT}" -s tools/capture.gd --
    "--mode=stills" "--seed=$seed" "--turns=$turns"
    "--out=$out" "--width=$WIDTH" "--height=$HEIGHT")
  set +e
  run_bounded "$log" "${argv[@]}"
  local rc=$?
  set -e
  return "$rc"
}

# --- self test ---------------------------------------------------------------
# The two claims this harness makes that cannot be taken on trust: that the
# blank-frame guard actually rejects a blank frame, and that the same seed and
# turn produce the same bytes twice. A guard nobody has watched fail is
# indistinguishable from a guard that is broken.
self_test() {
  local tmp failures=0
  tmp="$(mktemp -d)"
  # EXIT rather than RETURN: the failure path below calls `die`, which exits
  # rather than returning, and would otherwise leave the directory behind.
  trap 'rm -rf "$tmp"' EXIT

  echo "[self-test] 1/2 — blank-frame guard, running the capture under --headless on purpose"
  set +e
  capture_stills "$tmp/headless" "$SEED" "0" "$tmp/headless.log" 1
  local rc=$?
  set -e
  local wrote
  wrote="$(find "$tmp/headless" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL: the headless run exited 0. The guard did not fire."
    failures=$((failures + 1))
  elif [ "$wrote" != "0" ]; then
    echo "  FAIL: the headless run wrote $wrote file(s) before failing."
    failures=$((failures + 1))
  elif ! grep -q "CAPTURE-FAIL" "$tmp/headless.log"; then
    echo "  FAIL: the headless run failed, but not with a blank-frame verdict:"
    tail -10 "$tmp/headless.log" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    echo "  PASS: exit $rc, no files written, guard said:"
    grep "CAPTURE-FAIL" "$tmp/headless.log" | sed 's/^/    /'
  fi

  echo "[self-test] 2/2 — determinism, capturing seed $SEED turn 0 twice"
  set +e
  capture_stills "$tmp/a" "$SEED" "0" "$tmp/a.log"
  local rc_a=$?
  capture_stills "$tmp/b" "$SEED" "0" "$tmp/b.log"
  local rc_b=$?
  set -e
  if [ "$rc_a" -ne 0 ] || [ "$rc_b" -ne 0 ]; then
    echo "  FAIL: a capture run did not succeed on this host."
    explain_failure "$rc_a" "$tmp/a.log" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    local f name
    local mismatched=0
    for f in "$tmp"/a/*.png; do
      name="$(basename "$f")"
      if ! cmp -s "$f" "$tmp/b/$name"; then
        echo "  FAIL: $name differs between two runs of the same seed and turn."
        mismatched=1
      fi
    done
    if [ "$mismatched" = "0" ]; then
      echo "  PASS: identical bytes across two processes."
    else
      failures=$((failures + 1))
    fi
  fi

  [ "$failures" -eq 0 ] || die "$failures self-test check(s) failed."
  echo "[self-test] both checks passed."
}

if [ "$SELF_TEST" = "1" ]; then
  self_test
  exit 0
fi

# --- output location ---------------------------------------------------------
[ -n "$NAME" ] || NAME="seed-$SEED"
REL_OUT="$OUT_ROOT/$NAME"
ABS_OUT="$PWD/$REL_OUT"
rm -rf "$ABS_OUT"
mkdir -p "$ABS_OUT"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if [ "$MODE" = "stills" ]; then
  echo "[capture] stills, seed $SEED, turns $TURNS, ${WIDTH}x${HEIGHT} -> $REL_OUT/"
  set +e
  capture_stills "$ABS_OUT" "$SEED" "$TURNS" "$LOG"
  RC=$?
  set -e
  if [ "$RC" -ne 0 ] || ! grep -q "^CAPTURE-OK" "$LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: capture failed and nothing was written." >&2
    explain_failure "$RC" "$LOG" >&2
    exit 1
  fi
  grep -E "^\[capture\]" "$LOG" || true

  # Every requested turn must have produced a file. A run that quietly captures
  # three of four frames and exits 0 is the same lie as one that captures none.
  EXPECTED="$(echo "$TURNS" | tr ',' '\n' | grep -c '[0-9]' || true)"
  GOT="$(find "$ABS_OUT" -name '*.png' | wc -l | tr -d ' ')"
  [ "$GOT" -eq "$EXPECTED" ] \
    || { rm -rf "$ABS_OUT"; die "asked for $EXPECTED frame(s), got $GOT"; }
else
  command -v ffmpeg >/dev/null \
    || die "--movie needs ffmpeg to assemble a GIF (brew install ffmpeg). Godot's own movie output is AVI, which GitHub will not play inline."
  FRAMES_DIR="$(mktemp -d)"
  trap 'rm -f "$LOG"; rm -rf "$FRAMES_DIR"' EXIT

  echo "[capture] movie, seed $SEED, turns $FROM_TURN..$TO_TURN at ${FPS}fps -> $REL_OUT/motion.gif"
  # --write-movie forces --fixed-fps, so the recording advances in lockstep with
  # the simulation instead of with the wall clock: the same span of turns always
  # yields the same number of frames.
  set +e
  run_bounded "$LOG" "$GODOT" --resolution "${WIDTH}x${HEIGHT}" \
    --fixed-fps "$FPS" --write-movie "$FRAMES_DIR/frame.png" \
    -s tools/capture.gd -- \
    "--mode=movie" "--seed=$SEED" "--from=$FROM_TURN" "--to=$TO_TURN" \
    "--hold=$HOLD" "--out=$ABS_OUT" "--width=$WIDTH" "--height=$HEIGHT"
  RC=$?
  set -e
  if [ "$RC" -ne 0 ] || ! grep -q "^CAPTURE-OK" "$LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: movie capture failed and nothing was kept." >&2
    explain_failure "$RC" "$LOG" >&2
    exit 1
  fi
  grep -E "^\[capture\]" "$LOG" || true

  # The movie writer is the engine, so the in-engine guard cannot stand in front
  # of it — the poster stills above prove the viewport had pixels. This is the
  # independent second signal: a uniform PNG compresses to a few hundred bytes,
  # so a floor on recorded frame size catches a blank recording even if the
  # poster somehow passed.
  RECORDED="$(find "$FRAMES_DIR" -name '*.png' | wc -l | tr -d ' ')"
  [ "$RECORDED" -gt 0 ] || { rm -rf "$ABS_OUT"; die "--write-movie recorded no frames"; }
  TINY="$(find "$FRAMES_DIR" -name '*.png' -size -2k | wc -l | tr -d ' ')"
  if [ "$TINY" -gt 0 ]; then
    rm -rf "$ABS_OUT"
    die "$TINY of $RECORDED recorded frames are under 2KB — that is a blank recording, not a small one"
  fi
  echo "[capture] $RECORDED frames recorded, assembling GIF"

  ffmpeg -y -loglevel error -framerate "$FPS" -pattern_type glob \
    -i "$FRAMES_DIR/*.png" \
    -vf "scale=${GIF_WIDTH}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" \
    -loop 0 "$ABS_OUT/motion.gif" \
    || { rm -rf "$ABS_OUT"; die "ffmpeg could not assemble the GIF"; }
fi

# --- byte cap ----------------------------------------------------------------
BYTES="$(total_bytes "$ABS_OUT")"
if [ "$BYTES" -gt "$MAX_BYTES" ]; then
  rm -rf "$ABS_OUT"
  die "this run wrote $BYTES bytes, over the $MAX_BYTES cap — nothing was kept.
       Capture fewer turns, a shorter span, or a smaller --gif-width.
       Raise CAPTURE_MAX_BYTES only if you are prepared to carry it in the repo forever."
fi

echo
echo "[capture] $BYTES / $MAX_BYTES bytes written to $REL_OUT/"
echo "[capture] paste into the PR body:"
echo
while IFS= read -r f; do
  echo "![$(basename "$f" | sed 's/\.[a-z]*$//')](${f#"$PWD/"})"
done < <(find "$ABS_OUT" -type f | sort)
echo
