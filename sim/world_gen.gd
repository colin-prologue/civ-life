class_name WorldGen
extends RefCounted

## Turns an integer seed into a terrain map.
##
## The generator draws every random number from one `RandomNumberGenerator`
## seeded with the world seed, consumed in a fixed order, and touches nothing
## else — no engine singletons, no clock, no global RNG. That is the whole
## contract: seed in, identical map out, on any run and any machine.
##
## Shape of the world: two layers of value noise (elevation and moisture) built
## on random lattices, plus an edge falloff that pushes the rim of the map under
## water. The falloff is what keeps land in one piece instead of scattering it,
## which matters more right now than the terrain being interesting.
##
## Both fields are normalised to their own observed range across the map before
## anything is classified, and the thresholds below are read as fractions of
## that range. This is not cosmetic: summing octaves of uniform noise piles the
## raw values up in a narrow band around the middle, so absolute thresholds
## spread across 0..1 sample almost none of it — measured directly, the raw
## field put 66-86% of every map under water and produced essentially no
## mountains. Normalising first is also what keeps the thresholds meaningful if
## the octave list is ever changed.
##
## Normalisation is a second pass over data already computed in a fixed order,
## so it costs nothing in determinism: same seed, same field, same range, same
## map.

enum Terrain {
	WATER,
	GRASS,
	FOREST,
	HILL,
	MOUNTAIN,
}

const DEFAULT_WIDTH := 40
const DEFAULT_HEIGHT := 30

# Lattice resolutions for the noise octaves, coarse to fine. Each successive
# octave contributes half as much as the one before it.
const _ELEVATION_OCTAVES := [3, 6, 12]
const _MOISTURE_OCTAVES := [2, 5]

const _SEA_LEVEL := 0.44
const _HILL_LEVEL := 0.62
const _MOUNTAIN_LEVEL := 0.74
const _FOREST_MOISTURE := 0.50

# How hard the map edge is pulled down, and how sharply that pull falls off
# toward the middle. High exponent = flat interior, steep rim.
const _FALLOFF_STRENGTH := 0.55
const _FALLOFF_EXPONENT := 3.0


## Generate a world. Same seed, same size, same map — always.
static func generate(world_seed: int, width := DEFAULT_WIDTH, height := DEFAULT_HEIGHT) -> WorldMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	# Order matters: elevation lattices are drawn before moisture lattices, so
	# the sequence of draws is fixed by the constants above and not by anything
	# discovered at run time.
	var elevation := _build_lattices(rng, _ELEVATION_OCTAVES)
	var moisture := _build_lattices(rng, _MOISTURE_OCTAVES)

	var grid := HexGrid.new(width, height)
	var map := WorldMap.new(grid, world_seed)

	# Pass one: the raw fields, in grid order. Index i here is grid.index_of()
	# for the same tile, because both are row-major over offset space.
	var raw_elevation := PackedFloat32Array()
	var raw_moisture := PackedFloat32Array()
	raw_elevation.resize(grid.tile_count())
	raw_moisture.resize(grid.tile_count())

	var i := 0
	for row in range(height):
		for col in range(width):
			var u := float(col) / float(width - 1)
			var v := float(row) / float(height - 1)
			raw_elevation[i] = _fbm(elevation, u, v) - _falloff(u, v)
			raw_moisture[i] = _fbm(moisture, u, v)
			i += 1

	# Pass two: classify against each field's own range.
	_normalise(raw_elevation)
	_normalise(raw_moisture)
	for index in range(grid.tile_count()):
		map.set_terrain(grid.coord_at(index), _classify(raw_elevation[index], raw_moisture[index]))

	# Living and built things go on last, once every tile knows what it grows:
	# both placements read forage, and forage is only meaningful after the whole
	# map is classified. Each draws from its own generator (see `Herd.populate`
	# and `CityGen.populate`), so adding them did not move a single tile of
	# terrain on any existing seed.
	Herd.populate(map)

	# The city goes on after the herds, drawing from its own generator again, so
	# that placing it moved neither the terrain nor a single herd on any seed
	# that existed before it.
	CityGen.populate(map)

	return map


## Rescale a field in place so its lowest value is 0 and its highest is 1. A
## field that is entirely flat is left alone rather than divided by zero.
static func _normalise(values: PackedFloat32Array) -> void:
	if values.is_empty():
		return
	var lowest := values[0]
	var highest := values[0]
	for v in values:
		lowest = minf(lowest, v)
		highest = maxf(highest, v)
	var span := highest - lowest
	if span <= 0.0:
		return
	for index in range(values.size()):
		values[index] = (values[index] - lowest) / span


static func _classify(elevation: float, moisture: float) -> int:
	if elevation < _SEA_LEVEL:
		return Terrain.WATER
	if elevation >= _MOUNTAIN_LEVEL:
		return Terrain.MOUNTAIN
	if elevation >= _HILL_LEVEL:
		return Terrain.HILL
	if moisture >= _FOREST_MOISTURE:
		return Terrain.FOREST
	return Terrain.GRASS


## Distance-from-centre penalty in 0.._FALLOFF_STRENGTH. Zero in the middle of
## the map, full strength at the rim.
static func _falloff(u: float, v: float) -> float:
	var dx := absf(u * 2.0 - 1.0)
	var dy := absf(v * 2.0 - 1.0)
	var d := maxf(dx, dy)
	return _FALLOFF_STRENGTH * pow(d, _FALLOFF_EXPONENT)


static func _build_lattices(rng: RandomNumberGenerator, resolutions: Array) -> Array:
	var out := []
	for res in resolutions:
		out.append(_Lattice.new(rng, res, res))
	return out


## Fractal sum of the octaves at normalised position (u, v), each in 0..1.
## Result is in 0..1 because every lattice value is.
static func _fbm(lattices: Array, u: float, v: float) -> float:
	var total := 0.0
	var amplitude := 1.0
	var normaliser := 0.0
	for lattice in lattices:
		total += amplitude * lattice.sample(u, v)
		normaliser += amplitude
		amplitude *= 0.5
	return total / normaliser


## A grid of random values in 0..1 with smooth interpolation between them —
## value noise, written out rather than pulled from the engine so the exact
## numbers are ours and stay put.
class _Lattice extends RefCounted:
	var _cells_x: int
	var _cells_y: int
	var _values: PackedFloat32Array

	func _init(rng: RandomNumberGenerator, cells_x: int, cells_y: int) -> void:
		_cells_x = cells_x
		_cells_y = cells_y
		_values = PackedFloat32Array()
		_values.resize((cells_x + 1) * (cells_y + 1))
		for i in range(_values.size()):
			_values[i] = rng.randf_range(0.0, 1.0)

	## Sample at normalised (u, v), each in 0..1.
	func sample(u: float, v: float) -> float:
		var x := u * float(_cells_x)
		var y := v * float(_cells_y)
		var x0 := clampi(int(floor(x)), 0, _cells_x - 1)
		var y0 := clampi(int(floor(y)), 0, _cells_y - 1)
		var tx := clampf(x - float(x0), 0.0, 1.0)
		var ty := clampf(y - float(y0), 0.0, 1.0)
		# Smoothstep the interpolation weights so the lattice edges do not show
		# up as visible creases.
		var sx := tx * tx * (3.0 - 2.0 * tx)
		var sy := ty * ty * (3.0 - 2.0 * ty)
		var top := lerpf(_at(x0, y0), _at(x0 + 1, y0), sx)
		var bottom := lerpf(_at(x0, y0 + 1), _at(x0 + 1, y0 + 1), sx)
		return lerpf(top, bottom, sy)

	func _at(x: int, y: int) -> float:
		return _values[y * (_cells_x + 1) + x]
