class_name TurnReport
extends RefCounted

## What changed in the world during one turn, in an order two runs of the same
## seed will always agree on.
##
## `world-growth-tone` names attention as one of the two sources of tension in
## the game: more happens than one player can watch, and the cost of any choice
## is the thing they were not watching. That is only pressure if it is possible
## to find out what was missed, and until now the only feedback was a line of
## running totals — a total that moves says something happened somewhere, which
## is not the same as saying what, or where.
##
## Three properties are load-bearing.
##
## **It is derived, never a source of truth.** The report is built by comparing a
## snapshot taken at the start of the turn against the world at the end of it.
## Nothing here is written back, nothing accumulates across turns, and throwing
## every report away changes nothing about how the world runs. If a kind of
## change ever needs the report to remember something the world does not, that is
## the world missing a variable — say so, rather than giving the report a cache.
##
## **Notability is a bar, not a firehose.** Every kind below states the threshold
## it has to cross. A herd taking one step across a meadow is not news; leaving
## the meadow is. A turn in which nothing crossed a bar produces an empty report,
## and that is the correct answer rather than a gap to be filled.
##
## **It is bounded, and it says when it truncated.** At most `MAX_ENTRIES`
## entries. When more changes than that happen at once, the report keeps the most
## significant ones by `TurnChange.Kind` order and spends its last slot saying how
## many it dropped. Silent truncation would make a busy turn look like a quiet
## one, which is the exact failure this instrument exists to prevent.
##
## Nothing in the simulation branches on whether anyone reads this. The world
## builds a report every turn whether or not a renderer exists.

## The most entries one report will carry, including the entry that reports the
## drop.
##
## Six, and small on purpose. `world-growth-tone` rule 6 asks for fewer and
## chunkier statements over a complete log, and the thing being defended against
## is a change feed that reads as a notification queue — a list the eye skips
## rather than a thing that sends it somewhere. Six lines can be taken in at a
## glance; twenty cannot, however accurate they are.
const MAX_ENTRIES := 6

## Heads a herd's population has to cross a multiple of before the change is
## worth reporting.
##
## Herds run from a floor of a couple of head to a few hundred and move by
## several percent a turn, so a bar stated as an absolute change would fire every
## turn on the large herds and never on the small ones. A *mark crossed* does not
## have that problem: it fires when a herd passes 50, 100, 150 head, at whatever
## rate it happens to be growing.
const HERD_STEP := 50.0

## Grain a granary's store has to cross a multiple of before it is worth
## reporting.
##
## The acceptance criteria for this asked for "a granary crossing a fill
## fraction", and a fraction of capacity is the wrong bar here: `CityNode`
## deliberately sizes a granary at 5000 so that nothing in a normal run ever
## meets it (a granary that fills up and starts refusing deliveries would be a
## scarcity mechanic arriving by the back door). A hundred turns of one farm puts
## something like fifty grain in it, so any fraction coarse enough to be a
## fraction would never fire at all. The bar is therefore a chunk of grain, and
## ten of them is roughly a fortnight of good harvest.
const STORE_STEP := 10.0

## The turn this report describes — the turn the world is on now, not the one it
## left.
var turn: int

## The changes, in report order: the season first if it turned, then everything
## with a place on the map in grid order, then the dropped-entry count if there
## was one. See `_precedes()`.
var entries: Array[TurnChange] = []


func _init(p_turn: int) -> void:
	turn = p_turn


## A turn in which nothing crossed a bar. Common, and correct.
func is_empty() -> bool:
	return entries.is_empty()


## Whether this report is standing in for changes it could not carry.
func was_truncated() -> bool:
	for change in entries:
		if change.kind == TurnChange.Kind.DROPPED:
			return true
	return false


## The report in words, one line per entry, numbered to match the marks on the
## map. Anything showing this to a person uses these lines rather than
## re-deriving them, so the map and the words cannot drift apart.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for change in entries:
		if change.mark > 0:
			out.append("%d. %s" % [change.mark, change.describe()])
		else:
			out.append("   %s" % change.describe())
	return out


## Everything the world holds that a change could be measured against, taken
## before the turn runs.
##
## A plain dictionary of numbers and coordinates rather than references to the
## live objects: a reference to a herd would be a reference to a herd that has
## since moved, and the comparison would find nothing every time.
##
## Indexed positionally against `herds()`, `citizens()` and `nodes`, which is
## sound because nothing in this world is ever removed — `world-growth-tone` rule
## 1 — and the comparison below clamps to the shorter side anyway rather than
## assuming it.
static func snapshot(world: WorldMap) -> Dictionary:
	var herds := world.herds()
	var coords: Array[Vector2i] = []
	var populations := PackedFloat32Array()
	coords.resize(herds.size())
	populations.resize(herds.size())
	for i in range(herds.size()):
		coords[i] = herds[i].coord
		populations[i] = herds[i].population

	var stores := PackedFloat32Array()
	stores.resize(world.nodes.size())
	for i in range(world.nodes.size()):
		stores[i] = world.nodes[i].store

	# Whether the turn about to run is the one that changes season is knowable
	# from the clock alone, and the whole-map forage total is only summed when it
	# is. That is a branch on the calendar, not on whether anyone is reading the
	# report — the turn loop runs identically either way.
	var turning := Seasons.season_for_turn(world.turn + 1) != world.season()
	return {
		"season_turning": turning,
		"forage": world.total_forage() if turning else 0.0,
		"herd_coord": coords,
		"herd_population": populations,
		"store": stores,
	}


## Compare the world against a snapshot taken before the turn and report what
## crossed a bar.
static func since(world: WorldMap, before: Dictionary) -> TurnReport:
	var report := TurnReport.new(world.turn)
	var found: Array[TurnChange] = []

	if bool(before["season_turning"]):
		found.append(TurnChange.new(
			TurnChange.NOWHERE,
			TurnChange.Kind.SEASON_TURNED,
			world.total_forage() - float(before["forage"])
		))

	# The bar: a carrier that could not leave the tile it is standing on, on the
	# first turn it could not. A hold-up lasts up to a season and reporting it
	# every turn of that would be six lines saying the same thing; the onset is
	# the moment the road's throughput actually dropped.
	for citizen in world.citizens():
		if citizen.held_up == 1:
			# Summed from the agents rather than read off the per-tile cache.
			# The cache is documented as decision-only — repeated add and
			# subtract on floats drifts — and this number is both said out loud
			# ("3 mouths in the road") and used to rank entries when the report
			# has to drop some. Both of those are reporting.
			found.append(TurnChange.new(
				citizen.coord,
				TurnChange.Kind.ROUTE_BLOCKED,
				world.forage_demand_summed_at(citizen.coord)
			))

	# The bar: a granary's store crossed a multiple of `STORE_STEP`.
	var stores: PackedFloat32Array = before["store"]
	for i in range(mini(stores.size(), world.nodes.size())):
		var node := world.nodes[i]
		if node.kind != CityNode.Kind.GRANARY:
			continue
		if _mark_of(stores[i], STORE_STEP) == _mark_of(node.store, STORE_STEP):
			continue
		found.append(TurnChange.new(
			node.coord,
			TurnChange.Kind.GRANARY_STORE,
			_crossing(stores[i], node.store, STORE_STEP)
		))

	var herd_coords: Array = before["herd_coord"]
	var herd_populations: PackedFloat32Array = before["herd_population"]
	var herds := world.herds()
	for i in range(mini(herds.size(), herd_coords.size())):
		var herd := herds[i]
		var was: Vector2i = herd_coords[i]
		# The bar for movement: the herd changed the *kind of country* it is
		# standing in. A herd walks a tile a turn and fourteen of them stepping
		# about the map is the firehose this report exists not to be — but a herd
		# leaving the meadow for the wood is a thing that happened, and it is
		# legible on the map at a glance because the tile under the mark is a
		# different colour from the one beside it.
		if herd.coord != was and world.terrain_at(herd.coord) != world.terrain_at(was):
			found.append(TurnChange.new(
				herd.coord,
				TurnChange.Kind.HERD_CROSSED,
				herd.population
			))
		if _mark_of(herd_populations[i], HERD_STEP) != _mark_of(herd.population, HERD_STEP):
			found.append(TurnChange.new(
				herd.coord,
				TurnChange.Kind.HERD_POPULATION,
				_crossing(herd_populations[i], herd.population, HERD_STEP)
			))

	report._finalise(world, found)
	return report


## Which multiple of `step` a value sits in. The bar every threshold above is
## stated as: two values in the same band did not cross anything.
static func _mark_of(value: float, step: float) -> int:
	return floori(value / step)


## The mark a value crossed going from `was` to `now`, signed by which way it
## went: `+150.0` for a herd that passed a hundred and fifty head, `-30.0` for a
## granary that fell back below thirty grain.
##
## **A threshold report names the threshold, not the step that crossed it.** The
## first version of this reported the difference, and the difference is close to
## useless on a bar of this shape: a granary drifting past thirty grain reported
## "the granary took in 0 grain" — true, and a sentence with nothing in it —
## while five herds crossing five *different* population marks in one turn all
## reported "a herd grew by 3 head", five identical lines for five unrelated
## events. Both are the same mistake. What made the turn notable is the mark, so
## the mark is what gets said, and lines that were interchangeable become lines
## that name different things.
##
## The magnitude doubles as the drop-ranking key (`_outranks`), and this improves
## that too: on a crowded turn the herd that passed three hundred head outranks
## the one that passed fifty, where by delta they were indistinguishable.
static func _crossing(was: float, now: float, step: float) -> float:
	var mark := maxi(_mark_of(was, step), _mark_of(now, step))
	var level := float(mark) * step
	return level if now > was else -level


## Bound the candidates, put the survivors in report order, and number them.
func _finalise(world: WorldMap, found: Array[TurnChange]) -> void:
	for i in range(found.size()):
		found[i].seq = i
		found[i].order_index = world.grid.index_of(found[i].coord)

	var kept := found
	if found.size() > MAX_ENTRIES:
		# The drop rule, stated: sort by kind priority, then by size within a
		# kind, and keep as many as fit alongside one entry saying how many did
		# not. The last slot is spent on the count rather than on a sixth change,
		# because a report that quietly showed five of twenty would make a busy
		# turn indistinguishable from a calm one.
		found.sort_custom(_outranks)
		kept = found.slice(0, MAX_ENTRIES - 1)
		var dropped := TurnChange.new(
			TurnChange.NOWHERE,
			TurnChange.Kind.DROPPED,
			float(found.size() - kept.size())
		)
		dropped.seq = found.size()
		kept.append(dropped)

	kept.sort_custom(_precedes)
	var mark := 0
	for change in kept:
		if change.has_place():
			mark += 1
			change.mark = mark
	entries = kept


## Which of two changes is more worth keeping when they do not all fit.
##
## Kind first, in the priority order `TurnChange.Kind` is declared in, then the
## larger magnitude, then the order it was found. The last term is what makes
## this a total order rather than one that leaves ties to the sort's mood.
static func _outranks(a: TurnChange, b: TurnChange) -> bool:
	if a.kind != b.kind:
		return a.kind < b.kind
	var a_size := absf(a.magnitude)
	var b_size := absf(b.magnitude)
	if a_size != b_size:
		return a_size > b_size
	return a.seq < b.seq


## Report order: the whole map first, then the map itself in grid order, then
## what the report could not fit.
##
## Grid order — row-major over the offset grid, the same order `all_coords()`
## walks — rather than the order the comparison happened to find things in, so the
## list reads top-left to bottom-right down the map. `AgDR-001`: no ordering in
## this project may come from iteration over an unordered collection.
static func _precedes(a: TurnChange, b: TurnChange) -> bool:
	var a_rank := _place_rank(a)
	var b_rank := _place_rank(b)
	if a_rank != b_rank:
		return a_rank < b_rank
	if a.order_index != b.order_index:
		return a.order_index < b.order_index
	if a.kind != b.kind:
		return a.kind < b.kind
	return a.seq < b.seq


static func _place_rank(change: TurnChange) -> int:
	match change.kind:
		TurnChange.Kind.SEASON_TURNED:
			return 0
		TurnChange.Kind.DROPPED:
			return 2
	return 1
