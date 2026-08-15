extends GutTest

# Guards the boundary from .decisions/AgDR-001: sim/ is plain GDScript with no
# scene tree, no clock, and no unseeded randomness. That rule is easy to state
# and easy to break by reflex, so it is checked mechanically rather than by
# reviewer memory.
#
# This is a source scan, not a type check, so it is blunt by construction: it
# can only see text. The FORBIDDEN list below may need narrowing with an
# allowlist as sim/ grows — widening it is fine, removing it is not, because
# nothing else holds this boundary.

const SIM_DIR := "res://sim"

# pattern -> what it would mean if it showed up in sim/
const FORBIDDEN := {
	"(?<![.\\w])Node\\b": "a scene-tree dependency",
	"(?<![.\\w])Engine\\b": "engine singleton state",
	"(?<![.\\w])Time\\b": "wall-clock time",
	"(?<![.\\w])randi\\s*\\(": "the global unseeded RNG",
	"(?<![.\\w])randf\\s*\\(": "the global unseeded RNG",
	"(?<![.\\w])randomize\\s*\\(": "reseeding from the clock",
	"(?<![.\\w])OS\\b": "host environment state",
}


func test_sim_sources_stay_headless_and_seeded() -> void:
	var files := _gd_files(SIM_DIR)
	assert_gt(files.size(), 0, "the scan actually found sources to scan in %s" % SIM_DIR)

	var violations: Array[String] = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "could read %s" % path)
		for pattern in FORBIDDEN:
			var regex := RegEx.new()
			assert_eq(regex.compile(pattern), OK, "pattern compiles: %s" % pattern)
			var found := regex.search(text)
			if found != null:
				violations.append(
					"%s: '%s' — %s" % [path, found.get_string(), FORBIDDEN[pattern]]
				)

	assert_eq(violations.size(), 0, "sim/ reaches outside the headless core: %s" % [violations])


func test_the_scan_would_notice_a_violation() -> void:
	# A grep that matches nothing is indistinguishable from a grep that is
	# broken. Prove the patterns actually fire on the thing they describe, and
	# that they tolerate the seeded call they must not flag.
	var offending := "func _ready() -> void:\n\tvar x = randi()\n"
	var innocent := "var rng := RandomNumberGenerator.new()\nvar x := rng.randi_range(0, 9)\n"

	var hits_offending := 0
	var hits_innocent := 0
	for pattern in FORBIDDEN:
		var regex := RegEx.new()
		regex.compile(pattern)
		if regex.search(offending) != null:
			hits_offending += 1
		if regex.search(innocent) != null:
			hits_innocent += 1

	assert_gt(hits_offending, 0, "the scan catches an unseeded draw")
	assert_eq(hits_innocent, 0, "the scan does not flag a seeded generator")


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entries: Array[String] = []
	var entry_name := dir.get_next()
	while entry_name != "":
		entries.append(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	entries.sort()  # stable order so a failure report reads the same every run
	for entry in entries:
		var full := "%s/%s" % [dir_path, entry]
		if DirAccess.dir_exists_absolute(full):
			out.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			out.append(full)
	return out
