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
	_draw_season()
	_draw_legend()

	last_draw_usec = Time.get_ticks_usec() - started


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
