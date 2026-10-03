from pathlib import Path
import json,struct,io,csv,re
import numpy as np
from PIL import Image

root=Path(__file__).parent.parent/'output/Midnight_Drift_Garage_Detailed'
summary={};documents={}
for path in root.glob('*.glb'):
    raw=path.read_bytes();magic,version,total=struct.unpack_from('<III',raw)
    assert magic==0x46546c67 and version==2 and total==len(raw)
    jl,jt=struct.unpack_from('<II',raw,12);assert jt==0x4e4f534a
    doc=json.loads(raw[20:20+jl]);o=20+jl;bl,bt=struct.unpack_from('<II',raw,o);assert bt==0x004e4942
    documents[path.name]=(doc,raw[o+8:o+8+bl])
    binary=raw[o+8:o+8+bl];assert doc['buffers'][0]['byteLength']<=len(binary)
    def readacc(i):
        a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];dtype={5126:'<f4',5125:'<u4'}[a['componentType']]
        value=np.frombuffer(binary,dtype=dtype,count=a['count']*n,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],n)
        assert np.isfinite(value).all()
        if 'min' in a:
            assert isinstance(a['min'],list) and isinstance(a['max'],list) and len(a['min'])==n
            assert np.allclose(value.min(axis=0),a['min']) and np.allclose(value.max(axis=0),a['max'])
        return value
    for i in range(len(doc['accessors'])):readacc(i)
    triangles=0
    for m in doc['meshes']:
        for p in m['primitives']:
            v=readacc(p['attributes']['POSITION']);n=readacc(p['attributes']['NORMAL']);uv=readacc(p['attributes']['TEXCOORD_0']);indices=readacc(p['indices'])
            assert len(v)==len(n)==len(uv);assert indices.max()<len(v);assert len(indices)%3==0
            assert np.max(np.abs(np.linalg.norm(n,axis=1)-1))<1e-4
            triangles+=len(indices)//3
    for im in doc['images']:
        v=doc['bufferViews'][im['bufferView']]
        with Image.open(io.BytesIO(binary[v['byteOffset']:v['byteOffset']+v['byteLength']])) as image:image.load()
    for a in doc['animations']:
        times=readacc(a['samplers'][0]['input']);quats=readacc(a['samplers'][0]['output'])
        assert len(times)==len(quats) and np.all(np.diff(times[:,0])>0)
        assert np.allclose(np.linalg.norm(quats,axis=1),1)
        assert times[0,0]==0 and times[-1,0]==20
    visited=set()
    def walk(i):
        assert i not in visited;visited.add(i)
        for j in doc['nodes'][i].get('children',[]):walk(j)
    walk(0);assert len(visited)==len(doc['nodes'])
    # Total instanced polygon count, not just deduplicated mesh count.
    actual=sum(sum(doc['accessors'][p['indices']]['count']//3 for p in doc['meshes'][nd['mesh']]['primitives']) for nd in doc['nodes'] if 'mesh' in nd)
    summary[path.name]={'nodes':len(doc['nodes']),'triangles':actual,'materials':len(doc['materials']),'embedded_images':len(doc['images']),'animation_duration_s':20,'bytes':len(raw),'status':'passed'}
for p in root.rglob('*.png'):
    with Image.open(p) as im:im.load()

# The garage, inventories and static export must describe exactly the same separate parts.
doc,binary=documents['Midnight_Drift_Garage.glb']
names=[nd['name'] for nd in doc['nodes'] if 'mesh' in nd]
assert len(names)==len(set(names))
csvnames=[r['name'] for r in csv.DictReader((root/'Object_Inventory.csv').open())]
objnames=[s[2:] for s in (root/'Midnight_Drift_Garage.obj').read_text().splitlines() if s.startswith('o ')]
assert len(csvnames)==len(objnames)==len(names) and set(csvnames)==set(objnames)==set(names)
assert json.loads((root/'Scene_Manifest.json').read_text())['mesh_objects']==len(names)
assert any(nd.get('camera')==0 for nd in doc['nodes'])
assert not any('Spare_tyre_stack' in n or 'Rubber_tyre_' in n or 'Lift_overhead_bridge' in n or 'Lift_arm_pad_' in n for n in names)

def positions(mesh):
    a=doc['accessors'][mesh['primitives'][0]['attributes']['POSITION']];v=doc['bufferViews'][a['bufferView']]
    return np.frombuffer(binary,dtype='<f4',count=a['count']*3,offset=v.get('byteOffset',0)).reshape(-1,3)

specs=set();carcass_count=0
for nd in doc['nodes']:
    match=re.search(r'Tyre_carcass_(\d+)_(\d+)_R(\d+)',nd['name'])
    if not match:continue
    mm,aspect,inches=map(int,match.groups());w=mm/1000;rim=inches*.0254/2;outer=rim+w*aspect/100
    v=positions(doc['meshes'][nd['mesh']]);radial=np.linalg.norm(v[:,:2],axis=1)
    # Hollow beads contain no centre fill, and carcass dimensions match actual car tyre sizing.
    assert np.isclose(radial.min(),rim-.005,atol=1e-5)
    assert np.isclose(radial.max(),outer-.004,atol=1e-5)
    assert np.isclose(np.ptp(v[:,2]),w,atol=1e-5)
    specs.add(f'{mm}/{aspect} R{inches}');carcass_count+=1
assert len(specs)==4 and carcass_count==14
liftgroup=next(i for i,n in enumerate(doc['nodes']) if n['name'].startswith('Floorplate_two_post_lift_'))
liftchildren=[doc['nodes'][i] for i in doc['nodes'][liftgroup]['children']]
assert sum('Rubber_support_pad' in n['name'] for n in liftchildren)==4
assert sum('Outer_lifting_arm' in n['name'] for n in liftchildren)==4
assert sum('Telescopic_inner_arm' in n['name'] for n in liftchildren)==4
assert sum('Lift_base_plate' in n['name'] for n in liftchildren)==2

def quaternion_rotation(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
liftv=[];origin=np.array(doc['nodes'][liftgroup]['translation'])
for n in liftchildren:
    v=positions(doc['meshes'][n['mesh']])*n.get('scale',[1,1,1])
    liftv.append(v@quaternion_rotation(n.get('rotation',[0,0,0,1])).T+n['translation']+origin)
liftv=np.concatenate(liftv)
assert 3.1<liftv[:,2].max()<3.2
assert np.linalg.norm(liftv[:,:2],axis=1).min()>3.79
floor_mean=np.asarray(Image.open(root/'textures/Concrete_floor_basecolor.png')).mean()
wall_mean=np.asarray(Image.open(root/'textures/Concrete_wall_basecolor.png')).mean()
assert floor_mean<50 and wall_mean<40
summary['Revision_checks']={'separate_parts':len(names),'object_names_match_glb_obj_csv':True,'hollow_dimensioned_car_tyres':carcass_count,'tyre_sizes':sorted(specs),'lift_support_pads':4,'lift_clear_of_platform':True,'lift_height_m':round(float(liftv[:,2].max()),3),'floor_texture_mean_srgb_255':round(float(floor_mean),1),'wall_texture_mean_srgb_255':round(float(wall_mean),1),'status':'passed'}
(root/'Asset_Validation.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
