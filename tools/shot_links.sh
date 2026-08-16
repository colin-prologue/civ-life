#!/usr/bin/env bash
# tools/shot_links.sh — turn captured frames into links that actually render.
#
#   tools/shot_links.sh docs/shots/growth [docs/shots/world ...]
#
# GitHub does not resolve repo-relative image paths in a pull request or issue
# body. `![x](docs/shots/growth/motion.gif)` renders when the surrounding
# markdown is viewed *in the repo tree* — a README — and shows nothing at all in
# a PR description. The two forms are indistinguishable in markdown source,
# which is how a capture harness can ship with every byte verified and still put
# no picture in front of a reviewer.
#
# What does work, checked against a live file:
#
#   https://raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>  -> 200 image/gif
#
# Three things about the URL are load-bearing:
#
# 1. It is pinned to a commit sha, never a branch. A later capture writing the
#    same filenames on the same branch would otherwise retroactively change the
#    pictures in an already-merged pull request, and a merged PR is a record of
#    what was reviewed.
#
# 2. Owner and repo come from the git remote, never from a constant here. A
#    fork or a rename must not silently emit links into somebody else's
#    repository, where they would resolve to *their* file or to nothing.
#
# 3. Whether the files are committed at that sha is checked, not assumed. This
#    is normally run right after a capture, when the frames are new and
#    uncommitted, so the honest default answer is "these 404 until you commit
#    and push". A confident link to a file that is not there is the same class
#    of failure as the relative path — it looks correct in review and shows
#    nothing.
#
# stdout is the paste block and nothing else. Commentary goes to stderr, so
# `tools/shot_links.sh <dir> | pbcopy` copies markdown rather than chatter.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -gt 0 ] || die "usage: tools/shot_links.sh <dir> [<dir> ...]"

command -v git >/dev/null || die "git is not on PATH; the URL cannot be derived without it"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not inside a git work tree; owner, repo and sha are derived from it"

# -P on both sides of the later prefix comparison, or the two disagree the first
# time the tree sits under a symlink: `git rev-parse` reports the physical path
# while the shell's logical `pwd` keeps the link. macOS puts every `mktemp -d`
# under /var -> /private/var, so this is the normal case there, not a corner.
ROOT="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"

# --- owner/repo, from the remote ---------------------------------------------
# Both remote spellings, with or without the .git suffix. Anything that is not
# GitHub is a hard stop rather than a guess: raw.githubusercontent.com is a
# GitHub-specific host and there is no correct URL to emit for a GitLab or
# self-hosted remote.
REMOTE_NAME="${SHOT_LINKS_REMOTE:-origin}"
REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
[ -n "$REMOTE_URL" ] || die "no '$REMOTE_NAME' remote; owner and repo cannot be derived"

SLUG=""
case "$REMOTE_URL" in
  *github.com[:/]*)
    SLUG="${REMOTE_URL#*github.com}"
    SLUG="${SLUG#:}"
    SLUG="${SLUG#/}"
    SLUG="${SLUG%.git}"
    SLUG="${SLUG%/}"
    ;;
esac
case "$SLUG" in
  */*/*|"" |*/) die "remote '$REMOTE_URL' is not a github.com repository — raw.githubusercontent.com has no meaning for it" ;;
  */*) : ;;
  *) die "could not read owner/repo out of remote '$REMOTE_URL'" ;;
esac

# --- the sha ------------------------------------------------------------------
SHA="$(git rev-parse HEAD 2>/dev/null || true)"
case "$SHA" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
  *) die "HEAD is not a 40-character commit sha (got '${SHA:-nothing}'); is this a fresh repository with no commits?" ;;
esac

BASE="https://raw.githubusercontent.com/$SLUG/$SHA"

# --- collect the files --------------------------------------------------------
FILES=()
for dir in "$@"; do
  [ -d "$dir" ] || die "'$dir' is not a directory"
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$dir" -type f ! -name '.*' | sort)
done
[ "${#FILES[@]}" -gt 0 ] || die "no files found under: $*"

# A file counts as present at $SHA only if the blob recorded there is byte-for
# byte what is on disk. "Committed under this name once" is not the check: a
# re-capture that overwrites a frame leaves the path resolving and the picture
# wrong, which is a link that renders somebody else's evidence.
MISSING=0
LINES=()
for f in "${FILES[@]}"; do
  abs="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
  case "$abs" in
    "$ROOT"/*) rel="${abs#"$ROOT"/}" ;;
    *) die "'$f' is outside the repository at $ROOT" ;;
  esac

  at_sha="$(git rev-parse --quiet --verify "$SHA:$rel" 2>/dev/null || true)"
  on_disk="$(git hash-object -- "$abs")"
  if [ "$at_sha" != "$on_disk" ]; then
    MISSING=$((MISSING + 1))
  fi

  # Spaces are the one filename character that silently breaks a markdown link
  # rather than loudly breaking it.
  enc="${rel// /%20}"
  alt="$(basename "$rel")"
  alt="${alt%.*}"
  bang="!"
  case "$rel" in
    *.png|*.gif|*.jpg|*.jpeg|*.webp|*.avif) ;;
    *) bang="" ;;
  esac
  LINES+=("$bang[$alt]($BASE/$enc)")
done

# --- emit ---------------------------------------------------------------------
{
  echo "[links] remote '$REMOTE_NAME' is $SLUG, pinned at $SHA"
  if [ "$MISSING" -gt 0 ]; then
    echo "[links] $MISSING of ${#FILES[@]} file(s) are NOT committed at that sha — the links below 404 until they are."
    echo "[links] commit the frames, then re-run:  ./capture.sh --links $1"
  else
    echo "[links] all ${#FILES[@]} file(s) are committed at that sha; they resolve once it is pushed to $SLUG."
  fi
  echo "[links] URLs follow '$REMOTE_NAME'. If the pull request lives on a different fork, they point here anyway."
  echo "[links] paste into the PR body:"
  echo
} >&2

# The warning is part of the pasted markdown, not just terminal output. If a
# session pastes a block whose files are not committed, the reviewer sees a
# sentence explaining the broken images instead of guessing at them.
if [ "$MISSING" -gt 0 ]; then
  echo "> **These images 404 until commit \`$SHA\` is pushed to \`$SLUG\`.** $MISSING of ${#FILES[@]} file(s) below are not committed at that sha."
  echo
fi

printf '%s\n' "${LINES[@]}"
