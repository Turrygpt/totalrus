"""Transfer the existing infantry archer's skin onto a downloaded mesh.

Run with Blender --background --python tools/rig_archer_far.py -- <input.glb>.
"""
import json
from pathlib import Path
import struct
import sys

from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load(path):
    raw = path.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + size]), raw[28 + size:]


def read(doc, binary, index):
    entry = doc["accessors"][index]
    source = doc["bufferViews"][entry["bufferView"]]
    get = struct.Struct("<" + COMPONENTS[entry["componentType"]] * WIDTHS[entry["type"]])
    start = source.get("byteOffset", 0) + entry.get("byteOffset", 0)
    stride = source.get("byteStride", get.size)
    return [get.unpack_from(binary, start + i * stride) for i in range(entry["count"])]


def append_view(doc, binary, data, target=None):
    binary.extend(b"\0" * (-len(binary) % 4))
    entry = dict(buffer=0, byteOffset=len(binary), byteLength=len(data))
    if target:
        entry["target"] = target
    binary.extend(data)
    doc["bufferViews"].append(entry)
    return len(doc["bufferViews"]) - 1


def replace(doc, binary, index, rows, kind, component):
    pack = struct.Struct("<" + COMPONENTS[component] * WIDTHS[kind])
    view = append_view(doc, binary, b"".join(pack.pack(*row) for row in rows),
                       34963 if kind == "SCALAR" else 34962)
    doc["accessors"][index] = dict(bufferView=view, componentType=component, count=len(rows), type=kind)


def transfer(point, surface, source, triangles, joints, weights):
    nearest, _, face, distance = surface.find_nearest(point)
    triangle = triangles[face]
    a, b, c = (source[i] for i in triangle)
    u, v, w = b - a, c - a, nearest - a
    uu, uv, vv = u.dot(u), u.dot(v), v.dot(v)
    det = uu * vv - uv * uv
    weight_b = (vv * w.dot(u) - uv * w.dot(v)) / det if det > 1e-15 else 0.0
    weight_c = (uu * w.dot(v) - uv * w.dot(u)) / det if det > 1e-15 else 0.0
    influence = {}
    for i, factor in zip(triangle, (1 - weight_b - weight_c, weight_b, weight_c)):
        for joint, weight in zip(joints[i], weights[i]):
            influence[joint] = influence.get(joint, 0.0) + max(0.0, factor) * weight
    result = sorted(influence.items(), key=lambda item: -item[1])[:4]
    result += [(0, 0.0)] * (4 - len(result))
    total = sum(weight for _, weight in result)
    return tuple(joint for joint, _ in result), tuple(weight / total for _, weight in result), distance


def save(path, doc, binary):
    # Keep animation and skin data, dropping the old mesh and texture views.
    views = doc["bufferViews"]
    doc["bufferViews"], compact, remap = [], bytearray(), {}
    for entry in doc["accessors"] + doc["images"]:
        old = entry["bufferView"]
        if old not in remap:
            source = views[old]
            begin = source.get("byteOffset", 0)
            remap[old] = append_view(doc, compact, binary[begin:begin + source["byteLength"]], source.get("target"))
            if "byteStride" in source:
                doc["bufferViews"][remap[old]]["byteStride"] = source["byteStride"]
        entry["bufferView"] = remap[old]
    compact.extend(b"\0" * (-len(compact) % 4))
    doc["buffers"] = [dict(byteLength=len(compact))]
    metadata = json.dumps(doc, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(metadata) + len(compact)) +
                     struct.pack("<I4s", len(metadata), b"JSON") + metadata +
                     struct.pack("<I4s", len(compact), b"BIN\0") + compact)


def main(input_file, tier):
    doc, original = load(ROOT / "assets/archer_infantry.glb")
    low, downloaded = load(input_file)
    binary = bytearray(original)
    high_mesh = doc["meshes"][0]["primitives"][0]
    low_mesh = low["meshes"][0]["primitives"][0]
    high_attr, low_attr = high_mesh["attributes"], low_mesh["attributes"]
    source = [Vector(row) for row in read(doc, original, high_attr["POSITION"])]
    indices = [index for (index,) in read(doc, original, high_mesh["indices"])]
    triangles = list(zip(indices[::3], indices[1::3], indices[2::3]))
    surface = BVHTree.FromPolygons(source, triangles, all_triangles=True)
    joints = read(doc, original, high_attr["JOINTS_0"])
    weights = read(doc, original, high_attr["WEIGHTS_0"])
    points = [Vector(row) for row in read(low, downloaded, low_attr["POSITION"])]
    scale = max(p.y for p in source) / max(p.y for p in points)
    points = [p * scale for p in points]
    mapped = [transfer(p, surface, source, triangles, joints, weights) for p in points]
    low_indices = read(low, downloaded, low_mesh["indices"])
    limits = {"archer_mid": 6200, "archer_far": 3000, "archer_overview": 1000}
    assert len(low_indices) % 3 == 0 and len(low_indices) // 3 <= limits[tier]
    assert max(item[2] for item in mapped) < .1, "The downloaded mesh does not match the archer's rest pose"

    replace(doc, binary, high_attr["POSITION"], points, "VEC3", 5126)
    position = doc["accessors"][high_attr["POSITION"]]
    position["min"] = [min(p[axis] for p in points) for axis in range(3)]
    position["max"] = [max(p[axis] for p in points) for axis in range(3)]
    replace(doc, binary, high_attr["NORMAL"], read(low, downloaded, low_attr["NORMAL"]), "VEC3", 5126)
    uv = read(low, downloaded, low_attr["TEXCOORD_0"])
    replace(doc, binary, high_attr["TEXCOORD_0"], uv, "VEC2", 5126)
    replace(doc, binary, high_attr["TEXCOORD_1"], uv, "VEC2", 5126)
    replace(doc, binary, high_attr["JOINTS_0"], [item[0] for item in mapped], "VEC4", 5121)
    replace(doc, binary, high_attr["WEIGHTS_0"], [item[1] for item in mapped], "VEC4", 5126)
    replace(doc, binary, high_mesh["indices"], low_indices, "SCALAR", 5123)

    source_mat = low["materials"][low_mesh["material"]]["pbrMetallicRoughness"]
    material = doc["materials"][high_mesh["material"]]["pbrMetallicRoughness"]
    image = low["images"][low["textures"][source_mat["baseColorTexture"]["index"]]["source"]]
    image_view = low["bufferViews"][image["bufferView"]]
    offset = image_view.get("byteOffset", 0)
    image_data = downloaded[offset:offset + image_view["byteLength"]]
    img_index = doc["textures"][material["baseColorTexture"]["index"]]["source"]
    doc["images"][img_index] = dict(bufferView=append_view(doc, binary, image_data),
                                   name="ArcherAlbedo", mimeType=image["mimeType"])
    save(ROOT / "assets/lod" / (tier + ".glb"), doc, binary)
    print(f"{len(low_indices) // 3} triangles, {len(doc['animations'])} clips, "
          f"maximum skin transfer distance {max(item[2] for item in mapped):.4f} m")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    main(Path(args[0]), args[1] if len(args) > 1 else "archer_far")
