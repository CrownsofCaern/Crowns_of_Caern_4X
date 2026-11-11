"""Export only the new DLC artwork through the existing illustration pipeline."""
import hashlib,json,sys
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[4];batch=Path(__file__).parent
sys.path.insert(0,str(root/'tools/assets'))
from crowns_of_cinder_assets import illustrations
jobs=json.loads((batch/'jobs.json').read_text())
for j in jobs:
 a=j['asset'];source=root/a['source'];prompt=root/j['prompt_file']
 if not source.is_file():raise FileNotFoundError(source)
 with Image.open(source) as im:size=list(im.size)
 source.with_suffix('.json').write_text(json.dumps(dict(schema_version=1,provider='ChatGPT image_gen',id=a['id'],campaign=a['campaign'],chapter=a['chapter'],usage=a['usage'],story_source=a['story_source'],story_snapshot=str((batch/'story-snapshot.json').relative_to(root)),prompt_file=j['prompt_file'],prompt_sha256=hashlib.sha256(prompt.read_bytes()).hexdigest(),conditioning=[j['reference']],source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),source_size=size,quality_status='pending_visual_review',processing='Full resolution; no palette quantization or atlas downsampling'),indent=2)+'\n')
illustrations.build(root)
errors=illustrations.validate(root)
if errors:raise SystemExit('\n'.join(errors))
for cid in ['six_eyes','drowned_oath']:
 selected=[j for j in jobs if j['asset']['campaign']==cid]
 sheet=Image.new('RGB',(1000,365*((len(selected)+1)//2)),'#252327');d=ImageDraw.Draw(sheet)
 for i,j in enumerate(selected):
  a=j['asset'];x,y=i%2*500,i//2*365
  with Image.open(root/a['output']) as im:
   im.thumbnail((484,325));sheet.paste(im,(x+8,y+8))
  d.text((x+8,y+340),a['chapter_name'].encode('ascii','replace').decode(),fill='#e6ded2')
 dest=root/'docs/art/production/dlc-campaign-art';dest.mkdir(parents=True,exist_ok=True);sheet.save(dest/(cid+'-contact.jpg'),quality=94)
print('Exported 2 new journey maps and 18 missing briefing illustrations; existing artwork preserved')
