class_name LaCity
extends Node3D
## The city around the Los Angeles arena (owner, session 5: "a city below the battleground, which
## is a little higher than the city"). The arena is a plateau at y = 0, held up by concrete retaining
## walls; the streets run CITY_Y below it out to the haze. Built for the Intel HD 5500:
##   - every building is one instance of a single MultiMesh (one draw call for ~5000 buildings);
##     windows, floors and roofs are drawn by a small shader, not by geometry
##   - the street grid is one generated texture tiled once per block
##   - palms, freeway pillars and roof clutter are MultiMeshes too; nothing out here casts shadows
## Layout: low stucco blocks next to the plateau (their roofs stay below it, so the view is open),
## mid-rise further out, a downtown of towers to the north-east, two elevated freeways, mountains.

const CITY_Y := -22.0
const BLOCK := 80.0 # street centerline spacing
const STREET := 18.0
const SIDEWALK := 3.0
const PLATEAU := 132.0 # outer face of the retaining walls
const REACH := 1500.0
const DOWNTOWN := Vector2(560, -820)
const FREEWAY_Z := 410.0 # east-west freeway (south of the arena)
const FREEWAY_X := 470.0 # north-south freeway (east of the arena)
const FREEWAY_Y := 10.0 # deck height above the streets

var _rng := RandomNumberGenerator.new()
var _building_mat: ShaderMaterial
var _concrete: StandardMaterial3D


func build() -> void:
	_rng.seed = 2026
	_concrete = _panel_concrete()
	_ground()
	_retaining_walls()
	_buildings()
	_freeways()
	_palms()
	_mountains()
	_plumes()


# ---------------------------------------------------------------- materials

## Facades drawn in the shader: floors and window bays in world space, so any box size works.
## Instance color rgb = wall color, alpha = style (0 punched windows, 0.5 glass tower, 1 low-rise).
const BUILDING_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float city_y = -22.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 base = COLOR.rgb;
	float style = COLOR.a;
	if (wnrm.y > 0.5) {
		float g = hash(floor(wpos.xz * 0.5));
		ALBEDO = base * 0.45 + vec3(0.05) + g * 0.03;
		ROUGHNESS = 0.95;
	} else {
		float u = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
		float floor_h = style > 0.25 && style < 0.75 ? 3.9 : 3.5;
		float bay = style > 0.25 && style < 0.75 ? 1.6 : 3.2;
		float y = wpos.y - city_y;
		vec2 cell = vec2(u / bay, y / floor_h);
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float h = hash(id + floor(wpos.xz / 40.0));
		float win;
		if (style < 0.25) {
			win = step(0.2, f.x) * step(f.x, 0.8) * step(0.32, f.y) * step(f.y, 0.82);
		} else if (style < 0.75) {
			win = step(0.07, f.x) * step(f.x, 0.93) * step(0.1, f.y) * step(f.y, 0.94);
		} else {
			win = step(0.28, f.x) * step(f.x, 0.72) * step(0.38, f.y) * step(f.y, 0.8);
		}
		vec3 glass = mix(vec3(0.05, 0.065, 0.08), vec3(0.3, 0.34, 0.38), h * h);
		vec3 glass_avg = vec3(0.12, 0.14, 0.17);
		if (style > 0.25 && style < 0.75) {
			glass = mix(vec3(0.07, 0.09, 0.12), vec3(0.3, 0.35, 0.4), h);
			glass_avg = vec3(0.16, 0.19, 0.23);
		}
		if (h > 0.95) { glass = vec3(0.015); }
		float shop = 1.0 - step(1.0, cell.y);
		win = max(win * (1.0 - shop), shop * step(0.1, f.x) * step(f.x, 0.9) * step(0.08, f.y) * step(f.y, 0.75));
		// Far away the window grid is finer than a pixel: fade to its average instead of shimmering.
		vec2 fw = fwidth(cell);
		float aa = clamp(max(fw.x, fw.y) * 2.5 - 0.4, 0.0, 1.0);
		float cover = style < 0.25 ? 0.3 : (style < 0.75 ? 0.72 : 0.18);
		win = mix(win, cover, aa);
		glass = mix(glass, glass_avg, aa);
		float streak = 0.88 + 0.12 * hash(vec2(floor(u / 2.0), 1.0));
		vec3 wall = base * streak * mix(0.82, 1.0, smoothstep(0.0, 6.0, y));
		ALBEDO = mix(wall, glass, win);
		ROUGHNESS = mix(0.9, 0.2, win);
		METALLIC = win * 0.35;
	}
}
"""


func _make_building_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = BUILDING_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("city_y", CITY_Y)
	return m


## Concrete panels with seams and rain stains (retaining walls, freeway).
func _panel_concrete() -> StandardMaterial3D:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base := Color(0.56, 0.54, 0.5)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.darkened(0.25 * (1.0 - n))
			if x < 2 or y < 2:
				c = Color(0.3, 0.29, 0.27)
			var streak := fposmod(sin(float(x) * 12.9898) * 43758.5453, 1.0)
			if streak > 0.85:
				c = c.darkened(0.15 * float(y) / size)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 6.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## One city block as a texture (street centerlines on the tile edges): asphalt with lane lines and
## crosswalks, curbs, sidewalks, then the lot (parking, gravel) where the buildings stand.
func _street_material() -> StandardMaterial3D:
	var size := 256
	var mpp := BLOCK / size # meters per pixel
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.08
	var half_street := STREET * 0.5
	for py in size:
		for px in size:
			var x := px * mpp
			var z := py * mpp
			var dx := minf(x, BLOCK - x) # distance to the nearest centerline
			var dz := minf(z, BLOCK - z)
			var n := noise.get_noise_2d(px, py) * 0.5 + 0.5
			var c: Color
			if dx < half_street or dz < half_street:
				c = Color(0.2, 0.2, 0.21).darkened(0.2 * (1.0 - n))
				var along_x := dz < half_street and dx >= half_street # street running along x
				var along_z := dx < half_street and dz >= half_street
				if along_x and dz < 0.35:
					c = Color(0.62, 0.5, 0.12)
				elif along_z and dx < 0.35:
					c = Color(0.62, 0.5, 0.12)
				elif along_x and absf(dz - 4.5) < 0.2 and fmod(x, 9.0) < 4.0:
					c = Color(0.6, 0.6, 0.57)
				elif along_z and absf(dx - 4.5) < 0.2 and fmod(z, 9.0) < 4.0:
					c = Color(0.6, 0.6, 0.57)
				elif dx < half_street and dz >= half_street and dz < half_street + 4.0 and fmod(x, 1.6) < 0.8:
					c = Color(0.64, 0.64, 0.6) # crosswalk
				elif dz < half_street and dx >= half_street and dx < half_street + 4.0 and fmod(z, 1.6) < 0.8:
					c = Color(0.64, 0.64, 0.6)
			elif dx < half_street + SIDEWALK or dz < half_street + SIDEWALK:
				c = Color(0.55, 0.53, 0.5).darkened(0.15 * (1.0 - n))
				if fmod(x, 2.0) < mpp or fmod(z, 2.0) < mpp:
					c = c.darkened(0.15)
			else:
				c = Color(0.36, 0.35, 0.33).darkened(0.25 * (1.0 - n))
			img.set_pixel(px, py, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / BLOCK
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------- ground and plateau

func _ground() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000.0, 9000.0)
	mi.mesh = plane
	mi.material_override = _street_material()
	mi.position = Vector3(0, CITY_Y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Retaining walls around the plateau, with buttresses, a parapet line and drain stains.
func _retaining_walls() -> void:
	var mb := MeshBuilder.new()
	var h := -CITY_Y
	var dark := MatKit.flat(Color(0.25, 0.24, 0.22), 0.95)
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		var out := basis * Vector3(0, 0, -1)
		var along := basis * Vector3(1, 0, 0)
		var c := out * (PLATEAU - 2.0) + Vector3(0, CITY_Y + h * 0.5, 0)
		mb.box(_concrete, (basis * Vector3(PLATEAU * 2.0, h, 4.0)).abs(), MeshBuilder.at(c), 0.0)
		for k in 17:
			var t := -PLATEAU + 8.0 + k * 16.0
			var p := out * (PLATEAU + 0.6) + along * t + Vector3(0, CITY_Y + h * 0.5 - 1.0, 0)
			mb.box(_concrete, (basis * Vector3(2.0, h - 2.0, 1.4)).abs(), MeshBuilder.at(p), 0.15)
			var drain := out * (PLATEAU + 0.02) + along * (t + 8.0) + Vector3(0, -3.0, 0)
			mb.box(dark, (basis * Vector3(0.5, 0.5, 0.1)).abs(), MeshBuilder.at(drain), 0.0)
		mb.box(dark, (basis * Vector3(PLATEAU * 2.0, 0.5, 0.2)).abs(), MeshBuilder.at(out * (PLATEAU + 0.05) + Vector3(0, -0.6, 0)), 0.0)
	for mi in mb.commit(self, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- buildings

func _height_for(p: Vector2) -> Dictionary:
	var d := p.length()
	var to_dt := p.distance_to(DOWNTOWN)
	var r := _rng.randf()
	if to_dt < 320.0:
		var core := 1.0 - to_dt / 320.0
		if r < 0.25 + core * 0.6:
			return {"h": _rng.randf_range(70.0, 120.0 + 170.0 * core), "style": 0.5}
		return {"h": _rng.randf_range(25.0, 60.0), "style": 0.0}
	if d < 260.0:
		return {"h": _rng.randf_range(6.0, 19.0), "style": 1.0} # roofs stay below the plateau
	if d < 650.0:
		if r < 0.12:
			return {"h": _rng.randf_range(35.0, 70.0), "style": 0.0 if r < 0.08 else 0.5}
		return {"h": _rng.randf_range(10.0, 32.0), "style": 1.0 if r < 0.55 else 0.0}
	return {"h": _rng.randf_range(8.0, 40.0), "style": 1.0 if r < 0.5 else 0.0}


func _wall_color(style: float) -> Color:
	var low := [Color(0.74, 0.68, 0.57), Color(0.7, 0.57, 0.5), Color(0.78, 0.76, 0.7), Color(0.48, 0.3, 0.23),
		Color(0.62, 0.6, 0.55), Color(0.66, 0.62, 0.48)]
	var mid := [Color(0.58, 0.57, 0.54), Color(0.5, 0.5, 0.5), Color(0.66, 0.63, 0.58), Color(0.44, 0.4, 0.36)]
	var tower := [Color(0.3, 0.33, 0.36), Color(0.45, 0.48, 0.5), Color(0.24, 0.26, 0.27), Color(0.55, 0.53, 0.5)]
	var pick: Array = low if style > 0.75 else (tower if style > 0.25 else mid)
	var c: Color = pick[_rng.randi() % pick.size()]
	return c.darkened(_rng.randf_range(0.0, 0.12))


func _under_freeway(x0: float, z0: float, x1: float, z1: float) -> bool:
	var m := 22.0
	if z0 < FREEWAY_Z + m and z1 > FREEWAY_Z - m:
		return true
	if x0 < FREEWAY_X + m and x1 > FREEWAY_X - m:
		return true
	return false


func _buildings() -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var roofs: Array[Transform3D] = []
	var n := int(REACH / BLOCK)
	var lot_in := STREET * 0.5 + SIDEWALK + 1.5
	for bx in range(-n, n):
		for bz in range(-n, n):
			var x0 := bx * BLOCK + lot_in
			var z0 := bz * BLOCK + lot_in
			var x1 := (bx + 1) * BLOCK - lot_in
			var z1 := (bz + 1) * BLOCK - lot_in
			if x1 > -PLATEAU - 14.0 and x0 < PLATEAU + 14.0 and z1 > -PLATEAU - 14.0 and z0 < PLATEAU + 14.0:
				continue
			if _under_freeway(x0, z0, x1, z1):
				continue
			var center := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var d := center.length()
			var nx := 1 if d > 1100.0 else _rng.randi_range(1, 3)
			var nz := 1 if d > 1100.0 else _rng.randi_range(1, 2)
			var w := (x1 - x0) / nx
			var dpt := (z1 - z0) / nz
			for i in nx:
				for j in nz:
					if _rng.randf() < 0.1 and d < 900.0:
						continue # parking lot
					var px := x0 + (i + 0.5) * w
					var pz := z0 + (j + 0.5) * dpt
					var info := _height_for(Vector2(px, pz))
					var h: float = info.h
					var style: float = info.style
					var size := Vector3(w - _rng.randf_range(2.0, 6.0), h, dpt - _rng.randf_range(2.0, 6.0))
					xforms.append(Transform3D(Basis.from_scale(size), Vector3(px, CITY_Y + h * 0.5, pz)))
					var c := _wall_color(style)
					colors.append(Color(c.r, c.g, c.b, style))
					# Setbacks on towers, roof clutter on everything closer in.
					if style > 0.25 and style < 0.75 and h > 90.0:
						var top_h := h * _rng.randf_range(0.15, 0.3)
						var top := Vector3(size.x * 0.65, top_h, size.z * 0.65)
						xforms.append(Transform3D(Basis.from_scale(top), Vector3(px, CITY_Y + h + top_h * 0.5, pz)))
						colors.append(Color(c.r, c.g, c.b, style))
					if d < 800.0:
						for k in _rng.randi_range(1, 3):
							var rs := Vector3(_rng.randf_range(2.0, 5.0), _rng.randf_range(1.2, 2.6), _rng.randf_range(2.0, 4.0))
							var rp := Vector3(px + _rng.randf_range(-size.x, size.x) * 0.3, CITY_Y + h + rs.y * 0.5, pz + _rng.randf_range(-size.z, size.z) * 0.3)
							roofs.append(Transform3D(Basis.from_scale(rs), rp))
	# The building that carries the HOLLYWOOD sign, just north of the arena (its roof at y 6.5).
	xforms.append(Transform3D(Basis.from_scale(Vector3(104, 28.5, 24)), Vector3(-60, CITY_Y + 14.25, -150)))
	colors.append(Color(0.6, 0.58, 0.54, 0.0))
	_building_mat = _make_building_material()
	_multimesh(BoxMesh.new(), xforms, colors, _building_mat)
	var roof_mat := MatKit.plain(MatKit.flat(Color(0.5, 0.5, 0.48), 0.9))
	_multimesh(BoxMesh.new(), roofs, [], roof_mat)
	print("City: %d buildings, %d roof units" % [xforms.size(), roofs.size()])


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ---------------------------------------------------------------- freeways

func _freeways() -> void:
	var deck_y := CITY_Y + FREEWAY_Y
	var width := 30.0
	var asphalt := MatKit.flat(Color(0.2, 0.2, 0.21), 0.9)
	var line := MatKit.flat(Color(0.62, 0.62, 0.58), 0.8)
	var mb := MeshBuilder.new()
	var pillars: Array[Transform3D] = []
	for axis in 2:
		var basis := Basis.IDENTITY if axis == 0 else Basis(Vector3.UP, PI * 0.5)
		var offset := Vector3(0, 0, FREEWAY_Z) if axis == 0 else Vector3(FREEWAY_X, 0, 0)
		var length := REACH * 2.0
		mb.box(_concrete, (basis * Vector3(length, 1.6, width)).abs(), MeshBuilder.at(offset + Vector3(0, deck_y - 0.8, 0)), 0.0)
		mb.box(asphalt, (basis * Vector3(length, 0.05, width - 1.6)).abs(), MeshBuilder.at(offset + Vector3(0, deck_y + 0.02, 0)), 0.0)
		for s: float in [-1.0, 1.0]:
			mb.box(_concrete, (basis * Vector3(length, 1.1, 0.5)).abs(), MeshBuilder.at(offset + basis * Vector3(0, 0, s * (width * 0.5 - 0.25)) + Vector3(0, deck_y + 0.55, 0)), 0.1)
		for lane: float in [-7.0, -3.5, 3.5, 7.0]:
			for k in 80:
				var t := -600.0 + k * 15.0
				mb.box(line, (basis * Vector3(4.0, 0.06, 0.18)).abs(), MeshBuilder.at(offset + basis * Vector3(t, 0, lane) + Vector3(0, deck_y + 0.04, 0)), 0.0)
		for k in int(length / 40.0):
			var t := -REACH + 20.0 + k * 40.0
			var p := offset + basis * Vector3(t, 0, 0)
			if absf(p.x) < PLATEAU + 10.0 and absf(p.z) < PLATEAU + 10.0:
				continue
			for s: float in [-1.0, 1.0]:
				var pp := p + basis * Vector3(0, 0, s * 8.0)
				pillars.append(Transform3D(Basis.from_scale(Vector3(3.0, FREEWAY_Y - 1.6, 3.0)), pp + Vector3(0, CITY_Y + (FREEWAY_Y - 1.6) * 0.5, 0)))
	for mi in mb.commit(self, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_multimesh(BoxMesh.new(), pillars, [], _concrete)


# ---------------------------------------------------------------- palms, mountains, smoke

func _palms() -> void:
	var mb := MeshBuilder.new()
	var trunk := MatKit.paint(Color(0.42, 0.34, 0.24), 0.2, 0.0, 0.5, 0.6, 0.9, 51)
	var frond := MatKit.flat(Color(0.2, 0.32, 0.13), 0.85)
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED
	mb.cylinder(trunk, 0.42, 14.0, MeshBuilder.at(Vector3(0, 7.0, 0)), 7, 0.26, false)
	for k in 10:
		var a := TAU * k / 10.0
		var dir := Vector3(cos(a), -0.35, sin(a)).normalized()
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(0, 14.0, 0) + dir * 2.4)
		mb.box(frond, Vector3(1.1, 0.05, 5.0), xf, 0.0)
	var palm_mesh := mb.build_mesh()
	var xforms: Array[Transform3D] = []
	var n := int(700.0 / BLOCK)
	for bx in range(-n, n + 1):
		for bz in range(-n, n + 1):
			for along in 2:
				for k in 4:
					var t := (k + 0.5) * BLOCK / 4.0
					var off := STREET * 0.5 + 1.5
					var p := Vector3(bx * BLOCK + t, CITY_Y, bz * BLOCK + off) if along == 0 else Vector3(bx * BLOCK + off, CITY_Y, bz * BLOCK + t)
					if absf(p.x) < PLATEAU + 6.0 and absf(p.z) < PLATEAU + 6.0:
						continue
					if Vector2(p.x, p.z).length() > 700.0 or _rng.randf() < 0.45:
						continue
					var s := _rng.randf_range(0.8, 1.25)
					var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
					xforms.append(Transform3D(basis, p))
	_multimesh(palm_mesh, xforms, [], null)


## San Gabriel-style ridges far away in the smog: flat-shaded silhouettes in two hazy layers that
## skip the fog (they would turn white), so they read as distant mountains behind the city.
func _mountains() -> void:
	for layer in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.5, 0.52, 0.56) if layer == 0 else Color(0.58, 0.6, 0.63)
		m.disable_fog = true
		var count := 16 if layer == 0 else 12
		for k in count:
			var a := deg_to_rad(-170.0 + k * (300.0 / count) + _rng.randf_range(-6, 6))
			var r := (3200.0 if layer == 0 else 3900.0) + _rng.randf_range(-200.0, 200.0)
			var size := Vector3(_rng.randf_range(500, 800), _rng.randf_range(170, 330) * (1.0 if layer == 0 else 1.3), _rng.randf_range(250, 400))
			var node := MeshKit.sphere(self, 1.0, Vector3(sin(a) * r, CITY_Y - 30.0, -cos(a) * r), m, size, 10)
			node.rotation.y = -a
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _plumes() -> void:
	for p: Vector3 in [Vector3(420, 0, 260), Vector3(-460, 0, 180), Vector3(260, 0, -520), Vector3(-300, 0, -640)]:
		var plume := FxKit.smoke(16.0, 40)
		plume.lifetime = 16.0
		plume.gravity = Vector3(1.5, 3.0, 0)
		plume.color_ramp = null
		plume.color = Color(0.22, 0.21, 0.2, 0.4)
		plume.position = p + Vector3(0, CITY_Y + 8.0, 0)
		add_child(plume)
		plume.emitting = true
