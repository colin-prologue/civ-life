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
@export var camera_pitch_deg: float = 24.0
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
	for i in range(specimen_count):
		var col := i % columns
		var row := i / columns
		var at := Vector3((col - (columns - 1) * 0.5) * cell_size, 0.0,
				(row - (rows - 1) * 0.5) * cell_size)
		_add_specimen(i, at, mat)
		_add_caption(i, at)

	_add_stage(rows, mat)
	_add_camera(rows)
	_add_light()
	_add_environment()


func _add_specimen(i: int, at: Vector3, mat: StandardMaterial3D) -> void:
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


func _add_caption(i: int, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Caption%d" % i
	label.text = "seed %d" % i
	label.font_size = 96
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at + Vector3(0, -0.25, cell_size * 0.35)
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


func _add_camera(rows: int) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	var span := maxf(columns * cell_size, rows * cell_size)
	var dist := span * 2.1
	var pitch := deg_to_rad(camera_pitch_deg)
	cam.position = Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.basis = Basis.looking_at(-cam.position, Vector3.UP)
	var aspect := 16.0 / 9.0
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_horizontal_deg) * 0.5)
			/ aspect))
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
