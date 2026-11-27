"""Sculpt and bake the horse coat with Blender --background --python tools/prepare_horse_coat.py."""

from math import exp, sin
from pathlib import Path

import bpy
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[1]
HORSE_SOURCE = ROOT / "art/source/horse/Horse.blend"
COAT_SOURCE = ROOT / "art/horse_coat.blend"
TEXTURES = ROOT / "art/textures/horse"
SIZE = 2048
UV_NAME = "HorseCoatUV"


def select(*objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[-1]


def make_low():
    source = bpy.data.objects["Horse"].data.copy()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    source.validate()
    target = bpy.data.objects.new("Horse_Low", source)
    bpy.context.collection.objects.link(target)
    select(target)
    target.data.uv_layers.new(name=UV_NAME)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.31, island_margin=.019,
                             margin_method='FRACTION')
    bpy.ops.object.mode_set(mode='OBJECT')
    for polygon in target.data.polygons:
        polygon.use_smooth = True
    return target


def mask(value, start, end):
    t = max(0, min(1, (value - start) / (end - start)))
    return t * t * (3 - 2 * t)


def lobe(y, z, cy, cz, wy, wz):
    return exp(-((y - cy) / wy) ** 2 - ((z - cz) / wz) ** 2)


def grain(co):
    return noise.noise_vector(Vector((co.x * 17, co.y * 12, co.z * 15)))[0]


def sculpt(low):
    high = low.copy()
    high.data = low.data.copy()
    high.name = "Horse_High"
    bpy.context.collection.objects.link(high)
    select(high)
    subdiv = high.modifiers.new("Sculpt surface", 'SUBSURF')
    subdiv.levels = 3
    bpy.ops.object.modifier_apply(modifier=subdiv.name)
    mesh = high.data
    normals = [v.normal.copy() for v in mesh.vertices]
    for v, normal in zip(mesh.vertices, normals):
        x, y, z = v.co
        flank = mask(abs(x), .23, .55)
        shoulder = .075 * lobe(y, z, -1.04, 2.67, .31, .48)
        haunch = .085 * lobe(y, z, 1.12, 2.82, .46, .47)
        flank_hollow = -.038 * lobe(y, z, .67, 2.78, .22, .28)
        forearm = .032 * lobe(y, z, -1.39, 1.84, .24, .29)
        neck = .045 * lobe(y, z, -1.78 - .43 * (z - 3.35), 3.37, .26, .62)
        jowl = .033 * lobe(y, z, -2.57, 3.92, .26, .24)
        relief = flank * (shoulder + haunch + flank_hollow + forearm) + abs(normal.x) * (neck + jowl)
        v.co += normal * (relief + .008 * grain(v.co))
    mesh.update()
    return high


def paint(high):
    mesh = high.data
    colors = mesh.color_attributes.new(name="Coat", type='FLOAT_COLOR', domain='POINT')
    roughness = mesh.color_attributes.new(name="CoatRoughness", type='FLOAT_COLOR', domain='POINT')
    material_names = [mat.name for mat in mesh.materials]
    weights = [dict() for _ in mesh.vertices]
    for polygon in mesh.polygons:
        name = material_names[polygon.material_index]
        for index in polygon.vertices:
            weights[index][name] = weights[index].get(name, 0) + 1

    for v, patches, color, rough in zip(mesh.vertices, weights, colors.data, roughness.data):
        x, y, z = v.co
        n = grain(v.co)
        # Body coat transitions into darker points at the knees, hocks and muzzle.
        top = mask(z, 2.95, 3.70) * (1 - mask(abs(x), .18, .57))
        legs = 1 - mask(z + .07 * n, .84, 1.65)
        muzzle = mask(-y, 3.00, 3.44) * (1 - mask(z, 3.72, 3.99))
        warmth = .76 + .27 * sin(y * 1.52 + .6) + .13 * n
        bay = Vector((.239, .089, .035)) * warmth
        black = Vector((.023, .013, .010))
        soft = top * .55 + muzzle * .16
        body = bay.lerp(black, max(legs * .97, muzzle * .84, soft))
        irregularity = .021 * sin(z * 19) + .010 * sin(z * 54)
        blaze = (1 - mask(abs(x - irregularity), .043, .097)) * mask(-y, 2.69, 2.87)
        blaze *= mask(z, 3.70, 3.84) * (1 - mask(z, 4.40, 4.48))
        body = body.lerp(Vector((.55, .43, .29)), blaze)
        palette = {
            "Hair": (black * (.83 + .34 * n), .66),
            "Hooves": (Vector((.042, .033, .025)) * (1 + .16 * n), .57),
            "Muzzle": (body.lerp(Vector((.032, .019, .017)), .56), .66),
            "Eye_Black": (Vector((.011, .006, .004)), .23),
            "Eye_White": (Vector((.31, .20, .12)), .37),
        }
        total = sum(patches.values())
        result = Vector((0, 0, 0))
        gloss = 0.0
        for name, count in patches.items():
            swatch, roughness_value = palette.get(name, (body, .72 + .06 * n))
            result += swatch * (count / total)
            gloss += roughness_value * count / total
        color.color = (*result, 1)
        rough.color = (gloss, gloss, gloss, 1)

    mat = bpy.data.materials.new("Bay coat sculpt material")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    coat = nodes.new("ShaderNodeVertexColor")
    coat.layer_name = colors.name
    rough = nodes.new("ShaderNodeVertexColor")
    rough.layer_name = roughness.name
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    coordinates = nodes.new("ShaderNodeTexCoord")
    direction = nodes.new("ShaderNodeVectorMath")
    direction.operation = 'MULTIPLY'
    direction.inputs[1].default_value = (1.0, .65, .30)
    links.new(coordinates.outputs["Object"], direction.inputs[0])
    hairs = nodes.new("ShaderNodeTexNoise")
    hairs.inputs["Scale"].default_value = 170
    hairs.inputs["Detail"].default_value = 2
    links.new(direction.outputs["Vector"], hairs.inputs["Vector"])
    fibers = nodes.new("ShaderNodeMapRange")
    fibers.inputs["To Min"].default_value = .77
    fibers.inputs["To Max"].default_value = 1.20
    links.new(hairs.outputs["Fac"], fibers.inputs["Value"])
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = 'MULTIPLY'
    tint.inputs[0].default_value = 1
    links.new(coat.outputs["Color"], tint.inputs[1])
    links.new(fibers.outputs["Result"], tint.inputs[2])
    links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .18
    bump.inputs["Distance"].default_value = .006
    links.new(hairs.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    assign(high, mat)
    return mat, tint.outputs["Color"], rough.outputs["Color"]


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def bake(low, high, painted, color_output, rough_output):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.use_cage = True
    scene.render.bake.cage_extrusion = .16
    scene.render.bake.max_ray_distance = .36
    scene.render.bake.margin = 16
    scene.render.bake.normal_space = 'TANGENT'

    mat = bpy.data.materials.new("Bay horse — baked")
    mat.use_nodes = True
    assign(low, mat)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bake_nodes = painted.node_tree.nodes
    bake_links = painted.node_tree.links
    output = bake_nodes.get("Material Output")
    surface = output.inputs["Surface"]
    source_shader = surface.links[0].from_socket
    emission = bake_nodes.new("ShaderNodeEmission")

    select(high, low)
    for stem, bake_type, shader_output in (
        ("horse_normal", 'NORMAL', None),
        ("horse_base_color", 'EMIT', color_output),
        ("horse_roughness", 'EMIT', rough_output),
    ):
        print("BAKE", stem, flush=True)
        image = bpy.data.images.new(stem, SIZE, SIZE, alpha=False)
        image.colorspace_settings.name = 'sRGB' if stem == "horse_base_color" else 'Non-Color'
        texture = nodes.new("ShaderNodeTexImage")
        texture.label = stem
        texture.image = image
        nodes.active = texture
        if shader_output is not None:
            bake_links.new(shader_output, emission.inputs["Color"])
            bake_links.new(emission.outputs["Emission"], surface)
        bpy.ops.object.bake(type=bake_type)
        image.filepath_raw = str(TEXTURES / (stem + ".png"))
        image.file_format = 'PNG'
        image.save()
        image.pack()
        if bake_type == 'NORMAL':
            normal = nodes.new("ShaderNodeNormalMap")
            normal.uv_map = UV_NAME
            normal.inputs["Strength"].default_value = .72
            links.new(texture.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            target = "Base Color" if stem == "horse_base_color" else "Roughness"
            links.new(texture.outputs["Color"], bsdf.inputs[target])
    bake_links.new(source_shader, surface)
    bake_nodes.remove(emission)


def main():
    bpy.ops.wm.open_mainfile(filepath=str(HORSE_SOURCE))
    TEXTURES.mkdir(parents=True, exist_ok=True)
    low = make_low()
    high = sculpt(low)
    bake(low, high, *paint(high))
    high.hide_set(True)
    high.hide_render = True
    select(low)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(COAT_SOURCE))


if __name__ == "__main__":
    main()
