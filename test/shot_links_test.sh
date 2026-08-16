#!/usr/bin/env bash
# test/shot_links_test.sh — the emitted image URLs have the right shape.
#
# Run by ./test.sh. Not a GUT test: the thing under test is a shell script that
# reads git metadata, and putting it in the Godot suite would mean shelling out
# from GDScript to assert on text, which is the same test with a rendering
# engine bolted to it.
#
# What this is really guarding against is not a broken script — it is a link
# that looks right and shows nothing. PR #12 shipped `![x](docs/shots/…)`,
# which renders in the repo tree and renders nothing in a pull request body, and
# survived review because the two forms are indistinguishable in markdown
# source. Every assertion below is a property you cannot eyeball:
#
#   absolute host   — a relative path passes any "is there a link" check
#   40-char sha     — a branch name in the same slot looks identical and lets a
#                     later capture rewrite the pictures in a merged PR
#   derived slug    — a hard-coded owner works perfectly until someone forks
#
# Fixtures are throwaway git repositories, so the owner/repo assertions can use
# a name that is deliberately NOT this repository's: a hard-coded constant in
# the emitter would pass a test run against the real remote.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMIT="$ROOT/tools/shot_links.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }
pass() { echo "  pass: $*"; }

SHA_RE='[0-9a-f]{40}'

# A repository with one committed frame, on a branch whose name would be
# visible in the URL if the emitter pinned to a branch.
fixture() {
  local d="$TMP/$2"
  mkdir -p "$d/docs/shots/demo"
  git -C "$d" init -q -b switchboard/issue-14
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "test"
  git -C "$d" remote add origin "$1"
  printf 'not really a png' >"$d/docs/shots/demo/frame.png"
  git -C "$d" add -A
  git -C "$d" commit -qm "frame" >/dev/null
  echo "$d"
}

# Sets EMIT_OUT/EMIT_RC rather than returning the block, so a run that dies can
# be reported with its own error message instead of taking `set -e` and the
# whole file down with nothing printed.
EMIT_OUT=""
EMIT_RC=0
emit() {
  local dir="$1"; shift
  EMIT_RC=0
  EMIT_OUT="$( cd "$dir" && bash "$EMIT" "$@" 2>"$TMP/stderr" )" || EMIT_RC=$?
}

# For the cases that are supposed to succeed.
emit_ok() {
  emit "$@"
  [ "$EMIT_RC" -eq 0 ] || fail "the emitter exited $EMIT_RC: $(cat "$TMP/stderr")"
  return 0
}

echo "[shot-links] 1/6 — https remote: absolute, sha-pinned, owner from the remote"
d="$(fixture "https://github.com/octo-fork/civ-life-fork.git" https)"
emit_ok "$d" docs/shots/demo
out="$EMIT_OUT"
head_sha="$(git -C "$d" rev-parse HEAD)"
if [ "$EMIT_RC" -ne 0 ]; then
  : # already reported
elif [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" != "1" ]; then
  fail "expected exactly one markdown line, got: $out"
elif [[ ! "$out" =~ ^!\[frame\]\(https://raw\.githubusercontent\.com/octo-fork/civ-life-fork/($SHA_RE)/docs/shots/demo/frame\.png\)$ ]]; then
  fail "line is not an absolute, sha-pinned raw URL for the remote's owner/repo: $out"
elif [ "${BASH_REMATCH[1]}" != "$head_sha" ]; then
  fail "URL sha ${BASH_REMATCH[1]} is not HEAD ($head_sha)"
else
  pass "$out"
fi

echo "[shot-links] 2/6 — the branch name appears nowhere in the URL"
# The failure this rules out is not cosmetic: a branch-pinned URL means a later
# ticket re-capturing under the same filename silently changes the pictures in
# an already-merged pull request.
if [ -z "$out" ]; then
  fail "nothing was emitted, so this check would pass on an empty string"
elif [[ "$out" == *switchboard* || "$out" == *"/main/"* || "$out" == *"/HEAD/"* ]]; then
  fail "a branch name or symbolic ref is in the URL: $out"
else
  pass "no branch name in $(printf '%s' "$out" | sed 's#.*githubusercontent.com/##')"
fi

echo "[shot-links] 3/6 — ssh remote spelling yields the same owner/repo"
d2="$(fixture "git@github.com:another-owner/another-repo.git" ssh)"
emit_ok "$d2" docs/shots/demo
out2="$EMIT_OUT"
if [ "$EMIT_RC" -ne 0 ]; then
  : # already reported
elif [[ "$out2" != *"raw.githubusercontent.com/another-owner/another-repo/"* ]]; then
  fail "ssh remote did not resolve to another-owner/another-repo: $out2"
elif [[ "$out2" == *octo-fork* || "$out2" == *colin-prologue* ]]; then
  fail "owner is not derived from this repository's own remote: $out2"
else
  pass "owner/repo tracks the remote, not a constant"
fi

echo "[shot-links] 4/6 — an uncommitted frame is stated, not linked confidently"
printf 'brand new' >"$d/docs/shots/demo/fresh.png"
# Godot drops one of these next to every image it imports, so a shots directory
# is only all-pictures until the next time the editor or ./test.sh looks at it.
# Linking them produced a broken image per frame and a 404 warning caused
# entirely by metadata.
printf 'godot metadata' >"$d/docs/shots/demo/fresh.png.import"
emit_ok "$d" docs/shots/demo
out3="$EMIT_OUT"
if [ "$EMIT_RC" -ne 0 ]; then
  : # already reported
elif [[ "$out3" != *404* ]]; then
  fail "no 404 warning in the block for an uncommitted frame:"$'\n'"$out3"
elif [[ "$out3" != *"fresh.png"* ]]; then
  fail "the uncommitted frame got no link line at all: $out3"
elif [[ "$out3" == *".import"* ]]; then
  fail "a Godot .import sidecar was linked as though it were a picture: $out3"
else
  pass "block warns the links 404 until the commit is pushed, sidecars not linked"
fi

# The .import sidecar has done its job; it would otherwise keep the next check
# from testing what it means to test.
rm -f "$d/docs/shots/demo/fresh.png.import"

echo "[shot-links] 5/6 — a committed name whose bytes changed counts as uncommitted"
# A re-capture overwrites frames in place. The path still resolves at the sha,
# to the *old* picture — a link that renders the wrong evidence.
rm -f "$d/docs/shots/demo/fresh.png"
printf 'recaptured, different bytes' >"$d/docs/shots/demo/frame.png"
emit_ok "$d" docs/shots/demo
out4="$EMIT_OUT"
if [ "$EMIT_RC" -ne 0 ]; then
  : # already reported
elif [[ "$out4" != *404* ]]; then
  fail "an overwritten committed frame was reported as available:"$'\n'"$out4"
else
  pass "changed bytes under a committed name are not treated as present"
fi

echo "[shot-links] 6/6 — a non-GitHub remote is refused, not guessed at"
d3="$(fixture "https://gitlab.com/someone/elsewhere.git" gitlab)"
emit "$d3" docs/shots/demo
if [ "$EMIT_RC" -eq 0 ]; then
  fail "a gitlab remote produced a raw.githubusercontent.com URL"
else
  pass "refused with: $(head -1 "$TMP/stderr")"
fi

echo "[shot-links] and against this repository's own remote"
# The fixtures prove the emitter reads *a* remote. This proves the value it
# reads here is the one this repository actually pushes to.
emit_ok "$ROOT" docs/shots/world
real_out="$EMIT_OUT"
real_slug="$(git -C "$ROOT" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')"
real_sha="$(git -C "$ROOT" rev-parse HEAD)"
expected_prefix="https://raw.githubusercontent.com/$real_slug/$real_sha/docs/shots/world/"
if [[ "$real_out" != *"$expected_prefix"* ]]; then
  fail "expected URLs under $expected_prefix, got:"$'\n'"$real_out"
else
  pass "$real_slug @ ${real_sha:0:8}"
fi

[ "$failures" -eq 0 ] || {
  echo "ERROR: $failures shot-link assertion(s) failed." >&2
  exit 1
}
echo "[shot-links] all checks passed"
