extends Node3D
## The style × condition sheet: every style down one axis, the intent's five
## condition rungs across the other, one camera and one light.
##
## A row is ONE building decaying, not five buildings — the building id is held
## fixed across a row so the reader is watching the same structure lose parts.
## That is the only arrangement in which the ladder means anything.
##
## A sibling of lineup.tscn rather than a mode inside it: lineup varies one
## thing (building id) for one style, this varies two. One scene doing both
## needs a flag and two paths through the cell builder, which costs more than
## the stage and camera setup duplicated here.

@export var world_seed: int = 20260829

## Which building id each style's row shows, in DioramaStyles.NAMES order.
##
## The sheet shows ONE building per style, so this choice decides what the
## frame can demonstrate — and for `hero_arch` it decides it starkly. Its nine
## voussoirs are one cohesive level whose band is [0.42, 0.58], so at the 0.5
## rung the arc is a coin flip: ids 0, 1, 6, 7, 8 and 11 keep it standing while
## 2, 3, 4, 5, 9 and 10 lose it. The previous sheet used id = row index, drew
## id 3, and so could not show the one image this whole slice was built for.
##
## Chosen by a stated rule rather than by eye: the id whose five rungs produce
## the most DISTINCT survivor counts. That is picking a legible sample, not a
## flattering one — the variance above is real and is reported alongside the
## sheet rather than hidden by it.
@export var row_ids: Array[int] = [8, 0, 0, 0]
@export var cell_size: float = 5.0
@export var camera_pitch_deg: float = 34.0
@export var fov_horizontal_deg: float = 24.0

## Slack around the solved fit. Exactly 1.0 puts the pad edges on the frame
## edge, which reads as cropped even when nothing is actually cut.
@export var frame_margin: float = 1.30

## The intent's five named rungs: complete, aging, upper masses gone,
## structural remnants, footprint and a survivor.
const RUNGS := [1.0, 0.75, 0.5, 0.25, 0.05]

## A row's complete building is scaled to this fraction of a cell. Under ~0.5 the
## styles read as models on a table; over ~0.7 tall rows start clipping the row
## behind them at this pitch.
const ROW_HEIGHT := 0.44

## How far captions float above the stage, in world units. Enough that the
## billboard's lower half clears the pad it would otherwise sink into.
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
	var rows := DioramaStyles.NAMES.size()
	var cols := RUNGS.size()
	var tallest := 0.0
	for r in range(rows):
		# One scale per ROW, measured from that style's complete building, so
		# every style reads at a comparable size on the sheet. Without it the
		# hero arch (5.6 units) dwarfs a single-unit residential (1.5) and the
		# top row is an unreadable speck.
		#
		# Measured rather than tabulated: a constant per style goes stale the
		# moment a style's proportions are re-authored, which is the whole
		# point of a vocabulary meant to be thrashed on.
		#
		# The SAME scale applies to every cell in the row, so decay still reads
		# as real shrinkage across the row rather than being normalised away.
		var scale := _row_scale(r)
		for c in range(cols):
			var at := Vector3((c - (cols - 1) * 0.5) * cell_size, 0.0,
					(r - (rows - 1) * 0.5) * cell_size)
			tallest = maxf(tallest, _add_cell(r, c, at, scale, mat))
	_add_stage(rows, cols, mat)
	# Captions float CLEAR of the pad. A billboard quad is centred on its
	# position, so a label at y=0.02 has half its height below the stage
	# surface and the pad clips it — which is exactly how the first sheet came
	# back with its legend sunk into the plane.
	for c in range(cols):
		_add_caption("%.2f" % RUNGS[c], Vector3(
				(c - (cols - 1) * 0.5) * cell_size, CAPTION_Y,
				(rows * 0.5 + 0.1) * cell_size))
	for r in range(rows):
		_add_caption(DioramaStyles.NAMES[r], Vector3(
				-(cols * 0.5 + 0.66) * cell_size, CAPTION_Y,
				(r - (rows - 1) * 0.5) * cell_size))
	_add_camera(rows, cols, tallest)
	_add_light()


## Falls back to the row index when row_ids is short, so adding a style to
## DioramaStyles.NAMES cannot silently shift every other row's building.
func _id_for(r: int) -> int:
	return row_ids[r] if r < row_ids.size() else r


## How much to shrink or grow this row so its complete building reads at the
## same size as every other style's.
func _row_scale(r: int) -> float:
	var style: String = DioramaStyles.NAMES[r]
	var whole := DioramaCompose.build(DioramaStyles.for_name(style),
			world_seed, _id_for(r))
	var top := _top_of(whole)
	return 1.0 if top <= 0.001 else (cell_size * ROW_HEIGHT) / top


## Highest point of a part list, in the building's own space.
static func _top_of(parts: Array) -> float:
	var top := 0.0
	for p: Dictionary in parts:
		# A primitive builds UPWARD from its own origin, so its top is the
		# origin plus its own height. Height lives under `size.y` for boxes and
		# `height` for the round kinds, the same split _params_for writes.
		var prm: Dictionary = p["params"]
		var h: float = prm["size"].y if prm.has("size") else prm.get("height", 0.0)
		top = maxf(top, p["xf"].origin.y + h)
	return top


func _add_cell(r: int, c: int, at: Vector3, scale: float,
		mat: StandardMaterial3D) -> float:
	var style: String = DioramaStyles.NAMES[r]
	# The id is the ROW, not the cell: every cell in a row is the same building
	# at a different condition.
	var parts := DioramaCompose.build(DioramaStyles.for_name(style),
			world_seed, _id_for(r))
	var survivors := DioramaCondition.filter(parts, RUNGS[c])
	DioramaCompose.apply_roles(survivors, DioramaStyles.ROLES)
	var b := DioramaMeshKit.new()
	DioramaGrammar.emit(b, survivors, Transform3D.IDENTITY)
	var inst := MeshInstance3D.new()
	inst.name = "Cell_%s_%d" % [style, c]
	inst.mesh = b.commit()
	inst.material_override = mat
	inst.position = at
	inst.scale = Vector3.ONE * scale
	add_child(inst)
	return at.y + _top_of(survivors) * scale


## The pad's TOP sits at y = 0, because add_box builds upward from its origin
## and every building stands on the plane. A pad centred on zero would bury
## the bottom of every specimen.
func _add_stage(rows: int, cols: int, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var w := (cols + 2.3) * cell_size
	var d := (rows + 1.0) * cell_size
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.45 * cell_size, -0.24, 0)),
			Vector3(w, 0.24, d), Color(0.26, 0.25, 0.23))
	var inst := MeshInstance3D.new()
	inst.name = "Stage"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)


## Captions sit ABOVE the stage surface, not below it. Labels at a negative y
## are occluded by the pad and the sheet comes back with no legend at all.
func _add_caption(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Caption_%s" % text
	label.text = text
	label.font_size = 160
	# Sized against the camera distance the frustum solve produces, not guessed:
	# at 0.004 the legend was roughly six screen pixels and unreadable.
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	add_child(label)


## Distance derived from the frustum rather than guessed as a multiple of the
## span — a constant has no relation to the FOV and goes wrong the moment
## either changes.
func _add_camera(rows: int, cols: int, tallest: float) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	# Godot's Camera3D.fov is the VERTICAL angle under the default
	# KEEP_HEIGHT, so solving a HORIZONTAL span against it overshoots by the
	# viewport aspect — about 1.8x at 16:9, which is why the first capture put
	# the whole sheet in the middle third of the frame. Say which axis we mean.
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = fov_horizontal_deg
	# Solve BOTH axes and take the greater distance. Fitting width alone put the
	# sheet's front and back rows outside the frame: the pad is deep as well as
	# wide, and a pitched camera projects that depth into screen height.
	var half_fov := deg_to_rad(fov_horizontal_deg) * 0.5
	var aspect := 16.0 / 9.0
	var wide := (cols + 2.3) * cell_size
	var deep := (rows + 1.0) * cell_size
	var pitch := deg_to_rad(camera_pitch_deg)
	# What the depth and the tallest building occupy vertically once tilted.
	var high := deep * sin(pitch) + tallest * cos(pitch)
	var dist := maxf(
			(wide * 0.5) / tan(half_fov),
			(high * 0.5) / (tan(half_fov) / aspect)) * frame_margin
	cam.position = Vector3(0, sin(pitch) * dist + tallest * 0.5,
			cos(pitch) * dist)
	# look_at() requires the node to already be inside the tree (it resolves
	# via the node's own global transform), so add_child must come first —
	# calling it before add_child throws "Node not inside tree".
	add_child(cam)
	cam.look_at(Vector3(0, tallest * 0.3, 0), Vector3.UP)
	cam.current = true


## Ambient stands in for the diffuse bounce Forward+ has no GI to provide, and
## is tinted with ground albedo rather than sky — that is what the Blender
## parity pass measured. Environment colours are sRGB.
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
