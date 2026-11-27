"""Retarget the user's Mixamo pack to the existing rest pose and hand sockets.

Run after prepare_assets.py. Both the editable blend and GLB retain the original clips.
"""
import bpy
import json
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'art/source/sword_shield_pack'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
for action in list(bpy.data.actions):
    if action.name.startswith('pack_'):
        bpy.data.actions.remove(action)
rig = bpy.data.objects['WarriorRig']
body = bpy.data.objects['WarriorBody']
scene = bpy.context.scene
scene.render.fps = 30
rest = {b.name:b.matrix_local.copy() for b in rig.data.bones}
base_actions = list(bpy.data.actions)
rig.animation_data.action = bpy.data.actions['idle_sword']
scene.frame_set(0)
bpy.context.view_layer.update()
socket_offsets = {}
for socket,parent in [('GripRight','mixamorig:RightHand'),('GripLeft','mixamorig:LeftHand'),('SwordBelt','mixamorig:Hips')]:
    socket_offsets[socket] = rig.pose.bones[parent].matrix.inverted() @ rig.pose.bones[socket].matrix
rig.animation_data.action = None

def shield_frame(hand, forearm, torso, previous=None):
    torso_delta=torso.to_3x3() @ rest['mixamorig:Spine2'].to_3x3().inverted()
    up=(torso_delta @ Vector((0,0,1))).normalized()
    along=(hand.translation-forearm.translation).normalized()
    normal=up.cross(along).normalized()
    forward=(torso_delta @ Vector((0,-1,0))).normalized()
    reference=previous if previous is not None else forward
    if normal.dot(reference)<0:normal=-normal
    side=up.cross(normal).normalized()
    up=normal.cross(side).normalized()
    matrix=Matrix((side,-normal,up)).transposed().to_4x4()
    matrix.translation=hand.translation+hand.to_3x3() @ Vector((0,.025,0))
    return matrix,normal

clips = {
    'sword and shield idle.fbx':('pack_idle_sword',True),
    'sword and shield block idle.fbx':('pack_guard_sword',True),
    'sword and shield run.fbx':('pack_run_sword',True),
    'sword and shield run (2).fbx':('pack_backstep_sword',True),
    'sword and shield strafe.fbx':('pack_strafe_left_sword',True),
    'sword and shield strafe (2).fbx':('pack_strafe_right_sword',True),
    'sword and shield attack.fbx':('pack_attack_1',False),
    'sword and shield attack (2).fbx':('pack_attack_2',False),
    'sword and shield attack (3).fbx':('pack_attack_3',False),
    'sword and shield attack (4).fbx':('pack_attack_4',False),
    'sword and shield block.fbx':('pack_block_enter',False),
    'sword and shield block (2).fbx':('pack_block_exit',False),
    'sword and shield death.fbx':('pack_death',False),
    'sword and shield turn.fbx':('pack_turn_left',False),
    'sword and shield turn (2).fbx':('pack_turn_right',False),
    'draw sword 1.fbx':('pack_draw_sword',False),
    'sheath sword 1.fbx':('pack_sheath_sword',False),
}
manifest = json.loads((ROOT/'assets/animation_manifest.json').read_text())
for filename,(name,loop) in clips.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(PACK/filename))
    imported = set(bpy.data.objects)-before
    src = next(o for o in imported if o.type=='ARMATURE')
    source_action = src.animation_data.action
    start,end = source_action.frame_range
    duration = (end-start)/30
    corrections = {}
    for pb in rig.pose.bones:
        if pb.name not in src.pose.bones:continue
        source_rest = (src.matrix_world @ src.data.bones[pb.name].matrix_local).to_quaternion()
        target_rest = rest[pb.name].to_quaternion()
        alignment = (target_rest @ Vector((0,1,0))).rotation_difference(source_rest @ Vector((0,1,0)))
        corrections[pb.name] = source_rest.inverted() @ alignment @ target_rest
    src_root = src.matrix_world @ src.data.bones['mixamorig:Hips'].head_local
    scale = rest['mixamorig:Hips'].translation.z / src_root.z
    # Preserve the root's vertical movement, but remove travel. Navigation owns translation.
    samples=[]
    previous_normal=None
    count=round(end-start)
    for frame in range(count+1):
        rig.animation_data.action = None
        scene.frame_set(int(start)+frame)
        bpy.context.view_layer.update()
        desired={}
        bases={}
        for pb in rig.pose.bones:
            parent=pb.parent
            if parent:
                relative_rest = rest[parent.name].inverted() @ rest[pb.name]
                base = desired[parent.name] @ relative_rest
            else:
                base = rest[pb.name]
            if pb.name in corrections:
                source_pose=src.matrix_world @ src.pose.bones[pb.name].matrix
                q=source_pose.to_quaternion() @ corrections[pb.name]
                location=base.translation.copy()
                if pb.name=='mixamorig:Hips':
                    location.z=source_pose.translation.z*scale
                matrix=q.to_matrix().to_4x4()
                matrix.translation=location
            elif pb.name == 'GripLeft':
                matrix,previous_normal=shield_frame(desired['mixamorig:LeftHand'],desired['mixamorig:LeftForeArm'],desired['mixamorig:Spine2'],previous_normal)
            elif pb.name in socket_offsets:
                matrix=desired[parent.name] @ socket_offsets[pb.name]
            else:
                matrix=base.copy()
            desired[pb.name]=matrix
            basis=base.inverted() @ matrix
            bases[pb.name]=basis.decompose()
        samples.append(bases)
    action=bpy.data.actions.new(name)
    action.use_fake_user=True
    rig.animation_data.action=action
    for frame,values in enumerate(samples):
        for bone_name,(location,rotation,scale_vec) in values.items():
            pb=rig.pose.bones[bone_name]
            pb.rotation_mode='QUATERNION'
            pb.location=location
            pb.rotation_quaternion=rotation
            pb.scale=scale_vec
            for prop in ('location','rotation_quaternion','scale'):
                pb.keyframe_insert(data_path=prop,frame=frame,group=bone_name)
    for obj in imported:bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.actions.remove(source_action)
    manifest[name]={'duration':duration,'loop':loop,'source':filename}
    print('RETARGETED',name,duration,flush=True)

# Use the pack's clenched hand and wrist articulation for the authored spear clips too.
# Otherwise the same shield snaps between a proper grip and an open rest-pose hand.
rig.animation_data.action=bpy.data.actions['pack_guard_sword']
scene.frame_set(0)
bpy.context.view_layer.update()
hand=rig.pose.bones['mixamorig:LeftHand']
forearm=rig.pose.bones['mixamorig:LeftForeArm']
wrist_in_shield=rig.pose.bones['GripLeft'].matrix.to_quaternion().inverted() @ hand.matrix.to_quaternion()
finger_rotations={b.name:b.rotation_quaternion.copy() for b in rig.pose.bones if b.name.startswith('mixamorig:LeftHand') and b.name!='mixamorig:LeftHand'}
for action in base_actions:
    if '|' in action.name:continue
    rig.animation_data.action=action
    samples=[]
    previous_normal=None
    for frame in range(round(action.frame_range[1])+1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        torso=rig.pose.bones['mixamorig:Spine2'].matrix
        shield_rotation=torso.to_quaternion() @ rest['mixamorig:Spine2'].to_quaternion().inverted()
        matrix=(shield_rotation @ wrist_in_shield).to_matrix().to_4x4()
        matrix.translation=hand.head
        hand.matrix=matrix
        for name,q in finger_rotations.items():rig.pose.bones[name].rotation_quaternion=q
        bpy.context.view_layer.update()
        # The authored shield wall faces forward; only the hand follows its grip.
        matrix=shield_rotation.to_matrix().to_4x4()
        matrix.translation=hand.head+hand.matrix.to_3x3() @ Vector((0,.025,0))
        rig.pose.bones['GripLeft'].matrix=matrix
        bpy.context.view_layer.update()
        samples.append({name:rig.pose.bones[name].matrix_basis.decompose() for name in ['mixamorig:LeftHand','GripLeft',*finger_rotations]})
    for frame,values in enumerate(samples):
        for name,(location,rotation,scale_vec) in values.items():
            pb=rig.pose.bones[name]
            pb.location,pb.rotation_quaternion,pb.scale=location,rotation,scale_vec
            for prop in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=prop,frame=frame,group=name)
    print('SHIELD_GRIP',action.name,flush=True)
rig.animation_data.action=bpy.data.actions['idle_spear']
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for obj in (rig,body):obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/warrior.blend'))
for action in base_actions:
    if '|' in action.name:bpy.data.actions.remove(action)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/warrior.glb'),export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
    export_def_bones=False,export_yup=True,export_image_format='AUTO')
(ROOT/'assets/animation_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('PACK_READY',flush=True)
