"""Current eight-building contact sheet from the registered prepared artwork."""
from pathlib import Path
import json

from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/art/production/ultimate-buildings'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    registry=json.loads((ROOT/'assets/specs/ultimate_buildings.json').read_text())
    page=Image.new('RGB',(1520,820),'#202127')
    draw=ImageDraw.Draw(page)
    lines=['# Ultimate-building review','',
           'Eight dedicated buildings, including the Eclipse Sanctum and Abyssal Throne. Rendered candidates pending artistic approval.','',
           '[Developer handoff](../../ULTIMATE_BUILDINGS_REPORT.md) · [Native 350px contact](contact.png) · [Creature effects](all-faction-ultimate-stills.png)','',
           '| Faction | Building | Before construction | Built in Godot |','|---|---|---|---|']
    for i,asset in enumerate(registry['assets']):
        image=Image.open(ROOT/asset['output']).convert('RGBA')
        x,y=i%4*380,i//4*410
        page.paste(image,(x+(380-image.width)//2,y+355-image.height),image)
        draw.text((x+8,y+365),asset['building_name'],fill='#dfcc9c')
        draw.text((x+8,y+386),asset['faction']+' / '+str(image.width)+' x '+str(image.height),fill='#b6ac99')
        fid=asset['faction']
        lines.append(f"| {fid} | {asset['building_name']} | [View]({fid}-before-construction.png) | [View]({fid}-built.png) |")
    page.save(OUT/'contact.png')
    page.save(ROOT/'docs/art/ultimate_buildings.png')
    lines+=['','[Movement effects](all-faction-ultimate-movement.png) · [Attack effects](all-faction-ultimate-attacks.png)','',
            'Godot captures construct each ultimate through GameSession, verify the exact gold payment and active faction bonus, and show before/after town layers. Creature comparisons use real BattleFigure still, move and attack rendering. Gameplay rules and balance come from current main.','']
    (OUT/'README.md').write_text('\n'.join(lines))


if __name__=='__main__':
    main()
