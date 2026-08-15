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

if ! imports_ready; then
  echo "[test] import cache missing or incomplete — rebuilding (two passes)"
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  imports_ready || {
    echo "ERROR: import cache still incomplete after two passes. The suite would" >&2
    echo "       hang rather than fail, so stopping here instead." >&2
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
  "$GODOT" --headless -s tools/world_fingerprint.gd 2>/dev/null \
    | grep -E '^-?[0-9]+ [0-9]+$'
}

run_fingerprints > "$fp1"
run_fingerprints > "$fp2"

if [ ! -s "$fp1" ]; then
  echo "ERROR: the fingerprint pass produced no output. A silent no-op here" >&2
  echo "       would make the cross-process check vacuously green." >&2
  exit 1
fi

if ! diff -u "$fp1" "$fp2" >/dev/null; then
  echo "ERROR: the same seeds produced different maps in two separate processes." >&2
  echo "       Generation is reading something outside the seed." >&2
  diff -u "$fp1" "$fp2" >&2 || true
  exit 1
fi

echo "[test] $(wc -l < "$fp1" | tr -d ' ') seeds reproduced identically across processes"

exit 0
