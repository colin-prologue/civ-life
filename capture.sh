#!/usr/bin/env bash
# capture.sh — take pictures of the game so someone can review it from a phone.
#
#   ./capture.sh --seed 20260815 --turns 0,4,12 --name world
#   ./capture.sh --movie --seed 20260815 --from 0 --to 8 --name growth
#   ./capture.sh --links docs/shots/growth
#   ./capture.sh --self-test
#
# Deliberately NOT wired into ./test.sh. The suite has to stay runnable on a
# host with no rendering context; this command cannot run on one, and coupling
# them would make every future test run depend on a GPU.
#
# Four things about this are not obvious and cost real time to rediscover:
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
#
# 4. A written frame is not yet a visible one. GitHub does not resolve
#    repo-relative image paths in a pull request body, so the obvious markdown
#    puts no picture in front of a reviewer while looking exactly like markdown
#    that does. This command therefore prints absolute, commit-pinned URLs (see
#    tools/shot_links.sh) — and, because the frames are never committed at the
#    moment they are captured, says so and tells you to re-run `--links` once
#    they are.
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
SCENE=""
LABEL=""
OUT_ROOT="docs/shots"
MODE="stills"
FROM_TURN=0
TO_TURN=8
HOLD=6
FPS=10
GIF_WIDTH=480
SELF_TEST=0
LINKS_DIRS=()

usage() {
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options
  --seed N            world seed to generate (default 20260815)
  --turns a,b,c       turn numbers to photograph, stills mode (default 0,4,12)
  --movie             record a span of turns as a GIF instead of stills
  --placement         photograph the player's verb instead of the clock: a tile
                      selected, a farm on it, a route drawn, and the route
                      running. Three of those happen at the same turn, so the
                      distinguishing axis is player actions and --turns cannot
                      state it. Drives main.gd's own click/place/route entry
                      points. --seed and --turns do not apply.
  --from N --to N     turn span for --movie (default 0..8)
  --hold N            rendered frames held per turn in --movie (default 6)
  --fps N             capture and playback rate for --movie (default 10)
  --gif-width N       GIF width in pixels (default 480)
  --name NAME         subdirectory under docs/shots/ (default: derived)
  --scene PATH        res:// scene to photograph (default: the game scene).
                      A scene without the hex game's world/advance_turn() is
                      captured as a single verified still; --turns and --movie
                      do not apply to it and --movie is refused rather than
                      recording one frame N times.
  --label NAME        filename stem for a --scene still (default: the scene's
                      own basename). Ignored for the game scene, whose stills
                      are named by seed and turn.
  --resolution WxH    render size (default 1280x720)
  --links DIR         print the paste-ready markdown for an existing shots
                      directory and exit — no Godot, no capture. Run this
                      again after committing the frames: the URLs are pinned
                      to HEAD, and HEAD moves when you commit.
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
    --placement) MODE="placement"; shift ;;
    --from) FROM_TURN="$2"; shift 2 ;;
    --to) TO_TURN="$2"; shift 2 ;;
    --hold) HOLD="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --gif-width) GIF_WIDTH="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --scene) SCENE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --out) OUT_ROOT="$2"; shift 2 ;;
    --resolution) WIDTH="${2%x*}"; HEIGHT="${2#*x}"; shift 2 ;;
    --links) LINKS_DIRS+=("$2"); shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option '$1'" ;;
  esac
done

# --- links only ---------------------------------------------------------------
# Ahead of the Godot check on purpose. This mode reads a directory and the git
# metadata and nothing else; the whole point of it is to be re-runnable after a
# commit, on any host, long after the capture that produced the frames.
if [ "${#LINKS_DIRS[@]}" -gt 0 ]; then
  bash tools/shot_links.sh "${LINKS_DIRS[@]}"
  exit 0
fi

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
#
# Note the `|| rc=$?` idiom used here and at every other call that is allowed to
# fail. The obvious alternative — bracketing the call in `set +e` / `set -e` —
# is a trap, because those are global settings and not function-local ones: a
# helper that switches errexit back on hands it to a caller that had switched it
# off on purpose, and the helper's own non-zero `return` then kills the script
# before a single word of diagnosis is printed. That is how a self-test whose
# whole job is to observe a failure ends up exiting silently on the failure it
# was watching for.
run_bounded() {
  local log="$1"; shift
  local pid watchdog rc=0
  rm -f "$log.timeout"
  "$@" >"$log" 2>&1 &
  pid=$!
  ( sleep "$TIMEOUT_SECS"; touch "$log.timeout"; kill -9 "$pid" ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" || rc=$?
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
  if grep -qE "CAPTURE-FAIL|SHOT-FAIL" "$log"; then
    grep -E "CAPTURE-FAIL|SHOT-FAIL" "$log" | sed 's/^/  /'
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
  # Appended only when set, so the default invocation is byte-identical to what
  # it was before this option existed and every committed frame stays
  # reproducible by the command that made it.
  [ -n "$SCENE" ] && argv+=("--scene=$SCENE")
  [ -n "$LABEL" ] && argv+=("--label=$LABEL")
  local rc=0
  run_bounded "$log" "${argv[@]}" || rc=$?
  return "$rc"
}

# The placement frames. Same watchdog, same byte cap, same links as everything
# else here — only the script on the other end differs, because what varies
# across these frames is what the player did rather than what the clock did.
capture_placement() {
  local out="$1" log="$2"
  local -a argv
  argv=("$GODOT" --resolution "${WIDTH}x${HEIGHT}"
    -s tools/placement_shot.gd -- "$out")
  local rc=0
  run_bounded "$log" "${argv[@]}" || rc=$?
  return "$rc"
}

# --- self test ---------------------------------------------------------------
# The four claims this harness makes that cannot be taken on trust: that the
# blank-frame guard actually rejects a blank frame, that the same seed and
# turn produce the same bytes twice, that --scene can photograph something
# that is not the hex game, and that --placement — which runs a different
# script with its own copy of the guard — rejects a blank frame too. A guard
# nobody has watched fail is indistinguishable from a guard that is broken, and
# a scene option nobody has pointed at a foreign scene is indistinguishable from
# one that only ever worked on main.tscn. The fourth leg exists because the
# first three say nothing about a capture path added later: a second guard is a
# second thing that can be wrong.
SELF_TEST_TMP=""

self_test() {
  local failures=0 tmp
  SELF_TEST_TMP="$(mktemp -d)"
  tmp="$SELF_TEST_TMP"
  # EXIT rather than RETURN: the failure path below calls `die`, which exits
  # rather than returning, and would otherwise leave the directory behind.
  #
  # The trap body names a global deliberately. A `local` is out of scope by the
  # time the trap runs, and under `set -u` an EXIT trap that references an unset
  # variable fails — turning a self-test that passed both of its checks into a
  # non-zero exit, which reads from outside as the capture being broken.
  trap 'rm -rf "$SELF_TEST_TMP"' EXIT

  echo "[self-test] 1/4 — blank-frame guard, running the capture under --headless on purpose"
  # Created up front, not left to the capture: if the run dies before it makes
  # its own output directory, `find` on a missing path fails, and under
  # `pipefail` that aborts the self-test with no verdict printed at all — the
  # exact silent outcome this leg exists to rule out.
  mkdir -p "$tmp/headless"
  local rc=0
  capture_stills "$tmp/headless" "$SEED" "0" "$tmp/headless.log" 1 || rc=$?
  local wrote
  wrote="$(find "$tmp/headless" -name '*.png' | wc -l | tr -d ' ')"
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

  echo "[self-test] 2/4 — determinism, capturing seed $SEED turn 0 twice"
  local rc_a=0 rc_b=0
  capture_stills "$tmp/a" "$SEED" "0" "$tmp/a.log" || rc_a=$?
  capture_stills "$tmp/b" "$SEED" "0" "$tmp/b.log" || rc_b=$?
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

  # A 3D fixture with no HexMapView, no world, and no advance_turn(). It stands
  # in for the diorama lab the procedural-art intent says is judged through this
  # harness. The assertion is not "a file appeared" — a blank frame is a file —
  # but that the frame cleared the same blank-frame guard leg 1 just watched
  # fire, which is the only thing that makes a captured spike reviewable.
  echo "[self-test] 3/4 — --scene captures a scene that is not the hex game"
  local rc_s=0
  mkdir -p "$tmp/scene"
  local -a scene_argv
  scene_argv=("$GODOT" --resolution "${WIDTH}x${HEIGHT}" -s tools/capture.gd --
    "--mode=stills" "--seed=$SEED" "--turns=0" "--out=$tmp/scene"
    "--width=$WIDTH" "--height=$HEIGHT"
    "--scene=res://test/fixtures/static_scene.tscn" "--label=static")
  run_bounded "$tmp/scene.log" "${scene_argv[@]}" || rc_s=$?
  if [ "$rc_s" -ne 0 ]; then
    echo "  FAIL: capturing the static fixture exited $rc_s."
    explain_failure "$rc_s" "$tmp/scene.log" | sed 's/^/    /'
    failures=$((failures + 1))
  elif [ ! -f "$tmp/scene/static.png" ]; then
    echo "  FAIL: no static.png was written; --label was not honoured."
    failures=$((failures + 1))
  elif ! grep -q "^CAPTURE-OK 1" "$tmp/scene.log"; then
    echo "  FAIL: the run did not report exactly one verified frame:"
    tail -5 "$tmp/scene.log" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    echo "  PASS: one verified frame from a scene with no HexMapView:"
    grep -E "^\[capture\] static\.png" "$tmp/scene.log" | sed 's/^/    /'
  fi

  # --placement runs a different script with its own copy of the blank-frame
  # guard, and a guard nobody has watched fail is indistinguishable from a
  # broken one — the argument leg 1 exists for, applied to the second capture
  # path rather than assumed to carry over to it. Under --headless the run must
  # die on the first frame with nothing on disk, which also proves the check
  # runs *before* the write rather than after it.
  echo "[self-test] 4/4 — the placement path's blank-frame guard fires too"
  local rc_p=0
  mkdir -p "$tmp/placement"
  local -a placement_argv
  placement_argv=("$GODOT" --headless --resolution "${WIDTH}x${HEIGHT}"
    -s tools/placement_shot.gd -- "$tmp/placement")
  run_bounded "$tmp/placement.log" "${placement_argv[@]}" || rc_p=$?
  local wrote_p
  wrote_p="$(find "$tmp/placement" -name '*.png' | wc -l | tr -d ' ')"
  if [ "$rc_p" -eq 0 ]; then
    echo "  FAIL: the headless placement run exited 0. The guard did not fire."
    failures=$((failures + 1))
  elif [ "$wrote_p" != "0" ]; then
    echo "  FAIL: it wrote $wrote_p file(s) before failing; the check runs too late."
    failures=$((failures + 1))
  elif ! grep -q "SHOT-FAIL" "$tmp/placement.log"; then
    echo "  FAIL: it failed, but not with a blank-frame verdict:"
    tail -10 "$tmp/placement.log" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    echo "  PASS: exit $rc_p, no files written, guard said:"
    grep "SHOT-FAIL" "$tmp/placement.log" | sed 's/^/    /'
  fi

  [ "$failures" -eq 0 ] || die "$failures self-test check(s) failed."
  echo "[self-test] all checks passed."
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
  RC=0
  capture_stills "$ABS_OUT" "$SEED" "$TURNS" "$LOG" || RC=$?
  if [ "$RC" -ne 0 ] || ! grep -q "^CAPTURE-OK" "$LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: capture failed and nothing was written." >&2
    explain_failure "$RC" "$LOG" >&2
    exit 1
  fi
  grep -E "^\[capture\]" "$LOG" || true

  # Every requested turn must have produced a file. A run that quietly captures
  # three of four frames and exits 0 is the same lie as one that captures none.
  #
  # For a --scene capture the shell cannot derive the count: whether the scene
  # is turn-driven is a property only the engine can see, and a static scene
  # yields one still no matter how many turns were asked for. There the
  # harness's own reported count stands in. That is a weaker expectation --
  # self-reported rather than independent -- so it is used only where the
  # stronger one is unavailable, and the on-disk count is still what gets
  # compared, which is what catches a frame that was reported and never
  # landed.
  REPORTED="$(sed -n 's/^CAPTURE-OK \([0-9][0-9]*\).*/\1/p' "$LOG" | tail -1)"
  if [ -n "$SCENE" ]; then
    EXPECTED="${REPORTED:-0}"
  else
    EXPECTED="$(echo "$TURNS" | tr ',' '\n' | grep -c '[0-9]' || true)"
    # Default path only: the harness's count and the request must also agree,
    # so a harness that silently decided to write fewer is caught here rather
    # than passing because it wrote exactly as many as it meant to.
    [ "${REPORTED:-0}" -eq "$EXPECTED" ] \
      || { rm -rf "$ABS_OUT"; die "asked for $EXPECTED frame(s), harness reported ${REPORTED:-none}"; }
  fi
  GOT="$(find "$ABS_OUT" -name '*.png' | wc -l | tr -d ' ')"
  [ "$GOT" -eq "$EXPECTED" ] \
    || { rm -rf "$ABS_OUT"; die "asked for $EXPECTED frame(s), got $GOT"; }
elif [ "$MODE" = "placement" ]; then
  echo "[capture] placement, ${WIDTH}x${HEIGHT} -> $REL_OUT/"
  RC=0
  capture_placement "$ABS_OUT" "$LOG" || RC=$?
  if [ "$RC" -ne 0 ] || ! grep -q "^SHOT-OK" "$LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: capture failed and nothing was written." >&2
    explain_failure "$RC" "$LOG" >&2
    exit 1
  fi
  grep -E "^\[shot\]" "$LOG" || true

  # The script decides how many frames the sequence is, so unlike stills there
  # is no request to check its count against. What is still worth checking is
  # that every frame it says it wrote is on disk — the failure this catches is
  # a reported frame that never landed, which is the one that would put a
  # missing picture in a pull request that claims four.
  REPORTED="$(sed -n 's/^SHOT-OK \([0-9][0-9]*\).*/\1/p' "$LOG" | tail -1)"
  GOT="$(find "$ABS_OUT" -name '*.png' | wc -l | tr -d ' ')"
  [ "$GOT" -eq "${REPORTED:-0}" ] \
    || { rm -rf "$ABS_OUT"; die "harness reported ${REPORTED:-none} frame(s), got $GOT"; }
else
  command -v ffmpeg >/dev/null \
    || die "--movie needs ffmpeg to assemble a GIF (brew install ffmpeg). Godot's own movie output is AVI, which GitHub will not play inline."
  FRAMES_DIR="$(mktemp -d)"
  trap 'rm -f "$LOG"; rm -rf "$FRAMES_DIR"' EXIT

  echo "[capture] movie, seed $SEED, turns $FROM_TURN..$TO_TURN at ${FPS}fps -> $REL_OUT/motion.gif"
  # --write-movie forces --fixed-fps, so the recording advances in lockstep with
  # the simulation instead of with the wall clock: the same span of turns always
  # yields the same number of frames.
  RC=0
  run_bounded "$LOG" "$GODOT" --resolution "${WIDTH}x${HEIGHT}" \
    --fixed-fps "$FPS" --write-movie "$FRAMES_DIR/frame.png" \
    -s tools/capture.gd -- \
    "--mode=movie" "--seed=$SEED" "--from=$FROM_TURN" "--to=$TO_TURN" \
    "--hold=$HOLD" "--out=$ABS_OUT" "--width=$WIDTH" "--height=$HEIGHT" \
    ${SCENE:+"--scene=$SCENE"} || RC=$?
  if [ "$RC" -ne 0 ] || ! grep -q "^CAPTURE-OK" "$LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: movie capture failed and nothing was kept." >&2
    explain_failure "$RC" "$LOG" >&2
    exit 1
  fi
  grep -E "^\[capture\]" "$LOG" || true

  # The movie writer is the engine, so the guard cannot stand in front of what it
  # writes — but it can stand behind it. Every recorded frame is loaded back and
  # run through the same FrameCheck the stills pass through, in a separate pass
  # that needs no rendering context.
  #
  # The previous version of this check was a floor on file size, on the theory
  # that a uniform PNG compresses to a few hundred bytes. It was too weak, and
  # not in a theoretical way: `--write-movie` starts recording at engine start,
  # so the first frames are the clear colour from before the scene exists, and a
  # 1280x720 grey rectangle is comfortably over any sane floor. The GIF opened on
  # a blank screen and every check passed.
  RECORDED="$(find "$FRAMES_DIR" -name '*.png' | wc -l | tr -d ' ')"
  [ "$RECORDED" -gt 0 ] || { rm -rf "$ABS_OUT"; die "--write-movie recorded no frames"; }

  VERIFY_LOG="$(mktemp)"
  trap 'rm -f "$LOG" "$VERIFY_LOG"; rm -rf "$FRAMES_DIR"' EXIT
  VRC=0
  run_bounded "$VERIFY_LOG" "$GODOT" --headless -s tools/capture.gd -- \
    "--mode=verify" "--frames=$FRAMES_DIR" || VRC=$?
  if [ "$VRC" -ne 0 ] || ! grep -q "^CAPTURE-OK" "$VERIFY_LOG"; then
    rm -rf "$ABS_OUT"
    echo "ERROR: the recorded frames could not be checked for content." >&2
    explain_failure "$VRC" "$VERIFY_LOG" >&2
    exit 1
  fi

  # Leading blanks are engine start-up and are dropped. A blank *after* the
  # recording has begun properly is a hole in the middle of the film, which is a
  # different thing entirely and is fatal.
  TRIMMED=0
  HOLES=0
  SEEN_OK=0
  while read -r VERDICT FRAME; do
    if [ "$VERDICT" = "FRAME-OK" ]; then
      SEEN_OK=1
    elif [ "$SEEN_OK" = "1" ]; then
      HOLES=$((HOLES + 1))
    else
      rm -f "$FRAMES_DIR/$FRAME"
      TRIMMED=$((TRIMMED + 1))
    fi
  done < <(grep -E '^FRAME-(OK|BLANK) ' "$VERIFY_LOG")

  if [ "$SEEN_OK" = "0" ]; then
    rm -rf "$ABS_OUT"
    die "all $RECORDED recorded frames are blank — the recording drew nothing"
  fi
  if [ "$HOLES" -gt 0 ]; then
    rm -rf "$ABS_OUT"
    die "$HOLES recorded frame(s) are blank after the recording had started — a gap in the film, not a slow start"
  fi
  echo "[capture] $RECORDED frames recorded, $TRIMMED blank start-up frame(s) dropped, assembling GIF"

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
echo

# The frames were written a second ago, so they are certainly not committed at
# HEAD and the block below will say so. That is the correct thing for it to say:
# the alternative is a confident link to a file GitHub cannot fetch, which is
# the failure this replaced. Commit, then re-run `--links` for the real block.
bash tools/shot_links.sh "$REL_OUT"
echo
