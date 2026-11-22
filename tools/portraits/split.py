"""Cut the owner's portrait sheets (docs/reference/portraits/owner_<car>.webp: before-pick panel | white line |
after-pick panel) into <work>/<car>_idle_raw.png and <car>_select_raw.png."""
import sys
import numpy as np
from PIL import Image

REF, WORK = sys.argv[1], sys.argv[2]
for car in ["mr_grimm", "outlaw", "sweet_tooth", "roadkill", "axel", "thumper"]:
    im = Image.open("%s/owner_%s.webp" % (REF, car)).convert("RGB")
    a = np.asarray(im).astype(int)
    w = a.shape[1]
    white = (a.min(axis=2) > 200).mean(axis=0)
    xs = [x for x in range(300, w - 300) if white[x] > 0.8]  # the white line between the panels
    l, r = min(xs) - 2, max(xs) + 3
    im.crop((0, 0, l, im.height)).save("%s/%s_idle_raw.png" % (WORK, car))
    im.crop((r, 0, w, im.height)).save("%s/%s_select_raw.png" % (WORK, car))
    print(car, "split at", l, r)
