class_name MatKit
extends RefCounted
## Materials with generated textures: painted metal with scratches, chips, grime and rust streaks,
## bare steel, chrome, rubber, glass, emissive lamps. Textures are drawn pixel by pixel once and
## cached for the whole run (static), so a scene reload does not rebuild them.
## Everything uses triplanar mapping, so meshes need no UVs. Streaks run down the image's Y axis,
## which is "down" on every vertical face.

const SIZE := 256

static var _cache := {}


## Painted metal. wear 0..1 = scratches and chipped paint, rust 0..1 = rust spots and streaks,
## dirt 0..1 = grime. tile = meters per texture repeat.
static func paint(base: Color, wear := 0.3, rust := 0.2, dirt := 0.3, tile := 2.0, gloss := 0.45, seed := 1) -> StandardMaterial3D:
	var key := "paint_%s_%.2f_%.2f_%.2f_%.2f_%.2f_%d" % [base.to_html(), wear, rust, dirt, tile, gloss, seed]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + int(base.r * 255) * 31 + int(base.g * 255) * 17 + int(base.b * 255)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = rng.randi()
	fine.frequency = 0.09
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var bare := Color(0.42, 0.41, 0.4)
	var rust_c := Color(0.42, 0.2, 0.08)
	var dirt_c := base.darkened(0.55).lerp(Color(0.25, 0.21, 0.16), 0.5)
	for y in SIZE:
		for x in SIZE:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.lightened((n - 0.5) * 0.12) if n > 0.5 else base.darkened((0.5 - n) * 0.12)
			var gloss_v := gloss + (f - 0.5) * 0.12
			var g := clampf((n - 0.62 + dirt * 0.25) * 2.2, 0.0, 1.0) * dirt
			c = c.lerp(dirt_c, g * 0.7)
			gloss_v += g * 0.3
			albedo.set_pixel(x, y, c)
			rough.set_pixel(x, y, Color(clampf(gloss_v, 0.05, 1.0), 0, 0))
			height.set_pixel(x, y, Color(0.5 + (f - 0.5) * 0.06, 0, 0))
	# Chipped paint: little blobs of bare metal, some of them rusting.
	var chips := int(40 * wear)
	for i in chips:
		var cx := rng.randi_range(0, SIZE - 1)
		var cy := rng.randi_range(0, SIZE - 1)
		var r := rng.randf_range(1.0, 4.0)
		var rusty := rng.randf() < rust
		_blob(albedo, rough, height, cx, cy, r, rust_c if rusty else bare, 0.9 if rusty else 0.35, 0.3)
	# Scratches: thin bright lines.
	for i in int(60 * wear):
		var x0 := rng.randf_range(0, SIZE)
		var y0 := rng.randf_range(0, SIZE)
		var a := rng.randf_range(0, TAU)
		var length := rng.randf_range(6, 30)
		for t in int(length):
			var px := int(x0 + cos(a) * t) % SIZE
			var py := int(y0 + sin(a) * t) % SIZE
			if px < 0:
				px += SIZE
			if py < 0:
				py += SIZE
			albedo.set_pixel(px, py, albedo.get_pixel(px, py).lerp(Color(0.75, 0.74, 0.72), 0.55))
			height.set_pixel(px, py, Color(0.38, 0, 0))
	# Rust spots with streaks running down.
	for i in int(14 * rust):
		var cx := rng.randi_range(0, SIZE - 1)
		var cy := rng.randi_range(0, SIZE - 1)
		_blob(albedo, rough, height, cx, cy, rng.randf_range(2.0, 6.0), rust_c, 0.95, 0.62)
		var streak := rng.randi_range(12, 50)
		var w := rng.randi_range(1, 3)
		for t in streak:
			for dx in range(-w, w + 1):
				var px := (cx + dx + int(sin(t * 0.3) * 1.5)) % SIZE
				var py := (cy + t) % SIZE
				if px < 0:
					px += SIZE
				var k := (1.0 - float(t) / streak) * 0.55
				albedo.set_pixel(px, py, albedo.get_pixel(px, py).lerp(rust_c.darkened(0.2), k))
				rough.set_pixel(px, py, Color(lerpf(rough.get_pixel(px, py).r, 0.9, k), 0, 0))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true # MeshBuilder bakes dust/grime into vertex colors
	m.albedo_texture = ImageTexture.create_from_image(albedo)
	m.roughness_texture = ImageTexture.create_from_image(rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.metallic = 0.15
	m.metallic_specular = 0.6
	height.bump_map_to_normal_map(3.0)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(height)
	m.normal_scale = 0.6
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func _blob(albedo: Image, rough: Image, height: Image, cx: int, cy: int, r: float, col: Color, rv: float, hv: float) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var d := sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			var px := (cx + dx) % SIZE
			var py := (cy + dy) % SIZE
			if px < 0:
				px += SIZE
			if py < 0:
				py += SIZE
			var k := 1.0 - d * d
			albedo.set_pixel(px, py, albedo.get_pixel(px, py).lerp(col, k))
			rough.set_pixel(px, py, Color(lerpf(rough.get_pixel(px, py).r, rv, k), 0, 0))
			height.set_pixel(px, py, Color(lerpf(height.get_pixel(px, py).r, hv, k), 0, 0))


## Bare or dark steel (frames, armor plates, guns).
static func steel(base := Color(0.22, 0.22, 0.23), rust := 0.25, tile := 1.5) -> StandardMaterial3D:
	var key := "steel_%s_%.2f_%.2f" % [base.to_html(), rust, tile]
	if _cache.has(key):
		return _cache[key]
	var m := paint(base, 0.6, rust, 0.4, tile, 0.55, 3).duplicate() as StandardMaterial3D
	m.metallic = 0.7
	_cache[key] = m
	return m


static func chrome(tint := Color(0.78, 0.78, 0.8)) -> StandardMaterial3D:
	var key := "chrome_%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true # MeshBuilder bakes dust/grime into vertex colors
	m.albedo_color = tint
	m.metallic = 1.0
	m.roughness = 0.12
	m.metallic_specular = 0.8
	_cache[key] = m
	return m


## Tire rubber with a faint tread-wear texture.
static func rubber() -> StandardMaterial3D:
	if _cache.has("rubber"):
		return _cache["rubber"]
	var m := paint(Color(0.07, 0.07, 0.075), 0.0, 0.0, 0.5, 0.6, 0.85, 5).duplicate() as StandardMaterial3D
	m.metallic = 0.0
	_cache["rubber"] = m
	return m


static func glass(tint := Color(0.08, 0.12, 0.16), alpha := 0.75) -> StandardMaterial3D:
	var key := "glass_%s_%.2f" % [tint.to_html(), alpha]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true # MeshBuilder bakes dust/grime into vertex colors
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.6
	m.roughness = 0.04
	m.metallic_specular = 1.0
	_cache[key] = m
	return m


static func lamp(color: Color, energy := 3.0) -> StandardMaterial3D:
	var key := "lamp_%s_%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true # MeshBuilder bakes dust/grime into vertex colors
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	_cache[key] = m
	return m


static func flat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true # MeshBuilder bakes dust/grime into vertex colors
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m


## Ground surfaces in world space (triplanar), one texture tile = tile_m meters:
##   kind "concrete": poured slabs with joints, cracks, oil stains and patches (lots, sidewalks)
##   kind "asphalt":  coarse aggregate, sealed crack lines, darker tire tracks, patches
## Drawn once per kind and cached. Two-sided so hand-built ground meshes never go black.
static func pavement(kind: String, base: Color, tile_m := 16.0, seed := 1) -> StandardMaterial3D:
	var key := "pave_%s_%s_%.1f_%d" % [kind, base.to_html(), tile_m, seed]
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var coarse := FastNoiseLite.new()
	coarse.seed = rng.randi()
	coarse.frequency = 0.012
	coarse.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = rng.randi()
	grain.frequency = 0.35
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var n := coarse.get_noise_2d(x, y) * 0.5 + 0.5
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.darkened((1.0 - n) * 0.22).lightened((g - 0.5) * 0.1)
			var r := 0.88 + (g - 0.5) * 0.1
			if kind == "concrete" and (x % 64 < 1 or y % 64 < 1):
				c = c.darkened(0.35) # slab joints every 4 m (tile 16 m)
			img.set_pixel(x, y, c)
			rough.set_pixel(x, y, Color(r, 0, 0))
	# Stains (oil, water) and patches.
	for i in 10:
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		var rad := rng.randf_range(4.0, 18.0)
		var dark := rng.randf_range(0.15, 0.4)
		for dy in range(-int(rad), int(rad) + 1):
			for dx in range(-int(rad), int(rad) + 1):
				var d := Vector2(dx, dy).length() / rad
				if d > 1.0:
					continue
				var px := posmod(cx + dx, size)
				var py := posmod(cy + dy, size)
				var k := (1.0 - d * d) * dark
				img.set_pixel(px, py, img.get_pixel(px, py).darkened(k))
				rough.set_pixel(px, py, Color(lerpf(rough.get_pixel(px, py).r, 0.55, k * 1.5), 0, 0))
	# Cracks: wandering dark lines (asphalt also gets lighter sealant over some).
	for i in (6 if kind == "concrete" else 4):
		var p := Vector2(rng.randf_range(0, size), rng.randf_range(0, size))
		var a := rng.randf_range(0, TAU)
		var seal := kind == "asphalt" and rng.randf() < 0.5
		for t in rng.randi_range(20, 70):
			a += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(a), sin(a))
			var px := posmod(int(p.x), size)
			var py := posmod(int(p.y), size)
			var col := img.get_pixel(px, py)
			img.set_pixel(px, py, col.darkened(0.28) if not seal else col.darkened(0.35))
	img.generate_mipmaps()
	rough.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness_texture = ImageTexture.create_from_image(rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## The same material for plain primitive meshes (MeshKit boxes etc.), which carry no vertex
## colors: MatKit materials read the dust baked into MeshBuilder's vertex colors.
static func plain(m: StandardMaterial3D) -> StandardMaterial3D:
	var key := "plain_%d" % m.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var d := m.duplicate() as StandardMaterial3D
	d.vertex_color_use_as_albedo = false
	_cache[key] = d
	return d


static func _world_material(img: Image, tile_m: float, roughness: float, two_sided := true) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Large stone pavers (plazas): 2 m slabs in slightly different tones, dark joints, a few
## cracked or sunken slabs, grime in the joints. One tile = tile_m meters (4 x 4 slabs).
static func pavers(base: Color, tile_m := 8.0, seed := 1) -> StandardMaterial3D:
	var key := "pavers_%s_%.1f_%d" % [base.to_html(), tile_m, seed]
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var cell := size / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grain := FastNoiseLite.new()
	grain.seed = rng.randi()
	grain.frequency = 0.25
	var blotch := FastNoiseLite.new()
	blotch.seed = rng.randi()
	blotch.frequency = 0.03
	var tones: Array[float] = []
	for i in 16:
		tones.append(rng.randf_range(-0.08, 0.08))
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var tx := x / cell
			var ty := y / cell
			var t := tones[ty * 4 + tx]
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var b := blotch.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			c = c.darkened((1.0 - b) * 0.18).lightened((g - 0.5) * 0.08)
			var jx := mini(x % cell, cell - 1 - x % cell)
			var jy := mini(y % cell, cell - 1 - y % cell)
			var j := mini(jx, jy)
			if j < 2:
				c = c.darkened(0.45)
			elif j < 4:
				c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	for i in 5: # cracks across a slab
		var p := Vector2(rng.randf_range(0, size), rng.randf_range(0, size))
		var a := rng.randf_range(0, TAU)
		for k in rng.randi_range(15, 40):
			a += rng.randf_range(-0.4, 0.4)
			p += Vector2(cos(a), sin(a))
			var px := posmod(int(p.x), size)
			var py := posmod(int(p.y), size)
			img.set_pixel(px, py, img.get_pixel(px, py).darkened(0.35))
	var m := _world_material(img, tile_m, 0.85)
	_cache[key] = m
	return m


## Dry LA grass: muted green with yellowed and bare patches.
static func grass(base: Color, tile_m := 12.0, seed := 1) -> StandardMaterial3D:
	var key := "grass_%s_%.1f_%d" % [base.to_html(), tile_m, seed]
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var big := FastNoiseLite.new()
	big.seed = rng.randi()
	big.frequency = 0.02
	big.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = rng.randi()
	fine.frequency = 0.6
	var dry := Color(0.5, 0.45, 0.28)
	var dirt := Color(0.36, 0.3, 0.22)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var b := big.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.lerp(dry, smoothstep(0.45, 0.8, b) * 0.7)
			if b < 0.22:
				c = c.lerp(dirt, smoothstep(0.22, 0.1, b))
			c = c.darkened((1.0 - f) * 0.22).lightened(f * 0.05)
			img.set_pixel(x, y, c)
	var m := _world_material(img, tile_m, 0.97)
	_cache[key] = m
	return m


## Chaparral hillside (the hills around LA): clumps of dark scrub over dry tan earth, darker in
## the folds. Seen from far away, so one tile covers tile_m meters.
static func chaparral(tile_m := 40.0, seed := 1) -> StandardMaterial3D:
	var key := "chaparral_%.1f_%d" % [tile_m, seed]
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var big := FastNoiseLite.new()
	big.seed = rng.randi()
	big.frequency = 0.012
	big.fractal_octaves = 3
	var clump := FastNoiseLite.new()
	clump.seed = rng.randi()
	clump.frequency = 0.07
	clump.fractal_octaves = 2
	var fine := FastNoiseLite.new()
	fine.seed = rng.randi()
	fine.frequency = 0.7
	var scrub := Color(0.16, 0.19, 0.1)
	var sage := Color(0.3, 0.31, 0.2)
	var dry := Color(0.47, 0.4, 0.27)
	var dirt := Color(0.38, 0.3, 0.21)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var b := big.get_noise_2d(x, y) * 0.5 + 0.5
			var k := clump.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var c := dry.lerp(dirt, smoothstep(0.55, 0.8, b))
			c = c.lerp(sage, smoothstep(0.35, 0.55, k) * 0.8)
			c = c.lerp(scrub, smoothstep(0.52, 0.66, k + (b - 0.5) * 0.3))
			c = c.darkened((1.0 - f) * 0.3)
			img.set_pixel(x, y, c)
	var m := _world_material(img, tile_m, 1.0)
	_cache[key] = m
	return m


## Stone block wall (retaining walls): courses of rough blocks with mortar, rain streaks.
static func masonry(base: Color, tile_m := 4.0, seed := 1) -> StandardMaterial3D:
	var key := "masonry_%s_%.1f_%d" % [base.to_html(), tile_m, seed]
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var rows := 8
	var row_h := size / rows
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grain := FastNoiseLite.new()
	grain.seed = rng.randi()
	grain.frequency = 0.15
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var offsets: Array[int] = []
	var widths: Array[int] = []
	for r in rows:
		offsets.append(rng.randi_range(0, 60))
		widths.append(rng.randi_range(44, 72))
	for y in size:
		var r := y / row_h
		var yy := y % row_h
		for x in size:
			var xs := (x + offsets[r]) % size
			var block := xs / widths[r]
			var xx := xs % widths[r]
			var h := fposmod(sin(float(block * 31 + r * 17) * 12.9898) * 43758.5453, 1.0)
			var c := base.lightened((h - 0.5) * 0.18) if h > 0.5 else base.darkened((0.5 - h) * 0.22)
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			c = c.darkened((1.0 - g) * 0.2)
			if yy < 3 or xx < 3:
				c = base.darkened(0.5) # mortar
			elif yy < 6 or xx < 6:
				c = c.darkened(0.15)
			var streak := fposmod(sin(float(x) * 7.31) * 9341.7, 1.0)
			if streak > 0.9:
				c = c.darkened(0.12 * float(size - y) / size)
			img.set_pixel(x, y, c)
	var m := _world_material(img, tile_m, 0.9, false)
	m.vertex_color_use_as_albedo = true
	_cache[key] = m
	return m

