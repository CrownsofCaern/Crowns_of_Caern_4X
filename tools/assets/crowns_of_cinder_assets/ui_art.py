"""Small functional UI drawings with fixed, reproducible cursor hotspots."""
from PIL import Image, ImageDraw
from pathlib import Path

from . import postprocess


def cursor(pal, rng, size, action="default", generated_source=None):
    if generated_source:
        # Keep generated subjects separate from the precise, shared click tip.
        root = Path(__file__).resolve().parents[3]
        raw = Image.open(root / generated_source)
        directional = action in ("default", "attack", "capture", "select")
        native_size = (36, 36) if directional else (29, 29)
        subject = postprocess.process_generated(raw, {
            "size": native_size, "anchor": "center", "outline": True,
            "outline_weight": 1, "export_scale": 1,
        }, pal)
        image = Image.new("RGBA", size)
        image.alpha_composite(subject, (2, 2) if directional else (10, 10))
        draw = ImageDraw.Draw(image)
        # Exact opaque 2,2 hotspot on every cursor, regardless of source margins.
        if directional:
            draw.polygon([(2, 2), (2, 6), (6, 6)], fill=pal.c("X"), outline=pal.outline)
            return image
        draw.polygon([(2, 2), (2, 17), (6, 13), (9, 19), (12, 17), (8, 11), (15, 11)],
                     fill=pal.c("X"), outline=pal.outline, width=1)
        draw.line([(4, 6), (4, 12), (6, 10), (10, 10)], fill=pal.c("h"), width=1)
        return image
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    ink, steel, gold = pal.outline, pal.c("X"), pal.c("h")
    draw.polygon([(2, 2), (2, 29), (9, 22), (15, 36), (21, 33), (14, 20), (27, 21)], fill=steel, outline=ink, width=2)
    draw.line([(4, 6), (4, 24), (10, 18), (22, 19)], fill=gold, width=1)
    if action == "default":
        return image
    draw.rounded_rectangle((20, 20, 39, 39), radius=3, fill=pal.c("q"), outline=gold, width=1)
    if action == "move":
        draw.polygon([(25, 24), (30, 24), (30, 30), (35, 32), (35, 35), (24, 35), (24, 31), (26, 30)], fill=pal.c("f"), outline=ink)
    elif action == "town":
        draw.polygon([(24, 26), (24, 23), (27, 23), (27, 26), (32, 26), (32, 23), (35, 23), (35, 35), (24, 35)], fill=steel)
        draw.rectangle((28, 30, 31, 36), fill=ink)
    elif action == "attack":
        draw.line((24, 24, 35, 35), fill=steel, width=3)
        draw.line((35, 24, 24, 35), fill=pal.c("O"), width=3)
        draw.line((23, 30, 29, 36), fill=gold, width=2)
        draw.line((30, 36, 36, 30), fill=gold, width=2)
    elif action == "pickup":
        draw.polygon([(24, 31), (26, 27), (28, 29), (28, 23), (31, 23), (31, 29), (35, 27), (35, 33), (31, 36), (27, 36)], fill=pal.c("J"), outline=ink)
    elif action == "encounter":
        draw.rectangle((24, 23, 35, 35), fill=pal.c("J"), outline=gold)
        draw.line((27, 26, 32, 26, 32, 29, 29, 31), fill=ink, width=2)
        draw.point((29, 33), fill=ink)
    elif action == "select":
        draw.polygon([(25, 35), (25, 26), (28, 23), (33, 23), (35, 26), (35, 35)], fill=steel, outline=ink)
        draw.line((27, 28, 33, 28), fill=ink, width=2)
        draw.line((30, 30, 30, 34), fill=gold, width=1)
    elif action == "blocked":
        draw.ellipse((23, 23, 36, 36), outline=pal.c("E"), width=3)
        draw.line((25, 34, 34, 25), fill=pal.c("E"), width=3)
    elif action == "wait":
        draw.polygon([(25, 24), (35, 24), (31, 30), (35, 35), (25, 35), (29, 30)], fill=gold, outline=ink)
        draw.line((24, 23, 36, 23), fill=steel, width=2)
        draw.line((24, 36, 36, 36), fill=steel, width=2)
    return image
