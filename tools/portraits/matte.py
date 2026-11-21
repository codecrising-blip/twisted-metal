import sys
from rembg import remove, new_session
from PIL import Image
src, out, model = sys.argv[1], sys.argv[2], sys.argv[3]
sess = new_session(model)
im = Image.open(src).convert("RGB")
m = remove(im, session=sess, only_mask=True)
m.save(out)
print("mask", m.size)
