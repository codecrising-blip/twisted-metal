# Blender asset pipeline (round 10)

Models are built by the scripts here, weathered and baked to a texture atlas, and exported to
`assets/models/` as `.glb` + `_albedo/_normal/_orm.webp`. The game loads them with `ModelLib`.

```bash
python3.13 -m venv /tmp/bpy3.13 && /tmp/bpy3.13/bin/pip install bpy==5.3.0 pillow   # Blender 5.3 as a module
/tmp/bpy3.13/bin/python tools/blender/build_pickups.py            # rebuild + rebake (about 3 min)
/tmp/bpy3.13/bin/python tools/blender/build_pickups.py --nobake   # geometry only (seconds)
godot --headless --path . --import                                # Godot picks up the new files
```

`tmlib.py` is the library: geometry helpers, `M(kind, colour, wear, rust, dirt)` weathering
materials, `gbuffer()` (Cycles bake) and `weather()` (the look, composited in numpy), decals
(stencils, stripes), `export_glb()`. Read its header first.
