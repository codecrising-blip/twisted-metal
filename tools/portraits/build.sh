#!/bin/bash
# Driver portraits for the select screen (round 25): the owner's own art (docs/reference/portraits/owner_<car>.webp,
# a before-pick | after-pick sheet each), with the owner's fixes made here:
#   Mr. Grimm, Sweet Tooth: as drawn.
#   Roadkill: the clowns behind him after the pick are gone: Marcus cut out (rembg's isnet-anime), the background
#     rebuilt from the before-picture's own purple grunge (patches + its light + smoke clouds), a little darker.
#   Axel: the first pose closer (head to knees, EDSR x4 up), a little brighter, the AXEL lettering put back.
#   Outlaw: army clothes -> a clean police uniform (navy cloth smoothed, black leather strap and duty belt, the torn
#     sleeve closed, a gold badge and a POLICE shoulder patch). Round 26: her name JAMIE ROBERTS instead of the OUTLAW
#     title, like the others (names.py: the owner's own letters).
#   Thumper (round 29): the owner's new sheet (already says BRUCE), as drawn.
#   Brimstone / Jedediah (round 29): the PREACHER panel with a bible in his chest pocket (brimstone_bible.py); the
#     after-pick picture waits for the owner's courageous one (the idle picture stands in).
#   Darkside / Mr. Ash (round 26, mr_ash.py): hair off, a red rim light, and the after picture = the same body with
#     only the reaching arm moved (owner_darkside.webp; paint.py holds the shared LaMa / matte / rim tools).
# Old lettering comes off with LaMa (unletter.py): LAMA=/path/lama_fp32.onnx (github.com/CloudyTabzy/LaMa-OxiONNX,
# release model-lama-fp32-v1, sha256 aacebdf7...d584).
# Needs a venv with: opencv-contrib-python-headless<5 rembg onnxruntime pillow numpy (PyPI), the EDSR weights
# (github.com/Saafke/EDSR_Tensorflow models/EDSR_x4.pb). rembg downloads isnet-anime.onnx to $U2NET_HOME.
#   PY=/path/venv/bin/python EDSR=/path/EDSR_x4.pb LAMA=/path/lama_fp32.onnx tools/portraits/build.sh
set -e
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
$PY -I tools/portraits/split.py docs/reference/portraits "$W"
$PY -I tools/portraits/unletter.py "$W" outlaw "$LAMA" 64 575 505 830
for f in roadkill_select roadkill_idle outlaw_select; do
  $PY -I tools/portraits/matte.py "$W/${f}_raw.png" "$W/${f}_mask$( [ $f = roadkill_select ] && echo _anime ).png" isnet-anime
done
$PY -I tools/portraits/matte.py "$W/outlaw_idle_clean.png" "$W/outlaw_idle_mask.png" isnet-anime
$PY -I tools/portraits/roadkill_background.py "$W"
$PY -I tools/portraits/axel_idle.py "$W" "$EDSR"
$PY -I tools/portraits/outlaw_police.py "$W"
$PY -I tools/portraits/names.py "$W"
$PY -I tools/portraits/mr_ash.py "$W" "$LAMA"
$PY -I tools/portraits/brimstone_bible.py "$W/brimstone_idle_raw.png" "$W/brimstone_idle_bible.png"
$PY -I - "$W" <<'PYEOF'
import sys
from PIL import Image
W = sys.argv[1]
pick = {"mr_grimm": ("idle_raw", "select_raw"), "sweet_tooth": ("idle_raw", "select_raw"),
        "roadkill": ("idle_raw", "select_fixed"), "axel": ("idle_fixed", "select_raw"), "outlaw": ("idle_named", "select_fixed"),
        "thumper": ("idle_raw", "select_raw"), "darkside": ("idle_fixed", "select_fixed"),
        "brimstone": ("idle_bible", "idle_bible")}
for car, (i, s) in pick.items():
    for pose, src in (("idle", i), ("select", s)):
        Image.open("%s/%s_%s.png" % (W, car, src)).convert("RGB").save("assets/portraits/%s_%s.webp" % (car, pose), quality=92)
        print("wrote assets/portraits/%s_%s.webp" % (car, pose))
PYEOF
