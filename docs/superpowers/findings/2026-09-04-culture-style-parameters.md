# What a `CultureStyle` should actually carry

**Slice 4 (#35), against the four style trees that exist as of `styles.gd` at
this commit.** The intent's candidate parameter list was written before any
style tree existed. This checks it against four real ones.

The method is deliberately dull: read the four trees, ask of each candidate
parameter "which styles actually differ by this, and can the vocabulary even
say it", and report the answer including where it is inconvenient. Numbers are
the literals in `game/diorama/styles.gd`; where a dimension is a range the
midpoint is used.

---

## The headline

**Only one of the intent's eight candidates is both real and cheap: roof
profile.** Two more are real but live in the wrong place. Three are partly or
wholly unsayable in the current vocabulary — naming them as culture parameters
would be describing geometry the resolver cannot produce. And the single most
used varying parameter in the library, repetition count, is **not on the list at
all**.

The list was not wrong so much as written from architecture rather than from
the grammar. It names things buildings have; the useful list names things
*these trees vary*.

---

## The candidates, one at a time

### 1. Verticality — REAL, but implicit, and not currently a knob

Height-to-width, using each style's own base footprint:

| style | footprint (w × d) | total height | h : w |
|---|---|---|---|
| residential (3 units) | 2.85 × 0.80 | 1.17 | 0.41 |
| civic | 2.10 × 1.35 | 1.17 | 0.56 |
| stepped | 1.35 × 1.35 | 2.79 | 2.07 |
| hero_arch | 5.00 × 1.20 | ~5.40 | 1.08 |

A real five-fold spread, so verticality genuinely separates these buildings.
But it is an **emergent property of a dozen independent literals**, not a
parameter. There is nowhere to put a `verticality: 1.3` that would make a style
taller — a culture would have to reach into every `h` in every tree. Making
this a `CultureStyle` field means first giving the vocabulary a proportional
scale that applies down a subtree, which does not exist.

**Verdict:** right instinct, not yet reachable. Needs a vocabulary change
first, not a culture field.

### 2. Mass height and variation — LARGELY SPECULATION

This is the candidate the real trees contradict most directly.

| style | mass height | varies? |
|---|---|---|
| residential `body` | `[0.60, 1.30]` | yes, 2.2× spread |
| civic `walls` | `0.8` | no |
| stepped `tier0..2` | `0.61` | no |
| hero_arch `west`/`east` | `1.62` | no |

**One of four styles varies mass height at all.** Worse, hero_arch's is a
scalar *on purpose*: `styles.gd` records that written as a range the two piers
sampled independently — channels are keyed on node names — and the arc rested
on the taller one while floating above the shorter. A culture parameter that
widened height variation would reintroduce, as a feature, a bug slice 2 fixed.

**Verdict:** as stated, a parameter that would affect one style and break
another. If something here is worth keeping it is narrower: *how much a
repeated domestic unit varies from its neighbours*, which is residential's
`[0.60, 1.30]` and nothing else's.

### 3. Setback ratio and frequency — HALF REAL, HALF UNSAYABLE

`setback` exists and one style uses it: `stepped`, at `[0.24, 0.30]`. The other
three have none. So as a culture parameter it is a knob on a single style.

**Frequency has no expression whatsoever.** A `stack` carries one `setback` and
applies it at every child boundary. "Steps back every third tier", or "steps
back only above the halfway point", cannot be written. The word *frequency* in
the intent implies a rhythm the grammar has no way to state.

**Verdict:** ratio is real but narrow; frequency is speculation about a feature
that does not exist.

### 4. Tower / spire / arch / dome ratios — MIXED, AND TWO OF THE FOUR ARE UNSAYABLE

- **spire / finial: real.** Two styles carry a vertical accent, and their
  proportions genuinely differ — stepped's spire is 0.79 over 1.83 of tiers
  (0.43); hero_arch's finial is 1.5 over 1.95 of piers (0.77). That ratio is a
  legible cultural difference and is already two scalars in the data.
- **arch: real but singular.** One style has a `ring`. Its `radius`, `count`
  and angular span are all live parameters.
- **tower: does not exist.** No style has one and nothing distinguishes a tower
  from a tall `stack` in the vocabulary. Naming it names nothing.
- **dome: not expressible.** `_ring` in `compose.gd` places its children at
  `(cos·r, sin·r, 0)` and rotates about **Z** — a ring is always a *vertical*
  arc. There is no surface of revolution and no way to orient a ring into the
  ground plane. A dome needs a new primitive, not a culture field.

**Verdict:** two real, two speculative — and the speculative half is the half
that reads most like architecture.

### 5. Courtyard and enclosure bias — SPECULATION, but the nearest miss

Nothing in the library encloses anything. A `row` puts siblings in a line; a
`ring` would be the natural way to say "masses around a void", and it is the
one candidate that is *nearly* reachable — except that, per above, `ring` is
hard-coded to the vertical plane. One parameter (`ring` gets an axis) would
make courtyards sayable. Until then, enclosure bias is a field with nothing to
set.

**Verdict:** speculation today, cheapest of the speculative ones to make real.

### 6. Roof profile — REAL, CHEAP, AND THE BEST CANDIDATE ON THE LIST

| style | cap | taper | oversize |
|---|---|---|---|
| residential | `tapered` | 0.8 | 1.08 |
| civic | `tapered` | 0.5 | 1.06 |
| hero_arch | `box` (entablature) | — | 1.10 |
| stepped | none (a spire instead) | — | 0.50 |

Three distinct cap treatments across four styles, and the two tapered ones
differ by a factor of 1.6 in taper — that is a shallow hipped roof against a
near-pyramid. `taper` is already a scalar, is referenced by nothing else, and
changing it **changes the silhouette**.

**Verdict:** the one candidate that is real, already in the data, and would
move the S3 needle for the cost of one field.

### 7. Monument scale — REAL, BUT IT IS IN THE WRONG FILE

hero_arch's plinth is `[4.6, 5.4]` against residential's body `[0.55, 1.05]` —
about a six-fold linear break in hierarchy, which is exactly what the intent
means. But the *relative* scale that a viewer reads is not in the style library
at all: it is `building_scale = 0.72` and `hero_scale = 1.5`, two exports on
`spike.gd`. Scale is currently a property of the **diorama**, on the stated
reasoning that one style should be able to stand at village and at city size.

**Verdict:** real, and naming it a `CultureStyle` parameter is a decision to
move it off the diorama. That is defensible — how much a culture's monuments
tower over its houses is cultural — but it is a relocation, not a new field, and
it contradicts a reason already written down. Worth deciding deliberately.

### 8. Structural thickness — PARTLY SPECULATION

Only two styles have discrete supporting members: hero_arch's piers and
voussoirs at `w: 0.42`, civic's columns at `w: 0.09`. That is a 4.7× ratio, and
it is *style identity* — a pier is not a slender column — not culture.
`residential` and `stepped` are solid masses with no thickness concept at all;
a thickness multiplier has no referent in half the library.

**Verdict:** applies to half the styles, and on those it risks scaling away the
distinction between an arch and a colonnade.

---

## What the list missed

These are parameters **the four trees actually differ by** that the intent did
not name. They are ranked by how much silhouette they would buy.

1. **Repetition count, and its range.** `residential` draws `count: [1, 3]`,
   civic's colonnade is `count: 5`, the arch's ring is `count: 9`. This is the
   most-used varying parameter in the whole library and it is absent from the
   candidate list. A culture whose porticos have seven columns instead of four,
   or whose terraces run to five units instead of three, differs in outline
   immediately and at gameplay distance. **Strongest omission.**

2. **Oversize — the overhang.** Every cap carries one: 1.08, 1.06, 1.10, and
   stepped's 0.50. This is deep eaves against a flush parapet, one of the most
   legible cultural markers there is in real architecture, and it is already a
   scalar on every capping mass. Nearly free, and it changes the outline.

3. **Frontality — the composition axis.** `civic` uses `axis: "z"` to stand a
   portico in front of a hall; nothing else does. "Does this culture build a
   face you approach, or a block you walk around" is a genuine cultural axis and
   the vocabulary can already say it.

4. **Void-to-mass ratio.** hero_arch's `gap: 2.6` between piers. Arcaded against
   solid is cultural, the word exists, and it is used exactly once.

5. **Where the gold goes.** Both `aspiration` parts sit at the very top — a
   finial, a spire. A culture that gilded its footing or its threshold instead
   would be making a statement about what it honours, and this costs no new
   vocabulary at all: it is a role assignment. This is the one item on this list
   that is *semantic* rather than geometric, and it is the closest thing to
   culture-as-meaning available today.

---

## The S3 bar, answered plainly

> *"Culture must be legible in massing and silhouette, not just surface marks."*

**It is not. The two cultures shipped here differ in colour and in nothing
else, and this is provable rather than a matter of opinion.**

The proof is the pair of frames in `docs/shots/mbs-culture/`. The sheet holds
style, seed and building id fixed across each row, so the two columns are the
same geometry by construction — the test asserts it, comparing the two cells'
vertex arrays for equality. In colour the difference is obvious. Run the same
frame through the intent's own reduction test at six value bands and the two
columns become very nearly indistinguishable.

That is the finding, and it is worth being precise about what it does and does
not say:

- **The styles pass the reduction test.** Four buildings read as four distinct
  things in six greys. The vocabulary is doing its job.
- **The cultures fail it.** Whatever the palettes are doing, it is carried
  almost entirely by hue and by a value structure that survives quantisation
  poorly.
- **The value-separation rule did not cause this and cannot fix it.** That check
  guarantees roles separate *within* a culture, which is what stops a building
  turning into a silhouette of itself. Nothing in it asks two cultures to differ
  from *each other*, and adding such a rule would only make the palettes fight
  for the same tonal range.

**So slice 5's job is item 1, item 2 and candidate 6 — repetition count,
oversize and roof taper.** All three are already scalars in the trees, all three
change the outline, and none needs a vocabulary change. That is the cheapest
route from "recoloured one building" to "two cultures".

The two things that would need vocabulary work first, if they are wanted, are a
proportional scale that applies down a subtree (candidate 1) and a ring that can
lie in the ground plane (candidate 5).

## On gold

Gold stayed scarce, and it stayed scarce for a structural reason rather than a
lucky one. Scarcity is a property of the **styles**: two of four carry
`aspiration`, one part each, and `test_aspiration_stays_rare_across_the_library`
asserts that budget. No choice of colour in a culture file can spend more of it.
What a culture controls is what gold *means against its own walls* — in `sunlit`
it is the second-brightest role, a warm darkening against pale plaster; in
`basalt` it is the brightest thing on the building. Same role, opposite position
in each culture's own value order.

`patina`, the semantic partner, is deliberately not shipped. Verdigris is what
time does to deliberate metal, and nothing in the renderer varies colour with
age — slice 3 ruled weathering out of the condition ladder explicitly. Declaring
the role now would be vocabulary with no caller. It belongs to whichever slice
makes colour a function of condition.
