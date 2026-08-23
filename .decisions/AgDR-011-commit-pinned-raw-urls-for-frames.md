# AgDR-011 — Frames are linked by commit-pinned raw.githubusercontent.com URLs

**Status:** accepted
**Date:** 2026-08-15
**Amends:** AgDR-008, which said frames are inlined "by relative path". They are not.

## Decision

A pull request shows captured frames through absolute URLs of the form

```
https://raw.githubusercontent.com/<owner>/<repo>/<sha>/docs/shots/<name>/<file>
```

emitted by `./capture.sh --links <dir>`. Three parts are load-bearing:

**Absolute, not repo-relative.** GitHub resolves a relative image path when the
markdown is viewed in the repo tree and does not resolve it in a PR or issue
body. AgDR-008 assumed otherwise, and PR #12 shipped on that assumption with
every frame verified and nothing visible to a reviewer.

**Pinned to a sha, not a branch.** Re-capturing a name replaces the file
(AgDR-008: "old frames are not history"). A branch-pinned URL would therefore
let a later ticket change the pictures inside an already-merged pull request,
and a merged PR is a record of what was reviewed.

**Owner, repo and sha are derived from git, never constants.** A fork or a
rename that emitted links into the original repository would show a reviewer
somebody else's frames, or none.

Because the frames cannot be committed at the sha that exists while they are
being written, the emitter checks and says which state it is in, and is meant to
be re-run after the commit. It compares blob contents, not just path presence:
a re-captured frame under a committed name resolves to the old picture, which is
a link that renders the wrong evidence rather than no evidence.

## Rejected

**GitHub's attachment CDN.** Renders anywhere and needs no commit, but it takes
an interactive drag-and-drop an agent cannot perform, and it detaches the image
from the repository — the artifact outlives the branch that explains it.

**A `?raw=1` blob URL, or `github.com/<owner>/<repo>/raw/<sha>/…`.** Both work.
Neither is shorter or more stable than the host that exists to serve file bytes.

**Auto-editing the PR body.** The script prints; a session pastes. Writing to
the PR needs a token and turns a review artifact into something an agent can
change after review.

## What would make this the wrong call

**The repository going private.** `raw.githubusercontent.com` then requires a
token, every emitted link 404s for a logged-out reader, and the mechanism has to
be rebuilt on attachments or a hosted store.

**Pull requests from forks becoming normal.** The URLs follow the remote the
script can see. If work routinely pushes to a fork while the PR lives on the
upstream repo, the emitted links point at the fork — correct, but the reviewer's
mental model says otherwise, and the answer is probably to read the PR's head
repo rather than the local remote.

**Frames moving off the branch.** If the byte cap ever fails and AgDR-008's
orphan-media-branch fallback gets built, the sha in these URLs stops being the
sha of the commit under review, and the pinning argument has to be remade
against whatever holds the images.
