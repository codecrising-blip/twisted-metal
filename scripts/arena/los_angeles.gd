class_name LosAngelesArena
extends Node3D
## Stage 1 and the test stage: Twisted Metal 2's "Los Angeles: Quake Zone Rumble", rebuilt with the
## owner's layout (session 5):
##   - a raised battleground in the middle, PLAT_H (= about three Outlaws) above the roads, bigger
##     than before, held by retaining walls; ramps lead up from the road, the open edges are drops
##   - a wavy road loop around it (no square ring), with three hills for jumps and stunts
##   - twin tunnels on the north straight, glass walls you can drive through, ramps from the
##     battleground onto their roof (weapons, and a teleporter into the cage)
##   - on the battleground: the pit of fire in a quake crater, the burnt-out building, the power tower
##     whose four legs drop weapons, and the caged super health on a deck with an overpass ramp
##   - hot dog stands, storefronts against the steel outer wall, palms along the road
##   - the HOLLYWOOD sign on a scaffold beyond the north wall: shoot every letter from the tunnel roof
## Beyond the steel wall the city lies below: a pre-rendered panorama on the sky (assets/backdrops),
## not 3D, so all the modeling budget goes into the stage itself.
## Bright late-afternoon light, as in TM2. Fixed seed: the layout is the same every run.

signal easter_egg(title: String, text: String)

const HALF := 155.0 # inner face of the outer wall
const WALL_CHAMFER := 24.0
const MAP_HALF := 160 # heightmap reach (1 m samples); the plateau ends just past the wall
const PLAT_H := 5.0 # battleground height above the roads: about three Outlaws stacked (owner)
const PLAT_A := 100.0 # battleground half size in x (superellipse)
const PLAT_B := 92.0 # ... in z
const RAMP_L := 22.0
const RAMP_W := 14.0
const RAMP_ANGLES := [12.0, 105.0, 192.0, 322.0] # degrees around the battleground (0 = east, 90 = south)
const ROAD_W := 18.0
const HILL_H := 3.0
const HILL_AT := [0.33, 0.6, 0.86] # where the three hills sit along the road loop (0..1)
const ROOF_Y := 9.0 # tunnel roof
const ROAD_NORTH_Z := -128.0 # the north straight through the tunnels
const TUNNEL_X := 32.0 # tunnels run from -TUNNEL_X to TUNNEL_X
const TUNNEL_Z0 := -146.0
const TUNNEL_Z1 := -110.0
const DECK_Y := 6.0 # caged deck, above the battleground
const DECK_CENTER := Vector3(55, PLAT_H, -42)
const TOWER_AT := Vector3(52, PLAT_H, 48)
const BURNT_AT := Vector3(-52, PLAT_H, -38)
const SIGN_Z := -180.0
const SIGN_BASE_Y := 12.0
const BACKDROP := "res://assets/backdrops/los_angeles_city.jpg"

## Road loop control points (x, z), Catmull-Rom. Starts on the north straight (tunnels).
const ROAD_CTRL := [
	Vector2(-40, -128), Vector2(0, -128), Vector2(40, -128), Vector2(84, -130), Vector2(122, -108),
	Vector2(136, -70), Vector2(124, -30), Vector2(134, 14), Vector2(138, 58), Vector2(118, 100),
	Vector2(80, 132), Vector2(36, 120), Vector2(-10, 136), Vector2(-56, 124), Vector2(-100, 130),
	Vector2(-132, 98), Vector2(-126, 55), Vector2(-138, 10), Vector2(-134, -34), Vector2(-132, -80),
	Vector2(-100, -120),
]

var title := "LOS ANGELES"
var subtitle := "Quake Zone Rumble"
var spawn_points: Array[Transform3D] = []
var respawn_points: Array[Transform3D] = []
var weapon_points: Array[Vector3] = []
var health_points: Array[Vector3] = []
var mega_points: Array[Vector3] = []
var ramps: Array[Dictionary] = [] # {foot, top}: the AI drives to the foot, then up
var center := Vector3(0, PLAT_H, 0)
var wander_half := 130.0

var _rng := RandomNumberGenerator.new()
var _m := {} # materials
var _tower_legs := 4
var _tower_upper: Node3D
var _letters_left := 0

static var _road: PackedVector3Array
static var _hills: Array = []
static var _ramps: Array = []


func build() -> void:
	_rng.seed = 1996
	_materials()
	_environment()
	_terrain()
	_battleground_walls()
	_ramps_build()
	_roads()
	_cracks()
	_outer_wall()
	_storefronts()
	_tunnels()
	_overpass_and_cage()
	_fire_pit()
	_burnt_building(BURNT_AT)
	_power_tower()
	_hot_dog_stands()
	_palms()
	_hollywood_sign()
	var props := LaProps.new()
	props.name = "Props"
	add_child(props)
	props.build(self)
	_blimp()
	_points()


# ---------------------------------------------------------------- layout data (static)

## Road centerline, one point about every 2 m, y = 0.
static func road_points() -> PackedVector3Array:
	if _road.is_empty():
		var n := ROAD_CTRL.size()
		for i in n:
			var p0: Vector2 = ROAD_CTRL[(i - 1 + n) % n]
			var p1: Vector2 = ROAD_CTRL[i]
			var p2: Vector2 = ROAD_CTRL[(i + 1) % n]
			var p3: Vector2 = ROAD_CTRL[(i + 2) % n]
			var steps := maxi(2, int(p1.distance_to(p2) / 2.0))
			for k in steps:
				var t := float(k) / steps
				var t2 := t * t
				var t3 := t2 * t
				var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
				_road.append(Vector3(p.x, 0, p.y))
	return _road


## Road point and unit direction at a fraction (0..1) of the loop.
static func road_at(frac: float) -> Dictionary:
	var pts := road_points()
	var i := int(fposmod(frac, 1.0) * pts.size()) % pts.size()
	var dir := (pts[(i + 1) % pts.size()] - pts[(i - 1 + pts.size()) % pts.size()])
	dir.y = 0.0
	return {"p": pts[i], "dir": dir.normalized()}


static func hills() -> Array:
	if _hills.is_empty():
		for f: float in HILL_AT:
			var r := road_at(f)
			_hills.append({"p": Vector2(r.p.x, r.p.z), "d": Vector2(r.dir.x, r.dir.z)})
	return _hills


## The ramps up to the battleground: top (on its edge, y = PLAT_H), outward dir, side, foot.
static func ramp_list() -> Array:
	if _ramps.is_empty():
		for deg: float in RAMP_ANGLES:
			var a := deg_to_rad(deg)
			var c := cos(a)
			var s := sin(a)
			var r := 1.0 / pow(pow(absf(c) / PLAT_A, 4.0) + pow(absf(s) / PLAT_B, 4.0), 0.25)
			var e := Vector2(c, s) * r
			var nrm := Vector2(4.0 * pow(absf(e.x), 3.0) * signf(e.x) / pow(PLAT_A, 4.0), 4.0 * pow(absf(e.y), 3.0) * signf(e.y) / pow(PLAT_B, 4.0)).normalized()
			var dir := Vector3(nrm.x, 0, nrm.y)
			var top := Vector3(e.x, PLAT_H, e.y)
			_ramps.append({"top": top, "dir": dir, "side": Vector3(-dir.z, 0, dir.x), "foot": Vector3(top.x, 0, top.z) + dir * RAMP_L})
	return _ramps


## Signed distance (m, approx.) from the battleground edge: > 0 inside.
static func edge_distance(x: float, z: float) -> float:
	var f := pow(absf(x) / PLAT_A, 4.0) + pow(absf(z) / PLAT_B, 4.0)
	var s := pow(f, 0.25)
	var r := Vector2(x, z).length()
	if s < 0.0001:
		return PLAT_A
	return r / s - r


static func on_battleground(x: float, z: float) -> bool:
	return edge_distance(x, z) > 0.0


## Ground height: the raised battleground (with the crater), its ramps, and the road hills.
static func height_at(x: float, z: float) -> float:
	var ed := edge_distance(x, z)
	var h := PLAT_H * smoothstep(-0.5, 0.5, ed)
	if ed > 0.0:
		var r := Vector2(x, z).length()
		if r < 30.0:
			var t := clampf(r / 22.0, 0.0, 1.0)
			h -= 3.0 * (1.0 - smoothstep(0.15, 1.0, t))
			h += 0.7 * exp(-pow((r - 23.0) / 2.2, 2.0)) # rubble lip
		return h
	for rp: Dictionary in ramp_list():
		var rel := Vector3(x, 0, z) - Vector3(rp.top.x, 0, rp.top.z)
		var along: float = rel.dot(rp.dir)
		var across: float = absf(rel.dot(rp.side))
		if along > -1.0 and along < RAMP_L and across < RAMP_W * 0.5:
			h = maxf(h, PLAT_H * (1.0 - clampf(along / RAMP_L, 0.0, 1.0)))
	if h < 0.5:
		for hill: Dictionary in hills():
			var rel := Vector2(x, z) - (hill.p as Vector2)
			var a: float = rel.dot(hill.d) / 12.0
			var c: float = absf(rel.dot(Vector2(-hill.d.y, hill.d.x))) / 13.0
			if absf(a) < 1.0 and c < 1.0:
				h += HILL_H * pow(cos(a * PI * 0.5), 2.0) * (1.0 - smoothstep(0.7, 1.0, c))
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


## Distance from (x, z) to the road centerline (m).
static func road_distance(x: float, z: float) -> float:
	var best := INF
	var p := Vector3(x, 0, z)
	for q in road_points():
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


# ---------------------------------------------------------------- look

func _materials() -> void:
	_m.ground = MatKit.pavement("concrete", Color(0.4, 0.38, 0.35), 24.0, 7) # low ground around the road
	_m.deck = MatKit.pavement("concrete", Color(0.3, 0.29, 0.28), 16.0, 11) # the raised battleground
	_m.asphalt = MatKit.pavement("asphalt", Color(0.25, 0.25, 0.26), 16.0, 9)
	_m.yellow_line = _two_sided(MeshKit.mat(Color(0.95, 0.75, 0.12), 0.7))
	_m.white_line = _two_sided(MeshKit.mat(Color(0.92, 0.92, 0.88), 0.7))
	_m.crack = _two_sided(MeshKit.mat(Color(0.15, 0.14, 0.13), 1.0))
	_m.concrete = MeshKit.grime(Color(0.5, 0.49, 0.46), Color(0.36, 0.35, 0.33), 0.05, 0.9, 0.0, 0.2)
	_m.concrete_dark = MeshKit.grime(Color(0.44, 0.43, 0.41), Color(0.3, 0.29, 0.28), 0.05, 0.9, 0.0, 0.2)
	_m.wall = _panel_material(Color(0.6, 0.58, 0.54), Color(0.34, 0.33, 0.31), 4.0)
	_m.metal = MeshKit.mat(Color(0.5, 0.51, 0.53), 0.4, 0.8)
	_m.steel = MeshKit.mat(Color(0.36, 0.37, 0.39), 0.5, 0.7)
	_m.rust = MeshKit.grime(Color(0.5, 0.26, 0.1), Color(0.25, 0.12, 0.05), 0.15, 0.9, 0.3, 0.4)
	_m.char = MeshKit.grime(Color(0.16, 0.14, 0.12), Color(0.05, 0.05, 0.05), 0.12, 1.0, 0.0, 0.3)
	_m.brick = MeshKit.grime(Color(0.44, 0.24, 0.17), Color(0.14, 0.1, 0.08), 0.09, 0.95, 0.0, 0.3)
	_m.scorched = _two_sided(MeshKit.grime(Color(0.2, 0.19, 0.18), Color(0.08, 0.075, 0.07), 0.06, 1.0, 0.0, 0.15))
	_m.white = MeshKit.mat(Color(0.95, 0.95, 0.92), 0.6)
	_m.red = MeshKit.mat(Color(0.8, 0.1, 0.08), 0.6)
	_m.dark = MeshKit.mat(Color(0.06, 0.06, 0.07), 0.8)
	_m.window = MeshKit.mat(Color(0.15, 0.2, 0.28), 0.1, 0.5)
	_m.glass = MeshKit.mat(Color(0.55, 0.8, 0.95, 0.35), 0.05, 0.3)
	_m.glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m.chainlink = _chainlink_material()
	# MeshBuilder materials (dust baked into vertex colors).
	_m.retain = MatKit.paint(Color(0.52, 0.5, 0.46), 0.5, 0.35, 0.8, 3.0, 0.92, 140)
	_m.hazard = MatKit.paint(Color(0.68, 0.52, 0.08), 0.75, 0.5, 0.6, 1.0, 0.7, 141)
	_m.hazard_dark = MatKit.flat(Color(0.03, 0.03, 0.03), 0.9)
	_m.wall_steel = MatKit.paint(Color(0.22, 0.24, 0.22), 0.7, 0.75, 0.7, 2.0, 0.6, 142)
	_m.wall_steel.metallic = 0.6
	_m.rib = MatKit.steel(Color(0.16, 0.17, 0.16), 0.7, 1.0)


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
			img.set_pixel(x, y, Color(0.5, 0.52, 0.52, 1.0) if on else Color(0, 0, 0, 0))
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


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if ResourceLoader.exists(BACKDROP):
		# The city below, the mountains and the smog: one pre-rendered panorama (tests/bake_backdrop.gd).
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(BACKDROP)
		sky.sky_material = pano
	else:
		sky.sky_material = LosAngelesArena.sky_material()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.66, 0.62) # LA smog
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.0 # the backdrop already has its haze
	if RenderingServer.get_rendering_device() != null: # Forward+ / Mobile only
		env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9 # gritty, not candy (owner, session 5: "serious")
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = SUN_ROTATION
	add_child(sun)


const SUN_ROTATION := Vector3(-38, -45, 0) # low sun in the south-west


## The sky the backdrop is baked with (and the fallback when the backdrop image is missing).
static func sky_material() -> ProceduralSkyMaterial:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.46, 0.66)
	sky_mat.sky_horizon_color = Color(0.74, 0.7, 0.64) # smog on the horizon
	sky_mat.sky_curve = 0.1
	sky_mat.ground_horizon_color = Color(0.66, 0.63, 0.58)
	sky_mat.ground_bottom_color = Color(0.3, 0.29, 0.27)
	return sky_mat


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
	var g := MAP_HALF # grid points per side minus one
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
			# Two surfaces per chunk: the battleground top (darker slabs) and the low ground.
			var tools := [SurfaceTool.new(), SurfaceTool.new()]
			var used := [false, false]
			for t: SurfaceTool in tools:
				t.begin(Mesh.PRIMITIVE_TRIANGLES)
			for a in cells:
				for b in cells:
					var gi := cx * cells + a
					var gj := cz * cells + b
					for tri: Array in [[Vector2i(gi, gj), Vector2i(gi + 1, gj), Vector2i(gi, gj + 1)],
							[Vector2i(gi + 1, gj), Vector2i(gi + 1, gj + 1), Vector2i(gi, gj + 1)]]:
						var cxz := Vector2.ZERO
						for c: Vector2i in tri:
							cxz += Vector2(c.x * step - MAP_HALF, c.y * step - MAP_HALF) / 3.0
						var which := 1 if edge_distance(cxz.x, cxz.y) > 0.0 else 0
						used[which] = true
						for c: Vector2i in tri:
							var k: int = c.y * gn + c.x
							var x: float = c.x * step - MAP_HALF
							var z: float = c.y * step - MAP_HALF
							tools[which].set_normal(gnorm[k])
							tools[which].set_uv(Vector2(x, z) * 0.1)
							tools[which].add_vertex(Vector3(x, gh[k], z))
			for w in 2:
				if not used[w]:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = (tools[w] as SurfaceTool).commit()
				mi.material_override = _m.deck if w == 1 else _m.ground
				body.add_child(mi)
	# Where the plateau ends, just past the wall: a concrete face dropping toward the city.
	var mb := MeshBuilder.new()
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		var out := basis * Vector3(0, 0, -1)
		mb.box(_m.retain, (basis * Vector3(MAP_HALF * 2.0 + 4.0, 14.0, 2.0)).abs(), MeshBuilder.at(out * (MAP_HALF + 1.0) + Vector3(0, -7.0, 0)), 0.0)
	mb.commit(self, false)


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
		for p: Vector3 in [left[i], left[j], right[i], right[i], left[j], right[j]]: # clockwise from above = front face
			st.set_normal(_normal_at(p.x, p.z))
			st.set_uv(Vector2(p.x, p.z) * 0.1)
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Retaining walls around the battleground: one continuous concrete face with a hazard-painted
## edge and buttresses. The heightmap makes the cliff solid; this is what you see. It stands a
## metre out from the edge line so it hides the steep slope of the ground mesh. Gaps at the ramps.
func _battleground_walls() -> void:
	var mb := MeshBuilder.new()
	var segs := 320
	var pts: Array[Vector3] = []
	for k in segs:
		var a := TAU * k / segs
		var c := cos(a)
		var s := sin(a)
		var r := 1.0 / pow(pow(absf(c) / PLAT_A, 4.0) + pow(absf(s) / PLAT_B, 4.0), 0.25)
		pts.append(Vector3(c, 0, s) * r)
	var top := PLAT_H + 0.03
	for k in segs:
		var a := pts[k]
		var b := pts[(k + 1) % segs]
		var mid := (a + b) * 0.5
		var skip := false
		for rp: Dictionary in ramp_list():
			var rel := mid - Vector3(rp.top.x, 0, rp.top.z)
			if absf(rel.dot(rp.side)) < RAMP_W * 0.5 + 0.9 and absf(rel.dot(rp.dir)) < 3.0:
				skip = true
		if skip:
			continue
		var na := a.normalized()
		var nb := b.normalized()
		var ao := a + na * 1.0
		var bo := b + nb * 1.0
		var ai := a - na * 1.2
		var bi := b - nb * 1.2
		var out := (na + nb).normalized()
		var y0 := -0.6
		mb.quad(_m.retain, Vector3(ao.x, y0, ao.z), Vector3(bo.x, y0, bo.z), Vector3(bo.x, top - 0.5, bo.z), Vector3(ao.x, top - 0.5, ao.z), out)
		var stripe: Material = _m.hazard if (k / 2) % 2 == 0 else _m.hazard_dark
		mb.quad(stripe, Vector3(ao.x, top - 0.5, ao.z), Vector3(bo.x, top - 0.5, bo.z), Vector3(bo.x, top, bo.z), Vector3(ao.x, top, ao.z), out)
		mb.quad(stripe, Vector3(ao.x, top, ao.z), Vector3(bo.x, top, bo.z), Vector3(bi.x, top, bi.z), Vector3(ai.x, top, ai.z), Vector3.UP)
		if k % 8 == 0:
			var tangent := (b - a).normalized()
			var basis := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP))
			mb.box(_m.retain, Vector3(1.3, PLAT_H - 0.6, 0.8), Transform3D(basis, mid + out * 1.4 + Vector3(0, (PLAT_H - 0.6) * 0.5 - 0.6, 0)), 0.1)
	mb.commit(self, true, 0.6)


## Ramps from the road up to the battleground (the heightmap holds their slope): asphalt, sloped
## side walls with a low parapet (solid), painted edges.
func _ramps_build() -> void:
	var mb := MeshBuilder.new()
	var rails := StaticBody3D.new()
	rails.collision_layer = 1
	rails.collision_mask = 0
	add_child(rails)
	for rp: Dictionary in ramp_list():
		var top: Vector3 = rp.top
		var dir: Vector3 = rp.dir
		var side: Vector3 = rp.side
		var base := Vector3(top.x, 0, top.z) - dir * 0.6
		var foot := Vector3(top.x, 0, top.z) + dir * RAMP_L
		var rise := PLAT_H + 0.6
		for s: float in [-1.0, 1.0]:
			var o_in := side * s * (RAMP_W * 0.5)
			var o_out := side * s * (RAMP_W * 0.5 + 0.9)
			var away := side * s
			var park := 0.55 # parapet above the ramp surface
			# Outer face, inner face (above the ramp surface), sloped top, end cap.
			mb.quad(_m.retain, base + o_out + Vector3(0, -0.6, 0), foot + o_out + Vector3(0, -0.6, 0), foot + o_out + Vector3(0, park, 0), base + o_out + Vector3(0, rise + park - 0.6, 0), away)
			mb.quad(_m.retain, base + o_in + Vector3(0, rise - 0.6, 0), foot + o_in, foot + o_in + Vector3(0, park, 0), base + o_in + Vector3(0, rise + park - 0.6, 0), -away)
			mb.quad(_m.hazard, base + o_in + Vector3(0, rise + park - 0.6, 0), foot + o_in + Vector3(0, park, 0), foot + o_out + Vector3(0, park, 0), base + o_out + Vector3(0, rise + park - 0.6, 0), Vector3.UP)
			mb.quad(_m.retain, foot + o_in + Vector3(0, -0.6, 0), foot + o_out + Vector3(0, -0.6, 0), foot + o_out + Vector3(0, park, 0), foot + o_in + Vector3(0, park, 0), dir)
			# Collider: a thin slab along the parapet.
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var a := base + side * s * (RAMP_W * 0.5 + 0.45) + Vector3(0, rise - 0.6, 0)
			var b := foot + side * s * (RAMP_W * 0.5 + 0.45)
			box.size = Vector3(0.9, park + 0.6, a.distance_to(b))
			shape.shape = box
			var fwd := (b - a).normalized()
			shape.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), (a + b) * 0.5 + Vector3(0, park * 0.5 - 0.3, 0))
			rails.add_child(shape)
		ramps.append({"foot": foot + dir * 10.0, "top": top - dir * 8.0})
	mb.commit(self, true, 0.5)
	for rp: Dictionary in ramp_list():
		var pts := PackedVector3Array()
		var base := Vector3(rp.top.x, 0, rp.top.z) - (rp.dir as Vector3) * 2.0
		for k in 14:
			pts.append(base + (rp.dir as Vector3) * ((RAMP_L + 2.0) * k / 13.0))
		_drape(pts, RAMP_W - 0.2, 0.05, _m.asphalt)
		for s: float in [-1.0, 1.0]:
			_drape(pts, 0.3, 0.08, _m.yellow_line, false, s * (RAMP_W * 0.5 - 0.7))
		# Chevrons pointing up the ramp.
		for k in 3:
			var c := base + (rp.dir as Vector3) * (6.0 + k * 6.0)
			for s: float in [-1.0, 1.0]:
				var chev := PackedVector3Array([c + (rp.side as Vector3) * s * 3.5 + (rp.dir as Vector3) * 1.5, c])
				_drape(chev, 0.5, 0.09, _m.white_line)


func _roads() -> void:
	var loop := road_points()
	_drape(loop, ROAD_W, 0.04, _m.asphalt, true)
	for off: float in [-0.3, 0.3]:
		_drape(loop, 0.18, 0.07, _m.yellow_line, true, off)
	for off: float in [-ROAD_W * 0.5 + 0.7, ROAD_W * 0.5 - 0.7]:
		_drape(loop, 0.25, 0.07, _m.white_line, true, off)
	# Warning stripes painted across the road before each hill.
	for hill: Dictionary in hills():
		var p: Vector2 = hill.p
		var d: Vector2 = hill.d
		for back: float in [-20.0, 20.0]:
			var c := p + d * back
			var pts := PackedVector3Array()
			var across := Vector2(-d.y, d.x)
			for k in 9:
				var q := c + across * (-8.0 + k * 2.0)
				pts.append(Vector3(q.x, 0, q.y))
			for w in 3:
				var offs := w * 1.2 - 1.2
				var moved := PackedVector3Array()
				for q in pts:
					moved.append(q + Vector3(d.x, 0, d.y) * offs)
				_drape(moved, 0.45, 0.08, _m.white_line)


## Earthquake cracks: dark jagged lines across the ground (kept off the cliff edges).
func _cracks() -> void:
	for i in 26:
		var p := Vector3(_rng.randf_range(-140, 140), 0, _rng.randf_range(-140, 140))
		if p.length() < 26.0:
			continue
		var a := _rng.randf_range(0, TAU)
		var pts := PackedVector3Array()
		for k in _rng.randi_range(8, 18):
			if absf(edge_distance(p.x, p.z)) < 3.0:
				break
			pts.append(p)
			a += _rng.randf_range(-0.7, 0.7)
			p += Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.5, 3.0)
		_drape(pts, _rng.randf_range(0.15, 0.32), 0.09, _m.crack)


# ---------------------------------------------------------------- walls and buildings

func _wall_corners() -> Array:
	var c := WALL_CHAMFER
	return [
		Vector3(-HALF + c, 0, -HALF), Vector3(HALF - c, 0, -HALF), Vector3(HALF, 0, -HALF + c), Vector3(HALF, 0, HALF - c),
		Vector3(HALF - c, 0, HALF), Vector3(-HALF + c, 0, HALF), Vector3(-HALF, 0, HALF - c), Vector3(-HALF, 0, -HALF + c),
	]


## Outer wall: rusted steel plate (owner: "steel walls") with a chain-link fence on top, so the city
## below shows through. The collider is the full 8 m.
func _outer_wall() -> void:
	var h := 8.0
	var barrier_h := 2.8
	var corners := _wall_corners()
	var mb := MeshBuilder.new()
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var out := ((a + b) * 0.5).normalized()
		var dir := (b - a).normalized()
		var yaw := rad_to_deg(atan2(-dir.z, dir.x))
		var mid := (a + b) * 0.5 + out * 1.0
		var length := a.distance_to(b) + 2.2
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = mid + Vector3.UP * h * 0.5
		body.rotation_degrees.y = yaw
		add_child(body)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length, h, 2.0)
		shape.shape = bs
		body.add_child(shape)
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		mb.box(_m.wall_steel, Vector3(length, barrier_h, 1.6), Transform3D(basis, mid + Vector3.UP * barrier_h * 0.5), 0.02)
		mb.box(_m.rib, Vector3(length + 0.1, 0.22, 1.9), Transform3D(basis, mid + Vector3.UP * (barrier_h + 0.05)), 0.02)
		mb.box(_m.hazard, Vector3(length, 0.5, 1.64), Transform3D(basis, mid + Vector3.UP * 0.25), 0.0)
		var ribs := int(length / 3.0)
		for k in ribs + 1:
			var t := -length * 0.5 + k * length / ribs
			mb.box(_m.rib, Vector3(0.25, barrier_h, 1.8), Transform3D(basis, mid + dir * t + Vector3.UP * barrier_h * 0.5), 0.03)
			if k % 2 == 0:
				mb.box(_m.rib, Vector3(0.16, h - barrier_h, 0.16), Transform3D(basis, mid + dir * t + Vector3.UP * (barrier_h + (h - barrier_h) * 0.5)), 0.02)
		mb.box(_m.rib, Vector3(length, 0.12, 0.12), Transform3D(basis, mid + Vector3.UP * (h - 0.1)), 0.0)
		for wire in 3:
			mb.box(_m.rib, Vector3(length, 0.03, 0.03), Transform3D(basis, mid + Vector3.UP * (h + 0.15 + wire * 0.22) + out * (0.15 + wire * 0.15)), 0.0)
		var fence := MeshKit.box(self, Vector3(length, h - barrier_h - 0.2, 0.05), mid + Vector3.UP * (barrier_h + (h - barrier_h) * 0.5), _m.chainlink, Vector3(0, yaw, 0))
		fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mb.commit(self, true, 0.8)
	# Graffiti, Calypso's tournament everywhere (painted on the steel).
	var tags := [
		["QUAKE ZONE", Vector3(-30, 1.5, HALF - 0.85), 0.0, Color(0.85, 0.2, 0.22)],
		["CALYPSO LIES", Vector3(HALF - 0.85, 1.5, -40), 90.0, Color(0.25, 0.55, 0.9)],
		["SWEET TOOTH WAS HERE", Vector3(-HALF + 0.85, 1.5, 85), -90.0, Color(0.9, 0.5, 0.7)],
		["NO WISH IS FREE", Vector3(80, 1.5, -HALF + 0.85), 180.0, Color(0.9, 0.82, 0.25)],
	]
	for t in tags:
		var l := Label3D.new()
		l.text = t[0]
		l.font_size = 220
		l.pixel_size = 0.007
		l.outline_size = 18
		l.modulate = t[3]
		l.outline_modulate = Color(0.05, 0.05, 0.05)
		l.shaded = true
		l.position = t[1]
		l.rotation_degrees.y = t[2] + 180.0
		add_child(l)


## Shops built against the inside of the outer wall, where the road keeps its distance.
func _storefronts() -> void:
	_storefront(Vector3(-100, 0, HALF), Vector3(0, 0, -1), 26.0, 11.0, Color(0.72, 0.62, 0.45), "MOTEL", Color(0.9, 0.28, 0.3))
	_storefront(Vector3(36, 0, HALF), Vector3(0, 0, -1), 22.0, 9.0, Color(0.5, 0.62, 0.58), "LIQUOR", Color(0.3, 0.85, 0.45))
	var donuts := _storefront(Vector3(HALF, 0, -30), Vector3(-1, 0, 0), 20.0, 8.0, Color(0.78, 0.72, 0.6), "DONUTS", Color(0.95, 0.55, 0.2))
	var dough := MatKit.plain(MatKit.paint(Color(0.6, 0.4, 0.2), 0.5, 0.1, 0.7, 2.0, 0.8, 143))
	MeshKit.torus(donuts, 3.0, 6.5, Vector3(0, 16.0, -1.0), dough, Vector3(90, 0, 0))
	MeshKit.cylinder(donuts, 0.4, 6.0, Vector3(-3, 10.5, -1), _m.steel)
	MeshKit.cylinder(donuts, 0.4, 6.0, Vector3(3, 10.5, -1), _m.steel)
	_storefront(Vector3(HALF, 0, 100), Vector3(-1, 0, 0), 26.0, 13.0, Color(0.48, 0.28, 0.3), "THEATER", Color(0.95, 0.8, 0.3))
	_storefront(Vector3(-HALF, 0, 55), Vector3(1, 0, 0), 22.0, 9.0, Color(0.66, 0.5, 0.32), "TACOS", Color(0.95, 0.5, 0.12))
	_storefront(Vector3(-HALF, 0, -34), Vector3(1, 0, 0), 26.0, 10.0, Color(0.44, 0.48, 0.54), "AUTO PARTS", Color(0.95, 0.25, 0.2))
	_storefront(Vector3(100, 0, -HALF), Vector3(0, 0, 1), 20.0, 9.0, Color(0.6, 0.57, 0.52), "PAWN", Color(0.4, 0.75, 0.95))


func _storefront(on_wall: Vector3, inward: Vector3, width: float, height: float, color: Color, sign: String, sign_color: Color) -> Node3D:
	var node := Node3D.new()
	node.position = on_wall
	node.basis = Basis.looking_at(inward, Vector3.UP)
	add_child(node)
	var paint := MeshKit.grime(color, color.darkened(0.35), 0.08, 0.9, 0.0, 0.25)
	MeshKit.solid_box(node, Vector3(width, height, 2.0), Vector3(0, height * 0.5, -1.0), paint)
	var n_win := int(width / 5.0)
	for i in n_win:
		var x := -width * 0.5 + 2.5 + i * 5.0
		if absf(x) < 2.0:
			continue
		MeshKit.box(node, Vector3(3.2, 2.6, 0.1), Vector3(x, 2.2, -2.02), _m.window)
		if height > 9.0:
			MeshKit.box(node, Vector3(2.4, 1.8, 0.1), Vector3(x, 6.6, -2.02), _m.window)
	MeshKit.box(node, Vector3(2.4, 3.2, 0.1), Vector3(0, 1.6, -2.02), _m.dark)
	MeshKit.box(node, Vector3(width - 1.0, 0.3, 2.2), Vector3(0, 4.0, -3.0), MeshKit.mat(sign_color.darkened(0.45), 0.7), Vector3(-12, 0, 0))
	var l := Label3D.new()
	l.text = sign
	l.font_size = 300
	l.pixel_size = 0.012
	l.outline_size = 30
	l.modulate = sign_color * 1.1
	l.outline_modulate = Color(0.08, 0.06, 0.05)
	l.position = Vector3(0, height - 1.8, -2.1)
	l.rotation_degrees.y = 180.0
	node.add_child(l)
	return node


## Twin tunnels on the north straight: the road runs through them along x, a divider between the
## tubes, glass walls you can smash through, a freeway deck on top reached from the battleground.
func _tunnels() -> void:
	var cz := ROAD_NORTH_Z
	var length := TUNNEL_X * 2.0
	var width := TUNNEL_Z1 - TUNNEL_Z0
	var zc := (TUNNEL_Z0 + TUNNEL_Z1) * 0.5
	MeshKit.solid_box(self, Vector3(length, 1.0, width), Vector3(0, ROOF_Y - 0.5, zc), _m.deck)
	for z: float in [cz - 9.0, cz + 9.0]:
		for i in 8:
			MeshKit.box(self, Vector3(4.0, 0.04, 0.25), Vector3(-28 + i * 8.0, ROOF_Y + 0.02, z), _m.white_line)
	for z: float in [TUNNEL_Z0 + 0.6, TUNNEL_Z1 - 0.6]:
		MeshKit.box(self, Vector3(length, 0.05, 0.6), Vector3(0, ROOF_Y + 0.03, z), _m.yellow_line)
	# Freeway sign at the roof's east end, facing west along the deck (keeps the view north clear).
	var sign_post := Vector3(TUNNEL_X - 1.5, ROOF_Y, zc)
	for dz: float in [-4.5, 4.5]:
		MeshKit.cylinder(self, 0.25, 6.0, sign_post + Vector3(0, 3.0, dz), _m.steel)
	MeshKit.box(self, Vector3(0.3, 3.2, 11.0), sign_post + Vector3(0, 6.6, 0), MeshKit.mat(Color(0.1, 0.4, 0.22), 0.6))
	var fwy := Label3D.new()
	fwy.text = "101  HOLLYWOOD FWY"
	fwy.font_size = 140
	fwy.pixel_size = 0.012
	fwy.modulate = Color(1.3, 1.3, 1.3)
	fwy.position = sign_post + Vector3(-0.2, 6.6, 0)
	fwy.rotation_degrees.y = -90.0
	add_child(fwy)
	# Walls along x: pillars every 8 m with glass between. The roof ramps cover bays on the south side.
	var ramp_bays := [1, 2, 5, 6]
	for wall_z: float in [TUNNEL_Z0 + 0.5, cz, TUNNEL_Z1 - 0.5]:
		var thick := 2.0 if wall_z == cz else 1.0
		for i in 9:
			var x := -TUNNEL_X + i * 8.0
			MeshKit.solid_box(self, Vector3(1.4, ROOF_Y - 1.0, thick + 0.4), Vector3(x, (ROOF_Y - 1.0) * 0.5, wall_z), _m.concrete_dark)
		for i in 8:
			var xc := -TUNNEL_X + 4.0 + i * 8.0
			if wall_z == TUNNEL_Z1 - 0.5 and i in ramp_bays:
				MeshKit.solid_box(self, Vector3(6.6, ROOF_Y - 1.0, thick), Vector3(xc, (ROOF_Y - 1.0) * 0.5, wall_z), _m.concrete_dark)
			else:
				_glass_panel(Vector3(xc, 0, wall_z), thick)
	# Divider noses: wedges that deflect cars into one tube or the other.
	for s: float in [-1.0, 1.0]:
		# Prism: width across the road (local x -> world z), apex pointing out of the tunnel
		# (local y -> world x), height up (local z -> world y).
		var nose := MeshKit.prism(self, Vector3(2.4, 5.0, ROOF_Y - 1.0), Vector3(s * (TUNNEL_X + 2.5), (ROOF_Y - 1.0) * 0.5, cz), _m.concrete_dark)
		nose.basis = Basis(Vector3(0, 0, 1), Vector3(s, 0, 0), Vector3(0, s, 0))
		MeshKit.solid_mesh(self, nose)
		MeshKit.box(self, Vector3(0.1, 0.6, 2.6), Vector3(s * (TUNNEL_X + 0.1), 2.0, cz), MeshKit.mat(Color(0.95, 0.75, 0.1), 0.7))
	for z: float in [(TUNNEL_Z0 + cz) * 0.5, (cz + TUNNEL_Z1) * 0.5]:
		for x: float in [-20.0, 0.0, 20.0]:
			MeshKit.box(self, Vector3(6.0, 0.1, 1.0), Vector3(x, ROOF_Y - 1.06, z), MeshKit.emissive(Color(1.0, 0.95, 0.8), 3.0))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.92, 0.78)
			l.light_energy = 1.6
			l.omni_range = 15.0
			l.position = Vector3(x, ROOF_Y - 2.0, z)
			add_child(l)
	# Two ramps from the battleground's north edge up onto the roof (5 m -> 9 m).
	for x: float in [-16.0, 16.0]:
		var z0 := -PLAT_B * pow(1.0 - pow(absf(x) / PLAT_A, 4.0), 0.25) + 0.5
		var z1 := TUNNEL_Z1
		var run := absf(z1 - z0)
		var zm := (z0 + z1) * 0.5
		MeshKit.solid_box(self, Vector3(14.0, PLAT_H, run + 1.0), Vector3(x, PLAT_H * 0.5, zm), _m.concrete_dark)
		var ramp := MeshKit.prism(self, Vector3(run, ROOF_Y - PLAT_H, 14.0), Vector3(x, PLAT_H + (ROOF_Y - PLAT_H) * 0.5, zm), _m.concrete, Vector3(0, -90, 0))
		MeshKit.solid_mesh(self, ramp)
		for k in 4:
			var t := (k + 0.5) / 4.0
			var z := lerpf(z0, z1, t)
			MeshKit.box(self, Vector3(9.0, 0.05, 1.2), Vector3(x, PLAT_H + (ROOF_Y - PLAT_H) * t + 0.06, z), _m.yellow_line, Vector3(rad_to_deg(atan((ROOF_Y - PLAT_H) / run)), 0, 0))
		ramps.append({"foot": Vector3(x, PLAT_H, z0 + 10.0), "top": Vector3(x, ROOF_Y, z1 - 8.0)})
	# Teleporter on the roof: straight into the cage with the super health.
	var tp := Teleporter.new()
	add_child(tp)
	tp.global_position = Vector3(-TUNNEL_X + 8.0, ROOF_Y, TUNNEL_Z0 + 8.0)
	tp.destination = Transform3D(Basis(Vector3.UP, PI), DECK_CENTER + Vector3(0, DECK_Y + 0.1, -9))


func _glass_panel(at: Vector3, thick: float) -> void:
	var b := Breakable.new()
	b.health = 8.0
	b.debris_color = Color(0.7, 0.9, 1.0)
	b.position = at
	add_child(b)
	b.add_box_shape(Vector3(6.6, ROOF_Y - 1.4, thick * 0.5), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0))
	MeshKit.box(b.visual, Vector3(6.6, ROOF_Y - 1.4, thick * 0.3), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0), _m.glass)
	MeshKit.box(b.visual, Vector3(6.6, 0.2, thick * 0.5), Vector3(0, (ROOF_Y - 1.4) * 0.5, 0), _m.steel)


## The cage: a deck on the battleground with the super health, reached by an overpass ramp.
func _overpass_and_cage() -> void:
	var c := DECK_CENTER
	MeshKit.solid_box(self, Vector3(30, DECK_Y, 30), c + Vector3(0, DECK_Y * 0.5, 0), _m.wall)
	MeshKit.box(self, Vector3(30.2, 0.1, 30.2), c + Vector3(0, DECK_Y + 0.02, 0), _m.concrete_dark)
	var ramp := MeshKit.prism(self, Vector3(30, DECK_Y, 12), c + Vector3(0, DECK_Y * 0.5, 30), _m.concrete_dark, Vector3(0, -90, 0))
	MeshKit.solid_mesh(self, ramp)
	var slope := rad_to_deg(atan(DECK_Y / 30.0))
	for side: float in [-1.0, 1.0]:
		MeshKit.solid_box(self, Vector3(0.6, 1.0, 30.8), c + Vector3(side * 6.3, DECK_Y * 0.5 + 0.5, 30), _m.concrete, Vector3(slope, 0, 0))
	ramps.append({"foot": c + Vector3(0, 0, 52), "top": c + Vector3(0, DECK_Y, 6)})
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
	warn.modulate = Color(0.95, 0.2, 0.15)
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


## The pit of fire in the middle of the battleground.
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
	for k in 6:
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
	var b := c.y
	MeshKit.solid_box(self, Vector3(1.0, h, d), c + Vector3(-w * 0.5 + 0.5, h * 0.5, 0), _m.brick)
	MeshKit.solid_box(self, Vector3(1.0, h * 0.8, d), c + Vector3(w * 0.5 - 0.5, h * 0.4, 0), _m.brick)
	for s: float in [-1.0, 1.0]:
		var z := c.z + s * (d * 0.5 - 0.5)
		MeshKit.solid_box(self, Vector3(side, h, 1.0), Vector3(c.x - w * 0.5 + side * 0.5, b + h * 0.5, z), _m.brick)
		MeshKit.solid_box(self, Vector3(side, h * 0.85, 1.0), Vector3(c.x + w * 0.5 - side * 0.5, b + h * 0.425, z), _m.brick)
		MeshKit.solid_box(self, Vector3(door, h - 6.0, 1.0), Vector3(c.x, b + 6.0 + (h - 6.0) * 0.5, z), _m.brick)
		MeshKit.box(self, Vector3(door + 0.4, 0.6, 1.2), Vector3(c.x, b + 6.0, z), _m.char)
		for k in 3:
			var x := c.x - w * 0.5 + 2.0 + k * 3.2 if k < 2 else c.x + w * 0.5 - 3.0
			MeshKit.box(self, Vector3(1.8, 2.2, 1.1), Vector3(x, b + 9.0, z), _m.dark)
			MeshKit.box(self, Vector3(2.0, 1.5, 1.12), Vector3(x, b + 10.8, z), _m.char)
	MeshKit.solid_box(self, Vector3(w, 0.6, d), c + Vector3(0, 6.3, 0), _m.char) # first floor
	MeshKit.box(self, Vector3(w * 0.6, 0.5, d * 0.7), c + Vector3(-3, h - 0.3, -1), _m.char, Vector3(0, 0, -8))
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
	# Power lines running off over the wall toward the city.
	var line_mat := MeshKit.mat(Color(0.1, 0.1, 0.1), 0.6)
	for x: float in [-7.5, 7.5, -5.5, 5.5]:
		var y := 20.0 if absf(x) > 6.0 else 25.0
		var line := ZigLine.new()
		line.material = line_mat
		line.thickness = 0.08
		add_child(line)
		line.draw(at + Vector3(x, y, 0), Vector3(HALF + 70.0, 18.0, HALF + 30.0 + x), 0.0, 6.0)
	MeshKit.box(self, Vector3(4.6, 2.4, 0.08), at + Vector3(0, 6.0, 4.0), MatKit.plain(MatKit.paint(Color(0.7, 0.55, 0.08), 0.6, 0.6, 0.6, 2.0, 0.7, 120)))
	for face: float in [1.0, -1.0]:
		var sign := Label3D.new()
		sign.text = "DANGER\nHIGH VOLTAGE"
		sign.font_size = 90
		sign.pixel_size = 0.009
		sign.modulate = Color(0.05, 0.04, 0.03)
		sign.outline_size = 0
		sign.shaded = true
		sign.double_sided = false
		sign.position = at + Vector3(0, 6.0, 4.0 + 0.05 * face)
		sign.rotation_degrees.y = 0.0 if face > 0.0 else 180.0
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
		[Vector3(-30, 0, 52), 0.0], [Vector3(66, 0, 8), 90.0], [Vector3(-12, 0, -58), 180.0],
		[Vector3(-118, 0, -8), 90.0], [Vector3(96, 0, 70), -60.0], [Vector3(-60, 0, 108), 0.0],
	]
	for s in spots:
		var p: Vector3 = s[0]
		_hot_dog_stand(ground(p.x, p.z), s[1])


## Stand with a giant hot dog on the roof. Breaks into a weapon.
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
	var cart := MatKit.plain(MatKit.paint(Color(0.7, 0.67, 0.6), 0.7, 0.5, 0.75, 1.5, 0.6, 130))
	var stripe := MatKit.plain(MatKit.paint(Color(0.48, 0.1, 0.08), 0.7, 0.4, 0.6, 1.5, 0.6, 131))
	MeshKit.box(v, Vector3(4.0, 2.4, 2.8), Vector3(0, 1.2, 0), cart)
	MeshKit.box(v, Vector3(4.04, 0.4, 2.84), Vector3(0, 0.5, 0), stripe)
	MeshKit.box(v, Vector3(2.6, 1.0, 0.1), Vector3(0, 1.6, -1.42), _m.dark)
	for i in 6:
		MeshKit.box(v, Vector3(0.66, 0.22, 3.3), Vector3(-1.66 + i * 0.66, 2.55, 0), stripe if i % 2 == 0 else cart, Vector3(10, 0, 0))
	var bun := MatKit.plain(MatKit.paint(Color(0.66, 0.46, 0.26), 0.6, 0.0, 0.6, 1.0, 0.8, 132))
	var sausage := MatKit.plain(MatKit.paint(Color(0.42, 0.16, 0.1), 0.5, 0.0, 0.5, 1.0, 0.6, 133))
	for s: float in [-1.0, 1.0]:
		MeshKit.sphere(v, 0.6, Vector3(0, 3.25, s * 0.32), bun, Vector3(3.4, 0.7, 0.75), 12)
	MeshKit.sphere(v, 0.45, Vector3(0, 3.55, 0), sausage, Vector3(5.0, 0.9, 0.9), 12)
	for i in 7:
		MeshKit.box(v, Vector3(0.5, 0.06, 0.1), Vector3(-1.5 + i * 0.5, 3.96, 0.1 * (1 if i % 2 == 0 else -1)), MeshKit.mat(Color(0.7, 0.58, 0.12), 0.6), Vector3(0, 30.0 * (1 if i % 2 == 0 else -1), 0))
	var l := Label3D.new()
	l.text = "HOT DOGS"
	l.font_size = 90
	l.pixel_size = 0.01
	l.shaded = true
	l.modulate = Color(0.5, 0.08, 0.06)
	l.position = Vector3(0, 2.15, -1.48)
	l.rotation_degrees.y = 180.0
	v.add_child(l)


## Palms along both edges of the road, on the low ground. They topple when hit.
func _palms() -> void:
	var pts := road_points()
	var k := 0
	while k < pts.size():
		var p := pts[k]
		var nxt := pts[(k + 1) % pts.size()]
		var dir := (nxt - p).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var s := 1.0 if (k / 9) % 2 == 0 else -1.0
		var spot := p + side * s * (ROAD_W * 0.5 + 3.5)
		k += 9 + _rng.randi_range(0, 4)
		if absf(spot.x) < TUNNEL_X + 8.0 and spot.z < TUNNEL_Z1 + 4.0:
			continue
		if edge_distance(spot.x, spot.z) > -3.0 or road_distance(spot.x, spot.z) < ROAD_W * 0.5 + 2.0:
			continue
		if absf(spot.x) > HALF - 4.0 or absf(spot.z) > HALF - 4.0 or absf(spot.x) + absf(spot.z) > 2.0 * HALF - WALL_CHAMFER - 6.0:
			continue
		var blocked := false
		for rp: Dictionary in ramp_list():
			if spot.distance_to(rp.foot) < RAMP_L * 0.5 + 10.0:
				blocked = true
		for hill: Dictionary in hills():
			if Vector2(spot.x, spot.z).distance_to(hill.p) < 16.0:
				blocked = true
		if not blocked:
			_palm(ground(spot.x, spot.z))


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
	var frond := MeshKit.mat(Color(0.24, 0.42, 0.16), 0.8)
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


# ---------------------------------------------------------------- beyond the wall

## HOLLYWOOD on a steel scaffold standing up from the city below, just past the north wall.
## Each letter breaks when shot. Too high to hit from the ground: try the tunnel roof.
func _hollywood_sign() -> void:
	var mb := MeshBuilder.new()
	var steel := MatKit.steel(Color(0.2, 0.2, 0.21), 0.6, 1.0)
	var word := "HOLLYWOOD"
	var cell := 1.1
	var start_x := -10.0 - (word.length() - 1) * 8.0 * 0.5
	var x0 := start_x - 4.0
	var x1 := start_x + (word.length() - 1) * 8.0 + 4.0
	for k in 11:
		var x := lerpf(x0, x1, k / 10.0)
		mb.box(steel, Vector3(0.35, 52.0, 0.35), MeshBuilder.at(Vector3(x, SIGN_BASE_Y + 8.0 - 26.0, SIGN_Z - 2.0)), 0.02)
		mb.box(steel, Vector3(0.25, 0.25, 3.2), MeshBuilder.at(Vector3(x, SIGN_BASE_Y - 1.0, SIGN_Z - 0.6), Vector3(-30, 0, 0)), 0.02)
	for y: float in [SIGN_BASE_Y - 1.0, SIGN_BASE_Y + 4.0, SIGN_BASE_Y + 9.5, SIGN_BASE_Y - 10.0, SIGN_BASE_Y - 20.0]:
		mb.box(steel, Vector3(x1 - x0, 0.3, 0.3), MeshBuilder.at(Vector3((x0 + x1) * 0.5, y, SIGN_Z - 2.0)), 0.02)
	for k in 10:
		var xa := lerpf(x0, x1, k / 10.0)
		var xb := lerpf(x0, x1, (k + 1) / 10.0)
		for band in 2:
			var ya := SIGN_BASE_Y - 1.0 - band * 10.0
			var yb := ya - 9.0 if band == 1 else SIGN_BASE_Y + 9.5
			var a := Vector3(xa, ya, SIGN_Z - 2.0)
			var b := Vector3(xb, yb, SIGN_Z - 2.0)
			if k % 2 == 1:
				var t := a.y
				a.y = b.y
				b.y = t
			mb.box(steel, Vector3(0.18, a.distance_to(b), 0.18), MeshBuilder.along((a + b) * 0.5, b - a), 0.0)
	mb.commit(self, true, 0.0)
	var glyphs := {
		"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
		"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
		"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	}
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
		letter.broken.connect(_on_letter_broken)
		_letters_left += 1


func _on_letter_broken(_letter: Breakable, _by: Vehicle) -> void:
	_letters_left -= 1
	if _letters_left > 0:
		return
	easter_egg.emit("HOLLYWOOD IS DEAD", "Calypso: \"I never liked that sign. Take these, with my compliments.\"")
	for k in 3:
		Pickup.create(self, "power", Vector3(-10.0 + k * 10.0, ROOF_Y, (TUNNEL_Z0 + TUNNEL_Z1) * 0.5 + 6.0), true)


## Calypso's blimp, still far away in stage 1. It gets closer every stage.
func _blimp() -> void:
	var blimp := Node3D.new()
	blimp.name = "CalypsoBlimp"
	blimp.position = Vector3(620, 330, -1050)
	blimp.rotation_degrees.y = 25.0
	blimp.scale = Vector3.ONE * 1.7
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
	tw.tween_property(blimp, "position:y", 338.0, 8.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(blimp, "position:y", 330.0, 8.0).set_trans(Tween.TRANS_SINE)


## For the HUD radar: the outer wall, the road, the battleground edge and the tunnels.
func radar_lines() -> Array:
	var wall := PackedVector2Array()
	for c: Vector3 in _wall_corners():
		wall.append(Vector2(c.x, c.z))
	wall.append(wall[0])
	var road := PackedVector2Array()
	var pts := road_points()
	for i in range(0, pts.size(), 3):
		road.append(Vector2(pts[i].x, pts[i].z))
	road.append(road[0])
	var edge := PackedVector2Array()
	for k in 73:
		var a := TAU * k / 72.0
		var r := 1.0 / pow(pow(absf(cos(a)) / PLAT_A, 4.0) + pow(absf(sin(a)) / PLAT_B, 4.0), 0.25)
		edge.append(Vector2(cos(a), sin(a)) * r)
	var tunnel := PackedVector2Array([Vector2(-TUNNEL_X, TUNNEL_Z0), Vector2(TUNNEL_X, TUNNEL_Z0), Vector2(TUNNEL_X, TUNNEL_Z1),
		Vector2(-TUNNEL_X, TUNNEL_Z1), Vector2(-TUNNEL_X, TUNNEL_Z0)])
	return [wall, road, edge, tunnel]


# ---------------------------------------------------------------- gameplay points

## Named places the tests and screenshot tool use, so they follow the layout.
func spot(name: String) -> Transform3D:
	match name:
		"player":
			return spawn_points[0]
		"open": # open flat ground on the battleground, away from everything
			return _spot(0, 46, 0)
		"south_wall_45": # heading south-east at the south wall
			return _spot(-30, HALF - 15.0, -135)
		"south_wall_90":
			return _spot(-5, HALF - 15.0, 180)
	return _spot(0, 46, 0)


func _road_spot(frac: float, lift := 0.1, reverse := false) -> Transform3D:
	var r := road_at(frac)
	var dir: Vector3 = -r.dir if reverse else r.dir
	var yaw := atan2(-dir.x, -dir.z)
	var p: Vector3 = r.p
	return Transform3D(Basis(Vector3.UP, yaw), ground(p.x, p.z, lift))


func _points() -> void:
	# yaw: 0 faces north (-Z), 90 west, 180 south, -90 east.
	spawn_points = [
		_road_spot(0.55, 0.1, true), # player: on the south road, driving east
		_road_spot(0.12),
		_road_spot(0.97),
		_spot(-40, 30, 90), # battleground
		_spot(40, -10, -90),
	]
	respawn_points = spawn_points.duplicate()
	for f: float in [0.05, 0.25, 0.42, 0.7, 0.8, 0.92]:
		respawn_points.append(_road_spot(f))
	respawn_points.append_array([_spot(0, 60, 0), _spot(-60, -60, 180), _spot(70, 30, 90)])
	# Weapons along the road (not on the hills or by the ramp feet), on the battleground, on the roof.
	for k in 14:
		var f := (k + 0.5) / 14.0
		var r := road_at(f)
		var p: Vector3 = r.p
		var near_hill := false
		for hill: Dictionary in hills():
			if Vector2(p.x, p.z).distance_to(hill.p) < 20.0:
				near_hill = true
		if not near_hill:
			weapon_points.append(ground(p.x, p.z))
	for p: Vector3 in [Vector3(-35, 0, 20), Vector3(35, 0, -15), Vector3(0, 0, -40), Vector3(-60, 0, 60), Vector3(20, 0, 68), Vector3(-70, 0, -10)]:
		weapon_points.append(ground(p.x, p.z))
	weapon_points.append_array([Vector3(-20, ROOF_Y, TUNNEL_Z1 - 8.0), Vector3(10, ROOF_Y, TUNNEL_Z0 + 10.0), Vector3(24, ROOF_Y, TUNNEL_Z0 + 10.0)])
	health_points = [
		ground(-TUNNEL_X - 14.0, ROAD_NORTH_Z + 14.0), # by the tunnels
		ground(26, 22), # by the pit of fire
		ground(BURNT_AT.x + 16.0, BURNT_AT.z), # by the burnt building
		ground(-100, 30),
	]
	var hill: Dictionary = hills()[1]
	var top: Vector2 = hill.p
	health_points.append(Vector3(top.x, HILL_H + 2.6, top.y)) # floating over a hill: jump for it


func _spot(x: float, z: float, yaw_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), ground(x, z, 0.1))
