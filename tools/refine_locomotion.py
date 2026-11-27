"""Layer the retargeted sword pack into spear locomotion and armed charge cycles.

Run after retarget_pack.py. Original actions remain editable and unchanged.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig = bpy.data.objects['WarriorRig']
body = bpy.data.objects['WarriorBody']
scene = bpy.context.scene
scene.render.fps = 30
for action in list(bpy.data.actions):
    if action.name.startswith('motion_'): bpy.data.actions.remove(action)
rest = {b.name:b.matrix_local.copy() for b in rig.data.bones}

def sample(name, fraction):
    rig.animation_data.action = bpy.data.actions[name]
    a,b = rig.animation_data.action.frame_range
    frame = a+(b-a)*fraction
    scene.frame_set(int(frame), subframe=frame%1)
    bpy.context.view_layer.update()
    return {b.name:b.matrix.copy() for b in rig.pose.bones}

idle = sample('pack_idle_sword', 0)
carry = sample('idle_spear', 0)
ready = sample('combat_spear', 0)
torso_name = 'mixamorig:Spine2'

def aim_bone(pb,direction):
    q=pb.matrix.to_quaternion()
    q=(q@Vector((0,1,0))).rotation_difference(direction.normalized())@q
    m=q.to_matrix().to_4x4();m.translation=pb.head;pb.matrix=m
    bpy.context.view_layer.update()

def solve_arm(side,target):
    upper=rig.pose.bones['mixamorig:'+side+'Arm'];lower=rig.pose.bones['mixamorig:'+side+'ForeArm']
    start=upper.head.copy();delta=target-start
    distance=min(delta.length,(upper.bone.length+lower.bone.length)*.995);direction=delta.normalized()
    pole=Vector((.38 if side=='Left' else -.38,.02,.63))-start
    pole=(pole-direction*pole.dot(direction)).normalized()
    along=(upper.bone.length**2-lower.bone.length**2+distance**2)/(2*distance)
    elbow=start+direction*along+pole*math.sqrt(max(0,upper.bone.length**2-along**2))
    aim_bone(upper,elbow-start);aim_bone(lower,target-lower.head)

def grip_rotation(direction):
    z=Vector(direction).normalized();x=Vector((1,0,0));y=z.cross(x).normalized();x=y.cross(z)
    return Matrix((x,y,z)).transposed().to_quaternion()

# Source gait, duration, right-arm pose, left-arm pose, quiet walking torso.
clips = {
    'walk_spear':('walk_spear',1.2,carry,idle,True),
    'walk_sword':('walk_sword',1.2,idle,idle,True),
    'advance_spear':('walk_spear',1.2,ready,idle,True),
    'advance_sword':('walk_sword',1.2,idle,idle,True),
    'run_spear':('pack_run_sword',.7,carry,None,False),
    'charge_spear':('pack_run_sword',.7,ready,idle,False),
    'charge_sword':('pack_run_sword',.7,idle,idle,False),
    'idle_spear':('pack_idle_sword',2.433333,carry,None,False),
    'combat_spear':('pack_idle_sword',2.433333,ready,None,False),
    'backstep_spear':('pack_backstep_sword',.533333,ready,None,False),
    'strafe_left_spear':('pack_strafe_left_sword',.666667,ready,None,False),
    'strafe_right_spear':('pack_strafe_right_sword',.7,ready,None,False),
}
manifest = json.loads((ROOT/'assets/animation_manifest.json').read_text())
report = {}
for short,(source,duration,right_ref,left_ref,walking) in clips.items():
    name = 'motion_'+short
    samples = []
    heads = []
    count = round(duration*30)
    for frame in range(count+1):
        phase = frame/count
        original = sample(source, phase)
        desired = {}
        bases = {}
        for pb in rig.pose.bones:
            parent = pb.parent
            base = desired[parent.name] @ rest[parent.name].inverted() @ rest[pb.name] if parent else rest[pb.name]
            q = original[pb.name].to_quaternion()
            position = base.translation.copy()
            if pb.name == 'mixamorig:Hips':
                position = original[pb.name].translation.copy()
            if walking and pb.name in ['mixamorig:Spine','mixamorig:Spine1',torso_name]:
                # Retain a little counter-sway rather than transmitting the entire hip yaw.
                hip_delta = original['mixamorig:Hips'].to_quaternion() @ rest['mixamorig:Hips'].to_quaternion().inverted()
                q = Quaternion().slerp(hip_delta,.18) @ idle[pb.name].to_quaternion()
            if pb.name in ['mixamorig:Neck','mixamorig:Head']:
                q = idle[pb.name].to_quaternion().slerp(q,.12 if walking else .45)
            reference = None
            if pb.name.startswith('mixamorig:Right') and not any(part in pb.name for part in ['UpLeg','Leg','Foot','Toe']):
                reference = right_ref
            if pb.name.startswith('mixamorig:Left') and not any(part in pb.name for part in ['UpLeg','Leg','Foot','Toe']):
                reference = left_ref
            if pb.name == 'GripRight': reference = right_ref
            if pb.name == 'GripLeft': reference = left_ref
            if reference is not None:
                matrix = desired[torso_name] @ reference[torso_name].inverted() @ reference[pb.name]
            elif pb.name in ['GripRight','GripLeft','SwordBelt']:
                # A socket follows its hand/hips, preserving the corrected handle location.
                matrix = desired[parent.name] @ original[parent.name].inverted() @ original[pb.name]
            else:
                matrix = q.to_matrix().to_4x4()
                matrix.translation = position
            desired[pb.name] = matrix
            bases[pb.name] = (base.inverted() @ matrix).decompose()
        if short.startswith('charge_') or short == 'run_spear':
            # Keep the weapon aimed independently of the runner's forward torso lean.
            rig.animation_data.action=None
            for bone_name,(loc,rot,scl) in bases.items():
                pb=rig.pose.bones[bone_name];pb.location,pb.rotation_quaternion,pb.scale=loc,rot,scl
            bpy.context.view_layer.update()
            armed=short.startswith('charge_')
            bob=(original['mixamorig:Hips'].translation.z-rest['mixamorig:Hips'].translation.z)*.35
            direction=(0,-.98,.12) if short=='charge_spear' else ((0,-.58,.82) if short=='charge_sword' else (0,-.12,1))
            solve_arm('Right',Vector((-.18,-.16 if armed else -.10,(.73 if armed else .61)+bob)))
            hand=rig.pose.bones['mixamorig:RightHand'];q=grip_rotation(direction)
            m=(q@Quaternion(Vector((1,0,1)).normalized(),math.pi)).to_matrix().to_4x4();m.translation=hand.head;hand.matrix=m
            bpy.context.view_layer.update()
            m=q.to_matrix().to_4x4();m.translation=hand.head+hand.matrix.to_3x3()@Vector((0,.025,0));rig.pose.bones['GripRight'].matrix=m
            if armed:
                solve_arm('Left',Vector((.11,-.23,.69+bob)))
                hand=rig.pose.bones['mixamorig:LeftHand'];m=ready[hand.name].to_quaternion().to_matrix().to_4x4();m.translation=hand.head;hand.matrix=m
                bpy.context.view_layer.update()
                m=Matrix.Identity(4);m.translation=hand.head+hand.matrix.to_3x3()@Vector((0,.025,0));rig.pose.bones['GripLeft'].matrix=m
            bpy.context.view_layer.update()
            bases={pb.name:pb.matrix_basis.decompose() for pb in rig.pose.bones}
        samples.append(bases)
        heads.append(desired['mixamorig:Head'].to_quaternion())
    samples[-1] = samples[0]
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame,values in enumerate(samples):
        for bone_name,(location,rotation,scale) in values.items():
            pb = rig.pose.bones[bone_name]
            pb.rotation_mode = 'QUATERNION'
            pb.location,pb.rotation_quaternion,pb.scale = location,rotation,scale
            for prop in ('location','rotation_quaternion','scale'):
                pb.keyframe_insert(data_path=prop,frame=frame,group=bone_name)
    swing = max(math.degrees(heads[0].rotation_difference(q).angle) for q in heads)
    report[name] = {'head_angle_from_start_degrees':round(swing,3),'frames':count+1}
    manifest[name] = {'duration':count/30,'loop':True,'source':source,'layer':'sword pack body / weapon-specific hands / stabilized gaze'}
    print('MOTION',name,'head excursion',round(swing,2),flush=True)

rig.animation_data.action = bpy.data.actions['motion_idle_spear']
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig,body]:obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/warrior.blend'))
for action in list(bpy.data.actions):
    if '|' in action.name:bpy.data.actions.remove(action)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/warrior.glb'),export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
    export_def_bones=False,export_yup=True,export_image_format='AUTO')
(ROOT/'assets/animation_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(ROOT/'build/locomotion_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
