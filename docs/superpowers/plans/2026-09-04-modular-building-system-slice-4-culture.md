# MBS slice 4 — culture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a culture modulate the shared building vocabulary — proportions,
crown profile and palette — so one style tree under two cultures produces two
peoples rather than one people in two colours.

**Architecture:** A culture is a dictionary, like a style. It transforms the
**range** a value is sampled from, never the channel draw itself — so the same
building id under two cultures draws the same `u` and lands at the same relative
position in each modulated range. `kind: "crown"` resolves through the culture to
a concrete primitive, which is the silhouette half of the bar.

**Tech Stack:** Godot 4.7.1, GDScript, GUT test framework.

**Spec:** `docs/superpowers/specs/2026-09-04-modular-building-system-slice-4-culture.md`

**Ticket:** #35. Read the spec before Task 1 — the measurement that motivates
every choice lives there.

## Global Constraints

- **The culture must NEVER enter `channel()`.** This is the property the whole
  design rests on. If culture reached the channel, the same id under two cultures
  would draw unrelated values and every style would look like a different
  building. Culture changes the range, not the draw.
- **`compose.gd` stays pure.** No rendering, no scene-tree access, no I/O.
- **Godot's built-in `hash()` is banned.** Use `DioramaCompose.str_hash()` —
  FNV-1a — because `hash()` has no cross-platform stability guarantee and the
  determinism gate compares across processes.
- **All randomness goes through `DioramaCompose.channel(seed, id, path, purpose)`.**
  Never a sequential RNG.
- **Channels are keyed on node *names*, never index paths.**
- **The `lo <= hi` assert in `sample()` must run on the MODULATED range**, not
  the authored one — otherwise a bad multiplier slips past the guard that exists
  to catch reversed-range typos.
- **Only these purposes are modulated:** `h` by `verticality`; `w` and `d` by
  `thickness`; `setback` by `setback`; all of those additionally by `variance`.
  `oversize`, `taper`, `radius`, `from`, `to`, `advance`, `gap` and `count` are
  deliberately unmodulated.
- **`./test.sh` must exit 0** at the end of every task. It runs GUT, then a
  cross-process determinism check, then a headless launch of the main scene.
- **Do not touch `sim/`**, `condition.gd`, `mesh_kit.gd` or `grammar.gd`.
- Run `./test.sh` — not `godot -s addons/gut/...` alone — before any commit that
  claims to pass. The determinism gate lives outside GUT.

---

## File Structure

| File | Responsibility |
|---|---|
| `game/diorama/culture.gd` | **Create.** The culture library and the modulation arithmetic. Knows nothing about trees or parts |
| `game/diorama/compose.gd` | Modify. `sample()` takes ctx; culture in ctx; crown resolution; dome params; `apply_culture` |
| `game/diorama/styles.gd` | Modify. Four crowning masses become `kind: "crown"` |
| `game/diorama/culture_sheet.gd` / `.tscn` | **Create.** Culture × style sheet |
| `test/test_diorama_culture.gd` | **Create.** Modulation and identity properties |
| `test/test_diorama_compose.gd` | Modify. Updated for the `sample()` signature |
| `tools/diorama_compose_fingerprint.gd` | Modify. Fold a second culture in |
| `docs/shots/mbs-culture/` | The committed sheets |

---

### Task 1: The culture library and its modulation arithmetic

**Files:**
- Create: `game/diorama/culture.gd`
- Test: `test/test_diorama_culture.gd` (create)

**Interfaces:**
- Consumes: nothing. This file is standalone and imports no diorama code.
- Produces:
  - `class_name DioramaCulture`
  - `const SCALES := {...}` — purpose → multiplier-key mapping
  - `static func modulate(spec: Variant, culture: Dictionary, purpose: String) -> Variant`
  - `static func lowland() -> Dictionary`, `highland()`, `delta()`
  - `const NAMES := ["lowland", "highland", "delta"]`
  - `static func for_name(name: String) -> Dictionary`

**The arithmetic.** A range `[lo, hi]` becomes `[(mid - half) * scale,
(mid + half) * scale]` where `mid` is the midpoint and `half` is the half-width
times `variance`. A scalar is a degenerate range and just scales. A purpose not
in `SCALES` returns the spec untouched.

- [ ] **Step 1: Write the failing tests**

Create `test/test_diorama_culture.gd`:

```gdscript
extends GutTest
## The culture layer: what a people's way of building modulates, and what it
## must leave alone.


func _plain() -> Dictionary:
	# Every multiplier at 1.0 — the identity culture. Any test that uses this
	# is asserting that modulation with no effect really has no effect.
	return {"name": "plain", "palette": {}, "verticality": 1.0,
			"thickness": 1.0, "setback": 1.0, "variance": 1.0, "crown": "hip"}


func test_the_identity_culture_changes_nothing() -> void:
	var c := _plain()
	assert_eq(DioramaCulture.modulate(0.6, c, "h"), 0.6,
			"a scalar changed under an identity culture")
	var r: Array = DioramaCulture.modulate([0.6, 1.3], c, "h")
	assert_almost_eq(r[0], 0.6, 1e-6, "range lo moved under identity")
	assert_almost_eq(r[1], 1.3, 1e-6, "range hi moved under identity")


func test_scale_moves_a_range_without_changing_its_relative_width() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
	assert_almost_eq(r[0], 1.2, 1e-6, "lo should scale")
	assert_almost_eq(r[1], 2.8, 1e-6, "hi should scale")


func test_variance_widens_around_the_midpoint() -> void:
	# The midpoint must not move — variance is about how uniform a people's
	# buildings are, not about how big they are. Those are separate levers and
	# conflating them would make one unusable.
	var c := _plain()
	c["variance"] = 2.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
	assert_almost_eq((r[0] + r[1]) * 0.5, 1.0, 1e-6, "midpoint moved")
	assert_almost_eq(r[1] - r[0], 1.6, 1e-6, "width should double")


func test_variance_below_one_narrows_but_never_inverts() -> void:
	var c := _plain()
	c["variance"] = 0.0
	var r: Array = DioramaCulture.modulate([0.6, 1.4], c, "h")
	assert_almost_eq(r[0], 1.0, 1e-6, "a zero variance should collapse to mid")
	assert_true(r[0] <= r[1], "modulation inverted a range")


func test_only_the_stated_purposes_are_modulated() -> void:
	# Scaling `oversize` or `taper` would compound with the mass they modify,
	# and scaling `radius` would break an arch's fit against its own piers.
	var c := _plain()
	c["verticality"] = 3.0
	c["thickness"] = 3.0
	c["setback"] = 3.0
	for purpose in ["oversize", "taper", "radius", "from", "to", "advance",
			"gap", "count"]:
		assert_eq(DioramaCulture.modulate([1.0, 2.0], c, purpose), [1.0, 2.0],
				"'%s' should not be modulated by culture" % purpose)


func test_each_purpose_takes_its_own_multiplier() -> void:
	var c := _plain()
	c["verticality"] = 2.0
	c["thickness"] = 3.0
	c["setback"] = 4.0
	assert_eq(DioramaCulture.modulate(1.0, c, "h"), 2.0, "h takes verticality")
	assert_eq(DioramaCulture.modulate(1.0, c, "w"), 3.0, "w takes thickness")
	assert_eq(DioramaCulture.modulate(1.0, c, "d"), 3.0, "d takes thickness")
	assert_eq(DioramaCulture.modulate(1.0, c, "setback"), 4.0,
			"setback takes setback")


func test_null_stays_null() -> void:
	assert_eq(DioramaCulture.modulate(null, _plain(), "h"), null,
			"an absent spec must stay absent so the caller's default applies")


func test_the_three_cultures_differ_in_every_lever() -> void:
	# A culture that matches another on a lever is a wasted culture — the sheet
	# would show two rows differing in fewer ways than it appears to test.
	var cs: Array = []
	for n in DioramaCulture.NAMES:
		cs.append(DioramaCulture.for_name(n))
	for lever in ["verticality", "thickness", "setback", "variance", "crown"]:
		var seen := {}
		for c: Dictionary in cs:
			seen[c[lever]] = true
		assert_eq(seen.size(), cs.size(),
				"two cultures share a '%s' value" % lever)
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=test_diorama_culture -gexit`
Expected: FAIL — `Identifier "DioramaCulture" not declared`.

Note: `-gtest=<path>` does not isolate a script in this repo's GUT 9.3.0 when
`-gdir` is also set. Use `-gselect=<substring>`.

- [ ] **Step 3: Implement**

Create `game/diorama/culture.gd`:

```gdscript
class_name DioramaCulture
extends RefCounted
## A culture is a people's way of building: what proportions they favour, how
## uniform they are, what shape they put on top, and what they build in.
##
## It modulates the SHARED vocabulary rather than forking it. Every culture
## renders the same style trees, because ruins, the assembly tween and the
## whole composer rest on one tree per style — a per-culture fork would
## multiply all of that by the number of civilizations.
##
## A palette alone would not do it. Measured before this was written: the four
## styles draw from an almost identical role set — everything is plaster with
## an ochre roof and a brass tip — so swapping palettes tints all four styles
## identically. `procedural-art` experiment S3 sets the bar: culture must be
## legible in massing and silhouette, not surface marks.


## Which culture lever scales which sampled purpose. Anything absent here is
## deliberately unmodulated:
##
##   `oversize` and `taper` are RELATIVE to the mass they modify, so scaling
##   them would compound with the `w`/`d`/`h` scaling already applied.
##
##   `radius`, `from` and `to` describe an arc's SHAPE. Scaling an arch's
##   radius while its voussoirs thin would break the fit against its piers
##   that slice 2 spent a review round getting right.
##
##   `advance` and `gap` are row rhythm, and `count` is repetition. Both are
##   the deferred repetition lever, not this slice.
const SCALES := {
	"h": "verticality",
	"w": "thickness",
	"d": "thickness",
	"setback": "setback",
}


## Transform a proportion spec into the one this culture would build to.
##
## The RANGE moves, not the drawn value. How uniform a civilization's
## architecture is, is itself a cultural trait — a rigid imperial people build
## to a template, a vernacular one does not — so `variance` is a lever of its
## own, and it costs nothing to have it here rather than to retrofit it later.
##
## Returns the spec untouched for an unmodulated purpose, and null for null, so
## the caller's default still applies.
static func modulate(spec: Variant, culture: Dictionary,
		purpose: String) -> Variant:
	if spec == null or not SCALES.has(purpose):
		return spec
	var scale: float = culture.get(SCALES[purpose], 1.0)
	if spec is float or spec is int:
		return float(spec) * scale
	if not (spec is Array and spec.size() == 2):
		return spec
	var lo := float(spec[0])
	var hi := float(spec[1])
	var mid := (lo + hi) * 0.5
	# Half-width scales toward zero and never past it, so a variance under 1
	# narrows without inverting the range.
	var half := (hi - lo) * 0.5 * float(culture.get("variance", 1.0))
	return [(mid - half) * scale, (mid + half) * scale]


## Names in sheet order.
const NAMES := ["lowland", "highland", "delta"]


static func for_name(name: String) -> Dictionary:
	match name:
		"highland": return highland()
		"delta": return delta()
		_: return lowland()


## The baseline: the proportions the styles were authored against, so one row
## of the sheet shows the vocabulary unmodulated.
static func lowland() -> Dictionary:
	return {
		"name": "lowland",
		"palette": {
			"plaster": Color(0.902, 0.875, 0.800),
			"plaster_dim": Color(0.812, 0.776, 0.682),
			"ochre": Color(0.659, 0.475, 0.290),
			"brass": Color(0.788, 0.643, 0.290),
			"wood": Color(0.478, 0.361, 0.220),
		},
		"verticality": 1.0,
		"thickness": 1.0,
		"setback": 1.0,
		"variance": 1.0,
		"crown": "hip",
	}


## Tall, thin-walled, sharply stepped, and irregular — a people building on
## slopes with little flat ground.
static func highland() -> Dictionary:
	return {
		"name": "highland",
		"palette": {
			"plaster": Color(0.784, 0.780, 0.757),
			"plaster_dim": Color(0.663, 0.659, 0.639),
			"ochre": Color(0.427, 0.365, 0.310),
			"brass": Color(0.706, 0.612, 0.353),
			"wood": Color(0.376, 0.325, 0.267),
		},
		"verticality": 1.45,
		"thickness": 0.78,
		"setback": 1.35,
		"variance": 1.30,
		"crown": "spire",
	}


## Low, heavy-walled, barely tapered and highly uniform — a people building to
## a template on flat ground.
static func delta() -> Dictionary:
	return {
		"name": "delta",
		"palette": {
			"plaster": Color(0.918, 0.855, 0.706),
			"plaster_dim": Color(0.831, 0.757, 0.604),
			"ochre": Color(0.741, 0.514, 0.259),
			"brass": Color(0.831, 0.702, 0.318),
			"wood": Color(0.518, 0.400, 0.239),
		},
		"verticality": 0.70,
		"thickness": 1.30,
		"setback": 0.45,
		"variance": 0.55,
		"crown": "dome",
	}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: exit 0, all tests passing.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/culture.gd test/test_diorama_culture.gd
git commit -m "culture: three peoples, and the range arithmetic that separates them"
```

---

### Task 2: `sample()` takes a ctx — a pure refactor

**Files:**
- Modify: `game/diorama/compose.gd` — `sample`, `_params_for`, and 12 call sites
- Modify: `test/test_diorama_compose.gd` — any direct `sample()` calls

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `static func sample(spec: Variant, ctx: Dictionary, path: String, purpose: String, dflt: float) -> float`
  - `_params_for(kind, n, w, d, h, ctx, path)` — ctx replaces `seed, id`

**This task changes NO behaviour.** It is the signature change that lets Task 3
pass a culture without a seventh positional argument at twelve call sites. The
whole existing suite must pass unchanged; if any test's *expected value* changes,
something is wrong — stop and report rather than updating the expectation.

`path` stays a separate parameter because `_ring` samples its children at
`child_path`, not at `ctx["path"]`.

- [ ] **Step 1: Change the signature and every call site**

In `game/diorama/compose.gd`:

```gdscript
static func sample(spec: Variant, ctx: Dictionary, path: String,
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
	return lo + (hi - lo) * channel(ctx["seed"], ctx["id"], path, purpose)
```

Then update all twelve call sites, dropping `seed, id`:

- `_mass` (4): `oversize`, `w`, `d`, `h` — `sample(n.get("w"), ctx, path, "w", inherited.x)`
- `_params_for` (1): `taper` — this function must now take `ctx` and `path`
  instead of `seed, id, path`; update its signature and its two callers
  (`_mass` and `_ring`)
- `_stack` (1): `setback` — becomes `sample(n.get("setback"), ctx, path, "setback", 0.0)`,
  which also retires the `seed_of(ctx), id_of(ctx)` pair at that call
- `_row` (2): `advance`, `gap`
- `_ring` (3 + 2): `radius`, `from`, `to` at `path`; then `w` and `d` at
  `child_path` — `sample(body.get("w"), ctx, child_path, "w", 0.2)`

`_sample_count` keeps its `(spec, seed, id, path)` signature; it is not part of
the modulated path and Task 3 does not touch it.

- [ ] **Step 2: Run the full suite — expect it to pass unchanged**

Run: `./test.sh`
Expected: exit 0, **190 tests**, all passing, determinism gate green.

If any test fails on a *value* rather than a signature, the refactor changed
behaviour. Find out why before proceeding — do not adjust the expectation.

- [ ] **Step 3: Verify no call site was missed**

Run: `grep -n "sample(" game/diorama/compose.gd | grep "seed\|id_of\|seed_of"`
Expected: no output. Any hit is a call site still passing the old arguments.

- [ ] **Step 4: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: sample() takes the ctx it already needed"
```

---

### Task 3: Culture in the ctx, and the identity that must survive it

**Files:**
- Modify: `game/diorama/compose.gd` — `new_ctx`, `sample`, `build`
- Test: `test/test_diorama_culture.gd`

**Interfaces:**
- Consumes: `DioramaCulture.modulate(spec, culture, purpose)` from Task 1; the
  ctx-taking `sample()` from Task 2.
- Produces:
  - `new_ctx(seed, building_id, culture := {})` — ctx gains `"culture"`
  - `build(tree, seed, building_id, culture := {})`
  - An empty culture dictionary means no modulation, so every existing caller
    keeps working unchanged.

**The property this task exists to protect.** The channel draw is untouched;
only the range it maps into changes. The same id under two cultures draws the
same `u` and lands at the same *relative* position in each range — so the two
are recognizably the same building, differently proportioned. If culture ever
reached `channel()`, culture would read as reseeding and every style would look
like an unrelated building.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_culture.gd`:

```gdscript
const SEED := 4242


func _box(name: String, w: Variant, d: Variant, h: Variant) -> Dictionary:
	return {"mass": {"name": name, "kind": "box", "w": w, "d": d, "h": h,
			"role": "plaster"}}


func test_culture_never_reaches_the_channel() -> void:
	# THE load-bearing property. If culture entered the channel, the same
	# building under two cultures would draw unrelated values and every style
	# would look like a different building — which is the failure this whole
	# design exists to avoid.
	for id in range(8):
		var base := DioramaCompose.channel(SEED, id, "block/unit/body", "h")
		for n in DioramaCulture.NAMES:
			var ctx := DioramaCompose.new_ctx(SEED, id,
					DioramaCulture.for_name(n))
			assert_eq(DioramaCompose.channel(ctx["seed"], ctx["id"],
					"block/unit/body", "h"), base,
					"culture '%s' changed the channel draw at id %d" % [n, id])


func test_a_building_keeps_its_relative_position_across_cultures() -> void:
	# Two cultures' version of one building must be the SAME building
	# differently proportioned — varied, not randomized.
	var tree := _box("solo", 2.0, 2.0, [1.0, 3.0])
	for id in range(8):
		var frac := -1.0
		for n in DioramaCulture.NAMES:
			var c := DioramaCulture.for_name(n)
			var parts := DioramaCompose.build(tree, SEED, id, c)
			var r: Array = DioramaCulture.modulate([1.0, 3.0], c, "h")
			var h: float = parts[0]["params"]["size"].y
			var here := (h - r[0]) / maxf(r[1] - r[0], 1e-9)
			if frac >= 0.0:
				assert_almost_eq(here, frac, 1e-5,
						"id %d landed at a different relative position under '%s'"
						% [id, n])
			frac = here


func test_an_empty_culture_leaves_geometry_untouched() -> void:
	# Every pre-culture caller passes no culture; they must be unaffected.
	var tree := _box("solo", [1.0, 2.0], 2.0, [1.0, 3.0])
	var before := DioramaCompose.build(tree, SEED, 3)
	var after := DioramaCompose.build(tree, SEED, 3, {})
	assert_eq(before[0]["params"]["size"], after[0]["params"]["size"],
			"an empty culture changed the geometry")


func test_cultures_actually_produce_different_buildings() -> void:
	# Asserted by FINDING a difference rather than comparing one dimension
	# that might coincide — the same shape of test that caught a cohesive row
	# masquerading as an articulated one in slice 3.
	var tree := _box("solo", [1.0, 2.0], [1.0, 2.0], [1.0, 3.0])
	var pairs := 0
	for i in range(DioramaCulture.NAMES.size()):
		for j in range(i + 1, DioramaCulture.NAMES.size()):
			var a := DioramaCompose.build(tree, SEED, 5,
					DioramaCulture.for_name(DioramaCulture.NAMES[i]))
			var b := DioramaCompose.build(tree, SEED, 5,
					DioramaCulture.for_name(DioramaCulture.NAMES[j]))
			assert_ne(a[0]["params"]["size"], b[0]["params"]["size"],
					"'%s' and '%s' built the same thing"
					% [DioramaCulture.NAMES[i], DioramaCulture.NAMES[j]])
			pairs += 1
	assert_eq(pairs, 3, "expected three culture pairs to compare")


func test_a_reversed_range_is_caught_after_modulation_not_before() -> void:
	# The assert exists to catch authoring typos. It must see the range the
	# sampler actually uses, or a bad multiplier walks straight past the guard.
	var c := _plain()
	var r: Array = DioramaCulture.modulate([1.0, 2.0], c, "h")
	assert_true(r[0] <= r[1], "identity modulation produced a reversed range")
	c["variance"] = 0.0
	var flat: Array = DioramaCulture.modulate([1.0, 2.0], c, "h")
	assert_true(flat[0] <= flat[1], "zero variance produced a reversed range")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=test_diorama_culture -gexit`
Expected: FAIL — `new_ctx()` and `build()` do not take a culture argument.

- [ ] **Step 3: Implement**

In `game/diorama/compose.gd`:

```gdscript
static func new_ctx(seed: int, building_id: int,
		culture: Dictionary = {}) -> Dictionary:
	return {"seed": seed, "id": building_id, "path": "", "culture": culture,
			"need_lo": ENDURE_LO, "need_hi": ENDURE_HI,
			"frame": zero_frame(Transform3D.IDENTITY)}
```

Add `"culture": ctx["culture"]` to every hand-built `child_ctx` literal — there
are two, in `_stack` and `_row`. Miss one and that subtree silently loses its
culture, which no existing test would catch.

In `sample()`, modulate before anything else:

```gdscript
static func sample(spec: Variant, ctx: Dictionary, path: String,
		purpose: String, dflt: float) -> float:
	# The culture moves the RANGE. The channel draw below is untouched, so the
	# same building id under two cultures lands at the same relative position
	# in each — the same building, differently proportioned, rather than two
	# unrelated buildings.
	var m: Variant = DioramaCulture.modulate(spec, ctx["culture"], purpose)
	if m == null:
		return dflt
	if m is float or m is int:
		return float(m)
	assert(m is Array, "'%s' on '%s' must be a number or [lo, hi]"
			% [purpose, path])
	assert(m.size() == 2, "'%s' on '%s' must have exactly two bounds"
			% [purpose, path])
	var lo := float(m[0])
	var hi := float(m[1])
	# Asserted on the MODULATED range, not the authored one: this guard exists
	# to catch reversed-range typos, and a bad multiplier is exactly as worth
	# catching as a typo.
	assert(lo <= hi, "'%s' on '%s' has lo > hi after culture '%s'"
			% [purpose, path, ctx["culture"].get("name", "none")])
	return lo + (hi - lo) * channel(ctx["seed"], ctx["id"], path, purpose)
```

And `build`:

```gdscript
static func build(tree: Dictionary, seed: int, building_id: int,
		culture: Dictionary = {}) -> Array:
	var out := resolve(tree, new_ctx(seed, building_id, culture))
	var parts: Array = out["parts"]
	_finish(parts)
	return parts
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: exit 0, all tests passing, determinism gate green.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_culture.gd
git commit -m "compose: a culture moves the range, never the draw"
```

---

### Task 4: The `dome` arm `_params_for` never had

**Files:**
- Modify: `game/diorama/compose.gd` — `_params_for`, and `_mass`'s round-kind rule
- Test: `test/test_diorama_compose.gd`

**Interfaces:**
- Consumes: the ctx-taking `_params_for` from Task 2.
- Produces: `kind: "dome"` becomes a usable mass kind, emitting
  `{"radius": w * 0.5, "squash": <sampled>}`.

**This closes a pre-existing hole, not one this slice opened.** `emit()` already
handles `"dome"` (`grammar.gd:34`) and `DioramaMeshKit.add_dome(xf, radius,
squash, col)` already exists — but `_params_for` has no dome arm, so a style
writing `kind: "dome"` today hits its `unknown mass kind` assert. Task 5 needs
dome as a crown target, so it gets fixed here where it can be tested on its own.

**A dome is round**, so it must join `prism` and `cone` in `_mass`'s rule that
forces `d = w`. Reporting `(w, d)` for a shape built from one radius would
describe geometry that does not exist, and everything stacking on that frame
inherits the lie — the same reasoning already in that comment.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_compose.gd`:

```gdscript
func test_a_dome_emits_the_params_the_renderer_reads() -> void:
	# Checked against DioramaMeshKit.add_dome's actual signature
	# (xf, radius, squash, col) rather than against what seems reasonable —
	# grammar.gd reads params.radius and params.squash by name.
	var tree := {"mass": {"name": "cap", "kind": "dome", "w": 3.0, "h": 1.0,
			"role": "plaster"}}
	var parts := DioramaCompose.build(tree, SEED, 1)
	assert_eq(parts.size(), 1, "a dome should emit one part")
	assert_eq(parts[0]["kind"], "dome", "kind should survive to the part")
	assert_true(parts[0]["params"].has("radius"), "dome needs a radius")
	assert_true(parts[0]["params"].has("squash"), "dome needs a squash")
	assert_almost_eq(parts[0]["params"]["radius"], 1.5, 1e-6,
			"radius should be half the width")


func test_a_dome_reports_a_square_footprint() -> void:
	# A dome is built from ONE radius, so a frame reporting (w, d) would
	# describe geometry that does not exist and everything stacked on it would
	# inherit that lie — the same reason prism and cone already do this.
	var tree := {"stack": {"name": "s", "children": [
		{"mass": {"name": "cap", "kind": "dome", "w": 4.0, "d": 9.0, "h": 1.0,
				"role": "plaster"}}]}}
	var out := DioramaCompose.resolve(tree, DioramaCompose.new_ctx(SEED, 1))
	assert_almost_eq(out["frame"]["footprint"].x,
			out["frame"]["footprint"].y, 1e-6,
			"a dome reported a non-square footprint")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=test_diorama_compose -gexit`
Expected: FAIL — `unknown mass kind 'dome'`.

- [ ] **Step 3: Implement**

In `_mass`, add `dome` to the round-kind rule:

```gdscript
	# A cone, prism or dome is emitted as a circle of radius w/2 — `d` never
	# reaches the renderer. Reporting (w, d) would describe geometry that does
	# not exist, and everything stacking on this frame inherits the lie.
	if kind == "prism" or kind == "cone" or kind == "dome":
		d = w
```

In `_params_for`, add the arm:

```gdscript
		"dome":
			# squash is a PROPORTION of the radius, so it is unmodulated by
			# culture for the same reason `taper` is — scaling it would
			# compound with the thickness already applied to `w`.
			return {"radius": w * 0.5,
					"squash": sample(n.get("squash"), ctx, path, "squash", 0.85)}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: exit 0, all tests passing.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd test/test_diorama_compose.gd
git commit -m "compose: dome was renderable but not buildable"
```

---

### Task 5: Crown resolution, and the styles that use it

**Files:**
- Modify: `game/diorama/compose.gd` — `_mass`'s kind resolution
- Modify: `game/diorama/styles.gd:31,71,92,111` — four crowning masses
- Test: `test/test_diorama_culture.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - `DioramaCulture.CROWNS := {"spire": "cone", "dome": "dome", "hip": "tapered", "parapet": "box"}`
  - `static func crown_kind(culture: Dictionary) -> String`
  - `kind: "crown"` in a style resolves through the culture

**Ordering matters.** `_mass` reads `kind`, then forces `d = w` for round kinds,
then calls `_params_for`. Crown resolution must happen **at the point `kind` is
read**, before the round-kind rule — otherwise a crown resolving to `cone` or
`dome` would skip that rule and report a rectangular footprint for a round shape.

The four crowning masses, with what they are today:

| file:line | node | today |
|---|---|---|
| `styles.gd:31` | residential `roof` | `"kind": "tapered", "taper": 0.8` |
| `styles.gd:71` | hero_arch `finial` | `"kind": "cone"` |
| `styles.gd:92` | civic `roof` | `"kind": "tapered", "taper": 0.5` |
| `styles.gd:111` | stepped `spire` | `"kind": "cone"` |

Each becomes `"kind": "crown"`. Keep the `taper` values where they are — they
apply when a culture's crown resolves to `tapered` and are ignored otherwise.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_diorama_culture.gd`:

```gdscript
func test_each_crown_name_resolves_to_its_primitive() -> void:
	var expected := {"spire": "cone", "dome": "dome", "hip": "tapered",
			"parapet": "box"}
	for crown: String in expected:
		var c := _plain()
		c["crown"] = crown
		var tree := {"mass": {"name": "cap", "kind": "crown", "w": 2.0,
				"h": 1.0, "role": "plaster"}}
		var parts := DioramaCompose.build(tree, SEED, 1, c)
		assert_eq(parts[0]["kind"], expected[crown],
				"crown '%s' resolved wrong" % crown)


func test_a_crown_resolving_round_still_reports_a_square_footprint() -> void:
	# The ordering trap: crown resolution has to happen BEFORE _mass forces
	# d = w for round kinds, or a spire reports a rectangular footprint and
	# whatever stacks on it inherits that.
	for crown in ["spire", "dome"]:
		var c := _plain()
		c["crown"] = crown
		var tree := {"stack": {"name": "s", "children": [
			{"mass": {"name": "cap", "kind": "crown", "w": 4.0, "d": 9.0,
					"h": 1.0, "role": "plaster"}}]}}
		var out := DioramaCompose.resolve(tree,
				DioramaCompose.new_ctx(SEED, 1, c))
		assert_almost_eq(out["frame"]["footprint"].x,
				out["frame"]["footprint"].y, 1e-6,
				"crown '%s' reported a non-square footprint" % crown)


func test_every_style_crowns_through_the_culture() -> void:
	# All four styles must actually use `crown`, or a culture's roofline lever
	# silently does nothing for the ones that do not — the sheet would show
	# three cultures differing in fewer ways than it claims to.
	for style_name in DioramaStyles.NAMES:
		var kinds := {}
		for crown in ["spire", "dome", "hip", "parapet"]:
			var c := _plain()
			c["crown"] = crown
			for p: Dictionary in DioramaCompose.build(
					DioramaStyles.for_name(style_name), SEED, 0, c):
				kinds[p["kind"]] = true
		assert_true(kinds.has("dome") or kinds.has("cone"),
				"'%s' never produced a crown primitive" % style_name)


func test_an_unknown_crown_is_refused_not_silently_boxed() -> void:
	# Defaulting to "box" would turn a typo in a culture into a flat roof
	# nobody asked for, which reads as a design choice rather than a mistake.
	var c := _plain()
	c["crown"] = "zigurat"
	assert_eq(DioramaCulture.CROWNS.has("zigurat"), false,
			"fixture used a real crown name")
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=test_diorama_culture -gexit`
Expected: FAIL — `unknown mass kind 'crown'`.

- [ ] **Step 3: Implement**

In `game/diorama/culture.gd`:

```gdscript
## What a culture's `crown` name means in geometry. Roofline is what the eye
## resolves first at settlement distance, which is why this one substitution
## carries most of the silhouette half of experiment S3's bar.
const CROWNS := {
	"spire": "cone",
	"dome": "dome",
	"hip": "tapered",
	"parapet": "box",
}


static func crown_kind(culture: Dictionary) -> String:
	var name: String = culture.get("crown", "hip")
	assert(CROWNS.has(name), "unknown crown '%s'" % name)
	return CROWNS.get(name, "tapered")
```

In `_mass`, resolve at the point `kind` is read:

```gdscript
	var kind: String = n.get("kind", "box")
	# A style says "crown" and the CULTURE says what that is. Resolved here,
	# before the round-kind rule below, so a crown that becomes a cone or dome
	# still reports the square footprint a round shape actually occupies.
	if kind == "crown":
		kind = DioramaCulture.crown_kind(ctx["culture"])
```

Note the default: `crown_kind({})` returns `"tapered"` for an empty culture,
so pre-culture callers building a `crown` style get a hipped roof — the shape
three of the four styles had before this task.

In `game/diorama/styles.gd`, change the four crowning masses to
`"kind": "crown"`, leaving their `taper` values in place.

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh`
Expected: exit 0, all tests passing, determinism gate green.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/compose.gd game/diorama/culture.gd game/diorama/styles.gd test/test_diorama_culture.gd
git commit -m "styles: a crown is a shape the culture chooses"
```

---

### Task 6: `apply_culture`, and a second culture under the determinism gate

**Files:**
- Modify: `game/diorama/compose.gd` — `apply_roles` → `apply_culture`
- Modify: `game/diorama/lineup.gd`, `game/diorama/condition_sheet.gd`, `game/diorama/spike.gd` — callers
- Modify: `tools/diorama_compose_fingerprint.gd`
- Test: `test/test_diorama_culture.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `static func apply_culture(parts: Array, culture: Dictionary) -> void`

**Why the fingerprint changes.** Culture modulates geometry, so a culture that
resolved differently across two processes WOULD move vertices and the existing
mesh digest would catch it. But the gate currently builds only one culture, so
the modulation path is never exercised by it. Folding a second culture in makes
the gate cover the code this slice adds.

- [ ] **Step 1: Write the failing test**

Append to `test/test_diorama_culture.gd`:

```gdscript
func test_apply_culture_colours_every_part_from_the_palette() -> void:
	var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, 1,
			DioramaCulture.highland())
	DioramaCompose.apply_culture(parts, DioramaCulture.highland())
	var pal: Dictionary = DioramaCulture.highland()["palette"]
	for p: Dictionary in parts:
		assert_eq(p["color"], pal[p["role"]],
				"role '%s' did not take its culture's colour" % p["role"])


func test_two_cultures_colour_the_same_building_differently() -> void:
	var found := false
	for n in DioramaCulture.NAMES:
		var c := DioramaCulture.for_name(n)
		var parts := DioramaCompose.build(DioramaStyles.residential(), SEED, 1, c)
		DioramaCompose.apply_culture(parts, c)
		if parts[0]["color"] != DioramaCulture.lowland()["palette"][parts[0]["role"]]:
			found = true
	assert_true(found, "no culture produced a colour differing from lowland's")


func test_ruins_still_work_under_a_culture() -> void:
	# Slice 3's guarantee must survive slice 4: need bands come from node
	# structure and are untouched by culture, so ordered loss should hold.
	for n in DioramaCulture.NAMES:
		var c := DioramaCulture.for_name(n)
		var parts := DioramaCompose.build(DioramaStyles.stepped(), SEED, 2, c)
		var rungs := [1.0, 0.75, 0.5, 0.25, 0.05]
		for i in range(rungs.size() - 1):
			var higher := DioramaCondition.filter(parts, rungs[i])
			var lower := DioramaCondition.filter(parts, rungs[i + 1])
			for p: Dictionary in lower:
				assert_true(higher.has(p),
						"culture '%s': a part survived %f but not %f"
						% [n, rungs[i + 1], rungs[i]])
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gselect=test_diorama_culture -gexit`
Expected: FAIL — `apply_culture` not declared.

- [ ] **Step 3: Implement**

In `game/diorama/compose.gd`, replace `apply_roles`:

```gdscript
## Resolve each part's role into a concrete colour through a culture's palette.
## Kept separate from build() so one tree can be rendered in several palettes —
## which is what makes culture a mapping rather than a fork of the geometry.
static func apply_culture(parts: Array, culture: Dictionary) -> void:
	var palette: Dictionary = culture.get("palette", {})
	for p: Dictionary in parts:
		var role: String = p.get("role", "")
		assert(palette.has(role),
				"culture '%s' has no colour for role '%s'"
				% [culture.get("name", "none"), role])
		p["color"] = palette[role]
```

Update **seven call sites across five files** — counted, not estimated:

| file | calls |
|---|---|
| `game/diorama/lineup.gd` | 1 |
| `game/diorama/condition_sheet.gd` | 1 (on `survivors`, not `parts`) |
| `game/diorama/spike.gd` | **2** — one on `parts`, one on `hero` |
| `tools/diorama_compose_fingerprint.gd` | 1 (rewritten below anyway) |
| `test/test_diorama_styles.gd` | **2** |

Each becomes `DioramaCompose.apply_culture(<same first arg>,
DioramaCulture.lowland())`. `lowland`'s palette is `DioramaStyles.ROLES`
verbatim, so every one of these surfaces is unchanged visually — if any frame
or test value moves, something is wrong.

Then confirm none was missed: `grep -rn "apply_roles" game tools test` should
return nothing at all once the definition itself is renamed.

Leave `DioramaStyles.ROLES` in place — `lowland()` is authored from it and
removing it is a separate cleanup.

In `tools/diorama_compose_fingerprint.gd`, build two cultures:

```gdscript
	for style in [DioramaStyles.residential(), DioramaStyles.hero_arch()]:
		for culture in [DioramaCulture.lowland(), DioramaCulture.delta()]:
			for id in IDS:
				var parts := DioramaCompose.build(style, world_seed, id, culture)
				DioramaCompose.apply_culture(parts, culture)
				DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
				for p: Dictionary in parts:
					needs = (needs * 31 + int(round(p["need"] * 1000000.0))) \
							& 0xFFFFFFFFFFFFF
```

- [ ] **Step 4: Run to verify**

Run: `./test.sh`
Expected: exit 0. The determinism section must print
`tools/diorama_compose_fingerprint.gd: 3 seeds reproduced identically across
processes`. The printed integers will differ from before — expected, since the
generator now covers more.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/ tools/diorama_compose_fingerprint.gd test/test_diorama_culture.gd
git commit -m "culture: a palette is a property of a people, and the gate covers two"
```

---

### Task 7: The culture × style sheet, and its colour-held-constant control

**Files:**
- Create: `game/diorama/culture_sheet.gd`, `game/diorama/culture_sheet.tscn`

**Interfaces:**
- Consumes: `DioramaCulture.NAMES`, `for_name`, `DioramaStyles.NAMES`,
  `for_name`, `DioramaCompose.build/apply_culture`, `DioramaGrammar.emit`.
- Produces: a scene photographable by `./capture.sh --scene`.

**Two sheets from one scene.** An exported `uniform_palette` flag renders every
culture through `lowland`'s palette while keeping its geometry. That is the
control: **if the cultures are still tellable apart with colour held constant,
the geometry is doing the work.** Without it the sheet cannot distinguish "we
expressed culture" from "we built a tint with extra steps," which is the exact
failure the ticket predicts.

**Build it as a sibling of `condition_sheet.gd`**, which is the closest working
model — read it first. Reuse its solutions rather than rediscovering them:

- Each row is scaled by its own complete building's height so styles read at
  comparable size. Here the grid is culture × style, so scale per **cell**, from
  that cell's own building.
- `Camera3D.fov` is the VERTICAL angle under the default `KEEP_HEIGHT`. Set
  `keep_aspect = Camera3D.KEEP_WIDTH` and solve both axes, or the sheet lands in
  the middle third of the frame.
- A `Label3D` billboard is centred on its position, so a caption at y≈0 sinks
  into the stage pad. Float them clear.
- `add_box` builds UPWARD from its origin, so a pad whose top is the ground
  plane has its origin at `-height`.
- Row labels need their own gutter — a long style name runs under the first cell.
- `mat.vertex_color_is_srgb = false`; vertex colours are linear, `albedo_color`
  and `Environment` colours are sRGB.

- [ ] **Step 1: Write the scene script**

Create `game/diorama/culture_sheet.gd`, modelled on `condition_sheet.gd`:

```gdscript
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
		# origin plus its own height. Height lives under `size.y` for boxes and
		# `height` for the round kinds, the same split _params_for writes.
		var prm: Dictionary = p["params"]
		var h: float = prm["size"].y if prm.has("size") else prm.get("height", 0.0)
		top = maxf(top, p["xf"].origin.y + h)
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
```

- [ ] **Step 2: Write the scene file**

Create `game/diorama/culture_sheet.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://game/diorama/culture_sheet.gd" id="1"]

[node name="CultureSheet" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 3: Verify it builds headless**

Run: `godot --headless --quit-after 60 game/diorama/culture_sheet.tscn`
Expected: exit 0, no errors printed.

Then: `./test.sh` — expected exit 0.

- [ ] **Step 4: Look at it, and iterate on the framing**

```bash
./capture.sh --scene res://game/diorama/culture_sheet.tscn --name mbs-culture-wip --label wip
```

**Read the resulting PNG with your Read tool.** Do not skip this and do not
describe a frame you have not opened. Check:

1. Three culture rows and four style columns, all present.
2. Captions legible and clear of the stage pad, not clipped by the frame edge
   or occluded by the first cell.
3. Does each culture's crown actually differ — spire vs dome vs hipped?
4. Do the three cultures read as different peoples, or as one people three
   times? **Say which, plainly.**

Adjust `cell_size`, `fov_horizontal_deg`, `camera_pitch_deg`, `frame_margin`
and re-capture until it reads. `capture.sh` **wipes its output directory per
run**, so keep the same `--name` while iterating.

Delete `docs/shots/mbs-culture-wip/` before committing — Task 8 captures the
real frames under a different name.

- [ ] **Step 5: Commit**

```bash
git add game/diorama/culture_sheet.gd game/diorama/culture_sheet.tscn
git commit -m "sheet: three peoples across one vocabulary"
```

---

### Task 8: Capture both sheets, commit and link

**Files:**
- Create: `docs/shots/mbs-culture/`

**Interfaces:**
- Consumes: `culture_sheet.tscn` from Task 7.
- Produces: the committed evidence AgDR-008 requires and AgDR-011 links.

- [ ] **Step 1: Capture the coloured sheet**

```bash
./capture.sh --scene res://game/diorama/culture_sheet.tscn --name mbs-culture --label cultures
```

- [ ] **Step 2: Capture the control**

Set `uniform_palette = true` in `game/diorama/culture_sheet.tscn` by adding
`uniform_palette = true` under the node's `script = ExtResource("1")` line, then:

```bash
./capture.sh --scene res://game/diorama/culture_sheet.tscn --name mbs-culture-control --label geometry-only
```

Then set it back to `false` so the scene's default is the coloured sheet.

- [ ] **Step 3: Read both frames**

Open both PNGs with your Read tool and answer, in the report:

- Do the three cultures read as different peoples in the coloured sheet?
- **In the control, with colour held constant, can you still tell them apart?**
  This is the question the whole slice turns on. If the answer is no, the
  honest result is that proportion and crown are insufficient and the `choice`
  node is needed sooner than scoped — report that rather than softening it.
- Does each style stay recognizably itself across the three cultures?

- [ ] **Step 4: Commit both frames**

```bash
git add docs/shots/mbs-culture/ docs/shots/mbs-culture-control/ game/diorama/culture_sheet.tscn
git commit -m "docs: three cultures, and the same three with colour held constant"
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin claude/mbs-slice4-culture
```

The PR body must:

- Link both sheets by **absolute, sha-pinned** `raw.githubusercontent.com` URL
  per AgDR-011. The suite's `shot-links` check prints the correct owner/repo
  and sha.
- State that **AC11 and AC12 are unverified by the agent** — whether the
  cultures read as different peoples, and whether each style stays recognizably
  itself, are the owner's calls.
- **Report the control's answer explicitly.** Whether geometry alone
  distinguishes the cultures is the slice's real result, and a PR that buries it
  has hidden the finding it was written to produce.
- Note that `sample()` changed signature and `apply_roles` became
  `apply_culture`.

Before pushing: run `gh pr list --state open` and check nothing else is
touching `game/diorama/`. A peer session holds
`.claude/worktrees/vitality-wear`. After any merge of another branch into main,
re-run `./test.sh` **against the merge result**, not just this branch — #43 was
merged across #40, and that pairing is how the #17 collision was missed.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:

| Spec section | Task |
|---|---|
| Culture is data, three of them | 1 |
| Modulation transforms the range | 1 |
| Purpose → multiplier mapping | 1 (`SCALES`) |
| Channel untouched by culture | 3 (asserted) |
| Relative position preserved | 3 (asserted) |
| `sample()` takes ctx | 2 |
| `dome` arm in `_params_for` | 4 |
| Crown substitution | 5 |
| Styles use `crown` | 5 |
| `apply_culture` | 6 |
| Second culture in the fingerprint | 6 |
| Ruins survive culture | 6 (asserted) |
| Culture × style sheet | 7 |
| Colour-held-constant control | 7, 8 |
| AC11/AC12 stated unverified | 8 |

**Gaps found and closed during review:**

- The spec did not say crown resolution must precede `_mass`'s round-kind rule.
  Without that ordering a spire reports a rectangular footprint and everything
  stacked on it inherits the error. Called out in Task 5 with a test.
- The spec did not say where a dome's `squash` comes from. Task 4 samples it
  with a 0.85 default and leaves it unmodulated, for the same reason `taper` is.
- I first wrote Task 6 against "three callers" of `apply_roles`. A grep found
  **seven call sites across five files** — `spike.gd` has two and
  `test_diorama_styles.gd` has two, both of which I had missed. The task now
  carries the counted table. Estimating a call-site count instead of running
  the grep is exactly how a refactor task ships half-done.
- `crown_kind({})` needed a defined behaviour for pre-culture callers. Task 5
  returns `tapered`, which is what three of four styles had before.

**Type consistency checked:** `DioramaCulture.modulate`, `crown_kind`,
`for_name`, `NAMES`, `SCALES`, `CROWNS`; `DioramaCompose.sample(spec, ctx, path,
purpose, dflt)`, `new_ctx(seed, id, culture)`, `build(tree, seed, id, culture)`,
`apply_culture(parts, culture)`. Consistent across Tasks 1–8.

---

## Done bar

1. `./test.sh` exits 0.
2. All ten self-certifiable acceptance criteria met.
3. Both sheets committed and linked by sha-pinned URL.
4. The PR states AC11/AC12 unverified, and reports whether the control frame
   still distinguishes the cultures.
