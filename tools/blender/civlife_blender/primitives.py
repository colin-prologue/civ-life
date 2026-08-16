"""Tiny primitive vocabulary. Silhouette over topology, always.

Every function returns a bmesh built at the origin; callers place it.
Units are abstract 'model metres'; a house is ~2-4 units tall.
"""
import math

import bmesh
from mathutils import Matrix, Vector


def slab(w, d, h, taper=0.0):
    """Box with optional top taper (0 = straight, 1 = pyramid)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    top = min(1.0 - 1e-4, max(0.0, taper))
    for v in bm.verts:
        s = 1.0 - top if v.co.z > 0 else 1.0
        v.co.x *= w * s
        v.co.y *= d * s
        v.co.z = v.co.z * h + h / 2.0
    return bm


def column(radius, height, segments=8, taper=0.15):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, segments=segments,
        radius1=radius, radius2=radius * (1.0 - taper), depth=height)
    for v in bm.verts:
        v.co.z += height / 2.0
    return bm


def spire(radius, height, segments=6):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, segments=segments,
        radius1=radius, radius2=0.001, depth=height)
    for v in bm.verts:
        v.co.z += height / 2.0
    return bm


def dome(radius, squash=0.75, segments=12, rings=5):
    """Faceted half-sphere."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(
        bm, u_segments=segments, v_segments=rings * 2, radius=radius)
    geom = [v for v in bm.verts if v.co.z < -1e-5]
    bmesh.ops.delete(bm, geom=geom, context="VERTS")
    for v in bm.verts:
        v.co.z *= squash
    # cap the rim
    rim = [e for e in bm.edges if e.is_boundary]
    if rim:
        bmesh.ops.holes_fill(bm, edges=rim)
    return bm


def blob(radius, squash=0.7, subdivisions=1):
    """Faceted icosphere mass - canopy, boulder."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    for v in bm.verts:
        v.co.z *= squash
    return bm


def stepped_mass(w, d, tiers, tier_h, shrink=0.24):
    """Stack of shrinking slabs - the Deco setback profile."""
    bm = bmesh.new()
    for t in range(tiers):
        s = (1.0 - shrink) ** t
        tier = bmesh.new()
        bmesh.ops.create_cube(tier, size=1.0)
        for v in tier.verts:
            v.co.x *= w * s
            v.co.y *= d * s
            v.co.z = v.co.z * tier_h + tier_h / 2.0 + t * tier_h
        tier_mesh = _tmp_mesh(tier)
        bm.from_mesh(tier_mesh)
        _drop_mesh(tier_mesh)
    return bm


def arch_pieces(width, depth, height, thickness, segments=7):
    """Arch as separate pieces: [(bmesh, centre_z), ...] - piers first, then
    voussoirs bottom-up. Lets a ruin keep pier stumps or a partial span."""
    pieces = []
    span = width - 2 * thickness
    r = span / 2.0 + thickness / 2.0
    pier_h = max(0.05, height - r)
    for side in (-1, 1):
        pier = bmesh.new()
        bmesh.ops.create_cube(pier, size=1.0)
        for v in pier.verts:
            v.co.x = v.co.x * thickness + side * (width / 2.0 - thickness / 2.0)
            v.co.y *= depth
            v.co.z = v.co.z * pier_h + pier_h / 2.0
        pieces.append((pier, pier_h / 2.0))
    for i in range(segments):
        a0 = math.pi * i / segments
        a1 = math.pi * (i + 1) / segments
        mid = (a0 + a1) / 2.0
        seg_len = r * (a1 - a0) * 1.15
        seg = bmesh.new()
        bmesh.ops.create_cube(seg, size=1.0)
        rot = Matrix.Rotation(-mid, 4, "Y")  # long axis tangent to arc
        for v in seg.verts:
            v.co = Vector((v.co.x * thickness, v.co.y * depth, v.co.z * seg_len))
            v.co = rot @ v.co
            v.co.x += math.cos(mid) * r
            v.co.z += pier_h + math.sin(mid) * r
        pieces.append((seg, pier_h + math.sin(mid) * r))
    return pieces


def arch(width, depth, height, thickness, segments=7):
    """Two piers + voussoir segments along a half-circle: model-kit arch."""
    bm = bmesh.new()
    span = width - 2 * thickness
    r = span / 2.0 + thickness / 2.0
    pier_h = max(0.05, height - r)
    for side in (-1, 1):
        pier = bmesh.new()
        bmesh.ops.create_cube(pier, size=1.0)
        for v in pier.verts:
            v.co.x = v.co.x * thickness + side * (width / 2.0 - thickness / 2.0)
            v.co.y *= depth
            v.co.z = v.co.z * pier_h + pier_h / 2.0
        m = _tmp_mesh(pier)
        bm.from_mesh(m)
        _drop_mesh(m)
    for i in range(segments):
        a0 = math.pi * i / segments
        a1 = math.pi * (i + 1) / segments
        mid = (a0 + a1) / 2.0
        seg_len = r * (a1 - a0) * 1.15
        seg = bmesh.new()
        bmesh.ops.create_cube(seg, size=1.0)
        rot = Matrix.Rotation(-mid, 4, "Y")  # long axis tangent to arc
        for v in seg.verts:
            v.co = Vector((v.co.x * thickness, v.co.y * depth, v.co.z * seg_len))
            v.co = rot @ v.co
            v.co.x += math.cos(mid) * r
            v.co.z += pier_h + math.sin(mid) * r
        m = _tmp_mesh(seg)
        bm.from_mesh(m)
        _drop_mesh(m)
    return bm


def ring(radius, height, thickness, segments=10):
    """Circle of slabs - colonnade ring, henge, arena rim."""
    bm = bmesh.new()
    for i in range(segments):
        a = 2 * math.pi * i / segments
        seg_len = 2 * math.pi * radius / segments * 0.8
        seg = bmesh.new()
        bmesh.ops.create_cube(seg, size=1.0)
        rot = Matrix.Rotation(a, 4, "Z")
        for v in seg.verts:
            v.co = Vector((v.co.x * thickness, v.co.y * seg_len,
                           v.co.z * height + height / 2.0))
            v.co = rot @ v.co
            v.co.x += math.cos(a) * radius
            v.co.y += math.sin(a) * radius
        m = _tmp_mesh(seg)
        bm.from_mesh(m)
        _drop_mesh(m)
    return bm


def beam(length, w, h):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= length
        v.co.y *= w
        v.co.z = v.co.z * h + h / 2.0
    return bm


def card(w, h, thickness=0.03):
    """A thin standing card with real thickness so it casts shadows."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= w
        v.co.y *= thickness
        v.co.z = v.co.z * h + h / 2.0
    return bm


# --------------------------------------------------------------------- utils

import bpy as _bpy


def _tmp_mesh(bm):
    mesh = _bpy.data.meshes.new("_tmp")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def _drop_mesh(mesh):
    _bpy.data.meshes.remove(mesh)


def merge(bms):
    """Merge a list of bmeshes into one."""
    out = bmesh.new()
    for bm in bms:
        m = _tmp_mesh(bm)
        out.from_mesh(m)
        _drop_mesh(m)
    return out
