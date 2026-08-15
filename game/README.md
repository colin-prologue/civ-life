# game/ — the Godot layer

Scenes, rendering, input, and presentation. A thin client over `sim/`.

This layer reads simulation state and draws it; it does not own world rules. A
rule that lives here instead of in `sim/` is a rule that cannot be tested
headlessly and cannot be reproduced from a seed.

`main.tscn` is currently an empty placeholder scene so the project has a valid
`run/main_scene`. The hex map, camera, and input come later.
