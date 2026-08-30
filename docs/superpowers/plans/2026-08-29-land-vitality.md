# Land Vitality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tile a vitality per use that is drawn down by being worked that way and recovers on its own, so that land rotates, use is self-limiting, and the world stops converging to a fixed annual cycle.

**Architecture:** A new `Land` class holds the use enumeration, the constants, and the pure vitality arithmetic. `WorldMap` holds one flat `PackedFloat32Array` per use, the same shape as the existing terrain and forage arrays. Consumers ask for `forage_for_use(coord, use)` — the terrain-and-season curve scaled by that use's vitality — and report what they took back through `draw_vitality()`. A single recovery pass at the end of every turn pulls every value back toward its ceiling.

**Tech Stack:** Godot 4 / GDScript, GUT for tests, `./test.sh` for the suite and the cross-process determinism gate.

**Spec:** `docs/superpowers/specs/2026-08-29-early-game-practices-design.md`
**Record:** `.decisions/AgDR-014-land-remembers-use.md` (accepted, ratified 2026-08-29)
**Ticket:** #38

## Scope

This is **plan 1 of 2** for the spec's slice 1. It implements land vitality only — ticket #38 — which stands alone: it has its own ratified record, it delivers the spec's primary acceptance test (non-convergence), and #38 states that until practices exist its "uses" are the existing consumers, grazing and cultivation. The practice and adoption engine is plan 2 and is not started here.

## Global Constraints

- **`sim/` stays headless.** No `Node` dependency, no rendering, no input, no wall-clock time, no unseeded randomness (`AgDR-001`). Everything here must be constructible and runnable without a scene tree.
- **Flat arrays indexed by grid position, never dictionaries keyed by coordinate** (`AgDR-006`). Iteration is row-major over offset space and must never depend on a hash.
- **The turn is a single ordered pass.** Everything per-turn is called from `WorldMap.advance_turn()`, not from a parallel scheduler (`AgDR-007`).
- **Agents report quantities; nothing asks them what they are** (`AgDR-013`). `WorldMap` must not branch on agent kind. A herd knowing that it grazes is fine; `WorldMap` knowing it is a herd is not.
- **`AgDR-009`'s surviving half:** forage is still *derived* from terrain and season, never integrated. `Seasons.FORAGE_BY_TERRAIN` remains the ceiling; vitality scales it. There must be no unbounded accumulator anywhere.
- **No absorbing states.** Every vitality has a floor above zero and recovers from it unconditionally. No sequence of ordinary play may produce an irreversible loss of any tile's capacity.
- **`WorldGen.generate()` already populates herds and a city.** It calls
  `Herd.populate(map)` and `CityGen.populate(map)` at `sim/world_gen.gd:95-101`.
  **Never call `Herd.populate()` on a generated world** — doing so gives 28 herds
  with 14 duplicate ids, and duplicate ids collide in every fingerprint in this
  repo. The first run of Probe B made exactly this mistake and reported a milder
  convergence than the truth; it was caught in review, not by any test.
- **Every commit must leave `./test.sh` exiting 0.**
- Test files live at `test/test_*.gd` and extend `GutTest`. That glob is also the suite's own count check.
- Run the suite with `./test.sh`. Run one file with `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/<file>.gd -gexit`.

## File Structure

| File | Responsibility |
|---|---|
| `sim/land.gd` (new, `Land`) | The `Use` enumeration, the vitality constants and their derivation, and the pure arithmetic of depletion and recovery. No world dependency at all. |
| `sim/world_map.gd` (modify) | Holds one vitality array per use; `vitality_at`, `vitality_by_index`, `forage_for_use`, `draw_vitality`, and the recovery pass in `advance_turn()`. |
| `sim/herd.gd` (modify) | Grazing reads and draws `Use.GRAZE`. |
| `sim/node.gd` (modify) | A farm reads and draws `Use.CULTIVATE`. |
| `tools/world_fingerprint.gd` (modify) | Folds vitality into the cross-process digest. |
| `tools/periodicity_check.gd` (new) | Runs worlds forward 200 years and reports whether they settle into a repeating cycle. Not a GUT test — too slow for the suite, same reason the fingerprint tools live here. |
| `test.sh` (modify) | Runs the periodicity check as a gate. |
| `test/test_land.gd` (new) | The pure arithmetic: floors, ceilings, monotonicity, half-life. |
| `test/test_vitality.gd` (new) | World-level behaviour: recovery, depletion, per-use independence, FR-8a, FR-8b. |

---

### Task 1: `Land` — the use enumeration and the pure arithmetic

**Files:**
- Create: `sim/land.gd`
- Test: `test/test_land.gd`

**Interfaces:**
- Consumes: `Seasons.TURNS_PER_SEASON` (currently 6)
- Produces:
  - `Land.Use` — enum with `GRAZE` and `CULTIVATE`
  - `Land.USE_COUNT: int`
  - `Land.MIN_VITALITY: float`, `Land.MAX_VITALITY: float`
  - `Land.RECOVERY_HALF_LIFE_TURNS: int`
  - `Land.DEPLETION_PER_UNIT: float`
  - `Land.recovery_rate() -> float`
  - `Land.recovered(vitality: float) -> float`
  - `Land.depleted(vitality: float, intensity: float) -> float`

- [ ] **Step 1: Write the failing test**

Create `test/test_land.gd`:

```gdscript
extends GutTest
## The arithmetic of land wearing out and coming back, with no world attached.
##
## Kept pure and separate because the interesting properties here — that nothing
## reaches zero, that recovery never overshoots, that continuous maximum use
## settles at the floor rather than below it — are claims about the numbers, and
## they are far easier to trust asserted directly than inferred from a world.


func test_recovery_moves_toward_the_ceiling_and_stops_there() -> void:
	assert_almost_eq(Land.recovered(Land.MAX_VITALITY), Land.MAX_VITALITY, 0.0001,
			"full land stays full rather than overshooting")
	var half := Land.recovered(0.5)
	assert_gt(half, 0.5, "worn land recovers")
	assert_lt(half, Land.MAX_VITALITY, "but not all at once")


func test_recovery_reaches_half_way_back_in_one_half_life() -> void:
	# The constant is stated as a half-life so it can be reasoned about in
	# seasons; this asserts the rate actually derived from it does that.
	var v := 0.0
	for i in range(Land.RECOVERY_HALF_LIFE_TURNS):
		v = Land.recovered(v)
	assert_almost_eq(v, 0.5, 0.02, "half the distance closed in one half-life")


func test_depletion_never_reaches_zero() -> void:
	var v := Land.MAX_VITALITY
	for i in range(500):
		v = Land.depleted(v, 1.0)
	assert_eq(v, Land.MIN_VITALITY, "five hundred turns of maximum use stops at the floor")
	assert_gt(Land.MIN_VITALITY, 0.0, "and the floor is above zero")


func test_no_use_is_no_depletion() -> void:
	assert_eq(Land.depleted(0.7, 0.0), 0.7, "land nobody worked is land unchanged")


func test_continuous_maximum_use_settles_one_recovery_step_above_the_floor() -> void:
	# The turn order is deplete-then-recover, so ground worked flat out is
	# clamped to the floor and then lifted one step before the turn ends. The
	# attractor is therefore MIN_VITALITY + one recovery step, not MIN_VITALITY.
	#
	# Asserted tightly and against a derived value rather than a literal: a loose
	# tolerance here is what let an earlier, wrong claim about this equilibrium
	# pass by about 0.007.
	var v := Land.MAX_VITALITY
	for i in range(400):
		v = Land.recovered(Land.depleted(v, 1.0))
	assert_almost_eq(v, Land.continuous_use_equilibrium(), 0.001,
			"continuous full use settles one recovery step above the floor")
	assert_gt(v, Land.MIN_VITALITY, "and therefore strictly above it")


func test_intensity_scales_how_fast_land_wears() -> void:
	var light := Land.depleted(Land.MAX_VITALITY, 0.25)
	var heavy := Land.depleted(Land.MAX_VITALITY, 1.0)
	assert_gt(light, heavy, "lighter use wears the ground more slowly")
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_land.gd -gexit`

Expected: the script fails to parse — `Identifier "Land" not declared in the current scope`. That is the correct red for a class that does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `sim/land.gd`:

```gdscript
class_name Land
extends RefCounted

## What land remembers about being worked, and how it comes back.
##
## `AgDR-014` is the record. The decision in one line: a tile carries a vitality
## **per use**, not one vitality overall, so ground worn out by cultivation is
## still good ground for grazing. One number per tile would have collapsed
## "rotate" and "rest" into the same action.
##
## Nothing here touches a world. The arithmetic is separated from the state so
## that the properties that matter — nothing reaches zero, recovery never
## overshoots, continuous maximum use settles at the floor rather than below it
## — are asserted on the numbers directly.

## The ways land can be worked. Two for now, which are the consumers that exist:
## herds grazing and farms cultivating. Practices will extend this, and the
## enum is the only place that has to change when they do.
enum Use {
	GRAZE,
	CULTIVATE,
}

const USE_COUNT := 2

## Vitality is a fraction of what the terrain-and-season curve would otherwise
## give, so full land is 1.0 and `Seasons.FORAGE_BY_TERRAIN` stays the ceiling —
## which is the half of `AgDR-009` that survives.
const MAX_VITALITY := 1.0

## The floor, and it is above zero on purpose. `AgDR-014` forbids absorbing
## states: no sequence of ordinary play may cost a tile its capacity
## permanently. Manor Lords is the counter-example the record cites — its fully
## depleted deer stop regrowing and its logged-out berry bushes never return,
## and both would break tone rules 1 and 2 here.
const MIN_VITALITY := 0.15

## How long worn land takes to close half the distance back to full.
##
## Stated as a half-life in turns and derived from the season length rather than
## written as a bare rate, because the thing that actually matters is the
## *ratio* between this and the calendar. Half a year means a tile worked hard
## through one summer is most of the way back by the next — visible inside a
## session, slow enough to be a decision rather than a flicker.
const RECOVERY_HALF_LIFE_TURNS := Seasons.TURNS_PER_SEASON * 2

## How much one turn of maximum-intensity use takes off a tile.
##
## Sets how fast worn ground approaches its limit, and where land settles under
## *partial* use — at a steady intensity `I` that does not reach the floor,
## vitality converges on `1 - DEPLETION_PER_UNIT * I * (1 - r) / r`.
##
## It does **not** set where continuous maximum use settles. That is fixed by the
## floor and the turn order instead — see `continuous_use_equilibrium()`. An
## earlier version of this comment claimed the constant was calibrated to put
## full-use equilibrium at `MIN_VITALITY`; that was wrong, and the tripwire test
## written against it passed with about 0.007 of slack. Caught in review on
## PR #40.
const DEPLETION_PER_UNIT := 0.048


## The per-turn fraction of the remaining gap that recovery closes, derived from
## the half-life. Not a `const` because `pow()` is not a constant expression.
static func recovery_rate() -> float:
	return 1.0 - pow(0.5, 1.0 / float(RECOVERY_HALF_LIFE_TURNS))


## Where a tile settles under unbroken maximum use.
##
## **Not `MIN_VITALITY`.** Depletion clamps at the floor and then the same turn's
## recovery lifts it one step, so the attractor sits exactly one recovery step
## above the floor — and it does so for *any* depletion large enough to reach the
## floor at all, which is why retuning `DEPLETION_PER_UNIT` does not move it.
##
## Derived rather than written down so the test can assert it tightly: changing
## either the floor or the half-life moves this value and `test_land.gd` says so.
static func continuous_use_equilibrium() -> float:
	return MIN_VITALITY + recovery_rate() * (MAX_VITALITY - MIN_VITALITY)


## One turn of nobody working this tile, for this use.
##
## Exponential approach to the ceiling, so it cannot overshoot and there is no
## accumulator to drift — the `AgDR-009` no-drift property holds by construction
## here exactly as it did for forage.
static func recovered(vitality: float) -> float:
	return vitality + recovery_rate() * (MAX_VITALITY - vitality)


## One turn of this tile being worked, at `intensity` in 0..1.
static func depleted(vitality: float, intensity: float) -> float:
	return maxf(MIN_VITALITY, vitality - DEPLETION_PER_UNIT * clampf(intensity, 0.0, 1.0))
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_land.gd -gexit`

Expected: 6 tests passing.

- [ ] **Step 5: Run the full suite**

Run: `./test.sh`

Expected: exit 0. Nothing consumes `Land` yet, so nothing else can have changed.

- [ ] **Step 6: Commit**

```bash
git add sim/land.gd test/test_land.gd
git commit -m "Land: what a tile remembers about being worked, and how it comes back"
```

---

### Task 2: Vitality state on `WorldMap`

**Files:**
- Modify: `sim/world_map.gd`
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: `Land.Use`, `Land.USE_COUNT`, `Land.MAX_VITALITY`; `HexGrid.index_of`, `HexGrid.tile_count`
- Produces:
  - `WorldMap.vitality_at(coord: Vector2i, use: int) -> float`
  - `WorldMap.vitality_by_index(i: int, use: int) -> float`
  - `WorldMap.vitality_data(use: int) -> PackedFloat32Array`
  - `WorldMap.forage_for_use(coord: Vector2i, use: int) -> float`
  - `WorldMap.forage_for_use_by_index(i: int, use: int) -> float`

- [ ] **Step 1: Write the failing test**

Create `test/test_vitality.gd`:

```gdscript
extends GutTest
## Land vitality as the world holds it: how it is stored, how it is read, and
## what it does to what a tile is worth.

const SEED := 20260815


func _world() -> WorldMap:
	return WorldGen.generate(SEED)


func test_a_fresh_world_starts_at_full_vitality_everywhere() -> void:
	var world := _world()
	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_eq(value, Land.MAX_VITALITY, "an untouched world is unworn")


func test_vitality_is_stored_per_use() -> void:
	# The whole point of AgDR-014: ground worn by one use is untouched for the
	# other. If these two arrays are ever the same array, this fails.
	var world := _world()
	var graze := world.vitality_data(Land.Use.GRAZE)
	var cultivate := world.vitality_data(Land.Use.CULTIVATE)
	assert_eq(graze.size(), cultivate.size(), "one value per tile per use")
	assert_eq(graze.size(), world.grid.tile_count(), "and one per tile")


func test_forage_for_use_is_the_curve_scaled_by_vitality() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var base := world.forage_at(land)

	assert_almost_eq(world.forage_for_use(land, Land.Use.GRAZE), base, 0.0001,
			"at full vitality a use gets the whole curve")


func test_the_terrain_curve_is_still_the_ceiling() -> void:
	# AgDR-009's surviving half. Vitality scales the curve down and can never
	# scale it up, so no tile can ever be worth more than its terrain and season
	# say it is.
	var world := _world()
	for coord in world.grid.all_coords():
		for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
			assert_lte(world.forage_for_use(coord, use), world.forage_at(coord) + 0.0001,
					"no use exceeds the terrain curve at %s" % coord)


func _first_land_coord(world: WorldMap) -> Vector2i:
	for coord in world.grid.all_coords():
		if world.terrain_at(coord) != WorldGen.Terrain.WATER:
			return coord
	fail_test("the generated world has no land at all")
	return Vector2i.ZERO
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: parse failure on `vitality_data` — the method does not exist.

- [ ] **Step 3: Add the state and the readers**

In `sim/world_map.gd`, next to the existing `_forage` declaration (around line 45), add:

```gdscript
## One vitality value per tile per use, in the same grid order as `_terrain` and
## `_forage` (`AgDR-006`: flat arrays indexed by position, never a dictionary
## keyed by coordinate).
##
## An `Array` of `PackedFloat32Array`, indexed by `Land.Use`. Kept as separate
## arrays per use rather than one interleaved array so that a whole use can be
## read, hashed or compared in one call — and so that adding a use is appending
## an array rather than restriding every read.
var _vitality: Array = []
```

In `_init`, after the existing arrays are sized, add:

```gdscript
	_vitality.resize(Land.USE_COUNT)
	for use in range(Land.USE_COUNT):
		var row := PackedFloat32Array()
		row.resize(p_grid.tile_count())
		row.fill(Land.MAX_VITALITY)
		_vitality[use] = row
```

Then add the readers, next to the existing forage readers:

```gdscript
## How worn this tile is for this use, in `Land.MIN_VITALITY`..`MAX_VITALITY`.
func vitality_at(coord: Vector2i, use: int) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read vitality off the map")
	return vitality_by_index(i, use)


func vitality_by_index(i: int, use: int) -> float:
	var row: PackedFloat32Array = _vitality[use]
	return row[i]


## The whole vitality row for one use, in grid order.
func vitality_data(use: int) -> PackedFloat32Array:
	var row: PackedFloat32Array = _vitality[use]
	return row.duplicate()


## What this tile is actually worth to this use right now: the terrain-and-season
## curve scaled by how worn the ground is for that use.
##
## The curve remains the ceiling — vitality is a fraction and never exceeds 1.0 —
## which is the half of `AgDR-009` that survives `AgDR-014`.
func forage_for_use(coord: Vector2i, use: int) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read forage off the map")
	return forage_for_use_by_index(i, use)


## The same value by index, for callers scanning many tiles per turn.
##
## `Herd._best_ground()` scores every tile in its sense range every time it
## re-plans and reads by index for exactly that reason. It needs this rather than
## raw `forage_by_index()`, or destinations stay blind to wear while the tile
## underfoot is not — and a herd that cannot see worn ground keeps walking onto
## it, which would leave the rotation this whole record is about with no effect
## on where anything goes.
func forage_for_use_by_index(i: int, use: int) -> float:
	return _forage[i] * vitality_by_index(i, use)
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: 4 tests passing.

- [ ] **Step 5: Run the full suite**

Run: `./test.sh`

Expected: exit 0. Nothing reads `forage_for_use` yet, so no behaviour has changed.

- [ ] **Step 6: Commit**

```bash
git add sim/world_map.gd test/test_vitality.gd
git commit -m "WorldMap: one vitality array per use, alongside terrain and forage"
```

---

### Task 3: Recovery in the turn loop, and no absorbing states

**Files:**
- Modify: `sim/world_map.gd`
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: `Land.recovered`
- Produces: `WorldMap._recover_vitality()` — called from `advance_turn()`, private

- [ ] **Step 1: Write the failing test**

Append to `test/test_vitality.gd`:

```gdscript
func test_worn_land_recovers_without_anyone_doing_anything() -> void:
	# AgDR-014: recovery is unconditional. No policy, no structure, no player
	# action. It is the world's behaviour, not a reward.
	#
	# On a bare world for the same reason as the absorbing-states test below: a
	# generated one has herds walking over the tile being watched.
	var world := _bare_world()
	var land := Vector2i.ZERO
	world.set_vitality(land, Land.Use.GRAZE, Land.MIN_VITALITY)

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_gt(world.vitality_at(land, Land.Use.GRAZE), Land.MIN_VITALITY + 0.2,
			"a year of being left alone brings the ground back")


func test_recovery_stops_at_full_and_does_not_overshoot() -> void:
	var world := _bare_world()
	for i in range(200):
		world.advance_turn()
	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_lte(value, Land.MAX_VITALITY + 0.0001, "nothing rises above full")


## A world with terrain and nothing living in it.
##
## `WorldGen.generate()` places fourteen herds, a farm, a granary and citizens,
## so a "deplete, stop, run forward" test built on it is not resting at all —
## the farm holds its own tile near the continuous-use equilibrium and never
## reaches the ceiling. Any test whose claim is about land left alone needs a
## world where nothing is working it.
func _bare_world(terrain := WorldGen.Terrain.GRASS) -> WorldMap:
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	for coord in grid.all_coords():
		world.set_terrain(coord, terrain)
	return world


func test_no_absorbing_states_a_flattened_region_comes_all_the_way_back() -> void:
	# FR-8b. Deplete as hard as the rules allow, stop, and assert full recovery.
	# This is the assertion that separates this design from Manor Lords' deer.
	var world := _bare_world()
	assert_eq(world.agents.size(), 0, "nothing is working this land")
	assert_eq(world.nodes.size(), 0, "nothing is farming it either")
	for coord in world.grid.all_coords():
		world.set_vitality(coord, Land.Use.GRAZE, Land.MIN_VITALITY)
		world.set_vitality(coord, Land.Use.CULTIVATE, Land.MIN_VITALITY)

	for i in range(Seasons.TURNS_PER_YEAR * 10):
		world.advance_turn()

	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		for value in world.vitality_data(use):
			assert_gt(value, 0.9, "ten years of rest restores every tile toward full")
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: parse failure on `set_vitality`.

- [ ] **Step 3: Add the setter and the recovery pass**

In `sim/world_map.gd` add the setter next to the readers:

```gdscript
## Set a tile's vitality for a use directly.
##
## Exists for generation and for tests that need to start from a worn world.
## Ordinary wear goes through `draw_vitality()`; this is not the path play takes.
func set_vitality(coord: Vector2i, use: int, value: float) -> void:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot write vitality off the map")
	var row: PackedFloat32Array = _vitality[use]
	row[i] = clampf(value, Land.MIN_VITALITY, Land.MAX_VITALITY)
	_vitality[use] = row
```

Add the recovery pass, next to `_recompute_forage`:

```gdscript
## Every tile, every use, one turn closer to full.
##
## Runs last in the turn so that what recovers is what is left after the turn's
## work has been taken — and runs over every tile unconditionally, because
## `AgDR-014` makes recovery the world's default behaviour rather than something
## anybody has to cause. Same flat-array pass as `_recompute_forage`, for the
## same reason: this runs `tile_count()` times per use per turn.
func _recover_vitality() -> void:
	for use in range(Land.USE_COUNT):
		var row: PackedFloat32Array = _vitality[use]
		for i in range(row.size()):
			row[i] = Land.recovered(row[i])
		_vitality[use] = row
```

Change `advance_turn()` to:

```gdscript
func advance_turn() -> int:
	turn += 1
	_recompute_forage()
	for node in nodes:
		node.produce(self)
	for agent in agents:
		agent.step(self)
	_recover_vitality()
	return turn
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: 7 tests passing.

- [ ] **Step 5: Run the full suite**

Run: `./test.sh`

Expected: exit 0. Vitality still starts full and nothing draws it down, so no existing behaviour has moved.

- [ ] **Step 6: Commit**

```bash
git add sim/world_map.gd test/test_vitality.gd
git commit -m "Vitality recovers every turn, unconditionally, and never past full"
```

---

### Task 4: Grazing wears the ground

**Files:**
- Modify: `sim/world_map.gd`, `sim/herd.gd`
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: `Land.depleted`, `Land.Use.GRAZE`, `WorldMap.forage_for_use`, `WorldMap.forage_for_use_by_index`
- Produces:
  - `WorldMap.draw_vitality(coord: Vector2i, use: int, intensity: float) -> void`
  - `WorldMap.forage_demand_at_turn_start(coord: Vector2i) -> float`

- [ ] **Step 1: Write the failing test**

Append to `test/test_vitality.gd`:

```gdscript
func test_a_grazing_herd_wears_the_ground_it_stands_on() -> void:
	var world := _world()
	var herds := world.herds()
	assert_gt(herds.size(), 0, "the world placed herds — otherwise this asserts nothing")
	var watched: Herd = herds[0]
	var where := watched.coord

	for i in range(Seasons.TURNS_PER_SEASON):
		world.advance_turn()

	assert_lt(world.vitality_at(where, Land.Use.GRAZE), Land.MAX_VITALITY,
			"a season of grazing shows on the tile")


func test_standing_on_barren_ground_costs_nothing() -> void:
	# The bug this guards against: wear computed from how hungry the herd was
	# rather than from what it ate would floor every tile in the world each
	# winter, when nothing grows and every ration is bad.
	#
	# Built on an empty grid rather than a generated world, with a herd that
	# cannot move or sense. A generated world already holds fourteen herds that
	# would wander across the watched tile during the eighteen turns this waits
	# for winter, and a mobile subject would wander off it — either way the
	# assertion would be measuring something other than what it claims. The
	# species is pinned immobile so the scenario is forced rather than hoped for.
	var grid := HexGrid.new(8, 8)
	var world := WorldMap.new(grid, 99)
	var land := Vector2i.ZERO
	for coord in grid.all_coords():
		world.set_terrain(coord, WorldGen.Terrain.MOUNTAIN)

	# name, consumption/head, growth, decline, move_range, sense_range, min, start
	var rooted := Species.new("rooted", 0.006, 0.070, 0.110, 0, 0, 2.0, 40.0)
	var herd := Herd.new(1, land, rooted, 40.0)
	world.add_agent(herd)

	# Winter on a mountain is the least forage the table offers.
	while world.season() != Seasons.Season.WINTER:
		world.advance_turn()
	assert_eq(herd.coord, land, "the subject stayed on the watched tile")
	var before := world.vitality_at(land, Land.Use.GRAZE)
	for i in range(Seasons.TURNS_PER_SEASON):
		world.advance_turn()

	assert_eq(herd.coord, land, "and stayed there for the measurement")
	assert_gt(world.vitality_at(land, Land.Use.GRAZE), before - 0.05,
			"a herd on ground that fed it nothing barely wore it")


func test_two_herds_sharing_a_tile_do_not_overcharge_it() -> void:
	# The share each herd draws is settled against the census as it stood before
	# anything moved. Without that, a herd stepped after one that has already
	# grazed and left divides by a smaller denominator and claims a share the
	# tile was charged for a moment earlier — so a shared tile wears faster than
	# a tile carrying the same total number of animals in one herd.
	var shared := _bare_world()
	var solo := _bare_world()
	var where := Vector2i.ZERO
	shared.add_agent(Herd.new(1, where, Species.grazer(), 20.0))
	shared.add_agent(Herd.new(2, where, Species.grazer(), 20.0))
	solo.add_agent(Herd.new(1, where, Species.grazer(), 40.0))

	for i in range(Seasons.TURNS_PER_SEASON):
		shared.advance_turn()
		solo.advance_turn()

	assert_almost_eq(
		shared.vitality_at(where, Land.Use.GRAZE),
		solo.vitality_at(where, Land.Use.GRAZE),
		0.02,
		"forty animals wear a tile the same whether they arrived as one herd or two"
	)


func test_grazing_does_not_wear_the_ground_for_cultivation() -> void:
	# The per-use split, which is the entire point of AgDR-014. Ground eaten
	# down by animals is still good ground to farm.
	var world := _world()
	var where: Vector2i = world.herds()[0].coord

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_lt(world.vitality_at(where, Land.Use.GRAZE), 0.95, "grazing wore the grazing")
	assert_almost_eq(world.vitality_at(where, Land.Use.CULTIVATE), Land.MAX_VITALITY, 0.0001,
			"and left cultivation untouched")


func test_a_herd_on_worn_ground_gets_less_from_it() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var full := world.forage_for_use(land, Land.Use.GRAZE)
	world.set_vitality(land, Land.Use.GRAZE, 0.5)
	assert_almost_eq(world.forage_for_use(land, Land.Use.GRAZE), full * 0.5, 0.0001,
			"half-worn ground is worth half as much to a grazer")
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: `test_a_grazing_herd_wears_the_ground_it_stands_on` fails — vitality is still full because nothing draws it.

- [ ] **Step 3: Add `draw_vitality` and point grazing at it**

In `sim/world_map.gd`, first add the demand snapshot. `Herd.step()` grazes and
*then* migrates, so by the time a second herd on the same tile computes its
share, the first one may already have left and been removed from the live
census — letting the latecomer claim a share of forage the tile has already been
charged for. Sharing has to be settled against the census as it stood before
anything moved:

```gdscript
## The per-tile forage census as it stood at the start of this turn, before any
## agent grazed or moved.
##
## `Herd.step()` grazes and then migrates, so the live census changes underneath
## the agents still to be stepped. A herd dividing a tile's forage by the live
## demand would see earlier herds vanish and claim their share as well, and the
## tile would be charged for more than it grew. Sharing is settled against the
## world as it was when the turn began.
##
## A copy per turn rather than a second running total: one `duplicate()` of an
## array the map already keeps, against a bookkeeping path that would have to
## stay correct through every future mutator.
var _forage_demand_at_turn_start: PackedFloat32Array = PackedFloat32Array()


## What this tile's total forage demand was before anything moved this turn.
func forage_demand_at_turn_start(coord: Vector2i) -> float:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot read demand off the map")
	if i >= _forage_demand_at_turn_start.size():
		return _forage_demand[i]
	return _forage_demand_at_turn_start[i]
```

and take the snapshot at the top of `advance_turn()`, before nodes produce:

```gdscript
func advance_turn() -> int:
	turn += 1
	_recompute_forage()
	_forage_demand_at_turn_start = _forage_demand.duplicate()
	for node in nodes:
		node.produce(self)
	for agent in agents:
		agent.step(self)
	_recover_vitality()
	return turn
```

Then, next to `set_vitality`:

```gdscript
## Report that this tile was worked, for this use, at `intensity` in 0..1.
##
## The world does not ask who is calling. A herd knows that it grazes and a farm
## knows that it cultivates; `WorldMap` is told a use and a quantity and applies
## them, which is `AgDR-013`'s rule — agents report quantities, and nothing here
## branches on what kind of thing reported.
func draw_vitality(coord: Vector2i, use: int, intensity: float) -> void:
	var i := grid.index_of(coord)
	assert(i >= 0, "cannot wear ground off the map")
	var row: PackedFloat32Array = _vitality[use]
	row[i] = Land.depleted(row[i], intensity)
	_vitality[use] = row
```

In `sim/herd.gd`, change `ration_at` to read the grazing share rather than the raw curve:

```gdscript
func ration_at(world: WorldMap, candidate: Vector2i) -> float:
	var supported := species.heads_supported_by(world.forage_for_use(candidate, Land.Use.GRAZE))
	var mouths := world.forage_demand_at(candidate)
	if candidate != coord:
		mouths += population
	# The herd's own population is always in `mouths` and is never below the
	# species minimum, so this cannot divide by zero.
	return supported / maxf(mouths, species.minimum_population)
```

**And `_best_ground` too — this is the one that matters.** It does not call
`ration_at`; it re-implements the same scoring by index, because it runs over the
whole sense-range disc every time a herd re-plans. Changing only `ration_at`
would leave the tile underfoot vitality-aware while every destination still
looked fully productive, so herds would keep walking onto worn ground and the
rotation would have no effect on migration at all. In `_best_ground`, change:

```gdscript
			var supported := species.heads_supported_by(world.forage_by_index(i))
```

to:

```gdscript
			var supported := species.heads_supported_by(
					world.forage_for_use_by_index(i, Land.Use.GRAZE))
```

And in `_graze`, after the population is updated, report what was taken:

```gdscript
func _graze(world: WorldMap) -> void:
	var ration := ration_at(world, coord)
	var scaled := population
	if ration >= 1.0:
		scaled = population * (1.0 + species.growth_rate * minf(ration - 1.0, 1.0))
	else:
		scaled = population * (1.0 - species.decline_rate * minf(1.0 - ration, 1.0))
	world.set_herd_population(self, maxf(scaled, species.minimum_population))

	# Wear is what THIS herd actually ate. Two mistakes are easy here and both
	# were made in earlier drafts of this plan.
	#
	# First: wear is not how hungry the herd was. The tempting `1.0 / ration`
	# saturates on a tile supporting nothing, so a herd on dead winter grass
	# would wear the ground as hard as one on a spring meadow and every tile
	# would floor itself each winter.
	#
	# Second, and subtler: `forage_demand_at()` is the tile's TOTAL demand, every
	# agent standing there. Every co-located herd runs this same code, so
	# charging the tile the total once per herd bills it N times over for N
	# herds — flooring exactly the popular tiles the periodicity experiment is
	# measuring. Charge this herd for its own share: what it wanted, or its
	# proportional cut of what was there when that is less.
	# Third mistake, and the one that survived two reviews: the denominator has
	# to be the census as it stood before anything moved. `step()` grazes and
	# then migrates, so a herd stepped later sees earlier herds already gone from
	# the live census, divides by a smaller number, and claims a share the tile
	# was charged for a moment ago. Shares must sum to at most one, so they are
	# settled against a frozen census.
	var available := world.forage_for_use(coord, Land.Use.GRAZE)
	var mouths := maxf(world.forage_demand_at_turn_start(coord), species.minimum_population)
	var my_share := available * (forage_demand() / mouths)
	var my_want := population * species.consumption_per_head
	world.draw_vitality(coord, Land.Use.GRAZE, minf(my_share, my_want) / Seasons.MAX_FORAGE)
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: 12 tests passing.

- [ ] **Step 5: Run the full suite and expect fallout**

Run: `./test.sh`

Herd behaviour has genuinely changed — herds now wear the ground they stand on, so long-run populations and positions will differ from before. `test/test_herds.gd` may hold assertions calibrated to the old model.

**Fix any failure by re-deriving the expectation, never by weakening the assertion.** If a test asserted "herds recover after overhunting" and now fails, that is a finding about the new equilibrium and it belongs in the commit message. If a test asserted an exact population, re-derive it. If you cannot tell which, stop and report the failing assertion rather than adjusting a number until it passes.

- [ ] **Step 6: Commit**

```bash
git add sim/world_map.gd sim/herd.gd test/test_vitality.gd test/test_herds.gd
git commit -m "Grazing wears the ground, and a herd reads what is left of it"
```

---

### Task 5: Cultivation wears the ground

**Files:**
- Modify: `sim/node.gd`
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: `WorldMap.forage_for_use`, `WorldMap.draw_vitality`, `Land.Use.CULTIVATE`

- [ ] **Step 1: Write the failing test**

Append to `test/test_vitality.gd`:

```gdscript
func test_a_farm_wears_the_ground_it_works() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var farm := CityNode.new(1, land, CityNode.Kind.FARM)
	world.add_node(farm)

	for i in range(Seasons.TURNS_PER_YEAR):
		world.advance_turn()

	assert_lt(world.vitality_at(land, Land.Use.CULTIVATE), 0.95,
			"a year of farming shows on the field")
	assert_almost_eq(world.vitality_at(land, Land.Use.GRAZE), Land.MAX_VITALITY, 0.0001,
			"and leaves the grazing untouched")


func test_a_worn_field_yields_less() -> void:
	var world := _world()
	var land := _first_land_coord(world)
	var fresh := CityNode.new(1, land, CityNode.Kind.FARM)
	world.add_node(fresh)
	world.advance_turn()
	var first_year := fresh.store

	world.set_vitality(land, Land.Use.CULTIVATE, Land.MIN_VITALITY)
	fresh.store = 0.0
	world.advance_turn()

	assert_lt(fresh.store, first_year, "exhausted ground gives less than fresh ground")
	assert_gt(fresh.store, 0.0, "but never nothing — the floor is above zero")
```

Signatures verified against `sim/node.gd`: the constructor is `_init(p_id: int, p_coord: Vector2i, p_kind: int, p_capacity := -1.0)` and `store` is a public `float`, so both calls above are correct as written.

- [ ] **Step 2: Run the test and watch it fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: `test_a_farm_wears_the_ground_it_works` fails — cultivation vitality is untouched.

- [ ] **Step 3: Point the farm at the cultivation share**

In `sim/node.gd`, change `produce`:

```gdscript
func produce(world: WorldMap) -> void:
	if kind != Kind.FARM:
		return
	# The field is worth the seasonal curve scaled by how worn it is for growing
	# things — and working it wears it further. `AgDR-014`.
	var available := world.forage_for_use(coord, Land.Use.CULTIVATE)
	deposit(FARM_YIELD_PER_TURN * available)
	world.draw_vitality(coord, Land.Use.CULTIVATE, available)
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: 14 tests passing.

- [ ] **Step 5: Run the full suite and expect fallout**

Run: `./test.sh`

`test/test_city.gd` asserts that grain flows end to end and that seasonal variation reaches the city. Both should still hold — a farm still produces, just less as its field wears — but any assertion on an *absolute* quantity will have moved.

Same rule as Task 4: re-derive expectations, never weaken assertions.

`test_city.gd` now enforces this rather than asking for it. Its stated margins
sit against floor constants (`SPRING_OVER_WINTER_FLOOR`, `PEAK_OVER_TROUGH_FLOOR`,
`OBSTRUCTED_SHARE_CEILING`) with `test_the_stated_margins_have_not_been_quietly_weakened`
guarding them, so lowering a margin to chase a red suite turns a second test red
rather than passing silently.

If wear has genuinely swamped the seasonal signal, **that is a finding about
`Land.DEPLETION_PER_UNIT` and it should be reported** — the constants that need
changing are in `sim/land.gd`, not in the assertions.

- [ ] **Step 6: Commit**

```bash
git add sim/node.gd test/test_vitality.gd test/test_city.gd
git commit -m "A farm works its field, and the field remembers"
```

---

### Task 6: Options never close, and the best one keeps moving

**Files:**
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–5. No production code should be needed; if it is, the constants are wrong, not the test.

- [ ] **Step 1: Write the test**

This is FR-8a — the ticket's tone guarantee and its reason to exist, in two halves. Append to `test/test_vitality.gd`:

```gdscript
## Ground worth standing on. Deliberately a low bar: the claim being tested is
## that options never vanish, not that they stay good.
const VIABLE := 0.10


func test_a_herd_always_has_somewhere_worth_going() -> void:
	# FR-8a, first half, and the one that is not negotiable. Depletion may move
	# the answer; it may never remove the question. If this fails, the constants
	# are wrong — do not lower VIABLE to make it pass.
	var world := _world()

	for turn in range(Seasons.TURNS_PER_YEAR * 40):
		world.advance_turn()
		if turn % Seasons.TURNS_PER_SEASON != 0:
			continue
		for herd in world.herds():
			var options := 0
			for coord in world.grid.all_coords():
				if HexGrid.distance(herd.coord, coord) > herd.species.sense_range:
					continue
				if world.forage_for_use(coord, Land.Use.GRAZE) >= VIABLE:
					options += 1
			assert_gt(options, 0,
					"herd %d had nowhere to go on turn %d" % [herd.id, world.turn])


func test_the_best_ground_within_reach_keeps_changing() -> void:
	# FR-8a, second half. This is the periodicity fix stated locally: if the best
	# tile at a place never changes, nothing downstream ever has a reason to.
	var world := _world()
	var origin := _first_land_coord(world)

	var seen := {}
	var previous := Vector2i(-999, -999)
	var changes := 0
	for year in range(40):
		for i in range(Seasons.TURNS_PER_YEAR):
			world.advance_turn()
		var best := _best_within(world, origin, 4)
		seen[best] = true
		if best != previous:
			changes += 1
		previous = best

	assert_gt(changes, 5, "the best ground nearby changed repeatedly over forty years")
	assert_gt(seen.size(), 2, "and it was not just alternating between two tiles")


func _best_within(world: WorldMap, origin: Vector2i, radius: int) -> Vector2i:
	var best := origin
	var best_value := -1.0
	for coord in world.grid.all_coords():
		if HexGrid.distance(origin, coord) > radius:
			continue
		var value := world.forage_for_use(coord, Land.Use.GRAZE)
		if value > best_value:
			best_value = value
			best = coord
	return best
```

- [ ] **Step 2: Run the tests**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: both pass. If the first fails, the depletion constant is too aggressive relative to recovery — fix `Land.DEPLETION_PER_UNIT` or `RECOVERY_HALF_LIFE_TURNS` and re-run `test_land.gd`, which asserts their relationship. **Do not lower `VIABLE`.**

If the second fails, vitality is not producing enough variation to move the best tile around. Report the number of changes observed before adjusting anything — that number is the evidence for whether this mechanism works at all, and it belongs in the commit message either way.

- [ ] **Step 3: Run the full suite**

Run: `./test.sh`

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add test/test_vitality.gd
git commit -m "FR-8a: depletion moves the answer and never removes the question"
```

---

### Task 7: The periodicity gate

**Files:**
- Create: `tools/periodicity_check.gd`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `WorldGen.generate` (which populates herds itself — do not populate again), `WorldMap.advance_turn`, `WorldMap.vitality_data`

This is the spec's primary acceptance test and the reason `AgDR-014` was written. The baseline being beaten was measured before any of this existed: **every seed** settled into a repeating annual cycle — years 7, 17, 11 and 5 — with three of the four becoming completely static.

It lives in `tools/` rather than `test/` because it runs thousands of turns — the same reason `world_fingerprint.gd` lives there, and because GUT treats a non-`GutTest` script under `test/` as a broken test.

- [ ] **Step 1: Write the tool**

Create `tools/periodicity_check.gd`:

```gdscript
extends SceneTree

## Does the world still settle into a repeating cycle?
##
## `AgDR-014` exists because it did. Before land had any memory, a probe
## fingerprinting each year found **every seed** converging to a fixed annual
## cycle — settling at years 7, 17, 11 and 5 — with three of the four doing
## precisely the same thing every year forever after. Forage was a pure function
## of terrain and season, terrain never changed, and a deterministic
## gradient-follower over a periodic field has nowhere to go but a limit cycle.
##
## This is the gate that says that stopped being true. It prints one line per
## seed and exits non-zero if any world settles.
##
## The fingerprint is exact string match over quantised floats, which makes it
## *conservative in the right direction*: a world that is effectively static but
## jittering in the last decimal place will be reported as varying. If this gate
## passes, non-convergence is at least as good as it claims.

## Every seed Probe B measured, not a sample of them.
##
## All four settled in the baseline — years 7, 17, 11 and 5 — so a gate covering
## a subset could pass while a documented converging seed still settles, and
## `./test.sh` would report success with the primary acceptance criterion unmet.
const SEEDS := [20260815, 987654321, 42, 7]
const YEARS := 200


func _init() -> void:
	var failed := false
	for world_seed in SEEDS:
		var world := WorldGen.generate(world_seed)
	
		var prints: Array[String] = []
		for year in range(YEARS):
			for i in range(Seasons.TURNS_PER_YEAR):
				world.advance_turn()
			prints.append(_fingerprint(world))

		var period := -1
		var settled_at := -1
		for i in range(prints.size()):
			for j in range(i + 1, prints.size()):
				if prints[i] == prints[j] and _confirms(prints, i, j - i):
					settled_at = i
					period = j - i
					break
			if period > 0:
				break

		if period > 0:
			failed = true
			print("FAIL seed %d settled at year %d, repeating every %d year(s)"
					% [world_seed, settled_at + 1, period])
		else:
			print("ok   seed %d did not settle in %d years (%d distinct year-states)"
					% [world_seed, YEARS, prints.size()])

	quit(1 if failed else 0)


## A single pair of equal fingerprints is not a cycle.
##
## These digests are lossy — populations and vitality are quantised, and each
## vitality row is folded modulo a prime — so two sampled years can collide while
## the world goes on diverging afterwards. Acting on one match would let the
## primary acceptance gate report a false convergence and fail `./test.sh` on a
## world that is behaving correctly, which is the worse direction for this gate
## to be wrong in: a false alarm gets tuned away, and tuning away a real one is
## how the finding this record exists for gets lost.
##
## A candidate period is only accepted if every remaining sample repeats it.
static func _confirms(prints: Array, start: int, period: int) -> bool:
	var checked := 0
	for k in range(start + period, prints.size()):
		if prints[k] != prints[k - period]:
			return false
		checked += 1
	# Require the claim to rest on more than the pair that suggested it.
	return checked >= period * 2


## Herds and land together. Herd state alone was what the original probe hashed;
## vitality is folded in because it is the thing that is supposed to be keeping
## the world moving, and a gate that cannot see it would pass on a world where
## only the animals wobbled.
func _fingerprint(world: WorldMap) -> String:
	var parts: Array[String] = []
	for herd in world.herds():
		parts.append("%d:%d,%d:%d" % [herd.id, herd.coord.x, herd.coord.y,
				roundi(herd.population * 100.0)])
	for use in range(Land.USE_COUNT):
		var acc := 0
		var i := 0
		for value in world.vitality_data(use):
			acc = (acc * 31 + roundi(value * 1000.0) + i) % 1000000007
			i += 1
		parts.append("v%d:%d" % [use, acc])
	return "|".join(parts)
```

- [ ] **Step 2: Run it and read the result**

Run: `godot --headless -s tools/periodicity_check.gd`

Expected: four `ok` lines, exit 0.

Note the gate now requires a candidate period to be confirmed by every remaining
sample before it is called a cycle, so a lossy-fingerprint collision cannot fail
the suite on a world that is still moving.

**Time it.** Four seeds x 200 years is 19,200 turns and this runs on every
`./test.sh`. If it makes the suite unacceptably slow, reduce `YEARS` — never
`SEEDS`. All four baseline seeds settled by year 17, so years are the cheap
dimension and seed coverage is the one the gate exists for. State the measured
runtime in the PR.

If a seed still settles, **that is the finding this whole ticket exists to produce and it must be reported, not tuned around.** Report the year and period. `AgDR-014`'s own refutation clause covers this case: if land memory does not break the cycle, the honest next move is exogenous variation via #31, not adjusting these constants until the gate goes green.

- [ ] **Step 3: Wire it into `test.sh`**

Find the block that runs the existing fingerprint tools (search for `world_fingerprint.gd`) and add alongside them, following the same shape as its neighbours:

```bash
echo "[test] checking the world still varies year to year"
if ! "$GODOT" --headless -s tools/periodicity_check.gd; then
  echo "ERROR: a world settled into a repeating annual cycle. AgDR-014 exists to" >&2
  echo "       prevent exactly this; see its refutation clause before tuning." >&2
  exit 1
fi
```

- [ ] **Step 4: Run the full suite**

Run: `./test.sh`

Expected: exit 0, with the new line in the output.

- [ ] **Step 5: Commit**

```bash
git add tools/periodicity_check.gd test.sh
git commit -m "The world must not settle: the periodicity gate AgDR-014 was written for"
```

---

### Task 8: Determinism across processes

**Files:**
- Modify: `tools/world_fingerprint.gd`
- Test: `test/test_vitality.gd`

**Interfaces:**
- Consumes: `WorldMap.vitality_data`

- [ ] **Step 1: Write the failing test**

Append to `test/test_vitality.gd`:

```gdscript
func test_two_worlds_from_one_seed_wear_identically() -> void:
	var a := _world()
	var b := _world()

	for i in range(Seasons.TURNS_PER_YEAR * 20):
		a.advance_turn()
		b.advance_turn()

	for use in [Land.Use.GRAZE, Land.Use.CULTIVATE]:
		assert_eq(a.vitality_data(use), b.vitality_data(use),
				"twenty years of wear reproduced exactly for use %d" % use)
```

- [ ] **Step 2: Run it**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_vitality.gd -gexit`

Expected: PASS. Everything added in this plan is ordered array arithmetic with no randomness, so this should be green on the first run. **If it fails, stop** — a determinism failure here means something reads an unordered collection or an engine value, and it must be found rather than retried.

- [ ] **Step 3: Fold vitality into the cross-process digest**

The in-process test above cannot catch a divergence that is constant within a process and varies between them — which is the whole reason `world_fingerprint.gd` exists. Vitality now carries state forward, so it must be in that digest.

In `tools/world_fingerprint.gd`, extend `_fingerprint` so the final fold includes vitality:

```gdscript
static func _fingerprint(map: WorldMap) -> int:
	var acc := _fold(_fold(17, map.terrain_data()), _quantised_forage(map))
	for i in range(TURNS):
		map.advance_turn()
	acc = _fold(_fold(acc, [map.turn, map.season()]), _quantised_forage(map))
	acc = _fold(acc, _quantised_state(map))
	return _fold(acc, _quantised_vitality(map))


## Every tile's wear, for every use, quantised to integers in grid order.
##
## Folded in for the same reason the record gives for forage and live state: the
## cross-process check is only as wide as what it hashes, and a digest blind to
## vitality would keep agreeing across processes while every worn tile in the
## world diverged.
static func _quantised_vitality(map: WorldMap) -> Array:
	var out := []
	for use in range(Land.USE_COUNT):
		for value in map.vitality_data(use):
			out.append(roundi(value * 1000.0))
	return out
```

Signature verified: `_fold(acc: int, values) -> int` iterates `values` and folds each through `(out * 31 + int(value) + 1) % 1000000007`, so passing an `Array` of ints is exactly what its existing callers do.

- [ ] **Step 4: Run the full suite**

Run: `./test.sh`

Expected: exit 0, including the line reporting that the fingerprint tool reproduced every seed identically across two processes.

- [ ] **Step 5: Commit**

```bash
git add tools/world_fingerprint.gd test/test_vitality.gd
git commit -m "Fold vitality into the cross-process digest"
```

---

## Done bar

Check each against the ticket before opening the PR:

- [ ] Vitality is per use, stored as flat arrays in grid order (#38 AC1)
- [ ] Working a tile lowers that use's vitality; not working it raises it (AC2)
- [ ] `_best_ground()` scores destinations through vitality, not raw forage — otherwise migration ignores wear entirely
- [ ] Each herd is charged only for its own share of a shared tile's grazing
- [ ] Recovery is unconditional — no policy, structure or action required (AC3)
- [ ] Options never close: no agent ever has zero viable tiles in reach (AC4)
- [ ] The best reachable tile changes repeatedly rather than settling (AC5)
- [ ] No absorbing states: a flattened region recovers fully (AC6)
- [ ] The periodicity gate passes over 200 years (AC7)
- [ ] Determinism holds in-process and across processes (AC8)
- [ ] The three clocks are named relative to each other, with reasoning in `land.gd` (AC9)
- [ ] Nothing removes a node, route, agent or anything placed (AC10)
- [ ] `./test.sh` exits 0 (AC11)
- [ ] `AgDR-014` is merged — **already done**, ratified 2026-08-29 (AC12)

AC13 is the human one: a long run must read as land *rotating* rather than as slow decline or flicker. State in the PR body that it is unverified by the agent, and say what the periodicity gate reported so there is a number next to the judgement.

## What this plan does not do

Practices, households, adoption, surplus, standing — all of plan 2. The `Land.Use` enum is where they attach: a practice becomes a use, and nothing else in this plan has to change to accommodate one.
