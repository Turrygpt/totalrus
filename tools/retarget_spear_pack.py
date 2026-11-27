"""Retarget downloaded spear attacks without transferring bone scale or stretch."""
import bpy, json, math
from pathlib import Path
from mathutils import Matrix, Vector, Quaternion
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/warrior.blend'))
rig=bpy.data.objects['WarriorRig']; body=bpy.data.objects['WarriorBody']; scene=bpy.context.scene
scene.render.fps=30
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
rig.animation_data.action=bpy.data.actions['combat_spear'];scene.frame_set(0);bpy.context.view_layer.update()
guard={b.name:b.matrix.copy() for b in rig.pose.bones}
guard_basis={b.name:b.matrix_basis.decompose() for b in rig.pose.bones}
socket_offsets={name:guard[rig.pose.bones[name].parent.name].inverted()@guard[name] for name in ['GripRight','GripLeft','SwordBelt']}
fingers={b.name:b.matrix_basis.copy() for b in rig.pose.bones if 'Hand' in b.name and b.name not in ['mixamorig:RightHand','mixamorig:LeftHand']}
rig.animation_data.action=bpy.data.actions['pack_idle_sword'];scene.frame_set(0);bpy.context.view_layer.update()
for b in rig.pose.bones:
    if b.name.startswith('mixamorig:RightHand') and b.name!='mixamorig:RightHand': fingers[b.name]=b.matrix_basis.copy()
# The shaft crosses the curled fingers, not the wrist/back of the palm.
grip_center=Vector((-.002,.044,.024))
socket_offsets['GripRight'].translation=grip_center
before=set(bpy.data.objects); before_actions=set(bpy.data.actions)
bpy.ops.import_scene.fbx(filepath=str(next((ROOT/'art/source/spear_pack').glob('*.fbx'))))
imported=set(bpy.data.objects)-before;src=next(o for o in imported if o.type=='ARMATURE')
source_actions=sorted(set(bpy.data.actions)-before_actions,key=lambda a:a.name)
corrections={}
for b in rig.pose.bones:
    if b.name not in src.pose.bones:continue
    sr=(src.matrix_world@src.data.bones[b.name].matrix_local).to_quaternion();tr=rest[b.name].to_quaternion()
    alignment=(tr@Vector((0,1,0))).rotation_difference(sr@Vector((0,1,0)))
    corrections[b.name]=sr.inverted()@alignment@tr
src_root=src.matrix_world@src.data.bones['mixamorig:Hips'].head_local
scale=rest['mixamorig:Hips'].translation.z/src_root.z
manifest=json.loads((ROOT/'assets/animation_manifest.json').read_text())
report={}
def aim(bone,direction):
    q=bone.matrix.to_quaternion()
    q=(q@Vector((0,1,0))).rotation_difference(direction.normalized())@q
    m=q.to_matrix().to_4x4();m.translation=bone.head;bone.matrix=m
    bpy.context.view_layer.update()
def solve_right(target):
    upper=rig.pose.bones['mixamorig:RightArm'];lower=rig.pose.bones['mixamorig:RightForeArm']
    start=upper.head.copy();delta=target-start;direction=delta.normalized()
    distance=min(delta.length,(upper.bone.length+lower.bone.length)*.97)
    pole=Vector((-.45,.03,.58))-start;pole=(pole-direction*pole.dot(direction)).normalized()
    along=(upper.bone.length**2-lower.bone.length**2+distance**2)/(2*distance)
    elbow=start+direction*along+pole*math.sqrt(max(0,upper.bone.length**2-along**2))
    aim(upper,elbow-start);aim(lower,start+direction*distance-lower.head)
for number,source in enumerate(source_actions,1):
    name=f'spear_pack_attack_{number}'
    if name in bpy.data.actions:bpy.data.actions.remove(bpy.data.actions[name])
    src.animation_data.action=source
    lo,hi=source.frame_range;lo+=12;hi=min(hi,lo+42);count=round(hi-lo)
    samples=[];hands=[]
    for frame in range(count+1):
        rig.animation_data.action=None;scene.frame_set(int(lo)+frame);bpy.context.view_layer.update()
        desired={};bases={}
        for b in rig.pose.bones:
            parent=b.parent
            base=desired[parent.name]@rest[parent.name].inverted()@rest[b.name] if parent else rest[b.name]
            if b.name in corrections:
                source_pose=src.matrix_world@src.pose.bones[b.name].matrix
                q=source_pose.to_quaternion()@corrections[b.name]
                m=q.to_matrix().to_4x4();m.translation=base.translation
                if b.name=='mixamorig:Hips':m.translation.z=source_pose.translation.z*scale
            else:m=base.copy()
            # A shield-bearing left arm retains its grip while the torso shifts weight.
            if b.name.startswith('mixamorig:Left') and not any(part in b.name for part in ['UpLeg','Leg','Foot','Toe']):
                m=desired['mixamorig:Spine2']@guard['mixamorig:Spine2'].inverted()@guard[b.name]
            if b.name in fingers:m=base@fingers[b.name]
            if b.name in socket_offsets:m=desired[parent.name]@socket_offsets[b.name]
            desired[b.name]=m
            bases[b.name]=(base.inverted()@m).decompose()
        hand_source=desired['mixamorig:RightHand'].translation.copy()
        for bone_name,(loc,q,s) in bases.items():
            b=rig.pose.bones[bone_name];b.rotation_mode='QUATERNION'
            original_loc,original_q,_=guard_basis[bone_name]
            # Keep the source weight shift, but avoid torsion through the mail torso.
            influence=.55 if any(p in bone_name for p in ['UpLeg','Leg','Foot','Toe']) else .28
            if bone_name in ['mixamorig:Neck','mixamorig:Head']:influence=.15
            b.location=original_loc.lerp(loc,.4) if bone_name=='mixamorig:Hips' else original_loc
            b.rotation_quaternion=original_q.slerp(q,influence);b.scale=Vector((1,1,1))
        bpy.context.view_layer.update()
        # Use the downloaded thrust's timing, retaining a practical one-handed lane
        # beside the shield. No hand or forearm scaling is used to reach the target.
        reach=max(0,min(1,(-hand_source.y-.045)/.30))
        solve_right(Vector((-.18,-.105-.245*reach,.67+.035*reach+(0.035 if number==2 else 0))))
        shaft=Vector((-.015,-1,.015 if number==1 else -.025)).normalized()
        across=Vector((1,0,0));up=shaft.cross(across).normalized()
        grip_q=Matrix((up.cross(shaft),up,shaft)).transposed().to_quaternion()
        hand=rig.pose.bones['mixamorig:RightHand']
        m=(grip_q@socket_offsets['GripRight'].to_quaternion().inverted()).to_matrix().to_4x4();m.translation=hand.head
        hand.matrix=m;bpy.context.view_layer.update()
        rig.pose.bones['GripRight'].matrix=hand.matrix@socket_offsets['GripRight']
        for bone_name,value in fingers.items():rig.pose.bones[bone_name].matrix_basis=value
        bpy.context.view_layer.update()
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
        sole=min((evaluated.matrix_world@v.co).z for v in mesh.vertices)
        evaluated.to_mesh_clear()
        hips=rig.pose.bones['mixamorig:Hips'];m=hips.matrix.copy()
        m.translation+=rig.matrix_world.inverted().to_3x3()@Vector((0,0,-sole))
        hips.matrix=m;bpy.context.view_layer.update()
        samples.append({b.name:(b.location.copy(),b.rotation_quaternion.copy(),Vector((1,1,1))) for b in rig.pose.bones})
        hands.append(list(rig.pose.bones['GripRight'].matrix.translation))
    action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
    previous={}
    for frame,values in enumerate(samples):
        for bone_name,(loc,q,s) in values.items():
            q.normalize()
            if bone_name in previous:q.make_compatible(previous[bone_name])
            previous[bone_name]=q.copy()
            b=rig.pose.bones[bone_name];b.location=loc;b.rotation_quaternion=q;b.scale=s
            for prop in ['location','rotation_quaternion','scale']:b.keyframe_insert(data_path=prop,frame=frame,group=bone_name)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    impact=min(range(len(hands)),key=lambda i:hands[i][1])/30
    manifest[name]={'duration':count/30,'loop':False,'source':source.name,'impact':impact}
    report[name]={'hands':hands,'impact':impact}
    print('SPEAR_RETARGET',name,count/30,impact,flush=True)
for obj in imported:bpy.data.objects.remove(obj,do_unlink=True)
for a in source_actions:bpy.data.actions.remove(a)
# Apply the same palm position to carrying, guarding, thrusting and throwing.
# The authored release still opens the fingers; the sword clips retain their grip.
grip_clips=[a for a in bpy.data.actions if '|' not in a.name and
            (a.name.endswith('_spear') or a.name.startswith('spear_pack_') or a.name in ['throw_spear','guard_front','guard_rear','guard_enter','guard_exit'])]
for action in grip_clips:
    rig.animation_data.action=action
    frames=[]
    for frame in range(round(action.frame_range[1])+1):
        scene.frame_set(frame);bpy.context.view_layer.update()
        hand=rig.pose.bones['mixamorig:RightHand']
        grip=rig.pose.bones['GripRight'];m=grip.matrix.copy();m.translation=hand.matrix@grip_center;grip.matrix=m
        opening=max(0,min(1,(frame/30-.76)/.14)) if action.name=='throw_spear' else 0
        for bone_name,value in fingers.items():
            if not bone_name.startswith('mixamorig:RightHand'):continue
            b=rig.pose.bones[bone_name]
            b.rotation_quaternion=value.to_quaternion().slerp(b.rotation_quaternion,opening)
        bpy.context.view_layer.update()
        frames.append({b.name:b.matrix_basis.decompose() for b in rig.pose.bones if b.name=='GripRight' or b.name.startswith('mixamorig:RightHand') and b.name!='mixamorig:RightHand'})
    previous={}
    for frame,values in enumerate(frames):
        for bone_name,(loc,q,s) in values.items():
            if bone_name in previous:q.make_compatible(previous[bone_name])
            previous[bone_name]=q.copy()
            b=rig.pose.bones[bone_name];b.location=loc;b.rotation_quaternion=q;b.scale=s
            for prop in ['location','rotation_quaternion','scale']:b.keyframe_insert(data_path=prop,frame=frame,group=bone_name)
rig.animation_data.action=bpy.data.actions['motion_idle_spear'];scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig,body]:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/warrior.blend'))
for a in list(bpy.data.actions):
    if '|' in a.name:bpy.data.actions.remove(a)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/warrior.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_def_bones=False,export_yup=True,export_image_format='AUTO')
(ROOT/'assets/animation_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(ROOT/'build/spear_pack_retarget.json').write_text(json.dumps(report,indent=2))
print('SPEAR_PACK_READY',flush=True)
