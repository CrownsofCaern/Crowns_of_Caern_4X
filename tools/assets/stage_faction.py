"""Stage a 4x4 generated faction sheet into the existing pipeline, pending QC.
Usage: python tools/assets/stage_faction.py FACTION SOURCE BATCH
"""
import sys,json,shutil
from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image
from crowns_of_cinder_assets import production
root=Path(__file__).resolve().parents[2]
faction,source,batch_name=sys.argv[1:]
batch=root/'assets/source/batches'/batch_name
batch.mkdir(parents=True,exist_ok=True)
if (batch/'source.png').exists():
 if (batch/'source.png').read_bytes()!=Path(source).read_bytes():raise SystemExit('Refuse overwrite of archived sheet')
else:shutil.copyfile(source,batch/'source.png')
a=np.array(Image.open(source).convert('RGBA'))[:,:,3]>=128
h,w=a.shape;components=[]
for y,x in zip(*np.nonzero(a)):
 if not a[y,x]:continue
 q=deque([(y,x)]);a[y,x]=False;count=0;left=right=x;top=bottom=y
 while q:
  cy,cx=q.popleft();count+=1;left=min(left,cx);right=max(right,cx);top=min(top,cy);bottom=max(bottom,cy)
  for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
   ny,nx=cy+dy,cx+dx
   if 0<=ny<h and 0<=nx<w and a[ny,nx]:a[ny,nx]=False;q.append((ny,nx))
 if count>800:components.append((count,[left,top,right+1,bottom+1]))
components=sorted(components,reverse=True)[:16]
if len(components)!=16:raise SystemExit(f'Expected 16 isolated sprites, found {len(components)}; archive kept, manual bounds needed')
rows={i:[] for i in range(4)}
for count,rect in components:rows[min(3,int(((rect[1]+rect[3])/2)*4/h))].append(rect)
if any(len(row)!=4 for row in rows.values()):raise SystemExit('Irregular grid; archive kept, manual bounds needed')
rects=[[int(v) for v in rect] for row in rows.values() for rect in sorted(row)]
data=json.loads((root/'data/creatures'/f'{faction}.json').read_text())['creatures']
order=[]
for cid,c in sorted(data.items(),key=lambda item:(item[1]['tier'],item[0])):
 if not c.get('upgrade_of'):order.extend([cid,c['upgrade']])
p=root/'assets/specs/creatures.json';doc=json.loads(p.read_text());by_id={s['id']:s for s in doc['assets']}
assets=[]
for cid,rect in zip(order,rects):
 sid='creature_'+cid
 if sid not in by_id:raise SystemExit('Missing explicit structured spec: '+sid)
 by_id[sid].update(size=[128,128],generated_palette='preserve',map_scale=0.5,faction=faction)
 assets.append({'id':sid,'crop_xyxy':[max(0,rect[0]-1),max(0,rect[1]-1),min(w,rect[2]+1),min(h,rect[3]+1)]})
(batch/'layout.json').write_text(json.dumps({'schema_version':1,'grid':[4,4],'source_dimensions':[w,h],'assets':assets,'review':'Automatically staged isolated silhouettes; visual review pending'},indent=2)+'\n')
production.import_sheet(root,batch)
for asset in assets:
 mp=root/'assets/source/generated'/f"{asset['id']}.json"
 meta=json.loads(mp.read_text());meta.update(provider='ChatGPT image_gen',quality_status='pending_visual_review',native_size=[128,128],conditioning='Approved Concord rendering; faction-specific repository definitions')
 mp.write_text(json.dumps(meta,indent=2)+'\n')
p.write_text(json.dumps(doc,indent=2)+'\n')
print(f'Staged {len(assets)} {faction} assets; not visually approved')
