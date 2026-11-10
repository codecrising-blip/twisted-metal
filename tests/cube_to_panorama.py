"""Turns the six cube faces from tests/bake_backdrop.gd into one equirectangular panorama in the
layout Godot's PanoramaSkyMaterial reads: u = 0 looks north (-Z), u grows toward east (+X),
v = 0 is straight up.
    python3 tests/cube_to_panorama.py <faces_dir> <out.jpg> [width]
"""
import json
import sys

import numpy as np
from PIL import Image


def main() -> None:
    faces_dir, out = sys.argv[1], sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 6144
    height = width // 2
    info = json.load(open(f"{faces_dir}/faces.json"))
    faces = {}
    for name, axes in info.items():
        img = np.asarray(Image.open(f"{faces_dir}/{name}.png").convert("RGB"), dtype=np.float32)
        faces[name] = (img, np.array(axes["right"]), np.array(axes["up"]), np.array(axes["forward"]))
    u = (np.arange(width) + 0.5) / width
    v = (np.arange(height) + 0.5) / height
    uu, vv = np.meshgrid(u, v)
    lon = uu * 2.0 * np.pi - np.pi  # 0 at u = 0.5
    theta = vv * np.pi  # 0 = up
    # Godot: u = (atan2(x, -z) wrapped to 0..2pi) / 2pi, v = acos(y) / pi.
    phi = uu * 2.0 * np.pi
    x = np.sin(theta) * np.sin(phi)
    z = -np.sin(theta) * np.cos(phi)
    y = np.cos(theta)
    dirs = np.stack([x, y, z], axis=-1)
    out_img = np.zeros((height, width, 3), dtype=np.float32)
    best = np.full((height, width), -np.inf)
    for name, (img, right, up, fwd) in faces.items():
        d = dirs @ fwd
        mask = (d > best) & (d > 0)
        best = np.where(mask, d, best)
        px = (dirs @ right) / np.maximum(d, 1e-6)
        py = (dirs @ up) / np.maximum(d, 1e-6)
        h, w = img.shape[:2]
        col = np.clip(((px + 1.0) * 0.5 * w).astype(np.int32), 0, w - 1)
        row = np.clip(((1.0 - py) * 0.5 * h).astype(np.int32), 0, h - 1)
        sample = img[row, col]
        out_img = np.where(mask[..., None], sample, out_img)
    del lon
    Image.fromarray(np.clip(out_img, 0, 255).astype(np.uint8)).save(out, quality=88, optimize=True)
    print("panorama", out, width, "x", height)


if __name__ == "__main__":
    main()
