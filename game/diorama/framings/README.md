# Framings

One scene per frame the spike has to produce for review. They exist because
`capture.sh --scene` photographs a scene, and the parameters under
examination are exported properties — so a parameter sweep is a set of scenes
with different property overrides, not a set of command-line flags.

All of them run the same `spike.gd` against the same seed. Anything that
differs between two of these files is, by construction, the thing the pair is
evidence about.

```
./capture.sh --scene res://game/diorama/framings/fov-15.tscn \
    --label fov-15 --name s0-diorama
```
