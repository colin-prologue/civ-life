class_name DioramaPalette
extends RefCounted
## The semantic palette, kept literally in step with the Blender lab.
##
## HEX is a transcription of `core.PALETTE` in tools/blender/civlife_blender —
## same names, same values — so "parity with the lab sheets" is checkable by
## diffing two tables rather than by eye. test_diorama_palette.gd pins that.
##
## Colours are returned LINEAR, matching the lab's `_lin()`. This matters more
## than it looks: Godot's StandardMaterial3D treats vertex colours as linear
## unless `vertex_color_is_srgb` is set, so feeding it sRGB-looking floats —
## which is what the spike scaffold did — silently over-brightens every midtone
## and flattens the value separation the reduction test depends on. The lab
## converts once, up front; so do we.
##
## Roles, per the intent: ground / living nature / water / civilisation /
## aspiration (brass, kept scarce) / time (verdigris) / memory.

const HEX := {
	"indigo": "#12151e",      # the void the model sits in
	"plaster": "#e6dfcc",     # civilisation, maintained
	"plaster2": "#cfc6ae",    # civilisation, weathered; also road surface
	"moss": "#5f7247",        # living nature
	"moss2": "#4a5c39",       # living nature, in shade or older
	"verdigris": "#4f8f7a",   # time, inheritance, adaptation
	"brass": "#c9a44a",       # aspiration — scarce on purpose
	"ochre": "#a8794a",       # roof / worked earth
	"wood": "#7a5c38",        # trunks, timber
	"water": "#2e6d78",
	"stone": "#8d8877",       # rock, mountain
	"hilltint": "#77714a",    # dry upland
}

static var _cache := {}


## Colour space, measured on Godot 4.7 by feeding a known hex through each path
## and reading the rendered pixel back — not inferred from docs:
##
##   StandardMaterial3D.albedo_color   sRGB    (#2e6d78 in -> #2e6d78 out)
##   Environment.background_color      sRGB    (#12151e in -> #12151e out)
##   Environment.ambient_light_color   sRGB
##   vertex colours, when the material  linear
##     sets vertex_color_is_srgb=false
##
## In short: everything Godot exposes as a Color property is sRGB; the one
## exception is the vertex buffer, which is raw. So srgb() nearly everywhere,
## col() only for what a DioramaMeshKit builder writes into a mesh.
##
## Getting this backwards is quiet rather than obvious. A linear value handed
## to albedo_color darkens ~6x — that is how the spike's water rendered black
## while the vertex-coloured terrain right beside it looked correct — and a
## linear ambient_light_color is ~10x too dim, which reads as "the ambient
## knob does nothing" rather than as a colour bug.


## Linear-space colour for a palette name. Fails loudly rather than returning
## magenta: a typo'd role should not become an art decision.
static func col(name: String) -> Color:
	if _cache.has(name):
		return _cache[name]
	assert(HEX.has(name), "unknown palette role '%s'" % name)
	var c := Color(HEX[name]).srgb_to_linear()
	_cache[name] = c
	return c


## sRGB-space colour, for StandardMaterial3D.albedo_color only. See the note
## above before using this anywhere else.
static func srgb(name: String) -> Color:
	assert(HEX.has(name), "unknown palette role '%s'" % name)
	return Color(HEX[name])


## Value (perceptual lightness proxy) of a role, for the reduction test — the
## intent's claim is that identity survives in value alone, which is only
## checkable if value is something we can read off the palette.
static func value_of(name: String) -> float:
	var c := col(name)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
