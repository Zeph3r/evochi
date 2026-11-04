# Cleans the combat button sprites from Evochi_Combat_Button_Assets_v1 (png/256/<ability>/<state>.png): the pack
# baked the tail of each button's label into its drop shadow. Each bottom sector outside the rim is refilled from the
# same radius 52 degrees round (the shadow and glow are nearly round), the Healing Mist crest kept; then webp q90.
#   python3 tools/art/combat_buttons_clean.py <pack dir> flutter/assets/art/combat [ability ...]
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as nd
ab=sys.argv[3:] or ['pounce','dodge','healing_mist','bolt','pulse','lumen_glow','root_snare','spark_burst','stone_guard','starlight_beam']; st=['normal','ready','pressed','disabled']
FRAMED={'healing_mist','lumen_glow','root_snare','spark_burst','stone_guard','starlight_beam'}  # (the Elders' crested frame)
CLEAN={'pounce','dodge'}|FRAMED  # (the others came clean: kept as painted)
R={'pounce':121.5,'dodge':120.5,'bolt':117.5,'pulse':117.5,**{k:122.5 for k in FRAMED}}
def bil(img,x,y):
  return np.stack([nd.map_coordinates(img[...,c],[y,x],order=1,mode='nearest') for c in range(4)],-1)
for a in ab:
  for s in st:
    im=np.array(Image.open(f'{sys.argv[1]}/png/256/{a}/{s}.png').convert('RGBA')).astype(float)
    rgb=im[...,:3]
    yy,xx=np.mgrid[0:256,0:256].astype(float); cx=cy=127.5
    d=np.hypot(xx-cx,yy-cy); phi=np.degrees(np.arctan2(xx-cx,yy-cy))  # 0 = straight down
    r=R[a]-(8 if s=='pressed' else 0)
    gold=(rgb[...,0]>140)&(rgb[...,0]-rgb[...,2]>60)&(rgb[...,1]>90)&(np.abs(phi)<14)&(d<r+14)&(s!='ready' or True)
    gold=nd.binary_dilation(gold,iterations=2) if a in FRAMED else np.zeros_like(gold)
    wa=np.clip((40-np.abs(phi))/8,0,1)            # angular ramp
    wr=np.clip((d-(r-1.5))/2.5,0,1)               # radial ramp
    w=(wa*wr)*(~gold)
    if a in FRAMED:
      lum=rgb.mean(-1); sat=rgb.max(-1)-rgb.min(-1)
      dots=(lum>105)&(sat<70)&(yy>236)&(np.abs(phi)<24)&(d>r-12)&~gold
      dots=nd.binary_dilation(dots,iterations=2)&~gold
      w=np.maximum(w,dots.astype(float))
    w=nd.gaussian_filter(w,0.7)*(~gold)
    if a not in CLEAN: w=w*0
    sh=np.where(phi>=0,1,-1)*52
    th=np.radians(phi+sh)
    sx=cx+d*np.sin(th); sy=cy+d*np.cos(th)
    src=bil(im,sx,sy)
    outp=im*(1-w[...,None])+src*w[...,None]
    Image.fromarray(outp.clip(0,255).astype(np.uint8)).save(os.path.join(sys.argv[2], f'{a}_{s}.webp'), 'WEBP', quality=90, method=6, alpha_quality=95)
