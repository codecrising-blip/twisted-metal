"""Shared picture tools for the portraits (round 26): LaMa inpainting, a figure matte, rim light.
LaMa = big-lama ONNX with dynamic size (github.com/CloudyTabzy/LaMa-OxiONNX release model-lama-fp32-v1)."""
import numpy as np
import cv2
from PIL import Image, ImageDraw

_sess = None


def lama(a, hole, model, pad=48):
    """Paint the hole (HxW 0/1) of a (HxWx3 float 0..255) back in from what is round it."""
    global _sess
    import onnxruntime as ort
    if _sess is None:
        _sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    H, W = hole.shape
    ys, xs = np.nonzero(hole)
    x0 = max(0, xs.min() - pad); y0 = max(0, ys.min() - pad); x1 = min(W, xs.max() + pad); y1 = min(H, ys.max() + pad)
    img = a[y0:y1, x0:x1] / 255.0
    m = hole[y0:y1, x0:x1].astype(np.float32)
    img = img * (1 - m[..., None])
    ch, cw = m.shape
    ph = -ch % 64; pw = -cw % 64  # its FFT blocks want sides in multiples of 64
    ip = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode="reflect"); mp = np.pad(m, ((0, ph), (0, pw)), mode="reflect")
    ins = _sess.get_inputs()
    out = _sess.run(None, {ins[0].name: ip.transpose(2, 0, 1)[None].astype(np.float32), ins[1].name: mp[None, None]})[0]
    out = out[0].transpose(1, 2, 0)[:ch, :cw]
    if out.max() <= 1.5:
        out = out * 255.0
    res = a.copy()
    mm = cv2.GaussianBlur(m, (0, 0), 1.2)[..., None]
    res[y0:y1, x0:x1] = a[y0:y1, x0:x1] * (1 - mm) + out * mm
    return res


def poly(shape, ps, blur=0.0):
    """A filled polygon as a float mask (0..1)."""
    H, W = shape
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(ps, fill=255)
    m = np.asarray(m, np.float32) / 255.0
    return cv2.GaussianBlur(m, (0, 0), blur) if blur else m


def matte(a, model="isnet-general-use"):
    """The figure's matte (0..1). Dark figures on dark grounds are lifted first or the matte loses them."""
    from rembg import remove, new_session
    lifted = np.clip(((a / 255.0) ** 0.5) * 1.3, 0, 1)
    m = remove(Image.fromarray((lifted * 255).astype(np.uint8)), session=new_session(model), only_mask=True)
    return np.asarray(m, np.float32) / 255.0


def clean_mask(mask, open_px=13):
    """The figure only: smoke wisps and specks the matte caught are opened away, the largest blob kept."""
    M = (mask > 0.5).astype(np.uint8)
    M = cv2.morphologyEx(M, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (open_px, open_px)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(M, 8)
    if n > 1:
        M = (lab == 1 + int(np.argmax(st[1:, 4]))).astype(np.uint8)
    return M.astype(np.float32)


def rim_light(a, mask, color, strength=1.0, width=4.0, reach=40.0, detail=0.7, sides=1.0, top=0.5, bottom=0.0, lift=0.0, keep_out=None, seed=1):
    """a: HxWx3 float 0..255, mask: HxW 0..1 (the figure). color: (r, g, b) 0..1."""
    M = (mask > 0.5).astype(np.uint8)
    d_in = cv2.distanceTransform(M, cv2.DIST_L2, 5)
    sm = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 6.0)
    gy, gx = np.gradient(sm)
    n = np.sqrt(gx * gx + gy * gy) + 1e-6
    nx, ny = -gx / n, -gy / n  # outward normal
    wdir = sides * np.abs(nx) + top * np.clip(-ny, 0, 1) + bottom * np.clip(ny, 0, 1)
    wdir = cv2.GaussianBlur(np.clip(wdir, 0, 1).astype(np.float32), (0, 0), 10.0)  # carried inward from the edge
    rim = np.exp(-d_in / width) * M * wdir
    L = a.mean(2)
    hp = np.clip(L - cv2.GaussianBlur(L, (0, 0), 5.0), 0, None) / 40.0  # the coat's own light lines and ridges
    det = np.clip(hp, 0, 1) * np.exp(-d_in / reach) * M * wdir * detail
    # light catches some stretches of an edge more than others
    rng = np.random.default_rng(seed)
    wob = cv2.GaussianBlur(rng.random(M.shape).astype(np.float32), (0, 0), 9.0)
    wob = np.clip((wob - wob.mean()) / (wob.std() + 1e-6) * 0.35 + 0.8, 0.25, 1.2)
    glow = (rim * wob + det + lift * np.exp(-d_in / (reach * 2)) * M * wdir)
    if keep_out is not None:
        glow = glow * (1.0 - keep_out)
    glow = glow[..., None] * strength
    col = np.array(color, np.float32)[None, None, :] * 255.0
    out = a + glow * col * (1.0 - a / 255.0) * 1.6  # screen-like: dark cloth takes the colour, bright ink stays
    return np.clip(out, 0, 255)
