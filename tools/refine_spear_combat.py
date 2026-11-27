"""Give the spear thrust the sword pack's weight shift, with authored hand grips."""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/warrior.blend'))
rig = bpy.data.objects['WarriorRig']
body = bpy.data.objects['WarriorBody']
scene = bpy.context.scene
scene.render.fps = 30

def sample(name, phase):
    rig.animation_data.action = bpy.data.actions[name]
    lo, hi = rig.animation_data.action.frame_range
    time = lo + (hi - lo) * phase
    scene.frame_set(int(time), subframe=time % 1)
    bpy.context.view_layer.update()
    return ({b.name: b.matrix_basis.decompose() for b in rig.pose.bones},
            {b.name: b.matrix.copy() for b in rig.pose.bones})

def aim(bone, direction):
    q = bone.matrix.to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    m = q.to_matrix().to_4x4()
    m.translation = bone.head
    bone.matrix = m
    bpy.context.view_layer.update()

def arm(side, target):
    upper = rig.pose.bones['mixamorig:' + side + 'Arm']
    lower = rig.pose.bones['mixamorig:' + side + 'ForeArm']
    start = upper.head.copy()
    delta = target - start
    distance = min(delta.length, (upper.bone.length + lower.bone.length) * .995)
    direction = delta.normalized()
    pole = Vector((.38 if side == 'Left' else -.38, .02, .63)) - start
    pole = (pole - direction * pole.dot(direction)).normalized()
    along = (upper.bone.length ** 2 - lower.bone.length ** 2 + distance ** 2) / (2 * distance)
    elbow = start + direction * along + pole * math.sqrt(max(0, upper.bone.length ** 2 - along ** 2))
    aim(upper, elbow - start)
    aim(lower, target - lower.head)

def point_at(time, keys):
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if time <= tb:
            t = max(0, min(1, (time - ta) / (tb - ta)))
            t = t * t * (3 - 2 * t)
            return Vector(a).lerp(Vector(b), t)
    return Vector(keys[-1][1])

ready, world_ready = sample('motion_combat_spear', 0)
left_grip = world_ready['mixamorig:LeftHand'].inverted() @ world_ready['GripLeft']
samples = []
hand_positions = []
for frame in range(34):
    t = frame / 30
    phase = frame / 33
    source, _ = sample('pack_attack_2', phase)
    rig.animation_data.action = None
    weight = math.sin(math.pi * phase) ** .8
    for bone in rig.pose.bones:
        l0, q0, s0 = ready[bone.name]
        l1, q1, s1 = source[bone.name]
        influence = weight * (.08 if bone.name.endswith(('Head', 'Neck')) else .70)
        bone.rotation_mode = 'QUATERNION'
        bone.location = l0.lerp(l1, influence)
        bone.rotation_quaternion = q0.slerp(q1, influence)
        bone.scale = s0.lerp(s1, influence)
    bpy.context.view_layer.update()
    right = point_at(t, [(0, (-.17, -.18, .71)), (.24, (-.21, .045, .72)),
                         (.43, (-.155, -.385, .735)), (.52, (-.155, -.385, .735)),
                         (.79, (-.18, -.15, .70)), (1.1, (-.17, -.18, .71))])
    arm('Right', right)
    direction = Vector((0, -1, .035)).normalized()
    x = Vector((1, 0, 0))
    y = direction.cross(x).normalized()
    q = Matrix((y.cross(direction), y, direction)).transposed().to_quaternion()
    hand = rig.pose.bones['mixamorig:RightHand']
    m = (q @ Quaternion(Vector((1, 0, 1)).normalized(), math.pi)).to_matrix().to_4x4()
    m.translation = hand.head
    hand.matrix = m
    bpy.context.view_layer.update()
    m = q.to_matrix().to_4x4()
    m.translation = hand.head + hand.matrix.to_3x3() @ Vector((0, .025, 0))
    rig.pose.bones['GripRight'].matrix = m
    hand_positions.append(list(m.translation))
    arm('Left', world_ready['mixamorig:LeftHand'].translation)
    hand = rig.pose.bones['mixamorig:LeftHand']
    m = world_ready[hand.name].to_quaternion().to_matrix().to_4x4()
    m.translation = hand.head
    hand.matrix = m
    bpy.context.view_layer.update()
    rig.pose.bones['GripLeft'].matrix = hand.matrix @ left_grip
    bpy.context.view_layer.update()
    samples.append({b.name: b.matrix_basis.decompose() for b in rig.pose.bones})

name = 'motion_attack_spear'
if name in bpy.data.actions:
    bpy.data.actions.remove(bpy.data.actions[name])
action = bpy.data.actions.new(name)
action.use_fake_user = True
rig.animation_data.action = action
for frame, values in enumerate(samples):
    for bone_name, (loc, rot, scale) in values.items():
        bone = rig.pose.bones[bone_name]
        bone.location, bone.rotation_quaternion, bone.scale = loc, rot, scale
        for prop in ('location', 'rotation_quaternion', 'scale'):
            bone.keyframe_insert(data_path=prop, frame=frame, group=bone_name)
rig.animation_data.action = bpy.data.actions['motion_idle_spear']
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig, body]:obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/warrior.blend'))
for action in list(bpy.data.actions):
    if '|' in action.name:bpy.data.actions.remove(action)
bpy.ops.export_scene.gltf(filepath=str(ROOT / 'assets/warrior.glb'), export_format='GLB',
                         use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
                         export_force_sampling=True, export_def_bones=False, export_yup=True,
                         export_image_format='AUTO')
manifest_path = ROOT / 'assets/animation_manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
manifest[name] = {'duration': 1.1, 'loop': False, 'source': 'pack_attack_2',
                  'layer': 'sword-pack weight shift, spear retraction/thrust, preserved shield grip'}
manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
(ROOT / 'build/spear_motion_report.json').write_text(json.dumps({'hand_positions': hand_positions}), encoding='utf-8')
print('SPEAR_COMBAT_READY', flush=True)
