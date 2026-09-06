@tool
class_name DioramaSpike
extends Node3D
## S0 spike (ticket #17): can procedural relief + primitive architecture +
## instanced vegetation + a long lens produce the civ-life diorama?
##
## Everything is generated at build time from SEED — no imported assets, no
## sim/ changes. Art-direction parameters are exported so the composition can
## be tuned live in the editor; toggle `rebuild` after changing one.
##
## Baked-in lab findings: linear tonemap (poster colour, not filmic), IDW hex
## heights (the grid lives in the data, not the eye), tangent voussoirs,
## per-face value jitter (structured imperfection), clearing around the
## settlement so the road stays legible.

@export var world_seed: int = 42

@export_group("Terrain")
@export var elevation_exaggeration: float = 2.2
@export var terrain_faceting: float = 1.45     # grid verts per world unit
@export var ridge_sharpness: float = 1.35      # >1 pushes high ground higher
@export var valley_depth: float = 1.0          # scales the water-side carve
@export var plinth_depth: float = 3.0          # cut-block base under the land

@export_group("Camera")
@export var fov_horizontal_deg: float = 22.0   # intent range: 15-30
@export var camera_pitch_deg: float = 33.0
@export var camera_yaw_deg: float = -158.0
@export var camera_distance: float = 96.0
@export var camera_target_bias: Vector2 = Vector2(0.46, 0.52)

@export_group("Light")
@export var sun_elevation_deg: float = 27.0
@export var sun_azimuth_deg: float = 218.0
@export var sun_energy: float = 1.25
@export var ambient_energy: float = 0.45

@export_group("Buildings")
## How big a building stands in the valley. A style tree states a building's
## PROPORTIONS; the diorama states its size, so the same style can stand at
## village and at city scale without restating every dimension. These match the
## 0.72 and 1.5 the hardcoded recipes used to bake in.
@export var building_scale: float = 0.72
@export var hero_scale: float = 1.5

## Which culture built this valley. One settlement, one culture — the whole
## valley shares a palette, because a mapping is what a culture IS here and two
## palettes in one town would be two towns.
@export_enum("sunlit", "basalt") var culture: String = "sunlit"

@export var rebuild: bool = false:
	set(_v):
		_build()

const INDIGO := Color(0.071, 0.078, 0.110)
const MOSS := Color(0.451, 0.522, 0.337)
const MOSS_DARK := Color(0.310, 0.408, 0.271)
const HILL_TINT := Color(0.573, 0.529, 0.361)
const ROCK := Color(0.612, 0.596, 0.545)
const ROCK_HIGH := Color(0.729, 0.714, 0.671)
const SAND := Color(0.678, 0.647, 0.518)
const WATER_COL := Color(0.129, 0.353, 0.412)
const PLASTER2 := Color(0.847, 0.812, 0.718)
const OCHRE := Color(0.678, 0.494, 0.290)
const CANOPY := Color(0.294, 0.416, 0.239)
const CANOPY_DARK := Color(0.216, 0.318, 0.196)
const TRUNK := Color(0.400, 0.302, 0.196)
const PLINTH := Color(0.510, 0.478, 0.427)
const PLINTH_LOW := Color(0.376, 0.353, 0.322)
## Height the ridge_sharpness curve pivots around — roughly the tallest
## land the synthetic field produces before exaggeration.
const RIDGE_REF := 3.0

## Geometry fingerprints of the last build, for determinism tests.
var last_fingerprints: Dictionary = {}
## Wall-clock cost of the last _build(), in milliseconds (AC10: iteration
## speed is a finding, so it is measured rather than assumed).
var build_msec: float = 0.0


func _ready() -> void:
	_build()
	# AC10: iteration speed is a finding, so the number is printed rather
	# than assumed. It lands in the capture log next to the frame it made.
	if not Engine.is_editor_hint():
		print("[spike] built seed %d in %.1f ms" % [world_seed, build_msec])


func _build() -> void:
	var t0 := Time.get_ticks_usec()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	last_fingerprints.clear()

	var valley := SynthValley.new(world_seed)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_build_terrain(valley, mat)
	_build_water(valley)
	_build_settlement(valley, mat)
	_build_trees(valley, mat)
	_build_camera(valley)
	_build_light()
	_build_environment()
	build_msec = (Time.get_ticks_usec() - t0) / 1000.0


## Display height with the art-direction parameters applied. `ridge_sharpness`
## is a power curve on land only: above 1 it pulls ridges up and flattens the
## floor, which is what makes mountains carry a silhouette from a long lens
## without dragging the valley up with them.
func _height(valley: SynthValley, x: float, z: float) -> float:
	var h := valley.height_at(x, z)
	if h < 0.0:
		return h * valley_depth * elevation_exaggeration
	# normalised around RIDGE_REF so the exponent reshapes the range instead
	# of scaling it: an un-normalised pow() turns a 1.35 into a 3x on peaks
	# and makes every parameter downstream of it meaningless.
	return RIDGE_REF * pow(h / RIDGE_REF, ridge_sharpness) * elevation_exaggeration


## The river surface. Derived, never a constant: the riverbed moves with
## exaggeration and depth, so a fixed water plane would drown or strand the
## channel the moment either parameter is swept.
func _water_y() -> float:
	return -0.16 * valley_depth * elevation_exaggeration


func _build_terrain(valley: SynthValley, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var nx := int(valley.extent.x * terrain_faceting)
	var nz := int(valley.extent.y * terrain_faceting)
	var sx := valley.extent.x / nx
	var sz := valley.extent.y / nz
	# heights sampled once per grid vertex, shared by four faces — sampling
	# per-face instead tears the surface at every seam
	var grid := PackedFloat32Array()
	grid.resize((nx + 1) * (nz + 1))
	for i in range(nx + 1):
		for j in range(nz + 1):
			grid[i * (nz + 1) + j] = _height(valley, i * sx, j * sz)
	var lowest := 0.0
	for h in grid:
		lowest = minf(lowest, h)
	var base_y := lowest - plinth_depth * elevation_exaggeration * 0.4

	for i in range(nx):
		for j in range(nz):
			var x0 := i * sx
			var z0 := j * sz
			var p00 := Vector3(x0, grid[i * (nz + 1) + j], z0)
			var p10 := Vector3(x0 + sx, grid[(i + 1) * (nz + 1) + j], z0)
			var p11 := Vector3(x0 + sx, grid[(i + 1) * (nz + 1) + j + 1], z0 + sz)
			var p01 := Vector3(x0, grid[i * (nz + 1) + j + 1], z0 + sz)
			var cx := x0 + sx * 0.5
			var cz := z0 + sz * 0.5
			var col := _ground_color(valley, cx, cz, (p00.y + p11.y) * 0.5)
			# structured imperfection: per-face value jitter, hash-stable
			var jit := (DioramaHexKit.h01(world_seed, 5, i, j) - 0.5) * 0.055
			col = Color(col.r + jit, col.g + jit, col.b + jit)
			# split each cell on its shorter diagonal so facets follow the
			# slope instead of all leaning the same way
			if absf(p00.y - p11.y) <= absf(p10.y - p01.y):
				b.add_tri(p00, p11, p10, col)
				b.add_tri(p00, p01, p11, col)
			else:
				b.add_tri(p00, p01, p10, col)
				b.add_tri(p01, p11, p10, col)

	_build_plinth(b, valley, grid, nx, nz, sx, sz, base_y)
	_build_road(b, valley)
	_build_farms(b, valley)

	var inst := MeshInstance3D.new()
	inst.name = "Terrain"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)
	last_fingerprints["terrain"] = b.fingerprint()


## The cut block the landscape sits on. This is the single strongest signal
## that the thing on screen is a *model of* a place rather than a place: an
## architectural model has an edge, and the edge is honest about being one.
func _build_plinth(b: DioramaMeshKit, valley: SynthValley,
		grid: PackedFloat32Array, nx: int, nz: int, sx: float, sz: float,
		base_y: float) -> void:
	var band := base_y + (0.0 - base_y) * 0.42
	var edges := [
		{"axis": 0, "at": 0, "n": nz, "flip": true},
		{"axis": 0, "at": nx, "n": nz, "flip": false},
		{"axis": 1, "at": 0, "n": nx, "flip": false},
		{"axis": 1, "at": nz, "n": nx, "flip": true},
	]
	for e: Dictionary in edges:
		for k in range(e["n"]):
			var a: Vector3
			var c: Vector3
			if e["axis"] == 0:
				var i: int = e["at"]
				a = Vector3(i * sx, grid[i * (nz + 1) + k], k * sz)
				c = Vector3(i * sx, grid[i * (nz + 1) + k + 1], (k + 1) * sz)
			else:
				var j: int = e["at"]
				a = Vector3(k * sx, grid[k * (nz + 1) + j], j * sz)
				c = Vector3((k + 1) * sx, grid[(k + 1) * (nz + 1) + j], j * sz)
			if e["flip"]:
				var t := a
				a = c
				c = t
			b.add_quad(a, c, Vector3(c.x, band, c.z), Vector3(a.x, band, a.z),
					PLINTH)
			b.add_quad(Vector3(a.x, band, a.z), Vector3(c.x, band, c.z),
					Vector3(c.x, base_y, c.z), Vector3(a.x, base_y, a.z),
					PLINTH_LOW)
	b.add_quad(
			Vector3(0, base_y, 0), Vector3(valley.extent.x, base_y, 0),
			Vector3(valley.extent.x, base_y, valley.extent.y),
			Vector3(0, base_y, valley.extent.y), PLINTH_LOW)


## Road ribbon draped on the surface, and lifted into a bridge deck with piers
## where the alignment crosses the river. Roads that dive underwater were the
## first thing that broke the illusion of a built valley.
func _build_road(b: DioramaMeshKit, valley: SynthValley) -> void:
	var wy := _water_y()
	var deck := wy + 0.30 * elevation_exaggeration * 0.5
	var pier_span := 0.0
	for k in range(valley.road.size() - 1):
		var a2 := valley.road[k]
		var c2 := valley.road[k + 1]
		var dir := (c2 - a2).normalized()
		var n2 := Vector2(-dir.y, dir.x) * 0.24
		var ya := _road_y(valley, a2, deck)
		var yc := _road_y(valley, c2, deck)
		var quad := []
		for corner: Vector2 in [a2 - n2, a2 + n2, c2 + n2, c2 - n2]:
			var base_h: float = ya if corner.distance_to(a2) < corner.distance_to(c2) else yc
			quad.append(Vector3(corner.x, base_h, corner.y))
		b.add_quad(quad[0], quad[1], quad[2], quad[3], PLASTER2)
		if valley.is_submerged(a2.x, a2.y):
			# deck edge, so the bridge has a thickness at this scale
			b.add_quad(quad[0], quad[3],
					Vector3(quad[3].x, quad[3].y - 0.22, quad[3].z),
					Vector3(quad[0].x, quad[0].y - 0.22, quad[0].z), PLASTER2)
			pier_span += a2.distance_to(c2)
			if pier_span > 0.9:
				pier_span = 0.0
				var bed := _height(valley, a2.x, a2.y)
				var xf := Transform3D(Basis.IDENTITY, Vector3(a2.x, bed, a2.y))
				b.add_box(xf, Vector3(0.26, ya - bed, 0.42), PLASTER2)


func _road_y(valley: SynthValley, p: Vector2, deck: float) -> float:
	if valley.is_submerged(p.x, p.y):
		return deck
	return _height(valley, p.x, p.y) + 0.05 * elevation_exaggeration


## Farm strips on the near bank, aligned to the road rather than to the world
## axes — field geometry that ignores the route it serves reads as wallpaper.
func _build_farms(b: DioramaMeshKit, valley: SynthValley) -> void:
	var anchor := valley.road[8]
	var ahead := valley.road[14]
	var along := (ahead - anchor).normalized()
	var across := Vector2(-along.y, along.x)
	for i in range(7):
		var off := 1.7 + i * 0.62
		for s: float in [-1.0, 1.0]:
			var c := anchor + across * off * s + along * (i % 3) * 0.5
			if c.x > valley.river_x(c.y) - 1.6 or c.x < 0.8:
				continue
			if valley.height_at(c.x, c.y) < 0.06:
				continue
			var rot := atan2(along.x, along.y)
			var xf := Transform3D(Basis(Vector3.UP, rot),
					Vector3(c.x, _height(valley, c.x, c.y) + 0.02, c.y))
			b.add_box(xf, Vector3(0.44, 0.04, 2.6),
					OCHRE if (i + int(s)) % 2 == 0 else SAND)


func _ground_color(valley: SynthValley, x: float, z: float, y: float) -> Color:
	match valley.terrain_at(x, z):
		SynthValley.Terrain.WATER:
			return SAND.lerp(MOSS_DARK, 0.35)   # bank and bed; water covers it
		SynthValley.Terrain.FOREST:
			return MOSS_DARK
		SynthValley.Terrain.HILL:
			return HILL_TINT
		SynthValley.Terrain.MOUNTAIN:
			# value separation with altitude: the range needs to read as one
			# mass with a lit top, not as a uniform grey wall
			var t := clampf((y / elevation_exaggeration - 1.2) / 3.0, 0.0, 1.0)
			return ROCK.lerp(ROCK_HIGH, t)
		_:
			return MOSS
	return MOSS


func _build_water(valley: SynthValley) -> void:
	var plane := PlaneMesh.new()
	plane.size = valley.extent
	var inst := MeshInstance3D.new()
	inst.name = "Water"
	inst.mesh = plane
	inst.position = Vector3(valley.extent.x * 0.5, _water_y(),
			valley.extent.y * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER_COL
	mat.roughness = 0.45
	mat.metallic = 0.0
	inst.material_override = mat
	add_child(inst)


func _build_settlement(valley: SynthValley, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var kinds := ["residential", "residential", "civic", "residential",
			"stepped", "residential", "residential", "civic", "residential"]
	for i in range(valley.sites.size()):
		var site := valley.sites[i]
		var tree: Dictionary
		match kinds[i % kinds.size()]:
			"civic":
				tree = DioramaStyles.civic()
			"stepped":
				tree = DioramaStyles.stepped()
			_:
				tree = DioramaStyles.residential()
		var parts := DioramaCompose.build(tree, world_seed, i)
		DioramaCompose.apply_roles(parts, DioramaCultures.palette(culture))
		# Scale belongs to PLACEMENT, not to a style: the same style should be
		# able to stand at village and at city size, so the diorama says how big
		# its buildings are rather than every style restating it.
		var world := Transform3D(
				Basis(Vector3.UP, site.z).scaled(Vector3.ONE * building_scale),
				Vector3(site.x, _height(valley, site.x, site.y), site.y))
		DioramaGrammar.emit(b, parts, world)
	# the hero breaks the scale hierarchy, per the intent's composition rule:
	# huge valley, small town, thin road, one enormous civic structure
	var hs := valley.hero_site
	var hero := DioramaCompose.build(DioramaStyles.hero_arch(), world_seed, 0)
	DioramaCompose.apply_roles(hero, DioramaCultures.palette(culture))
	var hero_world := Transform3D(
			Basis(Vector3.UP, hs.z).scaled(Vector3.ONE * hero_scale),
			Vector3(hs.x, _height(valley, hs.x, hs.y), hs.y))
	DioramaGrammar.emit(b, hero, hero_world)
	var inst := MeshInstance3D.new()
	inst.name = "Settlement"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)
	last_fingerprints["settlement"] = b.fingerprint()


func _build_trees(valley: SynthValley, mat: StandardMaterial3D) -> void:
	# one small composed mesh per kind, instanced — vegetation is 3D stippling
	var kinds := {
		"conifer": _tree_mesh_conifer(),
		"broadleaf": _tree_mesh_broadleaf(),
	}
	var placements := {"conifer": [], "broadleaf": []}
	var accepted: Array[Vector2] = []
	var fp := 1469598103934665603
	var coords := valley.terrain.keys()
	coords.sort()
	for coord: Vector2i in coords:
		var t_class: int = valley.terrain[coord]
		if t_class != SynthValley.Terrain.FOREST and t_class != SynthValley.Terrain.HILL:
			continue
		var m: float = valley.moisture[coord]
		if t_class == SynthValley.Terrain.HILL and m < 0.58:
			continue
		var c := DioramaHexKit.hex_center(coord.x, coord.y)
		# density responds to moisture — the field drives the stippling
		var count := 2 + int(DioramaHexKit.h01(world_seed, 11, coord.x, coord.y)
				* (1.0 + m * 4.0))
		for i in range(count):
			var a := DioramaHexKit.h01(world_seed, 12, coord.x * 31 + i, coord.y) * TAU
			var d := sqrt(DioramaHexKit.h01(world_seed, 13, coord.x, coord.y * 31 + i)) * 0.85
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			if _near_town(valley, x, z) or valley.is_submerged(x, z):
				continue
			var too_close := false
			for p in accepted:
				if (p.x - x) * (p.x - x) + (p.y - z) * (p.y - z) < 0.34:
					too_close = true
					break
			if too_close:
				continue
			accepted.append(Vector2(x, z))
			var kind := "conifer" if valley.elevation[coord] > 0.60 else "broadleaf"
			var rot := DioramaHexKit.h01(world_seed, 14, coord.x + i, coord.y) * TAU
			var scl := 0.85 + DioramaHexKit.h01(world_seed, 15, coord.x, coord.y + i) * 0.55
			var tf := Transform3D(Basis(Vector3.UP, rot).scaled(
					Vector3(scl, scl * (0.85 + m * 0.5), scl)),
					Vector3(x, _height(valley, x, z) - 0.05, z))
			placements[kind].append(tf)
			fp = DioramaMeshKit._mix(fp, int(x * 1000.0) + int(z * 1000.0) * 92821)
	for kind: String in kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kinds[kind]
		mm.instance_count = placements[kind].size()
		for i in range(placements[kind].size()):
			mm.set_instance_transform(i, placements[kind][i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Trees_" + kind
		inst.multimesh = mm
		inst.material_override = mat
		add_child(inst)
	last_fingerprints["trees"] = fp


func _near_town(valley: SynthValley, x: float, z: float) -> bool:
	for site in valley.sites:
		if (site.x - x) * (site.x - x) + (site.y - z) * (site.y - z) < 3.2:
			return true
	var hs := valley.hero_site
	if (hs.x - x) * (hs.x - x) + (hs.y - z) * (hs.y - z) < 7.0:
		return true
	var step := maxi(1, valley.road.size() / 28)
	for k in range(0, valley.road.size(), step):
		var p := valley.road[k]
		if absf(p.x - x) < 1.0 and absf(p.y - z) < 1.0:
			return true
	return false


func _tree_mesh_conifer() -> ArrayMesh:
	var b := DioramaMeshKit.new()
	b.add_prism(Transform3D.IDENTITY, 0.055, 0.26, TRUNK, 5, 0.2)
	var y := 0.20
	for t in range(3):
		var xf := Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
		b.add_cone(xf, 0.34 - t * 0.08, 0.58 - t * 0.09,
				CANOPY_DARK if t % 2 == 0 else CANOPY, 7)
		y += 0.30
	return b.commit()


func _tree_mesh_broadleaf() -> ArrayMesh:
	var b := DioramaMeshKit.new()
	b.add_prism(Transform3D.IDENTITY, 0.055, 0.42, TRUNK, 5, 0.2)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, 0.58, 0)), 0.33, 0.78, CANOPY)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0.18, 0.48, 0.11)), 0.22, 0.72,
			CANOPY_DARK)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(-0.15, 0.50, -0.12)), 0.19, 0.70,
			CANOPY_DARK)
	return b.commit()


func _build_camera(valley: SynthValley) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	var target := Vector3(valley.extent.x * camera_target_bias.x,
			0.6 * elevation_exaggeration,
			valley.extent.y * camera_target_bias.y)
	var pitch := deg_to_rad(camera_pitch_deg)
	var yaw := deg_to_rad(camera_yaw_deg)
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch),
			-cos(pitch) * cos(yaw)) * camera_distance
	cam.position = target + offset
	cam.basis = Basis.looking_at(target - cam.position, Vector3.UP)
	# Godot's fov is vertical; the intent's 15-30 range is horizontal
	var aspect := 16.0 / 9.0
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_horizontal_deg) * 0.5) / aspect))
	cam.far = 4000.0
	add_child(cam)
	if not Engine.is_editor_hint():
		cam.make_current()


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	var dir := Vector3(-cos(el) * sin(az), -sin(el), cos(el) * cos(az))
	sun.basis = Basis.looking_at(dir, Vector3.UP)
	sun.light_energy = sun_energy
	sun.light_color = Color(1.0, 0.965, 0.898)
	sun.shadow_enabled = true
	# A long lens sits the camera far back; the default 100 m shadow range
	# ends before the subject does and the diorama loses the cast shadows
	# that are half of what makes it read as a lit model. Stretching one
	# orthogonal map over that range instead is what produced the first
	# broken frame — the whole valley came back mottled with acne, which
	# reads as dirty terrain rather than as a shadow bug. Four splits keep
	# the near texels small enough for the settlement.
	sun.directional_shadow_max_distance = camera_distance + 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.5
	add_child(sun)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = INDIGO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# cool fill against a warm key: plane separation without a second light
	env.ambient_light_color = Color(0.494, 0.545, 0.667)
	env.ambient_light_energy = ambient_energy
	# poster colour on sculpture, not filmic realism (lab finding)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
