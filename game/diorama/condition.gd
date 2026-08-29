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
