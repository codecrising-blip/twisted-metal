class_name LosAngelesArena
extends Node3D
## Stage 1 and the test stage: Twisted Metal 2's "Los Angeles: Quake Zone Rumble", rebuilt from the
## TM2 FAQ description (owner's choice, session 3):
##   - a ring road all the way around, with weapons along it
##   - twin tunnels with glass walls you can drive through, and ramps onto their roof (weapons and a
##     teleporter to the caged area)
##   - a small caged area with super health on a raised deck, reached by an overpass ramp
##   - a pit of fire in a quake crater, a burnt-out building next to it
##   - three quake humps in the road with health floating over them
##   - hot dog stands and a power tower with four legs that drop weapons when destroyed
##   - the HOLLYWOOD sign on the hills: shoot every letter from the tunnel roof (easter egg)
## Bright late-afternoon light, as in TM2. Fixed seed: the layout is the same every run.

signal easter_egg(title: String, text: String)

const HALF := 125.0 # inner face of the outer wall
const MAP_HALF := 128 # heightmap reach (1 m samples)
const ROAD_H := 88.0 # ring road centerline half-extent
const ROAD_R := 24.0 # ring road corner radius
const ROAD_W := 18.0
const ROOF_Y := 9.0 # tunnel roof
const DECK_Y := 6.0 # caged deck
const TUNNEL_X0 := -106.0
const TUNNEL_X1 := -70.0
const TUNNEL_Z := 32.0
const DECK_CENTER := Vector3(51, 0, -51)
const TOWER_AT := Vector3(45, 0, 45)
const SIGN_Z := -145.0
const SIGN_BASE_Y := 10.0

var title := "LOS ANGELES"
var subtitle := "Quake Zone Rumble"
var spawn_points: Array[Transform3D] = []
var respawn_points: Array[Transform3D] = []
var weapon_points: Array[Vector3] = []
var health_points: Array[Vector3] = []
var mega_points: Array[Vector3] = []
var ramps: Array[Dictionary] = [] # {foot, top}: the AI drives to the foot, then up
var center := Vector3.ZERO
var wander_half := 100.0

var _rng := RandomNumberGenerator.new()
var _m := {} # materials
var _tower_legs := 4
var _tower_upper: Node3D
var _letters_left := 0


func build() -> void:
	_rng.seed = 1996
	_materials()
	_environment()
	_terrain()
	_roads()
	_cracks()
	_outer_wall()
	_storefronts()
	_tunnels()
	_overpass_and_cage()
	_fire_pit()
	_burnt_building(Vector3(-30, 0, -45))
	_power_tower()
	_hot_dog_stands()
	_palms()
	_hills_and_sign()
	_skyline()
	_blimp()
	_points()


## Ground height of the play area: flat, except the fire-pit crater and the three road humps.
static func height_at(x: float, z: float) -> float:
	var h := 0.0
	var r := Vector2(x, z).length()
	if r < 30.0:
		var t := clampf(r / 22.0, 0.0, 1.0)
		h -= 3.0 * (1.0 - smoothstep(0.15, 1.0, t))
		h += 0.7 * exp(-pow((r - 23.0) / 2.2, 2.0)) # rubble lip
	var dz := absf(z - ROAD_H)
	if dz < 12.0 and absf(x) < 26.0:
		var across := 1.0 - smoothstep(9.0, 12.0, dz)
		for hx: float in [-20.0, 0.0, 20.0]:
			var u := (x - hx) / 5.0
			if absf(u) < 1.0:
				h += 1.3 * pow(cos(u * PI * 0.5), 2.0) * across
	return h


static func ground(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, height_at(x, z) + lift, z)


## Height of the visible ground mesh (2 m triangles) at x, z. Decals use this so they sit exactly
## on what you see, also inside the curved crater.
static func mesh_height(x: float, z: float) -> float:
	var gx := floorf(x / 2.0) * 2.0
	var gz := floorf(z / 2.0) * 2.0
	var u := (x - gx) / 2.0
	var v := (z - gz) / 2.0
	var h00 := height_at(gx, gz)
	var h10 := height_at(gx + 2.0, gz)
	var h01 := height_at(gx, gz + 2.0)
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	var h11 := height_at(gx + 2.0, gz + 2.0)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


static func on_mesh(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, mesh_height(x, z) + lift, z)


# ---------------------------------------------------------------- look

func _materials() -> void:
	_m.ground = _two_sided(MeshKit.grime(Color(0.5, 0.49, 0.46), Color(0.34, 0.33, 0.31), 0.035, 0.95, 0.0, 0.08))
	_m.scrub = MeshKit.grime(Color(0.46, 0.42, 0.3), Color(0.3, 0.32, 0.2), 0.02, 1.0, 0.0, 0.01)
	_m.asphalt = _two_sided(MeshKit.grime(Color(0.24, 0.24, 0.25), Color(0.14, 0.14, 0.15), 0.08, 0.9, 0.0, 0.12))
	_m.yellow_line = _two_sided(MeshKit.mat(Color(0.95, 0.75, 0.12), 0.7))
	_m.white_line = _two_sided(MeshKit.mat(Color(0.92, 0.92, 0.88), 0.7))
	_m.crack = _two_sided(MeshKit.mat(Color(0.1, 0.09, 0.08), 1.0))
	_m.concrete = MeshKit.grime(Color(0.6, 0.59, 0.56), Color(0.44, 0.43, 0.41), 0.05, 0.9, 0.0, 0.2)
	_m.concrete_dark = MeshKit.grime(Color(0.55, 0.54, 0.52), Color(0.38, 0.37, 0.36), 0.05, 0.9, 0.0, 0.2)
	_m.wall = _panel_material(Color(0.66, 0.64, 0.6), Color(0.38, 0.37, 0.35), 4.0)
	_m.metal = MeshKit.mat(Color(0.5, 0.51, 0.53), 0.4, 0.8)
	_m.steel = MeshKit.mat(Color(0.36, 0.37, 0.39), 0.5, 0.7)
	_m.rust = MeshKit.grime(Color(0.5, 0.26, 0.1), Color(0.25, 0.12, 0.05), 0.15, 0.9, 0.3, 0.4)
	_m.char = MeshKit.grime(Color(0.16, 0.14, 0.12), Color(0.05, 0.05, 0.05), 0.12, 1.0, 0.0, 0.3)
	_m.brick = MeshKit.grime(Color(0.44, 0.24, 0.17), Color(0.14, 0.1, 0.08), 0.09, 0.95, 0.0, 0.3)
	_m.scorched = _two_sided(MeshKit.grime(Color(0.2, 0.19, 0.18), Color(0.08, 0.075, 0.07), 0.06, 1.0, 0.0, 0.15))
	_m.hill = MeshKit.grime(Color(0.55, 0.47, 0.3), Color(0.3, 0.34, 0.18), 0.02, 1.0, 0.0, 0.015)
	_m.hill_far = MeshKit.grime(Color(0.46, 0.43, 0.34), Color(0.32, 0.34, 0.24), 0.02, 1.0, 0.0, 0.006)
	_m.white = MeshKit.mat(Color(0.95, 0.95, 0.92), 0.6)
	_m.red = MeshKit.mat(Color(0.8, 0.1, 0.08), 0.6)
	_m.dark = MeshKit.mat(Color(0.06, 0.06, 0.07), 0.8)
	_m.window = MeshKit.mat(Color(0.15, 0.2, 0.28), 0.1, 0.5)
	_m.glass = MeshKit.mat(Color(0.55, 0.8, 0.95, 0.35), 0.05, 0.3)
	_m.glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m.chainlink = _chainlink_material()
	_m.city = _window_material()


func _two_sided(m: StandardMaterial3D) -> StandardMaterial3D:
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Concrete panels: noise plus seams every `panel` meters (world-aligned).
func _panel_material(base: Color, seam: Color, panel: float) -> StandardMaterial3D:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.04
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.darkened(0.18 * (1.0 - n))
			if x < 3 or y < 2:
				c = seam
			elif y > size - 18:
				c = c.darkened(0.25 * float(y - size + 18) / 18.0) # rain stains near the bottom
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / panel
	return m


func _chainlink_material() -> StandardMaterial3D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var on := (x + y) % 16 < 2 or (x - y + 64) % 16 < 2
			img.set_pixel(x, y, Color(0.62, 0.64, 0.66, 1.0) if on else Color(0, 0, 0, 0))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.6
	m.roughness = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	return m


## Office tower windows: a grid, a few of them lit.
func _window_material() -> StandardMaterial3D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for cy in 4:
		for cx in 4:
			var lit := rng.randf() < 0.18
			var win := Color(0.85, 0.75, 0.5) if lit else Color(0.2, 0.27, 0.36).lightened(rng.randf() * 0.15)
			for y in 16:
				for x in 16:
					var frame := x < 3 or x > 13 or y < 4 or y > 13
					img.set_pixel(cx * 16 + x, cy * 16 + y, Color(0.58, 0.58, 0.6) if frame else win)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.5
	m.metallic = 0.2
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / 16.0
	return m


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.48, 0.78)
	sky_mat.sky_horizon_color = Color(0.88, 0.76, 0.6)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.82, 0.72, 0.58)
	sky_mat.ground_bottom_color = Color(0.45, 0.4, 0.33)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.74)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.72, 0.68) # thin LA smog
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.1
	if RenderingServer.get_rendering_device() != null: # Forward+ / Mobile only
		env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = Vector3(-38, -45, 0) # low sun in the south-west
	add_child(sun)


# ---------------------------------------------------------------- ground

func _terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var n := MAP_HALF * 2 + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			data[j * n + i] = height_at(i - MAP_HALF, j - MAP_HALF)
	hm.map_data = data
	var shape := CollisionShape3D.new()
	shape.shape = hm
	body.add_child(shape)

	# Visual chunks on a 2 m grid (sampled from the same heights), so each mesh is only lit by
	# nearby lights. Grid points: every second heightmap sample.
	var step := 2
	var g := MAP_HALF # grid points per side minus one (256 m / 2 m)
	var gn := g + 1
	var gh := PackedFloat32Array()
	var gnorm := PackedVector3Array()
	gh.resize(gn * gn)
	gnorm.resize(gn * gn)
	for gj in gn:
		for gi in gn:
			var i := gi * step
			var j := gj * step
			gh[gj * gn + gi] = data[j * n + i]
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, n - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, n - 1)
			gnorm[gj * gn + gi] = Vector3(data[j * n + il] - data[j * n + ir], 2.0, data[jd * n + i] - data[ju * n + i]).normalized()
	var cells := 16 # per chunk side (32 m)
	for cx in g / cells:
		for cz in g / cells:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for a in cells:
				for b in cells:
					var gi := cx * cells + a
					var gj := cz * cells + b
					for c: Vector2i in [Vector2i(gi, gj), Vector2i(gi + 1, gj), Vector2i(gi, gj + 1),
							Vector2i(gi + 1, gj), Vector2i(gi + 1, gj + 1), Vector2i(gi, gj + 1)]:
						var k: int = c.y * gn + c.x
						var x: float = c.x * step - MAP_HALF
						var z: float = c.y * step - MAP_HALF
						st.set_normal(gnorm[k])
						st.set_uv(Vector2(x, z) * 0.1)
						st.add_vertex(Vector3(x, gh[k], z))
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = _m.ground
			body.add_child(mi)
	# Flat ground beyond the walls: a frame around the map (a single big plane would cut
	# through the crater).
	var far := 800.0
	var m := float(MAP_HALF)
	for r: Rect2 in [Rect2(-far, -far, far * 2.0, far - m), Rect2(-far, m, far * 2.0, far - m),
			Rect2(-far, -m, far - m, m * 2.0), Rect2(m, -m, far - m, m * 2.0)]:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = r.size
		mi.mesh = plane
		mi.material_override = _m.scrub
		mi.position = Vector3(r.get_center().x, -0.02, r.get_center().y)
		add_child(mi)


func _normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 1.0, z) - height_at(x + 1.0, z), 2.0, height_at(x, z - 1.0) - height_at(x, z + 1.0)).normalized()


## A strip laid on the ground along a polyline (roads, painted lines, cracks).
func _drape(points: PackedVector3Array, width: float, lift: float, mat: Material, closed := false, offset := 0.0) -> void:
	var count := points.size()
	if count < 2:
		return
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in count:
		var prev := points[i - 1] if (i > 0 or closed) else points[i]
		var next := points[(i + 1) % count] if (i < count - 1 or closed) else points[i]
		var tangent := next - prev
		tangent.y = 0.0
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var c := points[i] + side * offset
		var l := c - side * width * 0.5
		var r := c + side * width * 0.5
		left.append(on_mesh(l.x, l.z, lift))
		right.append(on_mesh(r.x, r.z, lift))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := count if closed else count - 1
	for i in segs:
		var j := (i + 1) % count
		for p: Vector3 in [left[i], right[i], left[j], right[i], right[j], left[j]]:
			st.set_normal(_normal_at(p.x, p.z))
			st.set_uv(Vector2(p.x, p.z) * 0.1)
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Ring road centerline: a rounded rectangle, one point every `step` meters.
func _ring_points(h: float, r: float, step: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var straight := 2.0 * (h - r)
	var corners := [
		[Vector3(-h + r, 0, -h), Vector3(1, 0, 0), Vector3(h - r, 0, -h + r), -PI * 0.5],
		[Vector3(h, 0, -h + r), Vector3(0, 0, 1), Vector3(h - r, 0, h - r), 0.0],
		[Vector3(h - r, 0, h), Vector3(-1, 0, 0), Vector3(-h + r, 0, h - r), PI * 0.5],
		[Vector3(-h, 0, h - r), Vector3(0, 0, -1), Vector3(-h + r, 0, -h + r), PI],
	]
	for c in corners:
		var start: Vector3 = c[0]
		var dir: Vector3 = c[1]
		var n_straight := int(straight / step)
		for i in n_straight:
			pts.append(start + dir * i * step)
		var arc_center: Vector3 = c[2]
		var a0: float = c[3]
		var n_arc := int(r * PI * 0.5 / step)
		for i in n_arc:
			var a := a0 + PI * 0.5 * float(i) / n_arc
			pts.append(arc_center + Vector3(cos(a), 0, sin(a)) * r)
	return pts


func _roads() -> void:
	var ring := _ring_points(ROAD_H, ROAD_R, 2.0)
	_drape(ring, ROAD_W, 0.04, _m.asphalt, true)
	for off: float in [-0.3, 0.3]:
		_drape(ring, 0.18, 0.07, _m.yellow_line, true, off)
	for off: float in [-ROAD_W * 0.5 + 0.7, ROAD_W * 0.5 - 0.7]:
		_drape(ring, 0.25, 0.07, _m.white_line, true, off)
	# A cross street from the south road up to the crater, and a spur to the overpass.
	var south := PackedVector3Array()
	for i in 22:
		south.append(Vector3(0, 0, 79 - i * 2.0))
	_drape(south, 12.0, 0.045, _m.asphalt)
	var spur := PackedVector3Array()
	for i in 8:
		spur.append(Vector3(79 - i * 2.0, 0, 8))
	for i in 9: # quarter turn up to the overpass
		var a := PI * 0.5 + PI * 0.5 * float(i) / 8.0
		spur.append(Vector3(63, 0, -4) + Vector3(-cos(a + PI), 0, sin(a)) * 12.0)
	spur.append(Vector3(51, 0, -6))
	_drape(spur, 10.0, 0.045, _m.asphalt)


## Earthquake cracks: dark jagged lines across the ground and the roads.
func _cracks() -> void:
	for i in 16:
		var p := Vector3(_rng.randf_range(-110, 110), 0, _rng.randf_range(-110, 110))
		if p.length() < 26.0:
			continue
		var a := _rng.randf_range(0, TAU)
		var pts := PackedVector3Array()
		for k in _rng.randi_range(8, 18):
			pts.append(p)
			a += _rng.randf_range(-0.7, 0.7)
			p += Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.5, 3.0)
		_drape(pts, _rng.randf_range(0.35, 0.7), 0.09, _m.crack)


# ---------------------------------------------------------------- walls and buildings

func _outer_wall() -> void:
	var c := 20.0
	var h := 8.0
	var corners := [
		Vector3(-HALF + c, 0, -HALF), Vector3(HALF - c, 0, -HALF), Vector3(HALF, 0, -HALF + c), Vector3(HALF, 0, HALF - c),
		Vector3(HALF - c, 0, HALF), Vector3(-HALF + c, 0, HALF), Vector3(-HALF, 0, HALF - c), Vector3(-HALF, 0, -HALF + c),
	]
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var out := ((a + b) * 0.5).normalized()
		var dir := (b - a).normalized()
		var yaw := rad_to_deg(atan2(-dir.z, dir.x))
		var mid := (a + b) * 0.5 + out * 1.0
		MeshKit.solid_box(self, Vector3(a.distance_to(b) + 2.2, h, 2.0), mid + Vector3.UP * h * 0.5, _m.wall, Vector3(0, yaw, 0))
		# Cap and a painted hazard stripe along the bottom.
		MeshKit.box(self, Vector3(a.distance_to(b) + 2.4, 0.4, 2.6), mid + Vector3.UP * (h + 0.2), _m.concrete_dark, Vector3(0, yaw, 0))
		MeshKit.box(self, Vector3(a.distance_to(b) + 2.2, 0.7, 2.06), mid + Vector3.UP * 0.35, MeshKit.mat(Color(0.85, 0.66, 0.1), 0.8), Vector3(0, yaw, 0))
	# Graffiti, Calypso's tournament everywhere.
	var tags := [
		["QUAKE ZONE", Vector3(-60, 3.2, HALF - 0.05), 0.0, Color(0.9, 0.2, 0.25)],
		["CALYPSO LIES", Vector3(HALF - 0.05, 3.0, -70), 90.0, Color(0.2, 0.55, 0.95)],
		["SWEET TOOTH WAS HERE", Vector3(-HALF + 0.05, 3.0, 70), -90.0, Color(0.95, 0.5, 0.75)],
		["NO WISH IS FREE", Vector3(30, 3.4, -HALF + 0.05), 180.0, Color(0.95, 0.85, 0.2)],
	]
	for t in tags:
		var l := Label3D.new()
		l.text = t[0]
		l.font_size = 260
		l.pixel_size = 0.012
		l.outline_size = 24
		l.modulate = t[3]
		l.outline_modulate = Color(0.05, 0.05, 0.05)
		l.position = t[1]
		l.rotation_degrees.y = t[2] + 180.0
		add_child(l)


## Shops built against the inside of the outer wall (never out in the driving space).
func _storefronts() -> void:
	_storefront(Vector3(-75, 0, HALF), Vector3(0, 0, -1), 26.0, 11.0, Color(0.85, 0.72, 0.5), "MOTEL", Color(1.0, 0.3, 0.35))
	_storefront(Vector3(-30, 0, HALF), Vector3(0, 0, -1), 22.0, 9.0, Color(0.6, 0.75, 0.7), "LIQUOR", Color(0.3, 1.0, 0.5))
	var donuts := _storefront(Vector3(45, 0, HALF), Vector3(0, 0, -1), 20.0, 8.0, Color(0.92, 0.85, 0.7), "DONUTS", Color(1.0, 0.6, 0.2))
	# Giant donut on the roof (Randy's).
	var dough := MeshKit.mat(Color(0.75, 0.5, 0.25), 0.8)
	MeshKit.torus(donuts, 3.0, 6.5, Vector3(0, 16.0, -1.0), dough, Vector3(90, 0, 0))
	MeshKit.cylinder(donuts, 0.4, 6.0, Vector3(-3, 10.5, -1), _m.steel)
	MeshKit.cylinder(donuts, 0.4, 6.0, Vector3(3, 10.5, -1), _m.steel)
	_storefront(Vector3(HALF, 0, 30), Vector3(-1, 0, 0), 30.0, 13.0, Color(0.55, 0.3, 0.35), "THEATER", Color(1.0, 0.85, 0.3))
	_storefront(Vector3(HALF, 0, 85), Vector3(-1, 0, 0), 20.0, 9.0, Color(0.7, 0.66, 0.6), "PAWN", Color(0.4, 0.8, 1.0))
	_storefront(Vector3(-HALF, 0, 60), Vector3(1, 0, 0), 22.0, 9.0, Color(0.8, 0.6, 0.35), "TACOS", Color(1.0, 0.5, 0.1))
	_storefront(Vector3(-HALF, 0, -75), Vector3(1, 0, 0), 26.0, 10.0, Color(0.5, 0.55, 0.62), "AUTO PARTS", Color(1.0, 0.25, 0.2))


func _storefront(on_wall: Vector3, inward: Vector3, width: float, height: float, color: Color, sign: String, sign_color: Color) -> Node3D:
	var node := Node3D.new()
	node.position = on_wall
	node.basis = Basis.looking_at(inward, Vector3.UP)
	add_child(node)
	var paint := MeshKit.grime(color, color.darkened(0.35), 0.08, 0.9, 0.0, 0.25)
	MeshKit.solid_box(node, Vector3(width, height, 2.0), Vector3(0, height * 0.5, -1.0), paint)
	# Windows, door, awning.
	var n_win := int(width / 5.0)
	for i in n_win:
		var x := -width * 0.5 + 2.5 + i * 5.0
		if absf(x) < 2.0:
			continue
		MeshKit.box(node, Vector3(3.2, 2.6, 0.1), Vector3(x, 2.2, -2.02), _m.window)
		if height > 9.0:
			MeshKit.box(node, Vector3(2.4, 1.8, 0.1), Vector3(x, 6.6, -2.02), _m.window)
	MeshKit.box(node, Vector3(2.4, 3.2, 0.1), Vector3(0, 1.6, -2.02), _m.dark)
	MeshKit.box(node, Vector3(width - 1.0, 0.3, 2.2), Vector3(0, 4.0, -3.0), MeshKit.mat(sign_color.darkened(0.3), 0.7), Vector3(-12, 0, 0))
	var l := Label3D.new()
	l.text = sign
	l.font_size = 300
	l.pixel_size = 0.012
	l.outline_size = 30
	l.modulate = sign_color * 1.4
	l.outline_modulate = Color(0.08, 0.06, 0.05)
	l.position = Vector3(0, height - 1.8, -2.1)
	l.rotation_degrees.y = 180.0
	node.add_child(l)
	return node


func _tunnels() -> void:
	var cx := (TUNNEL_X0 + TUNNEL_X1) * 0.5
	var length := TUNNEL_Z * 2.0
	var width := TUNNEL_X1 - TUNNEL_X0
	# Roof deck (a freeway): drive up the ramps for weapons and the teleporter.
	MeshKit.solid_box(self, Vector3(width, 1.0, length), Vector3(cx, ROOF_Y - 0.5, 0), _m.concrete)
	for x: float in [cx - 9.0, cx + 9.0]:
		for i in 8:
			MeshKit.box(self, Vector3(0.25, 0.04, 4.0), Vector3(x, ROOF_Y + 0.02, -28 + i * 8.0), _m.white_line)
	for x: float in [TUNNEL_X0 + 0.6, TUNNEL_X1 - 0.6]:
		MeshKit.box(self, Vector3(0.6, 0.05, length), Vector3(x, ROOF_Y + 0.03, 0), _m.yellow_line)
	# Freeway sign on the roof's far edge.
	var sign_post := Vector3(TUNNEL_X0 + 1.0, ROOF_Y, 0)
	for dz: float in [-4.5, 4.5]:
		MeshKit.cylinder(self, 0.25, 6.0, sign_post + Vector3(0, 3.0, dz), _m.steel)
	MeshKit.box(self, Vector3(0.3, 3.2, 11.0), sign_post + Vector3(0, 6.6, 0), MeshKit.mat(Color(0.1, 0.45, 0.25), 0.6))
	var fwy := Label3D.new()
	fwy.text = "101  HOLLYWOOD FWY"
	fwy.font_size = 140
	fwy.pixel_size = 0.012
	fwy.modulate = Color(1.4, 1.4, 1.4)
	fwy.position = sign_post + Vector3(0.2, 6.6, 0)
	fwy.rotation_degrees.y = 90.0
	add_child(fwy)

	# Walls: pillars every 8 m with glass between. The ramps cover two bays on each side.
	var ramp_bays := [1, 2, 5, 6]
	for wall_x: float in [TUNNEL_X0 + 0.5, cx, TUNNEL_X1 - 0.5]:
		var thick := 2.0 if wall_x == cx else 1.0
		for i in 9:
			var z := -TUNNEL_Z + i * 8.0
			MeshKit.solid_box(self, Vector3(thick + 0.4, ROOF_Y - 1.0, 1.4), Vector3(wall_x, (ROOF_Y - 1.0) * 0.5, z), _m.concrete_dark)
		for i in 8:
			var zc := -TUNNEL_Z + 4.0 + i * 8.0
			if wall_x == TUNNEL_X1 - 0.5 and i in ramp_bays:
				MeshKit.solid_box(self, Vector3(thick, ROOF_Y - 1.0, 6.6), Vector3(wall_x, (ROOF_Y - 1.0) * 0.5, zc), _m.concrete_dark)
			else:
				_glass_panel(Vector3(wall_x, 0, zc), thick)
	# Divider noses: wedges that deflect cars into one tube or the other.
	for s: float in [-1.0, 1.0]:
		var nose := MeshKit.prism(self, Vector3(2.4, 5.0, ROOF_Y - 1.0), Vector3(cx, (ROOF_Y - 1.0) * 0.5, s * (TUNNEL_Z + 2.5)), _m.concrete_dark, Vector3(90.0 * s, 0, 0))
		MeshKit.solid_mesh(self, nose)
		MeshKit.box(self, Vector3(2.6, 0.6, 0.1), Vector3(cx, 2.0, s * (TUNNEL_Z + 0.1)), MeshKit.mat(Color(0.95, 0.75, 0.1), 0.7))
	# Lights inside the tubes.
	for x: float in [(TUNNEL_X0 + cx) * 0.5, (cx + TUNNEL_X1) * 0.5]:
		for z: float in [-20.0, 0.0, 20.0]:
			MeshKit.box(self, Vector3(1.0, 0.1, 6.0), Vector3(x, ROOF_Y - 1.06, z), MeshKit.emissive(Color(1.0, 0.95, 0.8), 3.0))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.92, 0.78)
			l.light_energy = 1.6
			l.omni_range = 15.0
			l.position = Vector3(x, ROOF_Y - 2.0, z)
			add_child(l)
	# Ramps onto the roof from the infield.
	for zc: float in [-16.0, 16.0]:
		var ramp := MeshKit.prism(self, Vector3(30, ROOF_Y, 16), Vector3(TUNNEL_X1 + 15.0, ROOF_Y * 0.5, zc), _m.concrete)
		MeshKit.solid_mesh(self, ramp)
		for k in 4:
			var t := (k + 0.5) / 4.0
			var x := TUNNEL_X1 + 30.0 * (1.0 - t)
			MeshKit.box(self, Vector3(1.2, 0.05, 10.0), Vector3(x, ROOF_Y * t + 0.05, zc), _m.yellow_line, Vector3(0, 0, -rad_to_deg(atan(ROOF_Y / 30.0))))
		ramps.append({"foot": Vector3(TUNNEL_X1 + 36.0, 0, zc), "top": Vector3(TUNNEL_X1 - 8.0, ROOF_Y, zc)})
	# Teleporter on the roof: straight into the cage with the super health.
	var tp := Teleporter.new()
	add_child(tp)
	tp.global_position = Vector3(TUNNEL_X0 + 8.0, ROOF_Y, -TUNNEL_Z + 8.0)
	tp.destination = Transform3D(Basis(Vector3.UP, PI), DECK_CENTER + Vector3(0, DECK_Y + 0.1, -9))


func _glass_panel(at: Vector3, thick: float) -> void:
	var b := Breakable.new()
	b.health = 8.0
	b.debris_color = Color(0.7, 0.9, 1.0)
	b.position = at
	add_child(b)
	b.add_box_shape(Vector3(thick * 0.5, ROOF_Y - 1.4, 6.6), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0))
	MeshKit.box(b.visual, Vector3(thick * 0.3, ROOF_Y - 1.4, 6.6), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0), _m.glass)
	MeshKit.box(b.visual, Vector3(thick * 0.5, 0.2, 6.6), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0), _m.steel)


func _overpass_and_cage() -> void:
	var c := DECK_CENTER
	MeshKit.solid_box(self, Vector3(30, DECK_Y, 30), c + Vector3(0, DECK_Y * 0.5, 0), _m.wall)
	MeshKit.box(self, Vector3(30.2, 0.1, 30.2), c + Vector3(0, DECK_Y + 0.02, 0), _m.concrete_dark)
	# Overpass ramp from the south, with low concrete rails.
	var ramp := MeshKit.prism(self, Vector3(30, DECK_Y, 12), c + Vector3(0, DECK_Y * 0.5, 30), _m.concrete_dark, Vector3(0, -90, 0))
	MeshKit.solid_mesh(self, ramp)
	var slope := rad_to_deg(atan(DECK_Y / 30.0))
	for side: float in [-1.0, 1.0]:
		MeshKit.solid_box(self, Vector3(0.6, 1.0, 30.8), c + Vector3(side * 6.3, DECK_Y * 0.5 + 0.5, 30), _m.concrete, Vector3(slope, 0, 0))
	ramps.append({"foot": c + Vector3(0, 0, 52), "top": c + Vector3(0, DECK_Y, 6)})
	# The cage: chain-link all round the deck, gate where the overpass arrives.
	var fence_h := 4.5
	var y := DECK_Y + fence_h * 0.5
	var runs := [
		[Vector3(-15, 0, -15), Vector3(15, 0, -15)],
		[Vector3(-15, 0, -15), Vector3(-15, 0, 15)],
		[Vector3(15, 0, -15), Vector3(15, 0, 15)],
		[Vector3(-15, 0, 15), Vector3(-6.5, 0, 15)],
		[Vector3(6.5, 0, 15), Vector3(15, 0, 15)],
	]
	for run in runs:
		var a: Vector3 = c + run[0]
		var b: Vector3 = c + run[1]
		var mid := (a + b) * 0.5
		var along_x := absf(b.x - a.x) > 0.1
		var size := Vector3(a.distance_to(b), fence_h, 0.12) if along_x else Vector3(0.12, fence_h, a.distance_to(b))
		MeshKit.solid_box(self, size, mid + Vector3.UP * y, _m.chainlink)
		var posts := int(a.distance_to(b) / 5.0) + 1
		for k in posts:
			var p := a.lerp(b, float(k) / maxf(1.0, posts - 1))
			MeshKit.cylinder(self, 0.12, fence_h + 0.4, p + Vector3.UP * (DECK_Y + (fence_h + 0.4) * 0.5), _m.steel, Vector3.ZERO, 6)
		MeshKit.box(self, size + Vector3(0.1, -fence_h + 0.12, 0.1), mid + Vector3.UP * (DECK_Y + fence_h), _m.steel)
	var warn := Label3D.new()
	warn.text = "CALYPSO PROPERTY\nKEEP OUT"
	warn.font_size = 120
	warn.pixel_size = 0.012
	warn.modulate = Color(1.2, 0.2, 0.15)
	warn.outline_size = 16
	warn.position = c + Vector3(-11, DECK_Y + 3.0, 15.15)
	add_child(warn)
	mega_points.append(c + Vector3(0, DECK_Y, -2))
	weapon_points.append(c + Vector3(-9, DECK_Y, -9))
	weapon_points.append(c + Vector3(9, DECK_Y, -9))


## Ground decal that follows the terrain: a disc of rings and spokes.
func _drape_disc(c: Vector3, radius: float, lift: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := int(radius / 2.0)
	var spokes := 40
	for r in rings:
		var r0 := radius * float(r) / rings
		var r1 := radius * float(r + 1) / rings
		for k in spokes:
			var a0 := TAU * k / spokes
			var a1 := TAU * (k + 1) / spokes
			var quad := [
				Vector2(cos(a0) * r0, sin(a0) * r0), Vector2(cos(a0) * r1, sin(a0) * r1),
				Vector2(cos(a1) * r0, sin(a1) * r0), Vector2(cos(a1) * r1, sin(a1) * r1),
			]
			for i: int in [0, 1, 2, 1, 3, 2]:
				var q: Vector2 = quad[i]
				var p := on_mesh(c.x + q.x, c.z + q.y, lift)
				st.set_normal(_normal_at(p.x, p.z))
				st.set_uv(Vector2(p.x, p.z) * 0.1)
				st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _fire_pit() -> void:
	var bottom := ground(0, 0)
	_drape_disc(Vector3.ZERO, 24.0, 0.12, _m.scorched)
	for k in 9: # cracks running out of the crater
		var a := k * TAU / 9.0 + _rng.randf_range(-0.2, 0.2)
		var pts := PackedVector3Array()
		var p := Vector3(cos(a), 0, sin(a)) * 6.0
		for i in 14:
			pts.append(p)
			a += _rng.randf_range(-0.3, 0.3)
			p += Vector3(cos(a), 0, sin(a)) * 2.4
		_drape(pts, 0.6, 0.1, _m.crack)
	FirePool.spawn(self, bottom, 4.5, 0.0, 4.0, null)
	# Broken gas main: pipe ends sticking out, a roaring flame and a strong light.
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		var p := bottom + Vector3(cos(a) * 2.6, 0.4, sin(a) * 2.6)
		var pipe := MeshKit.cylinder(self, 0.55, 3.4, p, _m.rust, Vector3(0, 0, 0), 10)
		pipe.basis = Basis(Quaternion(Vector3.UP, Vector3(-cos(a) * 0.5, 1.0, -sin(a) * 0.5).normalized()))
	var column := FxKit.fire(4.5, 90)
	column.position = bottom + Vector3.UP * 0.8
	column.emission_sphere_radius = 1.6
	column.initial_velocity_max = 7.0
	column.lifetime = 1.4
	add_child(column)
	column.emitting = true
	for k in 6: # flames licking out of the cracks around the gas main
		var a := k * TAU / 6.0
		var f := FxKit.fire(2.2, 40)
		f.position = ground(cos(a) * 3.5, sin(a) * 3.5, 0.3)
		f.emission_sphere_radius = 1.0
		add_child(f)
		f.emitting = true
	var smoke := FxKit.smoke(3.0, 30)
	smoke.position = bottom + Vector3.UP * 7.0
	add_child(smoke)
	smoke.emitting = true
	var light := FlickerLight.new()
	light.light_color = Color(1.0, 0.36, 0.1)
	light.base_energy = 1.6
	light.omni_range = 14.0
	light.position = bottom + Vector3.UP * 4.0
	add_child(light)
	# Broken slabs lying on the crater slopes (flat, no collision).
	for k in 10:
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(8.0, 18.0)
		var p := ground(cos(a) * r, sin(a) * r, 0.1)
		MeshKit.box(self, Vector3(_rng.randf_range(2, 4), 0.3, _rng.randf_range(1.5, 3)), p, _m.concrete_dark, Vector3(_rng.randf_range(-6, 6), _rng.randf_range(0, 180), _rng.randf_range(-6, 6)))


## Burnt-out building you can drive through (north and south doors, 10 m wide).
func _burnt_building(c: Vector3) -> void:
	var w := 22.0
	var d := 16.0
	var h := 13.0
	var door := 10.0
	var side := (w - door) * 0.5
	MeshKit.solid_box(self, Vector3(1.0, h, d), c + Vector3(-w * 0.5 + 0.5, h * 0.5, 0), _m.brick)
	MeshKit.solid_box(self, Vector3(1.0, h * 0.8, d), c + Vector3(w * 0.5 - 0.5, h * 0.4, 0), _m.brick)
	for s: float in [-1.0, 1.0]:
		var z := c.z + s * (d * 0.5 - 0.5)
		MeshKit.solid_box(self, Vector3(side, h, 1.0), Vector3(c.x - w * 0.5 + side * 0.5, h * 0.5, z), _m.brick)
		MeshKit.solid_box(self, Vector3(side, h * 0.85, 1.0), Vector3(c.x + w * 0.5 - side * 0.5, h * 0.425, z), _m.brick)
		MeshKit.solid_box(self, Vector3(door, h - 6.0, 1.0), Vector3(c.x, 6.0 + (h - 6.0) * 0.5, z), _m.brick)
		MeshKit.box(self, Vector3(door + 0.4, 0.6, 1.2), Vector3(c.x, 6.0, z), _m.char)
		# Burnt windows, scorch marks above them.
		for k in 3:
			var x := c.x - w * 0.5 + 2.0 + k * 3.2 if k < 2 else c.x + w * 0.5 - 3.0
			MeshKit.box(self, Vector3(1.8, 2.2, 1.1), Vector3(x, 9.0, z), _m.dark)
			MeshKit.box(self, Vector3(2.0, 1.5, 1.12), Vector3(x, 10.8, z), _m.char)
	MeshKit.solid_box(self, Vector3(w, 0.6, d), c + Vector3(0, 6.3, 0), _m.char) # first floor
	MeshKit.box(self, Vector3(w * 0.6, 0.5, d * 0.7), c + Vector3(-3, h - 0.3, -1), _m.char, Vector3(0, 0, -8)) # sagging roof
	var smoke := FxKit.smoke(2.5, 24)
	smoke.position = c + Vector3(2, h + 1.0, 0)
	add_child(smoke)
	smoke.emitting = true
	var embers := FxKit.fire(1.2, 24)
	embers.position = c + Vector3(-6, 7.0, 0)
	add_child(embers)
	embers.emitting = true
	var glow := FlickerLight.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.base_energy = 2.0
	glow.omni_range = 12.0
	glow.position = c + Vector3(-5, 4.0, 0)
	add_child(glow)


## High-voltage tower: shoot (or ram) its four legs and it falls, dropping three weapons.
func _power_tower() -> void:
	var at := TOWER_AT
	_tower_upper = Node3D.new()
	_tower_upper.position = at
	add_child(_tower_upper)
	var top := 30.0
	var corners := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]
	for k in corners:
		var s: Vector3 = k
		var leg := Breakable.new()
		leg.health = 40.0
		leg.smash_on_contact = false
		leg.ram_damage_mult = 1.0
		leg.debris_color = Color(0.45, 0.46, 0.48)
		leg.position = at + s * 5.0
		add_child(leg)
		leg.add_box_shape(Vector3(1.4, 9.0, 1.4), Vector3(-s.x * 0.7, 4.5, -s.z * 0.7))
		MeshKit.box(leg.visual, Vector3(1.8, 0.7, 1.8), Vector3(0, 0.35, 0), _m.concrete)
		_member(leg.visual, Vector3(0, 0.6, 0), Vector3(-s.x * 1.4, 9.0, -s.z * 1.4), 0.45, _m.steel)
		leg.broken.connect(_on_tower_leg_broken)
		# Upper body (falls when the legs are gone).
		_member(_tower_upper, s * 3.6 + Vector3.UP * 9.0, s * 1.2 + Vector3.UP * top, 0.4, _m.steel)
	for level in 5:
		var y0 := 9.0 + level * 4.2
		var y1 := y0 + 4.2
		var r0 := lerpf(3.6, 1.2, (y0 - 9.0) / (top - 9.0))
		var r1 := lerpf(3.6, 1.2, (y1 - 9.0) / (top - 9.0))
		for f in 4:
			var a := Vector3(-1, 0, -1).rotated(Vector3.UP, f * PI * 0.5)
			var b := Vector3(-1, 0, -1).rotated(Vector3.UP, (f + 1) * PI * 0.5)
			_member(_tower_upper, a * r0 + Vector3.UP * y0, b * r1 + Vector3.UP * y1, 0.15, _m.steel)
			_member(_tower_upper, b * r0 + Vector3.UP * y0, a * r1 + Vector3.UP * y1, 0.15, _m.steel)
	for y: float in [21.0, 26.0]:
		var arm := 8.0 if y < 25.0 else 6.0
		_member(_tower_upper, Vector3(-arm, y, 0), Vector3(arm, y, 0), 0.4, _m.steel)
		for x: float in [-arm + 0.5, arm - 0.5]:
			for k in 3:
				MeshKit.cylinder(_tower_upper, 0.22, 0.25, Vector3(x, y - 0.6 - k * 0.3, 0), MeshKit.mat(Color(0.3, 0.45, 0.6), 0.2, 0.3))
	# Power lines running off over the wall.
	var line_mat := MeshKit.mat(Color(0.1, 0.1, 0.1), 0.6)
	for x: float in [-7.5, 7.5, -5.5, 5.5]:
		var y := 20.0 if absf(x) > 6.0 else 25.0
		var line := ZigLine.new()
		line.material = line_mat
		line.thickness = 0.08
		add_child(line)
		line.draw(at + Vector3(x, y, 0), Vector3(HALF + 60.0, 22.0, HALF + 40.0 + x), 0.0, 6.0)
	var sign := Label3D.new()
	sign.text = "DANGER\nHIGH VOLTAGE"
	sign.font_size = 90
	sign.pixel_size = 0.012
	sign.modulate = Color(1.3, 1.1, 0.2)
	sign.outline_size = 14
	sign.position = at + Vector3(0, 6.0, 4.0)
	add_child(sign)


func _member(parent: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> MeshInstance3D:
	if a.distance_to(b) < 0.01:
		return null
	var mi := MeshKit.box(parent, Vector3(t, t, a.distance_to(b)), (a + b) * 0.5, mat)
	var dir := (b - a).normalized()
	mi.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	return mi


func _on_tower_leg_broken(leg: Breakable, by: Vehicle) -> void:
	FxKit.explosion(self, leg.global_position + Vector3.UP * 3.0, 1.0, Color(0.5, 0.75, 1.0))
	_tower_legs -= 1
	if _tower_legs > 0:
		return
	# Down it comes.
	var away := Vector3(1, 0, 0.3) if not is_instance_valid(by) else (TOWER_AT - by.global_position)
	away.y = 0.0
	away = away.normalized()
	var axis := Vector3.UP.cross(away).normalized()
	var start := _tower_upper.basis
	var tw := create_tween()
	tw.tween_method(func(t: float):
		_tower_upper.basis = Basis(axis, deg_to_rad(82.0) * t * t) * start
		_tower_upper.position = TOWER_AT + Vector3.DOWN * 8.0 * t * t, 0.0, 1.0, 1.6)
	tw.tween_callback(func():
		FxKit.explosion(self, TOWER_AT + away * 18.0 + Vector3.UP * 2.0, 3.0, Color(0.6, 0.8, 1.0))
		for k in 3:
			var p := TOWER_AT + away.rotated(Vector3.UP, (k - 1) * 0.6) * 9.0
			Pickup.create(self, ["power", "fire", "homing"][k], ground(p.x, p.z), true))


func _hot_dog_stands() -> void:
	var spots := [
		[Vector3(-25, 0, 64), 0.0], [Vector3(66, 0, -12), 90.0], [Vector3(-12, 0, -66), 180.0],
		[Vector3(110, 0, 30), -90.0], [Vector3(-110, 0, -70), 90.0], [Vector3(20, 0, 110), 0.0],
	]
	for s in spots:
		_hot_dog_stand(s[0], s[1])


## Tail o' the Pup style stand with a giant hot dog on the roof. Breaks into a weapon.
func _hot_dog_stand(pos: Vector3, yaw: float) -> void:
	var b := Breakable.new()
	b.health = 12.0
	b.loot = "weapon"
	b.debris_color = Color(0.95, 0.85, 0.6)
	b.position = pos
	b.rotation_degrees.y = yaw
	add_child(b)
	b.add_box_shape(Vector3(4.2, 3.0, 3.0), Vector3(0, 1.5, 0))
	var v := b.visual
	MeshKit.box(v, Vector3(4.0, 2.4, 2.8), Vector3(0, 1.2, 0), _m.white)
	MeshKit.box(v, Vector3(4.04, 0.4, 2.84), Vector3(0, 0.5, 0), _m.red)
	MeshKit.box(v, Vector3(2.6, 1.0, 0.1), Vector3(0, 1.6, -1.42), _m.dark)
	for i in 6:
		MeshKit.box(v, Vector3(0.66, 0.22, 3.3), Vector3(-1.66 + i * 0.66, 2.55, 0), _m.red if i % 2 == 0 else _m.white, Vector3(10, 0, 0))
	var bun := MeshKit.mat(Color(0.88, 0.62, 0.32), 0.8)
	var sausage := MeshKit.mat(Color(0.62, 0.22, 0.12), 0.5)
	for s: float in [-1.0, 1.0]:
		MeshKit.sphere(v, 0.6, Vector3(0, 3.25, s * 0.32), bun, Vector3(3.4, 0.7, 0.75), 12)
	MeshKit.sphere(v, 0.45, Vector3(0, 3.55, 0), sausage, Vector3(5.0, 0.9, 0.9), 12)
	for i in 7:
		MeshKit.box(v, Vector3(0.5, 0.06, 0.1), Vector3(-1.5 + i * 0.5, 3.96, 0.1 * (1 if i % 2 == 0 else -1)), MeshKit.mat(Color(1.0, 0.82, 0.1), 0.6), Vector3(0, 30.0 * (1 if i % 2 == 0 else -1), 0))
	var l := Label3D.new()
	l.text = "HOT DOGS"
	l.font_size = 90
	l.pixel_size = 0.01
	l.modulate = Color(1.2, 0.15, 0.1)
	l.position = Vector3(0, 2.15, -1.48)
	l.rotation_degrees.y = 180.0
	v.add_child(l)


## Palm trees in the outer band and corners. They topple when hit.
func _palms() -> void:
	var spots: Array[Vector3] = []
	for t: float in [-95.0, -55.0, -10.0, 30.0, 70.0, 100.0]:
		spots.append(Vector3(t, 0, -110))
		spots.append(Vector3(t + 12.0, 0, 109))
		spots.append(Vector3(-111, 0, t + 6.0))
		spots.append(Vector3(110, 0, t - 8.0))
	for p in spots:
		var blocked := false
		for s: Vector3 in [Vector3(110, 0, 30), Vector3(-110, 0, -70), Vector3(20, 0, 110), Vector3(-116, 0, 0)]:
			if p.distance_to(s) < 9.0:
				blocked = true
		if not blocked:
			_palm(p + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)))


func _palm(pos: Vector3) -> void:
	var b := Breakable.new()
	b.style = Breakable.Style.TOPPLE
	b.health = 15.0
	b.debris_color = Color(0.45, 0.36, 0.24)
	b.position = pos
	add_child(b)
	b.add_box_shape(Vector3(1.0, 5.0, 1.0), Vector3(0, 2.5, 0))
	var v := b.visual
	var trunk := MeshKit.grime(Color(0.5, 0.4, 0.28), Color(0.32, 0.25, 0.18), 0.3, 0.95)
	var frond := MeshKit.mat(Color(0.28, 0.5, 0.18), 0.8)
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED
	var height := _rng.randf_range(11.0, 16.0)
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.5, 2.0)
	var segs := 5
	var prev := Vector3.ZERO
	for k in segs:
		var t := float(k + 1) / segs
		var p := Vector3.UP * height * t + lean * t * t
		_member(v, prev, p, lerpf(0.75, 0.45, t), trunk)
		prev = p
	for k in 9:
		var pivot := Node3D.new()
		pivot.position = prev
		pivot.rotation = Vector3(deg_to_rad(_rng.randf_range(-40, -20)), k * TAU / 9.0 + _rng.randf_range(-0.2, 0.2), 0)
		v.add_child(pivot)
		MeshKit.box(pivot, Vector3(1.0, 0.06, 4.6), Vector3(0, 0, -2.3), frond)
	for k in 3:
		MeshKit.sphere(v, 0.28, prev + Vector3(cos(k * 2.1) * 0.5, -0.4, sin(k * 2.1) * 0.5), MeshKit.mat(Color(0.35, 0.25, 0.12)), Vector3.ONE, 8)


# ---------------------------------------------------------------- far away

func _hills_and_sign() -> void:
	# The Hollywood Hills rise behind the north wall.
	MeshKit.prism(self, Vector3(100, 60, 760), Vector3(0, 30, -180), _m.hill, Vector3(0, -90, 0))
	for k in 8:
		var x := -480.0 + k * 135.0 + _rng.randf_range(-30, 30)
		var r := _rng.randf_range(120, 180)
		MeshKit.sphere(self, r, Vector3(x, 0, -290 - _rng.randf_range(0, 90)), _m.hill_far, Vector3(1.3, _rng.randf_range(0.5, 0.8), 0.9), 16)
	for k in 6:
		var a := deg_to_rad(-60 + k * 40.0)
		var r := _rng.randf_range(90, 130)
		MeshKit.sphere(self, r, Vector3(sin(a) * 560.0, 0, cos(a) * 560.0), _m.hill_far, Vector3(1.5, 0.35, 1.0), 14)
	# HOLLYWOOD: each letter breaks when shot. Too high to hit from the ground: try the tunnel roof.
	var glyphs := {
		"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
		"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
		"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	}
	var word := "HOLLYWOOD"
	var cell := 1.1
	var start_x := -60.0 - (word.length() - 1) * 8.0 * 0.5
	for i in word.length():
		var letter := Breakable.new()
		letter.style = Breakable.Style.TOPPLE
		letter.smash_on_contact = false
		letter.health = 20.0
		letter.debris_color = Color(0.95, 0.95, 0.92)
		letter.position = Vector3(start_x + i * 8.0, SIGN_BASE_Y, SIGN_Z)
		letter.rotation_degrees.x = -8.0
		add_child(letter)
		letter.add_box_shape(Vector3(5 * cell, 7 * cell, 1.2), Vector3(0, 3.5 * cell, 0))
		var rows: Array = glyphs[word[i]]
		for r in 7:
			var row: String = rows[r]
			for col in 5:
				if row[col] == "1":
					MeshKit.box(letter.visual, Vector3(cell, cell, 0.6), Vector3((col - 2) * cell, (6 - r + 0.5) * cell, 0), _m.white)
		for x: float in [-1.6, 1.6]:
			MeshKit.cylinder(self, 0.12, 4.0, letter.position + Vector3(x, -1.0, -1.2), _m.steel, Vector3(-8, 0, 0), 6)
		letter.broken.connect(_on_letter_broken)
		_letters_left += 1


func _on_letter_broken(_letter: Breakable, _by: Vehicle) -> void:
	_letters_left -= 1
	if _letters_left > 0:
		return
	easter_egg.emit("HOLLYWOOD IS DEAD", "Calypso: \"I never liked that sign. Take these, with my compliments.\"")
	for k in 3:
		Pickup.create(self, "power", Vector3(TUNNEL_X1 - 6.0, ROOF_Y, -10.0 + k * 10.0), true)


## Downtown towers in the haze, some of them leaning after the quake. Smoke from fires in the city.
func _skyline() -> void:
	for k in 16:
		var a := deg_to_rad(_rng.randf_range(100, 170))
		var r := _rng.randf_range(260, 480)
		var p := Vector3(sin(a) * r, 0, -cos(a) * r)
		var w := _rng.randf_range(18, 40)
		var h := _rng.randf_range(50, 190)
		var tilt := _rng.randf_range(-6, 6) if _rng.randf() < 0.3 else 0.0
		MeshKit.box(self, Vector3(w, h, w * _rng.randf_range(0.7, 1.2)), p + Vector3.UP * h * 0.5, _m.city, Vector3(tilt, _rng.randf_range(0, 90), 0))
	for k in 10:
		var a := deg_to_rad(_rng.randf_range(-100, 80))
		var r := _rng.randf_range(220, 360)
		var h := _rng.randf_range(15, 45)
		MeshKit.box(self, Vector3(_rng.randf_range(20, 40), h, 25), Vector3(sin(a) * r, h * 0.5, cos(a) * r), _m.concrete_dark, Vector3(0, _rng.randf_range(0, 90), 0))
	for p: Vector3 in [Vector3(300, 0, 250), Vector3(-320, 0, 160), Vector3(180, 0, -330)]:
		var plume := FxKit.smoke(14.0, 40)
		plume.lifetime = 14.0
		plume.gravity = Vector3(1.5, 3.0, 0)
		plume.color_ramp = null
		plume.color = Color(0.28, 0.26, 0.25, 0.35)
		plume.position = p + Vector3.UP * 20.0
		add_child(plume)
		plume.emitting = true


## Calypso's blimp, still far away in stage 1. It gets closer every stage.
func _blimp() -> void:
	var blimp := Node3D.new()
	blimp.name = "CalypsoBlimp"
	blimp.position = Vector3(240, 170, -400)
	blimp.rotation_degrees.y = 25.0
	add_child(blimp)
	var skin := MeshKit.mat(Color(0.18, 0.17, 0.2), 0.5, 0.3)
	var gold := MeshKit.mat(Color(0.85, 0.65, 0.2), 0.3, 1.0)
	MeshKit.sphere(blimp, 14.0, Vector3.ZERO, skin, Vector3(4.2, 1.0, 1.0), 20)
	MeshKit.torus(blimp, 13.8, 14.4, Vector3(-18, 0, 0), gold, Vector3(0, 0, 90))
	MeshKit.torus(blimp, 13.0, 13.6, Vector3(22, 0, 0), gold, Vector3(0, 0, 90))
	for k in 4:
		var fin := Node3D.new()
		fin.position = Vector3(50, 0, 0)
		fin.rotation.x = k * PI * 0.5
		blimp.add_child(fin)
		MeshKit.box(fin, Vector3(14, 0.8, 12), Vector3(0, 0, 9), skin)
	MeshKit.box(blimp, Vector3(22, 5, 7), Vector3(0, -15, 0), gold)
	for side: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "CALYPSO"
		l.font_size = 400
		l.pixel_size = 0.035
		l.modulate = Color(1.3, 1.0, 0.4)
		l.outline_size = 0
		l.position = Vector3(0, 2, side * 14.3)
		l.rotation_degrees.y = 0.0 if side > 0 else 180.0
		blimp.add_child(l)
	var blinker := Blinker.new()
	blinker.period = 0.9
	blimp.add_child(blinker)
	for x: float in [-55.0, 55.0]:
		var lamp := MeshKit.sphere(blimp, 0.8, Vector3(x, 0, 0), MeshKit.emissive(Color(1, 0.1, 0.05), 8.0))
		blinker.group_a.append(lamp)
	var tw := blimp.create_tween().set_loops()
	tw.tween_property(blimp, "position:y", 176.0, 6.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(blimp, "position:y", 170.0, 6.0).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- gameplay points

func _points() -> void:
	# yaw: 0 faces north (-Z), 90 west, 180 south, -90 east.
	spawn_points = [
		_spot(-60, 88, -90), # player: south road, facing east along the three humps
		_spot(88, 40, 0), # east road, facing north
		_spot(40, -88, 90), # north road, facing west
		_spot(-79, -60, 180), # facing south into the east tunnel
		_spot(-30, 40, 0), # infield, facing north
	]
	respawn_points = spawn_points.duplicate()
	respawn_points.append_array([_spot(0, 60, 0), _spot(60, 0, 90), _spot(0, -60, 180), _spot(88, -40, 0), _spot(-60, -88, -90)])
	for p: Vector3 in [Vector3(0, 0, -88), Vector3(-40, 0, -88), Vector3(88, 0, 0), Vector3(88, 0, -50), Vector3(40, 0, 88),
			Vector3(70, 0, 88), Vector3(-88, 0, 60), Vector3(-88, 0, -50), Vector3(-97, 0, 0), Vector3(-79, 0, 10),
			Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 40)]:
		weapon_points.append(ground(p.x, p.z))
	weapon_points.append_array([Vector3(TUNNEL_X1 - 9.0, ROOF_Y, 0), Vector3(TUNNEL_X0 + 10.0, ROOF_Y, 10), Vector3(TUNNEL_X0 + 10.0, ROOF_Y, -8)])
	health_points = [
		ground(-62, 0), # next to the tunnels (infield side)
		ground(-116, 0), # next to the tunnels (outside)
		ground(18, 18), # next to the pit of fire
		ground(-30, -30), # next to the burnt-out building
		Vector3(-10, 3.0, ROAD_H), # floating over the humps: jump for it
	]


func _spot(x: float, z: float, yaw_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), ground(x, z, 0.1))
