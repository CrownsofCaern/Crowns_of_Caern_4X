#!/usr/bin/env python3
"""Author cobolt static pixel grids; animation artwork is a later production pass.
These are project-native palette-key sources, consumed by pipeline.py.
"""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
PALETTE = '.K123456789qQuUxXbBcCgGhHrReEoOyYsStTwWlLiIjJmMnNzZaAdDf'

def canvas(w=64,h=64):
    im=Image.new('L',(w,h)); d=ImageDraw.Draw(im)
    def poly(points,fill,outline='K'):
        d.polygon(points, fill=PALETTE.index(fill))
        if outline: d.line(points+[points[0]],fill=PALETTE.index(outline),width=1)
    def rect(box,fill,outline='K'): d.rectangle(box,fill=PALETTE.index(fill),outline=PALETTE.index(outline) if outline else None)
    def line(points,fill,width=1):d.line(points,fill=PALETTE.index(fill),width=width)
    return im,poly,rect,line

def save(im,name):
    p=ROOT/'assets/specs/pixel/cobolts'/f'{name}.txt';p.parent.mkdir(parents=True,exist_ok=True)
    rows = []
    for y in range(im.height):
        row = ''.join(PALETTE[im.getpixel((x,y))] * 2 for x in range(im.width)).rstrip('.') or '.'
        rows.extend([row, row])
    p.write_text('\n'.join(rows)+'\n')

def creature(name,tier):
    im,p,r,l=canvas(); metal='u' if tier==5 else 'S'
    # Low tail, boots and bent digitigrade legs.
    p([(28,43),(20,50),(8,51),(13,54),(26,53),(34,46)],'S');l([(12,52),(24,51),(31,45)],'t')
    p([(28,42),(35,43),(32,52),(28,56),(20,57),(22,54),(27,51)],'3')
    p([(37,41),(42,43),(44,51),(49,56),(39,57),(38,53),(35,49)],'4')
    l([(22,56),(27,56)],'i');l([(41,56),(46,56)],'i')
    if tier==1:
        p([(18,26),(29,24),(31,43),(18,43),(15,34)],'L');r((18,27,26,39),'l');l([(17,29),(29,29)],'G',2);l([(22,25),(22,43)],'w')
        r((17,22,27,26),'a');l([(18,23),(26,23)],'I')
    # Ragged teal-brown coat, leather straps and belt.
    p([(29,23),(41,22),(46,30),(41,41),(44,47),(36,45),(31,48),(24,44),(26,34)],'Q' if tier==5 else '3')
    p([(29,26),(33,28),(30,43),(27,44)],'5');p([(35,27),(40,25),(41,39),(35,43)],metal)
    l([(29,26),(39,39)],'l',2);l([(26,39),(41,39)],'w',3);r((32,38,35,40),'G');l([(33,38),(34,38)],'h')
    for y in [30,34]:l([(36,y),(39,y)],'G')
    # Neck and narrow reptilian snout, swept-back horns.
    p([(32,25),(33,18),(40,17),(40,25),(36,28)],'S')
    p([(32,19),(29,12),(34,8),(41,10),(44,15),(51,17),(50,20),(42,22),(36,21)],'S')
    p([(31,13),(25,5),(34,9),(37,12)],'i');p([(37,10),(34,3),(41,8),(43,13)],'i')
    l([(33,10),(39,11),(42,15),(49,17)],'t');l([(41,20),(49,19)],'w')
    l([(39,15),(42,15)],'K');l([(40,15),(41,15)],'h');l([(48,17),(48,17)],'K')
    # Forward arm and tier equipment.
    p([(40,26),(44,28),(44,34),(48,36),(47,39),(40,36),(37,30)],metal);l([(43,29),(42,33),(46,36)],'t')
    if tier==1:
        l([(44,37),(49,42)],'l',2);p([(49,40),(53,39),(52,45),(48,47),(50,43)],'U')
    if tier==2:
        l([(49,14),(49,55)],'l',2);p([(49,5),(46,15),(52,15)],'U');l([(49,7),(49,14)],'x')
        p([(21,28),(30,26),(32,38),(28,46),(21,42)],'l');l([(23,29),(29,28),(30,38),(27,43)],'G')
    if tier==3:
        l([(33,33),(56,30)],'l',3);l([(45,25),(48,35)],'U',2);l([(41,24),(52,35)],'G');l([(41,24),(56,30),(52,35)],'i');l([(45,30),(58,28)],'U')
        l([(24,24),(21,14)],'l',3);l([(20,13),(26,12)],'U')
    if tier==4:
        p([(45,24),(48,22),(52,25),(53,32),(50,36),(45,33)],'L');l([(45,25),(51,32)],'G');l([(51,25),(45,32)],'G');r((47,20,50,23),'w');l([(48,20),(50,19)],'O')
        p([(27,31),(36,32),(39,47),(26,47)],'l');l([(29,34),(28,44)],'L');r((22,40,27,47),'a');l([(23,41),(26,43)],'G')
    if tier==5:
        p([(27,23),(35,24),(33,30),(23,30)],'u');l([(25,25),(32,26)],'U')
        p([(42,26),(54,29),(54,48),(48,54),(40,48)],'Q');l([(43,28),(52,30),(52,47),(48,51),(42,47),(43,28)],'G')
        l([(48,31),(48,45)],'G');l([(44,36),(52,36)],'h');l([(44,36),(43,40),(46,40),(44,36)],'G');l([(51,36),(49,40),(53,40),(51,36)],'G')
        l([(22,33),(18,47)],'l',2);p([(19,35),(14,35),(17,31),(24,32),(26,36)],'U')
    save(im,'creature_cobolt_'+name)


def post(name,level):
    im,p,r,l=canvas(80,72)
    p([(5,61),(38,68),(76,57),(47,46)],'3');l([(10,61),(39,65),(69,57)],'5')
    # Shuttered stone counting house for the wealthy post.
    if level==3:
        p([(15,26),(39,19),(57,27),(57,54),(34,63),(15,54)],'4');p([(15,26),(34,32),(57,27),(39,19)],'6')
        for y in range(33,56,6): l([(17,y),(33,y+5),(55,y-1)],'2')
        r((20,36,30,54),'w');l([(23,37),(23,52)],'l');l([(27,39),(27,53)],'l');r((39,34,48,45),'w');l([(40,35),(47,43)],'G')
        p([(12,25),(36,16),(60,25),(35,34)],'3');l([(14,24),(36,18),(58,25)],'7')
        r((23,10,29,21),'4');l([(24,12),(28,12)],'6')
    # Covered canvas market with closed back, rope seams and dark interior.
    x=5 if level<3 else 38; y=32 if level<3 else 37
    p([(x,y),(x+23,y-8),(x+37,y),(x+15,y+9)],'a');p([(x,y),(x+15,y+9),(x+15,y+17),(x+3,y+12)],'L')
    p([(x+15,y+9),(x+37,y),(x+34,y+13),(x+15,y+20)],'d')
    l([(x+5,y),(x+23,y-6),(x+34,y)],'f');l([(x+15,y+9),(x+24,y-7)],'l')
    for i in [3,15,34]:l([(x+i,y+8),(x+i,y+27)],'w',2)
    r((x+6,y+17,x+21,y+26),'l');l([(x+7,y+20),(x+20,y+20)],'G');r((x+12,y+21,x+15,y+23),'h')
    if level<3:
        # Wagon with covered stock, never a visible garrison.
        p([(41,32),(49,27),(65,31),(67,48),(43,51)],'L');p([(41,32),(43,24),(49,21),(63,24),(65,31)],'a')
        l([(44,30),(47,24),(50,23),(62,25)],'d');l([(49,23),(50,30)],'l');l([(58,24),(59,31)],'l')
        for xw,yw in [(46,50),(62,46)]:
            p([(xw-4,yw-4),(xw+3,yw-4),(xw+5,yw),(xw+2,yw+5),(xw-3,yw+4),(xw-5,yw)],'w');l([(xw-3,yw),(xw+3,yw)],'G');l([(xw,yw-3),(xw,yw+3)],'L')
    if level>=2:
        for x in range(4,73,6): l([(x,52),(x,62 if x<38 else 58)],'l',2)
        l([(5,56),(35,63),(73,53)],'L',2)
    # Brass balance sign and amber lantern.
    l([(8,51),(8,20),(22,20)],'w',2);l([(9,21),(22,21)],'G');l([(18,22),(18,28)],'G');l([(12,26),(24,26)],'G')
    l([(12,26),(10,31),(15,31),(12,26)],'h');l([(24,26),(21,31),(26,31),(24,26)],'h')
    r((5,33,10,40),'G');r((6,34,9,38),'O');l([(7,35),(8,35)],'y')
    save(im,'site_cobolt_'+name)

if __name__=='__main__':
    for tier,name in enumerate(['pack_runner','caravan_spear','bolt_broker','cinder_alchemist','vault_warden'],1):creature(name,tier)
    for level,name in enumerate(['stall','yard','exchange'],1):post(name,level)
