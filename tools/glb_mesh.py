# Minimal GLB reader (numpy): accessors, node world transforms, the triangles of named meshes.
import json,struct,numpy as np
CT={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def load(p):
    b=open(p,'rb').read()
    l=struct.unpack('<I',b[12:16])[0]
    j=json.loads(b[20:20+l])
    off=20+l
    bl=struct.unpack('<I',b[off:off+4])[0]
    bin_=b[off+8:off+8+bl]
    return j,bin_
def acc(j,bin_,i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    n=NC[a['type']]; dt=CT[a['componentType']]
    start=bv.get('byteOffset',0)+a.get('byteOffset',0)
    stride=bv.get('byteStride',0)
    cnt=a['count']
    if stride and stride!=n*np.dtype(dt).itemsize:
        raw=np.frombuffer(bin_,dtype=np.uint8,count=stride*cnt,offset=start).reshape(cnt,stride)
        return raw[:,:n*np.dtype(dt).itemsize].copy().view(dt).reshape(cnt,n)
    return np.frombuffer(bin_,dtype=dt,count=cnt*n,offset=start).reshape(cnt,n) if n>1 else np.frombuffer(bin_,dtype=dt,count=cnt,offset=start)
def node_mats(j):
    # world transforms of nodes (only TRS)
    import math
    out={}
    def m_of(n):
        if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
        T=np.eye(4); T[:3,3]=n.get('translation',[0,0,0])
        q=n.get('rotation',[0,0,0,1]); x,y,z,w=q
        R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
        S=np.diag(n.get('scale',[1,1,1]))
        M=np.eye(4); M[:3,:3]=R@S
        return T@M
    def walk(i,P):
        n=j['nodes'][i]; W=P@m_of(n); out[i]=W
        for c in n.get('children',[]): walk(c,W)
    for r in j['scenes'][j.get('scene',0)]['nodes']: walk(r,np.eye(4))
    return out
def mesh_tris(j,bin_,name_prefix):
    W=node_mats(j); res=[]
    for ni,n in enumerate(j['nodes']):
        if 'mesh' not in n or not n.get('name','').startswith(name_prefix): continue
        for pr in j['meshes'][n['mesh']]['primitives']:
            P=acc(j,bin_,pr['attributes']['POSITION']).astype(np.float64)
            P=(W[ni][:3,:3]@P.T).T+W[ni][:3,3]
            I=acc(j,bin_,pr['indices']).astype(np.int64) if 'indices' in pr else np.arange(len(P))
            res.append(P[I.reshape(-1,3)])
    return np.concatenate(res) if res else np.zeros((0,3,3))
