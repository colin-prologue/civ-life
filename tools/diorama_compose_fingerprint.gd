extends SceneTree

## Prints a fingerprint of DioramaCompose + DioramaStyles output for a fixed
## list of seeds, one line per seed, in the same "seed fingerprint" shape
## tools/diorama_fingerprint.gd and tools/world_fingerprint.gd already use —
## so test.sh diffs this generator's output across two separate Godot
## processes with the exact same mechanism.
##
## compose.gd and styles.gd were invisible to that check before this file
## existed: tools/diorama_fingerprint.gd only walks DioramaSpike, so a
## cross-process divergence anywhere in the style-tree resolver (an instance
## id folded into a channel, a Dictionary iterated in address order) would
## reproduce cleanly inside one process — where the in-suite determinism test
## looks — and never show up there.
##
## Folded through DioramaMeshKit rather than compared as raw part
## dictionaries: mesh_kit.fingerprint() is the same order-stable digest the
## renderer's own determinism guarantee already rests on, so this checks the
## same thing DioramaGrammar.emit() feeds the screen, not a structurally
## different comparison of dictionaries that could drift out of sync with it.
##
## A sibling file rather than folded into diorama_fingerprint.gd's existing
## loop: that file's own comment (mirrored in test.sh) explains why each
## generator is checked on its own instead of through one concatenated
## stream — a generator that silently stopped emitting would otherwise hide
## behind the other one's still-nonempty output. The same argument holds one
## level down: folding the compose path into DioramaSpike's fingerprint would
## let a break in either half hide behind the other still being live.
##
## Several building ids are folded into one line per seed (not just one) so
## the row resolver's `count` sampling — freshly reworked to inclusive
## integer bounds — is actually exercised across several draws rather than
## whatever a single id happens to produce.
##
## Lives outside res://test because GUT treats any script there that does not
## extend GutTest as a broken test.

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
			DioramaCompose.apply_roles(parts, DioramaCultures.palette("sunlit"))
			DioramaGrammar.emit(b, parts, Transform3D.IDENTITY)
			for p: Dictionary in parts:
				# Quantised, because a float printed through two processes must
				# compare equal bit-for-bit and 1e-6 is far finer than any
				# visible difference in when a part falls.
				#
				# Masked to 52 bits, not 60: int64 signed overflow on the `* 31`
				# below is the same unspecified-behaviour smell str_hash() exists
				# to avoid — it happens to wrap identically on two processes of
				# the same binary, but that is an accident of platform, not a
				# guarantee, and this fold sits inside a gate whose only job is
				# to catch exactly that class of accident. 52 bits keeps
				# `needs * 31` (~1.4e17 at most) comfortably under int64's
				# ~9.2e18 ceiling, so the multiply never overflows in the first
				# place — nothing to wrap, nothing platform-dependent to trust.
				needs = (needs * 31 + int(round(p["need"] * 1000000.0))) \
						& 0xFFFFFFFFFFFFF
	return b.fingerprint() ^ needs
