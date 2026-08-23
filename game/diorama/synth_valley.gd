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
	noise.frequency = 0.11
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed + 7777
	noise2.frequency = 0.16

	var far := DioramaHexKit.hex_center(COLS - 1, ROWS - 1)
	extent = Vector2(far.x + 1.0, far.y + 1.0)

	for q in range(COLS):
		for r in range(ROWS):
			var c := DioramaHexKit.hex_center(q, r)
			var e := 0.5 + 0.5 * noise.get_noise_2d(c.x, c.y)
			# valley shaping: mountains rise on +x, river carves a sine path
			e += pow(maxf(0.0, c.x - extent.x * 0.62) * 0.14, 1.5)
			var river_z := _river_x(c.y)
			e -= maxf(0.0, 1.7 - absf(c.x - river_z)) * 0.22
			e = clampf(e, 0.0, 1.3)
			var m := 0.5 + 0.5 * noise2.get_noise_2d(c.x, c.y)
			var coord := Vector2i(q, r)
			elevation[coord] = e
			moisture[coord] = m
			var t: Terrain
			if e < 0.30:
				t = Terrain.WATER
			elif e > 0.92:
				t = Terrain.MOUNTAIN
			elif e > 0.76:
				t = Terrain.HILL
			elif m > 0.52:
				t = Terrain.FOREST
			else:
				t = Terrain.GRASS
			terrain[coord] = t
			height[coord] = _display_height(t, e)

	_lay_road()
	_pick_sites()


func _river_x(z: float) -> float:
	return extent.x * 0.42 + sin(z * 0.31) * 1.6


func _display_height(t: Terrain, e: float) -> float:
	match t:
		Terrain.WATER:
			return -0.55
		Terrain.MOUNTAIN:
			return 1.1 + (e - 0.92) * 9.0
		Terrain.HILL:
			return 0.5 + (e - 0.76) * 3.5
		_:
			return maxf(0.02, (e - 0.30) * 1.4)
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


func _lay_road() -> void:
	# the road runs the valley floor, west bank of the river, bending with it
	var pts := PackedVector2Array()
	for i in range(15):
		var z := extent.y * (0.06 + 0.88 * i / 14.0)
		var x := _river_x(z) - 2.1 + sin(z * 0.5) * 0.5
		pts.append(Vector2(x, z))
	road = DioramaHexKit.chaikin(pts, 2)


func _pick_sites() -> void:
	# building sites flank the road's mid-section, on dry ground
	var placed := 0
	var i := 4
	while placed < 8 and i < 11:
		var p := road[i * (road.size() / 15)]
		for side: float in [-1.0, 1.0]:
			if placed >= 8:
				break
			var jx := DioramaHexKit.h01(seed, 31, placed, 1) - 0.5
			var jz := DioramaHexKit.h01(seed, 31, placed, 2) - 0.5
			var x := p.x + side * (1.1 + jx * 0.8)
			var z := p.y + jz * 1.4
			if height_at(x, z) > 0.05 and terrain_at(x, z) != Terrain.WATER:
				var rot := (DioramaHexKit.h01(seed, 37, placed) - 0.5) * 0.6
				sites.append(Vector3(x, z, rot))
				placed += 1
		i += 1
	# the hero stands on the rise across the river
	var hz := extent.y * 0.42
	var hx := _river_x(hz) + 3.4
	hero_site = Vector3(hx, hz, 0.5)
