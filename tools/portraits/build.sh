#!/bin/bash
# Driver portraits for the select screen (round 25): the owner's own art (docs/reference/portraits/owner_<car>.webp,
# a before-pick | after-pick sheet each), with the owner's fixes made here:
#   Mr. Grimm, Sweet Tooth: as drawn.
#   Roadkill: the clowns behind him after the pick are gone: Marcus cut out (rembg's isnet-anime), the background
#     rebuilt from the before-picture's own purple grunge (patches + its light + smoke clouds), a little darker.
#   Axel: the first pose closer (head to knees, EDSR x4 up), a little brighter, the AXEL lettering put back.
#   Outlaw: army clothes -> a clean police uniform (navy cloth smoothed, black leather strap and duty belt, the torn
#     sleeve closed, a gold badge and a POLICE shoulder patch).
# Needs a venv with: opencv-contrib-python-headless<5 rembg onnxruntime pillow numpy (PyPI), the EDSR weights
# (github.com/Saafke/EDSR_Tensorflow models/EDSR_x4.pb). rembg downloads isnet-anime.onnx to $U2NET_HOME.
#   PY=/path/venv/bin/python EDSR=/path/EDSR_x4.pb tools/portraits/build.sh
set -e
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
$PY -I tools/portraits/split.py docs/reference/portraits "$W"
for f in roadkill_select roadkill_idle outlaw_idle outlaw_select; do
  $PY -I tools/portraits/matte.py "$W/${f}_raw.png" "$W/${f}_mask$( [ $f = roadkill_select ] && echo _anime ).png" isnet-anime
done
$PY -I tools/portraits/roadkill_background.py "$W"
$PY -I tools/portraits/axel_idle.py "$W" "$EDSR"
$PY -I tools/portraits/outlaw_police.py "$W"
$PY -I - "$W" <<'PYEOF'
import sys
from PIL import Image
W = sys.argv[1]
pick = {"mr_grimm": ("idle_raw", "select_raw"), "sweet_tooth": ("idle_raw", "select_raw"),
        "roadkill": ("idle_raw", "select_fixed"), "axel": ("idle_fixed", "select_raw"), "outlaw": ("idle_fixed", "select_fixed")}
for car, (i, s) in pick.items():
    for pose, src in (("idle", i), ("select", s)):
        Image.open("%s/%s_%s.png" % (W, car, src)).convert("RGB").save("assets/portraits/%s_%s.webp" % (car, pose), quality=92)
        print("wrote assets/portraits/%s_%s.webp" % (car, pose))
PYEOF
