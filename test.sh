#!/usr/bin/env bash
# test.sh — the project's "does it run" command. One entry point, so a fresh
# clone and a warm checkout behave identically.
#
#   ./test.sh
#
# Two non-obvious things this handles, both observed rather than assumed:
#
# 1. Godot's import cache lives in .godot/, which is gitignored, so EVERY fresh
#    clone starts without it. Running the GUT command against an unimported
#    project HANGS rather than erroring, which is worse than either. It also
#    needs two Godot invocations on a cold start: the first imports GUT's
#    images, and GUT only *sees* them on a subsequent run ("GUT got some new
#    images that are not imported yet. Please restart Godot.").
#
#    Readiness is checked against the imported artifacts themselves, not against
#    the existence of .godot/ — an interrupted import leaves the directory in
#    place with the cache incomplete, and a directory check would skip the
#    repair and hand the hang straight back.
#
# 2. GUT exits 0 when it discovers NO tests: it runs an empty collection and
#    derives its exit code purely from the zero failure count, printing
#    "Nothing was run." A rename, a moved file, or a changed prefix would
#    silently turn this command into a green light for an empty suite — which
#    for this project is the single check standing between a change and a merge.
#    The post-run guard below fails the command instead.
set -euo pipefail

GODOT="${GODOT:-godot}"
TEST_DIR="res://test"
MIN_TESTS="${MIN_TESTS:-1}"

command -v "$GODOT" >/dev/null || {
  echo "ERROR: '$GODOT' not on PATH. Install Godot 4 or set GODOT=/path/to/godot" >&2
  exit 1
}

cd "$(dirname "${BASH_SOURCE[0]}")"

# --- 0. the shell-side checks ------------------------------------------------
# Cheap, needs no engine, and runs first so a broken one is not buried under a
# minute of Godot output. The URL emitter is shell reading git metadata, so its
# test is shell too; asserting on that text from GDScript would mean shelling
# out from the engine to check a string.
echo "[test] shot-link URL form"
bash test/shot_links_test.sh

# --- 0b. decision records carry distinct numbers ------------------------------
# Agents work in parallel workspaces cloned from the same main, so two tickets
# in flight both read "the highest AgDR is 008" and both write an AgDR-009.
# Neither branch conflicts on merge — the filenames differ after the number —
# so git merges them happily and the collision only shows up when a human reads
# the directory. It already happened once: #13 and #15 both landed an AgDR-009.
#
# Cheap to check and it fails the command rather than a review, so it runs here
# before the expensive part. This catches the duplicate; it cannot stop two
# agents from picking the same number in the first place, which needs a number
# reserved at dispatch rather than at write time.
dupes="$(ls .decisions/AgDR-*.md 2>/dev/null \
  | sed -E 's|.*/AgDR-([0-9]+).*|\1|' \
  | sort | uniq -d)"
if [ -n "$dupes" ]; then
  echo "ERROR: two or more decision records share a number:" >&2
  for n in $dupes; do
    echo "       AgDR-$n:" >&2
    ls .decisions/AgDR-"$n"-*.md | sed 's|^|         |' >&2
  done
  echo "       Renumber the later one and update anything that references it." >&2
  exit 1
fi

# --- 0c. the importer stays out of docs/ -------------------------------------
# Godot writes an `.import` sidecar next to every image it can see under
# `res://`. For game art that is correct and those sidecars are committed. For
# the screenshots under `docs/shots/` it is pure noise: nobody loads them, and
# the metadata lands as untracked files in whichever branch ran this command
# next, so `git add -A` at the end of a ticket sweeps documentation churn into
# an unrelated pull request.
#
# This has now been "fixed" twice by committing the sidecars — once for
# `addons/gut/`, once for the nine under `docs/shots/`. Both times the files
# that existed stopped showing up and the next asset added re-opened it. The
# actual fix is `docs/.gdignore`, which stops them being generated at all.
#
# So the check is for the sidecars themselves, not for a list of paths: if any
# exist under `docs/`, the .gdignore is gone or has stopped working, and the
# next capture will put untracked metadata in somebody's diff. No git involved,
# so it reads the same in a dirty workspace as in a clean clone.
stray="$(find docs -type f \( -name '*.import' -o -name '*.uid' \) 2>/dev/null | sort)"
if [ -n "$stray" ]; then
  echo "ERROR: Godot import metadata was generated under docs/:" >&2
  echo "$stray" | sed 's|^|         |' >&2
  echo "       docs/ holds documentation images, never game resources, so these" >&2
  echo "       should not exist. Restore docs/.gdignore and delete them." >&2
  exit 1
fi

# --- 1. import readiness -----------------------------------------------------
# Every GUT image with an .import sidecar must have a matching compiled texture
# in the cache. Cheap (a few stats) so it runs on every invocation.
imports_ready() {
  [ -d .godot/imported ] || return 1
  local sidecar base
  shopt -s nullglob
  for sidecar in addons/gut/images/*.import; do
    base="$(basename "$sidecar" .import)"
    compgen -G ".godot/imported/${base}-*.ctex" >/dev/null || return 1
  done
  shopt -u nullglob
  return 0
}

# A `class_name` declared since the cache was last built is not in it, and a
# script referring to that class fails to parse — which lands as "GUT ignored a
# test script", pointing at the test rather than at the cache. Observed on a warm
# checkout the first time a new class was added: the guard below fired with a
# message that described the symptom and not the cause. A fresh clone never hits
# it, because it imports from nothing and picks everything up.
classes_registered() {
  local cache=".godot/global_script_class_cache.cfg"
  [ -f "$cache" ] || return 1
  local declared
  declared="$(grep -rhoE '^class_name +[A-Za-z_][A-Za-z0-9_]*' sim game tools test 2>/dev/null \
    | awk '{print $2}' | sort -u)"
  local name
  for name in $declared; do
    grep -q "\"class\": &\"$name\"" "$cache" || return 1
  done
  return 0
}

if ! imports_ready || ! classes_registered; then
  echo "[test] import cache missing, incomplete, or behind the sources — rebuilding (two passes)"
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  imports_ready || {
    echo "ERROR: import cache still incomplete after two passes. The suite would" >&2
    echo "       hang rather than fail, so stopping here instead." >&2
    exit 1
  }
  classes_registered || {
    echo "ERROR: a class_name in the sources is still missing from the class cache." >&2
    echo "       Scripts referring to it would fail to parse and be reported as" >&2
    echo "       broken tests, which is the wrong place to look." >&2
    exit 1
  }
fi

# --- 2. run the suite --------------------------------------------------------
echo "[test] running suite headless"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

set +e
"$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir="$TEST_DIR" -gexit 2>&1 | tee "$out"
status="${PIPESTATUS[0]}"
set -e

# --- 3. refuse an empty pass -------------------------------------------------
if grep -q "Nothing was run" "$out"; then
  echo "ERROR: GUT discovered no tests in $TEST_DIR and would have exited 0." >&2
  echo "       A suite that runs nothing must never report success." >&2
  exit 1
fi

# --- 3b. refuse a partial pass ----------------------------------------------
# A test script with a parse error is not a failing test — GUT logs a warning,
# skips the whole file, and derives a green exit code from the scripts that did
# load. Observed: an entire determinism suite vanished this way while the
# command still reported success. The empty-suite guard above does not catch it
# because the remaining scripts run fine. Silently running fewer tests than the
# repo contains is the same lie as running none.
if grep -qE "Ignoring script .* because it does not extend GutTest|Failed to load script .*res://test/" "$out"; then
  echo "ERROR: GUT skipped at least one test script (see 'Ignoring script' above)." >&2
  echo "       A script that fails to load is a broken test, not an absent one." >&2
  exit 1
fi

ran="$(awk '/^Tests +[0-9]+/ {print $2; exit}' "$out")"
if [ -z "${ran:-}" ] || [ "$ran" -lt "$MIN_TESTS" ]; then
  echo "ERROR: expected at least $MIN_TESTS test(s), GUT reported '${ran:-none}'." >&2
  exit 1
fi

# --- 3c. every script on disk must actually have run -------------------------
# A wording-independent backstop for the guard above. 3b recognises GUT's
# current phrasing; this one just counts, so a future GUT that skips a script
# with different wording still fails the command instead of passing quietly.
# The glob mirrors GUT's discovery (prefix `test_`, this directory only), so
# the two sides agree by construction and a non-test helper dropped in `test/`
# is invisible to both. Verified to fire: a `test_`-prefixed file GUT declines
# to load leaves 5 scripts on disk against 4 run.
#
# What this deliberately does NOT catch: a test file that is *deleted*. Both
# sides of the comparison are derived from the same tree, so a removed file
# lowers the expectation with it. Detecting that needs an expectation stored
# outside the tree — a committed script count, which then has to be bumped by
# hand on every added test and quietly lowered whenever it gets in the way.
# Not worth it: unlike a script that fails to load while looking perfectly
# fine, a deleted test file is loud in a diff, and review is the check for it.
shopt -s nullglob
on_disk=(test/test_*.gd)
shopt -u nullglob
expected="${#on_disk[@]}"

loaded="$(awk '/^Scripts +[0-9]+/ {print $2; exit}' "$out")"
if [ -z "${loaded:-}" ] || [ "$loaded" -ne "$expected" ]; then
  echo "ERROR: $expected test script(s) on disk, GUT ran '${loaded:-none}'." >&2
  echo "       A test file that disappears is not a test file that passes." >&2
  exit 1
fi

[ "$status" -eq 0 ] || exit "$status"

# --- 4. determinism across processes, not just within one -------------------
# The suite's determinism test generates the same seed twice inside a single
# Godot process. That catches a generator leaning on shared RNG state, but it
# structurally cannot catch a value that is constant within a process and
# differs between them — a per-process hash salt, an instance id folded into a
# draw, an engine value read once at startup. Each of those reproduces
# perfectly when you generate twice in one run.
#
# So: generate the same seeds in two separate processes and diff. No golden
# constant is stored, so the generator stays free to change and the check makes
# no claim about CPU architecture.
echo "[test] checking determinism across two processes"
fp1="$(mktemp)"; fp2="$(mktemp)"
trap 'rm -f "$out" "$fp1" "$fp2"' EXIT

run_fingerprints() {
  "$GODOT" --headless -s "$1" 2>/dev/null \
    | grep -E '^-?[0-9]+ [0-9]+$'
}

# Each generator is checked on its own rather than through one concatenated
# stream. A combined stream is non-empty as soon as *either* half produces
# lines, so a generator that silently stopped emitting would leave the
# emptiness guard green and take its own coverage down with it unnoticed.
for gen in tools/world_fingerprint.gd tools/diorama_fingerprint.gd tools/diorama_compose_fingerprint.gd; do
  run_fingerprints "$gen" > "$fp1"
  run_fingerprints "$gen" > "$fp2"

  if [ ! -s "$fp1" ]; then
    echo "ERROR: $gen produced no output. A silent no-op here would make the" >&2
    echo "       cross-process check vacuously green." >&2
    exit 1
  fi

  if ! diff -u "$fp1" "$fp2" >/dev/null; then
    echo "ERROR: the same seeds produced different output from $gen in two" >&2
    echo "       separate processes. Generation is reading something outside" >&2
    echo "       the seed." >&2
    diff -u "$fp1" "$fp2" >&2 || true
    exit 1
  fi

  echo "[test] $gen: $(wc -l < "$fp1" | tr -d ' ') seeds reproduced identically across processes"
done

# --- 5. the main scene actually launches ------------------------------------
# The suite instantiates the scene itself, which proves the nodes wire up — but
# it runs under GUT, not under the project's own startup path. A broken
# `run/main_scene`, an autoload that only exists at launch, or a null deref in
# `_ready` reached only on a real boot are all invisible to it and immediately
# visible to anyone pressing play.
#
# Run for a bounded number of frames and treat any engine-level error as a
# failure. Godot exits 0 on plenty of things it complains loudly about, so the
# exit code alone is not the check.
echo "[test] launching the main scene headless"
launch="$(mktemp)"
trap 'rm -f "$out" "$fp1" "$fp2" "$launch"' EXIT

set +e
"$GODOT" --headless --quit-after 120 >"$launch" 2>&1
launch_status=$?
set -e

if [ "$launch_status" -ne 0 ]; then
  echo "ERROR: the main scene exited $launch_status on a headless launch." >&2
  cat "$launch" >&2
  exit 1
fi

if grep -qE "^(ERROR|SCRIPT ERROR|USER ERROR)" "$launch"; then
  echo "ERROR: the main scene launched but logged errors." >&2
  grep -nE "^(ERROR|SCRIPT ERROR|USER ERROR)" "$launch" >&2
  exit 1
fi

echo "[test] main scene ran 120 frames clean"

exit 0
