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
# 2D-cutout limbs disconnect if a joint over-rotates past the pieces' overlap -
# and thin characters have almost none. So the collapse is driven by the ROOT
# and TORSO: the Hip sinks and pitches forward, the spine folds at the waist, the
# head lolls, and a squash sells the impact. Limbs stay within tiny, safe angles
# (<=~18 deg) so nothing detaches on any character.
KO = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    # anticipation: brief snap back, head tips, arms lift a hair
    (3,  {"Head": 12, "Spine": -7, "ArmL": 12, "ArmR": -13, "ForearmL": 8, "ForearmR": -8},
         (0, 0.1), 5, (0.97, 1.05)),
    # knees give, whole body pitches forward and drops
    (8,  {"Head": 20, "Spine": 16, "ArmL": -8, "ArmR": 9, "ForearmL": -10, "ForearmR": 11,
          "ThighL": 18, "ThighR": -19, "ShinL": -26, "ShinR": 27},
         (0, -1.15), -16, (1.05, 0.9)),
    # hits the floor: hard squash, folded forward over the knees, head hangs
    (13, {"Head": 34, "Spine": 26, "ArmL": -14, "ArmR": 15, "ForearmL": -16, "ForearmR": 17,
          "ThighL": 24, "ThighR": -25, "ShinL": -34, "ShinR": 35, "FootL": -10, "FootR": 11},
         (0, -2.05), -30, (1.16, 0.8)),
    # rebound overshoot (body springs a touch, head lags behind)
    (17, {"Head": 30, "Spine": 22, "ArmL": -11, "ArmR": 12, "ForearmL": -12, "ForearmR": 13,
          "ThighL": 22, "ThighR": -23, "ShinL": -32, "ShinR": 33},
         (0, -1.9), -27, (0.96, 1.05)),
    # settle: crumpled forward on the floor, at rest
    (22, {"Head": 32, "Spine": 24, "ArmL": -12, "ArmR": 13, "ForearmL": -14, "ForearmR": 15,
          "ThighL": 23, "ThighR": -24, "ShinL": -33, "ShinR": 34, "FootL": -9, "FootR": 10},
         (0, -2.0), -28, (1.0, 1.0)),
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


# GET-BACK-UP — the reverse of the collapse, with a groggy wobble: starts
# crumpled forward on the floor, gathers, pushes up through the hips, overshoots
# a touch, shakes it off, stands. Same root/torso-driven, limb-safe approach.
GET_UP = [
    # crumpled on the floor (matches the KO settle pose)
    (1,  {"Head": 32, "Spine": 24, "ArmL": -12, "ArmR": 13, "ForearmL": -14, "ForearmR": 15,
          "ThighL": 23, "ThighR": -24, "ShinL": -33, "ShinR": 34},
         (0, -2.0), -28, (1.0, 1.0)),
    # gather: head lifts, weight shifts, a beat of anticipation
    (5,  {"Head": 20, "Spine": 22, "ArmL": -16, "ArmR": 17, "ForearmL": -20, "ForearmR": 21,
          "ThighL": 26, "ThighR": -27, "ShinL": -36, "ShinR": 37},
         (0, -1.9), -24, (1.02, 0.98)),
    # push up through the hips, legs extend
    (11, {"Head": 8, "Spine": 8, "ArmL": -8, "ArmR": 9, "ForearmL": -8, "ForearmR": 9,
          "ThighL": 12, "ThighR": -13, "ShinL": -16, "ShinR": 17},
         (0, -0.7), -8, (0.98, 1.04)),
    # nearly up, groggy overshoot (stretch up, sways back)
    (15, {"Head": -8, "Spine": -6, "ArmL": -3, "ArmR": 3},
         (0, 0.12), 4, (0.96, 1.07)),
    # shake it off - quick head wobble
    (18, {"Head": 12, "Spine": 3, "ArmL": -4, "ArmR": 5}, (0, 0.02), -2, (1.01, 1.0)),
    # settle, standing
    (22, {}, (0, 0), 0, (1.0, 1.0)),
]

# All body/torso-driven, limbs kept within safe overlap angles so nothing detaches
# on thin characters. Each list: (frame, {bone:deg}, hip_loc, hip_rot_deg, squash).

# HAYMAKER — a loaded, leaning wind-up and swing. The POWER comes from the body
# coiling and uncoiling (Hip twist + spine), not a windmilling arm (which would
# shred). Right arm cocks and throws within a safe cap.
HAYMAKER = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (5,  {"Spine": -12, "Head": -8, "ArmR": -26, "ForearmR": -14, "ArmL": 10},
         (0, 0.05), 10, (0.98, 1.04)),                       # load back, coil
    (8,  {"Spine": -16, "Head": -10, "ArmR": -30, "ForearmR": -16, "ArmL": 14},
         (0, 0.02), 13, (0.97, 1.05)),                       # peak coil (anticipation hold)
    (11, {"Spine": 20, "Head": 14, "ArmR": 26, "ForearmR": 18, "ArmL": -14},
         (0, -0.05), -14, (1.08, 0.93)),                     # SWING through, squash
    (14, {"Spine": 14, "Head": 10, "ArmR": 20, "ForearmR": 12, "ArmL": -8},
         (0, 0), -9, (1.0, 1.0)),                            # follow-through
    (19, {}, (0, 0), 0, (1.0, 1.0)),                         # recover
]

# DODGE WEAVE — bob and weave, ducking side to side. Pure body/head motion.
DODGE_WEAVE = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (5,  {"Spine": -8, "Head": -10, "ThighL": 8, "ThighR": 8}, (-0.5, -0.55), -9, (1.03, 0.98)),  # weave left+duck
    (10, {"Head": 4}, (0, -0.35), 0, (1.02, 0.99)),          # low centre
    (14, {"Spine": 8, "Head": 10, "ThighL": -8, "ThighR": -8}, (0.5, -0.55), 9, (1.03, 0.98)),    # weave right+duck
    (19, {}, (0, 0), 0, (1.0, 1.0)),                         # back to guard
]

# STAGGER — reel back onto the ropes and wobble. Body-driven whip.
STAGGER = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (3,  {"Head": 22, "Spine": -16, "ArmL": 14, "ArmR": -15}, (0, 0.15), -12, (0.96, 1.06)),  # snap back
    (7,  {"Head": 16, "Spine": -20, "ArmL": 10, "ArmR": -11}, (0, 0.1), -15, (0.97, 1.05)),   # on the ropes
    (11, {"Head": -8, "Spine": 10, "ArmL": -6, "ArmR": 6}, (0, -0.05), 8, (1.03, 0.98)),      # wobble forward
    (15, {"Head": 8, "Spine": -8}, (0, 0.05), -6, (1.0, 1.0)),                                # wobble back
    (19, {}, (0, 0), 0, (1.0, 1.0)),                         # recover
]

# SHAKE IT OFF — comeback: shakes the head clear, squares up. Head + torso.
SHAKE_IT_OFF = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (4,  {"Head": -16, "Spine": 3}, (0, 0), -3, (1.0, 1.0)),   # shake left
    (7,  {"Head": 16, "Spine": -3}, (0, 0), 3, (1.0, 1.0)),    # shake right
    (10, {"Head": -12, "Spine": 2}, (0, 0), -2, (1.0, 1.0)),   # shake left
    (13, {"Head": 6, "Spine": -6, "ArmL": -8, "ArmR": 8}, (0, 0.12), 0, (0.97, 1.05)),  # shrug up, stretch
    (18, {}, (0, 0), 0, (1.0, 1.0)),                          # ready
]

# VICTORY — bouncy celebration hops with capped arm pumps.
VICTORY = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (4,  {"ThighL": 6, "ThighR": -6}, (0, -0.35), 0, (1.05, 0.9)),   # crouch (anticipation)
    (7,  {"ArmL": 20, "ArmR": -22, "ForearmL": 16, "ForearmR": -16, "Head": -6}, (0, 0.55), 0, (0.95, 1.08)),  # jump + pump up
    (10, {"ThighL": 6, "ThighR": -6}, (0, -0.2), 0, (1.06, 0.9)),    # land, squash
    (13, {"ArmL": 20, "ArmR": -22, "ForearmL": 16, "ForearmR": -16, "Head": -6}, (0, 0.5), 0, (0.95, 1.07)),   # pump again
    (16, {"Spine": 10, "Head": 8}, (0, -0.05), 0, (1.0, 1.0)),       # gloat lean
    (20, {}, (0, 0), 0, (1.0, 1.0)),
]

# TAUNT — lean in, beckon with a capped gesture, smug lean back.
TAUNT = [
    (1,  {}, (0, 0), 0, (1.0, 1.0)),
    (5,  {"Spine": 12, "Head": 8, "ArmR": 22, "ForearmR": 20}, (0, -0.05), 0, (1.02, 0.99)),  # lean in + beckon
    (9,  {"Spine": 12, "Head": 8, "ArmR": 14, "ForearmR": 10}, (0, -0.05), 0, (1.02, 0.99)),  # beckon return
    (13, {"Spine": -8, "Head": -6, "ArmL": 8}, (0, 0.05), 0, (0.99, 1.02)),                   # smug lean back
    (18, {}, (0, 0), 0, (1.0, 1.0)),
]

# ENTRANCE WALK — a walk-in-place cycle (legs alternate, arms swing, body bob).
# Loopable; the game can translate the boss across screen while it plays.
ENTRANCE = [
    (1,  {"ThighL": 18, "ThighR": -16, "ShinL": -10, "ShinR": 18, "ArmL": -12, "ArmR": 12}, (0, -0.05), 0, (1.0, 1.0)),
    (5,  {"ThighL": 2, "ThighR": 0, "ShinL": -4, "ShinR": 2, "ArmL": 0, "ArmR": 0}, (0, 0.06), 0, (1.0, 1.0)),
    (9,  {"ThighL": -16, "ThighR": 18, "ShinL": 18, "ShinR": -10, "ArmL": 12, "ArmR": -12}, (0, -0.05), 0, (1.0, 1.0)),
    (13, {"ThighL": 0, "ThighR": 2, "ShinL": 2, "ShinR": -4, "ArmL": 0, "ArmR": 0}, (0, 0.06), 0, (1.0, 1.0)),
    (16, {"ThighL": 18, "ThighR": -16, "ShinL": -10, "ShinR": 18, "ArmL": -12, "ArmR": 12}, (0, -0.05), 0, (1.0, 1.0)),
]

ANIMS = {
    "ko": KO, "getup": GET_UP, "haymaker": HAYMAKER, "dodge_weave": DODGE_WEAVE,
    "stagger": STAGGER, "shake_it_off": SHAKE_IT_OFF, "victory": VICTORY,
    "taunt": TAUNT, "entrance": ENTRANCE,
}


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

    # "all" (or a comma list) renders many animations in ONE invocation - the rig
    # is assembled once, then each anim clears the previous action and renders to
    # its own <out_dir>/<name>/ subfolder. Big speedup vs one Blender start per anim.
    names = list(ANIMS.keys()) if anim == "all" else [a for a in anim.split(",") if a in ANIMS]
    for name in names:
        arm.animation_data_clear()
        for pb in arm.pose.bones:
            pb.rotation_mode = 'XYZ'
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        arm.scale = (1, 1, 1)
        sub = os.path.join(out_dir, name)
        os.makedirs(sub, exist_ok=True)
        last = animate(arm, ANIMS[name])
        n = render_seq(sub, last)
        print("ANIM_OK %s frames=%d canvas=%dx%d" % (name, n, cw, ch))
    if not names:
        print("anim '%s' not defined" % anim)


if __name__ == "__main__":
    main()
