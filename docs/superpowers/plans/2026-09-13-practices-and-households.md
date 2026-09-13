# Practices and Households Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a society in the world. Households follow a practice, people act on it, what a practice earns depends on land that remembers being worked that way, and households take up their neighbours' practice when it is visibly doing better — so that a lineage grows by its way of doing things spreading, and no practice can win permanently.

**Architecture:** Three new `sim/` types and one new registry. `Practice` is a policy — pure functions from a world and a position to where a person goes and what they take — with no state of its own. `Household` is the unit that decides: a practice, members, and what it got last interval. `Person` is an `Agent` that consults its household's practice. `WorldMap` gains a `households` array beside `nodes`, and `Land.Use` gains one row per practice so that working a tile one way wears only that way. Reconsideration is punctuated and phase-staggered off a stable hash, never a global decision day.

**Tech Stack:** Godot 4 / GDScript, GUT for tests, `./test.sh` for the suite, the cross-process determinism gate and the periodicity gate.

**Spec:** `docs/superpowers/specs/2026-08-29-early-game-practices-design.md`
**Record:** `.decisions/AgDR-020-a-lineage-is-its-practice.md` (proposed; ratify before task 4)
**Tickets:** #60 (tasks 1–3), #61 (tasks 4–6), #62 (tasks 7–8)

## Scope

This is **plan 2 of 2** for the spec's slice 1. Plan 1 (land vitality, `AgDR-014`) is merged: per-use vitality, depletion, unconditional recovery, FR-8, and the FR-8a/FR-8b gates in flight on #42. **Do not rebuild any of it.** What this plan adds is the social layer the spec's FR-1 through FR-7 and FR-9 through FR-11 describe, plus the practice rows FR-8 needs.

What plan 1 already settled, and what this inherits rather than re-decides:

- Vitality is per use, floored above zero, recovering unconditionally toward the terrain ceiling (`sim/land.gd`).
- Sharing a tile is settled against **forage and census frozen at the start of the turn**, so no agent's outcome depends on where it sits in the agents array. Any new agent that divides a tile's yield must do the same — `Herd._graze()` is the worked example, and it took four review rounds to get right.
- Herds now travel 10–32 tiles over 500 turns and all 14 leave a camp's reach, which discharges the spec's "migration may not be a real escape route" risk. Follow has somewhere to follow to.

## Global Constraints

- **`sim/` stays headless** — no `Node`, no rendering, no input, no wall-clock, no unseeded randomness (`AgDR-001`). `sim/` must never import from `game/`.
- **No sequential RNG anywhere.** Every per-household value comes from a named hash channel, so adding a household or a channel cannot reshuffle existing ones (FR-5). This is the promise task 1 exists to keep and task 6 exists to test.
- **Flat arrays indexed by grid position, never dictionaries keyed by coordinate** (`AgDR-006`).
- **Everything per-turn is called from `WorldMap.advance_turn()`** (`AgDR-007`), in one ordered pass.
- **The world never asks an agent what it is** (`AgDR-013`). A person knowing its practice is fine; `WorldMap` branching on person-ness is not. Adding a fourth practice must add no branch to `Agent` or `WorldMap` (FR-2).
- **Nothing removes a person, a household, or anything built** (FR-9, tone rules 1 and 2). A practice that stops paying loses adopters; it never kills anyone.
- **No absorbing states** (FR-8b). Every new vitality row obeys the same floor and the same unconditional recovery.
- **`WorldGen.generate()` already populates herds and a city.** Never call a populate function on an already-populated world — that is how Probe B produced 14 duplicate ids and understated convergence.
- **Every commit leaves `./test.sh` exiting 0.** Run one file with `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=<file>.gd -gexit`.

## File Structure

| File | Responsibility |
|---|---|
| `sim/hash01.gd` (new, `Hash01`) | Deterministic hash to [0, 1) and the named channel constants. No world dependency. |
| `sim/practice.gd` (new, `Practice`) | The `Kind` enum, the map from practice to `Land.Use`, and the three policies as pure functions. No state. |
| `sim/household.gd` (new, `Household`) | Practice, members, last interval's surplus, phase offset and threshold, and the reconsideration rule. |
| `sim/person.gd` (new, `Person`, extends `Agent`) | Stands somewhere, reports its appetite, consults its household's practice each turn. |
| `sim/land.gd` (modify) | `Use` gains `FOLLOW`, `TEND`, `RANGE`; `USE_COUNT` follows. |
| `sim/agent.gd` (modify) | `harvestable()` — a second reported quantity, zero by default. |
| `sim/herd.gd` (modify) | `harvestable()` returns the herd's population. |
| `sim/node.gd` (modify) | The gathering camp scores sites by harvestable mass rather than by total appetite. |
| `sim/world_map.gd` (modify) | A `households` array beside `nodes`; the harvestable census; `standing_of()`; the reconsideration pass in `advance_turn()`. |
| `sim/world_gen.gd` (modify) | Places the initial households (FR-10). |
| `tools/world_fingerprint.gd` (modify) | Folds household practice, member count and surplus into the digest. |
| `tools/practice_check.gd` (new) | The population claims over the standard seeds — dominance, diffusion, decorrelation — too slow for GUT, same reason the periodicity check lives here. |
| `test.sh` (modify) | Runs the new gate. |
| `test/test_hash01.gd` (new) | Channel independence and stability. |
| `test/test_practice.gd` (new) | Each policy's characteristic behaviour, and the per-use wear. |
| `test/test_households.gd` (new) | Surplus, reconsideration, staggering, adoption, diffusion, restoring force, no erasure. |

---

### Task 1: `Hash01` — named channels, no sequential draws

**Files:** create `sim/hash01.gd`, `test/test_hash01.gd`

The formula is the one already proven in `game/diorama/hex_kit.gd`. **Duplicate it rather than import it:** `sim/` may not depend on `game/` (`AgDR-001`), and the art thread owns those files. Say so in the docstring, and note that consolidating the two — by having the diorama call the sim's — is a follow-up for whoever next touches the diorama, not this plan.

**Produces:** `Hash01.h01(seed, a, b := 0, c := 0) -> float`, plus channel constants (`CHANNEL_PHASE`, `CHANNEL_THRESHOLD`, `CHANNEL_PLACEMENT`, `CHANNEL_STARTING_PRACTICE`) so a channel is named once rather than spelled as a magic integer at each call.

- [ ] **Step 1: failing tests.** Same inputs give the same output; different channels with identical other arguments give different values; every value lies in [0, 1); a value for household 7 is unchanged by the existence of households 8–40 (the channel-stability promise, FR-5).
- [ ] **Step 2: implement.** Copy the formula exactly.
- [ ] **Step 3: verify.** `./test.sh` exits 0.

### Task 2: `Practice` — three policies and their uses

**Files:** create `sim/practice.gd`, `test/test_practice.gd`

**Produces:**
- `Practice.Kind` — `FOLLOW`, `TEND`, `RANGE`; `Practice.KIND_COUNT`
- `Practice.use_for(kind) -> int` — the `Land.Use` this practice wears
- `Practice.name_of(kind) -> String`
- `Practice.next_coord(kind, world, from, seed, id) -> Vector2i` — where a person following this practice goes next
- `Practice.intensity(kind, world, coord, mouths) -> float` — what a person takes there, as a fraction of the tile's yield for that use

The three policies, each best where the others are weak:

| Practice | Moves | Pays off when |
|---|---|---|
| `FOLLOW` | toward the most **harvestable mass** within sense range — see below; the forage-demand census is the wrong signal | herds are rich and moving |
| `TEND` | stays put unless its tile's `TEND` vitality falls below a stated fraction of `Land.MAX_VITALITY` | a place is stable and productive |
| `RANGE` | toward the best tile within a wider sense range that no one of its own household is standing on | the world is varied and things are far apart |

**Follow needs a signal people do not contribute to.** `WorldMap._forage_demand`
sums *every* agent's `forage_demand()`, and task 4 makes every person report one.
Pointed at that census, Follow walks toward whichever crowd is biggest — usually
other people, including other practices — and its defining behaviour is gone.
Found by codex review of this plan.

The fix stays inside `AgDR-013`, because it is another *quantity* rather than a
question about type: agents gain a second reported number — what can be taken
from them — which a herd answers with its population and everything else answers
with zero, and the world keeps a second per-tile census of it. Follow reads that.

**This is latent in merged code, not only here.** `CityNode`'s gathering camp
scores sites by `forage_demand_within()`, so the moment people exist, camps light
up for human crowds as readily as for animals. Ticket B carries the fix for both;
it is a real change to #49's behaviour and belongs in that ticket's PR body.

**Tend must not need a memory it has no place to keep.** An earlier draft had it
stay until its tile fell below "its own best remembered value", which is history
that neither the stateless policy nor the listed household fields hold. Also
found by codex review. The threshold is derivable instead: a fraction of
`Land.MAX_VITALITY`, the ceiling every tile recovers toward.

**Design decision for Gate A, state it in the ticket:** `TEND` gets its own `Land.Use` rather than sharing `CULTIVATE` with farms. Separate is the conservative reading of FR-8 ("a tile carries a vitality per practice") and keeps the band's story independent of the city's, at the cost of one more array and the question of what happens when a farm and a Tending household work the same ground. Sharing would make the two layers interact immediately, which is either the interesting thing or a premature coupling. **Recommendation: separate now**, with the shared-row experiment as its own ticket once both layers exist.

- [ ] **Step 1: failing tests.** On a rigged world: a Follow person walks toward a herd and a Tend person does not; a Tend person leaves only when its tile is worn past the threshold; two Range people of one household do not stack on the same tile; `use_for` is total over `Kind` and every returned use is a valid `Land.Use`.
- [ ] **Step 2: implement.** Pure functions; no member state; no reference to `Person` or `Household`.
- [ ] **Step 3: verify.**

### Task 3: `Land.Use` gains the practice rows

**Files:** modify `sim/land.gd`; extend `test/test_vitality.gd`

- [ ] **Step 1: failing test.** Wearing `TEND` on a tile leaves `GRAZE`, `CULTIVATE`, `FOLLOW` and `RANGE` untouched on every tile — assert the whole row, not one tile, the way the existing per-use test does.
- [ ] **Step 2: implement.** Add the three enum members; `USE_COUNT` follows from the enum rather than being written twice.
- [ ] **Step 3: verify the budget.** Recovery runs `USE_COUNT` rows per turn. The 500-turn budget test measured 1150 ms of 2000 at two rows; five rows must stay inside it. If it does not, the fix is the existing `recovered_row()` batching applied harder, not a raised budget.

**Part b — harvestable mass, the signal Follow actually needs.**

`Agent.harvestable()` returns zero; `Herd` returns its population; `WorldMap`
keeps a per-tile census of it beside the forage one, maintained by the same
mutators. The world still never asks what an agent *is* — this is a second
quantity, exactly as `forage_demand()` is.

Then point `CityNode`'s gathering camp at it. **Today this changes no number**:
only herds report appetite, so the two censuses are equal everywhere, and the
existing camp tests must stay green unchanged. It matters the moment people
exist, which is the next ticket — at which point the camp would otherwise light
up for human crowds.

- [ ] **Step 1: failing test.** An agent reporting appetite but no harvestable
      mass does not light a camp, and does not attract anything that reads the
      harvestable census. Build it with a bare `Agent` subclass in the test rather
      than waiting for `Person`.
- [ ] **Step 2: implement**, keeping every existing camp measurement identical.
- [ ] **Step 3: verify** the gathering suite's printed numbers are unchanged.

### Task 4: `Household` and `Person` — the data, and how they get into the world

**Files:** create `sim/household.gd`, `sim/person.gd`; modify `sim/world_map.gd`, `sim/world_gen.gd`; create `test/test_households.gd`

Ratify `AgDR-020` before starting this task: it is the record that says a lineage *is* its practice and that standing is derived, and tasks 4–6 encode it.

**Produces:**
- `Household` — `id`, `practice`, `members: Array[Person]`, `last_result` (see task 6), `gathered_this_interval`, `phase_offset()`, `threshold()`, `size()` (its member count)
- `Person extends Agent` — `household_id`, `forage_demand()` returning a stated per-person appetite, and `harvestable()` returning zero
- `Herd` — `harvestable()` returning its population, so Follow and the gathering camp have a signal people do not contribute to
- `WorldMap.households: Array[Household]`, `add_household()`, a per-tile harvestable census beside the forage one, and the same frozen-census discipline for anything a person divides
- `WorldMap.standing_of(practice) -> int` — **how many households follow it.** That is the lineage's size and its standing, per `AgDR-020`, and it is a property of the world rather than of any one household. A household's own `size()` is its member count and is *not* standing: once households differ in size the two numbers diverge, and an early draft of this plan conflated them. Found by codex review of this plan.
- `WorldGen` places 5–12 households in the shape of `Herd.populate`: bounded attempts, grid order, starting practices distributed across all three so the first reconsideration has something to compare against (FR-10)

**Why `households` is a registry on the world rather than something derived from `agents`:** a household needs to compare itself with nearby households, which means finding them. Deriving that by scanning `agents` and asking each one what it is would be exactly the branch `AgDR-013` forbids. A parallel array, like `nodes`, keeps the world's agent loop kind-blind: `WorldMap` steps agents without knowing any of them is a person, and asks households to reconsider without knowing any of them has members.

- [ ] **Step 1: failing tests.** A household is constructible headless with no world; `standing()` equals its member count; two worlds from one seed place identical households in identical positions with identical practices; all three practices are present on every standard seed; people report a non-zero appetite into the census.
- [ ] **Step 2: implement.**
- [ ] **Step 3: verify.**

### Task 5: People act, and the land remembers which way

**Files:** modify `sim/person.gd`, `sim/world_map.gd`; extend `test/test_practice.gd`

Each turn a person consults its household's practice for where to go, takes its share of the tile's yield for that practice's use, adds what it took to its household's running total for the interval, and wears that use — and *only* that use — by what it actually took.

**The trap plan 1 fell into four times, stated once here:** the share must be computed from forage and census **frozen at the start of the turn** (`grazing_forage_at_turn_start()` is the existing pattern, and it needs a per-use sibling). If a person divides live values, two identical people on one tile get different outcomes depending on array order. Write the order-independence test *first*: two identical households on one tile end the turn identical.

- [ ] **Step 1: failing tests.** A Tending person wears `TEND` and leaves `GRAZE` untouched; a person on worn ground takes less than one on fresh ground; two identical co-located households end a turn identical; a tile with more people on it yields each of them less (FR-8c); **a Follow person walks toward a herd rather than toward a larger crowd of people** — the finding that made `harvestable()` necessary, asserted with people on one side and animals on the other.
- [ ] **Step 2: implement.**
- [ ] **Step 3: verify.**

### Task 6: Reconsideration, staggered — and adoption from neighbours

**Files:** modify `sim/household.gd`, `sim/world_map.gd`; extend `test/test_households.gd`

**Produces:**
- `Household.RECONSIDER_INTERVAL_TURNS` — one named constant, default one year (`Seasons.TURNS_PER_YEAR`). Changing it changes the pacing of every household and nothing else (FR-4). The owner asked for this to be tunable so different pacing models can be tried; make that easy and say so in the docstring.
- A household reconsiders on the turn where `(turn + phase_offset) % RECONSIDER_INTERVAL_TURNS == 0`, so the band never flips on one synchronised decision day.
- Surplus for the interval: what its people gathered minus what they needed. **Perishable** — recorded for comparison and then reset, never banked, pooled or transferred (FR-7).
- **A result carries the practice that produced it.** `last_result` is the pair (practice, surplus), not a bare number. Because reconsideration is staggered, a household can earn well under Tend, switch to Follow at its own phase, and be read by a neighbour reconsidering later — who would otherwise take up *Follow* on Tend's evidence, spreading practices on results they never produced. Found by codex review of this plan. A household that has not yet completed an interval under its current practice offers the result it actually earned, under the practice that earned it.
- Adoption: `if theirs > mine * (1 + threshold)`, take up **the practice that produced `theirs`**, where `theirs` is the best result among households this one was **near during the interval** — sharing a tile or a neighbouring one (FR-6). Accumulate that neighbour set as the interval runs; a comparison made only at the final turn would miss everyone who has moved on.

- [ ] **Step 1: failing tests.** Households do not all reconsider on the same turn; a household with a much better neighbour adopts and one whose threshold exceeds the margin does not; adoption never reads a household that was never near (build a world with a rich household out of range and assert no adoption); surplus does not carry across intervals; changing `RECONSIDER_INTERVAL_TURNS` changes when decisions happen and nothing else; **a household that earned its result under one practice and has since switched is copied for the practice that earned it** — build the staggered case directly, since it is the one that produced this requirement.
- [ ] **Step 2: implement.**
- [ ] **Step 3: verify.**

### Task 7: The claims — dominance, diffusion, restoring force, decorrelation

**Files:** create `tools/practice_check.gd`; modify `test.sh`; extend `test/test_households.gd`

The population claims go in a `tools/` gate for the reason the periodicity check does: ten seeds of long runs are a minute of wall-clock that no one should pay on every suite run. The per-mechanism claims stay in GUT.

In the gate, over the standard seed set:
- **No dominance (FR-3).** No practice above **60%** of households in steady state, and none at zero. *If this fails, report it — do not widen the bound.* It is the spec's own stated refutation.
- **Diffusion shape.** A practice introduced to one household spreads to some but not all, over several intervals rather than one, with holdouts persisting past the median adopter.
- **Decorrelation.** Over 500 years: total population never approaches the floor; individual regions do reach lows; regional series are not in phase; every region that empties refills.
- **Non-convergence.** The periodicity check from plan 1, re-run with practices active, still finds no repeating cycle within 200 years. This is the criterion the whole design exists to satisfy.

In GUT:
- **Restoring force.** Force every household onto one practice, run forward, assert adoption diversifies again (tone rule 3).
- **No erasure.** After any run, every household and every placed thing still exists (FR-9).

- [ ] **Step 1: write the gate and see it report.** Report the numbers whether they pass or fail — they are the evidence for whether this design works at all.
- [ ] **Step 2: wire into `test.sh`** with a message pointing at the spec's refutation clause.
- [ ] **Step 3: verify.**

### Task 8: Determinism across processes

**Files:** modify `tools/world_fingerprint.gd`; extend `test/test_households.gd`

- [ ] **Step 1: failing test.** Same seed, 2,000 turns, two worlds equal — including every household's practice, member count and surplus (FR-11).
- [ ] **Step 2: fold households into the digest**, so a divergence in the social layer cannot hide behind identical herds.
- [ ] **Step 3: verify** the cross-process gate reproduces every seed.

## Ticket split

Three tickets, mirroring the split that worked for land vitality (#38 / #41 / #42): a foundation with no behaviour change, the engine, then the claims.

| Ticket | Tasks | Why it stands alone |
|---|---|---|
| **A — #60** | 1–3 | Pure additions: a hash, a policy table, three unused vitality rows, and the harvestable census the camp and Follow both need. Nothing in the world behaves differently — the camp's numbers are identical until people exist — and the budget question is answered here rather than inside a larger change. |
| **B — #61** | 4–6 | The engine: households exist, people act, practices spread. Depends on A and on `AgDR-020` being ratified. |
| **C — #62** | 7–8 | The claims and the determinism fold. Depends on B. This is the ticket that can legitimately fail and produce a finding rather than a fix. |

## Risks carried from the spec, and what is now known

- **Three clocks must stay in proportion** — season length (6 turns), vitality half-life (12 turns) and `RECONSIDER_INTERVAL_TURNS` (default 24). Name them relative to each other; do not tune independently.
- **"Near" is an invisible difficulty setting.** How near, and for how much of an interval, decides whether ideas cross the map or stay in one valley. Surface it as a named constant with its reasoning, and report what it does.
- **Drift may be emotionally flat.** If a household changing practice cannot be felt, the readout (#46, merged) has to carry it — and `AgDR-020` names this as its own refutation.
- **The probes' scoring functions were invented.** Probe A says the world has variance structure enough for three practices; it does not say these three, implemented properly, land the same way. Task 7 is where that gets tested for real.
- **Migration is no longer a risk.** Plan 1 measured herds travelling 10–32 tiles with all 14 leaving a camp's reach, against 0–8 before.
