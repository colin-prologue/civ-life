# Early-game practices — the social layer before civilization

**Date:** 2026-08-29
**parent-intent:** `world-growth-tone`
**Status:** design agreed in conversation; not yet planned or implemented
**Scope:** slice 1 of four. Slices 2–4 are sketched under "The arc" and are
deliberately unspecified — speccing them now would guess at answers slice 1
exists to produce.

## Why this, and why now

Five simulation tickets have landed and there is still no player in the world.
More importantly, there is no *society*: the sim has one coupling in it (a herd
standing on a route delays a citizen) and nothing that could be called a
decision by anyone other than the person pressing Space.

The owner's stated direction (2026-08-28) is to go deeper on the simulation
before touching civilization advancement — nature alive and vibrant, tribe
behaviour focused on survival, and an answer to what the player *is* and what
influence means before there is any polity to have standing in.

`AgDR-003` already answers the last question, but it answers it for a
civilization-era game: a faction inside a polity, spending standing on decisions
a polity makes. At band scale there is no polity. This design is what that
relationship looks like at era zero, built so that it *becomes* AgDR-003's shape
rather than being replaced by it.

## What the reference material actually says

`AgDR-004` names Adrian Tchaikovsky's *Children of Time* as the source of
Understandings. Re-reading the series for where its conflicts arise is what
produced this design's central move, so it is recorded rather than left implicit:

- **Conflicts in those books are almost never about scarcity.** They are about
  incompatible visions of what a society is — the Portiid male-rights arc, the
  Messenger-as-god argument, the uploaded minds at war over what creation should
  be. Resource commitment is the *residue* of the argument, not the argument.
- **Where scarcity does drive a society (Landfall, in *Children of Memory*), it
  produces paranoia, scapegoating and witch hunts** — precisely the tone this
  project forbids. That is outside evidence for the abundance baseline, not just
  a preference.
- **Fabian's arc is the model for influence without power.** A male Portiid may
  not lead, may not hold a peer house, and is not protected by law. He changes
  the civilization anyway, over generations, by being demonstrably useful and by
  getting an Understanding to spread.
- **Understandings are held by lineages and confer status.** Knowledge is not a
  tech tree there; it is the social hierarchy.

The consequence for this design: **influence is not a currency and not a
persuasion roll. It is the spread of a way of doing things.**

## The move this design rests on

The project's own README already describes the player as *"a clan, a house, a
lineage of practice."* That phrase fuses two things this design had been
treating separately, and taking it literally collapses the system by one whole
component:

**A lineage IS its practice. Taking up a practice and belonging to that lineage
are the same event.**

Therefore standing is not a second quantity needing reconciliation with
population — **a lineage's size and its standing are one number seen from two
sides.** Your practice spreading is your family growing. There is no influence
stat because there was never a second thing to measure.

## Evidence: what was measured before committing

Two throwaway probes were run against the current worldgen (scripts not
retained; findings are). Both are reproducible from the parameters stated.

### Probe A — is any practice dominant?

Every land tile across eight seeds, scored as a household start position, with
three candidate practices over one idealised year. Travel cost per hex is the
parameter that decides the outcome:

| travel cost / hex | tend | follow | range |
|---|---|---|---|
| 0.00 | 27.4% | 72.6% | 0.0% |
| 0.02 | 27.4% | 57.8% | 14.9% |
| 0.04 | 27.4% | 52.7% | 20.0% |
| **0.06** | **27.4%** | **47.2%** | **25.5%** |
| 0.10 | 40.6% | 19.5% | 39.9% |
| 0.16 | 48.2% | 2.6% | 49.2% |

**0.06 is `Herd.DISTANCE_COST`** — a value already in the sim, chosen for
unrelated reasons. At the cost the world already charges for walking, the three
practices split 27 / 47 / 26, with none above half and all three winning
somewhere on every seed tested.

**Finding: no dominance, and the balance lever already exists.** The scoring
functions were invented for the probe, so read this as a statement about the
world's variance structure rather than a validated model.

### Probe B — does the world vary from year to year?

Herd positions and populations fingerprinted at each year's turn, 60 years:

| seed | outcome |
|---|---|
| 20260815 | settles at year 9, repeats **every 2 years** |
| 42 | settles at year 36, repeats every 4 years |
| 7 | settles at year 43, repeats **every 1 year** — fully static |
| 987654321 | no exact repeat within 60 years |

**Finding, and it invalidated an earlier assumption in this design: the world
converges to a fixed cycle.** Three of four seeds become periodic, one within a
decade.

It is structural rather than unlucky. `AgDR-009` makes forage a pure function of
`(terrain, season)` and terrain never changes, so the forage field is exactly
periodic with the year; herds are the only stateful thing, and a deterministic
gradient-follower over a periodic field falls into a limit cycle.

The fingerprint is exact string match over float populations, so it
**under-reports** convergence — a world can be effectively static while failing
the exact test. Convergence is at least as bad as measured.

**Consequence:** a design whose engine is "the world changes, so which practice
pays changes" has no fuel in the sim as it stands. Adoption would converge
within a few decades and the social layer would go inert. This is the reason
crowding (below) is a required mechanism rather than a tuning detail.

## Architecture

### Four things, one of them not stored

| Unit | What it is |
|---|---|
| **Person** | An `Agent` with a position and a household. No name, no mood, no trait, no skill, no relationship, no preference. |
| **Household** | The smallest unit that decides. Carries its practice and what it got last cycle. Five to twelve per band. |
| **Practice** | A policy — what a person consults to choose their next action. Held by a lineage; a lineage *is* its practice. |
| **Standing** | Derived, never stored. The share of the band following your practice, which is the same as your lineage's size. |

**Individuals have bodies, never interiors.** The moment a person has a mood the
game becomes triage — someone is unhappy, go fix them — which is a management
loop and the opposite of the observational one this project wants. A colonist
having a breakdown will always outrank a forest quietly reaching density.

Apparent individuality is a **rendering** concern and is already specced:
`procedural-art` S5 choreographs walkers and grazers deterministically from
hex-level state. A person can have a gait and a load with `sim/` knowing none of
it.

### A practice is a policy, not a modifier

This distinction is the whole design. `+10% forage` is a number the player
optimises. *"My people follow the animals"* versus *"my people stay at the river
and work one place"* is a **visibly different band on the map**, and whose way is
winning can be read without opening anything.

`Agent.step(world)` already exists. A practice is what `step` consults. Herds
already do exactly this with their sensed gradient (`AgDR-010`); a practice is
that idea made plural and made social.

Three to start — chunky per tone rule 6, each best where the others are weak:

| Practice | The band | Pays off when |
|---|---|---|
| **Follow** | moves with the animals | herds are rich and moving |
| **Tend** | stays, works one place | a place is stable and productive |
| **Range** | spreads wide, covers ground | the world is varied and things are far apart |

### Decisions are punctuated and staggered

Households reconsider on an interval, not continuously and not on a fixed
calendar boundary. `RECONSIDER_INTERVAL_TURNS` is one tunable constant so
different pacing models can be tested.

Each household's **phase offset within that interval is derived from a stable
hash of its identity**, so the band never flips on a single synchronised
decision day. Adoption reads as continuous while remaining punctuated and
countable.

At its reconsideration, for each household:

```
mine   = what my practice got me over the last interval
theirs = the best result among households I was NEAR during it
if theirs > mine * (1 + my_threshold):
    take up that practice
```

**`my_threshold` is derived from a stable hash, not tuned per household.** Some
change on slight evidence; some hold out for generations. That buys three things
from one hash channel: a real diffusion curve (early adopters, majority,
holdouts), character without interiority ("the Antlers are stubborn" being a
true and observable statement about a household with no personality field), and
determinism intact per intent reconciliation 1.

**Local, not global.** "Households I was near" is spatial. You learn from who you
camped beside, which is what makes positioning the vehicle for influence and
keeps knowledge geographic.

### Payoff is perishable surplus

Under abundance the metric cannot be food, because the answer is always "enough".
It is what is left over:

```
surplus = what a household's people gathered  (practice-dependent)
        − what they needed                    (forage_demand, exists today)
```

**Surplus is local and perishable — never banked, pooled, or transferred.** This
is what stops it becoming a currency the player totals (tone rule 6), and it
makes placement matter: a household with a good year and nothing near it to
spend on has wasted the year.

### Crowding is required, not optional

Probe B says the world stops varying. Rather than importing variation from
outside (terrain change, weather), the social system generates its own:

**A practice's payoff falls as more households adopt it**, read through the
existing per-tile census `forage_demand_at()`.

Four properties, and the last is why it is in the design rather than being a
balance patch:

- It generates variation endogenously, needing no new world state.
- It is tone rule 3's restoring force, structurally rather than by tuning.
- It is tone rule 4 exactly — two existing systems reading each other rather
  than a third being added.
- **Influence becomes self-limiting.** You cannot have the whole band adopt your
  way, because the moment they do, your way stops being the best one. Success
  carries its own ceiling and nobody had to author a penalty. This is what keeps
  "you will want things you cannot simply cause" true even while you are winning.

**Crowding is a hypothesis, not a measured result.** It cannot be spiked without
the practice system existing, which is why re-running Probe B against it is an
acceptance criterion rather than a follow-up.

## Functional requirements

**FR-1** A household is `sim/` data with a practice, a member list, and a record
of its last interval's surplus. No `Node` dependency, constructible headless.

**FR-2** A practice is a policy consulted by `Agent.step()`. Adding a practice
adds no branch to `Agent` or `WorldMap` — `AgDR-013` holds: agents report
quantities and nothing asks them what they are.

**FR-3** Three practices ship: Follow, Tend, Range. Each is best somewhere on
every seed tested; none exceeds 50% of land tiles at `Herd.DISTANCE_COST`.

**FR-4** `RECONSIDER_INTERVAL_TURNS` is a single named constant. Changing it
changes the pacing of every household and nothing else.

**FR-5** A household's phase offset within the interval and its adoption
threshold are both derived from `h01(seed, household_id, purpose)`. No sequential
RNG anywhere (intent reconciliation 1).

**FR-6** Adoption compares against households that shared tiles or neighbouring
tiles during the interval — never a global ranking.

**FR-7** Surplus is computed per household per interval, is not carried across
intervals, and is not transferable between households.

**FR-8** A practice's realised payoff on a tile falls as forage demand on that
tile rises, read through `forage_demand_at()`.

**FR-9** Nothing in this system removes a person, a household, or anything built.
A practice that stops paying loses adopters; it does not kill anyone (tone rules
1 and 2).

**FR-10** Determinism: same seed, 2,000 turns, two worlds equal — including
household practices, member counts, and surplus records.

## Testing

Headless, per the repo's rule that the suite runs without a rendering context.

- **Non-convergence (the criterion this design exists to satisfy).** Probe B's
  fingerprint, re-run with the practice system and crowding active, asserting the
  world does **not** settle into a repeating cycle within 200 years. A design
  that converges has failed regardless of how well it is built.
- **No dominance.** Over a standard seed set, no practice holds more than a
  stated share of households in steady state.
- **Diffusion shape.** A practice introduced to one household spreads to some
  but not all, over multiple intervals rather than in one step, with holdouts
  persisting past the median adopter.
- **Channel stability.** Adding a household leaves existing households'
  thresholds and phase offsets unchanged — the named-channel promise, and the
  test most likely to catch a regression to index-based hashing.
- **Restoring force.** Perturb — force the whole band onto one practice — run
  forward, and assert adoption diversifies again. Tone rule 3, assertable.
- **No erasure.** After any run, every household and every placed thing still
  exists.
- **Determinism** across two processes, via the existing fingerprint mechanism.

## Done bar for slice 1

- Households, practices, adoption and crowding in `sim/`, running headless
- Three practices as policies consulted by `Agent.step()`
- Punctuated, staggered reconsideration on one tunable constant
- Perishable surplus computed from the existing `forage_demand()`
- The non-convergence test green over 200 years on the standard seed set
- The tests above green in `./test.sh`
- A decision record (below)

## The decision record this needs

An AgDR stating: **individuals have bodies and no interiors; a lineage is its
practice; standing is population and is derived rather than stored.** It
partially amends `AgDR-003`, which anticipated standing as a quantity of its own,
and it should say what would refute it — the likeliest refutation being that
drift-based membership never produces a *moment*, so gaining a household reads as
attrition arithmetic rather than as people choosing.

## Explicitly out of scope

Player input and placement (#27), the turn readout that would surface adoption
(#28), household growth and splitting, works and monuments, storage as a
practice, per-culture anything, conquest, Understandings as distinct objects,
any UI, and the civilization-advancement layer entirely.

## The arc (not specified here)

2. **Growth and share.** Sustained surplus adds people; households split. This is
   where standing becomes visible as a number, and where "grow the tribe" is
   answered.
3. **The player's lineage.** #27's placement verb, pointed at your own household
   rather than at the world. Influence becomes positioning: put your people where
   your practice will be seen working.
4. **Works, and storage as a practice.** Surplus pointed at something that
   persists. **The granary is an invention** — the lineage whose practice keeps
   this year's surplus into next year is the transition from band to settlement,
   which means the farm/granary/walker code already in `sim/` is the far end of
   this arc rather than something this design bypasses.

## Risks

**Crowding may not break periodicity.** It is the load-bearing untested
assumption and it is the plan's first task. If it fails, the fallback is
exogenous variation via terrain change (#31), which is more machinery for the
same result.

**Drift may be emotionally flat.** Membership changing by slow percentage risks
reading as attrition rather than as people choosing. #28's readout is what would
have to carry it, which makes #28 a dependency rather than a companion.

**"Near" is an invisible difficulty setting.** How near, for how much of an
interval, decides whether ideas cross the map or stay in one valley. It should be
surfaced rather than buried.

**The probe's scoring functions were invented.** Probe A says the *world* has
enough variance structure for three practices. It does not say these three
practices, implemented properly, will land the same way.
