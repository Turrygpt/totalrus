"""Put the existing archery clips on the spearman mesh and skeleton."""
from math import radians
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from archer_face_weights import stabilize_face

ARMATURE = 'mixamorig:'
BACK_SOCKETS = ('BowBack', 'QuiverBack')
SOCKETS = ('GripLeft', 'GripRight', 'SwordBelt', *BACK_SOCKETS)

bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/archer.blend'))
source = bpy.data.objects['ArcherRig']
actions = list(bpy.data.actions)
with bpy.data.libraries.load(str(ROOT / 'art/warrior.blend'), link=False) as (_, target):
    target.objects = ['WarriorRig', 'WarriorBody']
rig, body = target.objects
for obj in (rig, body):
    bpy.context.collection.objects.link(obj)

def infantry_neck_bounds(point):
    # Follow the jawline: the chin sits lower than the base of the skull.
    rear = max(0.0, min(1.0, (point.y + .045) / .028))
    jaw = .836 + .040 * rear
    return jaw - .032, jaw

stabilize_face(body, infantry_neck_bounds)
rig.animation_data_clear()
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
for name in BACK_SOCKETS:
    bone = rig.data.edit_bones.new(name)
    bone.parent = rig.data.edit_bones[ARMATURE + 'Spine2']
    bone.head = bone.parent.head
    bone.tail = bone.head + Vector((0, 0, .06))
    bone.use_deform = False
bpy.ops.object.mode_set(mode='OBJECT')

rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
source_rest = {bone.name: bone.matrix_local.copy() for bone in source.data.bones}
hips = ARMATURE + 'Hips'
neck = ARMATURE + 'Neck'
head = ARMATURE + 'Head'
chest = ARMATURE + 'Spine2'

def bounded_rotation(rotation, limit):
    rotation = rotation.normalized()
    if rotation.w < 0:
        rotation.negate()
    return Quaternion().slerp(rotation, min(1.0, limit / max(.001, rotation.angle)))

scene = bpy.context.scene
scene.render.fps = 30
for original in actions:
    name = original.name
    original.name = 'Source_' + name
    source.animation_data.action = original
    if original.slots:
        source.animation_data.action_slot = original.slots[0]
    animation = bpy.data.actions.new(name)
    animation.use_fake_user = True
    rig.animation_data_create().action = animation
    previous = {}
    for frame in range(round(original.frame_range.x), round(original.frame_range.y) + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        posed = {bone.name: bone.matrix.copy() for bone in source.pose.bones}
        delta = {key: pose.to_quaternion() @ source_rest[key].to_quaternion().inverted()
                 for key, pose in posed.items() if key not in SOCKETS}
        # Share the turn between neck and head and cap the lower neck bend near the collar.
        if name not in ('bow_death', 'bow_death_front', 'bow_hit'):
            chest_rotation = delta[chest]
            relative = chest_rotation.inverted() @ delta[head]
            turn = bounded_rotation(relative, radians(68))
            neutral_neck = chest_rotation @ Quaternion().slerp(turn, .40)
            delta[neck] = neutral_neck
            delta[head] = chest_rotation @ turn
        desired = {}
        for bone in rig.pose.bones:
            key = bone.name
            parent = bone.parent.name if bone.parent else None
            base = desired[parent] @ rest[parent].inverted() @ rest[key] if parent else rest[key]
            if key in SOCKETS:
                matrix = posed[key].copy()
                # Keep held items over the new hand and stowed items flush with the new torso.
                offset = posed[key].translation - posed[parent].translation
                matrix.translation = desired[parent].translation + offset
                if key in BACK_SOCKETS:
                    matrix.translation += delta[chest] @ Vector((0, -.020, .025))
            elif key in delta:
                matrix = (delta[key] @ rest[key].to_quaternion()).to_matrix().to_4x4()
                matrix.translation = base.translation
                if key == hips:
                    matrix.translation = posed[key].translation.copy()
            else:
                matrix = base.copy()
            desired[key] = matrix
            location, rotation, scale = (base.inverted() @ matrix).decompose()
            if key in previous and previous[key].dot(rotation) < 0:
                rotation.negate()
            previous[key] = rotation
            bone.rotation_mode = 'QUATERNION'
            bone.location, bone.rotation_quaternion, bone.scale = location, rotation, scale
            bone.keyframe_insert(data_path='location', frame=frame, group=key)
            bone.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=key)
    print('INFANTRY ARCHER', name, flush=True)

for action in list(bpy.data.actions):
    if action.name.startswith(('bow_', 'knife_')):
        continue
    bpy.data.actions.remove(action)
rig.animation_data.action = bpy.data.actions['bow_idle']
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for obj in (rig, body):
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / 'assets/archer_infantry.glb'), export_format='GLB',
    use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
    export_force_sampling=True, export_def_bones=False, export_yup=True,
)
