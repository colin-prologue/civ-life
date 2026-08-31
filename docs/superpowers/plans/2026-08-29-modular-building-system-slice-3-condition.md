# MBS slice 3 — condition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the derived height/kind `tag` on each part with `need` — a
single float that is the condition at which that part survives — and add the
filter, the tests and the sheet that make ruins real.

**Architecture:** `need` is drawn from the existing hash channels during
resolution and combined by node type: a `stack` imposes a running maximum on its
children (which *is* the load path), a `row` leaves siblings independent, and a
`ring` is cohesive — one value shared by its whole subtree, so an arch survives
or falls whole. Filtering on a fixed per-part threshold is monotone by
construction, so ordered loss cannot be violated by any style.

**Tech Stack:** Godot 4.7.1, GDScript, GUT test framework.

**Spec:** `docs/superpowers/specs/2026-08-29-modular-building-system-slice-3-condition.md`

**Ticket:** #34. Read the spec before Task 1 — the plan argues from it and the
census numbers that motivate every choice live there.

## Global Constraints

- **`compose.gd` stays pure.** No rendering, no scene-tree access, no I/O. It is
  a static-function library on `RefCounted`. (AC9)
- **Godot's built-in `hash()` is banned.** Use `DioramaCompose.str_hash()` —
  FNV-1a — because `hash()` carries no cross-platform stability guarantee and the
  determinism gate compares across processes.
- **Channels are keyed on node *names*, never index paths.** Inserting a sibling
  must not reshuffle the others.
- **Every draw goes through `DioramaCompose.channel(seed, id, path, purpose)`.**
  Never a sequential RNG. Determinism is a pure-hash property here.
- **`ENDURE_LO = 0.10`, `ENDURE_HI = 0.90`.** Tuning constants; the sheet tunes
  them. Use these exact values.
- **The condition ladder is `[1.0, 0.75, 0.5, 0.25, 0.05]`** — the intent's five
  named rungs, in that order.
- **`./test.sh` must exit 0** at the end of every task. It runs GUT, then a
  cross-process determinism check over three fingerprint generators, then a
  headless launch of the main scene.
- **Do not touch `sim/`.**
- Run `./test.sh` — not `godot -s addons/gut/...` alone — before any commit that
  claims to pass. The determinism gate lives outside GUT.

---

## File Structure

| File | Responsibility |
|---|---|
| `game/diorama/compose.gd` | Modify. Compute `need` per node type; drop `tag` |
| `game/diorama/condition.gd` | **Create.** The filter and the fragment rule. Knows nothing about the tree |
| `game/diorama/condition_sheet.gd` | **Create.** The style × condition sheet, as a scene |
| `game/diorama/condition_sheet.tscn` | **Create.** Scene wrapper for the above |
| `game/diorama/lineup.gd` | Modify. One-line fix: the style enum is stale |
| `test/test_diorama_condition.gd` | **Create.** Filter properties |
| `test/test_diorama_compose.gd` | Modify. Replace tag assertions with `need` |
| `tools/diorama_compose_fingerprint.gd` | Modify. Fold `need` into the digest |
| `docs/shots/mbs-condition/` | The committed sheet |

---

### Task 1: `need` on a mass, and the floor that threads through ctx

> **Superseded — read this first.** The single inherited `need_floor` this task
> specifies shipped, then failed twice on the DISTRIBUTION of levels and was
> replaced by an inherited BAND (`ctx["need_lo"]` / `ctx["need_hi"]`, the
> sub-range of `[ENDURE_LO, ENDURE_HI]` a node and its descendants may occupy).
> A stack partitions its band across its children in order; a row hands every
> child the band whole; a ring draws once inside its band for its whole subtree.
> See `_draw_need` in `game/diorama/compose.gd` for the rule and both failures.
> The strict-read rationale below still applies, to the band keys instead.
>
> Tasks 1-3 are left as written on purpose: they record what was attempted, and
> the two failed rules are worth keeping visible.

**Files:**
- Modify: `game/diorama/compose.gd` — `new_ctx`, `resolve`, `_mass`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: `DioramaCompose.channel(seed, id, path, purpose) -> float` (exists,
  line 38); `DioramaCompose.new_ctx(seed, building_id) -> Dictionary` (exists).
- Produces:
  - `const ENDURE_LO := 0.10`, `const ENDURE_HI := 0.90`
  - `ctx` gains key `"need_floor": float`
  - `resolve(node, ctx)` return gains key `"need": float` — the value whatever
    rests on this node must respect
  - every emitted part gains key `"need": float`

**Why the floor is read strictly.** `_mass` indexes `ctx["need_floor"]` rather
than `ctx.get("need_floor", 0.0)`. A `.get` default would silently turn a
combinator that forgot to pass the floor into "no load path" — parts float, no
test fails, and the bug is invisible until a sheet looks wrong. Strict indexing
crashes at the missed call site.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_compose.gd`:

```gdscript
func test_a_mass_draws_its_need_in_band_and_deterministically() -> void:
	var tree := _box("solo", 2.0, 2.0, 2.0)
	var a := DioramaCompose.build(tree, SEED, 3)
	var b := DioramaCompose.build(tree, SEED, 3)
	assert_eq(a.size(), 1, "fixture should emit exactly one part")
	assert_eq(a[0]["need"], b[0]["need"], "same seed and id gave two needs")
	assert_true(a[0]["need"] >= DioramaCompose.ENDURE_LO,
			"need %f fell below the band floor" % a[0]["need"])
	assert_true(a[0]["need"] <= DioramaCompose.ENDURE_HI,
			"need %f rose above the band ceiling" % a[0]["need"])


func test_two_ids_draw_different_needs() -> void:
	# Otherwise every building in a city ruins identically, which is the whole
	# reason need is drawn rather than computed from geometry.
	var tree := _box("solo", 2.0, 2.0, 2.0)
	var differ := false
	for id in range(12):
		if not is_equal_approx(
				DioramaCompose.build(tree, SEED, 0)[0]["need"],
				DioramaCompose.build(tree, SEED, id)[0]["need"]):
			differ = true
	assert_true(differ, "twelve ids all drew the same need")


func test_a_mass_never_outlives_the_floor_it_was_handed() -> void:
	var ctx := DioramaCompose.new_ctx(SEED, 7)
	ctx["need_floor"] = 0.95
	var out := DioramaCompose.resolve(_box("solo", 2.0, 2.0, 2.0), ctx)
	assert_almost_eq(out["parts"][0]["need"], 0.95, 1e-6,
			"a floor above the draw band should win")
	assert_almost_eq(out["need"], 0.95, 1e-6,
			"the node should report the need it settled on")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — `Invalid access to property or key 'need'`.

- [ ] **Step 3: Implement**

In `game/diorama/compose.gd`, add near the other constants:

```gdscript
## The band a part's endurance is drawn from. `need` is the condition at or
## above which a part survives, so a LOW need is a DURABLE part. The band is
## deliberately short of [0, 1]: nothing is indestructible and nothing is
## made of paper, and the sheet is what tunes these.
const ENDURE_LO := 0.10
const ENDURE_HI := 0.90


## A node's own endurance, before the floor its support imposes.
static func _draw_need(ctx: Dictionary, path: String) -> float:
	return ENDURE_LO + (ENDURE_HI - ENDURE_LO) * channel(
			ctx["seed"], ctx["id"], path, "endure")
```

Change `new_ctx` to seed the floor:

```gdscript
static func new_ctx(seed: int, building_id: int) -> Dictionary:
	return {"seed": seed, "id": building_id, "path": "", "need_floor": 0.0,
			"frame": zero_frame(Transform3D.IDENTITY)}
```

Change `resolve`'s unknown-node fallback to carry a need:

```gdscript
	assert(false, "unknown node type: %s" % str(node.keys()))
	return {"parts": [], "frame": zero_frame(ctx["frame"]["xf"]),
			"need": ctx["need_floor"]}
```

In `_mass`, compute the need, put it on the part, and return it. The degenerate
early return reports the floor unchanged — a node that emitted nothing must not
raise the floor for whatever stacks above it:

```gdscript
	if w <= EPS or d <= EPS or h <= EPS:
		return {"parts": [], "frame": zero_frame(xf),
				"need": ctx["need_floor"]}
```

and, replacing the part literal's `"tag": ""`:

```gdscript
	var need := maxf(ctx["need_floor"], _draw_need(ctx, path))
	var part := {"kind": kind, "xf": xf, "params": params,
			"color": Color.MAGENTA, "tag": "", "need": need, "y": 0.0,
			"role": n.get("role", "plaster")}
	return {"parts": [part], "need": need,
			"frame": {"xf": xf, "footprint": Vector2(w, d), "height": h}}
```

(`tag` stays for now and is removed in Task 4, so the suite keeps passing at
every step.)

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: all tests pass, determinism gate passes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: a mass draws its endurance, and inherits a floor"
```

---

### Task 2: A stack's running maximum is the load path

> **Superseded — read this first.** The single inherited `need_floor` this task
> specifies shipped, then failed twice on the DISTRIBUTION of levels and was
> replaced by an inherited BAND (`ctx["need_lo"]` / `ctx["need_hi"]`, the
> sub-range of `[ENDURE_LO, ENDURE_HI]` a node and its descendants may occupy).
> A stack partitions its band across its children in order; a row hands every
> child the band whole; a ring draws once inside its band for its whole subtree.
> See `_draw_need` in `game/diorama/compose.gd` for the rule and both failures.
> The strict-read rationale below still applies, to the band keys instead.
>
> Tasks 1-3 are left as written on purpose: they record what was attempted, and
> the two failed rules are worth keeping visible.

**Files:**
- Modify: `game/diorama/compose.gd` — `_stack`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: `ctx["need_floor"]`, `resolve(...)["need"]` from Task 1.
- Produces: no new names. `_stack` now returns the maximum `need` over its
  children, and hands child *i* a floor equal to child *i−1*'s returned `need`.

**The rule and why it is free.** A part cannot outlive what it rests on. In a
`stack` the children are literally stacked, so carrying a running maximum down
the child loop *is* the load path — derived from the vocabulary, with nothing
authored. A stack therefore has a non-decreasing `need` going up, and the highest
child is always the first to fall.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_compose.gd`:

```gdscript
func test_need_is_non_decreasing_up_a_stack() -> void:
	# The load-path property: nothing survives its own support. Swept over many
	# ids because a single draw could satisfy this by luck.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0), _box("d", 2.0, 2.0, 2.0)]}}
	for id in range(24):
		var parts := DioramaCompose.build(tall, SEED, id)
		assert_eq(parts.size(), 4, "fixture should emit four parts")
		for i in range(1, parts.size()):
			assert_true(parts[i]["need"] >= parts[i - 1]["need"],
					"id %d: part %d (need %f) outlives its support (need %f)"
					% [id, i, parts[i]["need"], parts[i - 1]["need"]])


func test_a_stack_reports_the_need_of_its_weakest_link() -> void:
	# What rests on a stack fails when any part of that stack fails, so the
	# stack must report its MAXIMUM need, not its minimum or its last child's.
	var tall := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("b", 2.0, 2.0, 2.0),
		_box("c", 2.0, 2.0, 2.0)]}}
	var out := DioramaCompose.resolve(tall, DioramaCompose.new_ctx(SEED, 5))
	var worst := -INF
	for p: Dictionary in out["parts"]:
		worst = maxf(worst, p["need"])
	assert_almost_eq(out["need"], worst, 1e-6,
			"stack under-reported how soon it fails")


func test_a_stack_child_that_resolves_away_does_not_raise_the_floor() -> void:
	# A zero-height mass emits nothing. If it still raised the running floor,
	# a style could make everything above it fragile by declaring a part it
	# never renders — an invisible cause for a visible problem.
	var with_ghost := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("ghost", 2.0, 2.0, 0.0),
		_box("c", 2.0, 2.0, 2.0)]}}
	var without := {"stack": {"name": "t", "children": [
		_box("a", 2.0, 2.0, 2.0), _box("c", 2.0, 2.0, 2.0)]}}
	var a := DioramaCompose.build(with_ghost, SEED, 5)
	var b := DioramaCompose.build(without, SEED, 5)
	assert_eq(a.size(), 2, "the zero-height child should emit nothing")
	assert_almost_eq(a[1]["need"], b[1]["need"], 1e-6,
			"a child that emitted nothing changed what stacks above it")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — `test_need_is_non_decreasing_up_a_stack` fails on some id
(children currently draw independently), and `_stack`'s return has no `"need"`.

- [ ] **Step 3: Implement**

In `_stack`, add a running floor before the child loop:

```gdscript
	# A part can never outlive what it rests on, so each child inherits the
	# need of the one below as a floor. Carrying that maximum down the loop IS
	# the load path — the vocabulary already says what rests on what, so no
	# style author states it.
	var running: float = ctx["need_floor"]
```

Add `need_floor` to the child ctx literal:

```gdscript
		var child_ctx := {"seed": ctx["seed"], "id": ctx["id"], "path": path,
				"need_floor": running,
				"frame": {"xf": base_xf.translated_local(
						Vector3(centre.x, y, centre.y)),
						"footprint": carried, "height": 0.0}}
```

Raise the running maximum immediately after resolving each child, before the
`if f["height"] > EPS` block (a child that emitted nothing returns the floor
unchanged, so this is safe for ghosts):

```gdscript
		var out := resolve(child, child_ctx)
		parts.append_array(out["parts"])
		running = maxf(running, out["need"])
```

Add `need` to both return sites:

```gdscript
	if bounds.is_empty():
		return {"parts": parts, "frame": zero_frame(base_xf), "need": running}
	var mid := bounds.mid()
	return {"parts": parts, "need": running,
			"frame": {"xf": base_xf.translated_local(Vector3(mid.x, 0, mid.y)),
					"footprint": bounds.span(), "height": y}}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: a stack's running maximum is its load path"
```

---

### Task 3: Rows stay independent, rings fall whole

> **Superseded — read this first.** The single inherited `need_floor` this task
> specifies shipped, then failed twice on the DISTRIBUTION of levels and was
> replaced by an inherited BAND (`ctx["need_lo"]` / `ctx["need_hi"]`, the
> sub-range of `[ENDURE_LO, ENDURE_HI]` a node and its descendants may occupy).
> A stack partitions its band across its children in order; a row hands every
> child the band whole; a ring draws once inside its band for its whole subtree.
> See `_draw_need` in `game/diorama/compose.gd` for the rule and both failures.
> The strict-read rationale below still applies, to the band keys instead.
>
> Tasks 1-3 are left as written on purpose: they record what was attempted, and
> the two failed rules are worth keeping visible.

**Files:**
- Modify: `game/diorama/compose.gd` — `_row`, `_ring`
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces: no new names. `_row` hands every child the *inherited* floor
  unchanged and returns the maximum over them. `_ring` computes one need and
  imposes it on every part it emits.

**The distinction, and why it is honest.** A row's children stand beside each
other, so one falling says nothing about the next — a terrace loses a house, not
the street, and a colonnade stands with columns missing. A ring's children are an
arch: remove one voussoir and the arc collapses. So `ring` is **cohesive** — one
draw for the whole subtree — while `row` is **articulated**.

Note `_ring` does not call `resolve()` on its children at all; it builds parts
inline. So imposing one value is a matter of writing it into each part literal.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_compose.gd`:

```gdscript
func _arch() -> Dictionary:
	return {"stack": {"name": "a", "children": [
		_box("plinth", 5.0, 2.0, 0.4),
		{"ring": {"name": "span", "radius": 1.5, "from": 0.0, "to": PI,
				"count": 7,
				"of": {"mass": {"name": "vs", "kind": "box", "w": 0.4,
						"d": 0.6, "role": "plaster"}}}}]}}


func test_every_voussoir_in_a_ring_shares_one_need() -> void:
	# An arch is not nine independent stones. Remove one and the arc is gone,
	# so the ring draws once and imposes it on the whole subtree.
	for id in range(12):
		var parts := DioramaCompose.build(_arch(), SEED, id)
		var ring_parts := parts.slice(1)
		assert_eq(ring_parts.size(), 7, "id %d: expected seven voussoirs" % id)
		for p: Dictionary in ring_parts:
			assert_almost_eq(p["need"], ring_parts[0]["need"], 1e-9,
					"id %d: a voussoir drew its own need" % id)


func test_a_ring_never_outlives_what_it_springs_from() -> void:
	for id in range(12):
		var parts := DioramaCompose.build(_arch(), SEED, id)
		assert_true(parts[1]["need"] >= parts[0]["need"],
				"id %d: the arc (need %f) outlived its plinth (need %f)"
				% [id, parts[1]["need"], parts[0]["need"]])


func test_row_siblings_draw_independently() -> void:
	# The property that makes a colonnade lose columns rather than vanish.
	# Asserted by FINDING a seed where two siblings differ — a test that never
	# observes the difference would pass against a cohesive row too.
	var terrace := {"row": {"name": "block", "advance": 1.0, "children": [
		_box("west", 2.0, 2.0, 2.0), _box("east", 2.0, 2.0, 2.0)]}}
	var found := false
	for id in range(24):
		var parts := DioramaCompose.build(terrace, SEED, id)
		assert_eq(parts.size(), 2, "fixture should emit two parts")
		if not is_equal_approx(parts[0]["need"], parts[1]["need"]):
			found = true
	assert_true(found, "24 ids and no row ever had siblings of differing need")


func test_a_row_reports_the_need_of_its_weakest_child() -> void:
	# What rests on a row fails when any of its supports does — an arch falls
	# when either pier goes, so the row reports the MAXIMUM.
	var piers := {"row": {"name": "piers", "gap": 2.0, "children": [
		_box("west", 0.4, 0.6, 1.6), _box("east", 0.4, 0.6, 1.6)]}}
	var out := DioramaCompose.resolve(piers, DioramaCompose.new_ctx(SEED, 5))
	assert_almost_eq(out["need"],
			maxf(out["parts"][0]["need"], out["parts"][1]["need"]), 1e-6,
			"row under-reported how soon it fails")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — ring parts have no `need` key and `_row`/`_ring` returns have
no `"need"`.

- [ ] **Step 3: Implement**

In `_row`, add the floor to the child ctx literal in the first (resolve) pass —
the *inherited* floor, unchanged, for every child:

```gdscript
	for child in children:
		var child_ctx := {"seed": seed, "id": id, "path": path,
				"need_floor": ctx["need_floor"],
				"frame": {"xf": base_xf,
						"footprint": ctx["frame"]["footprint"], "height": 0.0}}
		resolved.append(resolve(child, child_ctx))
```

Immediately after that loop, take the maximum:

```gdscript
	# Siblings stand beside one another, so one falling says nothing about the
	# next — but whatever rests on the ROW fails when any of them does.
	var need: float = ctx["need_floor"]
	for out: Dictionary in resolved:
		need = maxf(need, out["need"])
```

Add `need` to both `_row` return sites:

```gdscript
	if bounds.is_empty():
		return {"parts": parts, "frame": zero_frame(base_xf), "need": need}
```

```gdscript
	return {"parts": parts, "need": need,
			"frame": {"xf": base_xf, "footprint": bounds.span(),
					"height": tallest}}
```

In `_ring`, compute one value before the segment loop:

```gdscript
	# Cohesive, unlike a row: an arch is not N independent stones. Remove one
	# voussoir and the arc collapses, so the ring draws once and every part it
	# emits carries that same need.
	var need := maxf(ctx["need_floor"], _draw_need(ctx, path))
```

Write it into the part literal, replacing `"tag": "", "y": 0.0`:

```gdscript
		parts.append({"kind": kind, "xf": xf,
				"params": params, "color": Color.MAGENTA,
				"tag": "", "need": need, "y": 0.0,
				"role": body.get("role", "plaster")})
```

Add `need` to both `_ring` return sites:

```gdscript
	if lo.x == INF:
		return {"parts": parts, "frame": zero_frame(base_xf), "need": need}
```

```gdscript
	return {"parts": parts, "need": need,
			"frame": {"xf": base_xf, "footprint": hi - lo, "height": top}}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: rows articulate, rings cohere"
```

---

### Task 4: Retire `tag`, and put `need` under the determinism gate

**Files:**
- Modify: `game/diorama/compose.gd` — `_mass`, `_ring`, `_finish`, `build` doc
- Modify: `test/test_diorama_compose.gd` — remove two tag tests
- Modify: `tools/diorama_compose_fingerprint.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: parts no longer carry `"tag"`. They still carry `"y"` (the part's
  centre height) — nothing else reads it today, but it is cheap, correct, and
  the assembly tween will want it.

**Why the fingerprint needs a change.** The existing gate folds parts through
`DioramaMeshKit` and digests the geometry. `need` does not affect geometry, so a
`need` that diverged across processes would sail through unnoticed. It gets its
own fold, mixed into the same printed integer. The generator is also extended to
cover `hero_arch`, because the ring is where the cohesive draw lives and
`residential` has no ring at all.

- [ ] **Step 1: Delete the tag tests and write the replacement**

In `test/test_diorama_compose.gd`, **delete** `test_a_small_cone_on_top_is_an_accent`
and `test_tags_are_monotonic_in_height` entirely. Both assert a scheme that no
longer exists; `test_need_is_non_decreasing_up_a_stack` from Task 2 is the
property the second one was reaching for. Keep `test_y_is_the_part_centre_height`.

Append:

```gdscript
func test_parts_no_longer_carry_a_tag() -> void:
	# The four-way height/kind partition is gone, replaced by `need`. Asserted
	# so a merge cannot quietly reintroduce a field nothing maintains.
	for p: Dictionary in DioramaCompose.build(_tower(), SEED, 1):
		assert_false(p.has("tag"), "a part still carries a tag")
		assert_true(p.has("need"), "a part is missing its need")
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_compose.gd -gexit`
Expected: FAIL — "a part still carries a tag".

- [ ] **Step 3: Implement**

In `_mass`, drop `"tag": "",` from the part literal. In `_ring`, drop
`"tag": "",` from the part literal.

Replace `_finish` entirely — it keeps the `y` derivation and loses the bands:

```gdscript
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
```

`_area_of` becomes unreachable once the accent rule is gone — delete it.
`_height_of` is still used by `_finish`; keep it.

Update `build`'s doc comment:

```gdscript
## Public entry point. Resolve the tree, then derive each part's centre height.
## A part's `need` — the condition at which it survives — was already settled
## during resolution, where the tree still knows what rests on what.
```

In `tools/diorama_compose_fingerprint.gd`, extend `SEEDS`' loop body to cover two
styles and fold `need` in:

```gdscript
const SEEDS := [42, 7, 20260815]
const IDS := [0, 1, 2, 3, 4]


func _init() -> void:
	for world_seed in SEEDS:
		print("%d %d" % [world_seed, _fingerprint(world_seed)])
	quit()


## Builds several specimens for one seed and folds them into one digest.
##
## Two styles, not one: `hero_arch` is the only migrated style with a `ring`,
## and the ring's cohesive draw is the part of the need computation most likely
## to diverge across processes.
##
## `need` is folded separately from the geometry. The mesh digest would not
## notice a need that differed between processes, because need changes no
## vertex — so a silent cross-process divergence in the ruin filter would pass
## a gate that exists precisely to catch that class of bug.
static func _fingerprint(world_seed: int) -> int:
	var b := DioramaMeshKit.new()
	var needs := 0
	for style in [DioramaStyles.residential(), DioramaStyles.hero_arch()]:
		for id in IDS:
			var parts := DioramaCompose.build(style, world_seed, id)
			DioramaCompose.apply_roles(parts, DioramaStyles.ROLES)
			DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
			for p: Dictionary in parts:
				# Quantised, because a float printed through two processes must
				# compare equal bit-for-bit and 1e-6 is far finer than any
				# visible difference in when a part falls.
				needs = (needs * 31 + int(round(p["need"] * 1000000.0))) \
						& 0x7FFFFFFFFFFFFFF
	return b.fingerprint() ^ needs
```

- [ ] **Step 4: Run to verify**

Run: `./test.sh`
Expected: all pass. The determinism section must print
`tools/diorama_compose_fingerprint.gd: 3 seeds reproduced identically across
processes`. Exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd tools/diorama_compose_fingerprint.gd
git commit -m "compose: retire the height tag; put need under the determinism gate"
```

---

### Task 5: The filter, the sentinel and the standing fragment

**Files:**
- Create: `game/diorama/condition.gd`
- Test: `test/test_diorama_condition.gd` (create)

**Interfaces:**
- Consumes: parts carrying `"need": float` from Tasks 1–4.
- Produces:
  - `class_name DioramaCondition`
  - `static func filter(parts: Array, condition: float) -> Array`

**The three rules.** (1) `condition <= 0` returns empty — zero means *gone*, a
sentinel for a building removed rather than ruined, and AC5 only requires
non-empty *above* zero. (2) Otherwise condition is clamped up to the second
smallest distinct `need`, so a footprint plus one fragment always survives; a
bare pad is a foundation, not a ruin. (3) Everything at or below the effective
condition survives, which is monotone by construction.

- [ ] **Step 1: Write the failing tests**

Create `test/test_diorama_condition.gd`:

```gdscript
extends GutTest
## Properties of the ruin filter.
##
## These are asserted on returned arrays rather than on a picture, so they run
## on a host with no rendering context — the same reason test_diorama_compose.gd
## checks data instead of frames.

const SEED := 4242
const RUNGS := [1.0, 0.75, 0.5, 0.25, 0.05]


func _styles() -> Dictionary:
	return {"residential": DioramaStyles.residential(),
			"hero_arch": DioramaStyles.hero_arch(),
			"civic": DioramaStyles.civic(),
			"stepped": DioramaStyles.stepped()}


func _needs(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		out.append(p["need"])
	return out


func test_survivors_nest_as_condition_falls() -> void:
	# AC2, ordered loss. Filtering on a fixed per-part threshold is monotone by
	# construction, so this cannot fail without the filter having grown a
	# second rule. Swept over every style and rung pair to keep it honest.
	for style_name: String in _styles():
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			for i in range(RUNGS.size() - 1):
				var higher := DioramaCondition.filter(parts, RUNGS[i])
				var lower := DioramaCondition.filter(parts, RUNGS[i + 1])
				for p: Dictionary in lower:
					assert_true(higher.has(p),
							"%s id %d: a part survived %f but not %f"
							% [style_name, id, RUNGS[i + 1], RUNGS[i]])


func test_condition_zero_means_gone() -> void:
	var parts := DioramaCompose.build(DioramaStyles.civic(), SEED, 1)
	assert_eq(DioramaCondition.filter(parts, 0.0).size(), 0,
			"zero should mean removed, not ruined")
	assert_eq(DioramaCondition.filter(parts, -1.0).size(), 0,
			"a negative condition should also be empty")


func test_a_ruin_is_never_a_bare_footprint() -> void:
	# AC4 and AC5. A single slab is a foundation, not a ruin — the intent asks
	# for a footprint AND a surviving arch or wall.
	for style_name: String in _styles():
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			var distinct := {}
			for n in _needs(parts):
				distinct[n] = true
			var got := DioramaCondition.filter(parts, 0.01)
			assert_gt(got.size(), 0,
					"%s id %d: a positive condition returned nothing"
					% [style_name, id])
			if distinct.size() > 1:
				assert_gt(got.size(), 1,
						"%s id %d: bottomed out at a single part"
						% [style_name, id])


func test_full_condition_keeps_everything() -> void:
	for style_name: String in _styles():
		var parts := DioramaCompose.build(_styles()[style_name], SEED, 2)
		assert_eq(DioramaCondition.filter(parts, 1.0).size(), parts.size(),
				"%s lost a part at full condition" % style_name)


func test_a_ring_survives_or_falls_whole() -> void:
	# The property the whole assemblies design exists for: an arch is not nine
	# independent stones, so no condition may leave a partial arc.
	var parts := DioramaCompose.build(DioramaStyles.hero_arch(), SEED, 3)
	for rung in RUNGS:
		var got := DioramaCondition.filter(parts, rung)
		var by_need := {}
		for p: Dictionary in got:
			by_need[p["need"]] = int(by_need.get(p["need"], 0)) + 1
		var all_by_need := {}
		for p: Dictionary in parts:
			all_by_need[p["need"]] = int(all_by_need.get(p["need"], 0)) + 1
		for n in by_need:
			assert_eq(by_need[n], all_by_need[n],
					"rung %f: a need level survived only partially" % rung)


func test_the_empty_building_filters_to_nothing() -> void:
	assert_eq(DioramaCondition.filter([], 0.5).size(), 0,
			"an empty part list should filter to an empty result")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_condition.gd -gexit`
Expected: FAIL — `Identifier "DioramaCondition" not declared`.

- [ ] **Step 3: Implement**

Create `game/diorama/condition.gd`:

```gdscript
class_name DioramaCondition
extends RefCounted
## Turns a generated building into its own ruin by selecting over the parts it
## already emitted. Ruins are the same buildings — no separate assets.
##
## Every part carries `need`: the condition at or above which it survives, drawn
## during resolution where the style tree still knows what rests on what. So the
## filter here is one comparison, and it knows nothing about the tree.
##
## That is the whole point. Because `need` is fixed per part before this runs,
## survival is monotone in condition BY CONSTRUCTION — the set surviving at a
## low condition is necessarily a subset of the set surviving at a higher one,
## and no style can violate it. The predecessor scheme derived a four-way tag
## from normalised height here, at the end, and could not make that guarantee:
## a census found residential emitting 0% `base` and civic tagging its
## load-bearing colonnade as decoration.


## Parts of `parts` that survive at `condition`, in their original order.
##
## `condition` 0 means GONE — a building removed rather than ruined. Above zero
## the result is never empty, and never a bare footprint.
static func filter(parts: Array, condition: float) -> Array:
	if parts.is_empty() or condition <= 0.0:
		return []
	var effective := maxf(condition, _fragment_floor(parts))
	var out: Array = []
	for p: Dictionary in parts:
		if effective >= p["need"]:
			out.append(p)
	return out


## The condition below which this building would come back as a bare pad.
##
## Returns the SECOND smallest distinct `need`, so clamping to it always leaves
## the footprint plus one fragment above it — which fragment varies by seed, so
## a field of ruins is not a field of identical stumps. The intent's bottom rung
## is "footprint AND a surviving arch or wall": two things, and a lone slab
## reads desolate against the guardrail that ruins imply use and adaptation.
##
## Clamping condition upward is monotone, so this cannot break ordered loss:
## every condition below the floor yields the same set, and identical sets are
## supersets of one another.
static func _fragment_floor(parts: Array) -> float:
	var lowest := INF
	var second := INF
	for p: Dictionary in parts:
		var n: float = p["need"]
		if n < lowest:
			second = lowest
			lowest = n
		elif n > lowest and n < second:
			second = n
	# A building with one distinct need has no second level to spare; it
	# survives whole or not at all.
	return lowest if second == INF else second
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/condition.gd test/test_diorama_condition.gd
git commit -m "condition: the ruin filter, its zero sentinel and its standing fragment"
```

---

### Task 6: The census guard

**Files:**
- Test: `test/test_diorama_condition.gd` (append)

**Interfaces:**
- Consumes: `DioramaCompose.build`, `DioramaStyles.*`.
- Produces: nothing. This is the measurement that motivated the spec, re-run as
  a standing assertion.

**Why spread and not presence.** "Every style has a part at its own minimum
`need`" is true by definition and would pass against the broken scheme. The
assertion with teeth is that a style's needs *spread*: at least three distinct
levels and a real range between the most and least durable. `stepped` (0%
`upper`) and `residential` (0% `base`) would each have failed exactly that, and
it is the property a decay ladder requires in order to exist at all.

- [ ] **Step 1: Write the failing test**

Append to `test/test_diorama_condition.gd`:

```gdscript
func test_every_style_has_a_ladder_to_decay_down() -> void:
	# The census that motivated this design, standing as a test. Under the old
	# height-band tags residential emitted 0% `base` and stepped 0% `upper`,
	# which meant neither had an ORDER to lose things in — they went from whole
	# to gone. Asserting "has a part at its minimum need" would be vacuous, so
	# assert spread instead.
	for style_name: String in _styles():
		var levels := {}
		var lo := INF
		var hi := -INF
		for id in range(24):
			for n in _needs(DioramaCompose.build(_styles()[style_name], SEED, id)):
				levels[snappedf(n, 0.001)] = true
				lo = minf(lo, n)
				hi = maxf(hi, n)
		assert_gt(levels.size(), 2,
				"%s has %d distinct need levels over 24 ids — too few to decay"
				% [style_name, levels.size()])
		assert_gt(hi - lo, 0.2,
				"%s spans only %f in need; its parts all fall together"
				% [style_name, hi - lo])


func test_every_style_loses_something_before_it_loses_everything() -> void:
	# The failure mode stepped had: no ordering, so no rung of the ladder shows
	# a partial building. At least one of the intent's five rungs must leave a
	# style strictly between whole and its floor.
	for style_name: String in _styles():
		var partial := false
		for id in range(8):
			var parts := DioramaCompose.build(_styles()[style_name], SEED, id)
			for rung in RUNGS:
				var got := DioramaCondition.filter(parts, rung).size()
				if got > 0 and got < parts.size():
					partial = true
		assert_true(partial,
				"%s is never partially ruined at any rung — it goes from whole to gone"
				% style_name)
```

- [ ] **Step 2: Run to verify it passes or fails honestly**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gtest=res://test/test_diorama_condition.gd -gexit`

Expected: PASS. **If either fails, do not weaken the assertion.** A failure here
means the design does not deliver what the spec claims — report it and stop.
`hero_arch` is the one to watch: its ring is cohesive, so nine of its fourteen
parts share one need, and if the remaining draws cluster it may genuinely lack
three levels. If that happens the finding is real and belongs in the PR body.

- [ ] **Step 3: Commit**

```bash
git add test/test_diorama_condition.gd
git commit -m "condition: the census that killed height bands, as a standing guard"
```

---

### Task 7: The style × condition sheet, as a scene

**Files:**
- Create: `game/diorama/condition_sheet.gd`
- Create: `game/diorama/condition_sheet.tscn`
- Modify: `game/diorama/lineup.gd:21` and `:79-80`

**Interfaces:**
- Consumes: `DioramaCondition.filter`, `DioramaCompose.build`,
  `DioramaCompose.apply_roles`, `DioramaStyles.ROLES`, `DioramaMeshKit`,
  `DioramaGrammar.emit`.
- Produces: a scene at `res://game/diorama/condition_sheet.tscn` photographable
  by `./capture.sh --scene`.

**Why a new scene rather than an axis on `lineup`.** AC7 says the axes are the
same mechanism and this should cost little; if it costs more, say so. It costs a
little more. `lineup` varies **one** thing across a grid (building id) for one
style. This sheet varies **two** (style down, condition across) with the id held
fixed so a row reads as one building decaying. Folding both into one scene means
a mode flag and two code paths through the cell builder. The price paid instead
is about fifty lines of stage and camera setup that resemble `lineup`'s. Extract
the shared part when a third sheet appears, not before.

**Also fix a stale enum.** `lineup.gd:21` still offers only
`@export_enum("residential", "hero_arch")` and line 79 falls back to
`residential()` for anything else, so `civic` and `stepped` — migrated in slice
2 — cannot be sheeted at all. One-line fix, folded in here because this task is
where it was noticed.

- [ ] **Step 1: Fix the stale style enum**

In `game/diorama/lineup.gd`, line 21:

```gdscript
@export_enum("residential", "hero_arch", "civic", "stepped")
var style: String = "residential"
```

and lines 79–80:

```gdscript
	var tree: Dictionary = DioramaStyles.for_name(style)
```

In `game/diorama/styles.gd`, add the lookup so two callers do not each carry a
ladder of `if`s:

```gdscript
## Style trees by name, for scenes that pick one from an export.
static func for_name(name: String) -> Dictionary:
	match name:
		"hero_arch": return hero_arch()
		"civic": return civic()
		"stepped": return stepped()
		_: return residential()


## Every style, in sheet order.
const NAMES := ["residential", "civic", "stepped", "hero_arch"]
```

- [ ] **Step 2: Write the sheet scene script**

Create `game/diorama/condition_sheet.gd`:

```gdscript
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
@export var cell_size: float = 5.0
@export var camera_pitch_deg: float = 34.0
@export var fov_horizontal_deg: float = 24.0

## The intent's five named rungs: complete, aging, upper masses gone,
## structural remnants, footprint and a survivor.
const RUNGS := [1.0, 0.75, 0.5, 0.25, 0.05]

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
		for c in range(cols):
			var at := Vector3((c - (cols - 1) * 0.5) * cell_size, 0.0,
					(r - (rows - 1) * 0.5) * cell_size)
			tallest = maxf(tallest, _add_cell(r, c, at, mat))
	_add_stage(rows, cols, mat)
	for c in range(cols):
		_add_caption("%.2f" % RUNGS[c], Vector3(
				(c - (cols - 1) * 0.5) * cell_size, 0.02,
				(rows * 0.5) * cell_size))
	for r in range(rows):
		_add_caption(DioramaStyles.NAMES[r], Vector3(
				-(cols * 0.5 + 0.6) * cell_size, 0.02,
				(r - (rows - 1) * 0.5) * cell_size))
	_add_camera(rows, cols, tallest)
	_add_light()


## Returns the cell's highest point, so the camera can frame what is actually
## there rather than a constant that goes stale when a style's proportions
## change.
func _add_cell(r: int, c: int, at: Vector3,
		mat: StandardMaterial3D) -> float:
	var style: String = DioramaStyles.NAMES[r]
	# The id is the ROW, not the cell: every cell in a row is the same building
	# at a different condition.
	var parts := DioramaCompose.build(DioramaStyles.for_name(style),
			world_seed, r)
	var survivors := DioramaCondition.filter(parts, RUNGS[c])
	DioramaCompose.apply_roles(survivors, DioramaStyles.ROLES)
	var b := DioramaMeshKit.new()
	DioramaGrammar.emit(b, survivors, Transform3D.IDENTITY)
	var inst := MeshInstance3D.new()
	inst.name = "Cell_%s_%d" % [style, c]
	inst.mesh = b.commit()
	inst.material_override = mat
	inst.position = at
	add_child(inst)
	var top := 0.0
	for p: Dictionary in survivors:
		# A primitive builds UPWARD from its own origin, so its top is the
		# origin plus its own height. Height lives under `size.y` for boxes and
		# `height` for the round kinds, the same split _params_for writes.
		var prm: Dictionary = p["params"]
		var h: float = prm["size"].y if prm.has("size") else prm.get("height", 0.0)
		top = maxf(top, p["xf"].origin.y + h)
	return at.y + top


## The pad's TOP sits at y = 0, because add_box builds upward from its origin
## and every building stands on the plane. A pad centred on zero would bury
## the bottom of every specimen.
func _add_stage(rows: int, cols: int, mat: StandardMaterial3D) -> void:
	var b := DioramaMeshKit.new()
	var w := (cols + 1.4) * cell_size
	var d := (rows + 1.0) * cell_size
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.2 * cell_size, -0.24, 0)),
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
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	add_child(label)


## Distance derived from the frustum rather than guessed as a multiple of the
## span — a constant has no relation to the FOV and goes wrong the moment
## either changes.
func _add_camera(rows: int, cols: int, tallest: float) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov_horizontal_deg
	var span := maxf((cols + 1.4) * cell_size, (rows + 1.0) * cell_size)
	var dist := (span * 0.5) / tan(deg_to_rad(fov_horizontal_deg) * 0.5)
	var pitch := deg_to_rad(camera_pitch_deg)
	cam.position = Vector3(0, sin(pitch) * dist + tallest * 0.5,
			cos(pitch) * dist)
	cam.look_at(Vector3(0, tallest * 0.3, 0), Vector3.UP)
	cam.current = true
	add_child(cam)


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
```

- [ ] **Step 3: Write the scene file**

Create `game/diorama/condition_sheet.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://game/diorama/condition_sheet.gd" id="1"]

[node name="ConditionSheet" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 4: Verify the scene builds headless**

Run: `godot --headless --quit-after 60 game/diorama/condition_sheet.tscn`
Expected: exit 0, no errors printed.

Then run the full suite: `./test.sh` — expected exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/condition_sheet.gd game/diorama/condition_sheet.tscn game/diorama/lineup.gd game/diorama/styles.gd
git commit -m "sheet: styles down, condition across, one building per row"
```

---

### Task 8: Capture, commit and link the sheet

**Files:**
- Create: `docs/shots/mbs-condition/` (the frame and its sidecar)
- Modify: the PR body

**Interfaces:**
- Consumes: `condition_sheet.tscn` from Task 7.
- Produces: the committed evidence AgDR-008 requires and AgDR-011 links.

**`capture.sh` wipes its output directory per run**, so this `--name` must not
collide with an existing one under `docs/shots/`.

- [ ] **Step 1: Capture**

```bash
./capture.sh --scene res://game/diorama/condition_sheet.tscn --name mbs-condition --label condition-ladder
```

Expected: a PNG under `docs/shots/mbs-condition/`.

- [ ] **Step 2: Look at it**

Open the frame. Check, in order:

1. Are all four style rows present and all five condition columns present?
2. Are the captions legible and *not* occluded by the stage pad?
3. Does column 1 (condition 1.00) show four complete buildings?
4. Does `hero_arch` at some middle rung show **an arc still standing** with its
   entablature and finial gone? That is the single image this whole slice was
   designed around. If the arc is never intact while something above it is gone,
   the cohesive-ring rule is not doing its job — say so rather than shipping it.
5. Does any row go straight from whole to footprint with nothing in between?

If the framing is wrong, adjust `cell_size` / `fov_horizontal_deg` /
`camera_pitch_deg` in the scene and re-capture. Do not adjust `ENDURE_LO` or
`ENDURE_HI` to make the picture nicer without saying so in the PR body — those
change what every building in the game does, not just this sheet.

- [ ] **Step 3: Commit the frame**

```bash
git add docs/shots/mbs-condition/
git commit -m "docs: the style by condition sheet"
```

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin claude/mbs-slice3-condition
```

The PR body must:

- Link the sheet by **absolute, sha-pinned** `raw.githubusercontent.com` URL per
  AgDR-011. The suite's `shot-links` check prints the correct owner/repo and sha.
- State plainly that **AC11 and AC12 are unverified by the agent** — whether
  every style reads as a ruin rather than a smaller version of itself, and
  whether the tone is serene rather than grimdark, are the owner's calls.
- Report the census guard's numbers from Task 6: distinct need levels and spread
  per style.
- Note that `tag` was removed and `need` added — a parts-contract change.
- Note the engine version commit rides along on this branch.

Before pushing, per the concurrency risk: run `gh pr list --state open` and check
nothing else is touching `game/diorama/`. After any merge of another branch into
main, re-run `./test.sh` **against the merge result**, not just this branch —
#17's collision passed the full suite on both sides alone.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:

| Spec section | Task |
|---|---|
| `need` replaces the tag | 1, 4 |
| `mass` draws; floor inherited | 1 |
| `stack` running maximum = load path | 2 |
| `row` independent; container reports max | 3 |
| `ring` cohesive | 3 |
| `ENDURE_LO` / `ENDURE_HI` | 1 |
| The filter | 5 |
| `condition == 0` sentinel | 5 |
| Standing-fragment rule | 5 |
| AC2 monotonicity | 5 (test), guaranteed by 1–3 |
| AC3 determinism | 4 (fingerprint fold) |
| AC6 accent dissolved | 4 (tag removal + comment) |
| AC7 condition axis | 7 |
| AC8 committed sheet | 8 |
| AC9 compose stays pure | Global Constraints; nothing in 1–4 adds I/O |
| Testing items 1–7 | 5, 6 |

**Gaps found and closed during review:**

- The spec's testing item 4 (row independence "asserted by finding the
  difference") needed the loop-and-flag form, not a single-seed comparison —
  written that way in Task 3.
- The spec did not mention that `lineup.gd`'s style enum is stale and cannot
  select `civic` or `stepped`. Folded into Task 7 with a `DioramaStyles.for_name`
  helper so two callers do not each carry an `if` ladder.
- The spec did not say how `need` gets under the determinism gate. The existing
  fingerprint folds through geometry only, and `need` moves no vertex — Task 4
  adds a separate fold and extends the generator to `hero_arch`, the only
  migrated style with a ring.

**Two defects found in this plan during review and fixed inline:**

- Task 5's ring test carried a dead loop that computed nothing — removed.
- Task 7's cell-height expression cancelled algebraically to `p["y"]`, and its
  stage pad was centred such that its top sat *above* y = 0, burying the bottom
  of every specimen. Both rewritten against `add_box`'s actual convention:
  primitives build **upward** from their origin, so a pad whose top is the
  ground plane has its origin at `-height`.

---

## Done bar

1. `./test.sh` exits 0.
2. `tag` is gone; `need` is on every part and under the determinism gate.
3. All four styles pass the census guard.
4. The sheet is committed and linked by sha-pinned URL.
5. The PR body states AC11 and AC12 are unverified by the agent.
