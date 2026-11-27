"""Prepare the supplied bowman, separated weapons and retargeted longbow clips."""
import bpy,bmesh,json,math,sys
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from archer_face_weights import stabilize_face, level_archer_head
SOURCE=ROOT/'art/source'
ASSETS=ROOT/'assets'
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def export(name,objects,animations=False):
    select(objects)
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(name+'.glb')),export_format='GLB',use_selection=True,
        export_animations=animations,export_animation_mode='ACTIONS',export_force_sampling=True,
        export_def_bones=False,export_yup=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(Path.home()/'Downloads/archery weapon 3d model.glb'))
original=next(o for o in bpy.context.scene.objects if o.type=='MESH')
original.data.transform(original.matrix_world)
original.matrix_world=Matrix.Identity(4)
weapons={}
for name,lo,hi,origin,scale,faces in [
    ('bow',-1,-.30,(-.468,0,.385),2.0,2400),
    ('quiver',-.30,0,(-.12,0,.20),1.6,2200),
    ('arrow',0,.30,(.190,0,.015),1.65,400),
    ('knife',.30,1,(.465,0,.07),1.5,700),
]:
    mesh=original.data.copy()
    bm=bmesh.new();bm.from_mesh(mesh)
    remove=[v for v in bm.verts if not lo<=v.co.x<hi or (name=='bow' and v.co.x>-.36 and .085<v.co.z<.685)]
    bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(mesh);bm.free()
    for v in mesh.vertices:v.co=(v.co-Vector(origin))*scale
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    select([o]);mod=o.modifiers.new('Game budget','DECIMATE');mod.ratio=min(1,faces/max(1,len(mesh.polygons)))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for mat in o.data.materials:
        for n in mat.node_tree.nodes:
            if n.type=='BSDF_PRINCIPLED':n.inputs['Roughness'].default_value=.88
    export(name,[o]);weapons[name]=o
    print('WEAPON',name,len(o.data.polygons),flush=True)
bpy.data.objects.remove(original,do_unlink=True)
for o in weapons.values():o.hide_set(True)

bpy.ops.import_scene.fbx(filepath=str(next((SOURCE/'bowman').glob('*.fbx'))))
old=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
body=next(o for o in old.children if o.type=='MESH')
bpy.context.view_layer.update()
body.data.transform(body.matrix_world)
body.parent=None;body.matrix_world=Matrix.Identity(4)
body.modifiers.clear();body.name='ArcherBody'
data=bpy.data.armatures.new('ArcherRig');rig=bpy.data.objects.new('ArcherRig',data);bpy.context.collection.objects.link(rig)
select([rig]);bpy.ops.object.mode_set(mode='EDIT')
for b in old.data.bones:
    nb=data.edit_bones.new(b.name);nb.head=old.matrix_world@b.head_local;nb.tail=old.matrix_world@b.tail_local
    nb.align_roll((old.matrix_world@b.matrix_local).to_3x3().col[2])
    if b.parent:nb.parent=data.edit_bones[b.parent.name]
for name,parent in [('GripRight','RightHand'),('GripLeft','LeftHand'),('SwordBelt','Hips'),('QuiverBack','Spine2'),('BowBack','Spine2')]:
    b=data.edit_bones.new(name);b.head=data.edit_bones['mixamorig:'+parent].head;b.tail=b.head+Vector((0,0,.06));b.parent=data.edit_bones['mixamorig:'+parent];b.use_deform=False
bpy.ops.object.mode_set(mode='OBJECT')
bpy.data.objects.remove(old,do_unlink=True)
body.parent=rig;mod=body.modifiers.new('Archer skin','ARMATURE');mod.object=rig
stabilize_face(body)
rig.animation_data_create()
rest={b.name:b.matrix_local.copy() for b in data.bones}
rig.scale=(1.8,)*3
clips={
    'standing idle 01.fbx':'bow_idle','standing draw arrow.fbx':'bow_draw',
    'standing aim overdraw.fbx':'bow_aim','standing aim recoil.fbx':'bow_release',
    'standing walk forward.fbx':'bow_walk','standing run forward.fbx':'bow_run',
    'standing walk back.fbx':'bow_backstep','standing run back.fbx':'bow_retreat',
    'standing run left.fbx':'bow_left','standing run right.fbx':'bow_right',
    'standing react small from front.fbx':'bow_hit',
    'standing death backward 01.fbx':'bow_death','standing death forward 01.fbx':'bow_death_front',
}
extra={'sword and shield idle.fbx':'knife_idle','sword and shield attack (4).fbx':'knife_attack',
       'sword and shield run.fbx':'knife_run','draw sword 1.fbx':'knife_draw'}
manifest={}
for filename,name in list(clips.items())+list(extra.items()):
    pack=SOURCE/('longbow_pack' if filename in clips else 'sword_shield_pack')
    before=set(bpy.data.objects);bpy.ops.import_scene.fbx(filepath=str(pack/filename))
    imported=set(bpy.data.objects)-before;src=next(o for o in imported if o.type=='ARMATURE')
    action=src.animation_data.action;start,end=action.frame_range;count=round(end-start)
    corrections={}
    for pb in rig.pose.bones:
        if pb.name not in src.pose.bones:continue
        qs=(src.matrix_world@src.data.bones[pb.name].matrix_local).to_quaternion();qt=rest[pb.name].to_quaternion()
        align=(qt@Vector((0,1,0))).rotation_difference(qs@Vector((0,1,0)))
        corrections[pb.name]=qs.inverted()@align@qt
    root=src.matrix_world@src.data.bones['mixamorig:Hips'].head_local
    scale=rest['mixamorig:Hips'].translation.z/root.z
    samples=[];hands=[]
    for f in range(count+1):
        rig.animation_data.action=None;scene=bpy.context.scene;scene.render.fps=30;scene.frame_set(int(start)+f);bpy.context.view_layer.update()
        desired={};bases={}
        for pb in rig.pose.bones:
            par=pb.parent;base=desired[par.name]@rest[par.name].inverted()@rest[pb.name] if par else rest[pb.name]
            if pb.name in corrections:
                source=src.matrix_world@src.pose.bones[pb.name].matrix
                m=(source.to_quaternion()@corrections[pb.name]).to_matrix().to_4x4();m.translation=base.translation
                if pb.name=='mixamorig:Hips':m.translation.z=source.translation.z*scale
            elif pb.name=='GripRight':
                hand=desired[par.name];q=hand.to_quaternion()@Quaternion(Vector((1,0,1)).normalized(),math.pi)
                m=q.to_matrix().to_4x4();m.translation=hand.translation+hand.to_3x3()@Vector((0,.025,0))
            elif pb.name=='GripLeft':
                hand=desired[par.name];m=Matrix.Rotation(math.pi/2,4,'Z');m.translation=hand.translation+hand.to_3x3()@Vector((0,.025,0))
            else:
                torso=desired[par.name]@rest[par.name].inverted()
                if pb.name=='SwordBelt':pos=Vector((.12,.035,.52));q=Quaternion((1,0,0),math.pi)
                elif pb.name=='QuiverBack':pos=Vector((-.04,.10,.66));q=Quaternion((0,1,0),-.25)
                else:pos=Vector((.06,.12,.65));q=Quaternion((0,1,0),.35)
                m=torso@q.to_matrix().to_4x4();m.translation=torso@pos
            desired[pb.name]=m;bases[pb.name]=(base.inverted()@m).decompose()
        samples.append(bases)
        if f%5==0:hands.append([f,list(desired['GripLeft'].translation),list(desired['GripRight'].translation)])
    baked=bpy.data.actions.new(name);baked.use_fake_user=True;rig.animation_data.action=baked
    for f,values in enumerate(samples):
        for bn,(loc,rot,scl) in values.items():
            pb=rig.pose.bones[bn];pb.rotation_mode='QUATERNION';pb.location,pb.rotation_quaternion,pb.scale=loc,rot,scl
            for prop in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=prop,frame=f,group=bn)
    for o in imported:bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.actions.remove(action)
    manifest[name]={'duration':count/30,'source':filename,'hand_samples':hands}
    print('ARCHER CLIP',name,count/30,flush=True)
for image in bpy.data.images:
    if image.size[0]>2048:image.scale(2048,2048)
    if image.size[0]>0:image.pack()
rig.animation_data.action=bpy.data.actions['bow_idle'];bpy.context.scene.frame_set(0)
for name,o in weapons.items():
    o.hide_set(False)
    socket={'bow':'GripLeft','quiver':'QuiverBack','arrow':'GripRight','knife':'SwordBelt'}[name]
    for kind in ['COPY_LOCATION','COPY_ROTATION']:
        c=o.constraints.new(kind);c.target=rig;c.subtarget=socket
level_archer_head(rig)
rig.animation_data.action = bpy.data.actions["bow_idle"]
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/archer.blend'))
export('archer',[rig,body],True)
(ASSETS/'archer_animations.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('ARCHER_READY',flush=True)
