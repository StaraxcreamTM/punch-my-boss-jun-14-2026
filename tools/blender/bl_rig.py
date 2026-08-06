"""Assemble a game character's sliced parts into a Blender 2D cutout rig and
render animations to transparent PNG sequences for the play_anim overlay system.

Run headless:
  blender -b -P tools/blender/bl_rig.py -- <parts_dir> <out_dir> <anim> [start end]

<parts_dir>  a game assets/bossN/parts folder (must contain parts.json + PNGs)
<out_dir>    where fNNN.png frames are written
<anim>       animation name (see ANIMS); "tpose" just renders the standing figure

The rig is data-driven: parts.json gives each piece's origin/size/pivot in
source-image pixels, so pieces reassemble exactly as they were cut. A bone
hierarchy (BONES) matching the game's scheme parents the pieces; animations
keyframe the bones with real easing/overlap that the in-engine snap-tweens lack.
Unlit emission materials keep the flat inked cartoon look (no 3D shading).
"""
import json
import math
import os
import sys

import bpy
import mathutils

SCALE = 0.01           # 1 source pixel -> 0.01 Blender units
Z_ORDER = ["foot_l", "foot_r", "shin_l", "shin_r", "thigh_l", "thigh_r",
           "hips", "torso", "uarm_l", "uarm_r", "farm_l", "farm_r",
           "hand_l", "hand_r", "head"]

# Bone hierarchy: name -> (parent, part-that-defines-its-joint). The joint is the
# part's pivot; the bone head sits there. Root "Hip" is parented to nothing.
BONES = [
    ("Hip", None, "hips"),
    ("Spine", "Hip", "torso"),
    ("Head", "Spine", "head"),
    ("ArmL", "Spine", "uarm_l"), ("ForearmL", "ArmL", "farm_l"), ("HandL", "ForearmL", "hand_l"),
    ("ArmR", "Spine", "uarm_r"), ("ForearmR", "ArmR", "farm_r"), ("HandR", "ForearmR", "hand_r"),
    ("ThighL", "Hip", "thigh_l"), ("ShinL", "ThighL", "shin_l"), ("FootL", "ShinL", "foot_l"),
    ("ThighR", "Hip", "thigh_r"), ("ShinR", "ThighR", "shin_r"), ("FootR", "ShinR", "foot_r"),
]
# which parts hang off which bone (a bone drives its own part + is joint-owner)
PART_BONE = {
    "hips": "Hip", "torso": "Spine", "head": "Head",
    "uarm_l": "ArmL", "farm_l": "ForearmL", "hand_l": "HandL",
    "uarm_r": "ArmR", "farm_r": "ForearmR", "hand_r": "HandR",
    "thigh_l": "ThighL", "shin_l": "ShinL", "foot_l": "FootL",
    "thigh_r": "ThighR", "shin_r": "ShinR", "foot_r": "FootR",
}


def px_to_world(x, y, cw, ch):
    """Source-image pixel (top-left origin, y-down) -> centered Blender XY."""
    return ((x - cw / 2.0) * SCALE, -(y - ch / 2.0) * SCALE)


def make_plane(name, part, tex_path, cw, ch, zi):
    ox, oy = part["origin"]; w, h = part["size"]
    cx, cy = px_to_world(ox + w / 2.0, oy + h / 2.0, cw, ch)
    bpy.ops.mesh.primitive_plane_add(size=1)
    o = bpy.context.active_object
    o.name = name
    o.scale = (w * SCALE, h * SCALE, 1)
    o.location = (cx, cy, zi * 0.01)
    bpy.ops.object.transform_apply(scale=True)
    # unlit material: image emission, alpha-blended
    mat = bpy.data.materials.new(name + "_m"); mat.use_nodes = True
    mat.blend_method = 'BLEND'
    nt = mat.node_tree; nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(tex_path)
    tex.interpolation = 'Closest'
    emis = nt.nodes.new("ShaderNodeEmission")
    trans = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], emis.inputs["Color"])
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
    nt.links.new(trans.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emis.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    o.data.materials.append(mat)
    return o


def build(parts_dir, cw, ch):
    parts = json.load(open(os.path.join(parts_dir, "parts.json")))
    planes = {}
    for zi, key in enumerate(Z_ORDER):
        if key not in parts:
            continue
        p = os.path.join(parts_dir, key + ".png")
        if not os.path.exists(p):
            continue
        planes[key] = make_plane("part_" + key, parts[key], p, cw, ch, zi)
    return parts, planes


def build_armature(parts, planes, cw, ch):
    bpy.ops.object.armature_add(enter_editmode=True)
    arm = bpy.context.active_object
    arm.name = "Rig"
    eb = arm.data.edit_bones
    eb.remove(eb[0])                         # drop the default bone
    made = {}
    for name, parent, part_key in BONES:
        if part_key not in parts:
            continue
        px, py = parts[part_key]["pivot"]
        hx, hy = px_to_world(px, py, cw, ch)
        b = eb.new(name)
        b.head = (hx, hy, 0)
        b.tail = (hx, hy + 0.3, 0)           # short bone pointing +Y
        if parent and parent in made:
            b.parent = made[parent]
        made[name] = b
    bpy.ops.object.mode_set(mode='OBJECT')
    # parent each plane to its bone, keeping transform
    for part_key, bone_name in PART_BONE.items():
        if part_key not in planes or bone_name not in [b[0] for b in BONES]:
            continue
        pl = planes[part_key]
        pl.parent = arm
        pl.parent_type = 'BONE'
        pl.parent_bone = bone_name
        pl.matrix_parent_inverse = (arm.matrix_world @ arm.pose.bones[bone_name].matrix).inverted()
    return arm


def setup_render(out_path, cw, ch):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    # Frame is as WIDE as it is tall (figure centred at world origin) so limbs
    # that splay horizontally on a collapse/sprawl have room whatever the body
    # width. play_anim scales by height and centres on x, so the extra side
    # margin is free. Height ~720 keeps per-frame weight down.
    sc.render.resolution_y = 720
    sc.render.resolution_x = 720
    cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (0, 0, 10); cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ch * SCALE * 1.12          # square view = ch wide too
    sc.render.filepath = out_path


D = math.radians

# KO COLLAPSE — cartoon knock-out: hit recoil (anticipation) -> knees buckle ->
# topple back -> sprawl on the floor -> settle. Keys are (frame, poses) where
# poses maps a bone to its local-Z rotation in degrees; "_loc"/"_rot"/"_sq" drive
# the root Hip translation, whole-body topple, and squash/stretch. Blender's
# bezier interpolation between keys supplies the easing, overlap and follow-through
# the in-engine snap-tweens can't.
# NB: 2D-cutout limbs disconnect if a joint over-rotates past the pieces' overlap
# (bad on thin characters). Keep arms <=~30 deg, forearms <=~30, thighs <=~40,
# shins <=~55. The COLLAPSE reads from the body: Hip sinking, spine curl, head
# loll, and squash - not from flinging the limbs.
KO = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    # anticipation: small snap back, head tips, arms lift a touch (stretch up)
    (3,  {"Head": 14, "Spine": -8, "ArmL": 22, "ArmR": -24, "ForearmL": 14, "ForearmR": -14},
         (0, 0.12), -4, (0.97, 1.05)),
    # knees give out, body folds forward and drops straight down
    (8,  {"Head": 22, "Spine": 15, "ArmL": -16, "ArmR": 18, "ForearmL": -18, "ForearmR": 20,
          "ThighL": 34, "ThighR": -36, "ShinL": -52, "ShinR": 54},
         (0, -1.25), -12, (1.05, 0.9)),
    # hits the floor: hard squash, knees folded under, head drops, arms flop in
    (13, {"Head": 40, "Spine": 22, "ArmL": -26, "ArmR": 28, "ForearmL": -26, "ForearmR": 28,
          "ThighL": 42, "ThighR": -44, "ShinL": -56, "ShinR": 58, "FootL": -16, "FootR": 18},
         (0, -2.2), -18, (1.15, 0.8)),
    # rebound overshoot (follow-through: body springs up a touch, head lags)
    (17, {"Head": 34, "Spine": 18, "ArmL": -22, "ArmR": 24, "ForearmL": -20, "ForearmR": 22,
          "ThighL": 40, "ThighR": -42, "ShinL": -54, "ShinR": 56},
         (0, -2.0), -16, (0.96, 1.05)),
    # settle: crumpled on the floor, come to rest
    (22, {"Head": 38, "Spine": 20, "ArmL": -24, "ArmR": 26, "ForearmL": -23, "ForearmR": 25,
          "ThighL": 41, "ThighR": -43, "ShinL": -55, "ShinR": 57, "FootL": -15, "FootR": 17},
         (0, -2.12), -17, (1.0, 1.0)),
]


def key_pose(arm, frame, poses, loc, rot, sq):
    bpy.context.scene.frame_set(frame)
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
    for bone, deg in poses.items():
        if bone in arm.pose.bones:
            pb = arm.pose.bones[bone]
            pb.rotation_euler = (0, 0, D(deg))
            pb.keyframe_insert("rotation_euler", frame=frame)
    hip = arm.pose.bones.get("Hip")
    if hip:
        hip.location = (loc[0], loc[1], 0)
        hip.rotation_euler = (0, 0, D(rot))
        hip.keyframe_insert("location", frame=frame)
        hip.keyframe_insert("rotation_euler", frame=frame)
    arm.scale = (sq[0], sq[1], 1)
    arm.keyframe_insert("scale", frame=frame)


def animate(arm, table):
    # ensure every posed bone has a key at frame 1 too (clean rest start)
    all_bones = set()
    for _, poses, _, _, _ in table:
        all_bones |= set(poses.keys())
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
    for frame, poses, loc, rot, sq in table:
        full = {b: poses.get(b, 0) for b in all_bones}
        key_pose(arm, frame, full, loc, rot, sq)
    # Inserted keyframes default to BEZIER interpolation, so easing/overlap comes
    # for free. (Blender 5.x moved Action.fcurves under slotted actions; touching
    # them explicitly isn't needed here.)
    return table[-1][0]


ANIMS = {"ko": KO}


def render_seq(out_dir, last_frame):
    sc = bpy.context.scene
    n = 0
    for f in range(1, last_frame + 1):
        sc.frame_set(f)
        sc.render.filepath = os.path.join(out_dir, "f%03d" % n)
        bpy.ops.render.render(write_still=True)
        n += 1
    return n


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    parts_dir, out_dir, anim = argv[0], argv[1], argv[2]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = json.load(open(os.path.join(parts_dir, "parts.json")))
    cw = max(v["origin"][0] + v["size"][0] for v in parts.values())
    ch = max(v["origin"][1] + v["size"][1] for v in parts.values())
    parts, planes = build(parts_dir, cw, ch)
    arm = build_armature(parts, planes, cw, ch)
    os.makedirs(out_dir, exist_ok=True)
    setup_render(os.path.join(out_dir, "f"), cw, ch)
    if anim == "tpose":
        bpy.context.scene.render.filepath = os.path.join(out_dir, "tpose")
        bpy.ops.render.render(write_still=True)
        print("TPOSE_OK canvas=%dx%d parts=%d bones=%d" % (cw, ch, len(planes), len(arm.pose.bones)))
        return
    if anim in ANIMS:
        last = animate(arm, ANIMS[anim])
        n = render_seq(out_dir, last)
        print("ANIM_OK %s frames=%d canvas=%dx%d" % (anim, n, cw, ch))
        return
    print("anim '%s' not defined" % anim)


if __name__ == "__main__":
    main()
