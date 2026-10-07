PR 71 revised vitality-overlay temporal capture

Repository commit: 8ca7cc4c0af75a316de4047a25741da340a025b2
Branch under review: switchboard/issue-65
Godot: 4.7.2.stable.official.ed1daf0bf
Seed: 20260815
Overlay: vitality-graze
Caption recorded on every frame: graze — how worn
Render size: 1280x720
Frames: 121 PNG files, one for every integer turn 300 through 420 inclusive

Legend recorded on screen:
  hard-worn  under 0.90 (hatched)
  worn       0.90 to 0.95
  worked     0.95 to 0.99
  healthy    0.99 and up
  footnote: bands of a smooth value

Capture provenance:
  Existing capture.sh / tools/capture.gd harness, real game/main.tscn scene.
  One continuous deterministic world instance started at turn 0 and advanced
  incrementally to each target. It was not restarted per image.
  Rendering used the available WSLg X11 context with llvmpipe. Each PNG passed
  the harness's non-blank content check at 1280x720 before archive creation.

Frame order:
  Filename order is chronological: seed-20260815-turn-300.png through
  seed-20260815-turn-420.png. Do not interpolate, recolor, crop away captions
  or legend, or alter the values. This archive contains full-map frames.

Verification:
  At this exact head, GODOT=/home/colin/.local/bin/godot ./test.sh completed
  successfully. The hex-map display measurement (seed 20260815, turns
  300-420, grazing) counts land only: the denominator is non-WATER tile-frames,
  exactly the tiles the renderer bands; water is excluded. It reported
  hard-worn 0.411%, worn 4.822%, worked 15.235%, healthy 79.532%, so about
  20.5% of ordinary ground is visibly not-healthy. An earlier measurement that
  included water in the denominator (healthy 87.020%) is obsolete.

Human scope:
  These frames are evidence for the still-pending human AC8 readability check.
  They do not constitute acceptance, a merge approval, or a simulation claim.
