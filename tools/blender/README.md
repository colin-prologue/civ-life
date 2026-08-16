# Headless Blender lab

A procedural art-direction laboratory (`parent-intent: procedural-art`):
scripted bpy generators that answer "can ~20 simple geometric rules produce
a visual design space worth exploring?" with contact sheets, not assets.

Nothing here ships in the game. The grammars proven on these sheets are
specs for Godot generators; the renders are evidence for tickets.

## Setup

Runs headless on CPU - no GPU, no display, no Blender install needed:

    pip install bpy   # Blender-as-a-python-module (~330 MB, Python 3.11)

## Usage

    python3 build.py --experiment all       --seed 42
    python3 build.py --experiment culture   --seed 42
    python3 build.py --experiment trees     --seed 42
    python3 build.py --experiment monuments --seed 42
    python3 build.py --experiment time      --seed 42
    python3 build.py --experiment diorama   --seed 421
    python3 build.py --experiment diorama   --seed 421 --culture organic --ruined

Sheets land in `output/` (git-ignored). Each is deterministic from its seed:
same seed, same picture, any machine. A sheet takes ~30-60 s on 4 CPUs.

## Layout

    civlife_blender/
      core.py          seeded channels (hash-based, order-independent),
                       palette, materials, camera/light/render plumbing
      primitives.py    slab, column, spire, dome, blob, stepped mass,
                       arch (as separable pieces), ring, beam, card
      cultures.py      CultureStyle - shape preferences, not assets;
                       DECO and ORGANIC as deliberate opposites
      architecture.py  stepped monument, civic hall, residential, hero arch;
                       parts carry (tag, height) so ruins need no ruin assets
      vegetation.py    conifer/broadleaf/ancient/shrub/dead - faceted and
                       cardstock dialects
      terrain.py       faceted relief with terracing, river carve, road ribbon
      aging.py         condition-driven part removal + debris; same seed,
                       same damage
      diorama.py       the assembled valley (deterministic placement rules)
      build.py         CLI - parameters in, renders out

## Conventions

- All variation flows through `core.chan(seed, *channel)` - independent
  seeded streams per concern, so adding a generator never reshuffles
  unrelated geometry (mirrors the sim's hash-channel discipline).
- One directional key light + soft fill, `Standard` view transform (not
  AgX): poster color on sculpture, per the intent's lighting rules.
- Materials are flat colors from the semantic palette in `core.PALETTE`;
  no textures, no UVs.
