"""Asymmetric automotive jobs in progress, assembled from independent mesh parts."""
import math
import numpy as np
import base_geometry as B
import automotive_parts as A

def populate(Prop,rng,blue,green,orange,brass,oil,socket,ratchet,open_wrench,tube,bolt,curve):
    box,cyl,ring,beam=B.box,B.cyl,B.ring,B.beam
    with Prop('Manual_gearbox_on_floor',(5.82,-4.26,.267),rot=(math.pi/2,.015,.41)):
        casing=A.lathe('Cast_gearbox_and_bellhousing',[(.091,.48),(.122,.35),(.145,.09),(.155,-.07),(.237,-.21),(.237,-.30),(.210,-.30),(.210,-.23),(.130,-.08),(.119,.09),(.091,.35),(.072,.48)],64)
        B.obj('Cast_transmission_case',casing,B.chrome)
        for z in [-.055,.015,.085,.155,.225,.295,.365]:ring('Transmission_reinforcing_rib',(0,0,z),.151-max(z,0)*.095,.006,B.steel,48,6)
        for i in range(9):
            a=i*math.tau/9
            bolt((.228*math.cos(a),.228*math.sin(a),-.306),.012,.021)
            beam('Bellhousing_cast_rib',(.148*math.cos(a),.148*math.sin(a),-.06),(.235*math.cos(a),.235*math.sin(a),-.23),.009,.014,B.chrome)
        cyl('Bellhousing_shadow',(0,0,-.17),.12,.005,B.dark,32)
        cyl('Input_shaft',(0,0,-.30),.02,.18,B.chrome,20)
        for i in range(10):
            a=i*math.tau/10;box('Input_shaft_spline',(.020*math.cos(a),.020*math.sin(a),-.35),(.006,.006,.062),B.steel,.001,rot=(0,0,a))
        cyl('Output_shaft',(0,0,.515),.025,.11,B.chrome,20)
        box('Selector_housing',(.03,.14,.19),(.10,.082,.19),B.steel,.013)
        for z in [.12,.25]:bolt((.02,.189,z),.012,.018,rot=(math.pi/2,0,0))

    with Prop('Leaning_intercooler',(-5.29,-2.32,.268),rot=(.09,0,-.29)):
        box('Intercooler_core',(0,0,0),(.60,.12,.34),B.chrome,.003)
        for z in np.linspace(-.155,.155,23):box('Horizontal_cooling_fin',(0,-.066,z),(.59,.009,.005),B.steel,.001)
        for x in [-.34,.34]:
            box('Welded_end_tank',(x,0,0),(.09,.13,.34),B.steel,.018)
            cyl('Boost_pipe_stub',(x,-.135,.045),.039,.17,B.chrome,24,rot=(math.pi/2,0,0))
            ring('Hose_bead',(x,-.22,.045),.039,.003,B.chrome,24,6,rot=(math.pi/2,0,0))
        for x in [-.23,.23]:box('Intercooler_mount_tab',(x,0,-.20),(.049,.07,.076),B.steel,.003)

    def brake_caliper():
        box('Brake_caliper_cast_body',(0,0,.028),(.20,.09,.064),B.red,.025)
        for x in [-.058,.058]:
            cyl('Caliper_piston_boss',(x,0,.063),.028,.016,B.red,24)
            bolt((x,-.043,.03),.01,.018,rot=(math.pi/2,0,0))
        for y in [-.048,.048]:box('Brake_pad_backing_plate',(0,y,.027),(.13,.012,.046),B.steel,.005)
        cyl('Brake_bleed_nipple',(.083,.03,.079),.006,.031,B.chrome,10)
        curve([(-.084,.019,.053),(-.14,.065,.06),(-.24,.055,.021)],.004,B.rubber,'Braided_brake_hose')

    with Prop('Brake_service_mat',(-4.73,.92,.047),rot=(0,0,-.16)):
        box('Oil_resistant_floor_mat',(0,0,.003),(1.12,.78,.009),B.rubber,.006)
        with Prop('Used_brake_rotor',(-.28,-.15,.018)):A.brake_disc(.148)
        with Prop('New_brake_rotor',(.23,.13,.019),rot=(0,0,.17)):A.brake_disc(.169)
        with Prop('Removed_caliper',(.26,-.22,.015),rot=(0,0,-.33)):brake_caliper()
        with Prop('Brake_pad_pair',(-.14,.26,.013),rot=(0,0,.27)):
            for x in [-.07,.065]:
                box('Brake_pad_plate',(x,0,.009),(.105,.047,.008),B.steel,.008)
                box('Brake_friction_material',(x,0,.019),(.092,.041,.013),B.dark,.008)
        for i in range(9):bolt((rng.uniform(-.48,.5),rng.uniform(-.30,.33),.019),.008,.019)
    for pos,length,angle in [((-5.07,1.62,.089),.51,.24),((-4.64,1.43,.087),.42,-.32)]:
        with Prop('Loose_adjustable_coilover',pos,rot=(math.pi/2,0,angle)):A.coilover(length)
    with Prop('Bench_brake_caliper',(5.74,1.94,1.20),rot=(0,0,.46)):brake_caliper()

    with Prop('Spare_turbocharger',(5.87,-.16,1.28),rot=(math.pi/2,0,-.26)):
        ring('Compressor_scroll',(0,0,0),.065,.032,B.chrome,40,10,start=.15,end=math.tau-.25)
        cyl('Compressor_inlet',(0,0,.046),.042,.09,B.chrome,24)
        cyl('Open_compressor_inlet',(0,0,.093),.032,.005,B.dark,24)
        for i in range(10):
            a=i*math.tau/10;beam('Turbo_impeller_blade',(.008*math.cos(a),.008*math.sin(a),.09),(.028*math.cos(a+.35),.028*math.sin(a+.35),.09),.006,.004,B.chrome)
        cyl('Bearing_housing',(0,0,-.061),.026,.072,B.steel,24)
        ring('Turbine_scroll',(0,0,-.11),.058,.027,B.steel,40,10)
        tube((.075,-.015,0),(.112,-.075,0),.023,B.chrome,'Boost_outlet')
        box('Turbine_mount_flange',(0,.089,-.11),(.077,.025,.065),B.steel,.004)
        for x in [-.025,.025]:bolt((x,.105,-.10),.007,.017,rot=(math.pi/2,0,0))

    with Prop('Spare_exhaust_section',(-5.08,-4.39,.11),rot=(0,0,.51)):
        curve([(-.49,-.05,0),(-.25,-.05,0),(-.14,.04,0),(.20,.04,0),(.42,-.12,0)],.031,B.chrome,'Exhaust_pipe')
        cyl('Muffler_body',(.27,-.03,.02),.082,.33,B.steel,32,rot=(0,math.pi/2,-.40))
        for p in [(-.47,-.05,0),(.39,-.11,0)]:ring('Exhaust_weld_bead',p,.032,.003,B.chrome,24,6,rot=(0,math.pi/2,0))
        curve([(.12,.04,.02),(.12,.17,.09),(.23,.19,.09)],.008,B.chrome,'Rubber_mount_hanger')

    def impact_wrench():
        cyl('Impact_gun_body',(0,0,.067),.049,.13,blue,24,rot=(math.pi/2,0,0))
        cyl('Impact_anvil',(0,-.091,.067),.023,.053,B.chrome,16,rot=(math.pi/2,0,0))
        box('Impact_square_drive',(0,-.126,.067),(.018,.024,.018),B.steel,.002)
        beam('Impact_pistol_grip',(0,.03,.043),(0,.06,-.055),.037,.041,B.rubber)
        cyl('Air_quick_connect',(0,.060,-.061),.011,.037,brass,12)
        box('Impact_trigger',(0,-.014,-.012),(.018,.016,.026),B.steel,.003)
        for x in [-.051,.051]:
            for z in [.05,.068,.083]:box('Impact_air_vent',(x,.02,z),(.002,.044,.005),B.dark,.001)
    with Prop('Pneumatic_impact_wrench',(-4.18,1.28,.13),rot=(math.pi/2,0,.58)):impact_wrench()
    with Prop('Long_torque_wrench',(5.81,.47,1.226),rot=(math.pi/2,0,-.81)):
        ratchet(1.25)
        tube((0,0,-.12),(0,0,-.39),.012,B.chrome,'Torque_wrench_extension')
        cyl('Adjustable_torque_grip',(0,0,-.355),.019,.135,B.rubber,20)
        ring('Adjustment_lock_ring',(0,0,-.419),.019,.004,B.chrome,20,6)
    with Prop('Oil_drain_pan',(-5.82,4.25,.033),rot=(0,0,-.38)):
        cyl('Drain_pan_bowl',(0,0,.048),.19,.09,B.dark,32,r2=.23)
        cyl('Used_engine_oil',(0,0,.09),.207,.006,oil,32)
        ring('Pan_lip',(0,0,.095),.223,.010,B.rubber,40,6)
        box('Drain_pan_handle',(.23,0,.055),(.12,.045,.047),B.dark,.007)

    # Different size hand tools lie in arbitrary directions beside their current jobs.
    for i,(x,y,z) in enumerate([(5.81,2.33,1.23),(5.79,-.24,1.226),(-4.61,.52,.078),(-4.32,1.6,.078),(-4.65,5.76,1.608)]):
        with Prop('Scattered_service_spanner',(x,y,z),rot=(math.pi/2,0,float(rng.uniform(-2.7,2.7)))):open_wrench([.145,.34,.21,.39,.25][i])
    for i in range(14):
        with Prop('Loose_wheel_fastener',(-4.15+rng.uniform(-.22,.17),1.17+rng.uniform(-.12,.3),.067),rot=(float(rng.uniform(-.25,.25)),0,float(rng.uniform(0,math.tau)))):bolt((0,0,0),.009,.025)

    def rag(w=.30,d=.21):
        v=[];f=[];uv=[];nx=10;ny=8
        for iy in range(ny+1):
            for ix in range(nx+1):
                x=(ix/nx-.5)*w;y=(iy/ny-.5)*d
                z=.006+.012*math.sin(ix*1.2+iy*.6)**2+.025*math.exp(-((x/w-.1)*15)**2)
                v.append([x,y,z]);uv.append([ix/nx,iy/ny])
        for iy in range(ny):
            for ix in range(nx):
                a=iy*(nx+1)+ix;b=a+1;c=a+nx+1;f.extend([[a,b,c],[b,c+1,c]])
        B.obj('Crumpled_shop_cloth',B.mesh('Folded_rag',v,f,uv),green)
    for pos,angle in [((5.65,1.28,1.20),.42),((-4.57,.16,.052),-.71),((-4.51,5.36,1.575),.33)]:
        with Prop('Used_shop_rag',pos,rot=(0,0,angle)):rag()

    with Prop('Uncoiled_air_line',(-5.10,-.59,.066)):
        points=[(0,0,.34),(-.13,-.10,.04),(.08,-.25,0),(.30,-.02,0),(.44,.31,0),(.31,.58,0),(.37,.90,0),(.71,1.09,0),(.77,1.56,0)]
        curve(points,.010,orange,'Loose_air_hose')
        cyl('Pneumatic_coupler',(.77,1.56,.003),.014,.04,brass,12,rot=(math.pi/2,0,.10))

    # Open selected drawers as trays, moving the front and handle together.
    for center,z,extension in [(-4.696,.875,.19),(5.226,1.08,.29)]:
        for o in B.objects:
            dz=.03 if o['name']=='Drawer_handle' else -.10 if o['name']=='Drawer_seam' else 0
            if o['parent']=='Reference_Workstations' and o['name'] in ['Drawer_front','Drawer_handle','Drawer_seam'] and abs(o['pos'][0]-center)<.05 and abs(o['pos'][2]-(z+dz))<.005:
                o['pos'][1]-=extension
        with Prop('Partly_open_cabinet_drawer',(center,5.696-.39*.64-extension,z)):
            box('Extended_drawer_floor',(0,.17,-.063),(1.82,.39,.014),B.steel,.003)
            for x in [-.91,.91]:box('Drawer_side_wall',(x,.17,-.003),(.015,.39,.13),B.steel,.003)
            for j in range(5):
                with Prop('Drawer_socket',(-.62+j*.25+float(rng.uniform(-.07,.07)),.09+float(rng.uniform(-.05,.11)),-.05)):socket(.012+j*.002,.031+j*.006)

    offsets={}
    for o in B.objects:
        if o['parent']=='Reference_Workstations' and o['name'].startswith('Oil_bottle_'):
            key=round(o['pos'][0],4)
            if key not in offsets:offsets[key]=[float(rng.uniform(-.07,.07)),float(rng.uniform(-.08,.09)),0]
            o['pos']=(np.array(o['pos'])+offsets[key]).tolist()

    # Open shipping cartons occupy irregular clusters in the foreground and side aisle.
    def open_carton(w,d,h):
        box('Open_carton_base',(0,0,.013),(w,d,.025),B.cardboard,.003)
        for x in [-w/2,w/2]:box('Open_carton_side',(x,0,h/2),(.012,d,h),B.cardboard,.003)
        for y in [-d/2,d/2]:box('Open_carton_end',(0,y,h/2),(w,.012,h),B.cardboard,.003)
        for s in [-1,1]:
            a=s*(.55 if s<0 else 1.10)
            R=B.rotation((a,0,0));center=R@np.array([0,s*d*.17,0])+[0,s*d/2,h]
            box('Bent_top_flap',center,(w-.012,d*.34,.009),B.cardboard,.002,rot=(a,0,0))
        for s in [-1,1]:
            a=s*(-.92 if s<0 else -.46)
            R=B.rotation((0,a,0));center=R@np.array([s*w*.16,0,0])+[s*w/2,0,h]
            box('Bent_side_flap',center,(w*.32,d-.01,.009),B.cardboard,.002,rot=(0,a,0))
        box('Dark_cardboard_inside',(0,0,.030),(w-.02,d-.02,.006),B.wood,.001)
    for pos,size,angle in [((3.72,-4.93,.04),(.55,.43,.37),.47),((3.12,-4.77,.04),(.33,.31,.21),-.29),((-4.72,-2.15,.04),(.49,.57,.35),-.38)]:
        with Prop('Open_parts_shipping_box',pos,rot=(0,0,angle)):
            open_carton(*size)
            for j in range(3):
                with Prop('Packed_socket',(-.12+j*.105,float(rng.uniform(-.09,.1)),.036)):socket(.014+j*.006,.072+j*.022)
    with Prop('Uneven_carton_pile',(-4.97,-2.81,.04),rot=(0,0,.18)):
        box('Lower_used_box',(0,0,.16),(.49,.40,.32),B.cardboard,.006)
        box('Upper_box_shifted',(.10,-.06,.43),(.36,.30,.22),B.cardboard,.005,rot=(0,0,-.37))
        box('Old_packing_tape',(.11,-.08,.546),(.045,.30,.004),B.wood,.001,rot=(0,0,-.37))

    # Irregular oil stains ground the service projects in their floor space.
    for i,(x,y,r) in enumerate([(-5.86,4.43,.29),(5.81,-4.17,.30),(5.30,.23,.21)]):
        with Prop('Irregular_floor_oil_stain',(x,y,.033)):
            v=[[0,0,0]];f=[];n=36
            for j in range(n):
                a=j*math.tau/n;rr=r*float(rng.uniform(.64,1.0));v.append([rr*math.cos(a),rr*math.sin(a),0])
            for j in range(n):f.append([0,1+j,1+(j+1)%n])
            B.obj('Oil_stain_contour',B.mesh('Irregular_oil_patch',v,f,norm=[[0,0,1]]*len(v)),oil)
