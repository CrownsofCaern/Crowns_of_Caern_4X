from pathlib import Path
from PIL import Image,ImageDraw
import json
root=Path('.'); out=root/'docs/art/production/living-world'; spec=json.load(open('assets/specs/town_scenes.json'))['factions']['concord']
buildings=json.load(open('data/buildings.json'))['towns']['concord']['buildings']
ids=list(spec['assets']); sheet=Image.new('RGB',(1000,((len(ids)+4)//5)*190),(26,27,31));draw=ImageDraw.Draw(sheet)
for i,bid in enumerate(ids):
 im=Image.open(spec['assets'][bid]['source']).convert('RGBA');im.thumbnail((184,155),Image.Resampling.LANCZOS);x=i%5*200;y=i//5*190
 sheet.paste(im,(x+(200-im.width)//2,y+155-im.height),im);draw.text((x+4,y+159),bid,fill='#e6d7b6');draw.text((x+4,y+173),buildings[bid]['name'],fill='#a89e87')
sheet.save(out/'concord-buildings-contact.jpg',quality=95)
frames=[]
for p in sorted(out.glob('motion-*.png')):
 im=Image.open(p).convert('RGB').crop((75,75,560,335));d=ImageDraw.Draw(im);d.text((8,245),'Mounted hero: riding             Creature: breathing',fill='#d6c99f');frames.append(im)
if frames: frames[0].save(out/'subtle-motion.gif',save_all=True,append_images=frames[1:],duration=80,loop=0,optimize=False)
for p in out.glob('motion-*.png'):p.unlink()
# Native comparison reconstructed from precisely the atlas cells used in game.
m=json.load(open('assets/manifest.json'))['terrain'];atlas=Image.open('assets/atlases/terrain.png').convert('RGBA');t=m['tile_size'];contact=Image.new('RGB',(800,390),'#191b1e');d=ImageDraw.Draw(contact)
for n,tid in enumerate(['grass','rough']):
 info=m['terrains'][tid];field=info['field'];d.text((n*400+12,10),tid+' / continuous 8x8 cells / native scale',fill='#e6d7b6')
 for y in range(8):
  for x in range(8):
   col=field['column']+y*8+x;im=atlas.crop((col*t,info['row']*t,(col+1)*t,(info['row']+1)*t));contact.paste(im,(n*400+12+x*t,36+y*t))
contact.save(out/'connected-terrain-native.png')
