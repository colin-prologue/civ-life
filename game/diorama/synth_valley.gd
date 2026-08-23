class_name SynthValley
extends RefCounted
## Synthetic per-hex state for the S0 spike, shaped like the state the sim
## will eventually deliver: elevation, moisture, and terrain class at flat-top
## axial hex centres, plus a road path, building sites, and a hero site.
##
## Everything derives from one seed. No sim/ code is touched; when the real
## HexRenderState exists, it replaces this class and nothing downstream moves.

enum Terrain { WATER, GRASS, FOREST, HILL, MOUNTAIN }

const COLS := 18
const ROWS := 14

## Elevation below this is river. Kept as a named constant because three
## separate things have to agree on it: the terrain class, the display height,
## and where the road turns into a bridge.
const WATER_LEVEL := 0.30

var seed: int
var elevation: Dictionary = {}   # Vector2i -> float 0..1
var moisture: Dictionary = {}    # Vector2i -> float 0..1
var terrain: Dictionary = {}     # Vector2i -> Terrain
var height: Dictionary = {}      # Vector2i -> display height (art side)
var road: PackedVector2Array     # polyline of hex centres, ground plane
var sites: Array[Vector3] = []   # (x, z, rot) building sites
var hero_site: Vector3           # (x, z, rot)
var extent: Vector2              # world-space size of the slab


func _init(p_seed: int) -> void:
	seed = p_seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.075
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed + 7777
	noise2.frequency = 0.16

	var far := DioramaHexKit.hex_center(COLS - 1, ROWS - 1)
	extent = Vector2(far.x + 1.0, far.y + 1.0)

	for q in range(COLS):
		for r in range(ROWS):
			var c := DioramaHexKit.hex_center(q, r)
			var e := _land_elevation(c, noise)
			var m := 0.5 + 0.5 * noise2.get_noise_2d(c.x, c.y)
			var coord := Vector2i(q, r)
			elevation[coord] = e
			moisture[coord] = m
			var t: Terrain
			if e < WATER_LEVEL:
				t = Terrain.WATER
			elif e > 0.90:
				t = Terrain.MOUNTAIN
			elif e > 0.74:
				t = Terrain.HILL
			elif m > 0.50:
				t = Terrain.FOREST
			else:
				t = Terrain.GRASS
			terrain[coord] = t
			height[coord] = _display_height(t, e)

	_lay_road()
	_pick_sites()


## The valley's whole shape, as one continuous field: rolling ground, a
## mountain wall on +x, a low ridge on -x so the valley is enclosed rather
## than an open shelf, and a river cut hard enough to be a river and not a
## chain of ponds.
func _land_elevation(c: Vector2, noise: FastNoiseLite) -> float:
	var e := 0.52 + 0.30 * noise.get_noise_2d(c.x, c.y)
	# mountain wall along the eastern third
	var into_range := maxf(0.0, c.x - extent.x * 0.60) / (extent.x * 0.40)
	e += pow(into_range, 1.6) * 1.05
	# a modest western shoulder — the valley reads as enclosed, not as a shelf
	var west := maxf(0.0, extent.x * 0.16 - c.x) / (extent.x * 0.16)
	e += pow(west, 1.5) * 0.34
	# the river: a narrow channel with banks, not a moisture-driven blot
	var d := absf(c.x - river_x(c.y))
	e -= pow(maxf(0.0, 1.0 - d / 3.2), 2.0) * 0.42
	if d < 1.05:
		e = minf(e, WATER_LEVEL - 0.10 - (1.05 - d) * 0.12)
	return clampf(e, 0.0, 1.9)


## The river's centreline as a function of z. Public because the road has to
## know where it is in order to bridge it.
func river_x(z: float) -> float:
	return extent.x * 0.40 + sin(z * 0.24) * 2.1 + sin(z * 0.61) * 0.7


func _display_height(t: Terrain, e: float) -> float:
	match t:
		Terrain.WATER:
			# riverbed, not a flat floor — the channel keeps a cross-section
			return -0.30 - (WATER_LEVEL - e) * 2.2
		Terrain.MOUNTAIN:
			return 1.05 + (e - 0.90) * 3.2
		Terrain.HILL:
			return 0.52 + (e - 0.74) * 3.3
		_:
			return maxf(0.03, (e - WATER_LEVEL) * 1.25)
	return 0.0


## IDW over nearby hex centres — hexes present in the data, not in the eye
## (lab finding: smooth interpolation hides the grid; class edges are what
## leak, and this spike colours per terrain face with jittered blending).
func height_at(x: float, z: float) -> float:
	var q0 := int(x / 1.5)
	var r0 := int(z / DioramaHexKit.SQRT3)
	var wsum := 0.0
	var hsum := 0.0
	for q in range(maxi(0, q0 - 2), mini(COLS, q0 + 3)):
		for r in range(maxi(0, r0 - 2), mini(ROWS, r0 + 3)):
			var c := DioramaHexKit.hex_center(q, r)
			var d2 := (c.x - x) * (c.x - x) + (c.y - z) * (c.y - z)
			if d2 > 6.8:
				continue
			var w := 1.0 / pow(d2 + 0.08, 1.5)
			wsum += w
			hsum += w * height[Vector2i(q, r)]
	return hsum / wsum if wsum > 0.0 else 0.0


func terrain_at(x: float, z: float) -> Terrain:
	var best_d := INF
	var best := Terrain.GRASS
	var q0 := int(x / 1.5)
	var r0 := int(z / DioramaHexKit.SQRT3)
	for q in range(maxi(0, q0 - 2), mini(COLS, q0 + 3)):
		for r in range(maxi(0, r0 - 2), mini(ROWS, r0 + 3)):
			var c := DioramaHexKit.hex_center(q, r)
			var d2 := (c.x - x) * (c.x - x) + (c.y - z) * (c.y - z)
			if d2 < best_d:
				best_d = d2
				best = terrain[Vector2i(q, r)]
	return best


## True where the ground sits under the river surface — the bridge test, and
## the reason the road knows about water at all.
func is_submerged(x: float, z: float) -> bool:
	return absf(x - river_x(z)) < 1.35


func _lay_road() -> void:
	# The road crosses the valley west to east: farmland and town on the near
	# bank, a bridge over the river, then up toward the hero and the range.
	# Crossing rather than paralleling is a composition choice — it gives the
	# frame a line that travels through depth instead of across it.
	var pts := PackedVector2Array()
	for i in range(13):
		var t := float(i) / 12.0
		var x := extent.x * (0.03 + 0.86 * t)
		var z := extent.y * 0.62 - t * extent.y * 0.22 + sin(t * 4.1) * 1.5
		pts.append(Vector2(x, z))
	road = DioramaHexKit.chaikin(pts, 2)


func _pick_sites() -> void:
	# Buildings flank the road on the dry western bank, before the crossing.
	var placed := 0
	for k in range(6, road.size()):
		if placed >= 9:
			break
		var p := road[k]
		if p.x > river_x(p.y) - 2.4:
			continue
		if k % 3 != 0:
			continue
		for side: float in [-1.0, 1.0]:
			if placed >= 9:
				break
			var jx := DioramaHexKit.h01(seed, 31, placed, 1) - 0.5
			var jz := DioramaHexKit.h01(seed, 31, placed, 2) - 0.5
			var x := p.x + side * (1.15 + jx * 0.7)
			var z := p.y + jz * 1.5
			if height_at(x, z) > 0.06 and terrain_at(x, z) != Terrain.WATER:
				var rot := (DioramaHexKit.h01(seed, 37, placed) - 0.5) * 0.5
				sites.append(Vector3(x, z, rot))
				placed += 1
	# The hero stands on the far bank where the road climbs toward the range —
	# across the river from the town, so the crossing reads as going somewhere.
	var hz := road[road.size() - 4].y
	var hx := river_x(hz) + 3.6
	hero_site = Vector3(hx, hz, 0.35)
