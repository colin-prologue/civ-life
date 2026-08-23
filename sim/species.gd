class_name Species
extends RefCounted

## What one kind of animal eats, how fast it breeds, and how far it walks.
##
## Split out from `Herd` because a herd is an instance and this is a kind: every
## herd of the same animal shares one of these, and adding a second animal later
## is a new preset rather than a new class. Non-goal on this ticket, so there is
## exactly one preset.
##
## The numbers are calibrated rather than chosen. What fixes them is the
## behaviour they have to produce over a thousand turns — a population that
## neither dies out nor runs away, and that visibly moves between its high and
## its low across a year. `test/test_herds.gd` asserts all three, so a change
## here that breaks one of them fails the suite rather than being discovered by
## watching. See the calibration notes in that file for the observed values.

## Display name, used by logs and the renderer's legend.
var name: String

## Forage one head eats in one turn, in the units of `Seasons.forage_for()`. A
## tile therefore supports `forage / consumption_per_head` heads at full ration,
## which is what makes the seasonal forage curve a carrying capacity rather than
## a decoration.
var consumption_per_head: float

## Fraction the population grows by in one turn when fed at twice its needs. Fed
## exactly to its needs it holds; the response in between is proportional.
var growth_rate: float

## The same in the other direction, for a herd fed below its needs. Larger than
## `growth_rate` on purpose: animals thin faster than they breed, and it is that
## asymmetry that makes a year's cycle read as a rise and a fall rather than as
## a sine wave.
var decline_rate: float

## Tiles the herd may step in one turn. One, and the movement code walks that
## many single-tile steps, so the value is a range rather than a jump.
var move_range: int

## How far the herd can tell that somewhere is better than here, in tiles. It
## still only walks `move_range` a turn — this decides which direction, not how
## fast.
##
## Not a free parameter. At 1 — a herd choosing purely between the tiles it is
## touching — herds measurably do not migrate: a herd in the middle of a meadow
## sees six identical neighbours all winter and never finds the wood two tiles
## away. That was observed, not predicted, and it is what this value exists to
## fix. See `.decisions/AgDR-010-herds-follow-a-sensed-gradient.md`.
var sense_range: int

## The population a herd is never thinned below. Not a rule about biology — it
## is a floor under float arithmetic, and the intent file's restoring-forces
## rule says a knocked-down population comes back rather than being erased.
## Observed populations sit two orders of magnitude above it; if that ever stops
## being true, the tuning is wrong and this is not the place to fix it.
var minimum_population: float

## Heads a herd is placed with at world generation.
var starting_population: float


func _init(
	p_name: String,
	p_consumption_per_head: float,
	p_growth_rate: float,
	p_decline_rate: float,
	p_move_range: int,
	p_sense_range: int,
	p_minimum_population: float,
	p_starting_population: float
) -> void:
	name = p_name
	consumption_per_head = p_consumption_per_head
	growth_rate = p_growth_rate
	decline_rate = p_decline_rate
	move_range = p_move_range
	sense_range = p_sense_range
	minimum_population = p_minimum_population
	starting_population = p_starting_population


## The one animal in the world: a mixed grazing-and-browsing herd, at home on
## grass in summer and in forest in winter, which is what gives it somewhere to
## go when the meadows die back.
static func grazer() -> Species:
	return Species.new("herd", 0.006, 0.070, 0.110, 1, 4, 2.0, 40.0)


## How many heads a tile with this much forage can feed at full ration.
func heads_supported_by(forage: float) -> float:
	return forage / consumption_per_head
