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

## The gathering camp, working and quiet. A violet, because the two warm slots
## the city had were already spent on the farm and the granary and every
## remaining warm mid-tone collides with the hills — the same corner the road and
## the granary were painted into, resolved the same way.
##
## Unlike the other two structures this one is drawn at a brightness rather than
## at a colour, and that asymmetry is the point of the kind. A farm's year is
## legible from the tile it stands on, which the map already washes with the
## season; a camp's year is legible from nowhere on the map except the camp
## itself, because what feeds it is a herd that may be four tiles away and out of
## the frame the eye happens to be looking at.
const _GATHERING_FILL := Color(0.80, 0.35, 0.85)
const _GATHERING_QUIET := Color(0.26, 0.16, 0.31)

## The halo a working camp throws, as a fraction of the hex radius. It reaches
## past the node's own square on purpose: what a camp is doing is *reaching into
## the tiles around it*, and a mark confined to its own hex would say only that
## something there changed colour.
##
## Nothing about the halo's size claims to be `CityNode.GATHERING_RADIUS` drawn
## to scale. It is an indicator, and a nineteen-hex disc outlined accurately
## would cover the herds that are the reason it is lit.
const _GATHERING_HALO_SCALE := 0.92

## Citizens: a small pale figure, with the grain they are carrying shown as a
## warm core. Loaded and empty look different on purpose — the road then reads as
## traffic with a direction rather than as dots sliding back and forth.
const _CITIZEN_FILL := Color(0.96, 0.94, 0.88)
const _CITIZEN_LOADED := Color(1.00, 0.97, 0.62)
const _CITIZEN_EDGE := Color(0.16, 0.12, 0.08, 0.95)

## Structure size and citizen size, as fractions of the hex radius. The node is
## a chunky thing standing on a tile; the citizen is a person beside it.
const _NODE_SCALE := 0.52
const _CITIZEN_SCALE := 0.20

## Road width as a fraction of the hex radius, floored in pixels so the road does
## not vanish when the whole map is squeezed into a small window.
const _ROAD_WIDTH_SCALE := 0.18
const _ROAD_MIN_WIDTH := 2.0

## Colour a tile fades toward as its forage falls — a pale, bleached version of
## itself rather than a darker one, because a winter map should read as drained
## rather than as a map at night.
const _DORMANT := Color(0.82, 0.84, 0.87)

## How far toward `_DORMANT` a tile with no forage at all is allowed to go. Short
## of 1.0 on purpose: at 1.0 every barren tile is the same colour and the terrain
## underneath stops being readable, which trades one thing the player needs to
## see for another.
const _DORMANCY_MAX := 0.70

## Left edge of the season indicator and the legend below it, measured in from
## the right of the viewport. Shared so the two line up, and wide enough that
## the longest season caption is not clipped by the edge of the window.
const _PANEL_INSET := 176.0

const _EDGE_COLOR := Color(0.0, 0.0, 0.0, 0.18)
const _BACKGROUND := Color(0.07, 0.08, 0.10)
const _MARGIN := 12.0

## Microseconds the last `_draw()` took. Read by the redraw-budget test; the
## alternative is timing a whole frame, which measures the frame rate rather
## than the cost of drawing the map.
var last_draw_usec := 0

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
			_fills[i] = tile_color(terrain, _world.forage_at(coord))
			i += 1


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
	_draw_season()
	_draw_legend()

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


## The structures, as squares on the tiles they were placed on.
##
## A gathering camp additionally gets a halo, drawn under the square, so that the
## turn a herd arrives is a change in the *size* of a mark rather than only in
## its colour. Colour alone would ask the eye to compare a small square against
## its own memory of that square a few turns ago, which is exactly the comparison
## a person watching a map does not make.
func _draw_nodes() -> void:
	var half := _radius * _NODE_SCALE * 0.5
	for node in _world.nodes:
		var centre := center_of(node.coord)
		if node.kind == CityNode.Kind.GATHERING:
			_draw_gathering_halo(centre, node.yield_share())
		var box := Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(box, node_fill(node.kind, node.yield_share()))
		draw_rect(box, _NODE_EDGE, false, maxf(1.0, half * 0.22))


## The glow around a working camp: nothing at all when the ground around it is
## empty, opening out as animals come into range.
func _draw_gathering_halo(centre: Vector2, share: float) -> void:
	var lit := _lit_fraction(share)
	if lit <= 0.0:
		return
	var radius := _radius * _GATHERING_HALO_SCALE * lit
	draw_circle(centre, radius, Color(_GATHERING_FILL, 0.22 * lit))
	draw_arc(centre, radius, 0.0, TAU, 24, Color(_GATHERING_FILL, 0.55 * lit), maxf(1.0, _radius * 0.05))


## The fill for one structure. Static and public so a test can check the palette
## without a viewport, and so the lit/quiet reading is one function rather than
## something reconstructed at each draw call.
##
## `share` is the node's own report of how good its last turn was
## (`CityNode.yield_share()`), read rather than derived: how a yield was arrived
## at is simulation's business, and a view that recomputed it would be the second
## copy of a rule `AgDR-001` exists to prevent.
static func node_fill(kind: int, share: float) -> Color:
	match kind:
		CityNode.Kind.FARM:
			return _FARM_FILL
		CityNode.Kind.GATHERING:
			return _GATHERING_QUIET.lerp(_GATHERING_FILL, _lit_fraction(share))
	return _GRANARY_FILL


## How lit a camp looks for a given share of its best turn.
##
## Square root, for the same reason the herd marker uses one: the eye reads the
## bottom of a brightness range far more finely than the top, and a single herd
## in range is worth about half a camp's ceiling by construction
## (`CityNode.GATHERING_HALF_AT`). Linear would render the ordinary good case —
## one herd, right there, visible on the map — as a permanent half-light, and the
## thing the player has to notice is *arrival*, not magnitude.
static func _lit_fraction(share: float) -> float:
	return sqrt(clampf(share, 0.0, 1.0))


## The people on the road. Small — a person is not a herd — and filled according
## to whether they are carrying anything, so a glance at the road says which way
## the grain is going.
func _draw_citizens() -> void:
	var radius := maxf(2.0, _radius * _CITIZEN_SCALE)
	for citizen in _world.citizens():
		var centre := center_of(citizen.coord)
		var fill := _CITIZEN_LOADED if citizen.carrying > 0.0 else _CITIZEN_FILL
		draw_circle(centre, radius, fill)
		draw_arc(centre, radius, 0.0, TAU, 14, _CITIZEN_EDGE, maxf(1.0, radius * 0.30))


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
	var left := get_viewport_rect().size.x - _PANEL_INSET
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
## between "readable at a glance" and "guessable after a minute".
func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := ThemeDB.fallback_font_size
	var swatch := Vector2(16, 16)
	var pos := Vector2(get_viewport_rect().size.x - _PANEL_INSET, 62.0)
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

	# And the city, in the same order it is drawn on the map.
	draw_rect(Rect2(pos + swatch * 0.24, swatch * 0.52), _FARM_FILL)
	_legend_caption(font, font_size, pos, "farm")
	pos.y += swatch.y + 6.0
	draw_rect(Rect2(pos + swatch * 0.24, swatch * 0.52), _GRANARY_FILL)
	_legend_caption(font, font_size, pos, "granary")
	pos.y += swatch.y + 6.0
	# The camp's swatch is drawn twice, dark then lit, because its entry in the
	# legend is not a colour but a *difference* — the whole thing worth knowing
	# about this structure is that it has two states and the world decides which.
	draw_rect(Rect2(pos + Vector2(0.0, swatch.y * 0.24), swatch * 0.52), _GATHERING_QUIET)
	draw_rect(Rect2(pos + swatch * Vector2(0.48, 0.24), swatch * 0.52), _GATHERING_FILL)
	# Caption kept to roughly the width of the longest terrain name: the panel is
	# not clipped to, and "camp (lit=animals near)" ran off the right edge of a
	# 1280-wide frame — visible in any capture taken at that size.
	_legend_caption(font, font_size, pos, "camp (lit=animals)")
	pos.y += swatch.y + 6.0
	draw_circle(pos + swatch * 0.5, swatch.x * 0.22, _CITIZEN_LOADED)
	_legend_caption(font, font_size, pos, "citizens (lit=laden)")


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
