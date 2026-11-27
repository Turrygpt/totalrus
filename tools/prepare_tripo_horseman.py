"""Fit the downloaded horse and rebuild the mounted warrior for Godot."""

from math import cos, pi, sin
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_horseman import (
    HORSE_SCALE, RIDER_BONE, ROOT, SADDLE_BONE, SPEAR_BONE,
    bind_mesh, ellipsoid, make_clips, make_fall, make_rider, material,
    reset_pose, strap, use_action,
)

SOURCE = ROOT / "art/source/horse"
CLIPS = ("Idle", "Walk", "Trot", "Gallop", "Rear", "Death")
SEAT = Vector((0, .17, 3.79))
BACK = "tripo::Spine_0"
HEAD = "tripo::Head_2"
ROOT_BONE = "tripo::Root"
HORSE_LENGTH = 6.0


def import_mount():
    scene = bpy.context.scene
    existing = set(scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / "tripo_horse.glb"))
    imported = set(scene.objects) - existing
    rig = next(obj for obj in imported if obj.type == 'ARMATURE')
    mesh = next(obj for obj in rig.children if obj.type == 'MESH')
    rig.parent = None
    rig.matrix_world = Matrix.Identity(4)
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    mesh.matrix_basis = Matrix.Identity(4)
    size = Matrix.Scale(HORSE_LENGTH, 4)
    rig.data.transform(size)
    mesh.data.transform(size)
    for obj in imported - {rig, mesh}:
        bpy.data.objects.remove(obj, do_unlink=True)
    rig.name = "TripoHorseRig"
    mesh.name = "TripoHorse"
    bpy.context.view_layer.update()
    return rig, mesh


def joint_map():
    mapping = {
        ROOT_BONE: "Body",
        BACK: "Torso", "tripo::Spine_1": "Torso2",
        "tripo::Head_0": "Neck1", "tripo::Head_1": "Neck3", HEAD: "Head",
        "bone_16": "Back", "bone_27": "Tail1", "tripo::Tail_0": "Tail2",
        "tripo::Tail_1": "Tail4", "tripo::Tail_2": "Tail6", "bone_31": "Tail7",
        "bone_32": "Torso", "bone_33": "Torso",
        "bone_22": "BackLeg.R",
    }
    for side, suffix in (("Left", "L"), ("Right", "R")):
        for i, bone in enumerate(("FrontUpperLeg", "FrontUpperLeg", "FrontLowerLeg", "FF", "FF")):
            mapping[f"tripo::0_{side}_Limb_{i}"] = f"{bone}.{suffix}"
    for side, suffix, bones in (
        ("Left", "L", ("BackLeg", "BackUpperLeg", "BackLowerLeg", "FFB", "FFB")),
        ("Right", "R", ("BackUpperLeg", "BackLowerLeg", "FFB", "FFB")),
    ):
        for i, bone in enumerate(bones):
            mapping[f"tripo::1_{side}_Limb_{i}"] = f"{bone}.{suffix}"
    return mapping


def limit_rotation(rotation, angle):
    if rotation.w < 0:
        rotation.negate()
    if rotation.angle > angle:
        rotation = Quaternion().slerp(rotation, angle / rotation.angle)
    return rotation


def transfer(source, rig, mesh):
    mapping = joint_map()
    scene = bpy.context.scene
    originals = {name: bpy.data.actions[name] for name in CLIPS}
    bones = list(rig.pose.bones)
    rest = {bone.name: bone.bone.matrix_local.to_quaternion() for bone in bones}
    source_rest = {bone.name: bone.bone.matrix_local.copy() for bone in source.pose.bones}
    source_inverse = {name: m.to_quaternion().inverted() for name, m in source_rest.items()}
    local_rest = {
        bone.name: rest[bone.parent.name].inverted() @ rest[bone.name] if bone.parent else rest[bone.name]
        for bone in bones
    }
    forelegs = {
        f"tripo::0_{side}_Limb_{joint}": (suffix, joint)
        for side, suffix in (("Left", "L"), ("Right", "R"))
        for joint in range(5)
    }
    foot_pads = ("FF.L", "FF.R", "FFB.L", "FFB.R")
    pads_height = min(source_rest[name].translation.z for name in foot_pads)
    root = rig.pose.bones[ROOT_BONE]
    world_to_root = rest[ROOT_BONE].inverted()
    rig.animation_data_create()
    transferred = {}

    for name in CLIPS:
        original = originals[name]
        use_action(source, original)
        action = bpy.data.actions.new("Mount_" + name)
        action.use_fake_user = True
        rig.animation_data.action = action
        previous = {}
        for frame in range(round(original.frame_range.y) + 1):
            scene.frame_set(frame)
            delta = {
                bone: source.pose.bones[bone].matrix.to_quaternion() @ source_inverse[bone]
                for bone in set(mapping.values())
            }
            world = {}
            for bone in bones:
                key = bone.name
                swing = delta[mapping[key]]
                if name == "Gallop" and key in forelegs:
                    side, joint = forelegs[key]
                    if joint == 1:
                        # The imported foreleg has an extra segment above the knee.
                        # Spread the donor knee flexion over these two joints.
                        swing = swing.slerp(delta[f"FrontLowerLeg.{side}"], .30)
                desired = swing @ rest[key]
                parent_world = world[bone.parent.name] if bone.parent else Quaternion()
                pose = local_rest[key].inverted() @ parent_world.inverted() @ desired
                if name == "Gallop" and key in forelegs:
                    _, joint = forelegs[key]
                    pose = limit_rotation(pose, (1.18, .47, 1.05, .59, .31)[joint])
                world[key] = parent_world @ local_rest[key] @ pose
                if key in previous and previous[key].dot(pose) < 0:
                    pose.negate()
                previous[key] = pose.copy()
                bone.rotation_mode = 'QUATERNION'
                bone.rotation_quaternion = pose

            root_shift = source.pose.bones["Body"].head - source_rest["Body"].translation
            root.location = world_to_root @ root_shift
            bpy.context.view_layer.update()
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            lowest = min(vertex.co.z for vertex in evaluated.data.vertices)
            source_lift = min(source.pose.bones[pad].head.z for pad in foot_pads) - pads_height
            clearance = .012 if name == "Death" else max(.012, source_lift)
            root.location += world_to_root @ Vector((0, 0, clearance - lowest))
            root.keyframe_insert(data_path='location', frame=frame, group=root.name)
            for bone in bones:
                bone.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=bone.name)
        transferred[name] = action
        print("RETARGETED", name, flush=True)

    reset_pose(rig)
    for action in originals.values():
        bpy.data.actions.remove(action)
    for name, action in transferred.items():
        action.name = name


def add_saddle_bones(rig):
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    parent = rig.data.edit_bones[BACK]
    for name in (SADDLE_BONE, RIDER_BONE, SPEAR_BONE):
        bone = rig.data.edit_bones.new(name)
        bone.parent = parent
        bone.head = SEAT
        bone.tail = SEAT + Vector((0, 0, .42))
        parent = bone
    bpy.ops.object.mode_set(mode='OBJECT')


def fitted_section(surface, y, z, angles, gap):
    center = Vector((0, y, z))
    points = []
    for angle in angles:
        direction = Vector((sin(angle), 0, cos(angle)))
        hit, _, _, _ = surface.ray_cast(center + direction * 5, -direction, 5)
        if hit is None:
            raise ValueError(f"Harness section misses the horse at Y={y}, angle={angle}")
        points.append(hit + direction * gap)
    return points


def saddlecloth(rig, surface, cloth, band):
    angles = [i * pi / 36 for i in range(-16, 17)]
    rows = [-.59, -.54, -.4, -.21, 0, .21, .42, .64, .83, .88]
    points = [point for y in rows for point in fitted_section(surface, y, 2.62, angles, .075)]
    width = len(angles)
    faces = [(i, i + 1, i + width + 1, i + width)
             for i in range(width * (len(rows) - 1)) if i % width != width - 1]
    # Section angles run from left to right, so these faces point outside the coat.
    mesh = bpy.data.meshes.new("Fitted saddlecloth")
    mesh.from_pydata(points, [], faces)
    obj = bpy.data.objects.new("Fitted saddlecloth", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(cloth)
    mesh.materials.append(band)
    for face in mesh.polygons:
        row, column = divmod(face.index, width - 1)
        if row in (0, len(rows) - 2) or column in (0, width - 2):
            face.material_index = 1
        face.use_smooth = True
    shell = obj.modifiers.new("Wool thickness", 'SOLIDIFY')
    shell.thickness = .033
    bind_mesh(obj, rig, BACK)


def tack(rig, mesh, contacts):
    surface = BVHTree.FromPolygons([vertex.co for vertex in mesh.data.vertices],
                                  [face.vertices[:] for face in mesh.data.polygons])
    leather = material("Dark tack leather", (.054, .026, .013))
    bronze = material("Patinated stirrup bronze", (.28, .15, .055), .68)
    cloth = material("Dyed indigo wool", (.024, .061, .083))
    band = material("Ochre wool trim", (.22, .12, .045))
    saddlecloth(rig, surface, cloth, band)
    ellipsoid(rig, "Saddle seat", (0, .14, 3.52), (.48, .65, .18), leather, BACK)
    ellipsoid(rig, "Front saddle bow", (0, -.38, 3.69), (.39, .14, .15), leather, BACK)
    ellipsoid(rig, "Rear saddle bow", (0, .68, 3.66), (.43, .17, .20), leather, BACK)

    girth = fitted_section(surface, .04, 2.51, [i * pi / 12 for i in range(25)], .061)
    strap(rig, "Girth", girth, .046, leather, BACK)
    for side, sign in (("Left", 1), ("Right", -1)):
        foot = contacts[side + "Foot"]
        toe = contacts[side + "ToeBase"]
        x = (foot.x + toe.x) * .5
        y = (foot.y + toe.y) * .5
        z = min(foot.z, toe.z) - .10
        ring_top = (x, y, z + .39)
        strap(rig, "Stirrup leather", [(sign * .43, y, 3.50), (sign * .76, y, 3.07),
              (x, y, z + .50), ring_top], .029, leather, BACK)
        strap(rig, "Fitted stirrup", [ring_top, (x, y - .20, z + .25),
              (x, y - .21, z), (x, y + .19, z), (x, y + .19, z + .25),
              ring_top], .032, bronze, BACK)

    angles = [i * pi / 10 for i in range(21)]
    nose = fitted_section(surface, -2.78, 3.20, angles, .035)
    strap(rig, "Noseband", nose, .033, leather, HEAD)
    hand = contacts["LeftHand"] + Vector((0, -.16, -.045))
    for sign in (-1, 1):
        bit = max(nose, key=lambda p: sign * p.x) + Vector((0, .055, -.155))
        cheek = fitted_section(surface, -2.45, 3.72, [sign * pi / 3], .044)[0]
        poll = fitted_section(surface, -2.30, 3.86, [sign * pi / 5], .041)[0]
        strap(rig, "Bridle cheekpiece", (bit, cheek, poll), .027, leather, HEAD)
        ellipsoid(rig, "Bit ring", tuple(bit), (.037, .054, .054), bronze, HEAD)
        points = []
        control_a = bit + Vector((sign * .42, .46, .16))
        control_b = hand + Vector((sign * .38, -.49, -.20))
        for i in range(17):
            t = i / 16
            u = 1 - t
            points.append(u ** 3 * bit + 3 * u ** 2 * t * control_a
                          + 3 * u * t ** 2 * control_b + t ** 3 * hand)
        rein = strap(rig, "Rein", points, .018, leather, HEAD)
        head_group = rein.vertex_groups[HEAD]
        hand_group = rein.vertex_groups.new(name=SADDLE_BONE)
        for vertex in rein.data.vertices:
            progress = min(1, max(0, (vertex.co.y - bit.y) / (hand.y - bit.y)))
            weight = progress * progress * (3 - 2 * progress)
            head_group.add([vertex.index], 1 - weight, 'REPLACE')
            hand_group.add([vertex.index], weight, 'REPLACE')


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / "Horse.blend"))
    donor = bpy.data.objects["AnimalArmature"]
    make_clips(donor)
    mount, mesh = import_mount()
    transfer(donor, mount, mesh)
    for obj in list(donor.children):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(donor, do_unlink=True)
    add_saddle_bones(mount)
    contacts = {}
    rider = make_rider(mount, seat=SEAT, wide_stance=True, contacts=contacts)
    tack(mount, mesh, contacts)
    make_fall(mount, *rider, seat=SEAT, fall_x=5.26)
    use_action(mount, bpy.data.actions["Idle"])
    mount.scale = (HORSE_SCALE,) * 3
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start = 0
    scene.frame_end = 100
    scene.frame_set(0)
    for image in bpy.data.images:
        if image.size[0] and image.users:
            image.pack()
    bpy.ops.object.select_all(action='DESELECT')
    mount.select_set(True)
    bpy.context.view_layer.objects.active = mount
    if "--preview" in sys.argv:
        output = ROOT / "build/horseman_review"
        output.mkdir(parents=True, exist_ok=True)
        blend_path = output / "horseman_tripo.blend"
        glb_path = output / "horseman_tripo.glb"
    else:
        blend_path = ROOT / "art/horseman.blend"
        glb_path = ROOT / "assets/horseman.glb"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_animation_mode='ACTIONS',
                             export_frame_range=False, export_apply=True,
                             export_force_sampling=True)


if __name__ == "__main__":
    main()
