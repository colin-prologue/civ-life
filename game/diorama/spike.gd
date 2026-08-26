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
## Aim at the hero structure instead of the valley centre. The hero exists to
## break the scale hierarchy, and that claim is only reviewable from a
## framing that actually contains it.
@export var camera_focus_hero: bool = false

@export_group("Light")
## Matched to the lab's diorama sheet (build.py: elevation 26, azimuth 205).
@export var sun_elevation_deg: float = 26.0
@export var sun_azimuth_deg: float = 205.0
## Sun and ambient were fitted, not guessed: rendered against the lab's own
## diorama sheet (build.py --experiment diorama --seed 421) and scored on the
## luminance distribution of the model. At these values Godot lands
## p05/p50/p95 = 0.133/0.324/0.536 against the sheet's 0.121/0.359/0.495, and
## the dominant colour families agree to within a couple of 8-bit steps.
## Blender's 4.5 W/m2 and Godot's energy multiplier are not the same unit, so
## what carries across is the ratio and the resulting values, not the numbers.
@export var sun_energy: float = 1.0
## Ambient is doing a specific job: standing in for the diffuse bounce that
## Cycles has and Forward+ does not. The lab's sheet uses no fill light, yet
## its shadows stay open and green because light bounces off a large bright
## ground. Set this to zero and the shadows crush; set it high and the model
## goes flat. See _build_environment().
@export var ambient_energy: float = 0.45
@export_group("Shadow")
## Godot's DirectionalLight3D defaults (bias 0.1, normal_bias 2.0) are sized
## for human-scale scenes. This diorama is ~26x24 units with sub-unit
## buildings, so the defaults are larger than the things casting — they erase
## small shadows outright. Too small instead and the faceted terrain acnes
## badly. These are the smallest values that clear the acne (measured as
## high-frequency neighbour difference, which plateaus here) while keeping
## shadows attached to trees and buildings.
@export var shadow_bias: float = 0.06
@export var shadow_normal_bias: float = 0.4
@export var shadow_max_distance: float = 120.0
@export var shadow_enabled: bool = true

@export var rebuild: bool = false:
	set(_v):
		_build()

## Geometry fingerprints of the last build, for determinism tests.
var last_fingerprints: Dictionary = {}
## Wall-clock cost of the last _build(), whole and by phase (AC10). The spike
## fails its purpose if iteration is painful, so this is reported, not hidden.
var last_build_ms: float = 0.0
var last_phase_ms: Dictionary = {}


func _ready() -> void:
	_build()


func _build() -> void:
	var t_start := Time.get_ticks_usec()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	last_fingerprints.clear()
	last_phase_ms.clear()

	var valley := SynthValley.new(world_seed)
	_mark("synth", t_start)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Vertex colours are linear (DioramaPalette hands us linear); saying so
	# explicitly documents the choice and survives a Godot default change.
	mat.vertex_color_is_srgb = false
	mat.roughness = 0.92

	var t := Time.get_ticks_usec()
	_build_terrain(valley, mat)
	t = _mark("terrain", t)
	_build_water(valley)
	t = _mark("water", t)
	_build_settlement(valley, mat)
	t = _mark("settlement", t)
	_build_trees(valley, mat)
	t = _mark("trees", t)
	_build_camera(valley)
	_build_light()
	_build_environment()
	_mark("stage", t)
	last_build_ms = (Time.get_ticks_usec() - t_start) / 1000.0


## Record elapsed ms since `since`, returning now — so phases chain.
func _mark(phase: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	last_phase_ms[phase] = (now - since) / 1000.0
	return now


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
		b.add_quad(quad[0], quad[1], quad[2], quad[3], DioramaPalette.col("plaster2"))
	# farm strips beside the road's southern approach
	var f0 := valley.road[4]
	for i in range(5):
		var fx := f0.x - 1.6 - i * 0.5
		var fz := f0.y
		var xf := Transform3D(Basis.IDENTITY,
				Vector3(fx, _height(valley, fx, fz) + 0.02, fz))
		b.add_box(xf, Vector3(0.34, 0.05, 2.4),
				DioramaPalette.col("ochre") if i % 2 == 1 else DioramaPalette.col("plaster2"))
	var inst := MeshInstance3D.new()
	inst.name = "Terrain"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)
	last_fingerprints["terrain"] = b.fingerprint()


func _ground_color(valley: SynthValley, x: float, z: float) -> Color:
	match valley.terrain_at(x, z):
		SynthValley.Terrain.WATER:
			return DioramaPalette.col("moss2")      # river bed; the water plane covers it
		SynthValley.Terrain.FOREST:
			return DioramaPalette.col("moss2")
		SynthValley.Terrain.HILL:
			return DioramaPalette.col("hilltint")
		SynthValley.Terrain.MOUNTAIN:
			return DioramaPalette.col("stone")
		_:
			return DioramaPalette.col("moss")
	return DioramaPalette.col("moss")


func _build_water(valley: SynthValley) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(valley.extent.x + 2.0, valley.extent.y + 2.0)
	var inst := MeshInstance3D.new()
	inst.name = "Water"
	inst.mesh = plane
	inst.position = Vector3(valley.extent.x * 0.5, -0.10, valley.extent.y * 0.5)
	var mat := StandardMaterial3D.new()
	# albedo_color is sRGB, unlike everything else here — see DioramaPalette.
	mat.albedo_color = DioramaPalette.srgb("water")
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
	b.add_prism(Transform3D.IDENTITY, 0.05, 0.22, DioramaPalette.col("wood"), 5, 0.2)
	var y := 0.18
	for t in range(3):
		var xf := Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
		b.add_cone(xf, 0.30 - t * 0.07, 0.5 - t * 0.08,
				DioramaPalette.col("moss2") if t % 2 == 0 else DioramaPalette.col("moss"), 7)
		y += 0.26
	return b.commit()


func _tree_mesh_broadleaf() -> ArrayMesh:
	var b := DioramaMeshKit.new()
	b.add_prism(Transform3D.IDENTITY, 0.05, 0.38, DioramaPalette.col("wood"), 5, 0.2)
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, 0.52, 0)), 0.30, 0.75, DioramaPalette.col("moss"))
	b.add_blob(Transform3D(Basis.IDENTITY, Vector3(0.16, 0.44, 0.10)), 0.20, 0.7,
			DioramaPalette.col("moss2"))
	return b.commit()


func _build_camera(valley: SynthValley) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	# The hero is the one thing in the scene whose scale is the point, so it
	# gets its own framing rather than being whatever lands near the valley
	# centre. AC12(d) wants a shot where it dominates; without this the camera
	# always looks at the middle of the slab and crops the arch off the top.
	var target := Vector3(valley.extent.x * 0.5, 0.4, valley.extent.y * 0.5)
	if camera_focus_hero:
		target = Vector3(valley.hero_site.x, _height(valley, valley.hero_site.x,
				valley.hero_site.y) + 2.0, valley.hero_site.y)
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
	sun.shadow_enabled = shadow_enabled
	# Scene-scale shadow tuning. Left at Godot's defaults these values are
	# bigger than the buildings, and small casters lose their shadows entirely.
	sun.shadow_bias = shadow_bias
	sun.shadow_normal_bias = shadow_normal_bias
	sun.directional_shadow_max_distance = shadow_max_distance
	add_child(sun)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DioramaPalette.srgb("indigo")
	# Ambient is standing in for something specific: Cycles' diffuse bounce.
	# The lab's diorama sheet has no fill light, but its shadows are still open
	# and green, because light bounces off a large bright ground plane. Godot's
	# Forward+ has no GI, so if ambient is set to the near-black sky the
	# shadows crush to nothing and the value range comes out roughly twice the
	# reference's. Tinting ambient with the dominant ground albedo is the
	# cheapest honest approximation of that bounce.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = DioramaPalette.srgb("moss")
	env.ambient_light_energy = ambient_energy
	# Without this, ambient_light_color does nothing: sky_contribution defaults
	# to 1.0, which blends the explicit colour entirely out in favour of a sky
	# this scene does not have. Costs an afternoon to notice, because the knob
	# still moves and the picture still changes for other reasons.
	env.ambient_light_sky_contribution = 0.0
	# poster colour on sculpture, not filmic realism (lab finding)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
