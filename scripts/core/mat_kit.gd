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
	var m := paint(base, 0.6, rust, 0.4, tile, 0.5, 3).duplicate() as StandardMaterial3D
	m.metallic = 0.75
	return m


static func chrome(tint := Color(0.78, 0.78, 0.8)) -> StandardMaterial3D:
	var key := "chrome_%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
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
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m
