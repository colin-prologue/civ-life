# AgDR-012 — `docs/` is outside the resource tree

**Status:** accepted
**Date:** 2026-08-23
**Relates to:** AgDR-008 and AgDR-011, which put captured frames in the
repository in the first place. Neither considered what the engine would make of
them once they were there.

## Decision

`docs/` carries a `.gdignore`, so Godot's resource importer does not descend
into it. Nothing under `docs/` is a game resource; no `.import` or `.uid`
metadata is generated for anything in there; the directory holds pictures for
humans and GitHub and nothing else. `./test.sh` fails if any such metadata
appears under `docs/` anyway.

Everywhere else under `res://` is unchanged. Sidecars for real assets — the
images under `addons/gut/`, and anything `game/` or `sim/` loads — are generated
and committed exactly as before, because those files *are* resources and the
engine needs their metadata at runtime.

The two rules together are the actual content of this decision: **whether a
file's import metadata belongs in git is decided by whether the engine loads
the file, and it is decided per directory rather than per file.**

## Rejected

**Committing the sidecars.** This is what was done for `addons/gut/`, and then
again for the nine frames under `docs/shots/`. It works, once. It says these
particular files are resources whose metadata belongs in history, which for a
screenshot is false, and it leaves the next capture to rediscover the problem —
which it did, two frames later, in PR #20. Fixing the instance twice is the
evidence that the instance is not the thing to fix.

**A `.gitignore` entry for `docs/**/*.import`.** Cheapest, and wrong in a way
that is hard to see later. `.gitignore` means "generated, don't track it";
`.gdignore` means "not a resource, don't generate it". Only the second is true
here, and the first would leave real files sitting untracked in the working tree
where a future `git add -f` or a repo-wide sweep can still pick them up. It also
puts a Godot-specific rule in a file that has no idea what Godot is.

**Moving the frames out of the repository.** Solves it completely and gives up
AgDR-008: the whole point of committed frames is that a reviewer can judge "does
this look right" from a phone, against the branch under review.

## What would make this the wrong call

**A scene or script needing to load an image from `docs/`.** `load()` and
`ResourceLoader` would return nothing, and the failure would point at the
loading code rather than at this file. The capture harness reads frames back
with `Image.load_from_file`, which goes to disk rather than through the
importer, so it is unaffected — but that is a property of how it happens to be
written, not a guarantee. If documentation images ever need to be real
resources, this is the wrong shape and the split has to move.

**Captured output moving outside `docs/`.** `capture.sh --out` can already point
anywhere. The exclusion follows the directory, not the harness, so frames
written elsewhere under `res://` get sidecars again. That is the same bug in a
new location, and the answer is a `.gdignore` there too — or a rule about where
capture is allowed to write.

**Godot dropping or changing `.gdignore`.** It is an engine convention, not a
project one. If a future version stops honouring it, the guard in `./test.sh`
fires and there is no fallback that preserves the distinction above; the
sidecars would have to be committed and the reasoning here revisited.
