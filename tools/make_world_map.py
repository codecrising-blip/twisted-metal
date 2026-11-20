"""The world map for the stage select (round 24, owner: "a world map locating Los Angeles and the other stages").
A war-room map: dark steel oceans with a faint grid, burnt land masses with an ember rim, drawn from Natural Earth's
public-domain 1:50m land polygons (naturalearthdata.com; fetch ne_50m_land.geojson from the natural-earth-vector repo
and pass its path). Equirectangular, 2048 x 1024: x = (lon + 180) / 360, y = (90 - lat) / 180 (FrontEnd uses the
same projection to place the stage pins).
    python3 tools/make_world_map.py /path/to/ne_50m_land.geojson
Writes assets/ui/world_map.webp."""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 2048, 1024
SS = 2  # supersampling


def project(lon, lat):
    return ((lon + 180.0) / 360.0 * W * SS, (90.0 - lat) / 180.0 * H * SS)


def main(path):
    data = json.load(open(path))
    mask = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(mask)
    for f in data["features"]:
        g = f["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            for k, ring in enumerate(poly):
                pts = [project(lon, lat) for lon, lat in ring]
                if len(pts) > 2:
                    d.polygon(pts, fill=0 if k > 0 else 255)
    mask = mask.resize((W, H), Image.LANCZOS)
    m = np.asarray(mask, dtype=np.float32) / 255.0
    # ocean: dark blue-steel with a soft gradient and a lat/long grid
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ocean = np.zeros((H, W, 3), np.float32)
    ocean[...] = np.array([0.035, 0.05, 0.065])
    ocean += (1.0 - np.abs(yy / H - 0.5) * 2.0)[..., None] * np.array([0.02, 0.03, 0.04])
    grid = ((np.abs(((xx / W) * 36.0) % 1.0 - 0.5) > 0.494) | (np.abs(((yy / H) * 18.0) % 1.0 - 0.5) > 0.49)).astype(np.float32)
    ocean += grid[..., None] * np.array([0.03, 0.05, 0.06])
    # land: burnt umber, darker inland, rough noise
    rng = np.random.default_rng(3)
    noise = np.asarray(Image.fromarray((rng.random((H // 8, W // 8)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255.0
    noise2 = np.asarray(Image.fromarray((rng.random((H // 2, W // 2)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255.0
    land = np.array([0.2, 0.13, 0.08])[None, None, :] * (0.7 + 0.5 * noise[..., None]) * (0.85 + 0.3 * noise2[..., None])
    # the coast: a thin ember rim (edge of the mask), with a faint glow out into the sea
    edge = np.asarray(mask.filter(ImageFilter.FIND_EDGES), np.float32) / 255.0
    edge = np.clip(edge * 3.0, 0, 1)
    glow = np.asarray(Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
    img = ocean * (1.0 - m[..., None]) + land * m[..., None]
    img += glow[..., None] * np.array([0.5, 0.18, 0.04]) * 0.9
    img += edge[..., None] * np.array([1.0, 0.55, 0.2]) * 0.55
    # vignette
    d2 = np.sqrt(((xx / W) - 0.5) ** 2 + ((yy / H) - 0.5) ** 2 * 0.6)
    img *= (1.0 - np.clip((d2 - 0.35) * 1.2, 0, 0.5))[..., None]
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    os.makedirs(os.path.join(ROOT, "assets", "ui"), exist_ok=True)
    p = os.path.join(ROOT, "assets", "ui", "world_map.webp")
    out.save(p, quality=88)
    print("wrote", p)


if __name__ == "__main__":
    main(sys.argv[1])
