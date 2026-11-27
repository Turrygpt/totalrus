"""Author a metre-scale folded wool cape. Runtime handles wind and inertial flex."""
import bpy, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
vertices=[];uvs=[];faces=[]
nx,ny=24,30
for j in range(ny+1):
    t=j/ny
    for i in range(nx+1):
        u=i/nx; x=(u-.5)*(.72+.49*t)
        # Blender +Z is up, -Y is the character's rear in the exported cape frame.
        back=.035+.12*t+.045*math.sin(u*math.pi*12)*(.3+.7*t)-.14*(1-t)**3*(abs(u-.5)*2)**2
        height=-1.18*t-.045*abs(u-.5)*2+.015*math.cos(u*math.pi*2)*t
        vertices.append((x,-back,height));uvs.append((u,t))
for j in range(ny):
    for i in range(nx):
        a=j*(nx+1)+i;b=a+1;c=a+nx+1;d=c+1
        faces.extend([(a,c,b),(b,c,d)])
mesh=bpy.data.meshes.new('Tailored wool, radial folds');mesh.from_pydata(vertices,[],faces);mesh.update()
obj=bpy.data.objects.new('Princely_Cape',mesh);bpy.context.collection.objects.link(obj)
uv=mesh.uv_layers.new(name='UVMap')
for poly in mesh.polygons:
    poly.use_smooth=True
    for loop in poly.loop_indices:uv.data[loop].uv=uvs[mesh.loops[loop].vertex_index]
mat=bpy.data.materials.new('Heavy wool');mat.diffuse_color=(.08,.14,.21,1);mat.use_nodes=True
mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.94
obj.data.materials.append(mat)
bpy.context.view_layer.objects.active=obj;obj.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/princely_cape.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/princely_cape.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
print('CAPE',len(vertices),'vertices',len(faces),'triangles')
