"""Offline CPU raster preview of the actual authored 3D geometry."""
import build_detailed as D
B=D.B
import numpy as np, math
import argparse
from PIL import Image
from scipy.ndimage import gaussian_filter

parser=argparse.ArgumentParser();parser.add_argument('--view',choices=['garage','service'],default='garage');args=parser.parse_args()
W,H=(1800,1125) if args.view=='garage' else (1400,1000)
camera=np.array([4.6,-5.9,2.75] if args.view=='garage' else [-2.3,-.7,2.4])
target=np.array([-.5,1.65,1.50] if args.view=='garage' else [-5.7,3.55,1.55])
hfov=93 if args.view=='garage' else 76
forward=target-camera;forward/=np.linalg.norm(forward)
right=np.cross(forward,[0,0,1]);right/=np.linalg.norm(right);up=np.cross(right,forward)
rot=np.stack([right,up,forward],1);focal=W/(2*math.tan(math.radians(hfov)/2))
zbuf=np.full((H,W),np.inf,np.float32);normal=np.zeros((H,W,3),np.float32);world=np.zeros_like(normal)
uvbuf=np.zeros((H,W,2),np.float32);mid=np.full((H,W),-1,np.int16)
def clipped_tris(g,v,n,cam):
    for face in g['f']:
        vv=v[face];nn=n[face];tuv=g['uv'][face];cc=cam[face]
        if np.all(cc[:,2]>=.08):
            yield vv,nn,tuv,cc
            continue
        if np.all(cc[:,2]<.08):continue
        p=np.concatenate([vv,nn,tuv,cc],axis=1);poly=[]
        for j in range(3):
            a=p[j-1];b=p[j];ina=a[-1]>=.08;inb=b[-1]>=.08
            if ina!=inb:
                t=(.08-a[-1])/(b[-1]-a[-1]);poly.append(a+t*(b-a))
            if inb:poly.append(b)
        for j in range(1,len(poly)-1):
            q=np.stack([poly[0],poly[j],poly[j+1]])
            yield q[:,:3],q[:,3:6],q[:,6:8],q[:,8:11]
for oi,ob in enumerate(B.objects):
    g=B.geometry[ob['g']];R=B.rotation(ob['rot']);v=(g['v']*ob['scale'])@R.T+ob['pos'];n=g['n']@R.T
    if ob['parent']=='Turntable_ROTATE':v+=[0,0,0]
    cam=(v-camera)@rot
    screen=np.stack([W/2+cam[:,0]/np.maximum(cam[:,2],.001)*focal,H/2-cam[:,1]/np.maximum(cam[:,2],.001)*focal],1)
    for vv,nn,tuv,cc in clipped_tris(g,v,n,cam):
        fn=np.cross(vv[1]-vv[0],vv[2]-vv[0])
        if np.dot(fn,camera-vv[0])<=0:continue
        a,b,c=np.stack([W/2+cc[:,0]/cc[:,2]*focal,H/2-cc[:,1]/cc[:,2]*focal],1)
        xmin=max(0,int(np.floor(min(a[0],b[0],c[0]))));xmax=min(W-1,int(np.ceil(max(a[0],b[0],c[0]))))
        ymin=max(0,int(np.floor(min(a[1],b[1],c[1]))));ymax=min(H-1,int(np.ceil(max(a[1],b[1],c[1]))))
        if xmax<xmin or ymax<ymin:continue
        den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-8:continue
        yy,xx=np.mgrid[ymin:ymax+1,xmin:xmax+1];xx=xx+.5;yy=yy+.5
        w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
        w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1
        visible=(w0>=-1e-5)&(w1>=-1e-5)&(w2>=-1e-5)
        inv=w0/cc[0,2]+w1/cc[1,2]+w2/cc[2,2];depth=1/np.maximum(inv,1e-9)
        view=zbuf[ymin:ymax+1,xmin:xmax+1];visible&=depth<view
        if not visible.any():continue
        ys,xs=np.nonzero(visible);weights=np.stack([w0[visible]/cc[0,2],w1[visible]/cc[1,2],w2[visible]/cc[2,2]],1)/inv[visible,None]
        py=ys+ymin;px=xs+xmin;zbuf[py,px]=depth[visible];normal[py,px]=weights@nn;world[py,px]=weights@vv
        uvbuf[py,px]=weights@tuv;mid[py,px]=ob['m']
    if oi%1000==0:print('Raster',oi,'/',len(B.objects),flush=True)
mask=mid>=0
normal/=np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True),1e-8)
base=np.zeros((H,W,3),np.float32);rough=np.ones((H,W),np.float32)*.65;metal=np.zeros((H,W),np.float32);em=np.zeros_like(base)
for i,m in enumerate(B.materials):
    sel=mid==i
    if not sel.any():continue
    if m['base']:
        tex=np.asarray(Image.open(B.TEX/m['base']).convert('RGB'),dtype=np.float32)/255
        uv=uvbuf[sel]%1;tx=np.minimum((uv[:,0]*tex.shape[1]).astype(int),tex.shape[1]-1);ty=np.minimum(((1-uv[:,1])*tex.shape[0]).astype(int),tex.shape[0]-1)
        base[sel]=tex[ty,tx]**2.2*np.array(m['color'])
    else:base[sel]=m['color']
    rough[sel]=m['rough'];metal[sel]=m['metal']
    if m['emission']:em[sel]=m['emission']
view=camera-world;view/=np.maximum(np.linalg.norm(view,axis=-1,keepdims=True),1e-6)
color=base*np.array([.085,.095,.12])*(.6+.4*np.maximum(normal[:,:,2:3],0))
lights=[]
for x in [-3.6,0,3.6]:
    for y in [-3.84,-.64,2.56,5.12]:lights.append(([x,y,4.13],[.83,.9,1],2.45))
for x in [-4.69,5.22]:lights.append(([x,5.5,2.55],[1,.72,.42],4.0))
for y in [.3,1.5,2.5]:lights.append(([5.6,y,2.7],[1,.74,.49],2.0))
for i in range(16):
    a=i*math.tau/16;lights.append(([3.77*np.cos(a),3.77*np.sin(a),.25],[1,.005,.02],.75))
for pos,tint,energy in lights:
    l=np.array(pos)-world;d2=(l*l).sum(-1);l/=np.maximum(np.sqrt(d2)[:,:,None],1e-5)
    ndl=np.maximum((normal*l).sum(-1),0);half=l+view;half/=np.maximum(np.linalg.norm(half,axis=-1,keepdims=True),1e-6)
    nh=np.maximum((normal*half).sum(-1),0)
    spec=(nh**(18+(1-rough)*100))*(.06+.22*metal)
    color+=(base*ndl[:,:,None]*(1-metal[:,:,None]*.55)+spec[:,:,None])*(energy/(d2[:,:,None]+1.5))*np.array(tint)
# Contact occlusion where vertical objects meet the floor.
for ob in B.objects:
    if any(s in ob['name'] for s in ['Column_anchor_plate','Drawer_cabinet_body','Wheel_rack_upright','Turntable_static_plinth','Lift_base_plate']):
        p=np.array(ob['pos']);r=.4 if ob['name']!='Turntable_static_plinth' else 3.85
        dist=((world[:,:,:2]-p[:2])**2).sum(-1)
        occ=np.exp(-dist/(r*r))*.35*(world[:,:,2]<.07)
        color*=1-occ[:,:,None]
color+=em
# Actual city panorama behind the open door, sampled by view rays.
xx,yy=np.meshgrid(np.arange(W)+.5,np.arange(H)+.5)
ray=forward+(xx-W/2)[:,:,None]/focal*right-(yy-H/2)[:,:,None]/focal*up
ray/=np.linalg.norm(ray,axis=-1,keepdims=True)
sky_path=B.OUT/'skybox/Midnight_City_Panorama.png'
if sky_path.exists():
    sky=np.asarray(Image.open(sky_path).convert('RGB'),np.float32)/255
    u=(.5+.37+np.arctan2(ray[:,:,0],ray[:,:,1])/math.tau)%1;v=.5-np.arcsin(ray[:,:,2])/math.pi
    sx=np.minimum((u*sky.shape[1]).astype(int),sky.shape[1]-1);sy=np.minimum((v*sky.shape[0]).astype(int),sky.shape[0]-1)
    color[~mask]=sky[sy,sx][~mask]**2.2*.6
else:color[~mask]=[.015,.024,.037]
# Filmic display transform and mild glow from emissive surfaces only.
bloom=np.maximum(color-1,0);color+=gaussian_filter(bloom,(4,4,0))*.15+gaussian_filter(bloom,(13,13,0))*.09
x=color*.75;display=np.clip((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14),0,1)**(1/2.2)
im=Image.fromarray(np.uint8(display*255));B.save_png(im,B.OUT/('Garage_Preview.png' if args.view=='garage' else 'Service_Bay_Detail.png'))
print('Saved preview',flush=True)
if args.view=='garage':
    D.finalize()
    print('Refreshed final GLBs',flush=True)
