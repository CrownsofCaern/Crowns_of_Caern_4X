"""Resource art contact sheet at native, adventure-map and HUD sizes."""
from pathlib import Path
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'docs/art/production/resource-pickups'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    definitions=json.loads((ROOT/'data/resources.json').read_text())
    records=[(rid,definitions['resources'][rid]['name']) for rid in definitions['order']]+[('chest','Treasure chest')]
    image=Image.new('RGB',(880,100+len(records)*124),'#202127')
    draw=ImageDraw.Draw(image)
    draw.text((12,12),'Crowns of Caern / resource pickups / rendered candidates',fill='#dfd0ac')
    for x,text in [(120,'Previous 32px'),(250,'New native 96px'),(410,'Map 48px'),(560,'Icon 48px'),(680,'HUD 32px'),(780,'Costs 24px')]:
        draw.text((x,52),text,fill='#dfd0ac')
    for index,(rid,name) in enumerate(records):
        y=90+index*124
        draw.text((12,y+50),name,fill='#dfd0ac')
        sid='resource_'+rid if rid!='chest' else 'object_chest'
        before=Image.open(ROOT/'assets/source/batches/resource-pickups-001/references'/f'{sid}.png').convert('RGBA')
        art=Image.open(ROOT/'assets/build/object'/f'{sid}.png').convert('RGBA')
        for x,size,source in [(140,32,before),(264,96,art),(430,48,art)]:
            view=source.resize((size,size),Image.Resampling.NEAREST)
            image.paste(view,(x,y+100-size),view)
        if rid!='chest':
            icon=Image.open(ROOT/'assets/build/icon'/f'ui_resource_{rid}.png').convert('RGBA')
            for x,size in [(570,48),(690,32),(790,24)]:
                view=icon.resize((size,size),Image.Resampling.LANCZOS)
                image.paste(view,(x,y+100-size),view)
        draw.line((0,y+116,880,y+116),fill='#34353c')
    image.save(OUT/'contact.png')


if __name__=='__main__':
    main()
