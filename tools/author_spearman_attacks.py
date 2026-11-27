"""Author a separate, editable spear-and-shield animation library in Blender.

blender --background --python tools/author_spearman_attacks.py
All coordinates below are in the original one-metre rig; its object scale is 1.8.
The production warrior and game assets are intentionally not overwritten.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/spearman_attacks_10'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/warrior.blend'))
rig = bpy.data.objects['WarriorRig']
body = bpy.data.objects['WarriorBody']
scene = bpy.context.scene
scene.render.fps = 30
P = rig.pose.bones
def bone(name): return P['mixamorig:' + name]
def update(): bpy.context.view_layer.update()

rig.animation_data.action = bpy.data.actions['combat_spear']
scene.frame_set(0); update()
base = {b.name: b.matrix_basis.copy() for b in P}
world = {b.name: b.matrix.copy() for b in P}
socket_offsets = {name: world[P[name].parent.name].inverted() @ world[name]
                  for name in ['GripRight', 'GripLeft', 'SwordBelt']}
socket_offsets['GripRight'].translation = Vector((-.002, .044, .024))
foot_q = {s: world['mixamorig:' + s + 'Foot'].to_quaternion() for s in ['Left', 'Right']}
left_hand_q = world['mixamorig:LeftHand'].to_quaternion()
rig.animation_data.action = bpy.data.actions['spear_pack_attack_1']
scene.frame_set(0); update()
for b in P:
    if b.name.startswith('mixamorig:RightHand') and b.name != 'mixamorig:RightHand':
        base[b.name] = b.matrix_basis.copy()
rig.animation_data.action = None
for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)

def rotate_world(b, q, pos=None):
    m = q.to_matrix().to_4x4()
    m.translation = b.head if pos is None else pos
    b.matrix = m
    update()

def aim_bone(b, direction):
    # Start from the reference roll every frame; never accumulate axial twist.
    q = world[b.name].to_quaternion()
    q = (q @ Vector((0, 1, 0))).rotation_difference(direction.normalized()) @ q
    rotate_world(b, q)

max_reach_error = 0.0
def limb(side, kind, target, pole):
    global max_reach_error
    upper = bone(side + ('Arm' if kind == 'arm' else 'UpLeg'))
    lower = bone(side + ('ForeArm' if kind == 'arm' else 'Leg'))
    start = upper.head.copy()
    delta = Vector(target) - start
    a, b = upper.bone.length, lower.bone.length
    dist = max(abs(a-b)+.0001, min(delta.length, (a+b)*.985))
    max_reach_error = max(max_reach_error, abs(delta.length-dist))
    direction = delta.normalized()
    bend = Vector(pole)-start
    bend = (bend-direction*bend.dot(direction)).normalized()
    along = (a*a-b*b+dist*dist)/(2*dist)
    elbow = start + direction*along + bend*math.sqrt(max(0, a*a-along*along))
    aim_bone(upper, elbow-start)
    aim_bone(lower, start+direction*dist-lower.head)

def shaft_q(direction):
    z = Vector(direction).normalized()
    y = z.cross(Vector((1,0,0))).normalized()
    return Matrix((y.cross(z), y, z)).transposed().to_quaternion()

# A shared left-foot-forward guard. Hip/foot shifts are local and return to zero.
DEFAULT = dict(hip=(0,0,0), yaw=-.09, lean=.025, twist=0,
               hand=(-.225,.015,.685), aim=(0,-1,.045),
               lf=(0,0,0), rf=(0,0,0), shield=(0,0,0),
               shield_yaw=0, breath=0, carry=0)
def state(**kw): return dict(DEFAULT, **kw)
G = state()
def key(frame, **kw): return (frame, state(**kw))

CLIPS = [
 dict(id='01_quick_jab', label='Быстрый укол', end=30, impacts=[10],
      keys=[(0,G),key(5,hand=(-.23,.07,.685),hip=(0,.012,-.003),twist=-.045),
            key(10,hand=(-.205,-.31,.70),hip=(0,-.045,-.008),yaw=.08,lean=.075,twist=.06),
            key(12,hand=(-.208,-.30,.70),hip=(0,-.043,-.008),yaw=.075,lean=.07),
            key(20,hand=(-.235,-.085,.685),hip=(0,.008,-.005),yaw=-.10),(30,G)]),
 dict(id='02_power_lunge', label='Силовой выпад с шагом', end=46, impacts=[17],
      keys=[(0,G),key(9,hand=(-.235,.035,.69),hip=(-.015,.035,-.025),yaw=-.24,twist=-.08),
            key(13,hand=(-.08,-.15,.70),hip=(0,-.045,-.02),lf=(0,-.055,.028),yaw=-.02,lean=.08,shield=(.06,0,0)),
            key(17,hand=(-.03,-.30,.715),hip=(.015,-.105,-.025),lf=(0,-.10,0),yaw=.19,lean=.13,twist=.07,shield=(.06,0,0)),
            key(20,hand=(-.03,-.27,.71),hip=(.015,-.095,-.027),lf=(0,-.10,0),yaw=.17,lean=.11,shield=(.06,0,0)),
            key(24,hand=(-.06,-.05,.70),hip=(.005,-.04,-.018),lf=(0,-.10,0),yaw=.10,shield=(.06,0,0)),
            key(29,hand=(-.235,-.06,.68),hip=(0,-.025,-.018),lf=(0,-.10,0),yaw=-.1),
            key(36,lf=(0,-.05,.035),hip=(0,0,-.012)),(46,G)]),
 dict(id='03_high_thrust', label='Укол в верхний уровень', end=38, impacts=[14],
      keys=[(0,G),key(8,hand=(-.23,-.045,.765),aim=(0,-1,.12),hip=(-.008,.01,-.008),yaw=-.15),
            key(14,hand=(-.20,-.305,.785),aim=(.02,-1,.075),hip=(.008,-.05,-.006),yaw=.10,lean=.055,twist=.05,shield=(0,-.005,.025)),
            key(17,hand=(-.205,-.29,.78),aim=(.02,-1,.08),hip=(.008,-.045,-.006),yaw=.08,shield=(0,0,.025)),
            key(26,hand=(-.235,-.08,.735),aim=(0,-1,.08)),(38,G)]),
 dict(id='04_low_thrust', label='Укол в нижний уровень', end=42, impacts=[16],
      keys=[(0,G),key(9,hand=(-.235,-.005,.62),aim=(0,-1,-.12),hip=(0,.02,-.035),yaw=-.17,shield=(0,0,-.015)),
            key(16,hand=(-.21,-.34,.57),aim=(.015,-1,-.18),hip=(.01,-.06,-.06),yaw=.12,lean=.11,twist=.04,shield=(0,-.015,-.025)),
            key(19,hand=(-.215,-.32,.575),aim=(.015,-1,-.17),hip=(.01,-.052,-.057),yaw=.11,lean=.09,shield=(0,0,-.025)),
            key(29,hand=(-.23,-.07,.63),aim=(0,-1,-.05),hip=(0,.008,-.025)),(42,G)]),
 dict(id='05_outside_thrust', label='Укол справа по диагонали', end=40, impacts=[15],
      keys=[(0,G),key(8,hand=(-.255,-.01,.685),aim=(-.14,-1,.02),hip=(-.018,.015,-.01),yaw=-.23),
            key(15,hand=(-.29,-.295,.69),aim=(-.20,-1,.025),hip=(-.025,-.055,-.02),yaw=-.03,lean=.08,twist=.09,shield=(.005,0,0)),
            key(18,hand=(-.28,-.28,.685),aim=(-.18,-1,.025),hip=(-.02,-.05,-.02),yaw=-.05,lean=.07),
            key(28,hand=(-.25,-.075,.68),aim=(-.06,-1,.04),hip=(-.01,0,-.01)),(40,G)]),
 dict(id='06_inside_thrust', label='Укол к центру мимо щита', end=40, impacts=[15],
      keys=[(0,G),key(8,hand=(-.245,.015,.715),aim=(.06,-1,.04),hip=(-.01,.018,-.01),yaw=-.20),
            key(15,hand=(-.185,-.33,.73),aim=(.10,-1,.015),hip=(.015,-.06,-.018),yaw=.19,lean=.085,twist=.07,shield=(.035,0,.015),shield_yaw=.06),
            key(18,hand=(-.19,-.305,.73),aim=(.08,-1,.02),hip=(.01,-.05,-.015),yaw=.15,shield=(.03,0,.015)),
            key(28,hand=(-.23,-.06,.70),aim=(.04,-1,.03),yaw=-.07),(40,G)]),
 dict(id='07_descending_thrust', label='Укол сверху вниз', end=46, impacts=[19],
      keys=[(0,G),key(7,hand=(-.245,-.02,.76),aim=(0,-1,.12),hip=(-.01,.015,-.01),yaw=-.17),
            key(13,hand=(-.22,-.065,.835),aim=(.015,-1,-.03),hip=(0,.005,.005),yaw=-.17,shield=(0,-.01,.03)),
            key(19,hand=(-.20,-.315,.765),aim=(.015,-1,-.23),hip=(.01,-.055,-.022),yaw=.13,lean=.10,shield=(0,-.015,.01)),
            key(22,hand=(-.21,-.30,.75),aim=(.015,-1,-.22),hip=(.01,-.05,-.025),yaw=.12,lean=.08),
            key(33,hand=(-.235,-.065,.72),aim=(0,-1,-.02),hip=(0,.01,-.01)),(46,G)]),
 dict(id='08_retreat_counter', label='Оттяжка и ответный укол', end=50, impacts=[25],
      keys=[(0,G),key(8,hand=(-.23,.03,.68),hip=(-.01,.075,-.035),rf=(0,.07,.025),yaw=-.18,shield=(0,.02,.015)),
            key(14,hand=(-.235,.055,.685),hip=(-.01,.09,-.035),rf=(0,.105,0),yaw=-.23,shield=(0,.015,.02)),
            key(25,hand=(-.205,-.32,.705),hip=(.01,-.055,-.015),rf=(0,.105,0),yaw=.14,lean=.09,twist=.04,shield=(0,-.01,0)),
            key(28,hand=(-.21,-.30,.70),hip=(.01,-.05,-.018),rf=(0,.105,0),yaw=.11,lean=.07),
            key(36,hand=(-.23,-.07,.68),hip=(0,.005,-.015),rf=(0,.105,0)),
            key(42,rf=(0,.05,.035),hip=(0,.005,-.01)),(50,G)]),
 dict(id='09_double_jab', label='Двойной укол', end=56, impacts=[12,28],
      keys=[(0,G),key(6,hand=(-.235,-.035,.69),hip=(0,.015,-.008),yaw=-.16),
            key(12,hand=(-.205,-.305,.715),hip=(0,-.045,-.012),yaw=.08,lean=.07),
            key(15,hand=(-.21,-.28,.71),hip=(0,-.035,-.015),yaw=.06),
            key(21,hand=(-.24,.005,.66),aim=(0,-1,-.04),hip=(-.008,.015,-.018),yaw=-.19),
            key(28,hand=(-.21,-.345,.65),aim=(.02,-1,-.035),hip=(.01,-.065,-.033),yaw=.16,lean=.095,twist=.055),
            key(31,hand=(-.215,-.32,.655),aim=(.02,-1,-.03),hip=(.01,-.06,-.03),yaw=.13,lean=.08),
            key(42,hand=(-.235,-.07,.675),hip=(0,.008,-.01)),(56,G)]),
 dict(id='10_high_feint_low', label='Финт вверх и укол вниз', end=58, impacts=[30],
      keys=[(0,G),key(6,hand=(-.23,-.055,.74),aim=(0,-1,.10),yaw=-.15,hip=(0,.015,-.008)),
            key(12,hand=(-.215,-.23,.785),aim=(.01,-1,.12),hip=(0,-.025,-.008),yaw=.025,lean=.05),
            key(16,hand=(-.24,.09,.77),aim=(0,-1,.12),hip=(0,.015,-.015),yaw=-.13),
            key(20,hand=(-.24,.015,.645),aim=(0,-1,-.08),hip=(-.01,.025,-.035),yaw=-.20),
            key(30,hand=(-.21,-.34,.57),aim=(.015,-1,-.18),hip=(.01,-.065,-.06),yaw=.15,lean=.11,shield=(0,-.01,-.015)),
            key(33,hand=(-.215,-.315,.575),aim=(.015,-1,-.17),hip=(.01,-.055,-.055),yaw=.12,lean=.085),
            key(44,hand=(-.235,-.055,.635),aim=(0,-1,-.035),hip=(0,.012,-.025)),(58,G)])
]

def interpolate(keys, frame):
    for (fa,a),(fb,b) in zip(keys, keys[1:]):
        if frame <= fb:
            t=max(0,min(1,(frame-fa)/(fb-fa))); t=t*t*(3-2*t)
            return {k: tuple((1-t)*x+t*y for x,y in zip(a[k],b[k])) if isinstance(a[k],tuple)
                    else (1-t)*a[k]+t*b[k] for k in a}
    return keys[-1][1]

def pose(s):
    for b in P:
        b.rotation_mode='QUATERNION'; b.matrix_basis=base[b.name]; b.scale=(1,1,1)
    update()
    hip=Vector((.002,0,.455))+Vector(s['hip'])+Vector((0,0,s['breath']))
    pelvis_q=Quaternion((0,0,1),s['yaw'])
    rotate_world(bone('Hips'),pelvis_q @ world['mixamorig:Hips'].to_quaternion(),hip)
    # Lower the pelvis when a long stance would otherwise pull a planted foot.
    drop=0
    for side,origin,offset in [('Left',(.105,-.145,.0605),s['lf']),('Right',(-.12,.125,.0605),s['rf'])]:
        target=Vector(origin)+Vector(offset)
        delta=bone(side+'UpLeg').head-target
        reach=(bone(side+'UpLeg').bone.length+bone(side+'Leg').bone.length)*.975
        max_z=math.sqrt(max(.001,reach*reach-delta.x*delta.x-delta.y*delta.y))
        drop=max(drop,delta.z-max_z)
    if drop>0:
        hip.z-=drop
        rotate_world(bone('Hips'),pelvis_q @ world['mixamorig:Hips'].to_quaternion(),hip)
    for name,weight in [('Spine',.40),('Spine1',.35),('Spine2',.25)]:
        b=bone(name)
        q=Quaternion((0,0,1),s['twist']*weight) @ Quaternion((1,0,0),s['lean']*weight) @ b.matrix.to_quaternion()
        rotate_world(b,q)
    # Head stays directed towards the opponent while the chest turns.
    rotate_world(bone('Neck'), Quaternion((0,0,1),s['yaw']*.25) @ world['mixamorig:Neck'].to_quaternion())
    rotate_world(bone('Head'), Quaternion((0,0,1),s['yaw']*.10) @ world['mixamorig:Head'].to_quaternion())
    for side,origin,offset in [('Left',(.105,-.145,.0605),s['lf']),('Right',(-.12,.125,.0605),s['rf'])]:
        target=Vector(origin)+Vector(offset)
        pole=Vector((.13 if side=='Left' else -.145,-.40,.27))
        limb(side,'leg',target,pole)
        rotate_world(bone(side+'Foot'),foot_q[side])
    limb('Right','arm',Vector(s['hand']),Vector((-.43,.05,.65)))
    q=shaft_q(s['aim'])
    rotate_world(bone('RightHand'),q @ socket_offsets['GripRight'].to_quaternion().inverted())
    P['GripRight'].matrix=bone('RightHand').matrix @ socket_offsets['GripRight']; update()
    # A compact shield guard; maintain the original handle-to-palm transform.
    torso_shift=bone('Spine2').head-world['mixamorig:Spine2'].translation
    shield_target=Vector((.13,-.19,.65))+Vector(s['shield'])+Vector((torso_shift.x*.35,torso_shift.y*.48,torso_shift.z*.50))
    if s['carry']:
        shield_target=shield_target.lerp(Vector((.17,-.10,.58)),s['carry'])
    limb('Left','arm',shield_target,Vector((.37,.025,.58)))
    rotate_world(bone('LeftHand'),Quaternion((0,0,1),s['shield_yaw']+s['yaw']*.12) @ left_hand_q)
    P['GripLeft'].matrix=bone('LeftHand').matrix @ socket_offsets['GripLeft']
    P['SwordBelt'].matrix=bone('Hips').matrix @ socket_offsets['SwordBelt']
    update()

def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves

# A real opposing guard makes shield contacts and exposed target lanes reviewable.
# It is a static reference, not another exported animation library.
pose(G)
reference=bpy.data.collections.new('REFERENCE OPPONENT - targeting');scene.collection.children.link(reference)
defender=rig.copy();defender.data=rig.data.copy();defender.name='Reference_DefenderRig'
defender.animation_data_clear();reference.objects.link(defender)
defender.matrix_world=Matrix.Translation((0,-1.85,0)) @ Matrix.Rotation(math.pi,4,'Z') @ rig.matrix_world
defender.hide_render=False
def_body=body.copy();def_body.name='Reference_DefenderBody';reference.objects.link(def_body)
def_body.parent=defender
for modifier in def_body.modifiers:
    if modifier.type=='ARMATURE':modifier.object=defender
def_shield=bpy.data.objects['shield'].copy();def_shield.name='Reference_DefenderShield';reference.objects.link(def_shield)
for constraint in def_shield.constraints:
    if getattr(constraint,'target',None)==rig:constraint.target=defender
def_shield.data=def_shield.data.copy()
for index,original in enumerate(def_shield.data.materials):
    mat=original.copy();mat.name='Reference blue shield'
    node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    tint=mat.node_tree.nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=.72;tint.inputs[2].default_value=(.25,.52,.95,1)
    if node.inputs['Base Color'].links:
        link=node.inputs['Base Color'].links[0];mat.node_tree.links.new(link.from_socket,tint.inputs[1])
    else:tint.inputs[1].default_value=node.inputs['Base Color'].default_value
    mat.node_tree.links.new(tint.outputs[0],node.inputs['Base Color']);def_shield.data.materials[index]=mat
update()
from mathutils.bvhtree import BVHTree
def world_bvh(obj):
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
    tree=BVHTree.FromPolygons([evaluated.matrix_world@v.co for v in mesh.vertices],[list(p.vertices) for p in mesh.polygons])
    evaluated.to_mesh_clear();return tree
body_tree=world_bvh(def_body);shield_tree=world_bvh(def_shield)
print('DEFENDER_TRANSFORMS',list(defender.matrix_world.translation),[list(v) for v in def_body.matrix_world],flush=True)
target_specs={
 'shield_center':('shield',-.30,1.16,'В щит'),
 'shield_edge':('shield',-.49,1.09,'В край щита'),
 'flank':('body',.18,1.12,'В открытый бок'),
 'head':('body',0,1.55,'Над щитом — голова'),
 'shin':('body',-.18,.30,'Под щитом — голень'),
 'upper_arm':('body',.35,1.25,'В открытое плечо'),
 'shoulder':('body',.22,1.30,'Сверху — открытое плечо'),
 'counter_arm':('body',.30,1.23,'Ответ в открытую руку'),
 'knee':('body',-.16,.48,'Под щитом — колено'),
}
targets={}
for zone,(kind,x,z,label) in target_specs.items():
    tree=shield_tree if kind=='shield' else body_tree
    hit=tree.ray_cast(Vector((x,1,z)),Vector((0,-1,0)),5)[0]
    if hit is None:raise RuntimeError('Missing target surface: '+zone)
    targets[zone]={'point':hit+Vector((0,.004,0)),'kind':kind,'label':label}
tip_vertex=max(bpy.data.objects['spear'].data.vertices,key=lambda v:v.co.z).co.copy()
# Fixed hand-to-socket offset and the unscaled equipment mesh yield a rigid tip radius.
tip_vector=socket_offsets['GripRight'].to_quaternion().inverted() @ (socket_offsets['GripRight'].translation*1.8)+tip_vertex
tip_radius=tip_vector.length
def fit_wrist_to_target(wrist,shoulder,target):
    """Nearest point on the tip sphere, also within the unstretched arm's reach."""
    w=target+(wrist-target).normalized()*tip_radius
    reach=(bone('RightArm').bone.length+bone('RightForeArm').bone.length)*1.8*.975
    if (w-shoulder).length>reach:
        d=(target-shoulder).length;axis=(target-shoulder).normalized()
        if d>tip_radius+reach:raise RuntimeError('Target beyond arm+spear reach: '+str(d))
        along=(reach*reach-tip_radius*tip_radius+d*d)/(2*d)
        center=shoulder+axis*along
        radial=wrist-center;radial-=axis*radial.dot(axis)
        if radial.length<.0001:radial=Vector((-1,0,0))
        w=center+radial.normalized()*math.sqrt(max(0,reach*reach-along*along))
    return w
TARGET_PLAN={
 '01_quick_jab':[(10,'shield_center')],
 '02_power_lunge':[(17,'flank')],
 '03_high_thrust':[(14,'head')],
 '04_low_thrust':[(16,'shin')],
 '05_outside_thrust':[(15,'upper_arm')],
 '06_inside_thrust':[(15,'shield_edge')],
 '07_descending_thrust':[(19,'shoulder')],
 '08_retreat_counter':[(25,'counter_arm')],
 '09_double_jab':[(12,'shield_center'),(28,'knee')],
 '10_high_feint_low':[(12,'head'),(30,'shin')],
}
def target_keys(clip):
    result=[];plan=TARGET_PLAN[clip['id']]
    for frame,original in clip['keys']:
        s=dict(original)
        if frame in [0,clip['end']]:result.append((frame,dict(G)));continue
        contact,zone=min(plan,key=lambda pair:abs(pair[0]-frame))
        if clip['id']=='10_high_feint_low' and frame>=20:contact,zone=plan[-1]
        target=targets[zone]['point'].copy()
        pose(s)
        wrist=rig.matrix_world@bone('RightHand').head
        shoulder=rig.matrix_world@bone('RightArm').head
        direction=(target-wrist).normalized()
        near_contact=0<=frame-contact<=3
        if near_contact:
            retreat=.055 if frame>contact else .0
            if clip['id']=='10_high_feint_low' and contact==12:retreat=.22
            desired=target-direction*retreat
            for attempt in range(5):
                reach=(bone('RightArm').bone.length+bone('RightForeArm').bone.length)*1.8*.975
                excess=(desired-shoulder).length-(tip_radius+reach-.008)
                if excess<=0:break
                shift=desired-shoulder;shift.z=0;shift.normalize()
                s['hip']=tuple(Vector(s['hip'])+shift*(excess+.012)/1.8)
                pose(s);wrist=rig.matrix_world@bone('RightHand').head;shoulder=rig.matrix_world@bone('RightArm').head
            wrist=fit_wrist_to_target(wrist,shoulder,desired)
            s['hand']=tuple(rig.matrix_world.inverted()@wrist)
            direction=(desired-wrist).normalized()
        elif frame>max(f for f,z in plan)+5:
            # Retract before lowering back to the common straight guard lane.
            s['hand']=(s['hand'][0],max(.015,s['hand'][1]),s['hand'][2])
            pose(s);wrist=rig.matrix_world@bone('RightHand').head
            direction=(target-wrist).normalized()
        q=shaft_q(direction)
        q=(q@tip_vector).rotation_difference(direction*tip_radius)@q
        s['aim']=tuple(q@Vector((0,0,1)))
        result.append((frame,s))
    return result

manifest={'fps':30,'rig':'WarriorRig','forward':'-Y','up':'Z','root_motion':False,
          'description':'Spear and shield; common guard; planted feet except explicitly animated steps.', 'clips':{}}
manifest['targeting']={'defender_position':[0,-1.85,0],'mix':'Shield contacts, exposed body targets, and shield-to-knee combination.',
 'zones':{z:{'position':list(v['point']),'kind':v['kind'],'label':v['label']} for z,v in targets.items()}}
checks={}
actions=[]
def bake(name,label,end,keys,impacts=(),loop=False,kind='attack'):
    global max_reach_error
    max_reach_error=0
    samples=[]; diagnostics=[]
    rig.animation_data.action=None
    for frame in range(end+1):
        scene.frame_set(frame)
        s=interpolate(keys,frame);pose(s)
        samples.append({b.name:(b.location.copy(),b.rotation_quaternion.copy(),Vector((1,1,1))) for b in P})
        diagnostics.append({'frame':frame,'left_foot':list(bone('LeftFoot').head),'right_foot':list(bone('RightFoot').head),'grip':list(P['GripRight'].head),'shaft':list(P['GripRight'].matrix.to_quaternion() @ Vector((0,0,1)))})
    action=bpy.data.actions.new(name);action.use_fake_user=True
    action['label_ru']=label;action['loop']=loop;action['impact_frames']=list(impacts)
    action['source']='Authored spear-and-shield motion on the original WarriorRig'
    rig.animation_data.action=action
    previous={}
    for frame,values in enumerate(samples):
        for n,(loc,q,scale) in values.items():
            if n in previous:q.make_compatible(previous[n])
            previous[n]=q.copy()
            b=P[n];b.location=loc;b.rotation_quaternion=q;b.scale=scale
            for prop in ['location','rotation_quaternion','scale']:
                b.keyframe_insert(data_path=prop,frame=frame,group=n)
    for curve in curves(action):
        for point in curve.keyframe_points:point.interpolation='LINEAR'
    for label_,f in [('GUARD',0),('RECOVERED',end)]+[('CONTACT_%02d'%(i+1),f) for i,f in enumerate(impacts)]:
        marker=action.pose_markers.new(label_);marker.frame=f
    action.asset_mark()
    if action.asset_data:
        action.asset_data.description=label+' | guard, anticipation, contact, recovery | 30 fps'
    manifest['clips'][name]={'label':label,'duration':end/30,'frames':[0,end],'impact_frames':list(impacts),'impact_seconds':[f/30 for f in impacts],'loop':loop,'kind':kind}
    if kind=='attack':
        endpoint=max((samples[0][n][0]-samples[-1][n][0]).length for n in samples[0])
        checks[name]={'endpoint_position_error':endpoint,'max_requested_reach_clamp':max_reach_error,'samples':diagnostics}
    actions.append(action)
    print('AUTHORED',name,end,'REACH_CLAMP',round(max_reach_error,6),flush=True)
    return action

guard_keys=[(0,G),key(15,breath=.002,hand=(-.225,.015,.687)),key(30,breath=0),key(45,breath=-.0015,hand=(-.225,.015,.6835)),(60,G)]
bake('spear_ready_loop','Боевая стойка',60,guard_keys,loop=True,kind='stance')
carry=state(hip=(0,0,.035),yaw=0,lean=0,hand=(-.205,-.07,.61),aim=(0,-.15,1),lf=(0,.135,0),rf=(.015,-.105,0),carry=1)
enter_keys=[(0,carry),key(7,hip=(0,.025,.015),yaw=-.04,hand=(-.22,-.06,.65),aim=(0,-.55,.75),lf=(0,.065,.035),rf=(.015,-.105,0),carry=.5),
            key(15,hip=(0,.015,-.008),yaw=-.08,hand=(-.225,.02,.68),aim=(0,-1,.15),rf=(.008,-.055,.025)),(24,G)]
bake('spear_guard_enter','Вход в боевую стойку',24,enter_keys,kind='transition')
bake('spear_guard_exit','Выход из боевой стойки',24,[(24-f,s) for f,s in reversed(enter_keys)],kind='transition')
for clip in CLIPS:
    name='spear_attack_'+clip['id']
    plan=TARGET_PLAN[clip['id']]
    target_label='Щит → колено' if clip['id']=='09_double_jab' else ('Финт вверх → голень' if clip['id']=='10_high_feint_low' else targets[plan[-1][1]]['label'])
    labels={'01_quick_jab':'Быстрый укол в щит','02_power_lunge':'Выпад в открытый бок','03_high_thrust':'Укол над щитом',
            '04_low_thrust':'Укол под щитом','05_outside_thrust':'Диагональный укол в плечо','06_inside_thrust':'Удар по краю щита',
            '07_descending_thrust':'Укол сверху в плечо','08_retreat_counter':'Оттяжка и ответный укол','09_double_jab':'Щит — перевод в колено','10_high_feint_low':'Финт вверх — укол вниз'}
    action=bake(name,labels[clip['id']],clip['end'],target_keys(clip),clip['impacts'])
    manifest['clips'][name]['target_description']=target_label
    manifest['clips'][name]['targets']=[{'frame':frame,'zone':zone,'kind':targets[zone]['kind'],'position':list(targets[zone]['point']),'feint':frame not in clip['impacts']} for frame,zone in plan]
    action['targets']=json.dumps(manifest['clips'][name]['targets'],ensure_ascii=False)

# Keep only this library in the dedicated review file; original source is untouched.
rig.animation_data.action=None
for action in list(bpy.data.actions):
    if action not in actions:bpy.data.actions.remove(action)
track=rig.animation_data.nla_tracks.new();track.name='SPEAR / 10 ATTACKS / REVIEW'
cursor=1
for action in [bpy.data.actions['spear_guard_enter'],bpy.data.actions['spear_ready_loop']]+[a for a in actions if a.name.startswith('spear_attack_')]+[bpy.data.actions['spear_guard_exit']]:
    strip=track.strips.new(action.name,cursor,action)
    strip.action_frame_start=0;strip.action_frame_end=action.frame_range[1]
    strip.blend_type='REPLACE';strip.extrapolation='HOLD_FORWARD'
    label=manifest['clips'][action.name]['label']
    marker=scene.timeline_markers.new(action.name+' | '+label,frame=cursor)
    entry=manifest['clips'][action.name];entry['showcase_start']=cursor
    for i,impact in enumerate(entry['impact_frames']):
        scene.timeline_markers.new('CONTACT '+action.name+' '+str(i+1),frame=cursor+impact)
    cursor+=int(action.frame_range[1])+10
scene.frame_start=1;scene.frame_end=cursor-10

# Neutral review stage and three-quarter view, with the spear silhouetted clear of the body.
stage=bpy.data.collections.new('REVIEW STAGE');scene.collection.children.link(stage)
def move_to_stage(obj):
    for c in list(obj.users_collection):c.objects.unlink(obj)
    stage.objects.link(obj)
def material(name,color,metal=0,rough=.75):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    node=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value=(*color,1);node.inputs['Metallic'].default_value=metal;node.inputs['Roughness'].default_value=rough
    return m
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.018))
ground=bpy.context.object;ground.name='Review ground';move_to_stage(ground)
ground.data.materials.append(material('Review floor',(.045,.06,.075)))
bpy.ops.object.camera_add(location=(5.8,-3.7,3.25))
camera=bpy.context.object;camera.name='Review Camera';move_to_stage(camera)
target=Vector((0,-.86,.85));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=4.1;scene.camera=camera
for name,loc,energy,size in [('Key',(-3,-4,6),700,5),('Fill',(4,-1,3),450,4),('Rim',(0,3,5),900,3)]:
    data=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,data);stage.objects.link(o)
    o.location=loc;o.rotation_euler=(Vector((0,0,.9))-o.location).to_track_quat('-Z','Y').to_euler();data.energy=energy;data.shape='DISK';data.size=size
if scene.world is None:scene.world=bpy.data.worlds.new('Review world')
scene.world.color=(.12,.12,.12)
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=960;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.render.film_transparent=False

readme='''SPEARMAN / TEN STRIKES\n\nOriginal character: art/warrior.blend. 30 fps.\nSpacebar plays the complete NLA review. Timeline markers identify each clip and contact.\n\n13 Actions: 10 attacks, ready_loop, guard_enter, guard_exit.\nAll attacks start and end in the same left-foot-forward guard.\nEquipment stays attached to the original GripRight, GripLeft and SwordBelt bones.\nNo bone scaling, no object root motion. Steps return to their original footprint.\n\nTo edit one clip: mute the REVIEW NLA track and choose its Action in the Action Editor.\nContact timings are recorded in action pose markers and the JSON manifest.\nDouble jab has two contacts; high feint has one damage contact.\nGame animation selection and crowd bakes are separate and have not been replaced.\n\n'''+ '\n'.join(a.name+' : '+manifest['clips'][a.name]['label'] for a in actions)
bpy.data.texts.new('READ ME - SPEAR LIBRARY').write(readme)
script_text=bpy.data.texts.new('author_spearman_attacks.py');script_text.write(Path(__file__).read_text(encoding='utf-8'))
scene['library']='10 spear strikes + guard enter / loop / exit'
rig.show_in_front=False
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
scene.frame_set(1);update()
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
        elif area.type=='DOPESHEET_EDITOR' and area.spaces.active.mode=='TIMELINE':
            area.type='NLA_EDITOR'
for image in bpy.data.images:
    if image.size[0]>0 and not image.packed_file:
        try:image.pack()
        except RuntimeError:pass
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/spearman_attacks_10.blend'))
(OUT/'animation_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
(OUT/'authoring_checks.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
(OUT/'README.txt').write_text(readme,encoding='utf-8')
print('SPEARMAN_LIBRARY_SAVED',flush=True)
if '--no-render' in sys.argv:
    sys.exit(0)

# Selected inspection frames; renders never alter the saved timeline setup.
track.mute=True
for name,frame in [('spear_ready_loop',0),('spear_attack_02_power_lunge',17),('spear_attack_07_descending_thrust',19),('spear_attack_04_low_thrust',16)]:
    rig.animation_data.action=bpy.data.actions[name];scene.frame_set(frame);update()
    scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('PREVIEW_FRAMES_SAVED',flush=True)
