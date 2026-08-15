# AgDR-008 — Visual criteria are reviewed from frames committed to the branch

**Status:** accepted
**Date:** 2026-08-15

## Decision

Acceptance criteria of the form *is this a world worth watching* are answered by
running the game, capturing frames from inside the engine, committing them under
`docs/shots/`, and inlining them in the pull request by relative path.

Three parts of that are load-bearing:

**Capture is in-engine, from the viewport texture.** Not an OS screenshot tool.
macOS screen recording is gated behind a TCC grant an unattended run cannot
obtain, and a denied grant returns a black rectangle rather than an error.

**Every frame is checked for content before it is written.** `--headless` uses a
rendering driver that draws nothing while `Image.save_png()` still reports
success, so the naive version of this produces valid files containing nothing.
The check lives in its own file, taking an `Image`, so its *rule* is testable in
the ordinary suite on a machine with no GPU, while its *wiring* is proved by
`./capture.sh --self-test` running the capture under a real headless Godot and
watching it fail.

**Capture is not part of `./test.sh`.** The suite must stay runnable on a host
with no rendering context. Coupling them would put a GPU on the critical path of
every future test run.

## Rejected

**Golden images and visual diffing.** A human looks at these. Goldens would
create the brittle cross-architecture fixture the worldgen work already argued
against, and would turn a palette tweak into a fixture update.

**Video hosting, or an orphan media branch.** Frames go on the branch, bounded
by a per-invocation byte cap. The orphan-branch fallback is real but is not
built until the cap proves insufficient — carrying that machinery before there
is a size problem is more expensive than the size problem.

**A `DisplayServer.get_name() == "headless"` early exit.** It would catch the
one failure mode already known and would put a string comparison, rather than
the pixel check, on the failure path — so the self-test would exercise the
guard nobody is worried about.

## What would make this the wrong call

**Repository weight.** If capture frames come to dominate clone size, the byte
cap has failed and the answer is an orphan media branch, or a hosted store, not
a smaller cap.

**A reviewer who trusts thumbnails.** The whole mechanism rests on someone
actually opening the images. If frames start getting rubber-stamped, this has
converted an unverified claim into an unverified artifact, which is worse — the
artifact carries authority the claim did not.

**Motion that a GIF cannot show.** The frame rate and colour depth needed to
keep GIFs under the cap are low. Once the simulation has movement subtle enough
that a 64-colour, 10fps, 480px GIF misrepresents it, the format is the wrong
one and this needs revisiting.
