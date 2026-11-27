"""Split the supplied two-row model sheet into four grounded cabins."""
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'art/source/wooden log cabin 3d model.glb'))
sheet = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
sheet.data.transform(sheet.matrix_world)
sheet.matrix_world.identity()

def cabin_index(point):
    upper = point.z >= .397
    right = point.x >= (-.070 if upper else .036)
    return int(right) + (0 if upper else 2)

# Door sill and lintel measured in the 5.4 m baseline meshes. Fit the
# wall below the lintel while keeping the roof's thickness and shape.
doorways = ((.42, 2.14), (.15, 1.19), (.28, 1.69), (.435, 1.44))
for index, (sill, lintel) in enumerate(doorways):
    mesh = sheet.data.copy()
    # The four structures share the same PBR atlas. Keep their original UVs.
    edit = bmesh.new()
    edit.from_mesh(mesh)
    bmesh.ops.delete(edit, geom=[v for v in edit.verts if cabin_index(v.co) != index], context='VERTS')
    edit.to_mesh(mesh)
    edit.free()
    cabin = bpy.data.objects.new(f'Cabin{index + 1:02d}', mesh)
    bpy.context.collection.objects.link(cabin)
    vertices = mesh.vertices
    minimum = Vector(tuple(min(v.co[i] for v in vertices) for i in range(3)))
    maximum = Vector(tuple(max(v.co[i] for v in vertices) for i in range(3)))
    origin = (minimum + maximum) / 2
    origin.z = minimum.z
    scale = 5.4 / max((maximum - minimum).xy)
    for vertex in vertices:
        vertex.co = (vertex.co - origin) * scale
    bpy.context.view_layer.objects.active = cabin
    decimate = cabin.modifiers.new('Cabin mesh budget', 'DECIMATE')
    decimate.ratio = min(1, 1800 / len(mesh.polygons))
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    floor = min(v.co.z for v in cabin.data.vertices)
    new_sill, door_height = .15, 1.95
    for vertex in cabin.data.vertices:
        z = vertex.co.z - floor
        if z < sill:
            vertex.co.z = z * new_sill / sill
        elif z < lintel:
            vertex.co.z = new_sill + (z - sill) * door_height / (lintel - sill)
        else:
            vertex.co.z = z + new_sill + door_height - lintel
    print(cabin.name, len(cabin.data.polygons), 'triangles; floor', min(v.co.z for v in cabin.data.vertices), flush=True)
bpy.data.objects.remove(sheet, do_unlink=True)
for texture in bpy.data.images:
    width, height = texture.size
    if max(width, height) > 2048:
        scale = 2048 / max(width, height)
        texture.scale(round(width * scale), round(height * scale))
        texture.pack()
bpy.ops.export_scene.gltf(filepath=str(ROOT / 'assets/cinematic_log_cabin.glb'),
                          export_format='GLB', export_animations=False)
