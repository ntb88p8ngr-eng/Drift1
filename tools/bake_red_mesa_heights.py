# Bakes the ground height of the Red Mesa GLB halves (terrain, earth, asphalt, sand, gravel) onto a
# 4 m grid: assets/maps/red_mesa/heights.bin (float16) + heights.json. Run from the repo root:
#   python3 tools/bake_red_mesa_heights.py
import sys; sys.path.insert(0, 'tools')
from glb_mesh import *
import numpy as np, json, time
CELL=4.0
X0,X1,Z0,Z1=-2660.0,2660.0,-2160.0,2160.0
nx=int((X1-X0)/CELL)+1; nz=int((Z1-Z0)/CELL)+1
H=np.full((nz,nx),-1e9,np.float32)
t0=time.time()
for s in ['West','East']:
    j,b=load('assets/world_upload/Red_Mesa/Red_Mesa_Drift_Run_%s.glb'%s)
    for pre in ['terrain','earth','asphalt','sand','road_gravel']:
        T=mesh_tris(j,b,pre)   # prefix 'sand' also matches sand_light
        print(s,pre,len(T),round(time.time()-t0,1)); sys.stdout.flush()
        if len(T)==0: continue
        A=T[:,0];B=T[:,1];C=T[:,2]
        mnx=np.floor((np.minimum(np.minimum(A[:,0],B[:,0]),C[:,0])-X0)/CELL).astype(int)
        mxx=np.ceil((np.maximum(np.maximum(A[:,0],B[:,0]),C[:,0])-X0)/CELL).astype(int)
        mnz=np.floor((np.minimum(np.minimum(A[:,2],B[:,2]),C[:,2])-Z0)/CELL).astype(int)
        mxz=np.ceil((np.maximum(np.maximum(A[:,2],B[:,2]),C[:,2])-Z0)/CELL).astype(int)
        # group triangles by bbox size for vectorised sampling
        w=(mxx-mnx+1); h=(mxz-mnz+1)
        for sz in sorted(set(zip(w.tolist(),h.tolist()))):
            sel=np.where((w==sz[0])&(h==sz[1]))[0]
            if len(sel)==0: continue
            gx,gz=np.meshgrid(np.arange(sz[0]),np.arange(sz[1]))
            gx=gx.ravel();gz=gz.ravel()
            ix=mnx[sel][:,None]+gx[None,:]; iz=mnz[sel][:,None]+gz[None,:]
            px=X0+ix*CELL; pz=Z0+iz*CELL
            a=A[sel];bb=B[sel];c=C[sel]
            v0x=(bb[:,0]-a[:,0])[:,None]; v0z=(bb[:,2]-a[:,2])[:,None]
            v1x=(c[:,0]-a[:,0])[:,None]; v1z=(c[:,2]-a[:,2])[:,None]
            v2x=px-a[:,0][:,None]; v2z=pz-a[:,2][:,None]
            den=v0x*v1z-v1x*v0z
            den=np.where(np.abs(den)<1e-9,1e-9,den)
            u=(v2x*v1z-v1x*v2z)/den; v=(v0x*v2z-v2x*v0z)/den
            inside=(u>=-1e-4)&(v>=-1e-4)&(u+v<=1+1e-4)&(ix>=0)&(ix<nx)&(iz>=0)&(iz<nz)
            y=a[:,1][:,None]+u*(bb[:,1]-a[:,1])[:,None]+v*(c[:,1]-a[:,1])[:,None]
            ii=iz[inside];jj=ix[inside];yy=y[inside].astype(np.float32)
            np.maximum.at(H,(ii,jj),yy)
miss=(H<-1e8)
print('missing cells',miss.sum(),'of',H.size)
H[miss]=0.0
print('range',H.min(),H.max())
H.astype(np.float16).tofile('assets/maps/red_mesa/heights.bin')
json.dump({'origin':[X0,Z0],'cell':CELL,'nx':nx,'nz':nz,'format':'float16'},open('assets/maps/red_mesa/heights.json','w'))
