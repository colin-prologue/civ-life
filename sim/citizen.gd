class_name Citizen
extends Agent

## A person who walks a route, picks grain up at one end and puts it down at the
## other.
##
## This is the second implementation of `Agent`, and it is the one `AgDR-002`
## said to watch. The record's stated refutation was that citizen logic and
## wildlife logic would share a class but no actual behaviour — every method
## branching on which kind it is. That is not what happened: `Agent` gained one
## method while this was written (`forage_demand`, which is a quantity rather
## than a question about type), and neither it nor `WorldMap` asks anywhere
## whether an agent is a citizen. A citizen and a herd are stepped by the same
## loop, moved by the same mutator, and meet each other by standing on the same
## tile. See the grep in `test/test_city.gd`, which fails the suite if that stops
## being true.
##
## **Direction is not stored.** A citizen carrying grain is walking to the
## granary; a citizen carrying nothing is walking back to the farm. That is the
## whole state machine, and it has the useful property that it cannot get out of
## step with itself — there is no flag that can say "outbound" while the sack is
## empty.
##
## **Waiting.** At the farm with nothing to carry, a citizen stays put rather
## than walking an empty road. It reads as waiting for the harvest, and it keeps
## the granary's arithmetic honest: every arrival at the granary is a delivery.

## The most one person carries in one trip. Set above what the farm grows during
## a round trip at peak season, so an unstressed route is limited by the land
## rather than by the sack — `AgDR-002`'s tuning constraint is that the walker
## layer is boringly reliable when nothing is stressing it, and a carrier that
## is permanently the bottleneck is a layout puzzle waiting to happen.
const CARRY_CAPACITY := 8.0

## Turns a citizen will stand and wait for a tile to clear before pushing past
## whatever is on it.
##
## This is the guarantee that interference is temporary. A herd that settles on a
## road slows the road down — sharply, one turn moved in every seven — but it can
## never sever it, however long it stays. `world-growth-tone` rule 1 allows the
## world to disturb a flow and forbids it to remove what was built, and a route
## that stops working permanently is the second thing wearing the first one's
## clothes.
##
## One season is the bound because that is the scale the intent describes: a herd
## crossing a route costs a delivery, not a city.
const MAX_HELD_UP := Seasons.TURNS_PER_SEASON

var route: Route

## Grain in hand. Also, and not incidentally, which way this person is walking.
var carrying: float

## The most this citizen carries at once.
var capacity: float

## Where on `route.path` the citizen is standing. Kept alongside `coord` because
## a route may in principle cross itself, and "which tile am I on" is then not
## enough to answer "how far along am I".
var _index: int

## Consecutive turns spent unable to leave the current tile. Zero when the road
## is clear, 1 on the first turn of a hold-up.
##
## Readable rather than private because the turn report needs to know when a
## route's throughput dropped, and this citizen already counts it. The
## alternative was for the report to keep its own memory of who moved last turn,
## which would be a second copy of a fact the world already holds — and a report
## with state of its own is a cache that can disagree with the world.
var held_up: int


func _init(p_id: int, p_route: Route, p_index := 0, p_capacity := CARRY_CAPACITY) -> void:
	assert(p_index >= 0 and p_index < p_route.path.size(), "a citizen starts on the route")
	super(p_id, p_route.path[p_index])
	route = p_route
	_index = p_index
	carrying = 0.0
	capacity = p_capacity
	held_up = 0


## One turn: do the business of wherever you are standing, then walk.
##
## In that order, so a citizen who arrived at the farm last turn leaves with this
## turn's harvest rather than idling for a turn on arrival.
func step(world: WorldMap) -> void:
	if _index == 0:
		_collect()
	elif _index == route.path.size() - 1:
		_deliver()

	if _held_up_by_traffic(world):
		return
	if _index == 0 and carrying <= 0.0:
		# Nothing to carry. Wait at the farm rather than walk an empty road.
		return
	_walk(world)


## Fill up from the source node, up to what will fit in the sack.
func _collect() -> void:
	carrying += route.source.withdraw(capacity - carrying)


## Put down what the sink node will take. A full granary is not a failure and
## nothing is thrown away — the citizen keeps hold of the remainder and tries
## again next turn, which is the only way "stored grain never decreases" can be
## true of both ends of the route at once.
func _deliver() -> void:
	carrying -= route.sink.deposit(carrying)


## Whether something is in the way this turn.
##
## Interference is co-location plus one number, and nothing else. This asks the
## world what the tile's forage demand is — the same total a herd reads when it
## is deciding where to graze — and does not ask, and cannot find out, what kind
## of thing is producing it. A road full of livestock is slow to walk down. There
## is no rule here about herds, no lookup of what the obstruction is, and no
## damage in either direction.
##
## The limit of that, stated plainly rather than overclaimed: anything reporting
## no forage demand is invisible to this. Two citizens pass each other without
## noticing, which is right, and a future band would have to report something for
## this to see it. What the shared layer buys is that such a band needs a number,
## not a branch.
func _held_up_by_traffic(world: WorldMap) -> bool:
	if world.forage_demand_at(coord) <= 0.0:
		held_up = 0
		return false
	held_up += 1
	if held_up > MAX_HELD_UP:
		held_up = 0
		return false
	return true


## One tile along the route: toward the granary with a load, back toward the farm
## without one.
func _walk(world: WorldMap) -> void:
	var direction := 1 if carrying > 0.0 else -1
	var next := _index + direction
	if next < 0 or next >= route.path.size():
		return
	_index = next
	world.move_agent(self, route.path[_index])
