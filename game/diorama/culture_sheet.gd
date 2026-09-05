extends Node3D
## The style × culture sheet: every style down one axis, both cultures across
## the other, one camera and one light.
##
## This is the frame the slice exists to produce, and its whole argument rests
## on one property: a ROW IS ONE BUILDING. The style, the seed and the building
## id are all held fixed across a row, so the two cells differ in nothing but
## which palette resolved their roles. Vary the id across the row as well and
## the sheet would show two different buildings in two palettes, which proves
## nothing about culture and would flatter it besides.
##
## That is also what makes the sheet answer the question honestly rather than
## favourably. Whatever difference a reader sees here is the ENTIRE difference a
## culture makes today. If it reads as one building painted twice, that is the
## finding, not a failure of the capture — see
## docs/superpowers/findings/2026-09-04-culture-style-parameters.md.
##
## A sibling of condition_sheet.tscn rather than a mode inside it, on the same
## reasoning that scene gives for not being a mode inside lineup.tscn: the two
## sheets share a stage, a camera solve and a light, and differ in what a column
## means. Folding them together costs a flag and two paths through the cell
## builder.

@export var world_seed: int = 20260826

## Which building id each style's row shows, in DioramaStyles.NAMES order.
##
## `hero_arch` uses id 8 for the same reason condition_sheet.gd does — it is the
## id whose arc survives — and the rest use 0. The choice matters less here than
## on the condition sheet, because both cells of a row draw the same id by
## construction, so no id can make the two cultures look more different than
## they are.
@export var row_ids: Array[int] = [8, 0, 0, 0]
@export var cell_size: float = 5.0
@export var camera_pitch_deg: float = 34.0
@export var fov_horizontal_deg: float = 24.0

## Slack around the solved fit. Exactly 1.0 puts the pad edges on the frame
## edge, which reads as cropped even when nothing is actually cut.
@export var frame_margin: float = 1.30

## A row's building is scaled to this fraction of a cell.
const ROW_HEIGHT := 0.44

## How far captions float above the stage, in world units.
const CAPTION_Y := 0.9

## The left gutter that holds the style names, in cells, and the margin of pad
## left around everything, also in cells.
##
## These are stated as a LAYOUT rather than inherited from condition_sheet.gd's
## "(cols + 2.3) * cell_size" because that expression is only right at five
## columns. At two it reserves more than a full sheet's width of empty pad and
## then centres the camera on the middle of the emptiness, so the buildings sit
## crowded against one edge of the frame — which is how the first capture of
## this sheet came back. Width now follows from where things actually are.
const LABEL_GUTTER := 1.15
const PAD_MARGIN := 0.62

@export var rebuild: bool = false:
	set(v):
		rebuild = false
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		# Detach before queuing: queue_free() defers deletion to end of frame,
		# so a rebuild's same-named replacements would be auto-renamed while the
		# old nodes linger, breaking name lookups afterwards.
		remove_child(child)
		child.queue_free()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Vertex colours are LINEAR; albedo_color is sRGB. Mixing them silently
	# double-corrects and the sheet comes back washed out.
	mat.vertex_color_is_srgb = false
	var rows := DioramaStyles.NAMES.size()
	var cols := DioramaCultures.NAMES.size()
	var tallest := 0.0
	for r in range(rows):
		# One scale per ROW, measured from that style's own building, so every
		# style reads at a comparable size. Measured rather than tabulated: a
		# constant per style goes stale the moment a style is re-authored.
		#
		# Both cells of a row share it, which costs nothing here — they are the
		# same geometry — but says the right thing if a culture ever does change
		# massing, because then the row would show the size difference instead
		# of normalising it away.
		var scale := _row_scale(r)
		for c in range(cols):
			var at := Vector3(_col_x(c, cols), 0.0,
					(r - (rows - 1) * 0.5) * cell_size)
			tallest = maxf(tallest, _add_cell(r, c, at, scale, mat))
	_add_stage(rows, cols, mat)
	for c in range(cols):
		_add_caption(DioramaCultures.NAMES[c], Vector3(
				_col_x(c, cols), CAPTION_Y,
				(rows * 0.5 + 0.1) * cell_size))
	for r in range(rows):
		_add_caption(DioramaStyles.NAMES[r], Vector3(
				_col_x(0, cols) - LABEL_GUTTER * cell_size, CAPTION_Y,
				(r - (rows - 1) * 0.5) * cell_size))
	_add_camera(rows, cols, tallest)
	_add_light()


## Where a culture's column stands. Columns straddle x = 0; the row labels hang
## off to the left of them, which is what pulls the sheet's centre of gravity
## away from the origin and why _span() exists.
func _col_x(c: int, cols: int) -> float:
	return (c - (cols - 1) * 0.5) * cell_size


## The horizontal band the sheet actually occupies: from the far side of the
## style labels to the far side of the last column, plus a margin. Returned as
## [centre, width] because both the stage and the camera need exactly that, and
## deriving it twice is how the two drift apart.
func _span(cols: int) -> Array:
	var left := _col_x(0, cols) - (LABEL_GUTTER + PAD_MARGIN) * cell_size
	var right := _col_x(cols - 1, cols) + PAD_MARGIN * cell_size
	return [(left + right) * 0.5, right - left]


## Falls back to the row index when row_ids is short, so adding a style to
## DioramaStyles.NAMES cannot silently shift every other row's building.
func _id_for(r: int) -> int:
	return row_ids[r] if r < row_ids.size() else r


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
		var prm: Dictionary = p["params"]
		var h: float = prm["size"].y if prm.has("size") else prm.get("height", 0.0)
		top = maxf(top, p["xf"].origin.y + h)
	return top


## The cell. build() is called per cell rather than once per row and painted
## twice, deliberately: it is the stronger claim. If two independent builds of
## the same style, seed and id came out differing in anything but colour, this
## sheet would show it as a geometric difference between the two columns, and
## the reader would catch a determinism break by looking.
func _add_cell(r: int, c: int, at: Vector3, scale: float,
		mat: StandardMaterial3D) -> float:
	var style: String = DioramaStyles.NAMES[r]
	var culture: String = DioramaCultures.NAMES[c]
	var parts := DioramaCompose.build(DioramaStyles.for_name(style),
			world_seed, _id_for(r))
	DioramaCompose.apply_roles(parts, DioramaCultures.palette(culture))
	var b := DioramaMeshKit.new()
	DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
	var inst := MeshInstance3D.new()
	inst.name = "Cell_%s_%s" % [style, culture]
	inst.mesh = b.commit()
	inst.material_override = mat
	inst.position = at
	inst.scale = Vector3.ONE * scale
	add_child(inst)
	return at.y + _top_of(parts) * scale


## The pad's TOP sits at y = 0, because add_box builds upward from its origin
## and every building stands on the plane.
##
## Its own colour is deliberately NOT a role. The stage is apparatus, not
## architecture — painting it from a culture's palette would make the two
## columns sit on different ground and hand the sheet a difference that is not
## the buildings'.
func _add_stage(rows: int, cols: int, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var span := _span(cols)
	var d := (rows + 1.0) * cell_size
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(span[0], -0.24, 0)),
			Vector3(span[1], 0.24, d), Color(0.26, 0.25, 0.23))
	var inst := MeshInstance3D.new()
	inst.name = "Stage"
	inst.mesh = b.commit()
	inst.material_override = mat
	add_child(inst)


## Captions sit ABOVE the stage surface. A billboard quad is centred on its
## position, so a label at y=0.02 has half its height buried in the pad.
func _add_caption(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Caption_%s" % text
	label.text = text
	label.font_size = 160
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
	# Godot's Camera3D.fov is the VERTICAL angle under the default KEEP_HEIGHT,
	# so solving a HORIZONTAL span against it overshoots by the viewport aspect.
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = fov_horizontal_deg
	var half_fov := deg_to_rad(fov_horizontal_deg) * 0.5
	var aspect := 16.0 / 9.0
	var span := _span(cols)
	var deep := (rows + 1.0) * cell_size
	var pitch := deg_to_rad(camera_pitch_deg)
	# What the depth and the tallest building occupy vertically once tilted.
	var high := deep * sin(pitch) + tallest * cos(pitch)
	var dist := maxf(
			(span[1] * 0.5) / tan(half_fov),
			(high * 0.5) / (tan(half_fov) / aspect)) * frame_margin
	# Offset onto the sheet's own centre, not the origin. The columns straddle
	# zero but the row labels do not, so a camera on the origin frames the pad
	# and leaves the buildings off to one side.
	cam.position = Vector3(span[0], sin(pitch) * dist + tallest * 0.5,
			cos(pitch) * dist)
	# look_at() resolves via the node's global transform, so it must already be
	# inside the tree — add_child comes first or this throws.
	add_child(cam)
	cam.look_at(Vector3(span[0], tallest * 0.3, 0), Vector3.UP)
	cam.current = true


## The same sun and ambient the condition sheet stands under, and the same
## numbers DioramaCultures runs its lit and shadowed variants against. That
## correspondence is the point: the value check would be asserting a property
## of lighting this sheet does not use if they drifted apart.
func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46, -132, 0)
	sun.light_energy = DioramaCultures.SUN_ENERGY
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.58, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = DioramaCultures.AMBIENT_TINT
	e.ambient_light_energy = DioramaCultures.AMBIENT_ENERGY
	env.environment = e
	add_child(env)
