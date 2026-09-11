extends Node3D
## The culture × style sheet: three peoples down, four styles across, all at
## full condition. Slice 3 owns the condition axis; mixing them would confound
## the read.
##
## This sheet answers experiment S3 and nothing else: can you tell two
## civilizations apart, and is the difference in massing and silhouette rather
## than colour?
##
## `uniform_palette` is the control. Rendering every culture through one
## palette holds colour constant and leaves only geometry — if the cultures are
## still tellable apart, the geometry is doing the work. Without that frame the
## sheet cannot distinguish expressing culture from tinting one.
##
## Per-cell scaling (see _add_cell) normalises away absolute height
## differences between cultures, so what this sheet compares is proportion and
## silhouette, never size.

@export var world_seed: int = 20260904
@export var building_id: int = 0
@export var cell_size: float = 5.0
@export var camera_pitch_deg: float = 34.0
@export var fov_horizontal_deg: float = 24.0
@export var frame_margin: float = 1.30

## Render every culture through lowland's palette — the control frame.
@export var uniform_palette: bool = false

## A cell's building is scaled to this fraction of a cell.
const CELL_HEIGHT := 0.44

## How far captions float above the stage, so the billboard's lower half
## clears the pad it would otherwise sink into.
const CAPTION_Y := 0.9

@export var rebuild: bool = false:
	set(v):
		rebuild = false
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Vertex colours are LINEAR; albedo_color is sRGB. Mixing them silently
	# double-corrects and the sheet comes back washed out.
	mat.vertex_color_is_srgb = false
	var rows := DioramaCulture.NAMES.size()
	var cols := DioramaStyles.NAMES.size()
	var tallest := 0.0
	for r in range(rows):
		for c in range(cols):
			var at := Vector3((c - (cols - 1) * 0.5) * cell_size, 0.0,
					(r - (rows - 1) * 0.5) * cell_size)
			tallest = maxf(tallest, _add_cell(r, c, at, mat))
	_add_stage(rows, cols, mat)
	for c in range(cols):
		_add_caption(DioramaStyles.NAMES[c], Vector3(
				(c - (cols - 1) * 0.5) * cell_size, CAPTION_Y,
				(rows * 0.5 + 0.1) * cell_size))
	for r in range(rows):
		_add_caption(DioramaCulture.NAMES[r], Vector3(
				-(cols * 0.5 + 0.66) * cell_size, CAPTION_Y,
				(r - (rows - 1) * 0.5) * cell_size))
	_add_camera(rows, cols, tallest)
	_add_light()


## Returns the cell's highest point after scaling, so the camera frames what is
## actually there rather than a constant that goes stale.
func _add_cell(r: int, c: int, at: Vector3,
		mat: StandardMaterial3D) -> float:
	var culture := DioramaCulture.for_name(DioramaCulture.NAMES[r])
	var style: String = DioramaStyles.NAMES[c]
	var parts := DioramaCompose.build(DioramaStyles.for_name(style),
			world_seed, building_id, culture)
	DioramaCompose.apply_culture(parts,
			DioramaCulture.lowland() if uniform_palette else culture)
	var top := _top_of(parts)
	# Scaled per CELL, not per row: a highland tower and a delta hall differ in
	# height by design, and the sheet is comparing their shapes, not their
	# sizes. Normalising per cell is what lets silhouette be the variable.
	var scale := 1.0 if top <= 0.001 else (cell_size * CELL_HEIGHT) / top
	var b := DioramaMeshKit.new()
	DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
	var inst := MeshInstance3D.new()
	inst.name = "Cell_%s_%s" % [DioramaCulture.NAMES[r], style]
	inst.mesh = b.commit()
	inst.material_override = mat
	inst.position = at
	inst.scale = Vector3.ONE * scale
	add_child(inst)
	return at.y + top * scale


## Highest point of a part list, in the building's own space.
static func _top_of(parts: Array) -> float:
	var top := 0.0
	for p: Dictionary in parts:
		# A primitive builds UPWARD from its own origin, so its top is the
		# origin plus its own height. Height is DioramaCompose.part_height —
		# the same measurement _finish() uses to stamp `y` — not a second copy
		# of the size/height/dome match: a second copy is exactly how the
		# dome case (radius * squash; see add_dome / _dome_pt in mesh_kit.gd)
		# went missing from condition_sheet.gd's own copy of this helper while
		# it got fixed here, and how it went missing from compose.gd's `y`
		# entirely — every dome-crowned culture's true height was undercounted
		# there too, silently, because nothing asserted the params shape.
		top = maxf(top, p["xf"].origin.y + DioramaCompose.part_height(p))
	return top


## The pad's TOP sits at y = 0, because add_box builds upward from its origin
## and every building stands on the plane.
func _add_stage(rows: int, cols: int, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.45 * cell_size, -0.24, 0)),
			Vector3((cols + 2.3) * cell_size, 0.24, (rows + 1.0) * cell_size),
			Color(0.26, 0.25, 0.23))
	var inst := MeshInstance3D.new()
	inst.name = "Stage"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)


func _add_caption(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Caption_%s" % text
	label.text = text
	label.font_size = 160
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	add_child(label)


func _add_camera(rows: int, cols: int, tallest: float) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	# Godot's Camera3D.fov is the VERTICAL angle under the default
	# KEEP_HEIGHT, so solving a HORIZONTAL span against it overshoots by the
	# viewport aspect — about 1.8x at 16:9. Say which axis we mean.
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = fov_horizontal_deg
	var half_fov := deg_to_rad(fov_horizontal_deg) * 0.5
	var aspect := 16.0 / 9.0
	var wide := (cols + 2.3) * cell_size
	var deep := (rows + 1.0) * cell_size
	var pitch := deg_to_rad(camera_pitch_deg)
	var high := deep * sin(pitch) + tallest * cos(pitch)
	var dist := maxf(
			(wide * 0.5) / tan(half_fov),
			(high * 0.5) / (tan(half_fov) / aspect)) * frame_margin
	cam.position = Vector3(0, sin(pitch) * dist + tallest * 0.5,
			cos(pitch) * dist)
	# look_at() resolves via the node's global transform, so add_child first.
	add_child(cam)
	cam.look_at(Vector3(0, tallest * 0.3, 0), Vector3.UP)
	cam.current = true


## Ambient stands in for the diffuse bounce Forward+ has no GI to provide, and
## is tinted with ground albedo rather than sky. Environment colours are sRGB.
func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46, -132, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.58, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.44, 0.40)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
