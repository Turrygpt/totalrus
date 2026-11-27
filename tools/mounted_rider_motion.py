"""Skin the posed warrior and bake a seated trot and a light galloping seat."""

from math import cos, pi, sin, sqrt, tau

import bpy
from mathutils import Matrix, Vector

PELVIS = "RiderRoot"
SADDLE = "SaddleSocket"
SPEAR = "SpearRoot"
SHIELD = "RiderShield"
CHEST = "RiderChest"
HEAD = "RiderHead"
LIMBS = {
    "UpLeg": "Thigh", "Leg": "Shin", "Foot": "Boot",
    "Arm": "UpperArm", "ForeArm": "Forearm", "Hand": "Hand",
}
SIDES = ("Left", "Right")


def rider_joint(side, name):
    return f"Rider{LIMBS[name]}.{side[0]}"


def deform_bone(source_name):
    name = source_name.removeprefix("mixamorig:")
    for side in SIDES:
        if name.startswith(side):
            segment = name[len(side):]
            if segment.startswith("Hand"):
                return rider_joint(side, "Hand")
            if segment == "ToeBase":
                return rider_joint(side, "Foot")
            if segment in LIMBS:
                return rider_joint(side, segment)
    return PELVIS if name == "Hips" else HEAD if name in ("Head", "Neck") else CHEST


def add_controls(horse, rider, source_mesh, points, fingers=None):
    if len(source_mesh.data.vertices) != len(rider.data.vertices):
        raise ValueError("Mounted rider mesh must keep the source skin vertex order")
    parents = {CHEST: PELVIS, HEAD: CHEST}
    for side in SIDES:
        for chain, root in ((("UpLeg", "Leg", "Foot"), PELVIS), (("Arm", "ForeArm", "Hand"), CHEST)):
            for name in chain:
                joint = rider_joint(side, name)
                parents[joint] = root
                root = joint

    anchors = {CHEST: points["Spine1"], HEAD: points["Neck"]}
    anchors.update({rider_joint(side, name): points[side + name] for side in SIDES for name in LIMBS})
    bpy.ops.object.select_all(action="DESELECT")
    horse.select_set(True)
    bpy.context.view_layer.objects.active = horse
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent in parents.items():
        bone = horse.data.edit_bones.new(name)
        bone.parent = horse.data.edit_bones[parent]
        bone.head = anchors[name]
        bone.tail = bone.head + Vector((0, 0, .28))
    if fingers:
        for name, (parent, matrix) in fingers.items():
            bone = horse.data.edit_bones.new(name)
            bone.head = matrix.translation
            bone.tail = bone.head + matrix.to_quaternion() @ Vector((0, .055, 0))
            bone.align_roll(matrix.to_quaternion() @ Vector((0, 0, 1)))
            bone.parent = horse.data.edit_bones[parent]
    shield = horse.data.edit_bones.new(SHIELD)
    shield.parent = horse.data.edit_bones[rider_joint("Left", "Hand")]
    shield.head = points["LeftHand"]
    shield.tail = shield.head + Vector((0, 0, .28))
    bpy.ops.object.mode_set(mode="OBJECT")

    groups = {g.name: g for g in rider.vertex_groups}
    groups.update({name: rider.vertex_groups.new(name=name) for name in anchors})
    if fingers:
        groups.update({name: rider.vertex_groups.new(name=name) for name in fingers})
    source_groups = [group.name if fingers and group.name in fingers else deform_bone(group.name)
                     for group in source_mesh.vertex_groups]
    for vertex in source_mesh.data.vertices:
        weights = {}
        for weight in vertex.groups:
            name = source_groups[weight.group]
            weights[name] = weights.get(name, 0) + weight.weight
        # Keep the runtime skin within the four influences used by glTF.
        largest = sorted(weights.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(weight for _, weight in largest)
        if total:
            groups[PELVIS].remove([vertex.index])
            for name, weight in largest:
                groups[name].add([vertex.index], weight / total, "REPLACE")


def pitch_transform(root, pitch, position, roll=0):
    rotation = Matrix.Rotation(pitch, 4, "X") @ Matrix.Rotation(roll, 4, "Y")
    return Matrix.Translation(position) @ rotation @ Matrix.Translation(-root)


def solve_limb(upper, middle, end, root, goal):
    """Keep both segment lengths while moving the knee or elbow in its original bend plane."""
    first = (middle - upper).length
    second = (end - middle).length
    axis = (goal - root).normalized()
    distance = max(abs(first - second) + .0001,
                   min((goal - root).length, first + second - .0001))
    effective_goal = root + axis * distance
    along = (first * first - second * second + distance * distance) / (2 * distance)
    side = middle - upper
    bend = (side - axis * side.dot(axis)).normalized()
    joint = root + axis * along + bend * sqrt(max(0, first * first - along * along))

    def aim(begin, finish, position, target):
        turn = (finish - begin).rotation_difference(target - position)
        matrix = turn.to_matrix().to_4x4()
        return Matrix.Translation(position) @ matrix @ Matrix.Translation(-begin)

    return aim(upper, middle, root, joint), aim(middle, end, joint, effective_goal), effective_goal


def sample_pose(points, seat, grip, phase, pitch, lift, gait, ready, strike=0):
    gallop = gait == "Gallop"
    if gallop:
        thrust = sin(phase - .44)
        hip_offset = Vector((.023 * sin(phase), -.21 - .04 * thrust, .23 - .45 * lift + .028 * thrust))
        hip_pitch = .085 - .46 * pitch + .035 * thrust
        chest_pitch = .37 - .70 * pitch + .047 * thrust
        head_pitch = .085 - .74 * pitch
        foot_pitch = .046 * sin(phase - .15)
        grip_pitch = .32 - .67 * pitch + .052 * thrust
    else:
        beat = sin(2 * phase - .35)
        hip_offset = Vector((.023 * sin(phase), .028 * beat, -.39 * lift - .012 * beat))
        hip_pitch = -.59 * pitch + .077 * beat
        chest_pitch = -.75 * pitch - .027 * beat
        head_pitch = -.87 * pitch - .014 * beat
        foot_pitch = .039 * beat
        grip_pitch = -.66 * pitch + .022 * beat
    if gait in ("Idle", "Walk"):
        hip_offset = Vector((0, 0, -.18 * lift))
        hip_pitch = 0
        chest_pitch = .10 - .45 * pitch
        head_pitch = -.60 * pitch
        foot_pitch = 0
    if ready:
        grip_pitch = 1.23 - .70 * pitch + .03 * sin(phase)
        chest_pitch += .24 * strike

    hips = pitch_transform(seat, hip_pitch, seat + hip_offset, .021 * sin(phase))
    ankles = {}
    for side in SIDES:
        thigh, knee, ankle = (points[side + name] for name in ("UpLeg", "Leg", "Foot"))
        toe = points[side + "ToeBase"]
        ankles[side] = pitch_transform(toe, foot_pitch, toe) @ ankle
        delta = hips @ thigh - ankles[side]
        reach = (knee - thigh).length + (ankle - knee).length - .008
        supported_height = sqrt(max(0, reach * reach - delta.x * delta.x - delta.y * delta.y))
        hips.translation.z -= max(0, delta.z - supported_height)
    chest = points["Spine1"]
    neck = points["Neck"]
    torso = pitch_transform(chest, chest_pitch, hips @ chest, .012 * sin(phase))
    motions = {
        PELVIS: hips,
        CHEST: torso,
        HEAD: pitch_transform(neck, head_pitch, torso @ neck),
    }
    for side in SIDES:
        thigh, knee, ankle = (points[side + name] for name in ("UpLeg", "Leg", "Foot"))
        upper, lower, foot = solve_limb(thigh, knee, ankle, hips @ thigh, ankles[side])
        motions[rider_joint(side, "UpLeg")] = upper
        motions[rider_joint(side, "Leg")] = lower
        motions[rider_joint(side, "Foot")] = pitch_transform(ankle, foot_pitch, foot)

        shoulder, elbow, wrist = (points[side + name] for name in ("Arm", "ForeArm", "Hand"))
        offset = Vector((0, -.12 if gallop else 0, -.055 if gallop else 0))
        offset.z -= lift * (.44 if gallop else .24)
        if ready:
            offset += Vector((-.22, .13, -.13)) if side == "Right" else Vector((-.13, -.24, .35))
        if side == "Right":
            offset.y -= strike
        upper, lower, hand = solve_limb(shoulder, elbow, wrist, torso @ shoulder, wrist + offset)
        wrist_turn = grip_pitch if side == "Right" else (0.06 if ready else grip_pitch * .62)
        motions[rider_joint(side, "Arm")] = upper
        motions[rider_joint(side, "ForeArm")] = lower
        motions[rider_joint(side, "Hand")] = pitch_transform(wrist, wrist_turn, hand)

    hand_shift = motions[rider_joint("Right", "Hand")] @ grip
    motions[SPEAR] = pitch_transform(grip, grip_pitch, hand_shift)
    if ready:
        wrist = points["LeftHand"]
        hand = motions[rider_joint("Left", "Hand")] @ wrist
        motions[SHIELD] = (Matrix.Translation(hand) @ Matrix.Rotation(-.97, 4, "Z")
                           @ Matrix.Translation(-wrist))
    return motions


def bake_rider(horse, points, seat, grip):
    scene = bpy.context.scene
    saddle = horse.pose.bones[SADDLE]
    saddle_inverse = saddle.bone.matrix_local.inverted()
    for clip in ("Trot", "Gallop", "ReadyIdle", "ReadyWalk", "ReadyGallop", "MeleeStrike"):
        strike = clip == "MeleeStrike"
        ready = clip.startswith("Ready") or strike
        gait = "Idle" if strike else clip.removeprefix("Ready")
        if ready:
            bpy.data.actions[gait].copy().name = clip
        action = bpy.data.actions[clip]
        if strike:
            action.use_frame_range = True
            action.frame_start = 0
            action.frame_end = 22
        horse.animation_data.action = action
        horse.animation_data.action_slot = action.slots[0]
        frames = round(action.frame_range.y)
        saddles = []
        for frame in range(frames + 1):
            scene.frame_set(frame)
            saddles.append(saddle.matrix @ saddle_inverse)
        mean_height = sum((matrix @ seat).z for matrix in saddles[:-1]) / frames
        previous = {}
        for frame, mount in enumerate(saddles):
            scene.frame_set(frame)
            phase = tau * (frame % frames) / frames
            pitch = mount.to_euler("XYZ").x
            lift = (mount @ seat).z - mean_height
            # A short draw-back, a thrust at frame 10, then a return to the guard.
            reach = 0
            if strike:
                reach = (-.24 * sin(pi * frame / 10) if frame <= 5 else
                         .57 * sin(pi * (frame - 5) / 12) - .24 * max(0, (10 - frame) / 5)
                         if frame <= 11 else .57 * cos(.5 * pi * (frame - 11) / 11))
            pose = sample_pose(points, seat, grip, phase, pitch, lift, gait, ready, reach)
            transforms = {}
            for bone in horse.pose.bones:
                if bone.name not in pose:
                    continue
                parent = bone.parent
                rest = bone.bone.matrix_local
                transform = mount @ pose[bone.name] @ rest
                parent_transform = transforms.get(parent.name, parent.matrix)
                basis = bone.bone.convert_local_to_pose(
                    transform, rest, parent_matrix=parent_transform,
                    parent_matrix_local=parent.bone.matrix_local, invert=True,
                )
                rotation = basis.to_quaternion()
                if bone.name in previous and rotation.dot(previous[bone.name]) < 0:
                    rotation.negate()
                previous[bone.name] = rotation.copy()
                bone.rotation_mode = "QUATERNION"
                bone.rotation_quaternion = rotation
                bone.location = basis.translation
                transforms[bone.name] = transform
                bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
                bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=bone.name)
    horse.animation_data.action = None
    for bone in horse.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)


def position_rider_shield(horse, shield, horse_scale):
    # Put the board in front of the knuckles in both guarded and relaxed poses.
    clearance = Vector((-.050, -.065, .012)) / horse_scale
    shield.data.transform(Matrix.Translation(clearance))
    bone = horse.pose.bones[SHIELD]
    turn = Matrix.Rotation(-.33, 4, "Z")
    scene = bpy.context.scene
    for name in ("Idle", "Walk", "Trot", "Gallop"):
        action = bpy.data.actions[name]
        horse.animation_data.action = action
        horse.animation_data.action_slot = action.slots[0]
        frames = range(round(action.frame_range.x), round(action.frame_range.y) + 1)
        samples = []
        for frame in frames:
            scene.frame_set(frame)
            pose = bone.matrix.copy()
            pivot = pose.translation
            samples.append(Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot) @ pose)
        previous = None
        for frame, pose in zip(frames, samples):
            scene.frame_set(frame)
            bone.matrix = pose
            rotation = bone.rotation_quaternion.copy()
            if previous is not None and previous.dot(rotation) < 0:
                rotation.negate()
                bone.rotation_quaternion = rotation
            previous = rotation
            bone.keyframe_insert(data_path="location", frame=frame, group=SHIELD)
            bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=SHIELD)
