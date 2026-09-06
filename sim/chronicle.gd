class_name Chronicle
extends RefCounted

## A short rolling record of per-turn quantities, kept by the world so that
## somebody drawing it can say which way a number is going.
##
## **Why this exists in `sim/` rather than in the renderer.** A direction needs
## two readings, and neither of the two places a renderer could get a second
## reading from is available. It cannot keep one itself — `game/README.md` says
## the view holds no state that would not survive being thrown away and rebuilt
## from the world, and a trend buffer is exactly such state. It cannot recompute
## one either: forage is a pure function of `(seed, turn)` and could be
## re-derived, but a granary's store is the residue of every delivery ever made
## to it, and `WorldMap`'s own header already concedes that a world with agents
## in it is no longer reconstructible from two integers. So the history has to be
## somewhere, and the world is the only place left.
##
## **This is a ledger, not a rule.** Nothing in the turn loop reads it back;
## `advance_turn()` writes to it last and no system consults it. Deleting this
## file would change nothing about what the simulation does and everything about
## what can be said about it. That is the line `AgDR-001` draws, and it is why
## this is a query rather than a rule arriving in `sim/` by the back door.
##
## **Bounded on purpose.** One season of samples per series, dropped from the
## front. An unbounded log would grow without limit across the thousand-turn runs
## the herd tests do, and nothing here wants to answer a question about last
## year — "is it filling or emptying *now*" is a question about the recent past,
## and a window that reaches back further answers it worse, not better.

## How many turns of each series are kept. One season, so a trend is a claim
## about the current stretch of weather rather than about the whole run.
const WINDOW := Seasons.TURNS_PER_SEASON

## The series the world records. Named here rather than passed as loose strings
## so a typo at the writing end and a typo at the reading end cannot silently
## agree to be different series.
const GRANARY_STORE := "granary_store"
const GRANARY_IN := "granary_in"
const GRANARY_OUT := "granary_out"
const FARM_YIELD := "farm_yield"
const HERD_POPULATION := "herd_population"

## How far a quantity has to move, as a fraction of its own magnitude, before it
## is called rising or falling rather than steady.
##
## Above zero because float arithmetic makes an exactly flat series unlikely, and
## an arrow that flickers between up and down on a quantity that is not moving is
## worse than no arrow — it reports noise as news.
const DEADBAND := 0.02

## series name -> the last `WINDOW` values, oldest first.
var _series: Dictionary = {}


## Append this turn's value for one series.
func record(key: String, value: float) -> void:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	row.append(value)
	if row.size() > WINDOW:
		row = row.slice(row.size() - WINDOW)
	_series[key] = row


## The most recent value, or zero for a series nothing has been recorded into.
##
## Zero rather than an error: a world on turn 0 has no history, and a display
## asking about it should get an honest nothing rather than have to know whether
## the clock has moved yet.
func latest(key: String) -> float:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	return 0.0 if row.is_empty() else row[row.size() - 1]


## The mean of the whole window — the per-turn rate over the period, for a series
## that records a per-turn amount.
func rate(key: String) -> float:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	if row.is_empty():
		return 0.0
	return _mean(row, 0, row.size())


## Which way this series is going: `1` rising, `-1` falling, `0` steady or not
## yet known.
##
## The newer half of the window against the older half, rather than the last
## value against the one before it. A single-step comparison on a quantity that
## arrives in lumps — a delivery lands or it does not — reports the lumps rather
## than the direction, and a granary being filled steadily would read as
## alternating up and down.
func trend(key: String) -> int:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	if row.size() < 2:
		return 0
	@warning_ignore("integer_division")
	var half := row.size() / 2
	var older := _mean(row, 0, half)
	var newer := _mean(row, row.size() - half, row.size())
	return direction(older, newer)


## How many samples this series is holding. Exists so a caller can tell "steady"
## apart from "nothing recorded yet" when it needs to.
func span(key: String) -> int:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	return row.size()


## The raw window, oldest first. For tests and for anything that wants to draw
## the shape rather than the direction.
func samples(key: String) -> PackedFloat32Array:
	var row: PackedFloat32Array = _series.get(key, PackedFloat32Array())
	return row.duplicate()


## Rising, falling or steady, for two readings.
##
## The deadband is relative to the larger of the two magnitudes rather than
## absolute, because the same function is asked about a granary holding hundreds
## and about a yield of under one, and a fixed threshold would be all noise on
## one and all silence on the other.
static func direction(older: float, newer: float) -> int:
	var scale := maxf(absf(older), absf(newer))
	if scale <= 0.0:
		return 0
	var delta := newer - older
	if absf(delta) < DEADBAND * scale:
		return 0
	return 1 if delta > 0.0 else -1


static func _mean(row: PackedFloat32Array, from: int, to: int) -> float:
	if to <= from:
		return 0.0
	var total := 0.0
	for i in range(from, to):
		total += row[i]
	return total / float(to - from)
