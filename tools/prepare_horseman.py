"""Build the Quaternius mounted warrior and share rider construction helpers."""

from array import array
from math import cos, pi, sin, tau
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mounted_rider_motion import SHIELD, add_controls, bake_rider, position_rider_shield, rider_joint, solve_limb
from mounted_archery_motion import author_archery

ROOT = Path(__file__).resolve().parents[1]
HORSE_SCALE = .395
SEAT = Vector((0, -.24, 3.64))
SADDLE_BONE = "SaddleSocket"
RIDER_BONE = "RiderRoot"
SPEAR_BONE = "SpearRoot"


def use_action(rig, action):
    rig.animation_data.action = action
    if action and action.slots:
        rig.animation_data.action_slot = action.slots[0]


def reset_pose(rig):
    if rig.animation_data:
        use_action(rig, None)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def make_clips(rig):
    source = {name: bpy.data.actions[name] for name in ("Idle", "Walk", "Gallop", "Death")}
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    reset_pose(rig)
    for action in list(bpy.data.actions):
        if action not in source.values():
            bpy.data.actions.remove(action)

    body = rig.pose.bones["Body"]
    feet = [rig.pose.bones[name] for name in
            ("IKFrontLeg.L", "IKBackLeg.R", "IKFrontLeg.R", "IKBackLeg.L")]
    body_rest = body.bone.matrix_local.copy()
    foot_rests = [foot.bone.matrix_local.copy() for foot in feet]
    scene = bpy.context.scene

    def key_pose(bone, matrix, frame):
        bone.rotation_mode = 'QUATERNION'
        bone.matrix = matrix
        for prop in ("location", "rotation_quaternion"):
            bone.keyframe_insert(data_path=prop, frame=frame, group=bone.name)

    trot = bpy.data.actions.new("Trot")
    use_action(rig, trot)
    for frame in range(25):
        phase = frame / 24
        bob = -.11 * cos(2 * tau * (phase - .16))
        pitch = .037 * sin(2 * tau * phase)
        key_pose(body, Matrix.Translation((0, 0, bob)) @ body_rest
                 @ Matrix.Rotation(pitch, 4, 'X'), frame)
        for index, (foot, rest) in enumerate(zip(feet, foot_rests)):
            step = (phase + (.5 if index >= 2 else 0)) % 1
            if step < .43:
                travel, lift = -.76 + 1.52 * step / .43, 0
            else:
                swing = (step - .43) / .57
                travel = .76 * cos(pi * swing)
                lift = (.56 if index % 2 == 0 else .46) * sin(pi * swing)
            key_pose(foot, Matrix.Translation((0, travel, lift)) @ rest, frame)

    reset_pose(rig)
    rear = bpy.data.actions.new("Rear")
    use_action(rig, rear)
    pivot = Vector((0, 1.72, .04))
    for frame, angle, crouch, tuck in (
        (0, 0, 0, 0), (7, 6, -.20, 0), (17, 53, .03, 1),
        (24, 55, .01, .86), (33, 28, -.04, .63),
        (41, 0, -.16, 0), (48, 0, 0, 0),
    ):
        pitch = Matrix.Rotation(-angle * pi / 180, 4, 'X')
        around_haunches = Matrix.Translation(pivot) @ pitch @ Matrix.Translation(-pivot)
        key_pose(body, Matrix.Translation((0, 0, crouch)) @ around_haunches @ body_rest, frame)
        for index, (foot, rest) in enumerate(zip(feet, foot_rests)):
            matrix = rest
            if index % 2 == 0:
                offset = (0, .87 * tuck, (.22 if index == 0 else .08) * tuck)
                matrix = Matrix.Translation(offset) @ around_haunches @ rest
            key_pose(foot, matrix, frame)

    for action in [*source.values(), trot, rear]:
        action.use_fake_user = True
    reset_pose(rig)
    scene.frame_set(0)


def material(name, color, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = mat.diffuse_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = .82 if not metallic else .46
    return mat


def bind_mesh(obj, rig, bone):
    obj.parent = rig
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    obj.modifiers.new("Mount", 'ARMATURE').object = rig


def saddle_pad(rig, cloth, border):
    profile = [(-.69, 3.52, .59), (-.36, 3.43, .62), (.05, 3.46, .63), (.55, 3.60, .57)]
    sections = [(-1, -.53), (-.9, -.24), (-.61, -.025),
                (0, .055), (.61, -.025), (.9, -.24), (1, -.53)]
    vertices = [(x * width, y, z + drop) for y, z, width in profile for x, drop in sections]
    stride = len(sections)
    faces = [(i, i + 1, i + stride + 1, i + stride)
             for i in range(stride * (len(profile) - 1)) if i % stride != stride - 1]
    mesh = bpy.data.meshes.new("Saddlecloth")
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new("Saddlecloth", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(cloth)
    mesh.materials.append(border)
    thickness = obj.modifiers.new("Wool edge", 'SOLIDIFY')
    thickness.thickness = .035
    thickness.material_offset_rim = 1
    bind_mesh(obj, rig, "Torso2")


def ellipsoid(rig, name, center, radius, mat, bone):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8)
    obj = bpy.context.object
    obj.name = name
    for vertex in obj.data.vertices:
        vertex.co = Vector(center) + Vector(v * r for v, r in zip(vertex.co, radius))
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bind_mesh(obj, rig, bone)


def strap(rig, name, points, radius, mat, bone):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    curve.use_fill_caps = True
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for point, xyz in zip(spline.points, points):
        point.co = (*xyz, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    obj.data.materials.append(mat)
    bind_mesh(obj, rig, bone)
    return obj


def make_tack(rig, contacts):
    cloth = material("Indigo wool", (.025, .066, .115))
    brass = material("Patinated bronze", (.31, .17, .052), .7)
    leather = material("Dark saddle leather", (.058, .026, .012))
    saddle_pad(rig, cloth, brass)
    ellipsoid(rig, "Saddle seat", (0, -.22, 3.47), (.37, .68, .155), leather, "Torso2")
    ellipsoid(rig, "Cantle", (0, .37, 3.61), (.39, .16, .20), leather, "Torso2")
    ellipsoid(rig, "Pommel", (0, -.74, 3.61), (.32, .16, .18), leather, "Torso2")
    for name, side in (("Right", -1), ("Left", 1)):
        ankle = contacts[name + "Foot"]
        toe = contacts[name + "ToeBase"]
        x = toe.x
        y = toe.y * .70 + ankle.y * .30
        z = min(toe.z, ankle.z) - .075
        top = (x, y, z + .40)
        strap(rig, "Stirrup leather", [(.37 * side, y, 3.47),
              (.56 * side, y, 3.11), top], .031, leather, "Torso2")
        strap(rig, "Stirrup", [top, (x, y - .19, z + .24), (x, y - .21, z),
              (x, y + .17, z), (x, y + .17, z + .24), top], .028, brass, "Torso2")
        strap(rig, "Bridle cheekpiece", [(.225 * side, -2.57, 4.25),
              (.29 * side, -2.74, 3.96), (.34 * side, -3.16, 3.72)], .034, leather, "Head")
    strap(rig, "Noseband", [(-.34, -3.16, 3.72), (-.24, -3.26, 3.88),
          (0, -3.29, 3.93), (.24, -3.26, 3.88), (.34, -3.16, 3.72)], .035, leather, "Head")


def make_rider(horse, seat=SEAT, wide_stance=False, contacts=None, animate=False, rider_source=None):
    with bpy.data.libraries.load(str(ROOT / "art/warrior.blend"), link=False) as (_, dst):
        dst.objects = ["WarriorRig", "WarriorBody", "spear"] + (["shield"] if animate else [])
    rig, body, spear = dst.objects[:3]
    for obj in dst.objects:
        bpy.context.collection.objects.link(obj)
    imported = set()
    if rider_source:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(rider_source))
        imported = set(bpy.data.objects) - before
        bpy.data.objects.remove(body, do_unlink=True)
        bpy.data.objects.remove(rig, do_unlink=True)
        rig = next(obj for obj in imported if obj.type == "ARMATURE")
        body = next(obj for obj in imported if obj.type == "MESH" and
                    any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in obj.modifiers))
    rig.animation_data_clear()
    spear.constraints.clear()
    reset_pose(rig)

    def bone(name):
        return rig.pose.bones["mixamorig:" + name]

    def aim(name, direction):
        pb = bone(name)
        current = pb.matrix.to_quaternion()
        rotation = (current @ Vector((0, 1, 0))).rotation_difference(Vector(direction).normalized())
        matrix = (rotation @ current).to_matrix().to_4x4()
        matrix.translation = pb.head
        pb.matrix = matrix
        bpy.context.view_layer.update()

    aim("Spine", (0, -.11, 1))
    for side, sign in (("Left", 1), ("Right", -1)):
        aim(side + "UpLeg", (sign * .72, -.37, -.59) if wide_stance
            else (sign * .54, -.36, -.76))
        aim(side + "Leg", (sign * .11, .39, -.91) if wide_stance
            else (sign * -.04, .44, -.90))
        aim(side + "Foot", (0, -1, -.12))
        aim(side + "ToeBase", (0, -1, 0))
        aim(side + "Arm", (sign * .39, .15 if sign < 0 else -.16, -1))
        aim(side + "ForeArm", (sign * -.21, -1, .36 if sign < 0 else -.06))
        aim(side + "Hand", (sign * -.14, -1, -.08))

    if animate and not rider_source:
        hand = bone("RightHand")
        curl_reference = hand.bone.matrix_local.to_quaternion() @ Vector((1, 0, 0))
        for digit in ("Index", "Middle", "Ring", "Pinky"):
            for joint in (1, 2, 3):
                finger = bone(f"RightHand{digit}{joint}")
                axis = finger.bone.matrix_local.to_quaternion().inverted() @ curl_reference
                finger.rotation_mode = "QUATERNION"
                finger.rotation_quaternion = Quaternion(axis, 1.04)
        bpy.context.view_layer.update()
    fit = .95 / HORSE_SCALE
    origin = seat - (rig.matrix_world @ bone("Hips").head) * fit
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    body_mesh = bpy.data.meshes.new_from_object(evaluated)
    body_mesh.transform(Matrix.Translation(origin) @ Matrix.Scale(fit, 4) @ body.matrix_world)
    rider = bpy.data.objects.new("Mounted warrior", body_mesh)
    bpy.context.collection.objects.link(rider)
    bind_mesh(rider, horse, RIDER_BONE)

    socket = bone("RightHand").matrix @ Vector((-.002, .044, .024)) if animate else rig.pose.bones["GripRight"].head
    grip = origin + (rig.matrix_world @ socket) * fit
    if contacts is not None:
        names = ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftHand")
        if animate:
            names = ("Spine1", "Neck") + tuple(
                side + part for side in ("Left", "Right")
                for part in ("UpLeg", "Leg", "Foot", "ToeBase", "Arm", "ForeArm", "Hand")
            )
        for name in names:
            contacts[name] = origin + (rig.matrix_world @ bone(name).head) * fit
    if animate:
        fingers = {}
        if rider_source:
            hand_matrix = rig.matrix_world @ bone("RightHand").matrix
            contacts["RightPalmCurlAxis"] = hand_matrix.to_quaternion() @ Vector((1, 0, 0))
            for digit in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
                parent = rider_joint("Right", "Hand")
                for joint in range(1, 4):
                    finger = bone(f"RightHand{digit}{joint}")
                    matrix = rig.matrix_world @ finger.matrix
                    matrix.translation = origin + matrix.translation * fit
                    fingers[finger.name] = (parent, matrix)
                    parent = finger.name
        add_controls(horse, rider, body, contacts, fingers)
        shield = dst.objects[3]
        shield.constraints.clear()
        shield.matrix_basis = Matrix.Identity(4)
        shield.data = shield.data.copy()
        wrist = contacts["LeftHand"]
        shield.data.transform(Matrix.Translation(wrist) @ Matrix.Rotation(1.12, 4, "Z")
                              @ Matrix.Translation((0, -.22, -.20))
                              @ Matrix.Scale(.94 / HORSE_SCALE, 4))
        shield.name = "Rider shield"
        bind_mesh(shield, horse, SHIELD)
    spear.data = spear.data.copy()
    spear.data.transform(Matrix.Translation(grip) @ Matrix.Rotation(.21, 4, 'X')
                         @ Matrix.Scale(.90 / HORSE_SCALE, 4))
    spear.name = "Rider spear"
    bind_mesh(spear, horse, SPEAR_BONE)

    if rider_source:
        for obj in imported:
            bpy.data.objects.remove(obj, do_unlink=True)
    else:
        bpy.data.objects.remove(body, do_unlink=True)
        bpy.data.objects.remove(rig, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.name not in ("Idle", "Walk", "Trot", "Gallop", "Death", "Rear"):
            bpy.data.actions.remove(action)
    return rider, spear, grip


def make_fall(rig, rider, points, action, destination, pitch, roll, turn, leg_asymmetry):
    """Send the rider clear of the horse and extend the legs into a ground pose."""
    scene = bpy.context.scene
    use_action(rig, action)
    pelvis = rig.pose.bones[RIDER_BONE]
    rest = pelvis.bone.matrix_local.copy()
    settled = Matrix.Translation(destination) @ Matrix.Rotation(turn, 4, "Z")
    settled @= Matrix.Rotation(roll, 4, "Y") @ Matrix.Rotation(pitch, 4, "X")
    settled @= Matrix.Translation(-SEAT)
    motions = {}
    for side, sign in (("Left", 1), ("Right", -1)):
        thigh, knee, ankle = (points[side + name] for name in ("UpLeg", "Leg", "Foot"))
        span = (knee - thigh).length + (ankle - knee).length
        foot_target = thigh + Vector((sign * .17, .12 + sign * leg_asymmetry, -span * (.92 if sign > 0 else .85)))
        upper, lower, foot = solve_limb(thigh, knee, ankle, thigh, foot_target)
        motions[rider_joint(side, "UpLeg")] = upper
        motions[rider_joint(side, "Leg")] = lower
        motions[rider_joint(side, "Foot")] = Matrix.Translation(foot - ankle)
        shoulder, elbow, hand = (points[side + name] for name in ("Arm", "ForeArm", "Hand"))
        hand_target = shoulder + Vector((sign * (.64 if sign > 0 else .44), -.24, -.87 if sign > 0 else -.70))
        upper, lower, palm = solve_limb(shoulder, elbow, hand, shoulder, hand_target)
        motions[rider_joint(side, "Arm")] = upper
        motions[rider_joint(side, "ForeArm")] = lower
        motions[rider_joint(side, "Hand")] = Matrix.Translation(palm - hand)
    limbs = [bone for bone in rig.pose.bones if bone.name in motions]
    previous = {}

    for frame in range(31):
        scene.frame_set(frame)
        pelvis.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        progress = max(0.0, min((frame - 4) / 24, 1.0))
        blend = progress * progress * (3 - 2 * progress)
        pelvis.matrix = pelvis.matrix.lerp(settled @ rest, blend)
        bpy.context.view_layer.update()
        offset = pelvis.matrix @ rest.inverted()
        for bone in limbs:
            local = Matrix.Identity(4).lerp(motions[bone.name], blend)
            bone.matrix = offset @ local @ bone.bone.matrix_local
            bpy.context.view_layer.update()
        if blend > 0:
            evaluated = rider.evaluated_get(bpy.context.evaluated_depsgraph_get())
            lowest = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)
            if lowest < .045 or progress > .85:
                pelvis.location += pelvis.parent.matrix.to_3x3().inverted() @ Vector((0, 0, .045 - lowest))
                bpy.context.view_layer.update()
        for bone in [pelvis, *limbs]:
            quaternion = bone.rotation_quaternion.copy()
            if bone.name in previous and quaternion.dot(previous[bone.name]) < 0:
                quaternion.negate()
                bone.rotation_quaternion = quaternion
            previous[bone.name] = quaternion
            for prop in ("location", "rotation_quaternion"):
                bone.keyframe_insert(data_path=prop, frame=frame, group=bone.name)
    reset_pose(rig)


def apply_horse_coat(horse):
    with bpy.data.libraries.load(str(ROOT / "art/horse_coat.blend"), link=False) as (_, dst):
        dst.objects = ["Horse_Low"]
    low = dst.objects[0]
    baked = low.data
    original = horse.data
    count = len(original.loops)
    source_order = array('i', [0]) * len(baked.loops)
    game_order = array('i', [0]) * count
    baked.loops.foreach_get("vertex_index", source_order)
    original.loops.foreach_get("vertex_index", game_order)
    if source_order != game_order:
        raise RuntimeError("Horse coat UVs do not match the game mesh")

    uv = original.uv_layers.new(name=baked.uv_layers.active.name)
    coords = array('f', [0]) * (count * 2)
    baked.uv_layers.active.uv.foreach_get("vector", coords)
    uv.uv.foreach_set("vector", coords)
    original.materials.clear()
    original.materials.append(baked.materials[0])
    for polygon in original.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
    bpy.data.objects.remove(low)
    bpy.data.meshes.remove(baked)


def main(khazar=False):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "art/source/horse/Horse.blend"))
    rig = bpy.data.objects["AnimalArmature"]
    horse = bpy.data.objects["Horse"]
    horse.data.validate()
    apply_horse_coat(horse)
    make_clips(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    saddle = rig.data.edit_bones.new(SADDLE_BONE)
    saddle.parent = rig.data.edit_bones["Torso2"]
    saddle.head = SEAT
    saddle.tail = SEAT + Vector((0, 0, .4))
    rider_root = rig.data.edit_bones.new(RIDER_BONE)
    rider_root.parent = saddle
    rider_root.head = SEAT
    rider_root.tail = saddle.tail
    spear_root = rig.data.edit_bones.new(SPEAR_BONE)
    spear_root.parent = rider_root
    spear_root.head = SEAT
    spear_root.tail = saddle.tail
    bpy.ops.object.mode_set(mode='OBJECT')
    contacts = {}
    rider_source = ROOT / "art/source/khazar/rigged_rider.glb" if khazar else None
    rider = make_rider(rig, contacts=contacts, animate=True, rider_source=rider_source)
    make_tack(rig, contacts)
    original_fall = bpy.data.actions["Death"]
    falls = [original_fall, original_fall.copy(), original_fall.copy()]
    falls[1].name = "DeathSide"
    falls[2].name = "DeathProne"
    for action, end, pitch, roll, turn, asymmetry in zip(
            falls, [(5.15, -.7, .56), (-4.60, -.8, .68), (4.95, .16, .58)],
            [-pi/2, -pi/2, pi/2], [.10, 1.37, -.13], [-.33, .55, .24], [.17, .34, -.20]):
        make_fall(rig, rider[0], contacts, action, end, pitch, roll, turn, asymmetry)
    bake_rider(rig, contacts, SEAT, rider[2])
    if khazar:
        for prop in ("Rider shield", "Rider spear"):
            bpy.data.objects.remove(bpy.data.objects[prop], do_unlink=True)
        author_archery(rig, contacts)
    else:
        position_rider_shield(rig, bpy.data.objects["Rider shield"], HORSE_SCALE)
    use_action(rig, bpy.data.actions["Idle"])
    rig.scale = (HORSE_SCALE,) * 3

    for image in bpy.data.images:
        if image.size[0]:
            image.pack()
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 100
    bpy.context.scene.frame_set(0)
    bpy.context.preferences.filepaths.save_version = 0
    name = "khazar_mounted" if khazar else "horseman_quaternius"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art" / (name + ".blend")))
    bpy.ops.export_scene.gltf(filepath=str(ROOT / "assets" / (name + ".glb")),
                             export_animation_mode='ACTIONS', export_frame_range=False,
                             export_apply=True, export_force_sampling=True)


if __name__ == "__main__":
    main("--khazar" in sys.argv)
