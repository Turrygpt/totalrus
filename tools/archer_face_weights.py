"""Keep the entire jaw/face rigid with the skull; blend only below the chin."""

import bpy
from mathutils import Quaternion, Vector


def stabilize_face(body, blend_bounds=None):
    head = body.vertex_groups["mixamorig:Head"]
    minimum = min(vertex.co.z for vertex in body.data.vertices)
    height = max(vertex.co.z for vertex in body.data.vertices) - minimum
    for vertex in body.data.vertices:
        normalized_height = (vertex.co.z - minimum) / height
        # The beard tip is at .8407 of this mesh's height. The old .84-.885
        # ramp ran through the jaw and mouth, pulling them towards the shoulders
        # whenever an animation turned the head. Finish the blend below the jaw.
        start, end = blend_bounds(vertex.co) if blend_bounds else (.805, .838)
        strength = max(0.0, min(1.0, (normalized_height - start) / (end - start)))
        if strength == 0.0:
            continue
        strength *= strength * (3.0 - 2.0 * strength)
        old_weights = [(group.group, group.weight) for group in vertex.groups]
        previous_head = sum(weight for index, weight in old_weights if index == head.index)
        head_weight = max(strength, previous_head)
        other_total = sum(weight for index, weight in old_weights if index != head.index)
        for index, weight in old_weights:
            if index == head.index:
                continue
            elif head_weight == 1.0:
                body.vertex_groups[index].remove([vertex.index])
            else:
                body.vertex_groups[index].add([vertex.index], weight / other_total * (1.0 - head_weight), 'REPLACE')
        head.add([vertex.index], head_weight, 'REPLACE')


def level_archer_head(rig):
    """Preserve look direction while leveling the brow in standing and aiming poses."""
    scene = bpy.context.scene
    neck = rig.pose.bones["mixamorig:Neck"]
    head = rig.pose.bones["mixamorig:Head"]
    side = Vector((1, 0, 0))
    up = Vector((0, 0, 1))
    forward = Vector((0, -1, 0))
    for action in bpy.data.actions:
        if not action.name.startswith(("bow_", "knife_")):
            continue
        if any(name in action.name for name in ("death", "hit", "victory")):
            continue
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        frames = range(round(action.frame_range.x), round(action.frame_range.y) + 1)
        samples = []
        for frame in frames:
            scene.frame_set(frame)
            neck_rotation = neck.matrix.to_quaternion()
            head_rotation = head.matrix.to_quaternion()
            delta = head_rotation @ head.bone.matrix_local.to_quaternion().inverted()
            level = up.cross(delta @ forward).normalized()
            correction = (delta @ side).rotation_difference(level)
            samples.append((neck_rotation, head_rotation, correction))
        previous = {}
        for frame, (neck_rotation, head_rotation, correction) in zip(frames, samples):
            scene.frame_set(frame)
            for bone, rotation, weight in ((neck, neck_rotation, .45), (head, head_rotation, .94)):
                adjusted = Quaternion().slerp(correction, weight) @ rotation
                matrix = adjusted.to_matrix().to_4x4()
                matrix.translation = bone.head
                bone.matrix = matrix
                value = bone.rotation_quaternion.copy()
                if bone.name in previous and previous[bone.name].dot(value) < 0:
                    value.negate()
                    bone.rotation_quaternion = value
                previous[bone.name] = value
                bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=bone.name)
                bpy.context.view_layer.update()
