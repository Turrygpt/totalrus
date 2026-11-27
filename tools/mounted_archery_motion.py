"""Pose the mounted archer's arms and weapon sockets on the existing riding clips."""

import bpy
from math import pi, sin
from mathutils import Matrix, Quaternion, Vector
from mounted_rider_motion import CHEST, PELVIS, rider_joint, solve_limb


# Phase, upper-arm direction, forearm direction, sabre silhouette, and torso lean.
# Directions are in rider space, with forward along -Y.
SABRE_POSES = (
    (0.00, (.42, -.20, -.86), (.14, -.88, .45), (.24, -.17, .96), 0.00),
    (0.25, (.53,  .08, -.76), (.08, -.64, .72), (.12,  .13, .98), -.04),
    (0.46, (.23, -.92, -.29), (.10, -.99, .02), (.18, -.70, .69),  .15),
    (0.63, (.22, -.92, -.34), (.20, -.94, -.28), (.25, -.95, .25), .11),
    (0.83, (.38, -.49, -.79), (.08, -.94, .24), (.13, -.69, .71),  .04),
    (1.00, (.42, -.20, -.86), (.14, -.88, .45), (.24, -.17, .96), 0.00),
)


def sample_sabre_pose(phase, right):
    for start, end in zip(SABRE_POSES, SABRE_POSES[1:]):
        if phase <= end[0]:
            break
    weight = (phase - start[0]) / (end[0] - start[0])
    weight = weight * weight * (3.0 - 2.0 * weight)

    def direction(index):
        x, y, z = Vector(start[index]).lerp(Vector(end[index]), weight)
        return (right * x + Vector((0, y, z))).normalized()

    blade = direction(3)
    # Point the model's local +X cutting edge forward in the plane of the blade.
    forward = Vector((0, -1, 0))
    edge = (forward - blade * forward.dot(blade)).normalized()
    grip = Matrix((edge, blade.cross(edge), blade)).transposed().to_quaternion()
    lean = start[4] + (end[4] - start[4]) * weight
    return direction(1), direction(2), grip, lean


def pose_sword_arm(bones, points, chest_motion, base_turn, grip_local, reference):
    upper, lower, grip = reference[:3]
    shoulder, elbow, wrist = (points["Right" + name] for name in ("Arm", "ForeArm", "Hand"))
    root = chest_motion @ shoulder
    joint = root + (base_turn @ upper) * (elbow - shoulder).length
    palm = joint + (base_turn @ lower) * (wrist - elbow).length
    for bone, start, end, position, direction in (
            (bones[0], shoulder, elbow, root, joint - root),
            (bones[1], elbow, wrist, joint, palm - joint)):
        turn = (end - start).rotation_difference(direction).to_matrix().to_4x4()
        bone.matrix = (Matrix.Translation(position) @ turn
                       @ Matrix.Translation(-start) @ bone.bone.matrix_local)
        bpy.context.view_layer.update()
    hand_pose = (base_turn @ grip @ grip_local.to_quaternion().inverted()).to_matrix().to_4x4()
    hand_pose.translation = palm
    bones[-1].matrix = hand_pose
    bpy.context.view_layer.update()


def add_archery_sockets(rig, points):
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    sockets = {
        "GripLeft": (rider_joint("Left", "Hand"), points["LeftHand"]),
        "GripRight": (rider_joint("Right", "Hand"), points["RightHand"]),
        "SwordBelt": (PELVIS, points["LeftUpLeg"]),
        "BowBack": (CHEST, points["Spine1"]),
        "QuiverBack": (CHEST, points["Spine1"]),
    }
    for name, (parent, point) in sockets.items():
        bone = rig.data.edit_bones.new(name)
        bone.parent = rig.data.edit_bones[parent]
        bone.head = point
        bone.tail = point + Vector((0, 0, .25))
        bone.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return tuple(sockets)


def author_archery(rig, points):
    right = Vector((1 if points["RightArm"].x > points["LeftArm"].x else -1, 0, 0))
    socket_names = add_archery_sockets(rig, points)
    scene = bpy.context.scene
    stages = {"RiderDraw": 35, "RiderAim": 17, "RiderLoose": 15, "RiderSabre": 26}
    regular = [bpy.data.actions[name] for name in (
        "Idle", "Walk", "Trot", "Gallop", "ReadyIdle", "ReadyWalk", "ReadyGallop",
        "Rear", "Death", "DeathSide", "DeathProne", "MeleeStrike")]
    attacks = []
    for name, duration in stages.items():
        action = bpy.data.actions["Idle"].copy()
        action.name = name
        action.use_frame_range = True
        action.frame_start = 0
        action.frame_end = duration
        attacks.append(action)
    chest = rig.pose.bones[CHEST]
    pelvis = rig.pose.bones[PELVIS]
    hand = rig.pose.bones[rider_joint("Right", "Hand")]
    sword_arm = [rig.pose.bones[rider_joint("Right", name)] for name in ("Arm", "ForeArm", "Hand")]
    fingers = [bone for bone in rig.pose.bones if bone.name.startswith("mixamorig:RightHand")]
    knuckles = [rig.data.bones["mixamorig:RightHand" + digit + "1"].head_local.copy()
                for digit in ("Index", "Middle", "Ring", "Pinky")]
    grip_axis = (knuckles[0] - knuckles[-1]).normalized()
    center = sum(knuckles, Vector()) / len(knuckles)
    palm_ray = (center - hand.bone.head_local).normalized()
    curl_axis = points["RightPalmCurlAxis"]
    curl = curl_axis.cross(palm_ray).normalized()
    grip_origin = center - palm_ray * .026 + curl * .057
    grip_up = grip_axis
    grip_side = palm_ray.cross(grip_up).normalized()
    grip_forward = grip_up.cross(grip_side).normalized()
    sabre_rest = Matrix((grip_side, grip_forward, grip_up)).transposed().to_4x4()
    sabre_rest.translation = grip_origin
    sabre_local = hand.bone.matrix_local.inverted() @ sabre_rest
    # Roll the wrist clockwise around the handle while keeping the edge keyed forward.
    sabre_hold = sabre_local @ Matrix.Rotation(pi / 2, 4, "Z")
    thumb = rig.data.bones["mixamorig:RightHandThumb1"]
    thumb_target = (knuckles[0] + knuckles[1]) * .5 + curl * .075
    thumb_direction = thumb.matrix_local.to_quaternion().inverted() @ (thumb_target - thumb.head_local)
    thumb_fold = Vector((0, 1, 0)).rotation_difference(thumb_direction.normalized())
    for action in [*regular, *attacks]:
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        duration = round(action.frame_range.y)
        blade = action.name == "RiderSabre"
        chest_poses = []
        if blade:
            # Read the unmodified riding poses before inserting any sabre keys.
            for frame in range(duration + 1):
                scene.frame_set(frame)
                chest_poses.append(chest.matrix_basis.copy())
        previous = {}
        for frame in range(duration + 1):
            scene.frame_set(frame)
            if blade:
                chest.matrix_basis = chest_poses[frame]
                bpy.context.view_layer.update()
            phase = frame / max(1, duration)
            chest_motion = chest.matrix @ chest.bone.matrix_local.inverted()
            seat_motion = pelvis.matrix @ pelvis.bone.matrix_local.inverted()
            pose_bones = [rig.pose.bones[name] for name in socket_names]
            gripping = blade or action.name.startswith("Ready")
            if action.name in stages and not blade:
                settle = phase * phase * (3 - 2 * phase)
                lift = settle if action.name == "RiderDraw" else (1.0 - settle if action.name == "RiderLoose" else 1.0)
                for side in ("Left", "Right"):
                    shoulder, elbow, wrist = (points[side + name] for name in ("Arm", "ForeArm", "Hand"))
                    bones = [rig.pose.bones[rider_joint(side, name)] for name in ("Arm", "ForeArm", "Hand")]
                    parent = chest_motion @ shoulder
                    hand = bones[-1].head.copy()
                    if side == "Left":
                        desired = parent + Vector((.10, -1.43, .30))
                    else:
                        contact = points["LeftArm"] + Vector((.05, -1.25, .29))
                        anchor = shoulder + Vector((.08, -.32, .50))
                        draw = min(1.0, max(0.0, (phase - .22) / .72)) if action.name == "RiderDraw" else 1.0
                        desired = chest_motion @ contact.lerp(anchor, draw)
                        if action.name == "RiderLoose":
                            desired += Vector((-.08, .34 * sin(pi * phase), .10))
                    upper, lower, palm = solve_limb(shoulder, elbow, wrist, parent, hand.lerp(desired, lift))
                    matrices = [upper, lower, Matrix.Translation(palm - wrist)]
                    for bone, transform in zip(bones, matrices):
                        bone.matrix = transform @ bone.bone.matrix_local
                        bpy.context.view_layer.update()
                    pose_bones.extend(bones)
            if gripping:
                base_turn = chest_motion.to_quaternion()
                reference = sample_sabre_pose(phase if blade else 0.0, right)
                if blade:
                    turn = Matrix.Rotation(reference[3], 4, "X")
                    pivot = chest.matrix.translation
                    chest.matrix = Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot) @ chest.matrix
                    bpy.context.view_layer.update()
                    chest_motion = chest.matrix @ chest.bone.matrix_local.inverted()
                    pose_bones.append(chest)
                pose_sword_arm(sword_arm, points, chest_motion, base_turn, sabre_hold, reference)
                pose_bones.extend(sword_arm)
            for finger in fingers:
                finger.rotation_mode = "QUATERNION"
                local_axis = finger.bone.matrix_local.to_quaternion().inverted() @ curl_axis
                joint = int(finger.name[-1]) - 1
                if finger.name.endswith("Thumb1"):
                    rotation = Quaternion().slerp(thumb_fold, .76 if gripping else .83)
                elif "Thumb" in finger.name:
                    rotation = Quaternion(local_axis, (.0, .38, .28)[joint])
                elif gripping:
                    rotation = Quaternion(local_axis, 1.05)
                else:
                    angle = (.58, .83, .48)[joint]
                    if "Index" in finger.name or "Middle" in finger.name:
                        angle *= .66 if action.name in ("RiderDraw", "RiderAim") else .86
                    rotation = Quaternion(local_axis, angle)
                finger.rotation_quaternion = rotation
                finger.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=finger.name)
            for name in socket_names:
                bone = rig.pose.bones[name]
                if name in ("GripLeft", "GripRight"):
                    palm = bone.parent.head.copy()
                    if name == "GripLeft":
                        matrix = Matrix.Rotation(pi / 2, 4, "Z")
                        palm += Vector((0, -.10, .01))
                    else:
                        matrix = Matrix.Rotation(-.32, 4, "Z") @ Matrix.Rotation(.14, 4, "Y")
                        palm += Vector((-.04, -.08, .025))
                        if gripping:
                            # Keep the handle centred in the closed palm,
                            # with the blade axis fixed relative to the fingers.
                            matrix = bone.parent.matrix @ sabre_hold
                            palm = matrix.translation
                elif name == "SwordBelt":
                    matrix = seat_motion @ Matrix.Rotation(.69, 4, "X") @ Matrix.Rotation(pi - .17, 4, "Y")
                    palm = seat_motion @ (points["LeftUpLeg"] + Vector((.30, -.05, .46)))
                elif name == "QuiverBack":
                    matrix = chest_motion @ Matrix.Rotation(-.12, 4, "X") @ Matrix.Rotation(-.38, 4, "Y")
                    palm = chest_motion @ (points["Spine1"] + Vector((.23, .34, .23)))
                else:
                    matrix = chest_motion @ Matrix.Rotation(.52, 4, "Y")
                    palm = chest_motion @ (points["Spine1"] + Vector((.07, .44, -.36)))
                matrix.translation = palm
                bone.matrix = matrix
                bpy.context.view_layer.update()
            for bone in pose_bones:
                rotation = bone.rotation_quaternion.copy()
                if bone.name in previous and previous[bone.name].dot(rotation) < 0:
                    rotation.negate()
                    bone.rotation_quaternion = rotation
                previous[bone.name] = rotation
                for channel in ("location", "rotation_quaternion"):
                    bone.keyframe_insert(data_path=channel, frame=frame, group=bone.name)
