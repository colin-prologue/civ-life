# Product intent — procedural art and the rendering layer

**Slug:** `procedural-art`
**Status:** durable. Tickets inherit this with `parent-intent: procedural-art`.
**Revision:** 2 — the diorama direction (2026-08-16). Revision 1 assumed a
purely orthographic 2D vector map; this revision carries the shift to a
shallow-3D procedural diorama. What survived, what changed, and what is
still unproven are all marked.

Adapted from two external implementation briefs (the procedural-art brief
and the diorama update, 2026-08) and two art-direction studies ("The Grown
Map", "The Unbroken Thread"), reconciled against this repo's decisions.
Where an external brief and this file disagree, this file is what the repo
builds against — divergences are listed in "Reconciliations" so they were
chosen, not drifted into.

## North star

The map is not a static illustration of the current world. It is a living
record of geography, choices, use, hardship, abandonment, adaptation, and
inheritance. **The renderer should be able to explain every visible mark
from simulation state.**

The presentation target is a **living procedural diorama**: a monumental
miniature — sculptural terrain, extruded settlements, graphic roads and
cartographic marks printed onto the model — staged with a long lens. The
shorthand: **3D physical form + 2D printed information.** It should read
as a designed, illustrated architectural model of civilization, never as a
conventional low-poly 3D strategy game and never as realism.

Core tone (inherits `world-growth-tone`): decay everywhere, doubt nowhere.
Ruins carry evidence of continuity, not finality. Gold is aspiration and
deliberate human action; verdigris is time, inheritance, and adaptation —
a semantic relationship, not the only literal palette; culture-specific
palettes stay possible.

## Principles (unchanged from revision 1)

- **Geometry describes the present.** Terrain, water, structures, roads,
  current vegetation say what exists now.
- **Marks describe memory.** Ghost roads, foundation traces, scars,
  cultivation patterns, patina, regrowth say what happened before.
- **Density is earned** — and bounded by Rule 6 (see Guardrails).
- **Culture changes the handwriting.** Same event, different shapes,
  motifs, proportions, and line rhythms per culture.
- **Regression transforms; it does not reset.** Old layers remain
  available to future eras.
- **Nature is an active author** — and in 3D it gains occlusion: forests
  can engulf buildings and hide old roads, exposing only the tallest
  ruins. Nature becomes physically competitive with civilization.

**Do not store "the final look" of anything. Store state and history.**
Rendering is a deterministic interpretation of that state. The view holds
no state that would not survive being thrown away and rebuilt from the
world. This contract predates the diorama and outlives it.

## The pipeline (unchanged shape, new outputs)

```
SIMULATION STATE
  → semantic features        (terrain, water, claims, works, culture,
                              age, abandonment, use)
  → visual recipes           (fills, marks, glyph grammars, scars)
  → deterministic variation  (hash channels: jitter, motif, density,
                              omission — inside authored bounds)
  → render output
```

Revision 1's output was polygons and polylines. Revision 2's output adds:
terrain relief meshes, road ribbons, extruded building masses, vegetation
instances, monument geometry, ruin fragments — plus the same surface-line
cartography, now projected onto the model (thin geometry, decals, or
shader lines; whichever is cheapest and reliable).

## Reconciliations

Deliberate departures from the external briefs. A ticket that follows a
brief against one of these is wrong even if well built.

1. **Hash channels, not RNG streams.** All variation derives from pure
   hashes — `hash(world_seed, coord, channel)`, plus feature id where
   needed. Seeded-but-sequential RNG streams are draw-order-dependent and
   break fingerprint tests. Applies identically to mesh generation.

2. **Sim owns history; game owns interpretation.** `HexRenderState`,
   `WorldFeature` lifecycles, and `HistoricalScar` are `sim/` data —
   deterministic, seeded, fingerprinted. Generators, grammars, cameras,
   lighting, and all presentation state live in `game/`. Nothing about
   the diorama changes `sim/`: hexes remain simulation truth even where
   the terrain reads as one continuous landscape. Scars obey tone Rule 1
   — marks and transfers, never erasure.

3. **The renderer trails the sim by at most one step.** No generator is
   built for state that does not exist; the lab (below) covers
   experimentation with synthetic state instead.

4. **Attention outranks atmosphere.** New in revision 2, and the most
   important guardrail the diorama brief lacks. This game's entire
   tension model is attention — "the cost of any choice is the thing you
   weren't watching" — and a perspective camera with occluding ridges,
   engulfing forests, and tilt-shift blur is a machine for hiding
   information. That is romantic and it is also a gameplay statement.
   The rule: **the band where the player directs attention must be
   readable like an instrument** — near-cartographic, minimal occlusion,
   no blur over actionable state. Diorama richness lives in the closer
   bands, where the player has already chosen where to look. Depth of
   field may follow the player's region of interest ("LOD masquerading
   as cinematography"), but must never conceal a change the player would
   need to notice. When composition and legibility conflict at the
   attention band, legibility wins.

5. **The 2D renderer is not deleted until the spike passes.** The
   current vector renderer is the working game, the World band may well
   remain essentially 2D-cartographic forever, and the diorama could
   fail its first test. The diorama is built as a parallel scene, not a
   conversion. If and when the spike (S0 below) validates the direction,
   the platform decision gets an AgDR and `game/README`'s "no camera, no
   scroll, no zoom" constraint is formally revised. Until then that
   constraint stands for the shipping map view.

## Scale bands

Three bands, each defined by the question it answers — not a sliding
continuum of detail. Do not scale objects down at distance; omit
deliberately.

- **World — "where should my attention go?"** Near-cartographic:
  terrain masses, major rivers, biome fields, civilization centers, hero
  silhouettes, the strongest route graph. Almost no building geometry.
  This band is the instrument panel; reconciliation 4 applies in full.
- **Region — "what is happening here?"** The primary diorama: terrain
  relief, forests, settlements, roads, farms, ruins, monuments,
  historical marks.
- **Local — "who is doing it?"** Building masses, vegetation instances,
  minor roads, small scars, reclamation detail — and the diorama
  vignette: walkers, grazers, and flora staged deterministically *from
  hex-level state*. LOD is interpretation, not simulation: the sim says
  "farm node, three workers, herd of eight, autumn"; the renderer
  choreographs it. Sub-hex simulation, if ever wanted, is a sim design
  decision on its own merits — never forced by the camera.

## The diorama form

- **Chunked, not per-hex.** Visible geometry groups into regional render
  chunks (start ~16×16 hexes; a profiling starting point, not a spec).
  No scene tree of thousands of hex nodes. Hexes stay important to
  simulation and placement without staying visually obvious.
- **Relief, not terrain engine.** Elevation becomes shallow faceted
  relief: large geometric planes, stepped forms, exaggerated valleys,
  readable coastlines, recessed water. Architectural model + geological
  relief map + Deco bas-relief. Mountains earn strong silhouettes from
  the gameplay camera; plains stay quiet. Exaggeration is an
  art-direction parameter (`elevation_exaggeration`, `ridge_sharpness`,
  `valley_depth`, `coast_height`, `terrain_faceting`).
- **Long lens, fixed manner.** Subtle perspective (initial range FOV
  15–30°), consistent pitch. The player inspects an enormous model; they
  do not fly through a 3D world.
- **Poster light on sculpture.** One directional light plus simple
  ambient; rough materials, restrained specularity. The outputs that
  matter are silhouette, cast shadow, and plane separation. Long shadows
  are a compositional tool. Quantized tonal bands are a later
  experiment; PBR realism is not the baseline and not the goal.
- **Printed information.** Contours, hachures, field patterns, territory
  and boundary marks, ghost roads, and cultural motifs are drawn onto
  the model surface. The sculpted world and the printed map are one
  object; losing the cartographic language would lose the game's face.

## Architecture as grammar, extruded

No authored asset pipeline. Buildings come from the glyph grammar,
extended into mass: generate footprint → extrude → stack primitive
masses → apply cultural proportions → apply era/prosperity → apply
condition. The authored library stays tiny — on the order of: slab,
wall, column, arch, dome, spire, beam, ring, stepped mass, canopy,
courtyard; ~6 tree forms; ~5 rock forms. Richness comes from
composition, proportion, state, and light — never asset count. The
production rule: **if an environmental asset would need substantial
manual modeling, first ask whether it should be a generator.**

`CultureStyle` extends with 3D parameters (verticality, mass height and
variation, setback ratio/frequency, tower/spire/arch/dome ratios,
courtyard and enclosure bias, roof profile, monument scale, structural
thickness). Population determines how much is built; culture determines
how it organizes; prosperity determines height, regularity, maintenance,
and connectivity; hardship damages and interrupts generated geometry.

**Hero structures.** A rare, simulation-earned feature class whose scale
breaks the hierarchy — great monument, aqueduct, dam, ceremonial arch,
observatory. Their job is to say "they believed they could do this."
They persist across eras and walk the full life cycle: new → celebrated
→ weathered → damaged → ruined → reclaimed → rediscovered → incorporated
by a successor. Most civilization stays small against geography; the
occasional vertical exception is the punctuation that makes the rest
read. (These are the deep-time markers of the art studies, made
load-bearing.)

**Ruins are the same buildings.** No separate ruin assets. Condition
transforms the generated structure itself — 1.0 complete; 0.75 aging and
small losses; 0.5 upper masses gone, broken symmetry; 0.25 structural
remnants, exposed foundations, vegetation intrusion; 0.05 footprint and
a surviving arch or wall — deterministic per feature seed, so
destruction is stable across rebuilds. A culture's handwriting survives
its collapse because the broken geometry preserves its proportions.

**Roads are ribbons with memory.** Generated from route paths; width,
continuity, and edge regularity driven by traffic, technology, age,
condition. Abandonment walks: active ribbon → weathered → broken
segments → surface trace → vegetation-aligned memory. Old routes rarely
vanish; successors preferentially reuse surviving alignments.

**Vegetation is 3D stippling.** The blue-noise placement channels carry
over; a tree is a trunk plus 2–5 canopy masses, instanced. Distribution
still derives from moisture, biome, ecological age, disturbance,
clearing, abandonment. The new capability is occlusion — used per
reconciliation 4.

## Color as state

Semantic roles unchanged: ground, living nature, water, civilization,
aspiration (gold — scarce enough to signal intention), time/patina
(verdigris), memory (muted ghosts), rupture (rare), renewal. New in 3D:
role colors need enough **value** separation to survive light and
shadow, not just hue separation — the palette tests extend to lit and
shadowed variants.

**The reduction test, restated for 3D:** any candidate style must
survive as an unlit flat-shaded silhouette in six colors at gameplay
distance. If identity lives in lighting, blur, or texture, it is not yet
encoded as a rule.

## The lab

Unchanged in role, extended in kind: a standalone scene feeding
**synthetic** `HexRenderState` (and scripted history timelines) into the
real generators. The diorama lab region is ~12–20 hexes of valley:
river, mountains, forest, farmland, road, settlement, one hero monument.
Everything is judged through the capture harness (`tools/capture.gd`,
`shot_links.sh`) so art decisions are reviewable in tickets. The lab is
a fake sim; the renderer cannot tell the difference.

## Experiments, ordered by the assumption they kill

- **S0 — The composition spike (run first).** One question, per the
  diorama brief's own priority: *can procedural faceted relief +
  primitive architecture + instanced vegetation + a long-lens camera
  produce the intended composition at all?* Terrain mesh from synthetic
  elevation, one city grammar, forest instances, road ribbon, one hero
  structure, one directional light, flat materials. No DOF, no shaders,
  no ruins yet. If the answer is no, adjust geometry, camera, and scale
  relationships before adding any system complexity. **The diorama must
  work before the effects do.**
- **S1 — Readability through perspective.** The revision-2 replacement
  for the old 20-px legibility test, and the guardian of reconciliation
  4: at the World band's framing, with ridges and forests occluding, can
  a player still see where their attention is needed? Sweep camera
  pitch, FOV, and occlusion density against a set of "must notice"
  synthetic events. This can reshape the camera spec in a week — better
  now than after the grammar is built against it.
- **S2 — Deep time in one frame.** The historical sequence: the same
  valley, same camera, rendered at year 0 / 800 / 2,000 / 3,500 / 4,200
  / 5,000 / 7,000 — wild, settled, city, peak, hardship, silent forest
  with the hero monument above the canopy, and a new culture on old
  foundations. The mountains never change; the camera barely moves.
  Continuity of place carries deep time. (Subsumes revision 1's
  road-that-remembers and palimpsest experiments; still driven by
  scripted history, no sim needed.)
- **S3 — Two cultures, one valley.** Same geography and population, two
  opposite `CultureStyle` resources including the 3D parameters. Culture
  must be legible in massing and silhouette, not just surface marks.
- **S4 — Collapse without apocalypse.** Prosperous region, hardship
  curve, centuries of reclamation. Ruined must read serene, alive, and
  consequential — never grimdark.
- **S5 — The diorama vignette.** Local band: walkers, grazers, and
  flora choreographed deterministically from hex-level state; ambient
  motion between turns, all view-layer, all seeded. This is where
  "feels alive" gets its test — with AgDR-001's refutation clause in
  view: every vignette element must trace to a state variable.
- **Budget gate (continuous).** The 2D map keeps its 100 ms
  advance-and-redraw test untouched. The diorama gets its own gates
  from S0: chunk rebuild time on state change, and steady frame time,
  measured before any escalation (MultiMesh first, then lower-level
  servers, only on evidence).

What the lab cannot de-risk: whether the *real* sim's state
distributions compose well — synthetic sweeps are uniform, ecology
clusters. That stays open until live variables feed the same recipes,
which is why every sim ticket keeps making its own addition visible.

## Guardrails

- Designed and illustrated, never realistic: no PBR baseline, no bloom,
  no photorealism, no texture that carries the style by itself.
- Negative space is intentional; "density is earned" is bounded by Rule
  6 (fewer and chunkier). If accumulated detail makes a place harder to
  read, the detail is wrong. Legibility outranks richness — and at the
  attention band, legibility outranks composition (reconciliation 4).
- Wild nature stays visually competitive with civilization — now
  physically, via occlusion — but never at the cost of the attention
  band.
- Ruins imply use, adaptation, or incorporation more often than
  desolation. Hero ruins above a canopy are an invitation, not a grave.
- Gold stays scarce; patina tells time. Gold/verdigris is a semantic
  relationship — cultures may express it in their own palettes.
- Catastrophe breaks patterns; recovery creates new patterns that
  negotiate with what survived.
- Prefer rules derived from variables over unique exceptions. When a
  result feels generic, change the grammar, not the noise.
- Mood-board images (including the diffusion boards that seeded this
  direction) are references for composition, palette, and feeling —
  never for detail density. The buildable version is the tiny primitive
  library under deliberate light. Do not chase an image whose richness
  no generator produces.

## Definition of success

The prototype succeeds when this image emerges entirely from simulation
rules and generators:

A small new settlement occupies a river valley. Its buildings belong
unmistakably to a new culture. Farms follow a new geometry. A new road
crosses the faint remains of an older imperial route. Forest covers most
of the former city. Above the canopy stand three enormous verdigris
arches from a monument built thousands of years earlier. Behind
everything are the same mountains that were present before civilization
arrived.

And nothing about the scene implies that history has ended. Loss,
continuity, ambition, inheritance, possibility — the dimensional
expression of *decay everywhere, doubt nowhere*.

If a screenshot is interesting only because a seed happened to be
pretty, the system is not done. Success is pointing at any feature and
saying: that pattern exists because people farmed here for 600 years;
that faint line is the old imperial road; those arches survive because
hero structures outlast domestic fabric.

The renderer's job is to make history visible.

## Addendum — lab findings (2026-08-16)

The headless Blender lab (`tools/blender`) ran the experiment suite ahead
of the Godot spikes: the diorama and culture sheets, the seven-date
sequence, and a 40×30 hex-sourced world with conformance, salience,
cartography, seasons, and reduction passes. What follows are the results,
recorded as rules so S0/S1 inherit them instead of rediscovering them.
Sheets are reproducible from their seeds via `tools/blender/build.py`.

### Confirmed, now rules

1. **The hex data shape is safe — but soften class edges, never terrain.**
   A world built exactly from per-hex state (fields at flat-top axial
   centres, hex-line roads, hex-centre placement) is visually
   indistinguishable from free placement, with one exception: terrain-class
   region edges. Perfect hex boundaries on class tint read as board game
   instantly; hash-displaced corner jitter makes the same regions read as
   organic ground cover. Smooth (IDW-style) terrain interpolation is the
   default; honest stepped hex plateaus are an acceptable terraced
   fallback, not a failure. Roads: Chaikin-smoothed hex-centre paths win;
   raw 60° turns are tolerable but visibly mechanical.
2. **Exaggeration and contrast are band-scaled parameters, not constants.**
   Class-tint contrast that reads correctly up close is camouflage blotch
   at world distance (mute it as the camera rises — "omit, don't shrink"
   applies to color contrast). Mountains need far more vertical
   exaggeration to carry silhouette at world distance than looks right up
   close. Every scale-sensitive parameter should be authored per band.
3. **Salience numbers (first S1 data).** Twelve planted events (building,
   fire, herd) ray-cast against the camera: 12/12 visible at pitch 38° and
   48°, 10/12 at 28°. At this relief the dominant occluder is **canopy,
   not ridges** — forest density near watchable things is the real S1
   design variable. Caveat now part of the method: ray-cast visibility is
   not noticeability; small low-contrast events pass the ray test while
   being visually negligible. Noticing needs size, contrast, or motion,
   and S1-in-Godot must measure that, not just occlusion.
4. **Printed information survives 3D.** Contour ribbons following the
   relief and a territory band read as drawn on the model, not as debug
   overlay. The sculpture+cartography hybrid — the direction's identity —
   holds.
5. **Seasons are a palette re-grade with a held identity.** Four re-grades
   of the same world work when plaster, brass, roads, and water hue stay
   invariant; the world changes together and remains itself. Winter (snow
   world, dark water) is the strongest and costs nothing extra.
6. **The reduction test passes.** Six flat colors and value-only greyscale
   both keep the world legible; the road is the brightest value line on
   the map. Identity genuinely lives in silhouette and value.
7. **Craft rules from the earlier sheets, kept for Godot:** voussoirs lie
   tangent to the arc, not radial; render with a poster transform, not a
   filmic one (Blender: Standard, not AgX — Godot: disable filmic/ACES
   tonemap for this look); faceted-mass vegetation beats cardstock at
   these scales; buildings emit parts tagged (role, height) so ruins are a
   filter, not an asset set; a historical sequence needs a fixed place
   plan with monotonic per-index tree acceptance so forests thin and
   regrow in place; peak prosperity must read vertically (silhouette
   punctuation), not as more building count — count is invisible at world
   distance, and so is sub-silhouette damage.

### Still open (the lab cannot close these)

- **Godot parity.** All lab evidence is raytraced Cycles with soft sun and
  denoising. Real-time shadow maps, AO, and tonemapping may not carry the
  same model-like light — this is exactly ticket #17 (S0), unchanged.
- **Motion — now tested, verdict pending (2026-08-23).** The lab's
  turn-lapse experiment (`build.py --experiment lapse`) renders one
  120-turn valley timeline twice from the identical discrete schedule:
  a naive per-turn redraw (elements appear at full size the turn they
  change) beside an eased interpretation (elements scale in/out over a
  few turns, aging tints move continuously, ruin steps are finer),
  composed side by side in `turn_lapse.mp4`. What the frames certify:
  the eased variant is implementable purely view-side — the sim truth is
  identical in both panels, which is exactly the game layer's contract,
  and easing never desynchronizes from the schedule. Whether the cut
  variant is *acceptable* or easing is *required* is an aesthetic call
  a human makes from the clip; whichever way it lands, the cost of
  easing is one ramp function per element class, so the decision is
  about feel, not budget.
- **Real simulation distributions.** Every lab scene is placed by curated
  rules; whether live sim ecology composes as well stays open until real
  state feeds the recipes.
