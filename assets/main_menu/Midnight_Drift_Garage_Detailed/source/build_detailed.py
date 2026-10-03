"""Dense Midnight Drift workshop, built from separately editable components."""
import base_geometry as B
import automotive_parts as A
import numpy as np
import math, json, shutil, csv
from pathlib import Path

rng=np.random.default_rng(81274)
architecture=('Foundation','Floor_','Concrete_','Corrugated_','Red_wall_datum','Horizontal_wall_','Rear_wall','Rear_door_header','Roof','Column_','Truss_','Ceiling_purlin','Longitudinal_','Pipe_collar','Ventilation_','Duct_band','Shutter_','Raised_shutter','Front_','Drain_','Ceiling_light','Fixture_','Red_wall_light','Outside_','Safety_bollard','Bollard_')
S=np.array([.80,.64,.80]);baked={}
remove=('Left_workbench','Workbench_leg','Closed_storage_case','Storage_case_latch','Central_wall_sign_back','Midnight_Drift_wall_sign','Platform_spec_plate','Continuous_red_neon','Inner_red_neon','Personnel_door_frame','Personnel_door','Personnel_door_handle','Door_upper_window','Workstation_backplate','Backplate_perforation')
kept=[]
for o in B.objects:
    if o['name'] in remove:continue
    if o['name'].startswith(('Wheel_rack_','Display_wheel','Spare_tyre_stack','Boxed_spares')):continue
    if o['name'].startswith(('Drawer_','Cabinet_')) and -2<o['pos'][1]<2:continue
    if o['name'].startswith(architecture) or o['parent']=='Exterior':
        key=(o['g'],tuple(o['rot']))
        if key not in baked:
            g=B.geometry[o['g']];R=B.rotation(o['rot']);v=(g['v']@R.T)*S;n=(g['n']@R.T)/S;n/=np.linalg.norm(n,axis=1,keepdims=True)
            baked[key]=B.mesh('Architectural_'+g['name'],v,g['f'],g['uv'],n)
        o['g']=baked[key];o['pos']=(np.array(o['pos'])*S).tolist();o['rot']=[0,0,0]
        o['parent']='Architecture' if o['parent']!='Exterior' else 'Exterior'
    elif o['parent'] in ('Platform_Static','Turntable_ROTATE') or o['name'].startswith('Turntable_'):
        if o['parent']!='Turntable_ROTATE':o['pos'][1]-=1;o['parent']='Platform_Static'
        if o['name']=='Turntable_rotating_deck':o['m']=B.steel
    else:
        o['pos'][0]*=.78;o['pos'][1]*=.64
        if o['name'] in ['Electrical_service_box','Service_box_vent']:
            R=B.rotation((0,0,math.pi/2));o['pos']=(R@(np.array(o['pos'])-[-5.85,4.48,1.85])+[-6.50,4.18,2.70]).tolist();o['rot']=list((0,0,math.pi/2))
        if o['pos'][0]<0 and o['pos'][1]>5 and o['name'].startswith(('Drawer_','Cabinet_','Workstation_','Workbench_','Oil_bottle_','Parts_case')):
            o['pos'][0]+=.53
        if o['name'] in ['JDM_fabric_banner','Japanese_flag']:
            o['pos'][2]=3.65;o['scale']=[.82,.82,.82]
        o['parent']='Reference_Workstations'
    kept.append(o)
B.objects[:]=kept

# Reuse the visible reference artwork through UV coordinates on the original bitmap.
# The source image is copied without edits; only the selected poster/banner regions are mapped.
reference=Path(__file__).parent.parent/'references'/'image-gen-1(20261001-232039).png'
if not reference.exists():reference=Path(__file__).parent/'assets/Reference_Detail_Atlas.png'
atlaspath=B.TEX/'Reference_Detail_Atlas.png'
if reference.exists():shutil.copy2(reference,atlaspath)
packaged_sky=Path(__file__).parent.parent/'skybox'
if packaged_sky.exists() and not (B.OUT/'skybox').exists():shutil.copytree(packaged_sky,B.OUT/'skybox')
atlas=B.mat('Reference_poster_and_banners',[1,1,1],base='Reference_Detail_Atlas.png',rough=.92) if atlaspath.exists() else B.poster
def artwork_mesh(name,w,h,rect):
    W,H=1672,941;x0,y0,x1,y1=rect
    v=[[-w/2,0,-h/2],[w/2,0,-h/2],[w/2,0,h/2],[-w/2,0,h/2]]
    uv=[[x0/W,1-y1/H],[x1/W,1-y1/H],[x1/W,1-y0/H],[x0/W,1-y0/H]]
    return B.mesh(name,v,[[0,1,2],[0,2,3]],uv,[[0,-1,0]]*4)
for o in B.objects:
    if o['name']=='JDM_fabric_banner':
        o.update(g=artwork_mesh('Reference_JDM_banner',.66,2.25,(572,27,638,322)),m=atlas,pos=[-5.98,6.24,3.55],scale=[1,1,1])
    if o['name']=='Japanese_flag':
        o.update(g=artwork_mesh('Reference_Japanese_flag',.55,1.66,(672,30,731,218)),m=atlas,pos=[-4.55,6.24,3.65],scale=[1,1,1])

# Materials retain authored PBR maps; color accents use additional paint finishes.
blue=B.mat('Workshop_blue_paint',[.009,.034,.075],metal=.42,rough=.57)
yellow=B.mat('Safety_yellow_paint',[.29,.17,.016],metal=.35,rough=.65)
green=B.mat('Coolant_bottle_green',[.017,.065,.025],rough=.57)
orange=B.mat('Hand_tool_orange',[.28,.057,.009],rough=.7)
paper=B.mat('Printed_labels',[.38,.38,.34],rough=.85)
brass=B.mat('Valve_brass',[.31,.22,.08],metal=.85,rough=.35)
oil=B.mat('Dark_oil_stain',[.012,.011,.009],rough=.38)
warning=B.label_texture('Lift_warning',[('CAUTION',20,89,(222,173,36)),('4.0 TON',140,78,None),('AUTHORIZED USE ONLY',310,32,None)],size=(768,400))
label=B.label_texture('Workshop_labels',[('MIDNIGHT WORKS',20,63,None),('PERFORMANCE PARTS',135,42,None),('JAPAN  /  SERVICE',235,36,None)],size=(768,320))
platelabel=B.label_texture('Turntable_nameplate',[('MIDNIGHT DRIFT  ///',20,67,None)],size=(1024,128))
layoutgroups={}
def euler(R):
    y=math.asin(float(np.clip(-R[2,0],-1,1)))
    if abs(math.cos(y))>1e-6:return [math.atan2(R[2,1],R[2,2]),y,math.atan2(R[1,0],R[0,0])]
    return [math.atan2(-R[1,2],R[1,1]),y,0]
serial={}
class Prop:
    def __init__(self,kind,pos=(0,0,0),rot=(0,0,0)):
        serial[kind]=serial.get(kind,0)+1;self.name=f'{kind}_{serial[kind]:03d}';self.pos=np.array(pos,float);self.R=B.rotation(rot)
    def __enter__(self):self.start=len(B.objects);return self
    def __exit__(self,*args):
        for j,o in enumerate(B.objects[self.start:]):
            o['pos']=(self.R@o['pos']+self.pos).tolist();o['rot']=euler(self.R@B.rotation(o['rot']))
            o['name']=f'{self.name}/{o["name"]}_{j:03d}';o['parent']=self.name;o['assembly']=self.name
        layoutgroups[self.name]={'origin_source_z_up':self.pos.tolist(),'components':len(B.objects)-self.start}

def tube(a,b,r,m,name='Tube',n=16):
    a,b=np.array(a,float),np.array(b,float);v=b-a;L=np.linalg.norm(v)
    if L<1e-7:return
    return B.cyl(name,(a+b)/2,r,L,m,n,rot=(0,math.atan2(np.linalg.norm(v[:2]),v[2]),math.atan2(v[1],v[0])))
def bolt(pos,r=.014,h=.014,m=None,rot=(0,0,0)):
    return B.cyl('Hex_fastener',pos,r,h,B.chrome if m is None else m,6,rot=rot)
def curve(points,r=.018,m=None,name='Flexible_hose'):
    for a,b in zip(points[:-1],points[1:]):tube(a,b,r,B.rubber if m is None else m,name,12)
def box(*args,**kwargs):return B.box(*args,**kwargs)
def cyl(*args,**kwargs):return B.cyl(*args,**kwargs)
def ring(*args,**kwargs):return B.ring(*args,**kwargs)
def beam(*args,**kwargs):return B.beam(*args,**kwargs)
def decal(name,pos,w,h,m):return B.panel_image(name,pos,w,h,m)

def ring_wrench(size=.24):
    s=size/.24
    box('Forged_shaft',(0,0,0),(.023*s,.018*s,size*.69),B.chrome,.006*s)
    for z,r in [(size*.4,.031*s),(-size*.4,.024*s)]:
        ring('Ring_spanner_head',(0,0,z),r,.009*s,B.chrome,24,6,rot=(math.pi/2,0,0))
        for i in range(12):
            a=i*math.tau/12;box('Ring_internal_tooth',((r-.008*s)*math.cos(a),0,z+(r-.008*s)*math.sin(a)),(.005*s,.018*s,.007*s),B.chrome,.001,rot=(0,a,0))
    box('Shaft_stamp',(0,-.01*s,0),(.012*s,.003,.06*s),B.steel,.001)
def open_wrench(size=.25):
    start=len(B.objects)
    s=size/.25
    box('Forged_shaft',(0,0,0),(.024,.018,.25*.65),B.chrome,.006)
    z=.25*.35
    box('Open_jaw_bridge',(0,0,z),(.062,.02,.029),B.chrome,.007)
    for s in [-1,1]:box('Open_jaw_finger',(s*.025,0,z+.019),(.015,.02,.04),B.chrome,.003,rot=(0,s*.17,0))
    ring('Box_end',(0,0,-.25*.35),.024,.009,B.chrome,24,6,rot=(math.pi/2,0,0))
    for o in B.objects[start:]:o['pos']=(np.array(o['pos'])*s).tolist();o['scale']=[s,s,s]
def screwdriver(length=.27,m=None):
    m=B.red if m is None else m
    r=.015+length*.037
    cyl('Screwdriver_grip',(0,0,0),r,length*.36,m,20)
    for i in range(6):
        a=i*math.tau/6;box('Grip_flute',((r-.002)*math.cos(a),(r-.002)*math.sin(a),0),(.006,.006,length*.28),B.rubber,.002,rot=(0,0,a))
    cyl('Screwdriver_shank',(0,0,length*.34),.0035+length*.008,length*.34,B.chrome,12)
    box('Driver_tip',(0,0,length*.52),(.006+length*.02,.004,.020),B.chrome,.001)
    ring('Grip_collar',(0,0,length*.19),r*.8,.003,B.chrome,16,6)
def pliers():
    for s in [-1,1]:
        beam('Plier_handle',(s*.012,0,0),(s*.034,0,-.12),.017,.018,B.red)
        beam('Steel_jaw',(s*.003,-.001,.017),(s*.018,-.001,.082),.012,.018,B.chrome)
        for z in np.linspace(.05,.075,5):box('Jaw_tooth',(s*.013,0,float(z)),(.009,.025,.003),B.steel,0)
    cyl('Pivot_rivet',(0,-.008,0),.017,.03,B.chrome,16,rot=(math.pi/2,0,0))
def ratchet(size=1):
    start=len(B.objects)
    cyl('Ratchet_handle',(0,0,-.075),.016,.18,B.chrome,16)
    cyl('Ratchet_head',(0,0,.035),.034,.026,B.chrome,24,rot=(math.pi/2,0,0))
    box('Square_drive',(0,-.025,.035),(.018,.024,.018),B.steel,.003)
    box('Selector_lever',(0,.018,.045),(.035,.006,.008),B.steel,.002)
    for o in B.objects[start:]:o['pos']=(np.array(o['pos'])*size).tolist();o['scale']=[size,size,size]
def socket(r=.017,h=.045):
    cyl('Socket_body',(0,0,h/2),r,h,B.chrome,16)
    ring('Socket_lip',(0,0,h+.002),r*.78,r*.20,B.chrome,16,6)
    cyl('Socket_opening',(0,0,h+.003),r*.55,.003,B.dark,6)
    ring('Socket_knurl',(0,0,h*.22),r+.001,.002,B.steel,16,4)
def peg_hook(pos):
    tube(pos,(pos[0],pos[1]-.052,pos[2]),.007,B.chrome,'Pegboard_hook')
    tube((pos[0],pos[1]-.052,pos[2]),(pos[0],pos[1]-.052,pos[2]+.018),.007,B.chrome,'Hook_tip')

# The reference has tool walls close to the benches. Individual perforations and hooks.
for x in [-4.72,5.25]:
    with Prop('Rear_tool_wall',(x,6.17,2.13)):
        box('Pegboard_frame',(0,0,0),(2.23,.06,1.0),B.steel,.01)
        box('Perforated_board',(0,-.04,0),(2.12,.025,.89),B.wood,.008)
        for u in np.arange(-.98,1,.085):
            for z in np.arange(-.36,.44,.085):cyl('Peg_hole',(u,-.055,z),.008,.004,B.dark,8,rot=(math.pi/2,0,0))
        for u in [-.83,-.67,-.51,-.35,-.19,-.03,.13,.29,.45]:peg_hook((u,-.08,.32))
    for i in range(9):
        with Prop('Hanging_spanner',(x-.83+i*.16,6.045,2.21+float(rng.uniform(-.055,.055))),rot=(0,float(rng.uniform(-.13,.13)),0)):
            (ring_wrench if i%2==0 else open_wrench)([.145,.19,.27,.17,.34,.23,.39,.295,.205][i])
    for i in range(4):
        with Prop('Hanging_screwdriver',(x+.52+i*.135,6.035,2.15+float(rng.uniform(-.05,.05))),rot=(math.pi,float(rng.uniform(-.2,.2)),0)):screwdriver([.13,.31,.21,.42][i],[B.red,blue,orange,B.rubber][i])
    with Prop('Hanging_pliers',(x+.8,6.03,1.88)):pliers()
    with Prop('Hanging_ratchet',(x+.34,6.02,1.85)):ratchet()

# Banners and the mountain pass poster sit in the same rear-wall zones as the screenshot.
with Prop('Mountain_poster',(5.4,6.24,3.62)):
    box('Poster_frame',(0,.035,0),(1.40,.055,1.84),B.steel,.018)
    B.obj('Reference_mountain_pass_poster',artwork_mesh('Reference_mountain_pass_poster',1.25,1.68,(1404,87,1590,327)),atlas)
    for x in [-.65,.65]:
        for z in [-.87,.87]:bolt((x,-.012,z),.013,.014,rot=(math.pi/2,0,0))

# The original turntable skirt uses segmented red strips rather than a broad glowing cylinder.
for i in range(24):
    a=i*math.tau/24
    ring('Segmented_platform_neon',(0,0,.28),3.69,.019,B.neon,n=12,k=6,parent='Platform_Static',start=a+.018,end=a+math.tau/24-.018)
ring('Platform_top_neon_accent',(0,0,.468),3.57,.008,B.neon,n=192,k=6,parent='Turntable_ROTATE')
nameplate=decal('Platform_Midnight_nameplate',(0,-3.651,.355),1.9,.19,platelabel);nameplate['parent']='Platform_Static'

# Conventional low-ceiling floorplate two-post lift, inside an actual service bay.
# Approximately 3.35 m wide / 3.13 m high; swing arm reach is 1.0 to 1.3 m.
with Prop('Floorplate_two_post_lift',(-4.8,3.0,.032)):
    box('Low_floor_cable_cover',(0,0,.023),(3.35,.216,.037),B.steel,.008)
    for y in [-.105,.105]:box('Floorplate_edge',(0,y,.04),(3.34,.025,.025),B.steel,.004)
    for side in [-1,1]:
        x=side*1.6
        box('Lift_base_plate',(x,0,.025),(.55,.60,.045),B.steel,.012)
        box('Lift_column_back',(x,.12,1.558),(.30,.11,3.02),B.red,.008)
        for dx in [-.135,.135]:box('Column_channel_web',(x+dx,0,1.558),(.055,.36,3.02),B.red,.008)
        box('Column_top_cap',(x,0,3.07),(.35,.38,.055),B.red,.009)
        for dx in [-.22,.22]:
            for dy in [-.24,.24]:bolt((x+dx,dy,.062),.025,.026)
        for z in [.48,1.0,1.55,2.1,2.7]:
            box('Column_cross_brace',(x,.075,z),(.22,.04,.06),B.steel,.004)
            for dx in [-.09,.09]:bolt((x+dx,-.193,z),.013,.018,rot=(math.pi/2,0,0))
        for dx in [-.105,.105]:box('Carriage_slide_rail',(x+dx,-.06,1.58),(.027,.035,2.85),B.chrome,.003)
        box('Moving_carriage',(x,-.22,.49),(.31,.16,.66),B.steel,.015)
        for dx in [-.12,.12]:
            for z in [.24,.72]:cyl('Carriage_guide_roller',(x+dx,-.14,z),.04,.025,B.chrome,20,rot=(0,math.pi/2,0))
        cyl('Hydraulic_ram_barrel',(x,.055,1.03),.051,1.75,B.steel,24)
        cyl('Chrome_piston',(x,.055,2.23),.030,.65,B.chrome,24)
        ring('Hydraulic_seal',(x,.055,1.925),.045,.006,B.rubber,24,6)
        cyl('Top_chain_pulley',(x,-.028,2.91),.064,.042,B.steel,24,rot=(math.pi/2,0,0))
        tube((x-.054,-.028,.46),(x-.054,-.028,2.89),.008,B.steel,'Lift_chain')
        tube((x+.054,-.028,.46),(x+.054,-.028,2.89),.008,B.steel,'Lift_chain')
        for z in np.arange(.9,2.7,.14):box('Lock_ladder_tooth',(x+.08,-.12,z),(.043,.025,.019),B.steel,.002)
        for d in [-1,1]:
            p=np.array([x,-.18+d*.095,.18]);r=np.array([side*.79,d*(1.02 if d<0 else .97),.18]);q=p+(r-p)*.62
            cyl('Swing_arm_pivot',p,.067,.105,B.chrome,24)
            ring('Arm_lock_sector',p,.089,.012,B.steel,24,6)
            beam('Outer_lifting_arm',p,q,.135,.088,B.red)
            beam('Telescopic_inner_arm',q,r,.090,.058,B.steel)
            for z in [.225,.245,.265]:ring('Pad_thread',(r[0],r[1],z),.021,.0025,B.steel,16,4)
            cyl('Threaded_pad_stem',(r[0],r[1],.24),.022,.12,B.chrome,16)
            cyl('Steel_pad_plate',(r[0],r[1],.306),.073,.018,B.steel,24)
            cyl('Rubber_support_pad',(r[0],r[1],.322),.069,.018,B.rubber,24)
        box('Carriage_lock_release',(x,-.315,.64),(.12,.025,.024),B.chrome,.003)
    box('Power_unit_tank',(1.88,.09,1.1),(.23,.26,.43),B.dark,.025)
    cyl('Hydraulic_motor',(1.88,.09,1.46),.096,.28,B.steel,24)
    cyl('Reservoir_cap',(1.88,-.06,1.34),.026,.04,B.red,16)
    box('Lift_control_box',(1.6,-.245,1.18),(.24,.13,.31),B.steel,.018)
    for z,m in [(1.27,green),(1.12,B.red)]:cyl('Lift_control_button',(1.6,-.321,z),.022,.022,m,16,rot=(math.pi/2,0,0))
    decal('Lift_load_warning',(1.6,-.195,2.11),.25,.16,warning)
    curve([(1.87,.10,1.2),(1.98,.18,1.1),(1.98,.18,.12),(1.6,.1,.06),(-1.6,.1,.06)],.011,B.rubber,'Hydraulic_feed_hose')

# Workbenches and side tool wall, facing inward from the right side of the room.
with Prop('Long_side_workbench',(6.05,1.15,0),rot=(0,0,-math.pi/2)):
    box('Bench_top',(0,0,1.14),(3.5,.8,.105),B.wood,.018)
    box('Steel_apron',(0,0,.99),(3.43,.72,.12),B.steel,.01)
    for x in [-1.55,0,1.55]:
        for y in [-.29,.29]:box('Square_tube_leg',(x,y,.58),(.065,.065,1.05),B.steel,.004)
    box('Under_bench_shelf',(0,0,.3),(3.38,.68,.06),B.steel,.006)
    for x in [-1.35,-.8,-.25,.3,.85,1.4]:
        box('Parts_drawer',(x,-.36,.87),(.46,.045,.19),B.red,.009)
        box('Drawer_pull',(x,-.4,.9),(.31,.033,.025),B.chrome,.006)
    box('Side_pegboard',(0,.35,2.05),(3.6,.07,1.30),B.steel,.012)
    for x in np.arange(-1.6,1.65,.14):
        for z in np.arange(1.55,2.61,.14):cyl('Side_board_hole',(x,.309,z),.009,.004,B.dark,8,rot=(math.pi/2,0,0))
    box('Shelf_over_bench',(0,.21,2.88),(3.7,.45,.08),B.steel,.008)
    box('Bench_strip_light',(0,.11,2.80),(3.45,.07,.025),B.warm,.004)
for i in range(14):
    with Prop('Side_wall_spanner',(5.64,2.65-i*.21+float(rng.uniform(-.035,.035)),2.15+float(rng.uniform(-.075,.075))),rot=(float(rng.uniform(-.2,.2)),0,-math.pi/2)):
        (open_wrench if i%3 else ring_wrench)([.12,.18,.30,.16,.38,.24,.21,.34,.145,.285,.41,.225,.17,.32][i])
for i in range(8):
    with Prop('Side_wall_driver',(5.63,2.4-i*.23,1.77+float(rng.uniform(-.055,.055))),rot=(math.pi,0,-math.pi/2)):screwdriver([.12,.29,.19,.39,.16,.34,.23,.43][i],orange if i%2 else B.red)

# Wheel display shelves are mounted above the side benches rather than hiding rear tools.
for side,y in [(-1,2.1),(1,1.25)]:
    with Prop('Wall_mounted_wheel_display',(side*6.54,y,3.55),rot=(0,0,-side*math.pi/2)):
        for x in [-1.12,1.12]:box('Wheel_display_upright',(x,.06,0),(.05,.05,1.17),B.steel,.004)
        box('Wheel_display_tray',(0,-.11,-.51),(2.3,.48,.06),B.steel,.008)
        box('Display_top_rail',(0,.06,.59),(2.3,.06,.06),B.steel,.005)
        for i,x in enumerate([-.56,.48]):
            with Prop('Stored_alloy_wheel',(x,-.12,-.17),rot=(math.pi/2,0,.06*side)):
                A.alloy_wheel(*[(205,55,16),(275,35,19)][i],style=i)
            for z in [-.49,.54]:bolt((x,.025,z),.015,.018,rot=(math.pi/2,0,0))

def vice():
    box('Vice_base',(0,0,.04),(.34,.25,.06),B.steel,.012)
    cyl('Swivel_base',(0,0,.095),.125,.07,B.steel,24)
    box('Vice_main_body',(0,.015,.19),(.23,.19,.13),blue,.02)
    box('Fixed_jaw',(0,.09,.27),(.24,.065,.14),blue,.008)
    box('Moving_jaw',(0,-.115,.265),(.24,.064,.12),blue,.008)
    for y in [-.151,.052]:box('Serrated_jaw_face',(0,y,.29),(.22,.014,.07),B.chrome,.002)
    for x in np.arange(-.1,.11,.014):
        for y in [-.158,.044]:box('Jaw_serration',(x,y,.29),(.005,.006,.068),B.steel,0)
    tube((0,-.24,.19),(0,.13,.19),.018,B.chrome,'Vice_lead_screw',16)
    cyl('Lead_screw_collar',(0,-.235,.19),.038,.038,B.chrome,16,rot=(math.pi/2,0,0))
    tube((-.13,-.25,.19),(.13,-.25,.19),.01,B.chrome,'Tommy_bar',12)
    for x in [-.13,.13]:cyl('Bar_end',(x,-.25,.19),.018,.03,B.chrome,12,rot=(0,math.pi/2,0))
with Prop('Bench_vice',(5.70,2.60,1.2),rot=(0,0,-math.pi/2)):vice()
def drill():
    box('Cordless_drill_body',(0,0,.13),(.10,.21,.115),B.red,.035)
    cyl('Drill_chuck',(0,-.15,.135),.04,.075,B.steel,20,rot=(math.pi/2,0,0))
    tube((0,-.19,.135),(0,-.265,.135),.005,B.chrome,'Drill_bit',10)
    beam('Pistol_handle',(0,.028,.12),(0,.04,.025),.062,.056,B.rubber)
    box('Battery_pack',(0,.055,.017),(.10,.10,.055),B.dark,.012)
    box('Trigger',(0,-.013,.075),(.027,.019,.025),B.rubber,.005)
    for x in [-.055,.055]:
        for z in [.11,.13,.15]:box('Motor_cooling_slot',(x,.055,z),(.003,.064,.006),B.dark,.001)
with Prop('Cordless_drill',(5.74,.88,1.2),rot=(0,0,.7)):drill()
for i in range(8):
    with Prop('Bench_socket',(5.72+float(rng.uniform(-.08,.08)),1.6-i*.09,1.2)):socket(.011+i*.002,.033+(i%3)*.021)
for pos,rot in [((5.75,.1,1.2),(math.pi/2,0,.2)),((5.81,-.4,1.2),(math.pi/2,0,-.5))]:
    with Prop('Loose_bench_tool',pos,rot):open_wrench(.28)

def bottle(m=B.red,height=.30):
    cyl('Bottle_body',(0,0,height*.4),.055,height*.75,m,20,r2=.043)
    cyl('Bottle_neck',(0,0,height*.83),.022,height*.15,m,16)
    cyl('Bottle_cap',(0,0,height*.94),.026,height*.09,B.rubber,16)
    box('Bottle_label',(0,-.05,height*.42),(.065,.006,height*.32),paper,.003)
    for x in [-.024,-.008,.008,.024]:box('Label_print_line',(x,-.054,height*.42),(.003,.002,height*.23),B.dark,0)
def aerosol(m=B.red):
    cyl('Aerosol_can',(0,0,.115),.036,.22,m,20)
    ring('Can_bottom_rim',(0,0,.015),.034,.003,B.chrome,20,6)
    cyl('Can_shoulder',(0,0,.23),.032,.02,B.chrome,20,r2=.016)
    cyl('Spray_cap',(0,0,.253),.018,.027,B.dark,16)
    box('Spray_nozzle',(0,-.018,.257),(.009,.009,.008),paper,.002)
    box('Can_label',(0,-.036,.115),(.033,.005,.083),paper,.002)
def carton(size=(.35,.27,.25)):
    w,d,h=size;box('Cardboard_box',(0,0,h/2),size,B.cardboard,.007)
    box('Packing_tape',(0,0,h+.002),(.06,d,.005),paper,.001)
    box('Shipping_label',(w*.15,-d/2-.003,h*.6),(w*.46,.004,h*.31),paper,.001)
    for x in np.arange(-w*.03,w*.34,w*.035):box('Label_barcode',(x,-d/2-.006,h*.6),(w*.014,.002,h*.18),B.dark,0)
    for x in [-w/2+.01,w/2-.01]:box('Cardboard_edge',(x,0,h-.014),(.008,d,.009),B.wood,.002)
def binbox():
    box('Bin_bottom',(0,0,.018),(.23,.32,.025),blue,.005)
    for x in [-.105,.105]:box('Bin_side',(x,0,.073),(.025,.32,.13),blue,.004)
    box('Bin_back',(0,.145,.073),(.21,.025,.13),blue,.004)
    box('Bin_front_lip',(0,-.145,.05),(.21,.025,.08),blue,.004)
    box('Bin_label',(0,-.16,.06),(.10,.005,.045),paper,.001)
    for i in range(7):bolt((rng.uniform(-.085,.085),rng.uniform(-.1,.1),.052),.009,.023)

# Densely filled storage shelving; uprights, shelves, braces, bolts and stock are individual.
for side in [-1,1]:
    cx=side*5.95;cy=-2.65 if side<0 else 4.58
    shelf_angle=-side*math.pi/2+(-.026 if side<0 else .014)
    with Prop('Storage_shelving',(cx,cy,0),rot=(0,0,shelf_angle)):
        for x in [-1.15,1.15]:
            for y in [-.30,.30]:
                box('Shelf_angle_upright',(x,y,2.04),(.05,.05,3.95),B.steel,.003)
                for z in np.arange(.20,3.96,.18):cyl('Upright_adjustment_hole',(x,y-.028,z),.007,.003,B.dark,8,rot=(math.pi/2,0,0))
                box('Shelf_foot',(x,y,.08),(.18,.15,.07),B.steel,.008)
                bolt((x,y,.13),.025,.035)
        for z in [.3,1.1,1.9,2.7,3.5]:
            box('Shelf_steel_tray',(0,0,z),(2.4,.7,.045),B.steel,.005)
            box('Shelf_front_lip',(0,-.34,z+.032),(2.4,.02,.065),B.steel,.003)
            for x in [-1.15,1.15]:bolt((x,-.363,z),.011,.018,rot=(math.pi/2,0,0))
        beam('Shelf_cross_brace',(-1.15,.32,.2),(1.15,.32,3.95),.025,.025,B.steel)
        beam('Shelf_cross_brace',(-1.15,.32,3.95),(1.15,.32,.2),.025,.025,B.steel)
    # Shelf coordinates are rotated into the aisle, leaving the rear doorway open.
    R=B.rotation((0,0,shelf_angle))
    for level,z in enumerate([.33,1.13,1.93,2.73,3.53]):
        for j in range(7):
            if (j+level*3+(side+1)*2)%7 in [0,4]:continue
            q=R@np.array([-.95+j*.30+rng.uniform(-.025,.025),rng.uniform(-.09,.10),z])+[cx,cy,0]
            with Prop('Shelf_stock',q,rot=(0,0,shelf_angle+float(rng.uniform(-.32,.32)))):
                if level==1:binbox()
                elif level in [2,3]:
                    for y in [-.10,.08]:
                        with Prop('Shelf_consumable',(rng.uniform(-.032,.032),y+rng.uniform(-.025,.025),0),rot=(0,0,float(rng.uniform(-.6,.6)))):
                            if j%2:aerosol([B.red,blue,B.chrome][j%3])
                            else:bottle([B.red,green,blue][j%3],.25+(j%3)*.04)
                else:carton((.22+float(rng.uniform(0,.055)),.31+float(rng.uniform(0,.045)),.19+float(rng.uniform(0,.17))))

# Smaller cartons and fluids across both rear worktops and their overhead shelves.
for x in [-4.69,5.22]:
    for j in range(9):
        if (j==2 and x<0) or (j in [1,6] and x>0):continue
        with Prop('Worktop_consumable',(x-.86+j*.21+float(rng.uniform(-.04,.04)),5.62+float(rng.uniform(-.15,.14)),1.575),rot=(0,0,float(rng.uniform(-.7,.7)))):
            if j%3:bottle([B.red,green,blue][j%3],.23+(j%3)*.04)
            else:aerosol(B.chrome)
    for j in range(6):
        with Prop('Overhead_parts_box',(x-.93+j*.36+float(rng.uniform(-.035,.035)),5.85+float(rng.uniform(-.06,.07)),2.83),rot=(0,0,float(rng.uniform(-.14,.14)))):carton((.25+float(rng.uniform(0,.06)),.27,.18+float(rng.uniform(0,.10))))

def trolley(pos,angle):
    with Prop('Rolling_tool_trolley',pos,rot=(0,0,angle)):
        for z in [.23,.65,1.02]:
            box('Trolley_tray',(0,0,z),(.89,.51,.045),B.red,.008)
            for x in [-.44,.44]:box('Tray_side_lip',(x,0,z+.048),(.024,.50,.11),B.red,.004)
            for y in [-.245,.245]:box('Tray_front_lip',(0,y,z+.048),(.88,.024,.11),B.red,.004)
        for x in [-.41,.41]:
            for y in [-.21,.21]:
                box('Trolley_upright',(x,y,.64),(.032,.032,.88),B.steel,.003)
                cyl('Swivel_castor',(x,y,.11),.075,.05,B.rubber,20,rot=(0,math.pi/2,0))
                box('Caster_fork',(x,y,.165),(.07,.07,.055),B.steel,.007)
                bolt((x+.04,y,.11),.014,.025,rot=(0,math.pi/2,0))
        tube((.46,-.19,1.08),(.46,.19,1.08),.017,B.chrome,'Push_handle')
        box('Drawer_under_tray',(0,-.19,.90),(.76,.4,.14),B.steel,.008)
        box('Trolley_drawer_pull',(0,-.41,.91),(.36,.035,.022),B.chrome,.005)
        for j in range(8):
            with Prop('Trolley_socket',(-.33+j*.09+float(rng.uniform(-.017,.017)),-.1+float(rng.uniform(-.11,.10)),1.055)):socket(.010+j*.0018,.034+(j%3)*.02)
        with Prop('Trolley_ratchet',(.12,.12,1.075),rot=(math.pi/2,0,.8)):ratchet()
        for x in [-.24,0,.24]:
            with Prop('Trolley_aerosol',(x+float(rng.uniform(-.035,.035)),float(rng.uniform(-.05,.08)),.68)):aerosol(B.red)
trolley((-5.14,-.72,0),-.31);trolley((4.68,-1.43,0),.26)

def floor_jack():
    for x in [-.19,.19]:box('Jack_side_frame',(x,0,.14),(.07,.83,.17),B.red,.012)
    for y in [-.27,.31]:
        cyl('Jack_axle',(0,y,.10),.022,.48,B.chrome,16,rot=(0,math.pi/2,0))
        for x in [-.24,.24]:cyl('Jack_wheel',(x,y,.105),.085,.05,B.rubber,20,rot=(0,math.pi/2,0))
    box('Jack_cross_plate',(0,.22,.10),(.35,.12,.06),B.steel,.008)
    for x in [-.10,.10]:
        beam('Jack_lifting_arm',(x,.30,.15),(x,-.19,.31),.057,.075,B.red)
        bolt((x,-.19,.31),.021,.028,rot=(0,math.pi/2,0))
    cyl('Jack_saddle',(0,-.22,.345),.095,.046,B.steel,24)
    cyl('Jack_rubber_pad',(0,-.22,.375),.088,.021,B.rubber,24)
    tube((0,.25,.15),(0,-.09,.29),.046,B.steel,'Jack_hydraulic_ram',20)
    tube((0,.38,.14),(0,.95,.77),.018,B.chrome,'Long_jack_handle',16)
    tube((0,.89,.70),(0,1.01,.84),.026,B.rubber,'Jack_handle_grip',16)
    cyl('Pump_pivot',(0,.31,.17),.034,.31,B.chrome,16,rot=(0,math.pi/2,0))
with Prop('Red_floor_jack',(4.7,-3.9,0),rot=(0,0,-.38)):floor_jack()

# Compressor, gas bottle and welding trolley add mechanically plausible workshop clutter.
with Prop('Air_compressor',(-5.55,-5.0,0),rot=(0,0,.22)):
    cyl('Compressor_tank',(0,0,.39),.24,.9,blue,32,rot=(0,math.pi/2,0))
    for x in [-.45,.45]:cyl('Tank_end_dome',(x,0,.39),.22,.06,blue,32,rot=(0,math.pi/2,0),r2=.15)
    for x in [-.29,.29]:
        cyl('Compressor_wheel',(x,.22,.13),.12,.055,B.rubber,24,rot=(0,math.pi/2,0))
        box('Tank_foot',(x,-.14,.12),(.11,.1,.15),B.steel,.008)
    box('Compressor_motor',(0,0,.74),(.27,.35,.23),B.steel,.025)
    for x in np.arange(-.12,.14,.03):box('Cooling_fin',(x,0,.78),(.012,.38,.24),B.chrome,.001)
    cyl('Air_filter',(.20,0,.83),.075,.085,B.dark,20,rot=(0,math.pi/2,0))
    tube((-.22,-.20,.54),(-.22,-.20,.73),.017,brass,'Air_manifold')
    cyl('Pressure_gauge',(-.22,-.235,.77),.062,.029,B.chrome,24,rot=(math.pi/2,0,0))
    cyl('Gauge_face',(-.22,-.254,.77),.054,.005,paper,24,rot=(math.pi/2,0,0))
    beam('Gauge_needle',(-.22,-.259,.77),(-.19,-.259,.80),.004,.004,B.red)
    for i in range(7):
        a=i*math.pi/6;box('Gauge_tick',(-.22+.044*math.cos(a),-.26,.77+.044*math.sin(a)),(.004,.002,.01),B.dark,0)
    curve([(-.22,-.20,.68),(-.4,-.45,.48),(-.55,-.6,.08),(-.65,-.3,.08)],.012,orange)
with Prop('Welder_with_gas_trolley',(5.0,-5.0,0),rot=(0,0,-.22)):
    box('Welding_cart_base',(0,0,.14),(.8,.58,.07),B.steel,.01)
    for x in [-.30,.30]:
        for y in [-.22,.22]:cyl('Welding_cart_wheel',(x,y,.12),.09,.05,B.rubber,20,rot=(0,math.pi/2,0))
    for x in [-.30,.30]:box('Cart_frame_leg',(x,.20,.57),(.04,.04,.78),B.steel,.003)
    box('Welder_case',(0,-.09,.55),(.50,.44,.40),B.red,.035)
    box('Welder_front_panel',(0,-.318,.55),(.45,.025,.32),B.dark,.008)
    for x in [-.12,.12]:cyl('Welder_control_knob',(x,-.343,.61),.039,.026,B.rubber,16,rot=(math.pi/2,0,0))
    for x in [-.14,.14]:cyl('Cable_connector',(x,-.347,.44),.024,.03,brass,16,rot=(math.pi/2,0,0))
    for x in [-.255,.255]:
        for z in [.42,.46,.50,.54,.58,.62,.66]:box('Welder_air_vent',(x,-.03,z),(.003,.24,.012),B.dark,0)
    cyl('Shielding_gas_bottle',(.16,.23,1.02),.105,1.02,green,24,r2=.095)
    cyl('Gas_bottle_shoulder',(.16,.23,1.58),.09,.10,green,24,r2=.033)
    cyl('Gas_valve',(.16,.23,1.69),.021,.12,brass,16)
    ring('Gas_valve_handwheel',(.16,.23,1.74),.052,.009,B.red,20,6)
    for z in [.73,1.34]:ring('Bottle_restraint',(.16,.23,z),.11,.012,B.steel,24,6)
    for k in range(6):ring('Welding_cable_coil',(-.22,-.03,.06+k*.023),.24,.012,B.rubber,32,6)
    curve([(-.14,-.35,.44),(-.40,-.5,.2),(-.65,-.45,.06)],.014,B.rubber)

# Engine on a stand: block, heads, pulleys, manifold runners and bolts remain editable.
with Prop('Spare_inline_engine_in_corner',(-6.09,5.14,.008),rot=(0,0,.08)):
    for y in [-.45,.45]:
        box('Engine_stand_foot',(0,y,.13),(.84,.06,.08),B.red,.009)
        for x in [-.37,.37]:cyl('Stand_caster',(x,y,.1),.075,.043,B.rubber,20,rot=(0,math.pi/2,0))
    box('Stand_spine',(0,0,.18),(.07,.94,.08),B.red,.008)
    box('Stand_vertical_post',(0,.26,.75),(.12,.12,1.18),B.red,.008)
    cyl('Rotating_mount_head',(0,.17,1.27),.105,.24,B.steel,24,rot=(math.pi/2,0,0))
    box('Engine_block',(0,-.15,1.29),(.59,.61,.40),B.steel,.035)
    box('Cylinder_head',(0,-.15,1.58),(.56,.67,.18),B.chrome,.018)
    box('Valve_cover',(0,-.15,1.71),(.42,.57,.14),B.red,.025)
    for y in np.linspace(-.39,.1,5):
        for x in [-.20,.20]:bolt((x,y,1.80),.018,.018)
    for y in np.linspace(-.38,.08,4):
        curve([(.26,y,1.5),(.41,y,1.54),(.43,y,1.36),(.34,y,1.27)],.027,B.chrome,'Manifold_runner')
        cyl('Spark_plug',(0,y,1.79),.016,.065,paper,12)
    for x,z,r in [(-.17,1.22,.075),(.13,1.28,.09),(0,1.48,.067)]:
        cyl('Front_pulley',(x,-.505,z),r,.045,B.steel,24,rot=(math.pi/2,0,0))
        ring('Pulley_belt_groove',(x,-.534,z),r-.006,.008,B.rubber,24,6,rot=(math.pi/2,0,0))
        bolt((x,-.538,z),.024,.018,rot=(math.pi/2,0,0))
    for x in [-.28,.28]:
        for y in [-.4,-.2,0,.1]:bolt((x,y,1.46),.015,.024,rot=(0,math.pi/2,0))
    box('Oil_sump',(0,-.15,.99),(.45,.47,.16),B.steel,.02)
    cyl('Oil_filter',(-.36,-.18,1.21),.054,.11,B.red,20,rot=(0,math.pi/2,0))
    for x in [-.295,.295]:
        for z in [1.15,1.23,1.31,1.39]:box('Block_casting_rib',(x,-.15,z),(.022,.57,.025),B.steel,.004)
    for y in [-.37,-.2,-.03,.10]:
        cyl('Exhaust_port',(-.30,y,1.52),.029,.035,B.dark,16,rot=(0,math.pi/2,0))
        curve([(-.31,y,1.52),(-.45,y,1.48),(-.48,y,1.31),(-.49,-.45,1.16)],.023,B.chrome,'Four_into_one_header')
    cyl('Crankshaft_front_hub',(0,-.52,1.18),.055,.07,B.chrome,24,rot=(math.pi/2,0,0))
    cyl('Alternator_housing',(.28,-.37,1.34),.079,.145,B.chrome,24,rot=(math.pi/2,0,0))
    for y in np.arange(-.43,-.30,.022):ring('Alternator_casting_fin',(.28,y,1.34),.075,.006,B.steel,20,6,rot=(math.pi/2,0,0))
    box('Intake_plenum',(.37,-.15,1.51),(.15,.56,.13),B.chrome,.045)
    cyl('Throttle_body',(.37,-.465,1.51),.058,.13,B.chrome,24,rot=(math.pi/2,0,0))
    cyl('Open_throttle_bore',(.37,-.535,1.51),.044,.005,B.dark,24,rot=(math.pi/2,0,0))
    cyl('Oil_filler_cap',(-.10,-.32,1.805),.033,.025,B.dark,16)
    tube((-.25,-.33,1.23),(-.26,-.32,1.73),.005,B.chrome,'Oil_dipstick')
    ring('Dipstick_pull_loop',(-.26,-.32,1.765),.02,.004,yellow,16,6,rot=(math.pi/2,0,0))
    curve([(.20,-.33,1.56),(.28,-.53,1.54),(.35,-.55,1.34)],.010,B.rubber,'Engine_coolant_hose')
    for y in [-.37,-.20,-.03,.10]:
        curve([(0,y,1.82),(-.08,y,1.83),(-.15,-.50,1.68)],.004,B.rubber,'Ignition_wire')

# Floor stacks, jack stands and spare wheels stay outside the turntable envelope.
for i,(x,y,spec,count) in enumerate([(4.88,3.95,(235,40,18),3),(5.70,-3.10,(275,35,19),2),(-4.35,-4.86,(205,55,16),3)]):
    z=.04
    with Prop('Radial_car_tyre_stack',(x,y,0),rot=(0,0,float(rng.uniform(-.5,.5)))):
        for j in range(count):
            w=A.tyre_dimensions(*spec)[0]
            with Prop('Stacked_car_tyre',(float(rng.uniform(-.036,.036)),float(rng.uniform(-.035,.035)),z+w*.5),rot=(0,0,float(rng.uniform(-math.pi,math.pi)))):A.tyre(*spec,pattern=i)
            z+=w
for pos,spec,rot in [((-5.66,.48,.350),(225,45,17),(math.pi/2,.05,-.22)),((4.58,-3.11,.381),(275,35,19),(math.pi/2,.10,.43))]:
    with Prop('Loose_car_alloy_wheel',pos,rot):A.alloy_wheel(*spec,style=1)
for x,y in [(4.15,2.8),(-5.62,.86),(4.65,-4.76),(-5.49,-4.36)]:
    with Prop('Axle_jack_stand',(x,y,0)):
        for k in range(3):
            a=k*math.tau/3;beam('Tripod_leg',(.22*math.cos(a),.22*math.sin(a),.06),(0,0,.32),.048,.04,B.red)
        cyl('Stand_ratcheting_post',(0,0,.40),.033,.31,B.chrome,16)
        for z in [.32,.36,.40,.44,.48]:box('Ratchet_tooth',(.033,0,z),(.018,.017,.015),B.steel,.002)
        box('Axle_saddle',(0,0,.565),(.13,.085,.035),B.steel,.004)
        for x in [-.058,.058]:box('Saddle_upright',(x,0,.595),(.018,.085,.048),B.steel,.003)
for x,y in [(-4.3,5.18),(4.25,5.43),(-5.45,-3.96),(5.50,-.41),(4.32,3.29)]:
    with Prop('Loose_carton',(x,y,.042),rot=(0,0,float(rng.uniform(-.3,.3)))):carton((.44,.35,.37))
for x,y in [(4.06,-4.52),(-5.05,4.87)]:
    with Prop('Loose_fluid_crate',(x,y,.042),rot=(0,0,float(rng.uniform(-.5,.5)))):
        box('Crate_floor',(0,0,.025),(.44,.34,.04),B.steel,.006)
        for a in [-1,1]:
            box('Crate_side',(a*.21,0,.13),(.03,.34,.24),B.steel,.004)
            box('Crate_end',(0,a*.16,.13),(.43,.03,.24),B.steel,.004)
        for x in [-.1,.1]:
            for y in [-.075,.075]:
                with Prop('Crated_fluid',(x,y,.047)):bottle(green,.25)

# Coils, buckets, shop stool and additional scattered service objects.
for x,y in [(-4.73,-3.71),(4.15,4.48)]:
    with Prop('Air_hose_on_floor',(x,y,.05)):
        for i in range(7):ring('Hose_loop',(0,0,.014+i*.025),.30-i*.014,.011,orange,32,6)
        tube((.30,0,.014),(.55,-.21,.02),.010,orange)
        cyl('Hose_quick_coupling',(.56,-.22,.022),.022,.045,brass,12,rot=(0,math.pi/2,-.7))
with Prop('Workshop_stool',(4.92,.15,.04),rot=(0,0,.34)):
    cyl('Stool_cushion',(0,0,.56),.22,.085,B.rubber,32)
    cyl('Seat_base',(0,0,.51),.19,.035,B.steel,32)
    cyl('Stool_post',(0,0,.32),.04,.37,B.chrome,20)
    for i in range(5):
        a=i*math.tau/5;beam('Stool_leg',(0,0,.16),(.27*math.cos(a),.27*math.sin(a),.09),.025,.03,B.steel)
        cyl('Stool_castor',(.27*math.cos(a),.27*math.sin(a),.085),.046,.03,B.rubber,16,rot=(0,math.pi/2,a))
for x,y in [(6.15,-5.1),(-6.15,.95)]:
    with Prop('Shop_bucket',(x,y,.04)):
        cyl('Bucket_body',(0,0,.17),.16,.33,B.steel,24,r2=.19)
        cyl('Bucket_dark_interior',(0,0,.337),.177,.007,B.dark,24)
        ring('Bucket_rim',(0,0,.34),.185,.008,B.chrome,32,6)
        ring('Bucket_handle',(0,0,.40),.16,.006,B.chrome,24,6,rot=(math.pi/2,0,0),start=0,end=math.pi)


import workshop_clutter as C
C.populate(Prop,rng,blue,green,orange,brass,oil,socket,ratchet,open_wrench,tube,bolt,curve)

# Every part receives a unique name, even when immutable vertex data is shared.
for i,o in enumerate(B.objects):
    if not o.get('assembly'):o['name']=f'{o["parent"]}/{o["name"]}_{i:05d}'

def finalize():
    B.assembly_origins={name:g['origin_source_z_up'] for name,g in layoutgroups.items()}
    # Change the inherited turntable pivot from y=1 to y=0 in exported GLB.
    g=B.export_glb(B.OUT/'Midnight_Drift_Garage.glb')
    patch_pivot(B.OUT/'Midnight_Drift_Garage.glb',False)
    B.export_glb(B.OUT/'Neon_Turntable.glb',True);patch_pivot(B.OUT/'Neon_Turntable.glb',True)
    B.export_obj()
    # OBJ source exporter adds y=1 to turntable nodes, so fix just moving-deck vertices.
    p=B.OUT/'Midnight_Drift_Garage.obj';lines=p.read_text().splitlines();moving=False
    for i,line in enumerate(lines):
        if line.startswith('o '):moving='Turntable_ROTATE/' in line
        if moving and line.startswith('v '):
            v=list(map(float,line.split()[1:]));v[1]-=1;lines[i]='v %.6f %.6f %.6f'%tuple(v)
    p.write_text('\n'.join(lines)+'\n')
    rows=[]
    for i,o in enumerate(B.objects):rows.append({'part':i,'name':o['name'],'assembly':o['parent'],'material':B.materials[o['m']]['name'],'triangles':len(B.geometry[o['g']]['f'])})
    with open(B.OUT/'Object_Inventory.csv','w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    report={'revision':'Dark asymmetric automotive workshop','mesh_objects':len(B.objects),'assemblies':len(set(o['parent'] for o in B.objects)),'triangles':sum(len(B.geometry[o['g']]['f']) for o in B.objects),'materials':len(set(o['m'] for o in B.objects)),'room_dimensions_m':[13.6,12.8,4.96],'cars':0,'tyres':['205/55 R16','225/45 R17','235/40 R18','275/35 R19'],'lift':'Conventional floorplate two-post lift, approximately 3.35 m wide / 3.13 m high','skybox':'Street level industrial city','layout_seed':81274,'notes':'Separate mesh nodes; shared immutable geometry for repeated parts. Reconstruction, not a measured replica.'}
    (B.OUT/'Scene_Manifest.json').write_text(json.dumps(report,indent=2))
    actual=set(o['parent'] for o in B.objects)
    (B.OUT/'Assembly_Inventory.json').write_text(json.dumps({name:g for name,g in layoutgroups.items() if name in actual},indent=2))
    print(json.dumps(report),flush=True)

def patch_pivot(path,standalone):
    import struct
    raw=path.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jl]);binary=raw[20+jl:]
    doc['nodes'][3]['translation']=[0,0,0]
    if standalone:doc['nodes'][0]['translation']=[0,0,0]
    for nd in doc['nodes']:
        if nd['name']=='Neon_light':nd['translation'][1]-=1
    if not standalone:
        camera=np.array([4.6,-5.9,2.75]);target=np.array([-.5,1.65,1.50]);f=target-camera;f/=np.linalg.norm(f)
        r=np.cross(f,[0,0,1]);r/=np.linalg.norm(r);u=np.cross(r,f);R=np.stack([r,u,-f],axis=1)
        vfov=2*math.atan(math.tan(math.radians(93)/2)/1.6)
        doc['cameras']=[{'name':'Garage_reference_camera','type':'perspective','perspective':{'aspectRatio':1.6,'yfov':vfov,'znear':.03,'zfar':300}}]
        doc['nodes'].append({'name':'Garage_reference_camera','camera':0,'translation':camera.tolist(),'rotation':B.quaternion(euler(R))})
        doc['nodes'][1]['children'].append(len(doc['nodes'])-1)
    jb=json.dumps(doc,separators=(',',':')).encode();jb+=b' '*((-len(jb))%4)
    out=struct.pack('<III',0x46546c67,2,20+len(jb)+len(binary))+struct.pack('<II',len(jb),0x4e4f534a)+jb+binary
    path.write_bytes(out)

if __name__=='__main__':finalize()
