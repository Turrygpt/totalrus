"""Fit the downloaded prince to the existing rigs; keep all original assets intact.

Blender --background --python-exit-code 1 --python tools/prepare_prince.py
The cape is an editable, UV-mapped grid. Godot's prince_cloth.gd simulates it.
FactionEmbroidery is an independent material/UV island on the body.
"""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from archer_face_weights import stabilize_face
from mounted_rider_motion import deform_bone
from prepare_horseman import HORSE_SCALE, SEAT, reset_pose, use_action

OUT = ROOT / 'assets/prince'
SOURCE = ROOT / 'art/source/prince/download.glb'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.parent.mkdir(parents=True, exist_ok=True)
if not SOURCE.exists():
    shutil.copy2(Path.home() / 'Downloads/medieval warrior 3d model.glb', SOURCE)


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def material(name, color, roughness=.9, metal=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metal
    mat.use_backface_culling = False
    return mat


def surface(name, vertices, faces, uvs, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop in poly.loop_indices:
            uv.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def bind(obj, rig, bone=None):
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Identity(4)
    modifier = obj.modifiers.new('Prince skeleton', 'ARMATURE')
    modifier.object = rig
    if bone:
        obj.vertex_groups.new(name=bone).add(range(len(obj.data.vertices)), 1, 'REPLACE')


def transfer_skin(source, target):
    source.data.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in source.data.loop_triangles]
    positions = [v.co.copy() for v in source.data.vertices]
    bvh = BVHTree.FromPolygons(positions, tris, all_triangles=True)
    groups = [target.vertex_groups.new(name=g.name) for g in source.vertex_groups]
    errors = []
    for vertex in target.data.vertices:
        point, normal, index, distance = bvh.find_nearest(vertex.co)
        errors.append(distance)
        triangle = tris[index]
        weights = barycentric_transform(point, *(positions[i] for i in triangle),
                                        Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        result = {}
        for source_index, factor in zip(triangle, weights):
            for group in source.data.vertices[source_index].groups:
                result[group.group] = result.get(group.group, 0) + group.weight * max(0, factor)
        result = sorted(result.items(), key=lambda x: x[1], reverse=True)[:4]
        total = sum(weight for _, weight in result)
        assert total > 0
        for index, weight in result:
            if weight > .00001:
                groups[index].add([vertex.index], weight / total, 'REPLACE')
    return {'max_transfer_distance_m': max(errors) * 1.8,
            'mean_transfer_distance_m': sum(errors) / len(errors) * 1.8}


def chest_panel(body, rig):
    # Ray-fit the linen panel to the mail, leaving a 3 mm separation in game.
    body.data.calc_loop_triangles()
    tree = BVHTree.FromPolygons([v.co for v in body.data.vertices],
                               [tuple(t.vertices) for t in body.data.loop_triangles], all_triangles=True)
    vertices, faces, uv = [], [], []
    nx, ny = 10, 12
    for j in range(ny + 1):
        v = j / ny
        z = .600 + .150 * v
        half = .066 * (1 if v > .23 else .58 + v * 1.83)
        for i in range(nx + 1):
            u = i / nx
            x = .006 + (u * 2 - 1) * half
            hit = tree.ray_cast(Vector((x, -.5, z)), Vector((0, 1, 0)))[0]
            y = hit.y if hit else -.065
            vertices.append((x, y - .0025, z))
            uv.append((u, v))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    panel = surface('FactionChest', vertices, faces, uv,
                    material('FactionEmbroidery', (.10, .13, .17)))
    transfer_skin(body, panel)
    bind(panel, rig)
    # Joining retains the panel's separate material and complete 0..1 UV island.
    select([body, panel])
    bpy.ops.object.join()


def cape(rig, body):
    vertices, uvs, faces = [], [], []
    body.data.calc_loop_triangles()
    shoulder_surface = BVHTree.FromPolygons([v.co for v in body.data.vertices],
        [tuple(t.vertices) for t in body.data.loop_triangles], all_triangles=True)
    nx, ny = 16, 22
    for j in range(ny + 1):
        t = j / ny
        for i in range(nx + 1):
            u = i / nx
            side = abs(u * 2 - 1)
            width = .34 + .20 * math.sin(t * math.pi / 2)
            x = (u - .5) * width
            y = .118 - .020 * side ** 2 * (1 - t) ** 3 + .045 * t
            y += .017 * math.cos(u * math.pi * 10) * (.2 + .8 * t)
            z = .810 - .575 * t - .041 * side * (1 - t) + .018 * side * t
            if t < .12:
                contact, normal, _, _ = shoulder_surface.ray_cast(Vector((x, .4, z)), Vector((0, -1, 0)))
                if contact is None:
                    contact, normal, _, _ = shoulder_surface.find_nearest(Vector((x, .09, z)))
                fitted = contact + normal * .0045
                blend = (1 - t / .12) ** 2
                x, y, z = Vector((x, y, z)).lerp(fitted, blend)
            vertices.append((x, y, z))
            uvs.append((u, 1 - t))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + nx + 1, a + nx + 2, a + 1))
    obj = surface('PrinceCloak', vertices, faces, uvs,
                  material('Prince blue wool', (.055, .092, .145), .96))
    bind(obj, rig, 'mixamorig:Spine2')
    obj['cloth_columns'] = nx + 1
    obj['cloth_rows'] = ny + 1
    obj['runtime'] = 'res://scripts/prince_cloth.gd; shoulder edge pinned; world-space Verlet cloth'
    return obj


def export(path, objects, animations=True):
    select(objects)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_animations=animations, export_animation_mode='ACTIONS',
                              export_force_sampling=True, export_frame_range=False,
                              export_def_bones=False, export_yup=True, export_extras=True)


def pack_save(path):
    for image in bpy.data.images:
        if image.size[0] and not image.packed_file:
            image.pack()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(path))


def foot():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(ROOT / 'art/warrior.blend'), link=False) as (_, target):
        target.objects = ['WarriorRig', 'WarriorBody']
        target.actions = [name for name in _.actions if '|' not in name]
    rig, reference = target.objects
    for obj in (rig, reference):
        bpy.context.collection.objects.link(obj)
    rig.name = 'PrinceRig'
    rig.animation_data_clear()
    reset_pose(rig)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    body = next(o for o in bpy.context.selected_objects if o.type == 'MESH')
    body.name = 'PrinceBody'
    stats = transfer_skin(reference, body)
    # The helmet, aventail, beard and face move together. Blend below the beard.
    stabilize_face(body, lambda point: (.808, .848))
    bind(body, rig)
    chest_panel(body, rig)
    cloak = cape(rig, body)
    bpy.data.objects.remove(reference, do_unlink=True)
    for action in list(bpy.data.actions):
        if '|' in action.name:
            bpy.data.actions.remove(action)
        else:
            action.use_fake_user = True
    rig.animation_data_create()
    action = bpy.data.actions.get('motion_idle_spear') or bpy.data.actions.get('idle_spear')
    use_action(rig, action)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_set(0)
    pack_save(ROOT / 'art/prince.blend')
    export(OUT / 'prince_foot.glb', [rig, body, cloak])
    stats['source_sha256'] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    stats['body_vertices'] = len(body.data.vertices)
    stats['cape_vertices'] = len(cloak.data.vertices)
    stats['foot_actions'] = len(bpy.data.actions)
    return stats


def mounted():
    # Reuse the exact horse, tack, controls and clips already in the game.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/horseman_quaternius.glb'))
    horse = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    originals = set(bpy.data.actions)
    old = bpy.data.objects['Mounted warrior']
    with bpy.data.libraries.load(str(ROOT / 'art/prince.blend'), link=False) as (_, target):
        target.objects = ['PrinceRig', 'PrinceBody', 'PrinceCloak']
    rig, body, cloak = target.objects
    for obj in (rig, body, cloak):
        bpy.context.collection.objects.link(obj)
    rig.animation_data_clear()
    reset_pose(rig)

    def bone(name):
        return rig.pose.bones['mixamorig:' + name]

    def aim(name, direction):
        pb = bone(name)
        current = pb.matrix.to_quaternion()
        rotation = (current @ Vector((0, 1, 0))).rotation_difference(Vector(direction).normalized())
        matrix = (rotation @ current).to_matrix().to_4x4()
        matrix.translation = pb.head
        pb.matrix = matrix
        bpy.context.view_layer.update()

    aim('Spine', (0, -.11, 1))
    for side, sign in [('Left', 1), ('Right', -1)]:
        for name, direction in [('UpLeg', (sign * .54, -.36, -.76)),
                                ('Leg', (sign * -.04, .44, -.90)), ('Foot', (0, -1, -.12)),
                                ('ToeBase', (0, -1, 0)), ('Arm', (sign * .39, .15 if sign < 0 else -.16, -1)),
                                ('ForeArm', (sign * -.21, -1, .36 if sign < 0 else -.06)),
                                ('Hand', (sign * -.14, -1, -.08))]:
            aim(side + name, direction)
    fit = .95 / HORSE_SCALE
    origin = SEAT - (rig.matrix_world @ bone('Hips').head) * fit
    new_objects = []
    for source, name in [(body, 'PrinceBody'), (cloak, 'PrinceCloak')]:
        evaluated = source.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = bpy.data.meshes.new_from_object(evaluated)
        assert len(mesh.vertices) == len(source.data.vertices)
        mesh.transform(Matrix.Translation(origin) @ Matrix.Scale(fit, 4) @ source.matrix_world)
        if name == 'PrinceCloak':
            # Rest the riding cape over the croup. A vertical bind pose would start
            # inside the horse and let a two-sided collider choose the wrong side.
            shoulders = [v.co.copy() for v in list(mesh.vertices)[:17]]
            for vertex in mesh.vertices:
                t = (vertex.index // 17) / 22
                shoulder = shoulders[vertex.index % 17]
                angle = .50 + .90 * t
                length = .575 * 1.8 * .95 / HORSE_SCALE
                vertex.co.y = shoulder.y + length * (math.cos(.50) - math.cos(angle)) / .90
                vertex.co.z = shoulder.z - length * (math.sin(angle) - math.sin(.50)) / .90
        obj = bpy.data.objects.new(name + '_Mounted', mesh)
        bpy.context.collection.objects.link(obj)
        groups = {}
        for v in source.data.vertices:
            weights = {}
            for w in v.groups:
                key = deform_bone(source.vertex_groups[w.group].name)
                weights[key] = weights.get(key, 0) + w.weight
            for key, value in weights.items():
                if key not in groups:
                    groups[key] = obj.vertex_groups.new(name=key)
                groups[key].add([v.index], value, 'REPLACE')
        bind(obj, horse)
        new_objects.append(obj)
    for obj in (rig, body, cloak, old):
        bpy.data.objects.remove(obj, do_unlink=True)
    new_objects[0].name = 'PrinceBody'
    new_objects[1].name = 'PrinceCloak'
    for action in list(bpy.data.actions):
        if action not in originals:
            bpy.data.actions.remove(action)
    use_action(horse, bpy.data.actions['Idle'])
    bpy.context.scene.frame_set(0)
    pack_save(ROOT / 'art/prince_mounted.blend')
    export(OUT / 'prince_mounted.glb', [horse] + [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.parent == horse])
    return {'mounted_actions': len(originals), 'mounted_body_vertices': len(new_objects[0].data.vertices)}


if __name__ == '__main__':
    report = foot() if '--mounted-only' not in sys.argv else json.loads((OUT / 'authoring.json').read_text())
    report.update(mounted())
    (OUT / 'authoring.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('PRINCE_ASSETS_READY', json.dumps(report), flush=True)
