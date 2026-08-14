#!/usr/bin/env bash
# test.sh — the project's "does it run" command. One entry point, so a fresh
# clone and a warm checkout behave identically.
#
#   ./test.sh
#
# Why the import passes: Godot's import cache lives in .godot/, which is
# gitignored, so EVERY fresh clone starts without it and the test runner cannot
# load GUT's resources. Two passes are needed, not one — the first pass imports
# GUT's images but GUT itself only picks them up on the following run ("GUT got
# some new images that are not imported yet. Please restart Godot."). Running
# the test command directly on a clean clone hangs instead of failing, which is
# worse than either.
set -euo pipefail

GODOT="${GODOT:-godot}"

command -v "$GODOT" >/dev/null || {
  echo "ERROR: '$GODOT' not on PATH. Install Godot 4 or set GODOT=/path/to/godot" >&2
  exit 1
}

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -d .godot ]; then
  echo "[test] cold clone — building import cache (two passes)"
  "$GODOT" --headless --import >/dev/null 2>&1 || true
  "$GODOT" --headless --import >/dev/null 2>&1 || true
fi

echo "[test] running suite headless"
exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
