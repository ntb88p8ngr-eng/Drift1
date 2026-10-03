"""Reproject the unchanged source panorama to six cube faces; no invented extra detail."""
from pathlib import Path
import numpy as np, json, shutil, io, argparse
from PIL import Image
from scipy.ndimage import map_coordinates
out=Path(__file__).parent.parent/'output/Midnight_Drift_Garage_Detailed/skybox';out.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,default=out/'Midnight_City_Panorama.png');args=parser.parse_args()
src=args.source
def save_png(im,path):
    b=io.BytesIO();im.save(b,format='PNG');p=Path(path);temp=p.with_suffix('.png.new');temp.write_bytes(b.getvalue());temp.replace(p)
if src.resolve()!=(out/'Midnight_City_Panorama.png').resolve():shutil.copy2(src,out/'Midnight_City_Panorama.png')
im=np.asarray(Image.open(src).convert('RGB'));H,W=im.shape[:2];assert W==2*H
N=1024
u,v=np.meshgrid((np.arange(N)+.5)/N*2-1,(np.arange(N)+.5)/N*2-1)
faces={'px_right':(np.ones_like(u),-v,-u),'nx_left':(-np.ones_like(u),-v,u),
       'py_up':(u,np.ones_like(u),v),'ny_down':(u,-np.ones_like(u),-v),
       'pz_front':(u,-v,np.ones_like(u)),'nz_back':(-u,-v,-np.ones_like(u))}
for name,(x,y,z) in faces.items():
    l=np.sqrt(x*x+y*y+z*z);sx=(.5+.37+np.arctan2(x,z)/(2*np.pi))*W-.5;sy=(.5-np.arcsin(y/l)/np.pi)*H-.5
    a=np.stack([map_coordinates(im[:,:,k].astype(float),[sy,sx],order=1,mode='grid-wrap') for k in range(3)],-1)
    save_png(Image.fromarray(np.uint8(np.clip(a,0,255))),out/(name+'.png'))
cross=Image.new('RGB',(4*N,3*N),(12,14,19))
for name,pos in {'px_right':(2,1),'nx_left':(0,1),'py_up':(1,0),'ny_down':(1,2),'pz_front':(1,1),'nz_back':(3,1)}.items():
    cross.paste(Image.open(out/(name+'.png')),(pos[0]*N,pos[1]*N))
save_png(cross,out/'Midnight_City_Cubemap_Cross.png')
(out/'skybox_metadata.json').write_text(json.dumps({'type':'LDR RGB skybox','viewpoint':'Street level, approximately 1.4 m eye height','panorama_size':[W,H],'face_size':[N,N],'projection':'equirectangular latitude/longitude; six perspective 90 degree faces','convention':'+Y up, +Z front, +X right','panorama_sampling_u_offset_for_cube_front':.37,'note':'Source panorama is unchanged. Cube faces are rotated toward the street. Cube-face resolution is a technical reprojection, not additional native detail.'},indent=2))
(out/'Midnight_City.gdshader').write_text('shader_type sky;\nuniform sampler2D panorama : source_color, filter_linear, repeat_enable;\nuniform float exposure : hint_range(0.0, 4.0) = 1.0;\nuniform float horizontal_offset : hint_range(0.0, 1.0) = 0.37;\nvoid sky() { COLOR = texture(panorama, vec2(fract(SKY_COORDS.x + horizontal_offset), SKY_COORDS.y)).rgb * exposure; }\n')
(out/'README.md').write_text(f'''# Midnight City — Street Level\n\nNight industrial street viewed from approximately 1.4 metres above the pavement. Nearby warehouse fronts, street curbs and asphalt replace the previous elevated city view. No cars or people.\n\nUse Midnight_City_Panorama.png as an equirectangular environment background. Native resolution: {W} × {H}, LDR RGB. In Godot, assign it to a PanoramaSkyMaterial under a WorldEnvironment Sky. The included shader exposes environment exposure and horizontal offset controls. It defaults to an offset of 0.37 turns (133.2 degrees) to face the street. Apply the same panorama rotation in other engines if desired.\n\nSix 1024 × 1024 cube faces and a cross-layout preview are included. Coordinate convention: +Y up, +Z front, +X right. Face dimensions do not add native detail. The panorama is separate from the GLB; assign it in your target engine. The cube faces already apply the 0.37-turn street-facing rotation. The original panorama remains unchanged.\n\nThe authored scene's exterior apron is at floor level. Keep the panorama camera stationary or use it as a distant background; nearby road geometry in a skybox does not provide positional parallax.\n''')
print(f'Exported street-level {W}x{H} panorama and six {N}px cube faces',flush=True)
