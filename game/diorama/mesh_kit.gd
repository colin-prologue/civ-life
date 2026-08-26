class_name DioramaMeshKit
extends RefCounted
## Flat-shaded triangle accumulator with vertex colours.
##
## Everything in the spike is composed geometry — no imported assets. One
## builder per logical mesh; per-face normals give the faceted model look.
## Vertex colours + a single vertex-colour material keep the whole diorama
## to a handful of draw calls.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()


## Single-sided. CALLER CONTRACT: wind (a, b, c) counter-clockwise as seen
## from OUTSIDE the surface, so that (b-a)x(c-a) is the outward normal. Every
## recipe in this spike follows that convention; the engine's disagreement
## with it is handled here, once.
##
## Godot's front face is the winding whose right-hand normal points AWAY from
## the viewer — clockwise-front, the opposite of the OpenGL default. So the
## outward-CCW triangle the caller describes is the one Godot would cull. We
## therefore emit it reversed, and store the outward normal `n` alongside:
## winding satisfies the rasteriser, normal satisfies the light.
##
## This used to emit each triangle twice with opposed normals, to spare the
## recipes from having to agree on a winding. That was not free. The two copies
## are coplanar and coincident, so they z-fight — and because Godot kept the
## clockwise one, the copy that survived was always the one carrying the INWARD
## normal. Every surface in the diorama shaded with a normal pointing away from
## the sun and took no directional light at all; what looked like lighting was
## pure ambient. Hence no cast shadow, no plane separation, and speckle along
## the depth ties. Measured at the time: a mesh_kit box rendered 2.5x darker
## than an identical stock BoxMesh under the same light, and the terrain — whose
## windings already followed the caller contract — vanished entirely the moment
## the back faces were dropped. See test/test_diorama_mesh_kit.gd.
func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	verts.append(a)
	verts.append(c)
	verts.append(b)
	for _i in range(3):
		normals.append(n)
		colors.append(col)


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	add_tri(a, b, c, col)
	add_tri(a, c, d, col)


## Axis-aligned box in local space, transformed by xf. size is full extents;
## the box sits on its local origin plane (y in [0, size.y]).
func add_box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var p := []
	for yy in [0.0, size.y]:
		for corner in [Vector3(-hx, yy, -hz), Vector3(hx, yy, -hz),
				Vector3(hx, yy, hz), Vector3(-hx, yy, hz)]:
			p.append(xf * corner)
	add_quad(p[1], p[2], p[3], p[0], col)          # bottom (-y)
	add_quad(p[7], p[6], p[5], p[4], col)          # top    (+y)
	add_quad(p[4], p[5], p[1], p[0], col)          # -z
	add_quad(p[6], p[7], p[3], p[2], col)          # +z
	add_quad(p[5], p[6], p[2], p[1], col)          # +x
	add_quad(p[7], p[4], p[0], p[3], col)          # -x


## Tapered box: top face shrunk toward its centre. taper 0 = straight box,
## taper 1 = pyramid.
func add_tapered_box(xf: Transform3D, size: Vector3, taper: float, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var s := clampf(1.0 - taper, 0.001, 1.0)
	var bot := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz),
			Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var top := [Vector3(-hx * s, size.y, -hz * s), Vector3(hx * s, size.y, -hz * s),
			Vector3(hx * s, size.y, hz * s), Vector3(-hx * s, size.y, hz * s)]
	var b := []
	var t := []
	for v in bot:
		b.append(xf * v)
	for v in top:
		t.append(xf * v)
	add_quad(b[1], b[2], b[3], b[0], col)
	add_quad(t[3], t[2], t[1], t[0], col)
	for i in range(4):
		var j := (i + 1) % 4
		add_quad(t[i], t[j], b[j], b[i], col)


## N-gon prism (column) with optional taper, sitting on local origin.
func add_prism(xf: Transform3D, radius: float, height: float, col: Color,
		segments: int = 6, taper: float = 0.15) -> void:
	var rt := radius * (1.0 - taper)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var b0 := xf * Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := xf * Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := xf * Vector3(cos(a0) * rt, height, sin(a0) * rt)
		var t1 := xf * Vector3(cos(a1) * rt, height, sin(a1) * rt)
		add_quad(t0, t1, b1, b0, col)
		add_tri(xf * Vector3(0, height, 0), t1, t0, col)
		add_tri(xf * Vector3(0, 0, 0), b0, b1, col)


## Cone (spire / conifer tier), sitting on local origin.
func add_cone(xf: Transform3D, radius: float, height: float, col: Color,
		segments: int = 7) -> void:
	var tip := xf * Vector3(0, height, 0)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var b0 := xf * Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := xf * Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		add_tri(b1, b0, tip, col)
		add_tri(xf * Vector3(0, 0, 0), b0, b1, col)


## Faceted half-dome, flat side down at local origin.
func add_dome(xf: Transform3D, radius: float, squash: float, col: Color,
		segments: int = 10, rings: int = 4) -> void:
	for ri in range(rings):
		var p0 := PI * 0.5 * ri / rings
		var p1 := PI * 0.5 * (ri + 1) / rings
		for i in range(segments):
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var v00 := xf * _dome_pt(radius, squash, a0, p0)
			var v10 := xf * _dome_pt(radius, squash, a1, p0)
			var v01 := xf * _dome_pt(radius, squash, a0, p1)
			var v11 := xf * _dome_pt(radius, squash, a1, p1)
			if ri == rings - 1:
				add_tri(v10, v01, v00, col)
			else:
				add_quad(v10, v11, v01, v00, col)


func _dome_pt(radius: float, squash: float, a: float, p: float) -> Vector3:
	return Vector3(cos(a) * cos(p) * radius, sin(p) * radius * squash,
			sin(a) * cos(p) * radius)


## Faceted blob (canopy mass): squashed icosahedron-ish via low-res dome
## mirrored — good enough for a canopy silhouette at diorama distance.
func add_blob(xf: Transform3D, radius: float, squash: float, col: Color) -> void:
	add_dome(xf, radius, squash, col, 7, 3)
	var flip := xf * Transform3D(Basis.from_euler(Vector3(PI, 0, 0)), Vector3.ZERO)
	add_dome(flip, radius, squash * 0.5, col, 7, 2)


func commit(existing: ArrayMesh = null) -> ArrayMesh:
	var mesh := existing if existing != null else ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Order-stable fingerprint of the accumulated geometry, for determinism
## tests — mirrors tools/world_fingerprint.gd's role for the sim.
func fingerprint() -> int:
	var acc := 1469598103934665603
	for v in verts:
		acc = _mix(acc, int(round(v.x * 1000.0)))
		acc = _mix(acc, int(round(v.y * 1000.0)))
		acc = _mix(acc, int(round(v.z * 1000.0)))
	for c in colors:
		acc = _mix(acc, c.to_rgba32())
	return acc


static func _mix(acc: int, value: int) -> int:
	return ((acc ^ value) * 1099511628211) & 0x7FFFFFFFFFFFFFFF
