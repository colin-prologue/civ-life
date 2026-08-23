class_name DioramaHexKit
extends RefCounted
## Hash channels and hex math for the diorama spike.
##
## Every visual decision derives from h01(seed, ...) — pure, order-independent
## streams per concern, mirroring the sim's determinism discipline. Never draw
## from a sequential RNG for per-element variation: inserting one extra draw
## would reshuffle everything after it.

const SQRT3 := 1.7320508075688772


## Deterministic hash to [0, 1). Same inputs, same output, any machine.
static func h01(seed: int, a: int, b: int = 0, c: int = 0) -> float:
	var h := seed ^ (a * 374761393) ^ (b * 668265263) ^ (c * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


## Flat-top, odd-q offset — the sim's convention (AgDR-006). Returns the hex
## centre on the ground plane as (x, z); Y is up in Godot.
static func hex_center(q: int, r: int, s: float = 1.0) -> Vector2:
	var x := 1.5 * s * q
	var z := SQRT3 * s * (r + 0.5 * (q & 1))
	return Vector2(x, z)


## Chaikin corner cutting — hex-line paths read mechanical without it.
static func chaikin(points: PackedVector2Array, iterations: int = 2) -> PackedVector2Array:
	var pts := points
	for _i in range(iterations):
		var nxt := PackedVector2Array()
		nxt.append(pts[0])
		for k in range(pts.size() - 1):
			var a := pts[k]
			var b := pts[k + 1]
			nxt.append(a * 0.75 + b * 0.25)
			nxt.append(a * 0.25 + b * 0.75)
		nxt.append(pts[pts.size() - 1])
		pts = nxt
	return pts
