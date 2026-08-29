class_name DioramaCompose
extends RefCounted
## Resolves a style tree into the parts the diorama already renders.
##
## A style is data: nested dictionaries of node types, each keyed by its type
## name ("mass", "stack", "row"). resolve() folds that tree into a flat parts
## list plus a FRAME — the space the node occupies — and it is the frame that
## lets a parent place the next sibling without re-deriving arithmetic. That is
## the whole trick: `x += w * 0.95` and `y += tier_h` exist once here instead of
## once per recipe.
##
## Nothing in this file renders, touches the scene tree, or does I/O. It runs
## headless and must produce identical output in separate processes.

const FNV_OFFSET := 1469598103934665603
const FNV_PRIME := 1099511628211
const EPS := 1e-6

## The band a part's endurance is drawn from. `need` is the condition at or
## above which a part survives, so a LOW need is a DURABLE part. The band is
## deliberately short of [0, 1]: nothing is indestructible and nothing is
## made of paper, and the sheet is what tunes these.
const ENDURE_LO := 0.10
const ENDURE_HI := 0.90


## FNV-1a over a string. Godot's builtin hash() is deliberately NOT used: it
## carries no documented cross-platform stability guarantee, and this repo
## asserts that generation reproduces across separate processes. Mirrors the
## mixing already used by DioramaMeshKit.fingerprint().
static func str_hash(s: String) -> int:
	var acc := FNV_OFFSET
	for i in range(s.length()):
		acc = ((acc ^ s.unicode_at(i)) * FNV_PRIME) & 0x7FFFFFFFFFFFFFFF
	return acc


## A variation channel, keyed on the node's NAME PATH rather than its index
## path. The difference matters: with index paths, inserting one node shifts
## every sibling after it, so adding a porch rearranges the whole town. With
## names, adding "porch" leaves "tier1" untouched.
##
## Cost of that choice: renaming a node re-rolls its subtree. That is the right
## default — a rename is usually a redesign — but it surprises you once.
static func channel(seed: int, building_id: int, path: String,
		purpose: String) -> float:
	return DioramaHexKit.h01(seed, building_id, str_hash(path),
			str_hash(purpose))


## A proportion spec is a scalar (fixed), a two-element array (sampled), or
## absent (the caller's default).
static func sample(spec: Variant, seed: int, building_id: int, path: String,
		purpose: String, dflt: float) -> float:
	if spec == null:
		return dflt
	if spec is float or spec is int:
		return float(spec)
	assert(spec is Array, "'%s' on '%s' must be a number or [lo, hi]"
			% [purpose, path])
	assert(spec.size() == 2, "'%s' on '%s' must have exactly two bounds"
			% [purpose, path])
	var lo := float(spec[0])
	var hi := float(spec[1])
	# Not swapped silently: a reversed range is a typo, and quietly "fixing" it
	# hides the typo while changing what the style means.
	assert(lo <= hi, "'%s' on '%s' has lo > hi" % [purpose, path])
	return lo + (hi - lo) * channel(seed, building_id, path, purpose)


## `count` is inclusive integer bounds: a scalar is that exact count, and
## [lo, hi] means lo, lo+1, ..., hi with equal probability — so a style reads
## "[1, 3]" and means what it says, rather than "[1, 4.0]" meaning "1 to 3"
## because the sampler floors under the hood.
##
## floor, not round: round() would reach one past hi (round(2.99) is 3, but so
## is round(3.49)), so it is not the hi bound itself that needs reaching — it
## is that floor(c * span), scaled across span = hi - lo + 1 rather than
## hi - lo, lands exactly on hi when the channel value approaches 1 (which
## h01 never quite returns, so hi is a reachable outcome, not an asymptote,
## and nothing beyond it is ever produced).
static func _sample_count(spec: Variant, seed: int, id: int, path: String) -> int:
	if spec == null:
		return 1
	if spec is float or spec is int:
		return int(spec)
	assert(spec is Array, "'count' on '%s' must be a number or [lo, hi]" % path)
	assert(spec.size() == 2, "'count' on '%s' must have exactly two bounds" % path)
	var lo := int(spec[0])
	var hi := int(spec[1])
	assert(lo <= hi, "'count' on '%s' has lo > hi" % path)
	var span := hi - lo + 1
	var c := channel(seed, id, path, "count")
	return lo + int(floor(c * span))


static func seed_of(ctx: Dictionary) -> int:
	return ctx["seed"]


static func id_of(ctx: Dictionary) -> int:
	return ctx["id"]


static func zero_frame(xf: Transform3D) -> Dictionary:
	return {"xf": xf, "footprint": Vector2.ZERO, "height": 0.0}


static func new_ctx(seed: int, building_id: int) -> Dictionary:
	return {"seed": seed, "id": building_id, "path": "", "need_floor": 0.0,
			"frame": zero_frame(Transform3D.IDENTITY)}


## A node's own endurance, before the floor its support imposes.
static func _draw_need(ctx: Dictionary, path: String) -> float:
	return ENDURE_LO + (ENDURE_HI - ENDURE_LO) * channel(
			ctx["seed"], ctx["id"], path, "endure")


static func resolve(node: Dictionary, ctx: Dictionary) -> Dictionary:
	if node.has("mass"):
		return _mass(node["mass"], ctx)
	if node.has("stack"):
		return _stack(node["stack"], ctx)
	if node.has("row"):
		return _row(node["row"], ctx)
	if node.has("ring"):
		return _ring(node["ring"], ctx)
	assert(false, "unknown node type: %s" % str(node.keys()))
	return {"parts": [], "frame": zero_frame(ctx["frame"]["xf"]),
			"need": ctx["need_floor"]}


static func _path_of(ctx: Dictionary, n: Dictionary) -> String:
	var nm: String = n.get("name", "")
	assert(nm != "", "every node needs a name — channels are keyed on it")
	return nm if ctx["path"] == "" else ctx["path"] + "/" + nm


static func _mass(n: Dictionary, ctx: Dictionary) -> Dictionary:
	var path := _path_of(ctx, n)
	var seed: int = ctx["seed"]
	var id: int = ctx["id"]
	var xf: Transform3D = ctx["frame"]["xf"]
	var inherited: Vector2 = ctx["frame"]["footprint"]
	var oversize := sample(n.get("oversize"), seed, id, path, "oversize", 1.0)
	# A mass with no w/d takes the footprint it is standing on. That is how a
	# roof overhangs its body without restating the body's dimensions.
	var w := sample(n.get("w"), seed, id, path, "w", inherited.x) * oversize
	var d := sample(n.get("d"), seed, id, path, "d", inherited.y) * oversize
	var h := sample(n.get("h"), seed, id, path, "h", 0.0)
	# A node that emits nothing must not raise the floor for whatever stacks
	# above it — it reports the floor unchanged rather than a drawn need.
	if w <= EPS or d <= EPS or h <= EPS:
		return {"parts": [], "frame": zero_frame(xf), "need": ctx["need_floor"]}
	var kind: String = n.get("kind", "box")
	# A cone or prism is emitted as a circle of radius w/2 — `d` never reaches
	# the renderer. Reporting (w, d) would describe geometry that does not
	# exist, and everything stacking on this frame inherits the lie.
	if kind == "prism" or kind == "cone":
		d = w
	var params := _params_for(kind, n, w, d, h, seed, id, path)
	# A part never outlives the floor it inherits: whatever it stands on
	# already needs at least this much condition to still be there, so this
	# part cannot need less than that.
	var need := maxf(ctx["need_floor"], _draw_need(ctx, path))
	var part := {"kind": kind, "xf": xf, "params": params,
			"color": Color.MAGENTA, "need": need, "y": 0.0,
			"role": n.get("role", "plaster")}
	return {"parts": [part], "need": need,
			"frame": {"xf": xf, "footprint": Vector2(w, d), "height": h}}


## Maps a footprint and height onto whatever DioramaMeshKit's helper for this
## primitive expects. Round primitives take a radius from half the width.
static func _params_for(kind: String, n: Dictionary, w: float, d: float,
		h: float, seed: int, id: int, path: String) -> Dictionary:
	match kind:
		"box":
			return {"size": Vector3(w, h, d)}
		"tapered":
			return {"size": Vector3(w, h, d),
					"taper": sample(n.get("taper"), seed, id, path, "taper", 0.5)}
		"prism", "cone":
			return {"radius": w * 0.5, "height": h}
	assert(false, "unknown mass kind '%s' on '%s'" % [kind, path])
	return {}


## The union of what a node's children actually occupy, in the node's own local
## space. Both combinators need exactly this, and they had drifted apart on it
## four separate times — the frame origin, following a child's reported centre,
## skipping children that resolved to nothing, and what to report when NOTHING
## accumulated. Each was found in one and missed in the other, because they were
## written separately and each kept its own copy of the arithmetic. One
## accumulator, used by both, retires the whole class.
class Bounds:
	var lo := Vector2.INF
	var hi := -Vector2.INF

	## `centre` is where the child says it is; `footprint` is how much room it
	## takes. A child that resolved to nothing is simply never added.
	func add(centre: Vector2, footprint: Vector2) -> void:
		var half := footprint * 0.5
		lo = Vector2(minf(lo.x, centre.x - half.x),
				minf(lo.y, centre.y - half.y))
		hi = Vector2(maxf(hi.x, centre.x + half.x),
				maxf(hi.y, centre.y + half.y))

	## True when nothing was ever added — which is NOT the same as "the node had
	## no children". A node can declare several and have every one resolve away.
	func is_empty() -> bool:
		return lo.x == INF

	func span() -> Vector2:
		return Vector2.ZERO if is_empty() else hi - lo

	func mid() -> Vector2:
		return Vector2.ZERO if is_empty() else (lo + hi) * 0.5


## Children bottom-to-top. Each child is handed the frame of the one below it,
## which is both where it sits and the footprint it inherits if it declares
## none — so a roof can say "cover whatever I am on, 8% bigger".
static func _stack(n: Dictionary, ctx: Dictionary) -> Dictionary:
	var path := _path_of(ctx, n)
	var children: Array = n.get("children", [])
	_assert_unique_names(children, path)
	var base_xf: Transform3D = ctx["frame"]["xf"]
	var base_inv := base_xf.affine_inverse()
	var parts: Array = []
	var carried: Vector2 = ctx["frame"]["footprint"]
	var y := 0.0
	# Horizontal offset, in base-local space, of the thing the next child sits
	# on. Zero until a child reports a centre of its own.
	var centre := Vector2.ZERO
	var bounds := Bounds.new()
	# Each successive child inherits a footprint this much smaller than the one
	# below — a stepped monument's taper. It shrinks what a child INHERITS, not
	# what it declares, so a style can still break the taper deliberately by
	# stating a width.
	var setback := sample(n.get("setback"), seed_of(ctx), id_of(ctx), path,
			"setback", 0.0)
	# A part can never outlive what it rests on, so each child inherits the
	# need of the one below as a floor. Carrying that maximum down the loop IS
	# the load path — the vocabulary already says what rests on what, so no
	# style author states it.
	var running: float = ctx["need_floor"]
	for child in children:
		var child_ctx := {"seed": ctx["seed"], "id": ctx["id"], "path": path,
				"need_floor": running,
				"frame": {"xf": base_xf.translated_local(
						Vector3(centre.x, y, centre.y)),
						"footprint": carried, "height": 0.0}}
		var out := resolve(child, child_ctx)
		parts.append_array(out["parts"])
		# A child that resolved to nothing returns the floor it was handed
		# unchanged, so raising the running maximum here — before the height
		# check below — never lets a ghost part inflate what stacks above it.
		running = maxf(running, out["need"])
		var f: Dictionary = out["frame"]
		y += f["height"]
		if f["height"] > EPS:
			# A child may report a centre that is NOT the transform it was
			# handed — a row of unequal widths advancing by a fraction of each
			# width does not end up centred on where it started. Follow it, or
			# whatever stacks on top lands over the wrong place: correctly
			# sized, and hanging off one end.
			var child_xf: Transform3D = f["xf"]
			var local: Vector3 = base_inv * child_xf.origin
			centre = Vector2(local.x, local.z)
			bounds.add(centre, f["footprint"])
			carried = f["footprint"] * (1.0 - setback)
	if bounds.is_empty():
		return {"parts": parts, "frame": zero_frame(base_xf), "need": running}
	var mid := bounds.mid()
	return {"parts": parts, "need": running,
			"frame": {"xf": base_xf.translated_local(Vector3(mid.x, 0, mid.y)),
					"footprint": bounds.span(), "height": y}}


## Two siblings sharing a name would share every channel and come out
## identical. That is never the intent and is otherwise invisible — the
## buildings just look oddly repetitive.
static func _assert_unique_names(children: Array, path: String) -> void:
	var seen := {}
	for child: Dictionary in children:
		for type_key: String in child:
			var nm: String = child[type_key].get("name", "")
			assert(not seen.has(nm),
					"duplicate sibling name '%s' under '%s'" % [nm, path])
			seen[nm] = true


## Children along local X. `advance` scales the distance between the centres of
## two ADJACENT children — half of each one's width, not the preceding width
## alone:
##
##     centre-to-centre = (previous_width + this_width) / 2 * advance
##
## so 1.0 puts their edges exactly together, below 1.0 overlaps them by that
## fraction, and above 1.0 opens a gap. Widths 4 and 2 at `advance: 0.5` move
## their centres by 1.5, not by 2.0. A child that reports a centre away from
## where it was placed — any composite — is measured from its real edge, so the
## rule holds for nested rows as well as for plain masses.
##
## Scaling the preceding width alone is the older, wrong reading of this: it is
## only flush when neighbours happen to be the same size, and a style that
## samples each unit's width independently is never that. It shipped as visible
## gaps between houses that were supposed to be a terrace.
##
## Named `advance` and not `gap` on purpose: the value that reproduces the
## original terraced housing is 0.95, and calling that "a gap of 0.95" reads as
## a large separation when it is really a 5% overlap.
static func _row(n: Dictionary, ctx: Dictionary) -> Dictionary:
	var path := _path_of(ctx, n)
	var seed: int = ctx["seed"]
	var id: int = ctx["id"]
	var has_template := n.has("of")
	assert(not (has_template and n.has("children")),
			"'%s' has both 'count'/'of' and 'children' — pick one" % path)
	assert(not (n.has("count") and not has_template),
			"'%s' has 'count' without 'of' — count only repeats a template" % path)
	var children: Array = []
	if has_template:
		var count := _sample_count(n.get("count"), seed, id, path)
		for i in range(maxi(0, count)):
			children.append(_indexed(n["of"], i))
	else:
		children = n.get("children", [])
		_assert_unique_names(children, path)
	var base_xf: Transform3D = ctx["frame"]["xf"]
	var base_inv := base_xf.affine_inverse()
	# Two ways to space a row, and they answer different questions. `advance` is
	# a RATIO of the neighbours' half-widths, so spacing scales with whatever
	# the style sampled — right for a terrace. `gap` is an ABSOLUTE clear
	# distance between adjacent edges, which is the only way to state a real
	# dimension of the building: an arch's opening is a length, not a ratio, and
	# as a ratio it would come out as `w/t - 1` — derived from other sampled
	# dimensions and unwritable as a literal.
	assert(not (n.has("advance") and n.has("gap")),
			"'%s' has both 'advance' and 'gap' — pick one" % path)
	# A portico is a colonnade standing IN FRONT OF a hall: the same
	# side-by-side relationship, along depth instead of width.
	var is_z: bool = String(n.get("axis", "x")) == "z"
	assert(String(n.get("axis", "x")) in ["x", "z"],
			"'%s' row axis must be \"x\" or \"z\"" % path)
	var has_gap := n.has("gap")
	var advance := sample(n.get("advance"), seed, id, path, "advance", 1.0)
	var gap := sample(n.get("gap"), seed, id, path, "gap", 0.0)
	var parts: Array = []
	# DioramaMeshKit.add_box centres geometry in X (and Z), so a child's
	# xf.origin sits at ITS centre, not its near edge.
	var bounds := Bounds.new()
	var tallest := 0.0
	# Two passes, because placing a child flush against the one before it needs
	# BOTH their widths, and a child's width is only known once it is resolved.
	# Resolve every child at the row's own origin first, then lay them out.
	var resolved: Array = []
	for child in children:
		# Every child inherits the same, unchanged floor — a row does not carry
		# a running maximum down its children the way a stack does, because
		# siblings do not rest on one another. Each draws its own need against
		# only what the ROW itself was handed.
		var child_ctx := {"seed": seed, "id": id, "path": path,
				"need_floor": ctx["need_floor"],
				"frame": {"xf": base_xf,
						"footprint": ctx["frame"]["footprint"], "height": 0.0}}
		resolved.append(resolve(child, child_ctx))
	# Siblings stand beside one another, so one falling says nothing about the
	# next — but whatever rests on the ROW fails when any of them does.
	var need: float = ctx["need_floor"]
	for out: Dictionary in resolved:
		need = maxf(need, out["need"])
	var cursor := 0.0
	var prev_half := 0.0
	var prev_centre := 0.0     # previous child's centre, in ROW space
	var placed_any := false
	for out: Dictionary in resolved:
		var f: Dictionary = out["frame"]
		var fp: Vector2 = f["footprint"]
		var half: float = (fp.y if is_z else fp.x) * 0.5
		var child_xf: Transform3D = f["xf"]
		# Where the child says its centre is, relative to where it resolved.
		# For a mass that is zero; for a composite it need not be.
		var child_local: Vector3 = base_inv * child_xf.origin
		var offset: float = child_local.z if is_z else child_local.x
		if f["height"] > EPS:
			if placed_any:
				# Solve for the shift that puts this child's NEAR edge against
				# the previous child's FAR edge, in row space:
				#     (cursor + offset) - half == prev_centre + prev_half
				# scaled by advance, so 1.0 is flush and 0.95 overlaps by 5%.
				# Stepping by widths alone is only correct when every child's
				# centre coincides with where it was placed, which composites
				# break — a nested row of unequal widths reports a centre off
				# its own origin, and the next child then overlaps it.
				cursor = prev_centre - offset + (
						(prev_half + half + gap) if has_gap
						else (prev_half + half) * advance)
			placed_any = true
			prev_centre = cursor + offset
			prev_half = half
		# Children were resolved at the row's origin; shift them into place. A
		# child that resolved to nothing contributes no parts, no bounds, and
		# does not move the cursor.
		var step := Vector3(0, 0, cursor) if is_z else Vector3(cursor, 0, 0)
		var shift := base_xf * Transform3D(Basis.IDENTITY, step) * base_inv
		for part: Dictionary in out["parts"]:
			part["xf"] = shift * part["xf"]
		parts.append_array(out["parts"])
		if f["height"] > EPS:
			bounds.add(Vector2(child_local.x + (0.0 if is_z else cursor),
					child_local.z + (cursor if is_z else 0.0)), fp)
			tallest = maxf(tallest, f["height"])
	if bounds.is_empty():
		return {"parts": parts, "frame": zero_frame(base_xf), "need": need}
	# A node occupies a box CENTRED on the transform it was handed. The layout
	# above builds rightward from the first child, so recentre the finished
	# group. Without this a symmetric pair comes back offset by half its own
	# span and everything stacked above inherits that — the hero arch showed it
	# as a plinth sitting under nothing.
	var mid := bounds.mid()
	var recentre := base_xf * Transform3D(Basis.IDENTITY,
			Vector3(-mid.x, 0, -mid.y)) * base_inv
	for part: Dictionary in parts:
		part["xf"] = recentre * part["xf"]
	return {"parts": parts, "need": need,
			"frame": {"xf": base_xf, "footprint": bounds.span(),
					"height": tallest}}


## Children on an arc, each rotated so its long axis lies TANGENT to it.
##
## This is the node the whole vocabulary was staked on, because an arch's
## voussoirs are the one thing the hand-written grammar does that translation
## alone cannot express. The lab finding it encodes: voussoirs lie tangent, not
## radial — radial orientation makes an M-shaped scallop rather than an arch.
##
## `from` and `to` are angles in radians measured from +X, counter-clockwise in
## the XY plane, so a semicircular arch is 0 to PI. `radius` is to the arc's
## centreline. Each child is stretched to the arc length of its own segment,
## with a small overlap so the joints close.
##
## Always tangent. A style wanting children that stay upright around a circle
## can have that when one exists to need it; guessing at the option now would
## be a parameter with no caller.
static func _ring(n: Dictionary, ctx: Dictionary) -> Dictionary:
	var path := _path_of(ctx, n)
	var seed: int = ctx["seed"]
	var id: int = ctx["id"]
	var base_xf: Transform3D = ctx["frame"]["xf"]
	var radius := sample(n.get("radius"), seed, id, path, "radius", 1.0)
	var from := sample(n.get("from"), seed, id, path, "from", 0.0)
	var to := sample(n.get("to"), seed, id, path, "to", PI)
	var count := _sample_count(n.get("count"), seed, id, path)
	var template: Dictionary = n.get("of", {})
	assert(not template.is_empty(), "'%s' ring has no 'of' template" % path)
	# Cohesive, unlike a row: an arch is not N independent stones. Remove one
	# voussoir and the arc collapses, so the ring draws once and every part it
	# emits carries that same need.
	var need := maxf(ctx["need_floor"], _draw_need(ctx, path))
	var parts: Array = []
	var lo := Vector2.INF
	var hi := -Vector2.INF
	var top := 0.0
	for i in range(maxi(0, count)):
		var a0 := from + (to - from) * i / float(count)
		var a1 := from + (to - from) * (i + 1) / float(count)
		var mid := (a0 + a1) * 0.5
		# Stretched to its own arc length, plus a little, so the joints close.
		var seg_len := radius * (a1 - a0) * 1.15
		var child := _indexed(template, i)
		var body: Dictionary = child[child.keys()[0]]
		var child_path := path + "/" + String(body["name"])
		var thickness := sample(body.get("w"), seed, id, child_path, "w", 0.2)
		var depth := sample(body.get("d"), seed, id, child_path, "d", thickness)
		if thickness <= EPS or depth <= EPS or seg_len <= EPS:
			continue
		# Rotate first, then drop by half the segment so the box — which builds
		# upward from its own origin — straddles the arc centreline.
		var xf := base_xf * Transform3D(Basis(Vector3(0, 0, 1), mid),
				Vector3(cos(mid) * radius, sin(mid) * radius, 0)) \
				* Transform3D(Basis.IDENTITY, Vector3(0, -seg_len * 0.5, 0))
		var size := Vector3(thickness, seg_len, depth)
		# Through the same kind-aware path a mass uses. Building params.size
		# regardless of kind meant a ring of columns emitted "prism" with box
		# params, and emit() reads params.radius — a missing-key crash from a
		# style that looks entirely valid.
		var kind: String = body.get("kind", "box")
		var params := _params_for(kind, body, thickness, depth, seg_len,
				seed, id, child_path)
		parts.append({"kind": kind, "xf": xf,
				"params": params, "color": Color.MAGENTA,
				"need": need, "y": 0.0,
				"role": body.get("role", "plaster")})
		# A ring's frame must describe what it EMITTED, not the circle it was
		# described by: tangent boxes stick out past the arc by half their
		# thickness, so 2*radius under-reports the real width by ~14% on a
		# typical arch. Take the hull of the transformed corners instead.
		for cx in [-0.5, 0.5]:
			for cy in [0.0, 1.0]:
				for cz in [-0.5, 0.5]:
					var c: Vector3 = base_xf.affine_inverse() * (xf * Vector3(
							size.x * cx, size.y * cy, size.z * cz))
					lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
					hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
					top = maxf(top, c.y)
	if lo.x == INF:
		return {"parts": parts, "frame": zero_frame(base_xf), "need": need}
	# Centred on what it was handed, like every other node.
	var mid_xz := (lo + hi) * 0.5
	var recentre := base_xf * Transform3D(Basis.IDENTITY,
			Vector3(-mid_xz.x, 0, -mid_xz.y)) * base_xf.affine_inverse()
	for part: Dictionary in parts:
		part["xf"] = recentre * part["xf"]
	return {"parts": parts, "need": need,
			"frame": {"xf": base_xf, "footprint": hi - lo, "height": top}}


## Suffix a template's name with its index so repeated units get distinct
## channels — otherwise `count: 3` produces the same building three times.
static func _indexed(template: Dictionary, i: int) -> Dictionary:
	var out := {}
	for type_key: String in template:
		var body: Dictionary = template[type_key].duplicate(true)
		body["name"] = "%s%d" % [body.get("name", "item"), i]
		out[type_key] = body
	return out


## Public entry point. Resolve the tree, then derive each part's centre height.
## A part's `need` — the condition at which it survives — was already settled
## during resolution, where the tree still knows what rests on what.
static func build(tree: Dictionary, seed: int, building_id: int) -> Array:
	var out := resolve(tree, new_ctx(seed, building_id))
	var parts: Array = out["parts"]
	_finish(parts)
	return parts


## Derives what no node should have to author: each part's centre height.
##
## This used to derive a four-way structural tag from normalised height and
## node kind as well. A census over the four styles killed that scheme:
## residential emitted 0% `base`, stepped 0% `upper`, and civic 62.5% `accent`
## — which meant its colonnade, the thing holding the building up, was tagged
## decorative and stripped first. Height is orthogonal to structural
## essentiality. `need` replaces it, drawn per node during resolution where the
## tree still says what rests on what.
static func _finish(parts: Array) -> void:
	for p: Dictionary in parts:
		p["y"] = p["xf"].origin.y + _height_of(p) * 0.5


static func _height_of(p: Dictionary) -> float:
	var params: Dictionary = p["params"]
	return params["size"].y if params.has("size") else params.get("height", 0.0)


## Resolve each part's role into a concrete colour. Kept separate from build()
## so one tree can be rendered in several palettes — which is what makes
## culture a mapping rather than a fork of the geometry.
static func apply_roles(parts: Array, roles: Dictionary) -> void:
	for p: Dictionary in parts:
		var role: String = p.get("role", "")
		assert(roles.has(role), "no colour for role '%s'" % role)
		p["color"] = roles[role]
