"""Deterministic helpers, materials, and scene plumbing for the civ-life bpy lab.

Everything visual derives from (seed, *channel) -> Random, echoing the repo's
hash-channel discipline: independent channels keep unrelated geometry stable
when one generator changes.
"""
import hashlib
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- determinism

def chan(seed, *channel):
    """A Random seeded from (seed, channel...) - order-independent streams."""
    key = repr((seed,) + channel).encode()
    h = int.from_bytes(hashlib.sha256(key).digest()[:8], "big")
    return random.Random(h)


# ------------------------------------------------------------------- palette

def _lin(hexcode):
    """sRGB hex -> linear RGBA for Cycles."""
    v = [int(hexcode[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(c ** 2.2 for c in v) + (1.0,)


PALETTE = {
    "indigo":    _lin("#12151e"),
    "plaster":   _lin("#e6dfcc"),
    "plaster2":  _lin("#cfc6ae"),
    "moss":      _lin("#5f7247"),
    "moss2":     _lin("#4a5c39"),
    "verdigris": _lin("#4f8f7a"),
    "brass":     _lin("#c9a44a"),
    "ochre":     _lin("#a8794a"),
    "wood":      _lin("#7a5c38"),
    "water":     _lin("#2e6d78"),
    "stone":     _lin("#8d8877"),
    "hilltint":  _lin("#77714a"),
}


def material(name, roughness=0.9):
    mat = bpy.data.materials.get("cl_" + name)
    if mat:
        return mat
    mat = bpy.data.materials.new("cl_" + name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = PALETTE[name]
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def aged_material(base_name, age):
    """Base color lerped toward verdigris/moss by age in [0,1]."""
    key = "%s_aged%02d" % (base_name, int(age * 10))
    mat = bpy.data.materials.get("cl_" + key)
    if mat:
        return mat
    mat = bpy.data.materials.new("cl_" + key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    a, b = PALETTE[base_name], PALETTE["verdigris"]
    t = 0.8 * age
    col = tuple(a[i] + (b[i] - a[i]) * t for i in range(3)) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.92
    return mat


# --------------------------------------------------------------- scene setup

def fresh_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    world = bpy.data.worlds.new("cl_world")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = PALETTE["indigo"]
    bg.inputs[1].default_value = 1.0
    return scene


def add_sun(elevation_deg=28.0, azimuth_deg=145.0, energy=4.0, softness_deg=3.0):
    import math
    light = bpy.data.lights.new("cl_sun", type="SUN")
    light.energy = energy
    light.angle = math.radians(softness_deg)
    ob = bpy.data.objects.new("cl_sun", light)
    bpy.context.collection.objects.link(ob)
    ob.rotation_euler = (
        math.radians(90.0 - elevation_deg), 0.0, math.radians(azimuth_deg))
    return ob


def add_camera(target, distance, fov_deg=22.0, pitch_deg=32.0, yaw_deg=25.0,
               name="cl_cam"):
    """Long-lens diorama camera orbiting a target point."""
    import math
    cam = bpy.data.cameras.new(name)
    cam.lens_unit = "FOV"
    cam.angle = math.radians(fov_deg)
    cam.clip_end = 10000.0
    ob = bpy.data.objects.new(name, cam)
    bpy.context.collection.objects.link(ob)
    pitch = math.radians(pitch_deg)
    yaw = math.radians(yaw_deg)
    offset = Vector((
        math.cos(pitch) * math.sin(yaw),
        -math.cos(pitch) * math.cos(yaw),
        math.sin(pitch))) * distance
    ob.location = Vector(target) + offset
    direction = Vector(target) - ob.location
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = ob
    return ob


def render(path, res=(1600, 1000), samples=32):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    # Standard (not AgX): flat poster color on sculpture, not filmic realism.
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def add_fill(elevation_deg=55.0, azimuth_deg=330.0, energy=1.1):
    return add_sun(elevation_deg, azimuth_deg, energy=energy, softness_deg=40.0)


# ------------------------------------------------------------- mesh plumbing

def obj_from_bmesh(bm, name, mat, matrix=None):
    if matrix:
        bm.transform(matrix)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob


def move(ob, loc=(0, 0, 0), rot_z=0.0, scale=1.0):
    ob.matrix_world = (
        Matrix.Translation(Vector(loc))
        @ Matrix.Rotation(rot_z, 4, "Z")
        @ (Matrix.Scale(scale, 4) if scale != 1.0 else Matrix.Identity(4))
    ) @ ob.matrix_world
    return ob
