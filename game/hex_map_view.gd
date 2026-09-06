class_name HexMapView
extends Node2D

## Draws a `WorldMap` as coloured hexes, scaled to fit whatever viewport it is
## given.
##
## This node owns pixels and nothing else. It reads terrain, forage and the
## season out of the world and picks colours for them; it never decides what any
## of those should be, and it holds no state that would survive being thrown away
## and rebuilt from the world. If a rule ever needs to live here, it belongs in
## `sim/` instead — see `.decisions/AgDR-001-headless-sim-core.md`.
##
## Layout is flat-top, odd-q offset, matching `sim/hex_grid.gd`'s extent. Centre
## spacing is `1.5 * radius` horizontally and `sqrt(3) * radius` vertically, with
## odd columns pushed down half a step — the standard flat-top packing, written
## out here rather than derived so the one place screen geometry exists is
## readable.
##
## Every tile's polygon is built once per rebuild and replayed on each frame's
## `_draw()`. A turn advance rebuilds the whole thing from the world rather than
## patching what changed: at this size that is cheap (see the redraw budget in
## `test/test_turn_advance.gd`), and it means a future system that alters terrain
## becomes visible without touching this file.

## Terrain value -> fill colour. Chosen for separation in both hue and
## lightness, so the map stays readable when hue alone is unreliable —
## a projector, a bad panel, or a colour-blind player.
const TERRAIN_COLORS := {
	WorldGen.Terrain.WATER: Color(0.13, 0.30, 0.52),
	WorldGen.Terrain.GRASS: Color(0.58, 0.76, 0.40),
	WorldGen.Terrain.FOREST: Color(0.13, 0.45, 0.20),
	WorldGen.Terrain.HILL: Color(0.68, 0.50, 0.28),
	WorldGen.Terrain.MOUNTAIN: Color(0.72, 0.72, 0.75),
}

## Names used by the legend, in the order the legend lists them.
const TERRAIN_NAMES := {
	WorldGen.Terrain.WATER: "water",
	WorldGen.Terrain.GRASS: "grass",
	WorldGen.Terrain.FOREST: "forest",
	WorldGen.Terrain.HILL: "hills",
	WorldGen.Terrain.MOUNTAIN: "mountains",
}

## Accent per season, used for the indicator above the legend. Warm through the
## growing half of the year, cold at the end of it, so the header reads as the
## season before the word does.
const SEASON_COLORS := {
	Seasons.Season.SPRING: Color(0.55, 0.85, 0.45),
	Seasons.Season.SUMMER: Color(0.95, 0.80, 0.30),
	Seasons.Season.AUTUMN: Color(0.90, 0.52, 0.24),
	Seasons.Season.WINTER: Color(0.72, 0.84, 0.95),
}

## Herd markers: a warm dot on cool ground, sized by population so a growing
## herd is visible as growth rather than as a number that has to be read. Drawn
## on top of the tiles rather than tinted into them — a herd is a thing standing
## somewhere, not a property of the place.
const _HERD_FILL := Color(0.96, 0.36, 0.22)
const _HERD_EDGE := Color(0.15, 0.06, 0.03, 0.85)

## Marker radius as a fraction of the hex radius, at the smallest and largest
## populations the scale covers. Area, not radius, tracks population: a herd
## four times the size looks four times as big rather than sixteen.
const _HERD_MIN_SCALE := 0.22
const _HERD_MAX_SCALE := 0.66

## Population the marker reaches full size at. Everything above it draws the
## same, which is the price of a fixed scale — chosen above the largest herd
## observed over a thousand turns (see `test/test_herds.gd`) so the cap is a
## backstop rather than a thing the eye meets.
const _HERD_FULL_AT := 400.0

## The city: roads, structures, and the people on them.
##
## Drawn in warm, built colours against a landscape that is entirely greens,
## blues and greys, so the eye separates "somebody put that there" from "that
## grew there" before it reads a single shape. Structures are squares because
## every natural thing on this map is round or hexagonal.
##
## The road is dark rather than the sandy brown a track wants to be, and the
## granary is a deep red rather than an ochre, for a measured reason: the hill
## terrain is already brown and the mountains are already pale, so every warm
## mid-tone is taken. `test_hex_map_view.gd` holds the city palette to the same
## separation the terrain palette has to meet, and those two were the colours
## that failed it.
const _ROAD_COLOR := Color(0.38, 0.24, 0.28, 0.92)
const _FARM_FILL := Color(0.93, 0.79, 0.32)
const _GRANARY_FILL := Color(0.62, 0.20, 0.16)
const _NODE_EDGE := Color(0.20, 0.12, 0.04, 0.95)

## The unworked part of a farm's square: bare earth, dark enough that the lit
## part reads as a level in a container rather than as two colours side by side.
## A farm in midwinter is nearly all this; a farm in spring is nearly none of it.
const _FARM_FALLOW := Color(0.26, 0.17, 0.14)

## Citizens: a small pale figure, with the grain they are carrying shown as a
## warm core. Loaded and empty look different on purpose — the road then reads as
## traffic with a direction rather than as dots sliding back and forth.
const _CITIZEN_FILL := Color(0.96, 0.94, 0.88)
const _CITIZEN_LOADED := Color(1.00, 0.97, 0.62)
const _CITIZEN_EDGE := Color(0.16, 0.12, 0.08, 0.95)

## The ring drawn around somebody who cannot get past whatever is standing on
## their tile.
##
## A ring rather than a different fill, because the fill is already saying
## something — whether the sack is full — and a person can be laden *and* stuck.
## Two channels for two facts. Drawn outside the figure so it survives the map
## being squeezed small, where the figure itself is only a few pixels across.
const _CITIZEN_HELD := Color(0.99, 0.42, 0.16)
const _HELD_RING_SCALE := 2.0

## Grain arriving at a structure, and grain leaving it. Green in, red out, drawn
## as two stubs growing out of the top and bottom of the node so that a granary
## with something happening to it looks busy at a glance.
const _FLOW_IN := Color(0.44, 0.86, 0.44)
const _FLOW_OUT := Color(0.94, 0.40, 0.34)

## The flow a full-height stub represents. One carrier's sack, so the bar is
## legible against the thing that actually moves grain rather than against an
## abstract maximum.
const _FLOW_FULL_AT := Citizen.CARRY_CAPACITY

## Rising, falling, steady. Warm for growth and cool-red for decline, with a
## neutral grey bar for a quantity that is not moving — a steady number needs a
## mark of its own or "no arrow" and "no data" look the same.
const _TREND_RISING := Color(0.55, 0.88, 0.50)
const _TREND_FALLING := Color(0.95, 0.55, 0.38)
const _TREND_STEADY := Color(0.62, 0.64, 0.68)

## Structure size and citizen size, as fractions of the hex radius. The node is
## a chunky thing standing on a tile; the citizen is a person beside it.
const _NODE_SCALE := 0.52
const _CITIZEN_SCALE := 0.20

## Road width as a fraction of the hex radius, floored in pixels so the road does
## not vanish when the whole map is squeezed into a small window.
const _ROAD_WIDTH_SCALE := 0.18
const _ROAD_MIN_WIDTH := 2.0

## The attention marks: a ring around every tile this turn's report named, with
## the entry's number beside it.
##
## Cool and unnaturally bright, on purpose. Every colour in this scene so far
## belongs to something that is *in* the world — ground that grew, or something
## somebody built. This one belongs to the instrument rather than to the place,
## and it should look like it: a reading laid over the map, not a new kind of
## terrain. It is also the only pure cyan on screen, which is what lets it be
## found at a glance on a map that is otherwise green, blue, brown and grey.
##
## The marks carry no state. They are read out of `world.report` on every
## rebuild and vanish the moment the next turn produces a report without them —
## the whole point being that a mark answers "what changed *this* turn", and a
## mark that outlived its turn would be answering a question nobody asked.
const _CHANGE_COLOR := Color(0.55, 0.92, 1.00)
const _CHANGE_SHADOW := Color(0.04, 0.10, 0.14, 0.80)

## Ring radius as a fraction of the hex radius, and its thickness. Just inside
## the hex, so the ring reads as "this tile" rather than as a blob covering
## whatever is standing on it.
const _CHANGE_RING_SCALE := 0.84
const _CHANGE_RING_WIDTH := 0.13

## Colour a tile fades toward as its forage falls — a pale, bleached version of
## itself rather than a darker one, because a winter map should read as drained
## rather than as a map at night.
const _DORMANT := Color(0.82, 0.84, 0.87)

## How far toward `_DORMANT` a tile with no forage at all is allowed to go. Short
## of 1.0 on purpose: at 1.0 every barren tile is the same colour and the terrain
## underneath stops being readable, which trades one thing the player needs to
## see for another.
const _DORMANCY_MAX := 0.70

## The map overlays, in the order `O` cycles through them.
##
## An overlay is *data*, not code: the name of a `WorldMap` method returning one
## float per tile in grid order, the arguments to call it with, the range to
## normalise against, and the two ends of a colour ramp. Drawing one is a single
## function that knows none of those things specifically.
##
## That shape is the point of the entry rather than an accident of it. Vitality
## (#38) is `{"row": "vitality_data", "args": [Land.Use.GRAZE], ...}` — an
## element in this array and nothing else. `test_hex_map_view.gd` proves the
## claim by building exactly that entry and drawing it, so this cannot quietly
## become a system with one hard-coded scalar in it.
##
## Reading a whole row in one call, rather than a value per tile, is why this
## stays inside the redraw budget: `forage_data()` is one array copy for the
## entire map.
const OVERLAY_FORAGE := 0

const OVERLAYS: Array[Dictionary] = [
	{
		"name": "forage",
		"caption": "forage — feed for herds",
		"row": "forage_data",
		"args": [],
		"min": Seasons.MIN_FORAGE,
		"max": Seasons.MAX_FORAGE,
		"low": Color(0.62, 0.16, 0.18),
		"high": Color(0.30, 0.80, 0.36),
	},
]

## Left edge of the season indicator and the legend below it, measured in from
## the right of the viewport. Shared so the two line up, and wide enough that
## the longest season caption is not clipped by the edge of the window.
##
## Public because it is also the width every overlay caption has to fit inside,
## and `test_hex_map_view.gd` measures them against it. Nothing wraps the text:
## a caption wider than this runs off the side of the window, which is how the
## forage overlay first shipped reading "what the land fee".
const PANEL_INSET := 206.0

const _EDGE_COLOR := Color(0.0, 0.0, 0.0, 0.18)
const _BACKGROUND := Color(0.07, 0.08, 0.10)
const _MARGIN := 12.0

## Microseconds the last `_draw()` took. Read by the redraw-budget test; the
## alternative is timing a whole frame, which measures the frame rate rather
## than the cost of drawing the map.
var last_draw_usec := 0

## Which entry of `OVERLAYS` is painted onto the tiles, or -1 for none.
##
## A view *setting*, not world history: throwing this view away and building
## another gives an unoverlaid map, which is the correct behaviour for something
## the player toggled and not a fact about the world that got lost.
var overlay_index := -1

var _world: WorldMap
var _radius := 0.0
var _origin := Vector2.ZERO
var _polygons: Array[PackedVector2Array] = []
var _outlines: Array[PackedVector2Array] = []
var _fills: PackedColorArray = PackedColorArray()


## Point this view at a world and size it to the space available.
func show_world(world: WorldMap, viewport_size: Vector2) -> void:
	_world = world
	_fit(viewport_size)
	refresh()


## Rebuild the display from current world state. Called on every turn advance.
func refresh() -> void:
	_rebuild()
	queue_redraw()


## Re-fit to a new viewport size and redraw.
func resize_to(viewport_size: Vector2) -> void:
	if _world == null:
		return
	_fit(viewport_size)
	refresh()


## How many tile polygons the last rebuild produced. Exists so a test can check
## the whole map is being drawn rather than a fast-looking subset of it.
func tile_polygon_count() -> int:
	return _polygons.size()


## The colour the last rebuild painted on one tile, or transparent for a tile
## off the map.
##
## Exists so a test can ask what the map is actually showing rather than
## recompute what it ought to show. An overlay test that calls `overlay_fill()`
## itself passes whether or not the tiles ever receive the result; this one goes
## through the same array `_draw()` replays.
func tile_fill(coord: Vector2i) -> Color:
	if _world == null:
		return Color(0, 0, 0, 0)
	var i := _world.grid.index_of(coord)
	if i < 0 or i >= _fills.size():
		return Color(0, 0, 0, 0)
	return _fills[i]


## The radius in pixels the map was last fitted to.
func hex_radius() -> float:
	return _radius


## Centre of a tile in pixels, for the current fit. Public so a later ticket can
## put something on a tile without re-deriving the layout.
func center_of(coord: Vector2i) -> Vector2:
	var off := HexGrid.to_offset(coord)
	return _center_of_offset(off.x, off.y)


func _center_of_offset(col: int, row: int) -> Vector2:
	var x := _origin.x + _radius * (1.0 + 1.5 * float(col))
	var y := _origin.y + sqrt(3.0) * _radius * (float(row) + 0.5 * float(col & 1) + 0.5)
	return Vector2(x, y)


## Largest radius that fits the whole map in `viewport_size`, and the offset that
## centres it. Shrinking the map to fit is preferred over cropping it: the whole
## world being visible at once is the thing this scene exists to show.
func _fit(viewport_size: Vector2) -> void:
	var w := float(_world.grid.width)
	var h := float(_world.grid.height)
	var usable := viewport_size - Vector2(_MARGIN, _MARGIN) * 2.0
	var by_width := usable.x / (1.5 * w + 0.5)
	var by_height := usable.y / (sqrt(3.0) * (h + 0.5))
	_radius = maxf(1.0, minf(by_width, by_height))

	var drawn := Vector2(
		_radius * (1.5 * w + 0.5),
		sqrt(3.0) * _radius * (h + 0.5)
	)
	_origin = ((viewport_size - drawn) * 0.5).floor()


func _rebuild() -> void:
	var count := _world.grid.tile_count()
	_polygons.resize(count)
	_outlines.resize(count)
	_fills.resize(count)

	var entry := active_overlay()
	var scalars := PackedFloat32Array() if entry.is_empty() else overlay_row(_world, entry)

	var i := 0
	for row in range(_world.grid.height):
		for col in range(_world.grid.width):
			var centre := _center_of_offset(col, row)
			var corners := _corners(centre, _radius)
			_polygons[i] = corners
			var loop := corners.duplicate()
			loop.append(corners[0])
			_outlines[i] = loop
			var coord := HexGrid.from_offset(col, row)
			var terrain := _world.terrain_at(coord)
			# The sea keeps its own colour under every overlay. One rule, shared
			# by all of them rather than written per entry: an overlay is a
			# statement about land, and a red ocean would cost the map its
			# outline — which is the shape the player navigates by — to say
			# something true only of grazing.
			if scalars.is_empty() or terrain == WorldGen.Terrain.WATER:
				_fills[i] = tile_color(terrain, _world.forage_at(coord))
			else:
				_fills[i] = overlay_fill(entry, scalars[_world.grid.index_of(coord)])
			i += 1


## The overlay currently painted, or an empty dictionary when none is.
func active_overlay() -> Dictionary:
	if overlay_index < 0 or overlay_index >= OVERLAYS.size():
		return {}
	return OVERLAYS[overlay_index]


## Move to the next overlay, wrapping through "none". Bound to a key by `Main`.
func cycle_overlay() -> void:
	overlay_index += 1
	if overlay_index >= OVERLAYS.size():
		overlay_index = -1
	refresh()


## Turn on the overlay with this name, or turn overlays off for `""`. Returns
## false for a name that is not in the registry, so a caller passing a typo
## finds out rather than silently getting an unoverlaid map.
func set_overlay_named(overlay_name: String) -> bool:
	if overlay_name == "":
		overlay_index = -1
		refresh()
		return true
	for i in range(OVERLAYS.size()):
		if String(OVERLAYS[i]["name"]) == overlay_name:
			overlay_index = i
			refresh()
			return true
	return false


## The per-tile scalars one overlay entry reads, in grid order.
##
## The world is asked by method name rather than through a match on the entry,
## which is what makes a new overlay an array element instead of a code change.
## Every source is already a public `WorldMap` query returning a row in
## `grid.index_of()` order — the storage layout `AgDR-006` fixed — so there is no
## per-overlay unpacking to write either.
static func overlay_row(world: WorldMap, entry: Dictionary) -> PackedFloat32Array:
	return world.callv(String(entry["row"]), entry["args"])


## Where one scalar lands on one overlay's ramp.
##
## Normalised against the entry's own declared range rather than against the
## values actually present, so a map that happens to be uniformly poor reads as
## poor instead of being stretched to look varied. That is the same argument
## `tile_color()` makes for measuring forage against the global maximum.
static func overlay_fill(entry: Dictionary, value: float) -> Color:
	var low := float(entry["min"])
	var high := float(entry["max"])
	var share := clampf((value - low) / maxf(0.0001, high - low), 0.0, 1.0)
	var cold: Color = entry["low"]
	var warm: Color = entry["high"]
	return cold.lerp(warm, share)


## The fill for one tile: its terrain colour, bleached toward `_DORMANT` in
## proportion to how far its forage sits below the best any tile can manage.
##
## Measured against the global maximum rather than against each terrain's own
## annual peak. Relative-to-itself would make every terrain swing the full range
## and read more dramatically, at the price of a mountain in summer looking as
## fed as a meadow in spring — which is the one thing this colour is supposed to
## communicate.
##
## Water is left alone. It has no forage in any season, so scaling it would
## permanently bleach the sea to say something true only about grazing.
static func tile_color(terrain: int, forage: float) -> Color:
	var base: Color = TERRAIN_COLORS.get(terrain, Color.MAGENTA)
	if terrain == WorldGen.Terrain.WATER:
		return base
	var fed := clampf(forage / Seasons.MAX_FORAGE, 0.0, 1.0)
	return base.lerp(_DORMANT, (1.0 - fed) * _DORMANCY_MAX)


## The six corners of a flat-top hex, starting at the right-hand point and going
## clockwise in screen space.
static func _corners(centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(6)
	for i in range(6):
		var angle := deg_to_rad(60.0 * float(i))
		out[i] = centre + Vector2(cos(angle), sin(angle)) * radius
	return out


func _draw() -> void:
	if _world == null:
		return
	var started := Time.get_ticks_usec()

	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), _BACKGROUND)
	for i in range(_polygons.size()):
		draw_colored_polygon(_polygons[i], _fills[i])
		draw_polyline(_outlines[i], _EDGE_COLOR, 1.0)
	# Roads under everything the roads connect, herds under the people who have
	# to walk around them, and the structures on top: the draw order is the
	# reading order.
	_draw_routes()
	_draw_herds()
	_draw_nodes()
	_draw_citizens()
	# Last, and over everything: the marks are a reading of the map, so nothing
	# on the map is allowed to sit on top of one.
	_draw_changes()
	_draw_season()
	var below := _draw_legend()
	below = _draw_overlay_key(below)
	_draw_flows(below)

	last_draw_usec = Time.get_ticks_usec() - started


## One dot per herd, at the centre of the tile it is standing on.
##
## Read straight off the world every frame rather than cached with the polygons:
## herds move every turn while the tiles do not, and a cache of positions is a
## cache that can be wrong about the only thing on screen that is going
## anywhere.
func _draw_herds() -> void:
	for herd in _world.herds():
		var centre := center_of(herd.coord)
		var radius := _radius * herd_marker_scale(herd.population)
		draw_circle(centre, radius, _HERD_FILL)
		draw_arc(centre, radius, 0.0, TAU, 18, _HERD_EDGE, maxf(1.0, radius * 0.14))


## The roads, as a line through the centre of every tile they run along.
##
## Drawn tile-centre to tile-centre rather than as a band across each hex,
## because the thing that has to be legible is where the road *goes* — the tiles
## it occupies are already legible from the things standing on them.
func _draw_routes() -> void:
	var width := maxf(_ROAD_MIN_WIDTH, _radius * _ROAD_WIDTH_SCALE)
	for route in _world.routes:
		var points := PackedVector2Array()
		for coord in route.path:
			points.append(center_of(coord))
		draw_polyline(points, _ROAD_COLOR, width)


## The structures, as squares on the tiles they were placed on — each one showing
## what is happening to it as well as where it is.
##
## A farm's square is filled from the bottom by what its field grows *this turn*,
## against what the same field would grow at full forage. The square on a spring
## tile is nearly solid and the square on a winter tile is nearly bare earth,
## which is the difference the ticket asks for and the reason it is drawn as a
## level rather than as a tint: a level has a visible empty part, and the empty
## part is the point.
##
## A granary's square grows a green stub upward for grain arriving and a red one
## downward for grain leaving. Both are drawn whenever there is a granary, so an
## outflow of zero is a stub of no height next to a visible inflow rather than a
## thing the display forgot to mention.
func _draw_nodes() -> void:
	var half := _radius * _NODE_SCALE * 0.5
	for node in _world.nodes:
		var centre := center_of(node.coord)
		var box := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
		if node.kind == CityNode.Kind.FARM:
			draw_rect(box, _FARM_FALLOW)
			var share := farm_fill_share(node, _world)
			if share > 0.0:
				draw_rect(Rect2(
					box.position + Vector2(0.0, box.size.y * (1.0 - share)),
					Vector2(box.size.x, box.size.y * share)
				), _FARM_FILL)
		else:
			draw_rect(box, _GRANARY_FILL)
			_draw_flow_stubs(box, node.took_in, node.gave_out)
		draw_rect(box, _NODE_EDGE, false, maxf(1.0, half * 0.22))


## How much of a farm's square is lit: this turn's yield against what the same
## field would grow if the season were as good as it gets.
##
## Measured against the crop's own ceiling rather than against the best yield on
## this map, for the reason `tile_color()` gives: a normalisation that follows
## what is present makes a lean year look like an ordinary one.
static func farm_fill_share(node: CityNode, world: WorldMap) -> float:
	return clampf(node.yield_rate(world) / CityNode.FARM_YIELD_PER_TURN, 0.0, 1.0)


## The two stubs beside a store: what came in this turn, and what went out.
func _draw_flow_stubs(box: Rect2, took_in: float, gave_out: float) -> void:
	var width := maxf(2.0, box.size.x * 0.30)
	var full := box.size.y * 1.1
	var x := box.get_center().x - width * 0.5
	var up := full * clampf(took_in / _FLOW_FULL_AT, 0.0, 1.0)
	var down := full * clampf(gave_out / _FLOW_FULL_AT, 0.0, 1.0)
	# A floor of one pixel on each, so "nothing moved" is a mark rather than an
	# absence — an omitted bar reads as a display that has no opinion.
	draw_rect(Rect2(Vector2(x, box.position.y - maxf(1.0, up)), Vector2(width, maxf(1.0, up))),
		_FLOW_IN)
	draw_rect(Rect2(Vector2(x, box.end.y), Vector2(width, maxf(1.0, down))), _FLOW_OUT)


## The people on the road. Small — a person is not a herd — and filled according
## to whether they are carrying anything, so a glance at the road says which way
## the grain is going.
##
## Anyone who could not move gets a ring around them. That hold-up is the only
## place in the whole simulation where the wild world touches the built one
## (`Citizen.MAX_HELD_UP`), and until now a stalled dot and a walking dot were
## the same picture.
func _draw_citizens() -> void:
	var radius := maxf(2.0, _radius * _CITIZEN_SCALE)
	for citizen in _world.citizens():
		var centre := center_of(citizen.coord)
		var fill := _CITIZEN_LOADED if citizen.carrying > 0.0 else _CITIZEN_FILL
		if citizen.is_held_up():
			draw_arc(centre, radius * _HELD_RING_SCALE, 0.0, TAU, 20, _CITIZEN_HELD,
				maxf(1.5, radius * 0.45))
		draw_circle(centre, radius, fill)
		draw_arc(centre, radius, 0.0, TAU, 14, _CITIZEN_EDGE, maxf(1.0, radius * 0.30))


## A ring and a number on every tile this turn's report named.
##
## This is the half of the instrument that points. The status area says what
## happened; the number here says where, and the two carry the same number
## because `TurnReport` assigned it — the view is not counting anything of its
## own, so the list and the map cannot get out of step.
##
## Changes with no place on the map — the season turning, the count of what did
## not fit — are skipped rather than drawn somewhere arbitrary. They have no
## `mark` for the same reason.
##
## **One ring per tile, however many changes landed on it.** Two things can
## happen in one place in one turn — a herd walks into the wood *and* passes a
## hundred head, which is one herd having a big turn — and drawing a ring and a
## number per change put the second number exactly on top of the first, leaving a
## line of the report pointing at a mark that was not on screen. So the marks on
## a tile are gathered and read out together, "3,4", against a single ring. The
## entries arrive in grid order, so everything sharing a tile arrives together
## and one pass is enough.
func _draw_changes() -> void:
	var font := ThemeDB.fallback_font
	var radius := _radius * _CHANGE_RING_SCALE
	var width := maxf(1.5, _radius * _CHANGE_RING_WIDTH)
	for mark in change_marks(_world.report):
		_draw_change_mark(font, mark[0], mark[1], radius, width)


## The marks to draw: one `[coord, label]` per tile, in report order, with every
## change that landed on a tile read out together — `"4"` for a tile with one,
## `"3,4"` for a tile with two.
##
## Static and public so a test can check the grouping without a viewport.
##
## Merges neighbours in the list rather than gathering by coordinate, which is
## sound because `TurnReport` hands its entries over in grid order and so
## everything sharing a tile arrives together. It is also the reason there is no
## dictionary here: `AgDR-001` does not allow an order that came out of an
## unordered collection, and this way the order on the map is the report's.
static func change_marks(report: TurnReport) -> Array:
	var out: Array = []
	if report == null:
		return out
	for change in report.entries:
		if not change.has_place():
			continue
		if not out.is_empty() and out[-1][0] == change.coord:
			out[-1][1] += "," + str(change.mark)
			continue
		out.append([change.coord, str(change.mark)])
	return out


## One tile's ring, labelled with every mark that landed on it.
func _draw_change_mark(
	font: Font, coord: Vector2i, label: String, radius: float, width: float
) -> void:
	var centre := center_of(coord)
	# A dark ring under the bright one, so the mark survives landing on pale
	# mountains as well as on dark water.
	draw_arc(centre, radius, 0.0, TAU, 24, _CHANGE_SHADOW, width * 1.9)
	draw_arc(centre, radius, 0.0, TAU, 24, _CHANGE_COLOR, width)
	if font == null:
		return
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font_size)
	# Above the tile centre rather than on it: the thing that changed is
	# usually standing in the middle of the hex.
	var at := centre + Vector2(-size.x * 0.5, -radius - 3.0)
	draw_string(font, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		ThemeDB.fallback_font_size, _CHANGE_SHADOW)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		ThemeDB.fallback_font_size, _CHANGE_COLOR)


## Marker radius as a fraction of the hex radius, for a herd of this size.
## Static and public so a test can check the scale without a viewport.
static func herd_marker_scale(population: float) -> float:
	var share := clampf(population / _HERD_FULL_AT, 0.0, 1.0)
	# Square root, so the marker's *area* is proportional to the population.
	return lerpf(_HERD_MIN_SCALE, _HERD_MAX_SCALE, sqrt(share))


## The year, drawn as four bars with the current season lit. A name alone tells
## you where you are; the bars tell you where you are *going*, which is the
## difference between a caption and a calendar.
func _draw_season() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var current := _world.season()
	var left := get_viewport_rect().size.x - PANEL_INSET
	var pos := Vector2(left, 16.0)
	var bar := Vector2(38, 10)
	for season in Seasons.SEASON_ORDER:
		var color: Color = SEASON_COLORS[season]
		draw_rect(Rect2(pos, bar), color if season == current else color * 0.30)
		pos.x += bar.x + 4.0
	draw_string(
		font,
		Vector2(left, 16.0 + bar.y + 18.0),
		"%s — year %d" % [Seasons.season_name(current), _world.year()],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		ThemeDB.fallback_font_size,
		SEASON_COLORS[current]
	)


## A swatch and a name per terrain, because a colour key is the difference
## between "readable at a glance" and "guessable after a minute". Returns the y
## the next panel block may start at.
func _draw_legend() -> float:
	var font := ThemeDB.fallback_font
	if font == null:
		return 62.0
	var font_size := ThemeDB.fallback_font_size
	var swatch := Vector2(16, 16)
	var pos := Vector2(get_viewport_rect().size.x - PANEL_INSET, 62.0)
	for terrain in TERRAIN_NAMES:
		draw_rect(Rect2(pos, swatch), TERRAIN_COLORS[terrain])
		draw_rect(Rect2(pos, swatch), _EDGE_COLOR, false, 1.0)
		draw_string(
			font,
			pos + Vector2(swatch.x + 8.0, swatch.y - 3.0),
			TERRAIN_NAMES[terrain],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.92, 0.92, 0.92)
		)
		pos.y += swatch.y + 6.0

	# The herds get a line of their own, with the dot drawn at the size it is
	# used on the map so "bigger means more" is stated rather than inferred.
	draw_circle(pos + swatch * 0.5, swatch.x * 0.32, _HERD_FILL)
	_legend_caption(font, font_size, pos, "herds (size=count)")
	pos.y += swatch.y + 6.0

	# And the city, in the same order it is drawn on the map. The farm's swatch
	# is drawn half-lit, because half-lit is what it looks like on the map for
	# most of the year and a solid swatch would teach the wrong thing.
	var chip := swatch * 0.52
	draw_rect(Rect2(pos + swatch * 0.24, chip), _FARM_FALLOW)
	draw_rect(Rect2(pos + swatch * 0.24 + Vector2(0.0, chip.y * 0.45),
		Vector2(chip.x, chip.y * 0.55)), _FARM_FILL)
	_legend_caption(font, font_size, pos, "farm (fill=yield)")
	pos.y += swatch.y + 6.0
	draw_rect(Rect2(pos + swatch * 0.24, chip), _GRANARY_FILL)
	draw_rect(Rect2(pos + swatch * 0.24 + Vector2(chip.x * 0.35, -4.0),
		Vector2(chip.x * 0.3, 4.0)), _FLOW_IN)
	draw_rect(Rect2(pos + swatch * 0.24 + Vector2(chip.x * 0.35, chip.y),
		Vector2(chip.x * 0.3, 2.0)), _FLOW_OUT)
	_legend_caption(font, font_size, pos, "granary (in/out)")
	pos.y += swatch.y + 6.0
	draw_circle(pos + swatch * 0.5, swatch.x * 0.22, _CITIZEN_LOADED)
	_legend_caption(font, font_size, pos, "citizens (lit=laden)")
	pos.y += swatch.y + 6.0
	draw_arc(pos + swatch * 0.5, swatch.x * 0.40, 0.0, TAU, 20, _CITIZEN_HELD, 2.0)
	draw_circle(pos + swatch * 0.5, swatch.x * 0.22, _CITIZEN_FILL)
	_legend_caption(font, font_size, pos, "held up by traffic")
	pos.y += swatch.y + 6.0

	# And the marks, which are not a thing in the world at all — they are this
	# turn's report, drawn where it happened.
	draw_arc(pos + swatch * 0.5, swatch.x * 0.42, 0.0, TAU, 18, _CHANGE_COLOR, 2.0)
	_legend_caption(font, font_size, pos, "changed this turn")
	return pos.y + swatch.y + 10.0


func _legend_caption(font: Font, font_size: int, pos: Vector2, text: String) -> void:
	draw_string(
		font,
		pos + Vector2(24.0, 13.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.92, 0.92, 0.92)
	)


## The ramp the active overlay is painting with, and what it means. Nothing at
## all when no overlay is on, plus a one-line reminder that the key exists.
func _draw_overlay_key(top: float) -> float:
	var font := ThemeDB.fallback_font
	if font == null:
		return top
	var font_size := ThemeDB.fallback_font_size
	var left := get_viewport_rect().size.x - PANEL_INSET
	var entry := active_overlay()
	if entry.is_empty():
		draw_string(font, Vector2(left, top + 11.0), "[O] overlay: off",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.62, 0.64, 0.68))
		return top + 24.0

	# The ramp itself, in the same colours the tiles are getting, so the key
	# cannot describe a gradient the map is not using.
	var bar := Vector2(160.0, 9.0)
	var steps := 16
	for i in range(steps):
		var share := float(i) / float(steps - 1)
		draw_rect(
			Rect2(Vector2(left + bar.x * float(i) / float(steps), top),
				Vector2(ceilf(bar.x / float(steps)), bar.y)),
			overlay_fill(entry, lerpf(float(entry["min"]), float(entry["max"]), share))
		)
	draw_string(font, Vector2(left, top + bar.y + 14.0), String(entry["caption"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.92, 0.92, 0.92))
	return top + bar.y + 28.0


## Everything on this panel that is a rate or a direction rather than a level.
##
## Kept as one dictionary, built entirely from the world, because it is also what
## `test_hex_map_view.gd` compares between two views of the same world. If this
## ever reads a field of this node, that test fails — which is the point of it.
func readout() -> Dictionary:
	if _world == null:
		return {}
	var ledger := _world.chronicle
	return {
		"people": _world.citizen_count(),
		"held_up": _world.held_up_count(),
		"granary_store": _world.total_granary_store(),
		"granary_store_trend": ledger.trend(Chronicle.GRANARY_STORE),
		"granary_in": ledger.rate(Chronicle.GRANARY_IN),
		"granary_out": ledger.rate(Chronicle.GRANARY_OUT),
		"farm_yield": _world.farm_yield_rate(),
		"farm_yield_trend": ledger.trend(Chronicle.FARM_YIELD),
		"animals": _world.total_herd_population(),
		"animals_trend": ledger.trend(Chronicle.HERD_POPULATION),
		"turns_recorded": ledger.span(Chronicle.GRANARY_IN),
	}


## The flow band: how many people, how the granary is doing, what the land is
## giving, and which way each of those is going.
##
## Four lines and no more. `world-growth-tone` rule 6 applies to readouts as
## much as to systems — two or three well-chosen signals beat a complete
## instrument, and a panel long enough to scan is a panel nobody scans.
func _draw_flows(top: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := ThemeDB.fallback_font_size
	var data := readout()
	if data.is_empty():
		return
	var left := get_viewport_rect().size.x - PANEL_INSET
	var pos := Vector2(left, top)

	draw_string(font, pos + Vector2(0.0, 11.0),
		"flows — last %d turns" % int(data["turns_recorded"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.72, 0.74, 0.78))
	pos.y += 20.0

	# The people count first, because "how many are working" is the question that
	# has no other answer anywhere on screen.
	_flow_line(font, font_size, pos, "people", "%d  (%d held)" % [
		int(data["people"]), int(data["held_up"])], 0)
	pos.y += 18.0
	_flow_line(font, font_size, pos, "granary", "%d" % roundi(data["granary_store"]),
		int(data["granary_store_trend"]))
	pos.y += 18.0
	# In and out on one line and always both, so a zero outflow is stated rather
	# than left to be inferred from a missing number.
	_flow_line(font, font_size, pos, "  in / out", "%.1f / %.1f" % [
		data["granary_in"], data["granary_out"]], 0)
	pos.y += 18.0
	_flow_line(font, font_size, pos, "fields", "%.2f /turn" % data["farm_yield"],
		int(data["farm_yield_trend"]))
	pos.y += 18.0
	_flow_line(font, font_size, pos, "animals", "%d" % roundi(data["animals"]),
		int(data["animals_trend"]))


func _flow_line(font: Font, font_size: int, pos: Vector2, label: String, value: String,
		trend: int) -> void:
	draw_string(font, pos + Vector2(0.0, 11.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.70, 0.72, 0.76))
	draw_string(font, pos + Vector2(74.0, 11.0), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.94, 0.94, 0.94))
	_draw_trend(pos + Vector2(PANEL_INSET - 26.0, 3.0), trend)


## Rising, falling or steady, as a shape rather than as a glyph.
##
## A triangle drawn from points rather than an arrow character: the fallback font
## is whatever the engine ships and a missing glyph renders as a box, which would
## put the one mark the player is meant to read at a glance at the mercy of a
## font table. Colour carries the same information a second time, for the same
## reason the terrain palette separates in lightness as well as hue.
func _draw_trend(pos: Vector2, trend: int) -> void:
	var w := 10.0
	var h := 9.0
	if trend == 0:
		draw_rect(Rect2(pos + Vector2(0.0, h * 0.5 - 1.5), Vector2(w, 3.0)), _TREND_STEADY)
		return
	var points := PackedVector2Array()
	if trend > 0:
		points.append(pos + Vector2(w * 0.5, 0.0))
		points.append(pos + Vector2(w, h))
		points.append(pos + Vector2(0.0, h))
	else:
		points.append(pos)
		points.append(pos + Vector2(w, 0.0))
		points.append(pos + Vector2(w * 0.5, h))
	draw_colored_polygon(points, _TREND_RISING if trend > 0 else _TREND_FALLING)
