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


func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	# Two-sided on purpose: recipes compose boxes, fans, and open surfaces
	# with mixed windings, and a spike optimises for tunability over
	# triangle count. Each side carries its own outward normal so lighting
	# is correct from either face. TODO(S0-local): settle windings and drop
	# the back faces once the composition is locked.
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for _i in range(3):
		normals.append(n)
		colors.append(col)
	verts.append(a)
	verts.append(c)
	verts.append(b)
	for _i in range(3):
		normals.append(-n)
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
	add_quad(p[0], p[3], p[2], p[1], col)          # bottom
	add_quad(p[4], p[5], p[6], p[7], col)          # top
	add_quad(p[0], p[1], p[5], p[4], col)          # -z
	add_quad(p[2], p[3], p[7], p[6], col)          # +z
	add_quad(p[1], p[2], p[6], p[5], col)          # +x
	add_quad(p[3], p[0], p[4], p[7], col)          # -x


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
	add_quad(b[0], b[3], b[2], b[1], col)
	add_quad(t[0], t[1], t[2], t[3], col)
	for i in range(4):
		var j := (i + 1) % 4
		add_quad(b[i], b[j], t[j], t[i], col)


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
		add_quad(b0, b1, t1, t0, col)
		add_tri(xf * Vector3(0, height, 0), t0, t1, col)
		add_tri(xf * Vector3(0, 0, 0), b1, b0, col)


## Cone (spire / conifer tier), sitting on local origin.
func add_cone(xf: Transform3D, radius: float, height: float, col: Color,
		segments: int = 7) -> void:
	var tip := xf * Vector3(0, height, 0)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var b0 := xf * Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := xf * Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		add_tri(b0, b1, tip, col)
		add_tri(xf * Vector3(0, 0, 0), b1, b0, col)


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
				add_tri(v00, v01, v10, col)
			else:
				add_quad(v00, v01, v11, v10, col)


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
