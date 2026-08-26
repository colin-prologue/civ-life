@tool
class_name DioramaLineup
extends Node3D
## A contact sheet of buildings, as a scene.
##
##   ./capture.sh --scene res://game/diorama/lineup.tscn \
##       --label residential-seeds --name building-lineup
##
## Specimens are staged on a neutral grid rather than dropped into the valley,
## because comparing buildings in situ confounds the building with where it
## landed — terrain, occlusion, neighbours and distance all vary at once.
##
## The corresponding limitation, worth remembering before trusting a sheet: a
## neutral pad flatters things. A silhouette that reads here can still vanish
## at diorama distance behind two trees, so a style is chosen on this sheet and
## CONFIRMED in the valley.

@export var world_seed: int = 20260826
@export var specimen_count: int = 12
@export var columns: int = 4
@export var cell_size: float = 4.5
@export var camera_pitch_deg: float = 34.0
@export var fov_horizontal_deg: float = 24.0

@export var rebuild: bool = false:
	set(_v):
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92

	var rows := int(ceil(float(specimen_count) / float(maxi(1, columns))))
	var tallest := 0.0
	for i in range(specimen_count):
		var col := i % columns
		var row := i / columns
		var at := Vector3((col - (columns - 1) * 0.5) * cell_size, 0.0,
				(row - (rows - 1) * 0.5) * cell_size)
		tallest = maxf(tallest, _add_specimen(i, at, mat))
		_add_caption(i, at)

	_add_stage(rows, mat)
	_add_camera(rows, tallest)
	_add_light()
	_add_environment()


## Returns the specimen's highest point above the stage (xf.origin.y + its own
## height), so _add_camera can frame the tallest building in the batch instead
## of guessing a constant that goes stale the moment a style's proportions
## change.
func _add_specimen(i: int, at: Vector3, mat: StandardMaterial3D) -> float:
	var parts := DioramaCompose.build(DioramaStyles.residential(), world_seed, i)
	DioramaCompose.apply_roles(parts, DioramaStyles.ROLES)
	var b := DioramaMeshKit.new()
	DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
	var inst := MeshInstance3D.new()
	inst.name = "Specimen%d" % i
	inst.mesh = b.commit()
	inst.material_override = mat
	inst.position = at
	add_child(inst)
	var top := 0.0
	for p: Dictionary in parts:
		var params: Dictionary = p["params"]
		var h: float = params["size"].y if params.has("size") else params.get("height", 0.0)
		top = maxf(top, p["xf"].origin.y + h)
	return top


## Above the stage, not below it: _add_stage builds its pad from local y in
## [0, 0.2] at xf.origin.y = -0.2, so the pad's TOP is world y = 0.0 — a
## negative y here sits under that opaque geometry and never reaches the
## camera at all.
##
## 0.05 clears the pad but is not enough on its own: at this camera's shallow
## pitch, a caption at near-ground height and a row behind its own specimen is
## still hidden behind the ROOF of whichever specimen sits one row closer to
## the camera in the same column — verified by ray-tracing camera-to-caption
## against each neighbour's roof height, which is what set 0.45 rather than a
## rounder-looking guess: the tallest roof in this batch needs about 0.36 to
## clear, and 0.45 keeps a working margin.
##
## font_size 96 at pixel_size 0.002 is 0.192 world units tall — legible up
## close, but at the ~55-unit camera distance this sheet needs to fit all
## twelve specimens that is roughly 10 screen pixels, effectively unreadable.
## Doubled rather than just widening pixel_size, so the source glyph texture
## gets crisper along with the text getting bigger instead of the same
## texture stretched further.
func _add_caption(i: int, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Caption%d" % i
	label.text = "seed %d" % i
	label.font_size = 192
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at + Vector3(0, 0.45, cell_size * 0.35)
	add_child(label)


## A single pad under everything, so specimens cast shadows onto something and
## silhouettes read against a consistent value.
func _add_stage(rows: int, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var w := columns * cell_size
	var d := rows * cell_size
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)),
			Vector3(w + cell_size, 0.2, d + cell_size),
			Color(0.812, 0.776, 0.682))
	var inst := MeshInstance3D.new()
	inst.name = "Stage"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)


## Distance derived from the frustum rather than a guessed constant, which is
## what left the previous version wrong by construction: too close on the
## horizontal axis (clipping the outer columns) and too far on the vertical
## one (leaving the bottom of the frame mostly bare stage). Both axes are
## solved independently — "how far back until this half-extent fits inside
## this half-angle" — and the camera sits at whichever needs more room.
func _add_camera(rows: int, tallest: float) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	var pitch := deg_to_rad(camera_pitch_deg)
	var aspect := 16.0 / 9.0
	var h_half := deg_to_rad(fov_horizontal_deg) * 0.5
	var v_half := atan(tan(h_half) / aspect)
	cam.fov = rad_to_deg(2.0 * v_half)

	# Matches _add_stage's actual footprint (columns/rows of cells plus one
	# cell of margin on each axis), not an arbitrary span.
	var stage_w := columns * cell_size + cell_size
	var stage_d := rows * cell_size + cell_size
	var dist_h := (stage_w * 0.5) / tan(h_half)
	# The stage recedes away from the camera at this pitch, so its far edge's
	# on-screen extent foreshortens by sin(pitch), and the tallest specimen's
	# silhouette foreshortens by cos(pitch) rather than adding in full. That
	# full extent is symmetric about the view centre (half in front, half
	# behind), so it is HALF of it that has to fit inside the vertical
	# half-angle — feeding the whole extent to a half-angle constraint is what
	# over-reached and left margin on every side of the previous capture.
	var vertical_extent := stage_d * sin(pitch) + tallest * cos(pitch)
	var dist_v := (vertical_extent * 0.5) / tan(v_half)
	var dist := maxf(dist_h, dist_v) * 1.05

	cam.position = Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.basis = Basis.looking_at(-cam.position, Vector3.UP)
	add_child(cam)
	if not Engine.is_editor_hint():
		cam.make_current()


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(Vector3(0.38, -0.55, -0.74), Vector3.UP)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	# Scene-scale, like the diorama's: Godot's defaults are larger than these
	# buildings and would erase their shadows outright.
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.2
	add_child(sun)


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.071, 0.078, 0.110)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.494, 0.545, 0.667)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
