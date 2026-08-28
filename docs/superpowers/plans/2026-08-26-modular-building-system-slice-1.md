# Modular Building System — Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a building style a piece of data — a tree of composable nodes resolved into the parts contract the diorama already renders — and prove it by putting twelve variants of one style side by side in a single frame.

**Architecture:** A pure resolver folds a style tree into `{parts, frame}`. Each node returns the parts it produced *and* the space it occupies, so parents place siblings from children's frames instead of re-deriving arithmetic. Variation flows from channels keyed on node *names* rather than positions. Tags and part heights are derived in a post-pass, never authored. The resolver is a second producer for the existing parts contract, so nothing that renders today is modified.

**Tech Stack:** Godot 4 / GDScript, GUT for tests, existing `capture.sh --scene` for frames.

**Spec:** `docs/superpowers/specs/2026-08-26-modular-building-system-design.md`

## Global Constraints

- **Nothing that renders today may be modified.** `game/diorama/spike.gd`, `game/diorama/mesh_kit.gd`, `game/diorama/grammar.gd` and `game/diorama/synth_valley.gd` are read-only for this slice. The diorama's appearance must not change.
- **`sim/` is untouched.** This is entirely game-layer interpretation.
- **No sequential RNG, ever.** All variation derives from `DioramaHexKit.h01(...)`. A seeded-but-sequential stream is draw-order-dependent and breaks fingerprint tests (intent reconciliation 1).
- **`compose.gd` performs no rendering, no scene-tree access and no I/O.** It must run headless and produce identical results in separate processes.
- **Tests run headless.** `./test.sh` must pass on a host with no rendering context. Test files live at `test/test_*.gd` (that glob is also the suite's own count check) and `extend GutTest`.
- **Godot's builtin `hash()` is banned for channel derivation.** It has no documented cross-platform stability guarantee and this repo asserts determinism across processes. Use the FNV-1a helper defined in Task 1.
- **Parts contract, exact keys:** `{"kind", "xf", "params", "color", "tag", "y"}` — the shape `DioramaGrammar.emit()` consumes.
- **Every commit must leave `./test.sh` exiting 0.**

## File Structure

| File | Responsibility |
|---|---|
| `game/diorama/compose.gd` (new, `DioramaCompose`) | Node types, `resolve()`, frames, channel derivation, tag/`y` post-pass, condition filter. No rendering dependency. |
| `game/diorama/styles.gd` (new, `DioramaStyles`) | The style library: data literals and the default role→colour mapping. No logic beyond returning dictionaries. |
| `game/diorama/lineup.gd` (new, `DioramaLineup`) | Builds a grid of staged specimens with captions, one camera, one light. |
| `game/diorama/lineup.tscn` (new) | Scene wrapper so `capture.sh --scene` can photograph it. |
| `test/test_diorama_compose.gd` (new) | Resolver behaviour: channels, frames, nodes, tags, malformed input. |
| `test/test_diorama_styles.gd` (new) | The `residential` style resolves to a sane building. |
| `test/test_diorama_lineup.gd` (new) | The lineup scene builds the grid it was asked for. |

---

### Task 1: Channels, ranges, and the `mass` node

**Files:**
- Create: `game/diorama/compose.gd`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: `DioramaHexKit.h01(seed: int, a: int, b: int = 0, c: int = 0) -> float`
- Produces:
  - `DioramaCompose.str_hash(s: String) -> int`
  - `DioramaCompose.channel(seed: int, building_id: int, path: String, purpose: String) -> float`
  - `DioramaCompose.sample(spec: Variant, seed: int, building_id: int, path: String, purpose: String, dflt: float) -> float`
  - `DioramaCompose.new_ctx(seed: int, building_id: int) -> Dictionary` — returns `{"seed", "id", "path", "frame"}`
  - `DioramaCompose.resolve(node: Dictionary, ctx: Dictionary) -> Dictionary` — returns `{"parts": Array, "frame": Dictionary}`
  - A **frame** is `{"xf": Transform3D, "footprint": Vector2, "height": float}`. `xf` is the transform of the node's *base plane*; `footprint` is (width, depth); `height` is its vertical extent.

- [ ] **Step 1: Write the failing test**

Create `test/test_diorama_compose.gd`:

```gdscript
extends GutTest
## Resolver invariants for the style-tree composer.
##
## These are asserted on returned data rather than on a picture, so they run on
## a host with no rendering context — the same reason test_diorama_mesh_kit.gd
## checks buffers instead of frames.

const SEED := 4242


func _ctx() -> Dictionary:
	return DioramaCompose.new_ctx(SEED, 7)


func _box(name: String, w: Variant, d: Variant, h: Variant) -> Dictionary:
	return {"mass": {"name": name, "kind": "box", "w": w, "d": d, "h": h,
			"role": "plaster"}}


func test_str_hash_is_stable_and_distinguishes() -> void:
	assert_eq(DioramaCompose.str_hash("body"), DioramaCompose.str_hash("body"),
			"same string hashed twice differs")
	assert_ne(DioramaCompose.str_hash("body"), DioramaCompose.str_hash("roof"),
			"different strings collided")


func test_channel_is_deterministic_and_in_range() -> void:
	var a := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	var b := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	assert_eq(a, b, "same channel gave two values")
	assert_between(a, 0.0, 1.0, "channel escaped [0,1]")


func test_channel_varies_by_path_purpose_and_building() -> void:
	var base := DioramaCompose.channel(SEED, 7, "block/unit/body", "w")
	assert_ne(base, DioramaCompose.channel(SEED, 7, "block/unit/roof", "w"),
			"two different nodes drew the same value")
	assert_ne(base, DioramaCompose.channel(SEED, 7, "block/unit/body", "h"),
			"two fields of one node drew the same value")
	assert_ne(base, DioramaCompose.channel(SEED, 8, "block/unit/body", "w"),
			"two buildings drew the same value")


func test_sample_scalar_is_fixed_and_range_is_inside_bounds() -> void:
	assert_eq(DioramaCompose.sample(0.75, SEED, 7, "p", "w", 1.0), 0.75,
			"a scalar spec was not returned verbatim")
	var v := DioramaCompose.sample([0.5, 1.5], SEED, 7, "p", "w", 1.0)
	assert_between(v, 0.5, 1.5, "sampled value escaped its range")
	assert_eq(DioramaCompose.sample(null, SEED, 7, "p", "w", 0.25), 0.25,
			"a missing spec did not fall back to the default")


func test_mass_emits_one_part_with_the_contract_keys() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 2.0, 3.0), _ctx())
	assert_eq(out["parts"].size(), 1, "a mass produced the wrong part count")
	var p: Dictionary = out["parts"][0]
	for key in ["kind", "xf", "params", "color", "tag", "y"]:
		assert_true(p.has(key), "part is missing contract key '%s'" % key)
	assert_eq(p["kind"], "box", "part kind was not carried through")
	assert_eq(p["params"]["size"], Vector3(1.0, 3.0, 2.0),
			"box size is (w, h, d) — check the axis order")


func test_mass_frame_reports_its_own_extent() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 2.0, 3.0), _ctx())
	assert_eq(out["frame"]["footprint"], Vector2(1.0, 2.0), "footprint wrong")
	assert_eq(out["frame"]["height"], 3.0, "frame height wrong")


func test_mass_with_a_zero_dimension_emits_nothing() -> void:
	var out := DioramaCompose.resolve(_box("body", 1.0, 0.0, 3.0), _ctx())
	assert_eq(out["parts"].size(), 0,
			"a degenerate mass still emitted a part")
	assert_eq(out["frame"]["height"], 0.0,
			"a degenerate mass claimed vertical extent")


func test_mass_inherits_the_incoming_footprint_when_it_omits_one() -> void:
	# A roof declares no w/d: it takes the frame it sits on, scaled by oversize.
	var ctx := _ctx()
	ctx["frame"]["footprint"] = Vector2(2.0, 4.0)
	var roof := {"mass": {"name": "roof", "kind": "box", "h": 0.5,
			"oversize": 1.5, "role": "ochre"}}
	var out := DioramaCompose.resolve(roof, ctx)
	assert_eq(out["frame"]["footprint"], Vector2(3.0, 6.0),
			"oversize did not scale the inherited footprint")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — `Parse Error: Identifier "DioramaCompose" not declared in the current scope.`

- [ ] **Step 3: Write minimal implementation**

Create `game/diorama/compose.gd`:

```gdscript
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
		"dome":
			return {"radius": w * 0.5,
					"squash": sample(n.get("squash"), seed, id, path, "squash", 0.75)}
	assert(false, "unknown mass kind '%s' on '%s'" % [kind, path])
	return {}
```

Note the part carries a `role` alongside the contract keys and a placeholder
`color`; Task 5 resolves roles to colours. Carrying an extra key is harmless —
`emit()` reads only the keys it knows.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --import` then
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: PASS, 8/8.

The `--import` is required whenever a new `class_name` is added — Godot's global class cache is gitignored, and without it every reference fails to parse.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd game/diorama/compose.gd.uid test/test_diorama_compose.gd test/test_diorama_compose.gd.uid
git commit -m "compose: named channels, proportion ranges, and the mass node"
```

---

### Task 2: The `stack` node

**Files:**
- Modify: `game/diorama/compose.gd`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: Task 1's `resolve`, `_path_of`, `sample`, frames.
- Produces: `resolve()` handling `{"stack": {"name": String, "children": Array}}`. A stack's frame height is the sum of its children's; its footprint is the per-axis maximum.

- [ ] **Step 1: Write the failing test**

Append to `test/test_diorama_compose.gd`:

```gdscript
func _two_tier() -> Dictionary:
	return {"stack": {"name": "unit", "children": [
		_box("lower", 2.0, 2.0, 1.0),
		_box("upper", 1.0, 1.0, 3.0)]}}


func test_stack_sums_height_and_takes_the_widest_footprint() -> void:
	var out := DioramaCompose.resolve(_two_tier(), _ctx())
	assert_eq(out["parts"].size(), 2, "stack lost a child")
	assert_almost_eq(out["frame"]["height"], 4.0, 1e-5,
			"stack height is not the sum of its children")
	assert_eq(out["frame"]["footprint"], Vector2(2.0, 2.0),
			"stack footprint is not the widest child's")


func test_stack_places_each_child_on_top_of_the_one_below() -> void:
	var out := DioramaCompose.resolve(_two_tier(), _ctx())
	var lower: Dictionary = out["parts"][0]
	var upper: Dictionary = out["parts"][1]
	assert_almost_eq(lower["xf"].origin.y, 0.0, 1e-5,
			"first child should sit on the incoming base plane")
	assert_almost_eq(upper["xf"].origin.y, 1.0, 1e-5,
			"second child should sit on top of the first, at its height")


func test_a_zero_height_child_does_not_lift_its_successor() -> void:
	var tree := {"stack": {"name": "unit", "children": [
		_box("ghost", 1.0, 1.0, 0.0),
		_box("real", 1.0, 1.0, 2.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 1, "the degenerate child emitted a part")
	assert_almost_eq(out["parts"][0]["xf"].origin.y, 0.0, 1e-5,
			"a zero-height child still pushed its successor upward")


func test_adding_a_named_sibling_does_not_disturb_the_others() -> void:
	# The whole reason channels are keyed on names. If this fails, someone has
	# reintroduced index-based hashing and every edit will reshuffle the town.
	var before := DioramaCompose.resolve(
			{"stack": {"name": "unit", "children": [
				_box("body", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("roof", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0])]}}, _ctx())
	var after := DioramaCompose.resolve(
			{"stack": {"name": "unit", "children": [
				_box("porch", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("body", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0]),
				_box("roof", [1.0, 2.0], [1.0, 2.0], [1.0, 2.0])]}}, _ctx())
	assert_eq(before["parts"][0]["params"]["size"],
			after["parts"][1]["params"]["size"],
			"inserting 'porch' re-rolled 'body'")
	assert_eq(before["parts"][1]["params"]["size"],
			after["parts"][2]["params"]["size"],
			"inserting 'porch' re-rolled 'roof'")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — the `assert(false, "unknown node type: ...")` in `resolve` fires for `stack`.

- [ ] **Step 3: Write minimal implementation**

In `game/diorama/compose.gd`, add `stack` dispatch to `resolve`:

```gdscript
static func resolve(node: Dictionary, ctx: Dictionary) -> Dictionary:
	if node.has("mass"):
		return _mass(node["mass"], ctx)
	if node.has("stack"):
		return _stack(node["stack"], ctx)
	assert(false, "unknown node type: %s" % str(node.keys()))
	return {"parts": [], "frame": zero_frame(ctx["frame"]["xf"])}
```

and append:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: PASS, 12/12.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: the stack node, placing children on the frame below"
```

---

### Task 3: The `row` node

**Files:**
- Modify: `game/diorama/compose.gd`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: Task 2's `_stack`, `_assert_unique_names`, frames.
- Produces: `resolve()` handling `{"row": {"name", "advance", "count"+"of" | "children"}}`. `advance` is a multiple of the preceding child's width; `1.0` is flush, `<1.0` overlaps, `>1.0` gaps.

- [ ] **Step 1: Write the failing test**

Append to `test/test_diorama_compose.gd`:

```gdscript
func test_row_advances_by_a_fraction_of_the_previous_width() -> void:
	var tree := {"row": {"name": "block", "advance": 0.5, "children": [
		_box("a", 2.0, 1.0, 1.0),
		_box("b", 2.0, 1.0, 1.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["parts"][0]["xf"].origin.x, 0.0, 1e-5,
			"first child of a row should start at the origin")
	assert_almost_eq(out["parts"][1]["xf"].origin.x, 1.0, 1e-5,
			"advance 0.5 on a width-2 child should step 1.0, not 2.0")


func test_row_template_repeats_with_distinct_channels_per_index() -> void:
	var tree := {"row": {"name": "block", "count": 3, "advance": 1.0,
			"of": _box("unit", [1.0, 3.0], 1.0, 1.0)}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 3, "count did not repeat the template")
	var w0: float = out["parts"][0]["params"]["size"].x
	var w1: float = out["parts"][1]["params"]["size"].x
	assert_ne(w0, w1, "repeated units are identical — index is not in the channel")


func test_row_with_zero_count_is_legal_and_empty() -> void:
	var tree := {"row": {"name": "block", "count": 0, "advance": 1.0,
			"of": _box("unit", 1.0, 1.0, 1.0)}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_eq(out["parts"].size(), 0, "count 0 still produced parts")
	assert_eq(out["frame"]["height"], 0.0, "an empty row claimed height")
	assert_eq(out["frame"]["footprint"], Vector2.ZERO,
			"an empty row claimed a footprint")


func test_row_frame_spans_its_children_and_takes_the_tallest() -> void:
	var tree := {"row": {"name": "block", "advance": 1.0, "children": [
		_box("a", 2.0, 1.0, 1.0),
		_box("b", 2.0, 3.0, 5.0)]}}
	var out := DioramaCompose.resolve(tree, _ctx())
	assert_almost_eq(out["frame"]["footprint"].x, 4.0, 1e-5,
			"row width should span first near edge to last far edge")
	assert_almost_eq(out["frame"]["footprint"].y, 3.0, 1e-5,
			"row depth should be its deepest child")
	assert_almost_eq(out["frame"]["height"], 5.0, 1e-5,
			"row height should be its tallest child")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — `unknown node type: ["row"]`.

- [ ] **Step 3: Write minimal implementation**

Add `row` dispatch to `resolve` (keeping the existing `mass` and `stack` branches above it):

```gdscript
	if node.has("row"):
		return _row(node["row"], ctx)
```

and append:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: PASS, 16/16.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: the row node, spacing by advance rather than absolute gap"
```

---

### Task 4: Derived tags, `y`, and the condition filter

**Files:**
- Modify: `game/diorama/compose.gd`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `DioramaCompose.build(tree: Dictionary, seed: int, building_id: int) -> Array` — the public entry point: resolve, then finish tags and `y`.
  - `DioramaCompose.parts_at_condition(parts: Array, condition: float) -> Array`

- [ ] **Step 1: Write the failing test**

Append to `test/test_diorama_compose.gd`:

```gdscript
func _tower() -> Dictionary:
	return {"stack": {"name": "tower", "children": [
		_box("plinth", 4.0, 4.0, 1.0),
		_box("shaft", 3.0, 3.0, 6.0),
		{"mass": {"name": "spire", "kind": "cone", "w": 0.4, "d": 0.4,
				"h": 3.0, "role": "brass"}}]}}


func test_build_tags_every_part() -> void:
	for p: Dictionary in DioramaCompose.build(_tower(), SEED, 1):
		assert_ne(p["tag"], "", "a part came back untagged")


func test_lowest_part_is_base_and_highest_is_upper() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_eq(parts[0]["tag"], "base", "the bottom part is not tagged base")
	assert_eq(parts[1]["tag"], "mid", "the middle part is not tagged mid")


func test_a_small_cone_on_top_is_an_accent() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_eq(parts[2]["tag"], "accent",
			"a slim cone above the mass should read as an accent")


func test_y_is_the_part_centre_height() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	assert_almost_eq(parts[0]["y"], 0.5, 1e-5, "plinth centre should be h/2")
	assert_almost_eq(parts[1]["y"], 4.0, 1e-5, "shaft centre should be 1 + 6/2")


func test_tags_are_monotonic_in_height() -> void:
	# The property the ruin filter depends on: nothing tagged base sits above
	# anything tagged upper. Uses its own four-box fixture rather than _tower()
	# — the tower tops out in `mid` and `accent`, so running this against it
	# would pass without ever comparing a base to an upper.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0), _box("d", 2.0, 2.0, 2.0)]}}
	var parts := DioramaCompose.build(tall, SEED, 1)
	var highest_base := -INF
	var lowest_upper := INF
	for p: Dictionary in parts:
		if p["tag"] == "base":
			highest_base = maxf(highest_base, p["y"])
		elif p["tag"] == "upper":
			lowest_upper = minf(lowest_upper, p["y"])
	assert_gt(highest_base, -INF, "fixture produced no base part to compare")
	assert_lt(lowest_upper, INF, "fixture produced no upper part to compare")
	assert_lt(highest_base, lowest_upper,
			"a base part sits above an upper part")


func test_condition_removes_from_the_top_down() -> void:
	var parts := DioramaCompose.build(_tower(), SEED, 1)
	var half := DioramaCompose.parts_at_condition(parts, 0.5)
	var ruin := DioramaCompose.parts_at_condition(parts, 0.05)
	assert_lt(half.size(), parts.size(), "condition 0.5 removed nothing")
	assert_lt(ruin.size(), half.size(), "condition 0.05 removed no more than 0.5")
	for p: Dictionary in ruin:
		assert_eq(p["tag"], "base",
				"only base parts should survive at condition 0.05")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — `Invalid call. Nonexistent function 'build' in base 'GDScript'`.

- [ ] **Step 3: Write minimal implementation**

Append to `game/diorama/compose.gd`:

```gdscript
## Public entry point. Resolve the tree, then derive what no node should have
## to author: each part's centre height and its structural tag.
static func build(tree: Dictionary, seed: int, building_id: int) -> Array:
	var out := resolve(tree, new_ctx(seed, building_id))
	var parts: Array = out["parts"]
	_finish(parts)
	return parts


## Tags fall out of normalised height once the building's full extent is known,
## so a style author never labels a part and can never forget to. That is what
## makes ruins and the assembly tween automatic for every new style.
static func _finish(parts: Array) -> void:
	if parts.is_empty():
		return
	var total := 0.0
	var biggest_area := 0.0
	for p: Dictionary in parts:
		total = maxf(total, p["xf"].origin.y + _height_of(p))
		biggest_area = maxf(biggest_area, _area_of(p))
	for p: Dictionary in parts:
		var h := _height_of(p)
		p["y"] = p["xf"].origin.y + h * 0.5
		var t: float = p["y"] / maxf(total, EPS)
		if (p["kind"] == "cone" or p["kind"] == "prism") \
				and _area_of(p) < biggest_area * 0.25:
			p["tag"] = "accent"
		elif t < 0.20:
			p["tag"] = "base"
		elif t < 0.65:
			p["tag"] = "mid"
		else:
			p["tag"] = "upper"


static func _height_of(p: Dictionary) -> float:
	var params: Dictionary = p["params"]
	return params["size"].y if params.has("size") else params.get("height", 0.0)


static func _area_of(p: Dictionary) -> float:
	var params: Dictionary = p["params"]
	if params.has("size"):
		return params["size"].x * params["size"].z
	var r: float = params.get("radius", 0.0)
	return r * r * 4.0


## Keep the parts a building of this condition would still have standing.
## Slice 1 needs only the filter; the full condition transform (debris, partial
## spans) is a later slice. The ordering it relies on is asserted in the tests.
const CONDITION_ORDER := {"accent": 0.85, "upper": 0.60, "mid": 0.35, "base": 0.0}


static func parts_at_condition(parts: Array, condition: float) -> Array:
	var kept: Array = []
	for p: Dictionary in parts:
		if condition >= CONDITION_ORDER.get(p["tag"], 0.0):
			kept.append(p)
	return kept
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: PASS, 22/22.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: derive tags and part heights so ruins come for free"
```

---

### Task 5: `residential` as data, and role colours

**Files:**
- Create: `game/diorama/styles.gd`
- Modify: `game/diorama/compose.gd`
- Test: `test/test_diorama_styles.gd`

**Interfaces:**
- Consumes: Task 4's `DioramaCompose.build`.
- Produces:
  - `DioramaStyles.ROLES: Dictionary` — role name → `Color`
  - `DioramaStyles.residential() -> Dictionary`
  - `DioramaCompose.apply_roles(parts: Array, roles: Dictionary) -> void`

- [ ] **Step 1: Write the failing test**

Create `test/test_diorama_styles.gd`:

```gdscript
extends GutTest
## The first style expressed as data rather than as a function.
##
## These assertions are structural on purpose. A tolerance against the old
## grammar.gd function would either be so loose it asserts nothing or so tight
## it freezes a proof-of-concept model the owner has called disposable — the
## thing under test is the vocabulary, not this specimen.

const SEED := 20260826


func _built(id: int) -> Array:
	var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, id)
	DioramaCompose.apply_roles(parts, DioramaStyles.ROLES)
	return parts


func test_residential_is_one_to_three_body_and_roof_pairs() -> void:
	for id in range(12):
		var parts := _built(id)
		assert_between(parts.size(), 2, 6,
				"seed %d produced %d parts; expected 1-3 units of 2"
				% [id, parts.size()])
		assert_eq(parts.size() % 2, 0, "parts did not come in body/roof pairs")


func test_each_roof_sits_directly_on_its_own_body() -> void:
	var parts := _built(3)
	for i in range(0, parts.size(), 2):
		var body: Dictionary = parts[i]
		var roof: Dictionary = parts[i + 1]
		assert_almost_eq(roof["xf"].origin.y,
				body["xf"].origin.y + body["params"]["size"].y, 1e-5,
				"roof %d is not resting on its body" % i)
		assert_gt(roof["params"]["size"].x, body["params"]["size"].x,
				"roof should overhang its body")


func test_style_has_range_across_seeds() -> void:
	var sizes := {}
	for id in range(12):
		sizes[str(_built(id).size())] = true
	assert_gt(sizes.size(), 1,
			"twelve seeds produced buildings of one single size — no range")


func test_roles_resolve_to_palette_colours() -> void:
	for p: Dictionary in _built(1):
		assert_ne(p["color"], Color.MAGENTA,
				"a part kept its placeholder colour — role never resolved")


func test_same_seed_and_id_rebuild_identically() -> void:
	assert_eq(_built(5), _built(5), "same inputs produced different buildings")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_styles.gd -gexit`
Expected: FAIL — `Identifier "DioramaStyles" not declared in the current scope.`

- [ ] **Step 3: Write minimal implementation**

Create `game/diorama/styles.gd`:

```gdscript
class_name DioramaStyles
extends RefCounted
## The style library: buildings as data.
##
## A style names roles rather than colours, so the same tree can be rendered in
## two cultures' palettes without touching its geometry. Slice 1 ships one
## mapping; per-culture mappings arrive with S3.

const ROLES := {
	"plaster": Color(0.902, 0.875, 0.800),
	"plaster_dim": Color(0.812, 0.776, 0.682),
	"ochre": Color(0.659, 0.475, 0.290),
	"brass": Color(0.788, 0.643, 0.290),
	"wood": Color(0.478, 0.361, 0.220),
}


## A terrace of one to three units, each a plaster body under a tapered ochre
## roof that overhangs it. Compare against DioramaGrammar.residential(), which
## says the same thing in sixteen lines of arithmetic — if this is harder to
## read than that was, the whole design has failed its own premise.
static func residential() -> Dictionary:
	return {"row": {"name": "block", "count": [1, 4.0], "advance": 0.95, "of":
		{"stack": {"name": "unit", "children": [
			{"mass": {"name": "body", "kind": "box",
					"w": [0.55, 1.05], "d": [0.55, 1.05], "h": [0.60, 1.30],
					"role": "plaster"}},
			{"mass": {"name": "roof", "kind": "tapered", "taper": 0.8,
					"h": 0.22, "oversize": 1.08, "role": "ochre"}}]}}}}
```

`count` is `[1, 4.0]` and not `[1, 3]` because `_row` floors the sample: the
upper bound is exclusive in practice, so `[1, 4.0]` gives 1, 2 or 3 with equal
weight. `[1, 3]` would yield 3 only on an exact 1.0 draw, which never happens.

Append to `game/diorama/compose.gd`:

```gdscript
## Resolve each part's role into a concrete colour. Kept separate from build()
## so one tree can be rendered in several palettes — which is what makes
## culture a mapping rather than a fork of the geometry.
static func apply_roles(parts: Array, roles: Dictionary) -> void:
	for p: Dictionary in parts:
		var role: String = p.get("role", "")
		assert(roles.has(role), "no colour for role '%s'" % role)
		p["color"] = roles[role]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --import` then
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_styles.gd -gexit`
Expected: PASS, 5/5.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/styles.gd game/diorama/styles.gd.uid game/diorama/compose.gd test/test_diorama_styles.gd test/test_diorama_styles.gd.uid
git commit -m "styles: residential as a style tree, with roles resolved at build"
```

---

### Task 6: The specimen sheet

**Files:**
- Create: `game/diorama/lineup.gd`, `game/diorama/lineup.tscn`
- Test: `test/test_diorama_lineup.gd`
- Create (captured, committed in Step 6): `docs/shots/building-lineup/residential-seeds.png`

**Interfaces:**
- Consumes: `DioramaCompose.build`, `DioramaCompose.apply_roles`, `DioramaStyles.ROLES`, `DioramaStyles.residential()`, `DioramaGrammar.emit(builder, parts, world)`, `DioramaMeshKit`.
- Produces: `DioramaLineup` — a `Node3D` with exported `columns`, `cell_size`, `world_seed`, `specimen_count`, building one `MeshInstance3D` and one `Label3D` per cell.

- [ ] **Step 1: Write the failing test**

Create `test/test_diorama_lineup.gd`:

```gdscript
extends GutTest
## The specimen sheet: a grid of staged buildings, one camera, one light.
##
## The sheet is a SCENE rather than a montage of separate renders — one frame,
## no compositing step, deterministic by construction, and it drops onto the
## existing capture.sh --scene. These assertions cover structure only; whether
## the buildings are any good is the thing a human looks at the PNG to decide.


func test_lineup_builds_one_specimen_and_caption_per_cell() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 6
	add_child_autofree(lineup)
	await wait_frames(2)
	var meshes := 0
	var labels := 0
	for child in lineup.get_children():
		if child is MeshInstance3D:
			meshes += 1
		elif child is Label3D:
			labels += 1
	assert_eq(meshes, 6, "wrong number of specimens")
	assert_eq(labels, 6, "every specimen needs a caption or the sheet is unreadable")
	assert_not_null(lineup.get_node_or_null("Camera"), "no camera")
	assert_not_null(lineup.get_node_or_null("Sun"), "no light")


func test_specimens_are_laid_out_on_a_grid_without_overlap() -> void:
	var scene: PackedScene = load("res://game/diorama/lineup.tscn")
	var lineup: Node3D = scene.instantiate()
	lineup.specimen_count = 4
	lineup.columns = 2
	lineup.cell_size = 4.0
	add_child_autofree(lineup)
	await wait_frames(2)
	var seen := {}
	for child in lineup.get_children():
		if child is MeshInstance3D:
			var key := "%.2f,%.2f" % [child.position.x, child.position.z]
			assert_false(seen.has(key), "two specimens share a cell at " + key)
			seen[key] = true
	assert_eq(seen.size(), 4, "specimens did not spread over the grid")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_lineup.gd -gexit`
Expected: FAIL — the scene fails to load; `lineup.tscn` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `game/diorama/lineup.gd`:

```gdscript
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
@export var cell_size: float = 3.2
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
```

Create `game/diorama/lineup.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://game/diorama/lineup.gd" id="1"]

[node name="Lineup" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --import` then
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=test -gtest=res://test/test_diorama_lineup.gd -gexit`
Expected: PASS, 2/2.

- [ ] **Step 5: Run the whole suite**

Run: `./test.sh`
Expected: exit 0. Confirm the script-count backstop sees the three new test files and that the diorama's own tests still pass — nothing in this slice may have changed what `spike.gd` renders.

- [ ] **Step 6: Capture the sheet and commit everything**

```bash
./capture.sh --scene res://game/diorama/lineup.tscn \
    --label residential-seeds --name building-lineup
git add game/diorama/lineup.gd game/diorama/lineup.gd.uid \
        game/diorama/lineup.tscn test/test_diorama_lineup.gd \
        test/test_diorama_lineup.gd.uid docs/shots/building-lineup
git commit -m "lineup: a specimen sheet as a scene, and twelve residentials"
```

Then run `./tools/shot_links.sh docs/shots/building-lineup` and put the printed
markdown in the PR body — the URLs are pinned to `HEAD`, so this only works
after the commit above.

---

## Self-Review

**Spec coverage.** FR-1 → Task 1. FR-1a (`y` derived) → Task 4. FR-2 (scalar/range/malformed) → Task 1. FR-3 (names required, siblings unique) → Task 1 `_path_of`, Task 2 `_assert_unique_names`. FR-4 (`stack`) → Task 2. FR-5 (`advance`) → Task 3. FR-6 (`count`/`of` vs `children`, count 0) → Task 3. FR-7 (degenerate mass) → Task 1. FR-8 (tag post-pass) → Task 4. FR-9 (channel derivation) → Task 1. FR-10 (headless, no I/O) → global constraints, and `compose.gd` has no scene dependency. FR-11 (lineup) → Task 6. FR-12 (`residential` as data) → Task 5.

**Deviation from the spec, flagged rather than absorbed:** the spec writes the channel as `hash(path)`; this plan pins **FNV-1a** and bans Godot's builtin `hash()`, because the builtin carries no cross-platform stability guarantee and `test.sh` asserts determinism across processes. This is a tightening, not a contradiction, but it is a decision the spec did not make.

**Second deviation:** the spec put the condition filter in slice 3. Task 4 includes a five-line `parts_at_condition`, because without it the "ruins come free" claim is asserted only as tag ordering and never actually exercised. The full condition *transform* — debris, partial spans, material ageing — remains slice 3.

**Placeholder scan:** no TBD/TODO; every code step carries runnable code; no step says "handle errors appropriately".

**Type consistency:** frames are `{"xf", "footprint", "height"}` in every task. `resolve()` returns `{"parts", "frame"}` throughout. `build()` returns a bare `Array` of parts and is the only public entry point used by Tasks 5 and 6. `apply_roles` is called separately from `build` in both the styles test and the lineup, consistently.

**Known gap, deliberate:** no test asserts that the *rendered* sheet looks correct — that is the human judgement the PNG exists for, and it cannot be asserted headless.
