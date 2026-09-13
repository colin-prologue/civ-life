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
## overshoots, and where continuous maximum use actually settles — are asserted
## on the numbers directly.

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


## How many turns of unbroken maximum use it takes to halve a full tile, with
## recovery pushing back the whole time.
##
## This is the wear clock stated in the same units as `RECOVERY_HALF_LIFE_TURNS`,
## which is the only way to say whether the two are in proportion — and being in
## proportion is what `AgDR-014` is actually asking for. Land that wears far
## faster than it recovers reads as decline; land that recovers far faster than it
## wears reads as nothing happening at all. Rotation is what happens when the two
## clocks are within about a season of each other, and `test_land.gd` asserts
## exactly that, so `DEPLETION_PER_UNIT` cannot be retuned on its own.
##
## Measured against the real turn order — deplete, then recover — rather than
## against depletion alone, because that is the sequence a worked tile actually
## experiences. Returns -1 if recovery outpaces maximum use so the tile never
## halves at all, which is a statement that the constants are out of proportion
## rather than a number.
static func wear_half_life_turns() -> int:
	var vitality := MAX_VITALITY
	var turns := 0
	while vitality > MAX_VITALITY * 0.5:
		var next := recovered(depleted(vitality, 1.0))
		if next >= vitality:
			return -1
		vitality = next
		turns += 1
	return turns


## One turn of nobody working this tile, for this use.
##
## Exponential approach to the ceiling, so it cannot overshoot and there is no
## accumulator to drift — the `AgDR-009` no-drift property holds by construction
## here exactly as it did for forage.
static func recovered(vitality: float) -> float:
	return vitality + recovery_rate() * (MAX_VITALITY - vitality)


## One turn of recovery over a whole row, returned rather than mutated in place
## because `PackedFloat32Array` is copy-on-write.
##
## Exists for speed, and the speed is not hypothetical. `recovered()` calls
## `recovery_rate()`, which calls `pow()`; applied per tile per use per turn that
## is 2,400 `pow()` calls a turn, which measured 2,522 ms against
## `test_seasons.gd`'s 2,000 ms budget for 500 turns. Hoisting the rate out of
## the loop makes it two calls a turn.
##
## Same trade `Seasons.forage_row()` already makes for the same reason: fetch the
## rate once, index per tile. `test_land.gd` asserts this agrees with
## `recovered()` element by element, so the two cannot drift apart.
##
## Land already at the ceiling is skipped, at two levels, because recovery runs
## over every tile of every use every turn while only the handful of tiles
## somebody is standing on or farming are ever below full. `v + r * (1 - v)` at
## `v == MAX_VITALITY` is exactly `MAX_VITALITY`, so a full row is a fixed point
## and a full tile is its own answer: neither skip changes a value.
##
## The row-level skip asks `count()`, which scans in native code, rather than
## looking for a value below full in a GDScript loop — the loop is the entire
## cost being avoided, so the test for whether to run it must not itself be one.
## Deliberately stateless: a "somebody wore this" flag would be faster still, but
## it would have to be set by every future path that lowers a value, and a path
## that forgot would silently stop that use recovering. Recomputing the answer
## cannot go stale.
##
## Measured on a 1200-tile world over 500 turns, against `test_seasons.gd`'s
## 2,000 ms budget: the turn loop costs 887 ms with this pass removed entirely,
## 2,646 ms with it unconditional, 1,637 ms with only the per-tile skip, and
## 1,201 ms with both. The budget is wall-clock and this machine was carrying
## other work, so read the four as a ratio rather than as absolute times.
static func recovered_row(row: PackedFloat32Array) -> PackedFloat32Array:
	if row.count(MAX_VITALITY) == row.size():
		return row
	var rate := recovery_rate()
	for i in range(row.size()):
		var value := row[i]
		if value >= MAX_VITALITY:
			continue
		row[i] = value + rate * (MAX_VITALITY - value)
	return row


## One turn of this tile being worked, at `intensity` in 0..1.
static func depleted(vitality: float, intensity: float) -> float:
	return maxf(MIN_VITALITY, vitality - DEPLETION_PER_UNIT * clampf(intensity, 0.0, 1.0))
