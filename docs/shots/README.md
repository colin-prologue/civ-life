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
```

The command prints the markdown to paste into the PR body. Paths are
repo-relative, so GitHub renders them inline without anyone downloading
anything.

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
