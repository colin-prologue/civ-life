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


static func zero_frame(xf: Transform3D) -> Dictionary:
	return {"xf": xf, "footprint": Vector2.ZERO, "height": 0.0}


static func new_ctx(seed: int, building_id: int) -> Dictionary:
	return {"seed": seed, "id": building_id, "path": "",
			"frame": zero_frame(Transform3D.IDENTITY)}


static func resolve(node: Dictionary, ctx: Dictionary) -> Dictionary:
	if node.has("mass"):
		return _mass(node["mass"], ctx)
	if node.has("stack"):
		return _stack(node["stack"], ctx)
	if node.has("row"):
		return _row(node["row"], ctx)
	assert(false, "unknown node type: %s" % str(node.keys()))
	return {"parts": [], "frame": zero_frame(ctx["frame"]["xf"])}


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
	if w <= EPS or d <= EPS or h <= EPS:
		return {"parts": [], "frame": zero_frame(xf)}
	var kind: String = n.get("kind", "box")
	var params := _params_for(kind, n, w, d, h, seed, id, path)
	var part := {"kind": kind, "xf": xf, "params": params,
			"color": Color.MAGENTA, "tag": "", "y": 0.0,
			"role": n.get("role", "plaster")}
	return {"parts": [part],
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


## Children bottom-to-top. Each child is handed the frame of the one below it,
## which is both where it sits and the footprint it inherits if it declares
## none — so a roof can say "cover whatever I am on, 8% bigger".
static func _stack(n: Dictionary, ctx: Dictionary) -> Dictionary:
	var path := _path_of(ctx, n)
	var children: Array = n.get("children", [])
	_assert_unique_names(children, path)
	var base_xf: Transform3D = ctx["frame"]["xf"]
	var parts: Array = []
	var carried: Vector2 = ctx["frame"]["footprint"]
	var y := 0.0
	var widest := Vector2.ZERO
	for child in children:
		var child_ctx := {"seed": ctx["seed"], "id": ctx["id"], "path": path,
				"frame": {"xf": base_xf.translated_local(Vector3(0, y, 0)),
						"footprint": carried, "height": 0.0}}
		var out := resolve(child, child_ctx)
		parts.append_array(out["parts"])
		var f: Dictionary = out["frame"]
		y += f["height"]
		if f["height"] > EPS:
			carried = f["footprint"]
		widest = Vector2(maxf(widest.x, f["footprint"].x),
				maxf(widest.y, f["footprint"].y))
	return {"parts": parts,
			"frame": {"xf": base_xf, "footprint": widest, "height": y}}


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


## Children along local X. The cursor advances by `advance` x the PRECEDING
## child's width, so spacing scales with the building rather than being an
## absolute distance. 1.0 is flush, below 1.0 overlaps, above 1.0 leaves a gap.
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
	var children: Array = []
	if has_template:
		# floor, not round: round() reaches the upper bound, so [1, 3.99]
		# yields 4 as well as 1-3. With floor, [1, 4.0] gives exactly 1-3 and
		# each is equally likely — h01 never returns 1.0.
		var count := int(floor(sample(n.get("count"), seed, id, path,
				"count", 1.0)))
		for i in range(maxi(0, count)):
			children.append(_indexed(n["of"], i))
	else:
		children = n.get("children", [])
		_assert_unique_names(children, path)
	var base_xf: Transform3D = ctx["frame"]["xf"]
	var advance := sample(n.get("advance"), seed, id, path, "advance", 1.0)
	var parts: Array = []
	var cursor := 0.0
	var span := 0.0
	var deepest := 0.0
	var tallest := 0.0
	for child in children:
		var child_ctx := {"seed": seed, "id": id, "path": path,
				"frame": {"xf": base_xf.translated_local(Vector3(cursor, 0, 0)),
						"footprint": ctx["frame"]["footprint"], "height": 0.0}}
		var out := resolve(child, child_ctx)
		parts.append_array(out["parts"])
		var f: Dictionary = out["frame"]
		span = cursor + f["footprint"].x
		deepest = maxf(deepest, f["footprint"].y)
		tallest = maxf(tallest, f["height"])
		cursor += f["footprint"].x * advance
	return {"parts": parts,
			"frame": {"xf": base_xf, "footprint": Vector2(span, deepest),
					"height": tallest}}


## Suffix a template's name with its index so repeated units get distinct
## channels — otherwise `count: 3` produces the same building three times.
static func _indexed(template: Dictionary, i: int) -> Dictionary:
	var out := {}
	for type_key: String in template:
		var body: Dictionary = template[type_key].duplicate(true)
		body["name"] = "%s%d" % [body.get("name", "item"), i]
		out[type_key] = body
	return out
