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
@export var elevation_exaggeration: float = 1.5
@export var terrain_faceting: float = 2.4      # grid verts per world unit
@export var valley_depth: float = 1.0          # scales the water-side carve

@export_group("Camera")
@export var fov_horizontal_deg: float = 22.0   # intent range: 15-30
@export var camera_pitch_deg: float = 36.0
@export var camera_yaw_deg: float = -140.0
@export var camera_distance: float = 72.0

@export_group("Light")
@export var sun_elevation_deg: float = 26.0
@export var sun_azimuth_deg: float = 205.0
@export var sun_energy: float = 1.7

@export var rebuild: bool = false:
	set(_v):
		_build()

const INDIGO := Color(0.055, 0.063, 0.094)
const MOSS := Color(0.404, 0.475, 0.310)
const MOSS_DARK := Color(0.322, 0.400, 0.265)
const HILL_TINT := Color(0.494, 0.463, 0.320)
const ROCK := Color(0.553, 0.541, 0.494)
const WATER_COL := Color(0.196, 0.427, 0.475)
const PLASTER2 := Color(0.812, 0.776, 0.682)
const OCHRE := Color(0.659, 0.475, 0.290)
const CANOPY := Color(0.310, 0.420, 0.255)
const CANOPY_DARK := Color(0.255, 0.353, 0.220)
const TRUNK := Color(0.478, 0.361, 0.220)

## Geometry fingerprints of the last build, for determinism tests.
var last_fingerprints: Dictionary = {}


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	last_fingerprints.clear()

	var valley := SynthValley.new(world_seed)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92

	_build_terrain(valley, mat)
	_build_water(valley)
	_build_settlement(valley, mat)
	_build_trees(valley, mat)
	_build_camera(valley)
	_build_light()
	_build_environment()


func _height(valley: SynthValley, x: float, z: float) -> float:
	var h := valley.height_at(x, z)
	if h < 0.0:
		h *= valley_depth
	return h * elevation_exaggeration


func _build_terrain(valley: SynthValley, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var nx := int(valley.extent.x * terrain_faceting)
	var nz := int(valley.extent.y * terrain_faceting)
	var sx := valley.extent.x / nx
	var sz := valley.extent.y / nz
	for i in range(nx):
		for j in range(nz):
			var x0 := i * sx
			var z0 := j * sz
			var p00 := Vector3(x0, _height(valley, x0, z0), z0)
			var p10 := Vector3(x0 + sx, _height(valley, x0 + sx, z0), z0)
			var p11 := Vector3(x0 + sx, _height(valley, x0 + sx, z0 + sz), z0 + sz)
			var p01 := Vector3(x0, _height(valley, x0, z0 + sz), z0 + sz)
			var cx := x0 + sx * 0.5
			var cz := z0 + sz * 0.5
			var col := _ground_color(valley, cx, cz)
			# structured imperfection: per-face value jitter, hash-stable
			var jit := (DioramaHexKit.h01(world_seed, 5, i, j) - 0.5) * 0.07
			col = Color(col.r + jit, col.g + jit, col.b + jit)
			b.add_tri(p00, p11, p10, col)
			b.add_tri(p00, p01, p11, col)
	# road ribbon, draped and lifted
	for k in range(valley.road.size() - 1):
		var a2 := valley.road[k]
		var c2 := valley.road[k + 1]
		var dir := (c2 - a2).normalized()
		var n2 := Vector2(-dir.y, dir.x) * 0.19
		var quad := []
		for corner in [a2 - n2, a2 + n2, c2 + n2, c2 - n2]:
			quad.append(Vector3(corner.x,
					_height(valley, corner.x, corner.y) + 0.045, corner.y))
		b.add_quad(quad[0], quad[1], quad[2], quad[3], PLASTER2)
	# farm strips beside the road's southern approach
	var f0 := valley.road[4]
	for i in range(5):
		var fx := f0.x - 1.6 - i * 0.5
		var fz := f0.y
		var xf := Transform3D(Basis.IDENTITY,
				Vector3(fx, _height(valley, fx, fz) + 0.02, fz))
		b.add_box(xf, Vector3(0.34, 0.05, 2.4),
				OCHRE if i % 2 == 1 else PLASTER2)
	var inst := MeshInstance3D.new()
	inst.name = "Terrain"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)
	last_fingerprints["terrain"] = b.fingerprint()


func _ground_color(valley: SynthValley, x: float, z: float) -> Color:
	match valley.terrain_at(x, z):
		SynthValley.Terrain.WATER:
			return MOSS_DARK      # river bed; the water plane covers it
		SynthValley.Terrain.FOREST:
			return MOSS_DARK
		SynthValley.Terrain.HILL:
			return HILL_TINT
		SynthValley.Terrain.MOUNTAIN:
			return ROCK
		_:
			return MOSS
	return MOSS


func _build_water(valley: SynthValley) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(valley.extent.x + 2.0, valley.extent.y + 2.0)
	var inst := MeshInstance3D.new()
	inst.name = "Water"
	inst.mesh = plane
	inst.position = Vector3(valley.extent.x * 0.5, -0.10, valley.extent.y * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER_COL
	mat.roughness = 0.25
	inst.material_override = mat
	add_child(inst)


func _build_settlement(valley: SynthValley, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var kinds := ["residential", "residential", "civic", "residential",
			"stepped", "residential", "residential", "civic"]
	for i in range(valley.sites.size()):
		var site := valley.sites[i]
		var parts: Array
		match kinds[i % kinds.size()]:
			"civic":
				parts = DioramaGrammar.civic(world_seed, i)
			"stepped":
				parts = DioramaGrammar.stepped(world_seed, i)
			_:
				parts = DioramaGrammar.residential(world_seed, i)
		var world := Transform3D(Basis(Vector3.UP, site.z),
				Vector3(site.x, _height(valley, site.x, site.y), site.y))
		DioramaGrammar.emit(b, parts, world)
	# the hero breaks the scale hierarchy, per the intent's composition rule
	var hs := valley.hero_site
	var hero := DioramaGrammar.hero_arch(world_seed)
	var hero_world := Transform3D(Basis(Vector3.UP, hs.z),
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
	for coord: Vector2i in valley.terrain:
		if valley.terrain[coord] != SynthValley.Terrain.FOREST:
			continue
		var c := DioramaHexKit.hex_center(coord.x, coord.y)
		var count := 2 + int(DioramaHexKit.h01(world_seed, 11, coord.x, coord.y) * 2.0)
		for i in range(count):
			var a := DioramaHexKit.h01(world_seed, 12, coord.x * 31 + i, coord.y) * TAU
			var d := DioramaHexKit.h01(world_seed, 13, coord.x, coord.y * 31 + i) * 0.62
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			if _near_town(valley, x, z):
				continue
			var too_close := false
			for p in accepted:
				if (p.x - x) * (p.x - x) + (p.y - z) * (p.y - z) < 0.55:
					too_close = true
					break
			if too_close:
				continue
			accepted.append(Vector2(x, z))
			var kind := "conifer" if valley.elevation[coord] > 0.62 else "broadleaf"
			var rot := DioramaHexKit.h01(world_seed, 14, coord.x + i, coord.y) * TAU
			var scl := 0.8 + DioramaHexKit.h01(world_seed, 15, coord.x, coord.y + i) * 0.5
			var t := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * scl),
					Vector3(x, _height(valley, x, z), z))
			placements[kind].append(t)
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
		if (site.x - x) * (site.x - x) + (site.y - z) * (site.y - z) < 2.6:
			return true
	var step := maxi(1, valley.road.size() / 20)
	for k in range(0, valley.road.size(), step):
		var p := valley.road[k]
		if absf(p.x - x) < 0.9 and absf(p.y - z) < 0.9:
			return true
	return false


func _tree_mesh_conifer() -> ArrayMesh:
	var b := DioramaMeshKit.new()
	b.add_prism(Transform3D.IDENTITY, 0.05, 0.22, TRUNK, 5, 0.2)
	var y := 0.18
	for t in range(3):
		var xf := Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
		b.add_cone(xf, 0.30 - t * 0.07, 0.5 - t * 0.08,
				CANOPY_DARK if t % 2 == 0 else CANOPY, 7)
		y += 0.26
	return b.commit()


func _tree_mesh_broadleaf() -> ArrayMesh:
	var b := DioramaMeshKit.new()
	b.add_prism(Transform3D.IDENTITY, 0.05, 0.38, TRUNK, 5, 0.2)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, 0.52, 0)), 0.30, 0.75, CANOPY)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0.16, 0.44, 0.10)), 0.20, 0.7,
			CANOPY_DARK)
	return b.commit()


func _build_camera(valley: SynthValley) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	var target := Vector3(valley.extent.x * 0.5, 0.4, valley.extent.y * 0.5)
	var pitch := deg_to_rad(camera_pitch_deg)
	var yaw := deg_to_rad(camera_yaw_deg)
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch),
			-cos(pitch) * cos(yaw)) * camera_distance
	cam.position = target + offset
	cam.basis = Basis.looking_at(target - cam.position, Vector3.UP)
	# Godot's fov is vertical; the intent's 15-30 range is horizontal
	var aspect := 16.0 / 9.0
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_horizontal_deg) * 0.5) / aspect))
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
	sun.shadow_enabled = true
	add_child(sun)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = INDIGO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.65
	# poster colour on sculpture, not filmic realism (lab finding)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
