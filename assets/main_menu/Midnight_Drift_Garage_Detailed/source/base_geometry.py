"""Midnight Drift garage: authored geometry, UV textures, GLB/OBJ exporter.
Python 3.10+; numpy, Pillow, scipy. Units: metres, Z up in source.
"""
from pathlib import Path
import json, math, struct, io, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

OUT=Path(__file__).parent.parent/'output'/'Midnight_Drift_Garage_Detailed'
TEX=OUT/'textures'; TEX.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(4782)
materials=[]; geometry=[]; objects=[]

def save_png(im,path):
    stream=io.BytesIO();im.save(stream,format='PNG')
    p=Path(path);tmp=p.with_suffix('.png.new');tmp.write_bytes(stream.getvalue());tmp.replace(p)

def save_img(name,a):
    save_png(Image.fromarray(np.uint8(np.clip(a,0,255))),TEX/name)
    return name

def noise(n):
    a=np.zeros((n,n),np.float32)
    for s,w in [(8,.35),(32,.25),(128,.20),(512,.12),(n,.08)]:
        t=rng.random((min(s,n),min(s,n))).astype(np.float32)
        a+=np.asarray(Image.fromarray(t).resize((n,n),Image.Resampling.BICUBIC))*w
    return (a-.5)*2

def surface(name,color,metal=.0,rough=.7,n=1024,kind='metal'):
    f=noise(n); y,x=np.mgrid[:n,:n]
    base=np.array(color)[None,None,:]*(1+f[:,:,None]*.24)
    h=f*.12
    if kind=='concrete':
        pits=rng.random((n,n)); base+=((pits>.982)*11-(pits<.035)*12)[:,:,None]
        # Fine branching concrete fissures, tileable when repeated.
        crack=Image.new('L',(n,n)); d=ImageDraw.Draw(crack)
        for k in range(9):
            px,py=rng.integers(0,n,2); pts=[(int(px),int(py))]
            for i in range(8):
                px+=rng.integers(-50,51);py+=rng.integers(10,80);pts.append((int(px),int(py)))
            d.line(pts,fill=130,width=1)
        c=np.asarray(crack)/255.;base-=c[:,:,None]*24;h-=c*.4
    elif kind=='brushed':
        lines=gaussian_filter(rng.random((n,n)),(0,18));base+=(lines-.5)[:,:,None]*30;h+=(lines-.5)*.2
    elif kind=='diamond':
        xx=x%(n//16); yy=y%(n//16); q=n//16
        pat=((np.abs(xx-q*.5)+np.abs(yy-q*.5)*2)<q*.17).astype(float)
        pat=gaussian_filter(pat,.65);base+=pat[:,:,None]*32;h+=pat*.65
    elif kind=='wood':
        g=np.sin(y*.32+gaussian_filter(f,10)*20)+np.sin(y*.8+f*4)*.2
        base+=g[:,:,None]*9;h+=g*.12
    elif kind=='rubber':
        stripes=((y%(n//24))<3).astype(float);base+=stripes[:,:,None]*3;h+=stripes*.3
    elif kind=='paint':
        chips=gaussian_filter(rng.random((n,n)),.8)>.78
        base[chips]=[48,46,43];h-=chips*.25
    gy,gx=np.gradient(h);normal=np.stack([-gx*7,-gy*7,np.ones_like(h)],-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    orm=np.zeros((n,n,3));orm[:,:,0]=255;orm[:,:,1]=np.clip(rough+f*.08,.03,1)*255;orm[:,:,2]=metal*255
    return mat(name,color=[1,1,1],metal=metal,rough=rough,base=save_img(name+'_basecolor.png',base),normal=save_img(name+'_normal.png',(normal*.5+.5)*255),orm=save_img(name+'_orm.png',orm))

def mat(name,color,metal=0,rough=.6,base=None,normal=None,orm=None,emission=None):
    m=dict(name=name,color=color,metal=metal,rough=rough,base=base,normal=normal,orm=orm,emission=emission)
    materials.append(m);return len(materials)-1

concrete=surface('Concrete_floor',[42,44,47],rough=.68,n=2048,kind='concrete')
wall=surface('Concrete_wall',[32,34,36],rough=.94,n=2048,kind='concrete')
steel=surface('Aged_black_steel',[28,31,34],metal=.78,rough=.57,n=2048,kind='brushed')
chrome=surface('Brushed_alloy',[137,141,145],metal=.92,rough=.32,kind='brushed')
red=surface('Worn_crimson_paint',[91,9,15],metal=.5,rough=.62,kind='paint')
deckmat=surface('Turntable_diamond_plate',[34,37,41],metal=.78,rough=.51,n=2048,kind='diamond')
rubber=surface('Tyre_rubber',[13,14,15],rough=.86,kind='rubber')
wood=surface('Workbench_wood',[59,44,31],rough=.86,kind='wood')
cardboard=surface('Storage_cartons',[72,56,40],rough=.93,kind='wood')
dark=mat('Deep_charcoal',[.011,.014,.018],metal=.35,rough=.72)
white=mat('Ivory_paint',[.62,.63,.6],metal=.05,rough=.72)
neon=mat('Neon_red',[.5,.005,.01],rough=.3,emission=[8,.015,.035])
warm=mat('Warm_fixture',[.85,.76,.59],rough=.35,emission=[3.8,3.0,2.1])
cool=mat('Cool_fixture',[.7,.8,1],rough=.35,emission=[3.5,4.0,4.5])
amber=mat('Safety_amber',[.9,.4,.04],rough=.4,emission=[1.2,.32,.015])

def graphic(name,w,h,color):return Image.new('RGB',(w,h),color)
font='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def label_texture(name,lines,bg=(20,22,24),fg=(205,202,195),size=(1024,512)):
    im=graphic(name,*size,bg);d=ImageDraw.Draw(im)
    for text,y,sz,col in lines:
        f=ImageFont.truetype(font,sz);b=d.textbbox((0,0),text,font=f);xx=(size[0]-b[2])/2
        d.text((xx,y),text,font=f,fill=col or fg)
    save_png(im,TEX/(name+'.png'));return mat(name,[1,1,1],base=name+'.png',rough=.85)
logo=label_texture('Midnight_Drift_sign',[('MIDNIGHT',25,105,None),('DRIFT',138,170,(194,17,29)),('JAPAN  /  NIGHT WORKS',360,34,None)])
jdm=label_texture('JDM_banner',[('JDM',80,150,None),('CARS',330,50,None),('PEOPLE',440,50,None),('DRIVE',550,50,None),('CULTURE',660,50,None),('ALWAYS',770,50,None)],size=(512,1024))
baylabel=label_texture('Bay_label',[('BAY 01',80,116,None),('ROTATING DISPLAY',258,38,None),('KEEP CLEAR',365,42,(186,31,36))])
flagim=Image.new('RGB',(1024,640),(184,181,171));ImageDraw.Draw(flagim).ellipse((355,160,670,475),fill=(129,16,30));save_png(flagim,TEX/'Japanese_flag.png')
flagmat=mat('Japanese_flag',[1,1,1],base='Japanese_flag.png',rough=1)
# Original monochrome mountain road poster, no borrowed photographs.
im=Image.new('RGB',(768,1024),(41,43,44));d=ImageDraw.Draw(im)
for k,col in [(0,(95,97,96)),(1,(68,72,71)),(2,(39,43,42))]:
    pts=[(0,700)]
    for x in range(0,800,32):pts.append((x,int(250+k*130+90*np.sin(x*.012+k)+rng.integers(-45,45))))
    pts.extend([(768,850),(0,850)]);d.polygon(pts,fill=col)
road=[(420+int(160*np.sin(t*9)*(1-t)),int(400+t*400)) for t in np.linspace(0,1,120)]
d.line(road,fill=(141,143,135),width=18);d.line(road,fill=(61,64,62),width=11)
d.text((85,867),'LIVE TO DRIFT',font=ImageFont.truetype(font,61),fill=(188,180,165))
d.text((147,950),'MIDNIGHT PASS',font=ImageFont.truetype(font,26),fill=(151,153,147))
save_png(im,TEX/'Mountain_pass_poster.png');poster=mat('Mountain_pass_poster',[1,1,1],base='Mountain_pass_poster.png',rough=.95)
im=Image.new('RGB',(1024,256),(18,19,20));d=ImageDraw.Draw(im)
for x in range(-256,1300,160):d.polygon([(x,0),(x+80,0),(x-176,256),(x-256,256)],fill=(174,131,40))
save_png(im,TEX/'Hazard_stripes.png');hazard=mat('Hazard_stripes',[1,1,1],base='Hazard_stripes.png',rough=.8)

def mesh(name,v,f,uv=None,norm=None):
    v=np.asarray(v,np.float32);f=np.asarray(f,np.uint32).reshape(-1,3)
    if uv is None:uv=np.zeros((len(v),2),np.float32)
    if norm is None:
        norm=np.zeros_like(v);fn=np.cross(v[f[:,1]]-v[f[:,0]],v[f[:,2]]-v[f[:,0]])
        for k in range(3):np.add.at(norm,f[:,k],fn)
        norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-9)
    geometry.append(dict(name=name,v=v,f=f,uv=np.asarray(uv,np.float32),n=np.asarray(norm,np.float32)))
    return len(geometry)-1

def cuboid(w,d,h,bevel=0):
    # Flat-faced box with real edge chamfers. Faces have separate UV islands.
    half=np.array([w,d,h])/2;b=min(bevel,min(half)*.4)
    verts=[];faces=[];uvs=[];ns=[]
    def face(poly,normal):
        start=len(verts);normal=np.array(normal,float);normal/=np.linalg.norm(normal)
        # Orient outward.
        if np.dot(np.cross(np.array(poly[1])-poly[0],np.array(poly[2])-poly[0]),normal)<0:poly=poly[::-1]
        verts.extend(poly);ns.extend([normal]*len(poly))
        a=int(np.argmax(np.abs(normal)));axes=[k for k in range(3) if k!=a]
        for p in poly:uvs.append([p[axes[0]]/max(half[axes[0]]*2,.001)+.5,p[axes[1]]/max(half[axes[1]]*2,.001)+.5])
        for j in range(1,len(poly)-1):faces.append([start,start+j,start+j+1])
    for ax in range(3):
        i,j=[k for k in range(3) if k!=ax]
        for s in [-1,1]:
            p=[]
            for si,sj in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                a=np.zeros(3);a[ax]=s*half[ax];a[i]=si*(half[i]-b);a[j]=sj*(half[j]-b);p.append(a)
            normal=np.zeros(3);normal[ax]=s;face(p,normal)
    if b:
        for free in range(3):
            i,j=[k for k in range(3) if k!=free]
            for si in [-1,1]:
                for sj in [-1,1]:
                    p=[]
                    for end,side in [(-1,0),(1,0),(1,1),(-1,1)]:
                        a=np.zeros(3);a[free]=end*(half[free]-b)
                        a[i]=si*(half[i]-(b if side else 0));a[j]=sj*(half[j]-(0 if side else b));p.append(a)
                    normal=np.zeros(3);normal[i]=si;normal[j]=sj;face(p,normal)
        for sx in [-1,1]:
            for sy in [-1,1]:
                for sz in [-1,1]:
                    signs=np.array([sx,sy,sz]);p=[]
                    for i in range(3):
                        a=half-b;a=a.copy();a[i]=half[i];p.append(a*signs)
                    face(p,signs)
    return mesh(f'Beveled_box_{w}_{d}_{h}_{b}',verts,faces,uvs,ns)

cache={}
def obj(name,g,m,pos=(0,0,0),rot=(0,0,0),parent='Garage',scale=(1,1,1)):
    objects.append(dict(name=name,g=g,m=m,pos=list(pos),rot=list(rot),parent=parent,scale=list(scale)))
    return objects[-1]
def box(name,pos,size,m,bevel=.012,rot=(0,0,0),parent='Garage'):
    key=tuple(size)+(bevel,)
    if key not in cache:cache[key]=cuboid(*size,bevel)
    return obj(name,cache[key],m,pos,rot,parent)

def cylinder_geom(r,h,n=32,r2=None):
    r2=r if r2 is None else r2;v=[];uv=[];ns=[];f=[]
    for i in range(n+1):
        a=i/n*math.tau;c,s=np.cos(a),np.sin(a)
        for z,rr,t in [(-h/2,r,0),(h/2,r2,1)]:
            v.append([rr*c,rr*s,z]);uv.append([i/n,t]);normal=np.array([c,s,(r-r2)/h]);ns.append(normal/np.linalg.norm(normal))
    for i in range(n):k=i*2;f.extend([[k,k+2,k+1],[k+1,k+2,k+3]])
    for top,rr in [(False,r),(True,r2)]:
        off=len(v);v.append([0,0,h/2 if top else -h/2]);uv.append([.5,.5]);ns.append([0,0,1 if top else -1])
        for i in range(n+1):
            a=i/n*math.tau;v.append([rr*np.cos(a),rr*np.sin(a),h/2 if top else -h/2]);uv.append([.5+.5*np.cos(a),.5+.5*np.sin(a)]);ns.append([0,0,1 if top else -1])
        for i in range(n):f.append([off,off+i+1,off+i+2] if top else [off,off+i+2,off+i+1])
    return mesh(f'Cylinder_{r}_{h}_{n}_{r2}',v,f,uv,ns)
def cyl(name,pos,r,h,m,n=32,rot=(0,0,0),parent='Garage',r2=None):
    key=('cyl',r,h,n,r2)
    if key not in cache:cache[key]=cylinder_geom(r,h,n,r2)
    return obj(name,cache[key],m,pos,rot,parent)

def ring_geom(r,minor,n=128,k=10,start=0,end=math.tau):
    v=[];f=[];uv=[];ns=[]
    for i in range(n+1):
        a=start+(end-start)*i/n
        for j in range(k+1):
            b=j/k*math.tau;c,s=np.cos(a),np.sin(a);cb,sb=np.cos(b),np.sin(b)
            v.append([(r+minor*cb)*c,(r+minor*cb)*s,minor*sb]);ns.append([cb*c,cb*s,sb]);uv.append([i/n,j/k])
    for i in range(n):
        for j in range(k):q=i*(k+1)+j;f.extend([[q,q+k+1,q+1],[q+1,q+k+1,q+k+2]])
    return mesh(f'Torus_{r}_{minor}_{start}_{end}',v,f,uv,ns)
def ring(name,pos,r,minor,m,n=96,k=8,rot=(0,0,0),parent='Garage',start=0,end=math.tau):
    key=('ring',r,minor,n,k,start,end)
    if key not in cache:cache[key]=ring_geom(r,minor,n,k,start,end)
    return obj(name,cache[key],m,pos,rot,parent)
def beam(name,a,b,width,depth,m,parent='Garage'):
    a,b=np.array(a,float),np.array(b,float);v=b-a;L=np.linalg.norm(v)
    ry=math.atan2(np.sqrt(v[0]**2+v[1]**2),v[2]);rz=math.atan2(v[1],v[0])
    return box(name,(a+b)/2,(width,depth,L),m,rot=(0,ry,rz),parent=parent)
def plaque(name,pos,w,h,m,rot=(math.pi/2,0,0)):
    return box(name,pos,(w,.015,h),m,bevel=0,rot=(0,0,0))
def panel_image(name,pos,w,h,m):
    # Upright XZ image, outward normal towards -Y; UV top stays top.
    v=[[-w/2,0,-h/2],[w/2,0,-h/2],[w/2,0,h/2],[-w/2,0,h/2]]
    g=mesh(name,v,[[0,1,2],[0,2,3]],[[0,0],[1,0],[1,1],[0,1]],[[0,-1,0]]*4)
    return obj(name,g,m,pos)

# Full shell, floor and architectural expansion joints.
box('Foundation',(0,0,-.16),(17.4,20.4,.3),wall,.04)
box('Floor_surface',(0,0,.015),(17,20,.035),concrete,0)
for x in np.arange(-8,8.1,2):box('Floor_expansion_X',(float(x),0,.036),(.008,20,.006),dark,0)
for y in np.arange(-10,10.1,2):box('Floor_expansion_Y',(0,float(y),.036),(17,.008,.006),dark,0)
for x in [-8.55,8.55]:
    box('Concrete_side_wall',(x,0,3.1),(.28,20,6.2),wall,.025)
    for y in np.arange(-9.5,10,1):box('Corrugated_side_rib',(x-np.sign(x)*.17,float(y),3.4),(.065,.06,5.2),steel,.005)
    box('Red_wall_datum',(x-np.sign(x)*.21,0,1.12),(.016,20,.08),red,0)
    for z in [.22,1.8,5.5]:box('Horizontal_wall_rail',(x-np.sign(x)*.24,0,z),(.13,20,.13),steel,.01)
# Back wall with real open roller door, 8.6m wide.
for x in [-6.52,6.52]:box('Rear_wall_wing',(x,10,3.1),(4.15,.3,6.2),wall,.02)
box('Rear_door_header',(0,10,5.75),(8.9,.35,.9),steel,.02)
box('Roof',(0,0,6.27),(17.4,20.3,.2),steel,.015)
for x in [-8.15,8.15]:
    for y in [-9.3,-5,0,5,9.5]:
        box('Column_web',(x,y,3.0),(.14,.36,6),steel,.008)
        for xx in [-.19,.19]:box('Column_flange',(x+xx,y,3),(.12,.47,6),steel,.012)
        box('Column_anchor_plate',(x,y,.1),(.7,.72,.12),steel,.02)
        for dx in [-.25,.25]:
            for dy in [-.25,.25]:cyl('Column_anchor_bolt',(x+dx,y+dy,.19),.045,.07,chrome,n=6)
for y in [-8,-4,0,4,8]:
    for z in [5.56,6.04]:box('Roof_truss_chord',(0,y,z),(16.5,.16,.18),steel,.012)
    for x in np.arange(-8,8,2):
        beam('Truss_diagonal',(x,y,5.56),(x+2,y,6.04),.09,.09,steel)
        beam('Truss_diagonal',(x,y,6.04),(x+2,y,5.56),.075,.075,steel)
for x in [-6,-3,0,3,6]:box('Ceiling_purlin',(x,0,6.03),(.12,20,.15),steel,.006)
# Conduits, joints and overhead ventilation.
for x,z,r in [(-7.6,5.22,.06),(-7.35,5.28,.045),(7.55,5.4,.075)]:
    cyl('Longitudinal_service_pipe',(x,0,z),r,19.8,chrome,rot=(math.pi/2,0,0))
    for y in np.arange(-9,10,2):ring('Pipe_collar',(x,float(y),z),r+.005,.013,steel,n=16,k=6,rot=(math.pi/2,0,0))
cyl('Ventilation_main',(5.8,0,5.8),.26,18.8,steel,48,rot=(math.pi/2,0,0))
for y in [-8,-4,0,4,8]:ring('Duct_band',(5.8,y,5.8),.265,.025,chrome,n=32,k=6,rot=(math.pi/2,0,0))
# Door guide rails, rolled-up shutter slats, drive casing.
for x in [-4.47,4.47]:
    box('Shutter_track',(x,9.77,2.8),(.22,.2,5.6),steel,.012)
    box('Shutter_track_inner',(x,9.64,2.8),(.055,.06,5.55),chrome,.004)
    for z in np.arange(.35,5.5,.6):cyl('Shutter_track_screw',(x,9.6,float(z)),.028,.028,chrome,6,rot=(math.pi/2,0,0))
for z in np.arange(4.8,5.65,.075):box('Raised_shutter_slat',(0,9.65,float(z)),(8.8,.09,.065),steel,.01)
cyl('Shutter_roller',(0,9.96,5.86),.25,9,steel,48,rot=(0,math.pi/2,0))
box('Shutter_motor',(4.8,9.7,5.62),(.52,.48,.6),red,.05)
box('Shutter_control',(4.83,9.35,1.5),(.28,.16,.43),white,.025)
for z,m in [(1.6,neon),(1.43,dark)]:cyl('Door_control_button',(4.83,9.25,z),.035,.025,m,16,rot=(math.pi/2,0,0))
# Front facade edges: central 12m opening for camera and vehicles.
for x in [-7.35,7.35]:box('Front_facade_wing',(x,-10,3.1),(2.3,.2,6.2),wall,.02)
box('Front_lintel',(0,-10,5.96),(12.5,.24,.5),steel,.02)

# Turntable: static foundation and smooth full-rotation deck pivot at centre.
P=(0,1,.0)
cyl('Turntable_static_plinth',(0,1,.12),3.78,.18,steel,192)
cyl('Turntable_static_shadow_gap',(0,1,.23),3.66,.09,dark,192)
cyl('Turntable_rotating_deck',(0,0,.37),3.62,.19,deckmat,192,parent='Turntable_ROTATE')
for z,r in [(.27,3.705),(.34,3.68),(.435,3.66)]:
    ring('Continuous_red_neon',(0,1,z),r,.021,neon,n=256,k=8,parent='Platform_Static')
ring('Deck_outer_alloy_trim',(0,0,.47),3.575,.014,chrome,n=256,k=6,parent='Turntable_ROTATE')
ring('Inner_red_neon',(0,0,.475),3.16,.014,neon,n=256,k=6,parent='Turntable_ROTATE')
ring('Inner_track',(0,0,.474),2.9,.012,steel,n=192,k=6,parent='Turntable_ROTATE')
for i in range(24):
    a=i*math.tau/24
    # Faceted skirt panels, paired recessed fasteners and expansion grooves.
    r=3.62;x,y=r*np.cos(a),r*np.sin(a)
    box('Turntable_skirt_segment',(x,y,.35),(.045,.91,.22),steel,.009,rot=(0,0,a),parent='Turntable_ROTATE')
    for zz in [.285,.417]:
        cyl('Skirt_hex_bolt',((r+.03)*np.cos(a),(r+.03)*np.sin(a),zz),.018,.018,chrome,6,rot=(0,math.pi/2,a),parent='Turntable_ROTATE')
    if i%2==0:beam('Deck_radial_seam',(2.92*np.cos(a),2.92*np.sin(a),.474),(3.53*np.cos(a),3.53*np.sin(a),.474),.008,.008,dark,parent='Turntable_ROTATE')
for i in range(48):
    a=i*math.tau/48;cyl('Deck_perimeter_rivet',(3.48*np.cos(a),3.48*np.sin(a),.478),.015,.009,chrome,8,parent='Turntable_ROTATE')
for side in [-1,1]:
    for y in [-3.4,5.4]:box('Safety_floor_marking',(side*3.9,y,.041),(1.1,.17,.008),hazard,0)
panel_image('Platform_spec_plate',(0,-2.637,.35),1.65,.17,baylabel)

# Rear work area: cabinetry without nonsense wall tools.
def cabinet(x,y,width=1.65,m=steel):
    box('Drawer_cabinet_body',(x,y,.8),(width,.75,1.35),m,.045)
    box('Cabinet_steel_counter',(x,y,1.53),(width+.09,.85,.08),chrome,.015)
    for i in range(6):
        z=.26+i*.205;box('Drawer_front',(x,y-.39,z),(width-.11,.045,.18),m,.012)
        box('Drawer_handle',(x,y-.435,z+.03),(width-.32,.045,.028),chrome,.009)
        box('Drawer_seam',(x,y-.42,z-.10),(width-.14,.016,.012),dark,0)
    for dx in [-width*.37,width*.37]:
        for dy in [-.26,.26]:cyl('Cabinet_castor',(x+dx,y+dy,.13),.08,.055,rubber,20,rot=(0,math.pi/2,0))
cabinet(-6.7,8.9,2.0,red);cabinet(6.7,8.9,2.0,steel)
for x in [-6.7,6.7]:
    box('Workstation_backplate',(x,9.42,2.14),(2.15,.08,.9),steel,.016)
    box('Workstation_upper_shelf',(x,9.21,2.76),(2.4,.52,.075),steel,.012)
    box('Workbench_light_housing',(x,9.12,2.70),(2.0,.18,.09),steel,.015)
    box('Workbench_warm_light',(x,9.08,2.643),(1.88,.105,.016),warm,.005)
    for ix in range(17):
        for iz in range(6):cyl('Backplate_perforation',(x-.94+ix*.117,9.371,1.82+iz*.13),.009,.004,dark,8,rot=(math.pi/2,0,0))
    for k in range(4):
        px=x-.7+k*.43;cyl('Oil_bottle_body',(px,8.95,1.72),.065,.3,red if k%2 else steel,16)
        cyl('Oil_bottle_cap',(px,8.95,1.9),.027,.055,dark,12)
    box('Parts_case',(x+.55,9.1,2.95),(.65,.32,.32),dark,.03)
    box('Parts_case_handle',(x+.55,9.1,3.13),(.19,.05,.055),chrome,.009)
box('Central_wall_sign_back',(6.55,9.7,4.2),(3.25,.10,1.78),steel,.02)
panel_image('Midnight_Drift_wall_sign',(6.55,9.632,4.2),3.1,1.6,logo)
panel_image('JDM_fabric_banner',(-5.45,9.76,4.0),1.05,2.1,jdm)
panel_image('Japanese_flag',(-7.15,9.76,4.0),1.4,.9,flagmat)
# Left wall parallel to Y: shelving and wheels, not cars.
def wheel(name,pos,r=.41,rotation=(math.pi/2,0,0)):
    ring(name+'_tyre',pos,r-.07,.105,rubber,48,10,rotation)
    ring(name+'_alloy_lip',pos,r-.145,.022,chrome,48,6,rotation)
    # Build rim and spokes in local XY, rotate the objects as a group transform.
    for i in range(10):
        a=i*math.tau/10
        # Wheel is in XZ plane, rim axis along Y.
        beam(name+'_spoke',(pos[0]+.075*np.cos(a),pos[1],pos[2]+.075*np.sin(a)),(pos[0]+(r-.145)*np.cos(a+.10),pos[1],pos[2]+(r-.145)*np.sin(a+.10)),.024,.037,chrome)
    cyl(name+'_hub',pos,.075,.065,steel,24,rot=rotation)
    for i in range(5):
        a=i*math.tau/5;cyl(name+'_lug',(pos[0]+.049*np.cos(a),pos[1]-.04,pos[2]+.049*np.sin(a)),.012,.02,chrome,6,rot=rotation)
for x in [-6.4,6.4]:
    for y in [4.9]:
        for dx in [-1.05,1.05]:box('Wheel_rack_upright',(x+dx,y,2.0),(.07,.07,3.75),steel,.005)
        for z in [.16,1.55,2.82,3.85]:box('Wheel_rack_shelf',(x,y,z),(2.24,.9,.055),steel,.006)
        for xx in [-.55,.55]:
            for z in [2.04,3.28]:wheel('Display_wheel',(x+xx,y-.16,z),r=.43)
        for xx in [-.65,0,.65]:box('Boxed_spares',(x+xx,y,.5),(.55,.55,.62),cardboard,.015)
for x in [-7,7]:
    for z in [.24,.46,.68]:ring('Spare_tyre_stack',(x,2.3,z),.36,.105,rubber,48,10)
cabinet(-6.6,-.5,1.7,red)
box('Left_workbench',( -7.1,-3.1,1.12),(1.7,2.6,.09),wood,.025)
for x in [-7.8,-6.4]:
    for y in [-4.25,-1.95]:box('Workbench_leg',(x,y,.59),(.09,.09,1.1),steel,.006)
box('Closed_storage_case',(-7.1,-2.7,1.36),(.8,.64,.38),steel,.035)
box('Storage_case_latch',(-7.1,-3.037,1.35),(.17,.025,.08),chrome,.006)
# Rear personnel door, louvred switchboard, extinguisher.
box('Personnel_door_frame',(7.0,7.15,1.2),(1.16,.11,2.4),steel,.025)
box('Personnel_door',(7.0,7.05,1.18),(.99,.075,2.25),red,.015)
box('Personnel_door_handle',(7.38,6.98,1.12),(.1,.10,.035),chrome,.006)
box('Door_upper_window',(7,6.998,1.82),(.55,.02,.44),dark,.012)
box('Electrical_service_box',(-7.5,7.0,1.85),(.65,.24,1.0),steel,.035)
for z in np.linspace(1.62,2.16,10):box('Service_box_vent',(-7.5,6.867,float(z)),(.45,.018,.018),dark,.005)
cyl('Fire_extinguisher',(-5.04,9.3,.6),.14,.68,red,32)
cyl('Extinguisher_valve',(-5.04,9.3,.99),.05,.12,chrome,12)
box('Extinguisher_handle',(-5.04,9.3,1.03),(.2,.055,.065),steel,.008)
beam('Extinguisher_hose',(-4.94,9.3,1.0),(-4.85,9.3,.58),.022,.022,rubber)
# Pneumatic coiled hose with proper helix geometry.
v=[];f=[];uv=[];nn=[];N=340;K=6
for i in range(N+1):
    t=i/N;a=t*math.tau*18;centre=np.array([5.05+.11*np.cos(a),9.15+.11*np.sin(a),2.55-t*1.45])
    radial=np.array([np.cos(a),np.sin(a),0]);other=np.array([0,0,1.])
    for j in range(K):
        b=j/K*math.tau;n=radial*np.cos(b)+other*np.sin(b);v.append(centre+n*.013);nn.append(n);uv.append([t,j/K])
for i in range(N):
    for j in range(K):q=i*K+j;qn=i*K+(j+1)%K;f.extend([[q,q+K,qn],[qn,q+K,qn+K]])
obj('Coiled_air_hose',mesh('Coiled_air_hose',v,f,uv,nn),red)
# Floor drainage channel, grated slots.
box('Drain_channel',(0,7.0,.041),(10,.22,.018),steel,0)
for x in np.arange(-4.9,5,.1):box('Drain_slot',(float(x),7,.052),(.025,.16,.008),dark,0)
# Suspended lighting: cool overhead and red wall strips.
for x in [-4.5,0,4.5]:
    for y in [-6,-1,4,8]:
        box('Ceiling_light_fixture',(x,y,5.35),(2.1,.22,.12),steel,.024)
        box('Ceiling_light_diffuser',(x,y,5.281),(1.98,.14,.025),cool,.005)
        for dx in [-.8,.8]:cyl('Fixture_suspension',(x+dx,y,5.55),.008,.32,steel,8)
for x in [-8.15,8.15]:
    for y in [-6,-1,4,8]:
        box('Red_wall_light_housing',(x,y,2.9),(.16,1.65,.10),steel,.012)
        box('Red_wall_light',(x-np.sign(x)*.09,y,2.9),(.025,1.53,.035),neon,.005)
# Minimal exterior apron only; skyline belongs to separate skybox.
box('Outside_asphalt',(0,16,-.02),(22,12,.11),concrete,0,parent='Exterior')
for x in [-4.8,4.8]:
    for y in [11.2,13.7]:
        cyl('Safety_bollard',(x,y,.51),.11,.95,steel,20,parent='Exterior')
        for z in [.2,.45,.7]:cyl('Bollard_reflector',(x,y,z),.114,.07,hazard,20,parent='Exterior')

def rotation(r):
    x,y,z=r;cx,sx=np.cos(x),np.sin(x);cy,sy=np.cos(y),np.sin(y);cz,sz=np.cos(z),np.sin(z)
    return np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])@np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])
def quaternion(r):
    x,y,z=np.array(r)/2;cx,sx=np.cos(x),np.sin(x);cy,sy=np.cos(y),np.sin(y);cz,sz=np.cos(z),np.sin(z)
    return [sx*cy*cz-cx*sy*sz,cx*sy*cz+sx*cy*sz,cx*cy*sz-sx*sy*cz,cx*cy*cz+sx*sy*sz]

def export_glb(path,platform_only=False):
    selected=[o for o in objects if not platform_only or o['parent'] in ['Platform_Static','Turntable_ROTATE'] or o['name'].startswith('Turntable_')]
    material_ids=sorted(set(o['m'] for o in selected));material_map={i:k for k,i in enumerate(material_ids)}
    data=bytearray();views=[];access=[]
    def buf(raw,target=None):
        while len(data)%4:data.append(0)
        off=len(data);data.extend(raw);v={'buffer':0,'byteOffset':off,'byteLength':len(raw)}
        if target:v['target']=target
        views.append(v);return len(views)-1
    def acc(a,typ,comp=5126,target=34962,bounds=False):
        a=np.asarray(a,dtype='<f4' if comp==5126 else '<u4');v=buf(a.tobytes(),target)
        z=dict(bufferView=v,componentType=comp,count=len(a),type=typ)
        if bounds:z.update(min=np.atleast_1d(a.min(axis=0)).tolist(),max=np.atleast_1d(a.max(axis=0)).tolist())
        access.append(z);return len(access)-1
    textures=[];images=[];texmap={}
    def tex(name):
        if name in texmap:return texmap[name]
        images.append(dict(name=name,bufferView=buf((TEX/name).read_bytes()),mimeType='image/png'))
        textures.append(dict(sampler=0,source=len(images)-1));texmap[name]=len(textures)-1;return texmap[name]
    gm=[];usedext=['KHR_materials_emissive_strength','KHR_lights_punctual']
    for mid in material_ids:
        m=materials[mid]
        p=dict(baseColorFactor=m['color']+[1],metallicFactor=m['metal'],roughnessFactor=m['rough'])
        if m['base']:p['baseColorTexture']={'index':tex(m['base'])}
        if m['orm']:p.update(metallicRoughnessTexture={'index':tex(m['orm'])},metallicFactor=1,roughnessFactor=1)
        q=dict(name=m['name'],pbrMetallicRoughness=p,doubleSided=False)
        if m['normal']:q['normalTexture']={'index':tex(m['normal']),'scale':.8}
        if m['orm']:q['occlusionTexture']={'index':tex(m['orm'])}
        if m['emission']:
            strength=max(m['emission']);q['emissiveFactor']=[c/strength for c in m['emission']];q['extensions']={'KHR_materials_emissive_strength':{'emissiveStrength':strength}}
        gm.append(q)
    nodes=[dict(name='Midnight_Drift_Garage',rotation=quaternion([-math.pi/2,0,0]),children=[1,2,3,4],extras={'units':'metres','source':'Reconstructed from 2D garage reference; no cars','front':'negative source Y'})]
    if platform_only:nodes[0]['translation']=[0,0,1]
    nodes.extend([dict(name='Garage',children=[]),dict(name='Platform_Static',children=[]),dict(name='Turntable_ROTATE',translation=[0,1,0],children=[],extras={'pivot':'vertical centre','deck_height_m':.465,'animation':'20 second full turn; loop in engine'}),dict(name='Exterior',children=[])])
    groups={'Garage':1,'Platform_Static':2,'Turntable_ROTATE':3,'Exterior':4};ms=[];meshmap={}
    for parent in dict.fromkeys(o['parent'] for o in selected):
        if parent not in groups:
            origin=globals().get('assembly_origins',{}).get(parent,[0,0,0])
            nodes.append(dict(name=parent,translation=origin,children=[]));groups[parent]=len(nodes)-1;nodes[1]['children'].append(groups[parent])
    for ob in selected:
        key=(ob['g'],ob['m'])
        if key not in meshmap:
            g=geometry[ob['g']]
            guv=g['uv'].copy();guv[:,1]=1-guv[:,1]
            at={k:acc(guv if a=='uv' else g[a],t,bounds=k=='POSITION') for k,a,t in [('POSITION','v','VEC3'),('NORMAL','n','VEC3'),('TEXCOORD_0','uv','VEC2')]}
            idx=acc(g['f'].reshape(-1),'SCALAR',5125,34963)
            ms.append(dict(name=g['name'],primitives=[dict(attributes=at,indices=idx,material=material_map[ob['m']],mode=4)]));meshmap[key]=len(ms)-1
        nd=dict(name=ob['name'],mesh=meshmap[key],translation=ob['pos'],rotation=quaternion(ob['rot']),scale=ob['scale'])
        if ob['parent'] in globals().get('assembly_origins',{}):
            nd['translation']=(np.array(ob['pos'])-assembly_origins[ob['parent']]).tolist()
        if ob.get('assembly'):nd['extras']={'assembly':ob['assembly'],'separate_component':True}
        nodes.append(nd);nodes[groups[ob['parent']]]['children'].append(len(nodes)-1)
    times=np.linspace(0,20,17,dtype=np.float32);ang=times/20*math.tau
    quats=np.stack([np.zeros(17),np.zeros(17),np.sin(ang/2),np.cos(ang/2)],1)
    anim=[dict(name='Turntable_360_20s',samplers=[dict(input=acc(times,'SCALAR',target=None,bounds=True),output=acc(quats,'VEC4',target=None),interpolation='LINEAR')],channels=[dict(sampler=0,target={'node':3,'path':'rotation'})])]
    lights=[]
    if not platform_only:
        for x in [-3.6,0,3.6]:
            for y in [-3.8,-.64,2.56,5.12]:
                lights.append(dict(name='Overhead_work_light',type='point',color=[.8,.87,1.],intensity=90,range=9))
                nodes.append(dict(name='Overhead_light',translation=[x,y,4.13],extensions={'KHR_lights_punctual':{'light':len(lights)-1}}));nodes[1]['children'].append(len(nodes)-1)
        for x in [-5.22,5.22]:
            lights.append(dict(name='Workbench_light',type='point',color=[1,.78,.53],intensity=90,range=5))
            nodes.append(dict(name='Workbench_light',translation=[x,5.5,2.55],extensions={'KHR_lights_punctual':{'light':len(lights)-1}}));nodes[1]['children'].append(len(nodes)-1)
    for i in range(12):
        a=i*math.tau/12;lights.append(dict(name='Platform_neon_fill',type='point',color=[1,.005,.015],intensity=9,range=2.5))
        nodes.append(dict(name='Neon_light',translation=[3.72*np.cos(a),1+3.72*np.sin(a),.23],extensions={'KHR_lights_punctual':{'light':len(lights)-1}}));nodes[2]['children'].append(len(nodes)-1)
    gltf=dict(asset={'version':'2.0','generator':'Midnight Drift procedural geometry exporter'},scene=0,scenes=[dict(name='Midnight Drift garage',nodes=[0])],nodes=nodes,meshes=ms,materials=gm,textures=textures,images=images,samplers=[dict(magFilter=9729,minFilter=9987,wrapS=10497,wrapT=10497)],accessors=access,bufferViews=views,buffers=[dict(byteLength=len(data))],animations=anim,extensionsUsed=usedext,extensions={'KHR_lights_punctual':{'lights':lights}})
    jb=json.dumps(gltf,separators=(',',':')).encode();jb+=b' '*((-len(jb))%4);data+=b'\0'*((-len(data))%4)
    with open(path,'wb') as out:
        out.write(struct.pack('<III',0x46546c67,2,12+8+len(jb)+8+len(data)));out.write(struct.pack('<II',len(jb),0x4e4f534a));out.write(jb);out.write(struct.pack('<II',len(data),0x004e4942));out.write(data)
    return gltf

def export_obj():
    with open(OUT/'Midnight_Drift_Garage.mtl','w') as out:
        for m in materials:
            out.write('\nnewmtl '+m['name']+'\nKd '+' '.join(map(str,m['color']))+'\nKs .2 .2 .2\nNs 64\n')
            if m['emission']:out.write('Ke '+' '.join(map(str,m['emission']))+'\n')
            if m['base']:out.write('map_Kd textures/'+m['base']+'\n')
            if m['normal']:out.write('map_Bump textures/'+m['normal']+'\n')
    with open(OUT/'Midnight_Drift_Garage.obj','w') as out:
        out.write('# Units metres; Z up; GLB recommended for PBR and animation\nmtllib Midnight_Drift_Garage.mtl\n');off=1
        for ob in objects:
            g=geometry[ob['g']];R=rotation(ob['rot']);v=(g['v']*ob['scale'])@R.T+ob['pos'];n=g['n']@R.T
            if ob['parent']=='Turntable_ROTATE':v+=[0,1,0]
            out.write('o '+ob['name']+'\nusemtl '+materials[ob['m']]['name']+'\n')
            for p in v:out.write('v %.6f %.6f %.6f\n'%tuple(p))
            for p in g['uv']:out.write('vt %.6f %.6f\n'%tuple(p))
            for p in n:out.write('vn %.6f %.6f %.6f\n'%tuple(p))
            for face in g['f']:
                ids=face+off;out.write('f '+' '.join(f'{i}/{i}/{i}' for i in ids)+'\n')
            off+=len(v)

if __name__=='__main__':
    g=export_glb(OUT/'Midnight_Drift_Garage.glb')
    export_glb(OUT/'Neon_Turntable.glb',True);export_obj()
    print(json.dumps({'objects':len(objects),'unique_geometry':len(geometry),'triangles':sum(len(geometry[o['g']]['f']) for o in objects),'materials':len(materials),'GLB_MB':round((OUT/'Midnight_Drift_Garage.glb').stat().st_size/1e6,2)}))
