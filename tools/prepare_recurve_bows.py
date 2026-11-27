"""Fit the downloaded bow to the infantry grip and make a shorter riding bow."""
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'art/source/wooden staff 3d model.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
original = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
original.data.transform(original.matrix_world)

for name, height, width, reflex in (
        ('recurve_bow', 1.43, 1.43, .0),
        ('khazar_bow', 1.10, 1.25, .045)):
    mesh = original.data.copy()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # Remove the straight baked string so the in-game string can follow the archer's hand.
    string = [vert for vert in bm.verts if .121 < vert.co.z < .873 and vert.co.y > .074]
    bmesh.ops.delete(bm, geom=string, context='VERTS')
    bm.to_mesh(mesh)
    bm.free()

    def fit(x, y, z):
        t = (z - .505) * 2
        across = (y + .070) * width - reflex * abs(t)**5
        depth = -x * width
        length = (z - .505) * height
        if name == 'recurve_bow':
            fade = max(0, min(1, (.20 - abs(length)) / .11))
            grip = 1 - .38 * fade * fade * (3 - 2 * fade)
            across = .009 + (across - .009) * grip
            depth *= grip
        return across, depth, length

    for vertex in mesh.vertices:
        vertex.co = fit(*vertex.co)
    bow = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(bow)
    bpy.ops.object.select_all(action='DESELECT')
    bow.select_set(True)
    bpy.context.view_layer.objects.active = bow
    decimate = bow.modifiers.new('Bow budget', 'DECIMATE')
    decimate.ratio = min(1, 1450 / len(mesh.polygons))
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    bpy.ops.export_scene.gltf(filepath=str(ROOT / 'assets' / (name + '.glb')),
                              export_format='GLB', use_selection=True, export_animations=False)
    print('BOW', name, len(bow.data.polygons),
          'knots in Godot:', fit(0, .085, .909), fit(0, .085, .092), flush=True)
