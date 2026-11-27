"""Add a short bow/knife victory pose to the editable archer."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/archer.blend'))
rig=bpy.data.objects['ArcherRig'];scene=bpy.context.scene
if bpy.data.actions.get('bow_victory'):bpy.data.actions.remove(bpy.data.actions['bow_victory'])
rig.animation_data.action=bpy.data.actions['bow_idle'];scene.frame_set(0);bpy.context.view_layer.update()
reference={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
hands={side:rig.pose.bones['mixamorig:'+side+'Hand'].head.copy() for side in ['Left','Right']}
wrists={side:rig.pose.bones['mixamorig:'+side+'Hand'].matrix.to_quaternion() for side in ['Left','Right']}
def aim(pb,direction):
    q=pb.matrix.to_quaternion();q=(q@Vector((0,1,0))).rotation_difference(direction.normalized())@q
    m=q.to_matrix().to_4x4();m.translation=pb.head;pb.matrix=m;bpy.context.view_layer.update()
def limb(side,target):
    a=rig.pose.bones['mixamorig:'+side+'Arm'];b=rig.pose.bones['mixamorig:'+side+'ForeArm']
    start=a.head.copy();v=target-start;distance=min(v.length,(a.bone.length+b.bone.length)*.995);direction=v.normalized()
    pole=Vector((.4 if side=='Left' else -.4,.03,.85))-start
    pole=(pole-direction*pole.dot(direction)).normalized()
    along=(a.bone.length**2-b.bone.length**2+distance**2)/(2*distance)
    elbow=start+direction*along+pole*math.sqrt(max(0,a.bone.length**2-along**2))
    aim(a,elbow-start);aim(b,target-b.head)
samples=[]
rig.animation_data.action=None
for frame in range(85):
    t=frame/30;lift=min(1,t/.55,max(0,(2.8-t)/.65));lift=lift*lift*(3-2*lift)
    for name,matrix in reference.items():rig.pose.bones[name].matrix_basis=matrix
    bpy.context.view_layer.update()
    for side,sign,socket in [('Left',1,'GripLeft'),('Right',-1,'GripRight')]:
        target=hands[side].lerp(Vector((sign*.20,-.06,1.02+math.sin(t*9)*.012)),lift)
        limb(side,target)
        hand=rig.pose.bones['mixamorig:'+side+'Hand']
        q=wrists[side].slerp(Quaternion(Vector((1,0,1)).normalized(),math.pi),lift)
        m=q.to_matrix().to_4x4();m.translation=hand.head;hand.matrix=m;bpy.context.view_layer.update()
        q=Quaternion((0,0,1),math.pi/2) if side=='Left' else hand.matrix.to_quaternion()@Quaternion(Vector((1,0,1)).normalized(),math.pi)
        m=q.to_matrix().to_4x4();m.translation=hand.head+hand.matrix.to_3x3()@Vector((0,.025,0))
        rig.pose.bones[socket].matrix=m;bpy.context.view_layer.update()
    samples.append({b.name:b.matrix_basis.decompose() for b in rig.pose.bones})
action=bpy.data.actions.new('bow_victory');action.use_fake_user=True;rig.animation_data.action=action
for frame,values in enumerate(samples):
    for name,(loc,rot,scale) in values.items():
        b=rig.pose.bones[name];b.location,b.rotation_quaternion,b.scale=loc,rot,scale
        for prop in ['location','rotation_quaternion','scale']:b.keyframe_insert(data_path=prop,frame=frame,group=name)
rig.animation_data.action=bpy.data.actions['bow_idle'];scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/archer.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig,bpy.data.objects['ArcherBody']]:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/archer.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_def_bones=False,export_yup=True)
manifest=json.loads((ROOT/'assets/archer_animations.json').read_text());manifest['bow_victory']={'duration':2.8,'source':'authored two-arm cheer'}
(ROOT/'assets/archer_animations.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
