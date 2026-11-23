"""Brimstone idle portrait: the owner's PREACHER panel with a bible standing in his chest pocket (owner, round 29)."""
import sys
from PIL import Image, ImageDraw, ImageFilter
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
K = 4                                  # draw at 4x, then shrink: clean ink lines
x0, y0, w, h = 446, 474, 96, 100       # the patch on his left chest (image right), panel pixels
lay = Image.new("RGBA", (w * K, h * K), (0, 0, 0, 0))
d = ImageDraw.Draw(lay)
def P(x, y):
    return (x * K, y * K)
ink = (8, 6, 6, 255)
# the book, leaning a little toward his shoulder: cover, page block on top, spine shading
book = [P(14, 18), P(72, 9), P(78, 82), P(19, 88)]
d.polygon(book, fill=(30, 22, 20, 255), outline=ink)
d.line(book + [book[0]], fill=ink, width=3 * K)
d.polygon([P(18, 18), P(70, 10), P(71, 17), P(19, 25)], fill=(214, 200, 168, 255))   # page edges
for k in range(4):
    d.line([P(20, 20 + k * 1.4), P(69, 12 + k * 1.4)], fill=(160, 140, 112, 255), width=K)
d.line([P(14, 18), P(72, 9)], fill=ink, width=3 * K)
d.polygon([P(16, 26), P(22, 25), P(25, 86), P(20, 87)], fill=(18, 13, 12, 255))       # spine side, in shadow
d.line([P(67, 13), P(73, 80)], fill=(92, 70, 60, 255), width=2 * K)                   # worn leather catching the light
# the cross on the cover, tarnished gold with ink outline
cx, cy = 46, 44
for (a, b, c, e) in ((cx - 4, cy - 16, cx + 4, cy + 22), (cx - 14, cy - 6, cx + 14, cy + 1)):
    d.rectangle([P(a, b), P(c, e)], fill=(186, 140, 62, 255), outline=ink, width=2 * K)
d.line([P(cx - 3, cy - 14), P(cx - 3, cy + 20)], fill=(232, 196, 110, 255), width=K)
# a red ribbon marker hanging over the pages
d.line([P(55, 13), P(58, 27), P(54, 35)], fill=(150, 18, 16, 255), width=3 * K)
# the pocket's lip across the lower part of the book (coat cloth, stitched edge)
pocket = [P(2, 70), P(90, 62), P(91, 79), P(3, 87)]
d.polygon(pocket, fill=(56, 40, 38, 255))
d.line([P(2, 70), P(90, 62)], fill=ink, width=3 * K)
d.line([P(3, 86), P(91, 78)], fill=(20, 14, 13, 255), width=2 * K)
for k in range(10):
    x = 6 + k * 8.6
    d.line([P(x, 74 - k * 0.8), P(x + 4, 73.6 - k * 0.8)], fill=(96, 72, 66, 255), width=K)
lay = lay.resize((w, h), Image.LANCZOS)
im.paste(lay, (x0, y0), lay)
im.save(out)
