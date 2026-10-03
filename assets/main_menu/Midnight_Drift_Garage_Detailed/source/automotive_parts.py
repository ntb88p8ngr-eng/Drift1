"""Hollow radial car tyres, alloy wheels and dimensioned automotive components.
Each tread block and wheel component is an individually editable mesh node.
Tyre dimensions follow width / aspect ratio / rim diameter, in metres.
"""
import math
import numpy as np
import base_geometry as B
from PIL import Image, ImageDraw, ImageFont

def lathe(name,profile,n=96):
    """Closed clockwise radial cross section revolved about the local Z axis."""
    profile=np.asarray(profile,float);L=len(profile)
    tang=np.roll(profile,-1,axis=0)-np.roll(profile,1,axis=0)
    pn=np.stack([-tang[:,1],tang[:,0]],1)
    pn/=np.linalg.norm(pn,axis=1,keepdims=True)
    v=[];ns=[];uv=[];faces=[]
    for i in range(n+1):
        a=math.tau*i/n;c,s=math.cos(a),math.sin(a)
        for j,(r,z) in enumerate(profile):
            v.append([r*c,r*s,z]);ns.append([pn[j,0]*c,pn[j,0]*s,pn[j,1]])
            uv.append([i/n,j/(L-1)])
    for i in range(n):
        for j in range(L):
            a=i*L+j;b=i*L+(j+1)%L;c=(i+1)*L+j;d=(i+1)*L+(j+1)%L
            faces.extend([[a,b,c],[b,d,c]])
    return B.mesh(name,v,faces,uv,ns)

cache={}
def tyre_dimensions(width_mm=225,aspect=45,rim_inches=17):
    w=width_mm/1000;inner=rim_inches*.0254/2
    return w,inner,inner+w*aspect/100

def tyre(width_mm=225,aspect=45,rim_inches=17,pattern=0):
    w,inner,outer=tyre_dimensions(width_mm,aspect,rim_inches)
    code=f'{width_mm}_{aspect}_R{rim_inches}'
    key=('tyre',code)
    if key not in cache:
        # Flat sidewall, rounded shoulder, broad cylindrical tread, hollow bead opening.
        p=[(inner-.005,w*.38),(inner+.010,w*.43),(inner+.031,w*.495),
           (outer-.040,w*.50),(outer-.019,w*.465),(outer-.004,w*.365),
           (outer-.004,-w*.365),(outer-.019,-w*.465),(outer-.040,-w*.50),
           (inner+.031,-w*.495),(inner+.010,-w*.43),(inner-.005,-w*.38),
           (inner+.010,-w*.29),(outer-.038,-w*.29),(outer-.038,w*.29),(inner+.010,w*.29)]
        cache[key]=lathe('Car_tyre_radial_profile_'+code,p)
    B.obj('Tyre_carcass_'+code,cache[key],B.rubber)
    # Five separated rows of curved tread blocks produce four real circumferential grooves.
    seg=64;band=w*.73/5;step=math.tau/seg
    for row in range(5):
        z=(-2+row)*band;z0=z-band*.42;z1=z+band*.42
        skew=(row-2)*step*.14*(1 if pattern%2 else -1)
        gkey=('tread',code,row,pattern%2)
        if gkey not in cache:
            # Wedge with a curved outer face; staggered lateral gaps stay genuinely open.
            points=[];faces=[];uv=[]
            for rr in [outer-.006,outer+.0015]:
                for zz in [z0,z1]:
                    for t in range(4):
                        a=(-.42+t*.28)*step+skew*(1 if zz==z1 else -1)
                        points.append([rr*math.cos(a),rr*math.sin(a),zz]);uv.append([t/3,0 if zz==z0 else 1])
            # indices inner bottom 0..3, inner top 4..7, outer bottom 8..11, outer top12..15
            for t in range(3):
                faces.extend([[8+t,9+t,12+t],[12+t,9+t,13+t],
                              [t,4+t,t+1],[4+t,5+t,t+1],
                              [t,t+1,8+t],[8+t,t+1,9+t],
                              [4+t,12+t,5+t],[12+t,13+t,5+t]])
            faces.extend([[0,8,4],[4,8,12],[3,7,11],[7,15,11]])
            cache[gkey]=B.mesh('Curved_tread_block_'+code+f'_row{row}',points,faces,uv)
        for i in range(seg):
            a=i*step+(row%2)*step*.42
            B.obj('Tread_block',cache[gkey],B.rubber,rot=(0,0,a))
    for s in [-1,1]:
        B.ring('Bead_lip',(0,0,s*w*.39),inner+.005,.0035,B.rubber,64,6)
        B.ring('Moulded_sidewall_line',(0,0,s*w*.498),outer-.047,.0012,B.rubber,64,4)
        B.ring('Inner_sidewall_line',(0,0,s*w*.486),inner+.035,.0012,B.rubber,64,4)
    sidewall_marking(code,width_mm,aspect,rim_inches,w,inner,outer)

def sidewall_marking(code,width_mm,aspect,rim_inches,w,inner,outer):
    key=('label',code)
    if key not in cache:
        # A small mapped arc carries actual tyre dimensions, subdued like moulded lettering.
        text=f'{width_mm}/{aspect} R{rim_inches}     RADIAL  /  TUBELESS'
        im=Image.new('RGB',(1024,128),(13,14,15));d=ImageDraw.Draw(im)
        font=ImageFont.truetype(B.font,49);d.text((28,35),text,fill=(41,43,45),font=font)
        name='Tyre_sidewall_'+code+'.png';B.save_png(im,B.TEX/name)
        material=B.mat('Moulded_tyresize_'+code,[1,1,1],base=name,rough=.88)
        r0=inner+.042;r1=min(outer-.051,r0+.023);a0=.2;a1=2.95
        v=[];uv=[];f=[];n=64
        for i in range(n+1):
            a=a0+(a1-a0)*i/n
            for r,t in [(r0,0),(r1,1)]:
                v.append([r*math.cos(a),r*math.sin(a),w*.501]);uv.append([i/n,t])
        for i in range(n):k=i*2;f.extend([[k,k+1,k+2],[k+1,k+3,k+2]])
        # Triangle winding positive Z: angle tangent then radius points gives negative; order above positive.
        cache[key]=(B.mesh('Tyre_size_marking_arc_'+code,v,f,uv,[[0,0,1]]*len(v)),material)
    g,m=cache[key];B.obj('Embossed_tyre_specification',g,m)
    B.obj('Embossed_tyre_specification_reverse',g,m,rot=(math.pi,0,0))

def alloy_wheel(width_mm=225,aspect=45,rim_inches=17,style=0):
    tyre(width_mm,aspect,rim_inches,style)
    w,inner,outer=tyre_dimensions(width_mm,aspect,rim_inches)
    key=('rim',width_mm,rim_inches)
    if key not in cache:
        cache[key]=lathe('Hollow_alloy_barrel',[(inner-.024,w*.43),(inner+.005,w*.43),
            (inner+.005,-w*.43),(inner-.024,-w*.43)],64)
    B.obj('Alloy_wheel_barrel',cache[key],B.chrome)
    B.ring('Polished_rim_lip',(0,0,w*.44),inner-.005,.009,B.chrome,64,6)
    B.ring('Rim_back_lip',(0,0,-w*.43),inner-.005,.007,B.chrome,64,6)
    z=w*.33;spokes=5 if style%2 else 6
    for i in range(spokes):
        a=i*math.tau/spokes
        for off in [-.045,.045]:
            B.beam('Cast_alloy_spoke',(.053*math.cos(a),.053*math.sin(a),z-.018),
                   ((inner-.022)*math.cos(a+off),(inner-.022)*math.sin(a+off),z+.012),.026,.019,B.chrome)
    B.cyl('Wheel_hub',(0,0,z),.065,.039,B.steel,32)
    B.cyl('Center_cap',(0,0,z+.025),.032,.013,B.chrome,24)
    for i in range(5):
        a=i*math.tau/5;B.cyl('Wheel_lug_nut',(.048*math.cos(a),.048*math.sin(a),z+.026),.009,.02,B.chrome,6)
    a=.66;B.cyl('Air_valve_stem',((inner-.025)*math.cos(a),(inner-.025)*math.sin(a),z+.03),.006,.037,B.rubber,12)
    B.cyl('Valve_dust_cap',((inner-.025)*math.cos(a),(inner-.025)*math.sin(a),z+.052),.007,.012,B.steel,12)

def brake_disc(radius=.155):
    key=('disc',radius)
    if key not in cache:
        cache[key]=lathe('Vented_brake_disc',[(.062,.011),(radius,.011),(radius,-.011),(.062,-.011)],64)
    B.obj('Brake_disc_rotor',cache[key],B.chrome)
    for i in range(40):
        a=i*math.tau/40
        B.box('Rotor_vent',((radius-.01)*math.cos(a),(radius-.01)*math.sin(a),0),(.022,.006,.008),B.dark,.001,rot=(0,0,a))
    B.cyl('Disc_hat',(0,0,.017),.07,.025,B.steel,40)
    B.cyl('Hub_bore',(0,0,.031),.029,.004,B.dark,32)
    for i in range(5):
        a=i*math.tau/5;B.cyl('Rotor_lug_hole',(.047*math.cos(a),.047*math.sin(a),.031),.006,.004,B.dark,12)
    for row,r in enumerate([radius*.65,radius*.83]):
        for i in range(14):
            a=(i+.4*row)*math.tau/14;B.cyl('Drilled_rotor_hole',(r*math.cos(a),r*math.sin(a),.0125),.0035,.003,B.dark,10)

def coilover(length=.49):
    B.cyl('Damper_body',(0,0,length*.25),.033,length*.5,B.steel,24)
    B.cyl('Damper_piston',(0,0,length*.65),.013,length*.5,B.chrome,16)
    B.cyl('Top_mount',(0,0,length-.04),.055,.021,B.red,24)
    for z in [length*.20,length*.70]:B.ring('Spring_perch',(0,0,z),.053,.008,B.steel,24,6)
    pts=[]
    for t in np.linspace(0,math.tau*7,113):pts.append([.047*math.cos(t),.047*math.sin(t),length*.21+t/(math.tau*7)*length*.47])
    for a,b in zip(pts[:-1],pts[1:]):
        a=np.array(a);b=np.array(b);v=b-a
        B.cyl('Coil_spring_wire',(a+b)/2,.006,np.linalg.norm(v),B.red,8,rot=(0,math.atan2(np.linalg.norm(v[:2]),v[2]),math.atan2(v[1],v[0])))
    B.box('Damper_lower_bracket',(0,0,.018),(.067,.045,.065),B.steel,.009)
    for x in [-.026,.026]:B.cyl('Mount_bolt',(x,0,length-.02),.008,.015,B.chrome,6)
