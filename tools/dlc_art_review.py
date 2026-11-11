"""Native-scale contact sheets and animation loops for optional faction art."""
from pathlib import Path
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'docs/art/production/dlc-factions'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    pack = json.loads((ROOT/'assets/specs/dlc_factions.json').read_text())
    manifest = json.loads((ROOT/'assets/manifest.json').read_text())
    animation = json.loads((ROOT/'assets/animations.json').read_text())
    sheets = {}

    def sprite(sid):
        record = manifest['sprites'][sid]
        name = record['atlas']
        if name not in sheets:
            sheets[name] = Image.open(ROOT/manifest['atlases'][name]['path'].removeprefix('res://')).convert('RGBA')
        x,y,w,h = record['rect']
        return sheets[name].crop((x,y,x+w,y+h))

    for fid, faction in pack['factions'].items():
        groups = [
            ('creatures', [('creature_'+cid,pack['creatures'][cid]['name']) for cid in faction['creature_ids']],4,160,160),
            ('buildings', [('building_'+bid,pack['buildings'][bid]['name']) for bid in faction['building_ids']],5,260,282),
            ('heroes-towns', [(a['id'],a['id']) for a in pack['assets'] if a['faction']==fid and a['category']!='creature' and not a['id'].startswith('building_')],4,200,224)]
        for category, records, columns, width, height in groups:
            image = Image.new('RGB',(columns*width,((len(records)+columns-1)//columns)*height+30),'#202127')
            draw = ImageDraw.Draw(image)
            draw.text((8,8),faction['name']+' / '+category+' / native-scale candidates',fill='#dfd0ac')
            for i,(sid,label) in enumerate(records):
                art = sprite(sid)
                x,y=i%columns*width,i//columns*height+30
                image.paste(art,(x+(width-art.width)//2,y+height-24-art.height),art)
                draw.text((x+4,y+height-18),label,fill='#dfd0ac')
            image.save(OUT/f'{fid}-{category}.png')
        for category, ids, actions in [
            ('creatures',['creature_'+cid for cid in faction['creature_ids']],['move','attack']),
            ('heroes',['hero_'+hid for hid in faction['hero_ids']],['move'])]:
            for action in actions:
                frames=[]
                for phase in range(4):
                    columns=4 if category=='creatures' else 3
                    frame=Image.new('RGB',(columns*320,((len(ids)+columns-1)//columns)*278+30),'#202127')
                    draw=ImageDraw.Draw(frame)
                    draw.text((8,8),faction['name']+' / '+category+' '+action+' / candidate',fill='#dfd0ac')
                    for i,sid in enumerate(ids):
                        unit=animation['units'][sid]
                        if unit['atlas'] not in sheets:
                            sheets[unit['atlas']]=Image.open(ROOT/animation['atlases'][unit['atlas']]['path'].removeprefix('res://')).convert('RGBA')
                        x,y,w,h=unit['actions'][action]['frames'][phase]
                        art=sheets[unit['atlas']].crop((x,y,x+w,y+h))
                        dx,dy=i%columns*320,i//columns*278+30
                        frame.paste(art,(dx,dy),art)
                        draw.text((dx+6,dy+258),sid,fill='#dfd0ac')
                    frames.append(frame)
                durations=[150]*4 if action=='move' else [180,120,180,120]
                frames[0].save(OUT/f'{fid}-{category}-{action}.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=False)
                frames[1].save(OUT/f'{fid}-{category}-{action}-contact.png')
    # Compact overview of original unmodified sheets, for human visual auditing.
    records=pack['batches']
    page=Image.new('RGB',(1024,((len(records)+2)//3)*300),'#202127')
    draw=ImageDraw.Draw(page)
    for i,job in enumerate(records):
        image=Image.open(ROOT/job['source']).convert('RGBA')
        image.thumbnail((330,268),Image.Resampling.LANCZOS)
        x,y=i%3*341,i//3*300
        page.paste(image,(x,y),image)
        draw.text((x+4,y+276),job['id'],fill='#dfd0ac')
    page.save(OUT/'source-contact.jpg',quality=95)
    lines = ['# Standalone DLC faction art review', '',
             'The Umbral Court (dark elves) and Abyssal Shoal (fish men). Native-scale candidates; gameplay activation is separate and the main campaigns are untouched.', '',
             '[Developer handoff](../../DLC_FACTIONS_REPORT.md) · [Original source overview](source-contact.jpg)', '']
    for fid, faction in pack['factions'].items():
        lines += ['## '+faction['name'], '',
                  f"[Creature contact sheet]({fid}-creatures.png) · [All 30 buildings]({fid}-buildings.png) · [Heroes, towns and icons]({fid}-heroes-towns.png)", '',
                  f"[Creature movement loop]({fid}-creatures-move.gif) · [Creature attacks]({fid}-creatures-attack.gif) · [Hero movement]({fid}-heroes-move.gif)", '',
                  '| Tier | Base | Upgrade |', '|---|---|---|']
        for i in range(0,16,2):
            base, up = [pack['creatures'][cid] for cid in faction['creature_ids'][i:i+2]]
            lines.append(f"| {base['tier']} | {base['name']} (`{base['id']}`) | {up['name']} (`{up['id']}`) |")
        lines += ['', 'Hero classes: '+', '.join(pack['hero_classes'][hid]['name']+' (`'+hid+'`)' for hid in faction['hero_ids'])+'.', '',
                  f"Godot: [idle]({fid}-creatures-idle-godot.png), [walking]({fid}-creatures-move-godot.png), [attacking]({fid}-creatures-attack-godot.png).", '',
                  'Town construction: '+', '.join(f'[stage {n}]({fid}-town-stage-{n}-godot.png)' for n in range(1,5))+'.', '']
    lines += ['## Review limits', '',
              '32 creatures, 64 creature clips, six hero sprites/gaits, 60 building layers, eight map-town stages, two foundations, eight icons/cursor designs and six map props. The 120 static atlas sprites and 248 new action poses preserve high-resolution sources and conditioning references.', '',
              'Four-frame movement and three-pose attacks plus rest are first-pass animations. More in-between poses, dedicated idle/hit/death clips and projectiles remain separate work. The cursor is artwork without automatic context/hotspot activation. These packs contain no gameplay stats, balance or campaign links.', '']
    (OUT/'README.md').write_text('\n'.join(lines))


if __name__=='__main__':
    main()
