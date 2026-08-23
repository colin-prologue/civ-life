"""CultureStyle: shape preferences, not assets. Two deliberately opposite
grammars for the first study."""
from dataclasses import dataclass


@dataclass
class CultureStyle:
    name: str
    verticality: float      # 0 low & spreading .. 1 towers
    symmetry: float         # 0 jittered .. 1 mirrored/regular
    curvature: float        # 0 angular (slabs/spires) .. 1 curved (arches/domes)
    setback_frequency: float
    arch_frequency: float
    spire_frequency: float
    monumentality: float    # 0 clustered small .. 1 singular monumental
    repetition: float       # 0 irregular .. 1 rhythmic colonnades
    accent: str = "brass"   # aspiration material
    body: str = "plaster"   # main material
    secondary: str = "ochre"


DECO = CultureStyle(
    name="deco",
    verticality=0.85,
    symmetry=0.9,
    curvature=0.15,
    setback_frequency=0.85,
    arch_frequency=0.25,
    spire_frequency=0.65,
    monumentality=0.9,
    repetition=0.7,
    accent="brass",
    body="plaster",
    secondary="ochre",
)

ORGANIC = CultureStyle(
    name="organic",
    verticality=0.2,
    symmetry=0.3,
    curvature=0.9,
    setback_frequency=0.1,
    arch_frequency=0.8,
    spire_frequency=0.0,
    monumentality=0.5,
    repetition=0.3,
    accent="verdigris",
    body="plaster2",
    secondary="wood",
)
