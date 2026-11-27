"""Build the editable Blender character and Godot assets from the supplied downloads.

Run with Blender --background --python tools/prepare_assets.py.
"""
import json
import math
import zipfile
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
SOURCE = ROOT / 'art'
DOWNLOADS = Path.home() / 'Downloads'
ASSETS.mkdir(exist_ok=True)
SOURCE.mkdir(exist_ok=True)
unpacked = SOURCE / 'source'
unpacked.mkdir(exist_ok=True)
for archive in ('tripo_convert_94e20a7d-90a1-493c-bd17-e67a0d750f9f.zip', 'medieval weapon 3d model.zip'):
    with zipfile.ZipFile(DOWNLOADS / archive) as contents:
        contents.extractall(unpacked)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(unpacked / 'medieval_weapon_3d_model.fbx'))
weapon_source = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.update()
weapon_source.data.transform(weapon_source.matrix_world)
weapon_source.matrix_world = Matrix.Identity(4)
weapon_mesh = weapon_source.data.copy()
weapon_material = weapon_source.data.materials[0]
for shader_node in weapon_material.node_tree.nodes:
    if shader_node.type == 'BSDF_PRINCIPLED':
        shader_node.inputs['Roughness'].default_value = .82
        shader_node.inputs['Metallic'].default_value = .12

def export_selected(path, animations=False):
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_animations=animations, export_animation_mode='ACTIONS',
                              export_force_sampling=True, export_def_bones=False,
                              export_yup=True, export_image_format='AUTO')

def select_only(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

weapons = {}
for name in ('spear', 'sword', 'shield'):
    mesh = weapon_mesh.copy()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    def belongs(v):
        if name == 'spear':
            return v.co.x < -.30
        if name == 'sword':
            return -.30 <= v.co.x < -.08
        return v.co.x >= -.08
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not belongs(v)], context='VERTS')
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if name == 'spear':
        origin, scale = Vector((-.413, -.009, .43)), 2.3
    elif name == 'sword':
        origin, scale = Vector((-.1795, -.009, .556)), 1.55
    else:
        # Origin at the wrapped rear handle, offset from the shield's centre boss.
        origin, scale = Vector((.197, .045, .260)) + Vector((-.120,-.045,.025))/1.48, 1.48
    for v in mesh.vertices:
        v.co = (v.co - origin) * scale
        if name == 'sword':
            v.co.x = -v.co.x
            v.co.z = -v.co.z
            v.co = Quaternion((0,0,1), math.pi / 2) @ v.co
    # Small details in the source weapons are needlessly expensive at squad distance.
    modifier = obj.modifiers.new('Game mesh', 'DECIMATE')
    modifier.ratio = .45
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    export_selected(ASSETS / (name + '.glb'))
    weapons[name] = obj

bpy.data.objects.remove(weapon_source, do_unlink=True)
for obj in weapons.values():
    obj.hide_set(True)

bpy.ops.import_scene.fbx(filepath=str(unpacked / 'tripo_convert_94e20a7d-90a1-493c-bd17-e67a0d750f9f.fbx'))
armature = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
body = next(o for o in armature.children if o.type == 'MESH')
armature.name = 'WarriorRig'
body.name = 'WarriorBody'
# A semantic head mask in UV2 lets the game vary hair without tinting clothes or armour.
hair_uv = body.data.uv_layers.get('HairRegion') or body.data.uv_layers.new(name='HairRegion')
for loop in body.data.loops:
    z = body.data.vertices[loop.vertex_index].co.z
    weight = max(0.0, min(1.0, (z - .805) / .025))
    hair_uv.data[loop.index].uv = (weight * weight * (3.0 - 2.0 * weight), 0.0)
original_actions = list(bpy.data.actions)
walk_source = next(a for a in original_actions if 'walk.' in a.name)
for action in original_actions:
    action.use_fake_user = True

select_only([armature])
bpy.ops.object.mode_set(mode='EDIT')
for name, parent in [('GripRight', 'RightHand'), ('GripLeft', 'LeftHand'), ('SwordBelt', 'Hips')]:
    bone = armature.data.edit_bones.new(name)
    bone.head = armature.data.edit_bones['mixamorig:' + parent].head
    bone.tail = bone.head + Vector((0, 0, .06))
    bone.parent = armature.data.edit_bones['mixamorig:' + parent]
    bone.use_deform = False
bpy.ops.object.mode_set(mode='OBJECT')
pose = armature.pose.bones
rest = {b.name: b.matrix_local.copy() for b in armature.data.bones}
for bone in pose:
    bone.rotation_mode = 'QUATERNION'

def bone(name):
    return pose['mixamorig:' + name]

def set_world_rotation(pb, rotation, location=None):
    matrix = rotation.to_matrix().to_4x4()
    matrix.translation = pb.head if location is None else location
    pb.matrix = matrix
    bpy.context.view_layer.update()

def aim_bone(pb, direction):
    base = rest[pb.name].to_quaternion()
    rest_direction = base @ Vector((0, 1, 0))
    set_world_rotation(pb, rest_direction.rotation_difference(direction.normalized()) @ base)

def limb(side, kind, target, pole):
    upper = bone(side + ('Arm' if kind == 'arm' else 'UpLeg'))
    lower = bone(side + ('ForeArm' if kind == 'arm' else 'Leg'))
    start = upper.head.copy()
    length_a, length_b = upper.bone.length, lower.bone.length
    delta = target - start
    distance = min(delta.length, (length_a + length_b) * .995)
    direction = delta.normalized()
    bend = pole - start
    bend = (bend - direction * bend.dot(direction)).normalized()
    along = (length_a ** 2 - length_b ** 2 + distance ** 2) / (2 * distance)
    height = math.sqrt(max(0, length_a ** 2 - along ** 2))
    elbow = start + direction * along + bend * height
    aim_bone(upper, elbow - start)
    aim_bone(lower, target - lower.head)

def grip_rotation(direction):
    z = Vector(direction).normalized()
    x = Vector((1, 0, 0))
    y = z.cross(x).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed().to_quaternion()

def socket(name, position, direction):
    set_world_rotation(pose[name], grip_rotation(direction), Vector(position))

def smooth_points(time, keys):
    for i in range(len(keys) - 1):
        ta, a = keys[i]
        tb, b = keys[i + 1]
        if time <= tb:
            weight = max(0, (time - ta) / (tb - ta))
            weight = weight * weight * (3 - 2 * weight)
            return Vector(a).lerp(Vector(b), weight)
    return Vector(keys[-1][1])

def fingers(side, closed):
    for digit in ('Index', 'Middle', 'Ring', 'Pinky'):
        for joint in (1, 2, 3):
            pb = bone(side + 'Hand' + digit + str(joint))
            curl_axis = rest[pb.name].to_quaternion().inverted() @ (rest['mixamorig:' + side + 'Hand'].to_quaternion() @ Vector((1,0,0)))
            pb.rotation_quaternion = Quaternion(curl_axis, closed * 1.15)

clips = {
    'idle_spear': (2.0, True), 'walk_spear': (1.2, True), 'run_spear': (.72, True),
    'idle_sword': (2.0, True), 'walk_sword': (1.2, True), 'run_sword': (.72, True),
    'guard_front': (2.0, True), 'guard_rear': (2.0, True), 'guard_sword': (2.0, True),
    'guard_enter': (.55, False), 'guard_exit': (.55, False),
    'throw_spear': (1.35, False), 'draw_sword': (1.35, False),
    'advance_spear': (1.2, True), 'advance_sword': (1.2, True),
    'combat_spear': (2.0, True), 'combat_sword': (2.0, True),
    'attack_spear': (1.10, False), 'attack_sword': (.92, False),
    'attack_sword_alt': (1.02, False), 'hit': (.48, False),
    'block': (.40, False), 'death_back': (1.65, False), 'death_side': (1.80, False),
    'backstep_spear': (1.2, True), 'strafe_left_spear': (1.2, True), 'strafe_right_spear': (1.2, True),
    'victory_spear': (2.8, False), 'victory_sword': (2.8, False),
}
authored = []
scene = bpy.context.scene
scene.render.fps = 30
for clip_name, (duration, looping) in clips.items():
    samples = []
    frame_count = round(duration * 30)
    for frame in range(frame_count + 1):
        t = frame / 30
        phase = frame / frame_count * math.tau
        walking = clip_name.startswith(('walk', 'advance', 'backstep', 'strafe'))
        running = clip_name.startswith('run')
        armature.animation_data.action = walk_source if walking else None
        for pb in pose:
            pb.matrix_basis = Matrix.Identity(4)
        if walking:
            source_frame = 1 + (frame / frame_count) * 56
            if clip_name.startswith('backstep'): source_frame = 57 - (frame / frame_count) * 56
            scene.frame_set(int(source_frame), subframe=source_frame % 1)
            bpy.context.view_layer.update()
            hips = bone('Hips')
            matrix = hips.matrix.copy()
            matrix.translation.x = rest[hips.name].translation.x
            matrix.translation.y = rest[hips.name].translation.y
            hips.matrix = matrix
        else:
            scene.frame_set(frame)
            hips = bone('Hips')
            matrix = rest[hips.name].copy()
            matrix.translation.z += .006 * math.sin(phase) if not running else .018 * math.cos(phase * 2)
            hips.matrix = matrix
        bpy.context.view_layer.update()
        if running:
            for side, sign, offset in [('Left', 1, 0), ('Right', -1, math.pi)]:
                p = phase + offset
                target = Vector((sign * .08, math.cos(p) * .19, .06 + max(0, math.sin(p)) * .12))
                limb(side, 'leg', target, Vector((sign * .09, -.35, .26)))
                set_world_rotation(bone(side + 'Foot'), rest['mixamorig:' + side + 'Foot'].to_quaternion())
        if clip_name.startswith('strafe'):
            drift = 1 if 'left' in clip_name else -1
            for side, sign, offset in [('Left',1,0),('Right',-1,math.pi)]:
                p = phase+offset
                target = Vector((sign*.08+math.cos(p)*.075*drift,-.015,.035+max(0,math.sin(p))*.045))
                limb(side,'leg',target,Vector((sign*.12,-.3,.25)))
                set_world_rotation(bone(side+'Foot'),rest['mixamorig:'+side+'Foot'].to_quaternion())
        # Keep the armed torso stable while preserving the source walk's leg motion.
        for name in ('Spine', 'Spine1', 'Spine2', 'LeftShoulder', 'RightShoulder', 'Neck', 'Head'):
            bone(name).rotation_quaternion = Quaternion()
        if clip_name == 'throw_spear':
            twist = smooth_points(t, [(0,(0,0,0)),(.4,(-.21,0,0)),(.95,(.18,0,0)),(1.35,(0,0,0))]).x
            spine_basis = rest['mixamorig:Spine'].to_quaternion()
            bone('Spine').rotation_quaternion = spine_basis.inverted() @ Quaternion((0,0,1), twist) @ spine_basis
        bpy.context.view_layer.update()
        guard = clip_name.startswith(('guard', 'advance', 'combat', 'attack', 'backstep', 'strafe')) or clip_name == 'block'
        weight = 1.0 if guard else 0.0
        if clip_name == 'guard_enter': weight = min(1.0, t / duration)
        if clip_name == 'guard_exit': weight = 1.0 - min(1.0, t / duration)
        right = Vector((-.19, -.115, .61)).lerp(Vector((-.17, -.18, .71)), weight)
        left = Vector((.17, -.10, .60)).lerp(Vector((.105, -.22, .67)), weight)
        direction = Vector((0, -.12, 1)).lerp(Vector((0, -.97, .24)), weight)
        if clip_name == 'guard_rear': direction = Vector((0, -.40, .92))
        if 'sword' in clip_name:
            direction = Vector((0, -.62, .78))
        if walking or running:
            right.z += math.sin(phase) * .015
            left.z -= math.sin(phase) * .012
        if running:
            left = Vector((.21, .015 + math.sin(phase)*.025, .51))
        if clip_name == 'throw_spear':
            right = smooth_points(t, [(0,(-.19,-.115,.61)),(.4,(-.19,.12,.84)),(.62,(-.14,.04,.88)),(.99,(-.13,-.265,.74)),(1.35,(-.19,-.115,.61))])
            direction = smooth_points(t, [(0,(0,-.12,1)),(.42,(0,-.94,.34)),(.85,(0,-.97,.24)),(1.35,(0,-.12,1))])
        if clip_name == 'draw_sword':
            right = smooth_points(t, [(0,(-.19,-.115,.61)),(.5,(.105,-.08,.60)),(.78,(.09,-.20,.68)),(1.02,(-.09,-.22,.78)),(1.35,(-.19,-.115,.61))])
            direction = smooth_points(t, [(0,(0,-.1,1)),(.5,(-.15,0,-1)),(.78,(-.15,-.15,-1)),(1.02,(0,-.9,.2)),(1.35,(0,-.62,.78))])
            left = Vector((.19,-.11,.66))
        if clip_name.startswith('combat'):
            right += Vector((0, math.sin(phase)*.006, math.sin(phase)*.004))
            left.z += math.sin(phase)*.003
        if clip_name == 'attack_spear':
            right = smooth_points(t, [(0,(-.17,-.18,.71)),(.24,(-.20,.015,.70)),(.43,(-.16,-.32,.72)),(.58,(-.16,-.32,.72)),(1.1,(-.17,-.18,.71))])
            direction = Vector((0,-1,.02))
        if clip_name == 'attack_sword':
            right = smooth_points(t, [(0,(-.17,-.18,.71)),(.25,(-.25,-.05,.83)),(.44,(.07,-.32,.65)),(.63,(.09,-.25,.60)),(.92,(-.17,-.18,.71))])
            direction = smooth_points(t, [(0,(0,-.62,.78)),(.25,(-.1,.2,1)),(.44,(.8,-.9,-.3)),(.63,(.7,-.5,-.7)),(.92,(0,-.62,.78))])
        if clip_name == 'attack_sword_alt':
            right = smooth_points(t, [(0,(-.17,-.18,.71)),(.28,(-.15,-.02,.91)),(.48,(-.11,-.32,.62)),(.7,(-.11,-.28,.60)),(1.02,(-.17,-.18,.71))])
            direction = smooth_points(t, [(0,(0,-.62,.78)),(.28,(0,.35,1)),(.48,(0,-1,-.4)),(.7,(0,-.8,-.6)),(1.02,(0,-.62,.78))])
        if clip_name.startswith('attack'):
            twist = smooth_points(t, [(0,(0,0,0)),(.24,(-.15,0,0)),(.45,(.2,0,0)),(duration,(0,0,0))]).x
            spine_basis = rest['mixamorig:Spine'].to_quaternion()
            bone('Spine').rotation_quaternion = spine_basis.inverted() @ Quaternion((0,0,1), twist) @ spine_basis
        if clip_name in ('hit','block'):
            recoil = math.sin(math.pi * min(t/duration,1))
            right = Vector((-.17,-.18,.71)) + Vector((0,.07,-.015))*recoil
            left = Vector((.105,-.22,.67)) + Vector((0,.07,.035))*recoil
            direction = Vector((0,-.92,.36))
            spine_basis = rest['mixamorig:Spine'].to_quaternion()
            bone('Spine').rotation_quaternion = spine_basis.inverted() @ Quaternion((1,0,0), -.12*recoil) @ spine_basis
        if clip_name.startswith('death'):
            right = Vector((-.20,-.13,.56))
            left = Vector((.20,-.12,.57))
            direction = Vector((0,-.32,.95))
        if clip_name.startswith('victory'):
            lift = smooth_points(t,[(0,(0,0,0)),(.55,(1,0,0)),(2.1,(1,0,0)),(2.8,(0,0,0))]).x
            cheer = math.sin(t*9)*.025*lift
            right = right.lerp(Vector((-.21,-.10,.94+cheer)),lift)
            left = left.lerp(Vector((.20,-.12,.83-cheer*.5)),lift)
            direction = direction.lerp(Vector((0,-.06,1)),lift)
        bpy.context.view_layer.update()
        elbow_pole = Vector((-.38,.04,.60))
        if clip_name == 'throw_spear':
            elbow_pole = smooth_points(t, [(0,(-.38,.04,.60)),(.4,(-.32,.08,.82)),(.99,(-.25,-.10,.79)),(1.35,(-.38,.04,.60))])
        limb('Right', 'arm', right, elbow_pole)
        limb('Left', 'arm', left, Vector((.35,.02,.56)))
        wrist_rotation = grip_rotation(direction) @ Quaternion(Vector((1,0,1)).normalized(), math.pi)
        opening = 0.0
        if clip_name == 'throw_spear':
            opening = min(1.0, max(0.0, (t - .76) / .14))
            finger_direction = (bone('RightHand').head - bone('RightForeArm').head).normalized()
            palm_side = Vector((1,0,0))
            palm_normal = palm_side.cross(finger_direction).normalized()
            palm_side = finger_direction.cross(palm_normal).normalized()
            release_rotation = Matrix((palm_side, finger_direction, palm_normal)).transposed().to_quaternion()
            recovery = 1.0 - max(0.0, (t - 1.05) / .30)
            wrist_rotation = wrist_rotation.slerp(release_rotation, opening * recovery)
        set_world_rotation(bone('RightHand'), wrist_rotation)
        set_world_rotation(bone('LeftHand'), rest['mixamorig:LeftHand'].to_quaternion())
        fingers('Right', 1.0 - opening * .92)
        fingers('Left', .8)
        bpy.context.view_layer.update()
        palm_center = bone('RightHand').head + bone('RightHand').matrix.to_3x3() @ Vector((0,.025,0))
        socket('GripRight', palm_center, direction)
        left_palm = bone('LeftHand').head + bone('LeftHand').matrix.to_3x3() @ Vector((0,.025,0))
        socket('GripLeft', left_palm, (0,0,1))
        socket('SwordBelt', (.11,-.08,.59), (-.15,0,-1))
        if clip_name.startswith('death'):
            # Transform the complete solved pose, including the equipment sockets.
            fall = max(0., min(1., (t-.10)/(duration-.3)))
            fall = fall*fall*(3-2*fall)
            hips = bone('Hips')
            matrix = hips.matrix.copy()
            axis = Vector((1,.32 if clip_name == 'death_side' else -.10,0)).normalized()
            matrix = Matrix.Translation(matrix.translation) @ Quaternion(axis,-1.52*fall).to_matrix().to_4x4() @ Matrix.Translation(-matrix.translation) @ matrix
            matrix.translation.z -= .39*fall
            matrix.translation.y += .17*fall
            hips.matrix = matrix
            bpy.context.view_layer.update()
            lowest = min(min(pb.head.z,pb.tail.z) for pb in pose if pb.name.startswith('mixamorig:'))
            if lowest < .025:
                matrix = hips.matrix.copy()
                matrix.translation.z += .025-lowest
                hips.matrix = matrix
                bpy.context.view_layer.update()
        samples.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in pose})
    armature.animation_data.action = None
    action = bpy.data.actions.new(clip_name)
    action.use_fake_user = True
    armature.animation_data.action = action
    for frame, values in enumerate(samples):
        for name, (location, rotation, scale) in values.items():
            pb = pose[name]
            pb.location, pb.rotation_quaternion, pb.scale = location, rotation, scale
            for prop in ('location', 'rotation_quaternion', 'scale'):
                pb.keyframe_insert(data_path=prop, frame=frame, group=name)
    authored.append(action)
    print('AUTHORED', clip_name, flush=True)

# Source size is one metre. Scale the complete rig, including attachments, to 1.8 m.
armature.scale = (1.8, 1.8, 1.8)
for image in bpy.data.images:
    if image.size[0] > 0:
        image.pack()
for name, obj in weapons.items():
    obj.hide_set(False)
    attachment = {'spear':'GripRight', 'shield':'GripLeft', 'sword':'SwordBelt'}[name]
    for kind in ('COPY_LOCATION', 'COPY_ROTATION'):
        constraint = obj.constraints.new(kind)
        constraint.target = armature
        constraint.subtarget = attachment

leather = bpy.data.materials.new('Scabbard leather')
leather.diffuse_color = (.031,.022,.014,1)
leather.use_nodes = True
leather_shader = next(n for n in leather.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
leather_shader.inputs['Base Color'].default_value = leather.diffuse_color
leather_shader.inputs['Roughness'].default_value = .94
for name, size, offset in [('Scabbard',(.036,.075,.90),.43),('Belt loop',(.10,.065,.12),.05)]:
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.object
    obj.name = name
    for vertex in obj.data.vertices:
        vertex.co = Vector((vertex.co.x*size[0]/2,vertex.co.y*size[1]/2,vertex.co.z*size[2]/2+offset))
    obj.data.materials.append(leather)
    for kind in ('COPY_LOCATION','COPY_ROTATION'):
        constraint = obj.constraints.new(kind)
        constraint.target = armature
        constraint.subtarget = 'SwordBelt'
armature.animation_data.action = next(a for a in authored if a.name == 'idle_spear')
scene.frame_set(0)
select_only([armature, body])
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'warrior.blend'))
for action in original_actions:
    bpy.data.actions.remove(action)
export_selected(ASSETS / 'warrior.glb', animations=True)
(ASSETS / 'animation_manifest.json').write_text(json.dumps({name: {'duration':duration, 'loop':loop} for name,(duration,loop) in clips.items()}, indent=2))
print('ASSETS_READY', flush=True)
