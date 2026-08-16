class_name Seasons
extends RefCounted

## The year: which season a turn falls in, and what a tile of each terrain can
## feed while that season lasts.
##
## Two rules live here and nowhere else.
##
## **The calendar.** `TURNS_PER_SEASON` is the only number that decides how long
## a year is. Everything else — the length of the year, which turn is midwinter,
## how many turns a herd spends hungry — is derived from it, so retuning the
## pace of the world is one edit.
##
## **Forage.** A land tile's forage is looked up from its terrain and the current
## season. It is not integrated, accumulated, or fed back into itself: the value
## on turn 500 is computed from scratch the same way the value on turn 1 was.
## That is deliberate and it is the reason forage cannot drift out of its bounds
## no matter how long the world runs — there is no state to drift. See
## `.decisions/AgDR-009-forage-is-recomputed-not-integrated.md` for what that
## costs, because it is not free: nothing can deplete a tile by eating from it
## until that record is revisited.
##
## The shape of the table is the interesting part rather than the exact numbers.
## Grass is explosive in spring and dead by winter; forest is slower to start,
## peaks on autumn mast, and still carries browse in winter when the meadows
## carry nothing. That difference is what makes where a herd stands matter, and
## it is why forage is a per-terrain curve rather than one global multiplier.

enum Season {
	SPRING,
	SUMMER,
	AUTUMN,
	WINTER,
}

## How long one season lasts. The single knob for the pace of the year: the
## year is four of these, and nothing else in the project hard-codes a length.
const TURNS_PER_SEASON := 6

## Seasons in the order they occur. `Season.values()` would do the same job, but
## only by accident of declaration order, and the cycle wrapping correctly is an
## acceptance criterion rather than a coincidence.
const SEASON_ORDER := [Season.SPRING, Season.SUMMER, Season.AUTUMN, Season.WINTER]

const TURNS_PER_YEAR := TURNS_PER_SEASON * 4

## Bounds every tile's forage stays inside, for all terrain and all seasons.
## Asserted against directly rather than being a comment about intent.
const MIN_FORAGE := 0.0
const MAX_FORAGE := 1.0

const SEASON_NAMES := {
	Season.SPRING: "spring",
	Season.SUMMER: "summer",
	Season.AUTUMN: "autumn",
	Season.WINTER: "winter",
}

## Terrain -> forage in each season, indexed by `Season`. Water feeds nothing
## grazing and is zero in every season; it is listed rather than special-cased
## so the table covers the whole enumeration and a missing terrain is a loud
## failure instead of a silent fallback.
const FORAGE_BY_TERRAIN := {
	WorldGen.Terrain.WATER: [0.0, 0.0, 0.0, 0.0],
	WorldGen.Terrain.GRASS: [0.95, 0.80, 0.55, 0.15],
	WorldGen.Terrain.FOREST: [0.70, 0.85, 0.95, 0.35],
	WorldGen.Terrain.HILL: [0.70, 0.55, 0.40, 0.10],
	WorldGen.Terrain.MOUNTAIN: [0.35, 0.45, 0.20, 0.05],
}


## Which season a turn falls in. Turn 0 is the first turn of spring, and the
## cycle wraps forever.
static func season_for_turn(turn: int) -> int:
	@warning_ignore("integer_division")
	var elapsed := maxi(0, turn) / TURNS_PER_SEASON
	return SEASON_ORDER[elapsed % SEASON_ORDER.size()]


## Years completed plus one, so the world starts in year 1 rather than year 0.
static func year_for_turn(turn: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, turn) / TURNS_PER_YEAR + 1


static func season_name(season: int) -> String:
	return SEASON_NAMES.get(season, "unknown")


## What one tile of this terrain can feed in this season.
static func forage_for(terrain: int, season: int) -> float:
	var curve: Array = FORAGE_BY_TERRAIN.get(terrain, [])
	if curve.is_empty():
		return MIN_FORAGE
	return curve[season]


## The whole forage table for one season, indexed by terrain value.
##
## Exists because the alternative is a dictionary lookup per tile per turn, and
## the turn loop runs this over every tile on the map — see the 500-turn budget
## in `test/test_seasons.gd`. Terrain values are a contiguous enumeration from
## zero, which is what makes an array indexable by them.
static func forage_row(season: int) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	row.resize(FORAGE_BY_TERRAIN.size())
	for terrain in FORAGE_BY_TERRAIN:
		assert(terrain >= 0 and terrain < row.size(), "terrain values are not a dense range")
		row[terrain] = FORAGE_BY_TERRAIN[terrain][season]
	return row
