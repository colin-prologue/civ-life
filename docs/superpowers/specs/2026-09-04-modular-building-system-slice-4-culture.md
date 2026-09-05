# Modular building system — slice 4: culture

**Ticket:** #35. **Parent intent:** `procedural-art`, experiment S3.
**Follows:** slice 3 (`2026-08-29-modular-building-system-slice-3-condition.md`).

---

## Why this, and why the obvious version fails

Slice 1 shipped a single default role→colour mapping. The ticket's mechanical
ask is to make that mapping a property of a culture, so one style tree rendered
under two cultures produces two different buildings.

The ticket also names the trap, and a measurement confirms it before any code is
written. The four migrated styles draw from an almost identical role set:

| style | roles used | sampled ranges |
|---|---|---|
| residential | `plaster`, `ochre` | 4 |
| civic | `plaster`, `plaster_dim`, `ochre` | 4 |
| stepped | `plaster`, `plaster_dim`, `brass` | 3 |
| hero_arch | `plaster`, `plaster_dim`, `ochre`, `brass` | 1 |

Everything is plaster with an ochre roof and a brass tip. **Two cultures
resolved through different palettes therefore produce the same four buildings
under a global colour filter.** That is not culture; it is a tint.

`procedural-art` experiment S3 sets the bar this must clear: *"culture must be
legible in massing and silhouette, not just surface marks."* So a culture must
modulate the shared vocabulary — the intent forbids forking geometry, since
ruins, the assembly tween and the whole vocabulary rest on one tree per style.

(Incidental finding: `ROLES` defines `wood` and no style uses it. Dead entry.)

---

## Architecture

### 1. A culture is data, in the shape a style already has

```gdscript
static func highland() -> Dictionary:
    return {
        "name": "highland",
        "palette": {"plaster": Color(...), "ochre": Color(...), ...},
        "verticality": 1.25,   # scales every sampled `h`
        "thickness": 0.85,     # scales every sampled `w` and `d`
        "setback": 1.40,       # scales every sampled `setback`
        "variance": 1.20,      # widens or narrows every sampled range
        "crown": "dome",       # what `kind: "crown"` resolves to
    }
```

A static function returning a dictionary, exactly like `DioramaStyles`. Nothing
new to learn, and it stays as thrash-able as the styles are.

### 2. Culture modulates the RANGE, not the sampled value

A spec of `h: [0.6, 1.3]` under a culture is transformed before sampling:

```
mid   = (lo + hi) / 2
half  = (hi - lo) / 2 * variance
lo'   = (mid - half) * scale
hi'   = (mid + half) * scale
```

where `scale` is the culture's multiplier for that purpose. A scalar `h: 0.6` is
a degenerate range and simply scales.

**Which purpose takes which multiplier** — the mapping is explicit, and anything
not listed is deliberately unmodulated:

| purpose | multiplier | why |
|---|---|---|
| `h` | `verticality` | The massing lever. Tall thin peoples versus low heavy ones. |
| `w`, `d` | `thickness` | Wall and pier heft. Reads at close range where verticality does not. |
| `setback` | `setback` | How sharply a stepped mass tapers. |
| *(all of the above)* | `variance` | Applied to every modulated range's half-width. |
| `oversize`, `taper` | — | Relative to the mass they modify; scaling them twice would compound. |
| `radius`, `from`, `to` | — | A ring's arc is a *shape*, not a proportion. Scaling an arch's radius while its voussoirs thin would break the arc's fit against its piers, which slice 2 spent a review round getting right. |
| `advance`, `gap` | — | Row spacing is rhythm, and rhythm is the repetition lever that was deferred out of this slice. |
| `count` | — | Sampled by `_sample_count`, not `sample()`, so it is unmodulated by construction. Also the deferred repetition lever. |

**Why the range rather than the value.** How *uniform* a civilization's
architecture is, is itself a cultural trait — a rigid imperial culture builds to
a template, a vernacular one does not. Modulating the sampled value can only
move the mean; modulating the range moves the mean and the spread both, for the
same cost. Adding `variance` later would otherwise mean revisiting every call
site a second time.

### 3. The property that makes culture read as variation, not noise

**The channel draw `u` is untouched. Only the range it maps into changes.**

Building id 7 under two cultures draws the *same* `u` for every purpose, and so
lands at the *same relative position* in each modulated range. The two cultures'
version of one building are recognizably the same building, differently
proportioned.

This is load-bearing and it constrains the implementation: **the culture must
never enter `channel()`.** If it did, the same id under two cultures would draw
unrelated values and culture would read as reseeding rather than as a people's
way of building. Every style would look like a different building, which is the
failure this design exists to avoid.

It also means culture composes with slice 3 for free: `need` bands are computed
from node structure and untouched by culture, so ruins still work, and the
cross-process determinism gate still holds.

### 4. Crown substitution — the silhouette half

A style writes `kind: "crown"` where it currently writes `cone` or `tapered`.
The culture maps that abstract kind to a concrete primitive at resolve time.

| culture `crown` | primitive | reads as |
|---|---|---|
| `"spire"` | `cone` | a point |
| `"dome"` | `dome` | a curve |
| `"hip"` | `tapered` | a pitched roof |
| `"parapet"` | `box` | a flat crown |

`stepped`'s spire, `residential`'s roof, `civic`'s roof and `hero_arch`'s finial
all become crowns, so one edit per style changes every roofline in a
civilization. Roofline is what the eye resolves first at settlement distance,
which is why this is the cheapest change that satisfies "silhouette".

**A gap this exposes.** `emit()` already handles `"dome"` and `DioramaMeshKit`
already has `add_dome`, but `_params_for` does not produce dome params — a style
writing `kind: "dome"` today hits its `unknown mass kind` assert. Slice 4 must
add that arm: `{"radius": w * 0.5, "squash": ...}`. This is a pre-existing hole,
not one this slice introduces.

### 5. `sample()` takes a ctx

`sample(spec, seed, id, path, purpose, dflt)` has no way to see a culture, and
threading one through as a seventh positional argument at a dozen call sites is
worse than the refactor. It becomes:

```gdscript
static func sample(spec: Variant, ctx: Dictionary, path: String,
        purpose: String, dflt: float) -> float
```

`ctx` already carries `seed`, `id` and now `culture`. `path` stays separate
because `_ring` samples its children at `child_path`, not at `ctx["path"]`.

This shortens every call site rather than lengthening it, and it puts the
purpose→multiplier lookup in one place instead of at each caller.

### 6. Where it plugs in

- `culture.gd` — **new.** The culture library and the modulation arithmetic.
- `compose.gd` — `ctx` carries the culture; `sample()` consults it; `_params_for`
  resolves `crown` and gains its `dome` arm. Stays pure: no rendering, no scene
  tree, no I/O.
- `apply_roles(parts, ROLES)` → `apply_culture(parts, culture)`, reading
  `culture["palette"]`.
- `condition.gd`, `mesh_kit.gd`, `grammar.gd` — **untouched.**

---

## Components

| File | Change |
|---|---|
| `game/diorama/culture.gd` | **New.** Three cultures as data, plus `modulate(spec, culture, purpose)` |
| `game/diorama/compose.gd` | `sample()` takes ctx; `crown` resolution; `dome` params; `apply_culture` |
| `game/diorama/styles.gd` | Four styles switch their crowning masses to `kind: "crown"` |
| `game/diorama/culture_sheet.gd`, `.tscn` | **New.** Culture × style sheet |
| `test/test_diorama_culture.gd` | **New.** Modulation and identity properties |
| `test/test_diorama_compose.gd` | Updated for the `sample()` signature |
| `tools/diorama_compose_fingerprint.gd` | Fold a second culture in |
| `docs/shots/mbs-culture/` | The committed sheet |

---

## The culture × style sheet

Three cultures down, four styles across, all at condition 1.0. Slice 3 owns the
condition axis; mixing them would confound the read.

The sheet answers S3 and nothing else: **can you tell two civilizations apart,
and is the difference in massing and silhouette rather than colour?** A useful
control: the same sheet rendered in one shared palette. If the cultures are still
distinguishable with colour held constant, the geometry is doing the work.

---

## Functional requirements

1. A culture is a dictionary; three exist, differing in all of palette,
   proportion multipliers and crown.
2. Modulation transforms the range before sampling, per section 2.
3. **The channel draw is unmodified by culture.** Asserted directly: for a fixed
   seed and id, `channel()` returns identical values under every culture.
4. **Relative position is preserved.** For any sampled value, its position within
   its own modulated range is identical across cultures.
5. `kind: "crown"` resolves through the culture; all four styles use it.
6. `_params_for` gains a `dome` arm.
7. Determinism holds across processes, with a second culture folded into the
   existing fingerprint gate.
8. `compose.gd` performs no rendering, no scene-tree access and no I/O.
9. The culture × style sheet is committed under `docs/shots/` and linked per
   AgDR-011, plus the colour-held-constant control.
10. `./test.sh` exits 0.

**Human — not self-certifiable by an agent:**

11. Do the three cultures read as different peoples, or as one people with three
    paint schemes? Name any pair that fails.
12. Does each style stay recognizably itself across cultures? A `residential`
    that is unrecognizable under culture B means the multipliers are too strong,
    and the fix is smaller numbers rather than a redesign.

State in the PR body that AC11 and AC12 are unverified by the agent.

---

## Testing

1. **Channel invariance under culture** — the property everything rests on.
2. **Relative position preserved** across cultures for the same seed and id.
3. **Modulation arithmetic** — a scalar scales; a range moves and widens; a
   `variance` of 1.0 leaves width unchanged; a `scale` of 1.0 leaves the range
   unchanged. Each asserted so that mutating the formula fails it.
4. **Crown resolution** — each of the four crown names produces the expected
   primitive kind, and an unknown crown asserts rather than silently boxing.
5. **`dome` params** are what `emit()` reads, checked against `add_dome`'s
   signature rather than assumed.
6. **Cultures actually differ** — for a fixed seed and id, at least one sampled
   dimension differs between every pair of cultures. Asserted by *finding* the
   difference, not by comparing one dimension that might coincide.
7. **Ruins still work** — a culture-modulated building filtered at each condition
   rung still obeys ordered loss, so slice 3's guarantees survive slice 4.
8. **Determinism** through the existing cross-process gate, with two cultures.

---

## Done bar

1. Every acceptance criterion met or explicitly answered.
2. `./test.sh` exits 0.
3. Both sheets committed and linked.
4. The PR states AC11 and AC12 are unverified by the agent, and reports whether
   the colour-held-constant control still distinguishes the cultures.

---

## Explicitly out of scope

- The `choice` node, and repetition/enclosure bias. Deliberately deferred: they
  need a vocabulary feature that does not exist, and the owner scoped this slice
  to massing and silhouette.
- Culture affecting `need`, decay or the condition ladder.
- Per-culture *new* styles. One vocabulary, modulated — forking geometry is what
  the intent forbids and what makes ruins possible.
- Weathering, patina, or any colour change with condition (slice 3's non-goal,
  restated because a palette slice invites it).
- Procedurally generating cultures from a world seed. The parameters are all
  numeric, so this stays open; three hand-authored cultures are enough to test
  whether the mechanism expresses culture at all.
- `sim/` — untouched. Nothing there has a culture yet.

---

## Risks

**The multipliers may be too strong or too weak, and the sheet is the only
instrument.** Slice 3 needed three attempts at a distribution rule, each looking
fine in summary. Expect at least one tuning round here, and prefer measuring a
census of resulting dimensions over judging from a single frame.

**Recognizability and differentiation pull against each other.** Strong
multipliers make cultures distinct and styles unrecognizable; weak ones do the
reverse. AC11 and AC12 are deliberately a pair, and if they cannot both be
satisfied, that is the finding — it would mean proportion alone is insufficient
and the `choice` node is needed sooner than planned.

**A `variance` below 1.0 could invert a range.** `half` scales toward zero, never
past it, so `lo' <= hi'` always holds — but the assertion in `sample()` that
catches reversed ranges must run on the MODULATED range, not the authored one,
or a bad multiplier would slip past the guard that exists to catch typos.

**Four styles is a thin basis for extracting culture parameters.** The intent's
candidate list (courtyard bias, tower/dome ratios, structural thickness) was
written before any style existed; this slice implements the three that the four
real styles visibly differ by, and the honest output includes which candidates
still have no style to justify them.

**Concurrency.** A peer session holds `.claude/worktrees/vitality-wear` on
`claude/land-vitality-wear`. Check `gh pr list --state open` before dispatch, and
run the suite against the **merge result on main** — #43 was merged across #40
and that pairing is exactly how the #17 collision was missed.
