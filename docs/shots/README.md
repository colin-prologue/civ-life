# docs/shots — what the game looked like

Frames written by [`../../capture.sh`](../../capture.sh) and committed to the
branch that produced them, so a "does this look right" acceptance criterion can
be judged from a phone instead of from the machine Godot is installed on.

Every ticket from the renderer onward carries at least one criterion an agent
cannot self-certify — some variant of *is this a world worth watching*. Those
are the criteria that matter most here and the ones least likely to get checked,
because checking them used to mean being at a particular desk. A frame in a pull
request does not make the judgement; it just stops requiring physical access to
make it.

## Using it

```sh
./capture.sh --seed 20260815 --turns 0,4,12 --name world   # stills
./capture.sh --movie --seed 20260815 --from 0 --to 8       # a short GIF
./capture.sh --self-test                                   # prove the guard fires
./capture.sh --links docs/shots/growth                     # markdown for the PR
```

Capture, **commit the frames**, then run `--links` and paste what it prints.
That order is not a style preference: the URLs are pinned to `HEAD`, and the
frames are not in `HEAD` until you commit them. Run `--links` before committing
and it will tell you so rather than hand you a link to a file that is not there.

## Why the links look like that

`![x](docs/shots/growth/motion.gif)` does not work. GitHub resolves a
repo-relative image path when the surrounding markdown is viewed *in the repo
tree* — this file, for instance — and does not resolve it in a pull request or
issue body, where it renders as nothing at all. The two forms are
indistinguishable in markdown source, which is how PR #12 shipped with every
frame verified byte-for-byte and no picture visible to anyone reading it.

So the emitted URLs are absolute, and pinned to a commit sha rather than to a
branch:

```
https://raw.githubusercontent.com/<owner>/<repo>/<sha>/docs/shots/<name>/<file>
```

The sha matters for the same reason "old frames are not history" below does,
pointing the other way: re-capturing a name replaces the file, and a
branch-pinned URL would let that quietly change the pictures inside a pull
request that was already reviewed and merged. Owner and repo come from the git
remote, so a fork emits its own links rather than somebody else's.

This depends on the repository staying public. `raw.githubusercontent.com` on a
private repo needs a token, and if that changes, this whole approach does.

## Rules this directory lives under

**Frames are committed, so they are capped.** 6 MiB per invocation, enforced by
the script; going over deletes the run's output rather than leaving it next to a
warning. A repository carries its images forever. Prefer few, well-chosen
frames over a contact sheet.

**Nothing here is a golden image.** These are for a person to look at. There is
no diffing, no perceptual comparison, no fixture to regenerate — storing goldens
would create exactly the brittle cross-architecture artifact the worldgen work
already argued against, and would turn a palette tweak into a fixture update.

**Old frames are not history.** Re-capturing a name replaces it. If a frame
stops matching what the game does, delete it; a stale picture in a directory
called `shots` is read as current.

## The one thing that would make this worthless

Godot's `--headless` uses a rendering driver that rasterizes nothing, and
`Image.save_png()` still succeeds against it. The obvious implementation of this
directory is one full of valid PNG files containing nothing — which is worse
than an empty directory, because it looks like evidence. `capture.sh` checks
every frame for content before writing it, and `--self-test` runs the capture
under `--headless` on purpose to watch the check reject the result. Run that
after touching either the capture path or the renderer.
