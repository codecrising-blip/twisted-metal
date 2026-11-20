"""Driver portraits for the select screen (round 24, owner: "enhanced versions of the drivers' profile pictures:
Outlaw from TM2, Sweet Tooth from TMB, Axel from TM2, Roadkill and Grimm from Head-On; one pose before you select,
a more exciting one after").

Made from the owner's own reference pictures (docs/reference/, and the Head-On select screen in
docs/reference/videos/mr grimm video.mp4): each is cropped to a 3:4 portrait, cleaned (the JPEG noise smoothed out),
upscaled in steps with sharpening in between (a single big resize goes soft), then graded to one look: deeper
contrast, a little more colour, warm shadows, a dark vignette and a fine grain, so the five read as one set.
    python3 tools/make_portraits.py [--sr EDSR_x4.pb] [car ...]
--sr: upscale with OpenCV's EDSR x4 super-resolution network instead of plain Lanczos steps (needs
opencv-contrib-python-headless; the weights EDSR_x4.pb are in github.com/Saafke/EDSR_Tensorflow, models/).
It keeps line art far crisper than resizing. The JPEG noise is taken out first (non-local means), so the
network doesn't sharpen the blocks.
Writes assets/portraits/<car>_idle.webp and <car>_select.webp (600 x 800)."""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "reference")
OUT = os.path.join(ROOT, "assets", "portraits")
W, H = 600, 800


def video_frame(path, t):
    """One frame of a reference video as an image."""
    tmp = os.path.join(tempfile.gettempdir(), "portrait_frame.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", path, "-frames:v", "1", tmp], check=True)
    return Image.open(tmp).convert("RGB")


# car -> pose -> (source, crop box in source pixels). Sources are file names in docs/reference or
# ("video", file in docs/reference/videos, time in s). Crops stay below the videos' watermark (top-left).
SOURCES = {
    "outlaw": {  # TM2's Capt. Jamie Roberts: the bio card's pistol at her side, then the TM2 cover pointing it at you
        "idle": ("Jamie_Roberts_TM2_Bio.webp", (178, 0, 320, 190)),
        "select": ("TM2JamieRobertsPSX.webp", (10, 18, 358, 482)),
    },
    "axel": {  # TM2's Axel between his wheels, then the same art closer, teeth bared
        "idle": ("TM2AxelInfobox.webp", (37, 0, 259, 296)),
        "select": ("TM2AxelInfobox.webp", (64, 0, 232, 224)),
    },
    "roadkill": {  # Head-On's Marcus Kane, then close on his glare
        "idle": ("InfoboxHeadOnMarcus.webp", (250, 0, 750, 667)),
        "select": ("InfoboxHeadOnMarcus.webp", (360, 30, 660, 430)),
    },
    "sweet_tooth": {  # TMB (owner): the grinning mask in the asylum's dark, then the same face in a wall of fire
        "idle": (("video", "story_tmb_sweet_tooth.mp4", 64.0), (150, 20, 420, 360)),
        "select": (("video", "story_tmb_sweet_tooth.mp4", 61.7), (185, 20, 455, 360)),
    },
    "mr_grimm": {  # Head-On's reaper with his scythe (the select screen), then his skull with burning red eyes
        "idle": (("video", "mr grimm video.mp4", 1.0), (390, 545, 536, 740)),
        "select": (("video", "story_headon_mr_grimm.mp4", 66.0), (70, 20, 325, 360)),
    },
}


def load(src):
    if isinstance(src, tuple) and src[0] == "video":
        return video_frame(os.path.join(REF, "videos", src[1]), src[2])
    return Image.open(os.path.join(REF, src)).convert("RGB")


_SR = None


def sr_model(path):
    global _SR
    if _SR is None:
        import cv2
        _SR = cv2.dnn_superres.DnnSuperResImpl_create()
        _SR.readModel(path)
        _SR.setModel("edsr", 4)
    return _SR


def upscale_sr(im, w, h, model):
    """EDSR x4 (repeated while still short of the size), then a clean resize to the frame."""
    import cv2
    a = cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2BGR)
    a = cv2.fastNlMeansDenoisingColored(a, None, 4, 4, 7, 21)  # JPEG / video noise
    if a.shape[1] * 2 < w or a.shape[0] * 2 < h:  # big sources only need a resize (EDSR on CPU is slow)
        a = sr_model(model).upsample(a)  # one x4 pass; the last bit of size is a plain resize
    out = Image.fromarray(cv2.cvtColor(a, cv2.COLOR_BGR2RGB)).resize((w, h), Image.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))


def upscale(im, w, h):
    """Up in steps of at most 2x, sharpening a little after each: crisper lines than one big resize."""
    im = im.filter(ImageFilter.MedianFilter(3)) if min(im.size) < 400 else im  # JPEG / video noise
    while im.width * 2 < w or im.height * 2 < h:
        im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
        im = im.filter(ImageFilter.UnsharpMask(radius=1.6, percent=90, threshold=2))
    im = im.resize((w, h), Image.LANCZOS)
    return im.filter(ImageFilter.UnsharpMask(radius=2.2, percent=110, threshold=3))


def grade(im):
    im = ImageEnhance.Contrast(im).enhance(1.14)
    im = ImageEnhance.Color(im).enhance(1.12)
    a = np.asarray(im, dtype=np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    warm = np.array([1.0, 0.55, 0.3], dtype=np.float32)
    a = a + (1.0 - lum) ** 3 * warm * 0.06  # warm shadows (the series' fire light)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    d = np.sqrt(((xx / a.shape[1]) - 0.5) ** 2 * 1.6 + ((yy / a.shape[0]) - 0.45) ** 2)
    a = a * (1.0 - np.clip((d - 0.32) * 1.5, 0.0, 0.55))[..., None]  # vignette
    rng = np.random.default_rng(7)
    a = a + rng.normal(0.0, 0.012, a.shape[:2])[..., None]  # fine grain
    return Image.fromarray((np.clip(a, 0.0, 1.0) * 255).astype(np.uint8))


def main():
    model = sys.argv[sys.argv.index("--sr") + 1] if "--sr" in sys.argv else None
    os.makedirs(OUT, exist_ok=True)
    only = [a for a in sys.argv[1:] if a in SOURCES]
    for car, poses in SOURCES.items():
        if only and car not in only:
            continue
        for pose, (src, box) in poses.items():
            im = load(src).crop(box)
            # cover the 3:4 frame (crop the longer side, keep the top: faces are high in these pictures)
            want = W / H
            if im.width / im.height > want:
                nw = int(im.height * want)
                x0 = (im.width - nw) // 2
                im = im.crop((x0, 0, x0 + nw, im.height))
            else:
                nh = int(im.width / want)
                im = im.crop((0, 0, im.width, nh))
            out = grade(upscale_sr(im, W, H, model) if model else upscale(im, W, H))
            path = os.path.join(OUT, "%s_%s.webp" % (car, pose))
            out.save(path, quality=90)
            print("wrote", path, "from", src, box)


if __name__ == "__main__":
    main()
