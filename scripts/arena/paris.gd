class_name ParisArena
extends ArenaKit
## Stage 2: Paris (docs/design/32-paris-design.md, layout v2 "two banks of the Seine").
## x east (-275..275), z south (-225..225), y up; 550 x 450 m = 17 s x 14 s at Sweet Tooth's top speed.
## The city is flat at y 0; everything lower (the Seine's trench) and higher (terraces, Montmartre,
## roofs) is built explicitly, so every edge is exact (no 1 m height-grid slopes for walls).
## Phase 1: ground, river with lower quays, bridges, roads, plazas, parks, terraces, city blocks
## (ParisBlocks), gameplay points. Landmarks, the tower and the tricks come in later phases.

const HX := 275.0
const HZ := 225.0
const STEP := 2.5 # river sampling along x
const WATER_Y := -6.5
const QUAY_Y := -5.0
const QUAY_W := 10.0 # lower quay (design 8 m; 10 so Axel's 2.8 m body has room at speed)
const WATER_HALF := 15.0
const PROMENADE := 2.5 # stone coping between the trench and the quay road
const QUAY_ROAD_W := 16.0
const SIDEWALK := 5.0
const ROOF_Y := 13.0 # drivable roofs of the Haussmann quarter (TM2's legacy)
const TALL_Y := 20.4 # the other blocks (not drivable)
const PARAPET_H := 0.9
const VEHICLE_BARRIER_LAYER := 16
const ETOILE := Vector2(-150, -168)
const RING_R := 35.0
const TOWER := Vector2(-190, 140)
const MONT := Vector2(226, -184)
const MONT_LOW := 38.0 # terrace 1 half size (+7)
const MONT_TOP := 18.0 # terrace 2 half size (+14)
const RIVER_CTRL := [Vector2(-340, 64), Vector2(-280, 62), Vector2(-200, 58), Vector2(-120, 52), Vector2(-40, 44),
	Vector2(40, 40), Vector2(120, 44), Vector2(200, 54), Vector2(280, 66), Vector2(340, 68)]
# Bridges: x, width, spans across the river (d from the river centre at x), hump.
const BRIDGES := [
	{"name": "iena", "x": -190.0, "w": 18.0, "spans": "full", "h": 1.0},
	{"name": "alexandre", "x": 0.0, "w": 24.0, "spans": "full", "h": 1.2},
	{"name": "pont_neuf", "x": 182.0, "w": 16.0, "spans": "island", "h": 0.6},
	{"name": "notre_dame_n", "x": 226.0, "w": 14.0, "spans": "north", "h": 0.5},
	{"name": "petit_pont", "x": 244.0, "w": 14.0, "spans": "south", "h": 0.5},
]

# Palette (design 32 section 5)
const C_STONE := Color("D8C9AC")
const C_QUAY := Color("C4B597")
const C_ASPHALT := Color("3A3B3E")
const C_COBBLE := Color("6B6458")
const C_SIDEWALK := Color("B9AE98")
const C_GRAVEL := Color("CDBA8E")
const C_LAWN := Color("6F8F48")
const C_WATER := Color("4E6B6A")
const C_CURB := Color("8C877E")
const C_ZINC := Color("6F7C86")
const C_GOLD := Color("C9A54A")

var title := "PARIS"
var music := "paris"
var subtitle := "City of Lights Out"
var next_line := "Prepare for Chernobyl"
var spawn_points: Array[Transform3D] = []
var respawn_points: Array[Transform3D] = []
var weapon_points: Array[Vector3] = []
var weapon_kinds: Array[String] = []
var health_points: Array[Vector3] = []
var mega_points: Array[Vector3] = []
var turbo_points: Array[Vector3] = []
var ramps: Array[Dictionary] = []
var center := Vector3(0, 0, -40)
var wander_half := 220.0

var roads: Array[Dictionary] = [] # {pts: PackedVector2Array, w}
var blocks: Array[Dictionary] = [] # {poly, roof: bool, h}
var _m := {}
var _buildings: StaticBody3D
var _road_polys: Array[PackedVector2Array] = []
static var _rz := PackedFloat32Array()


func build() -> void:
	_materials()
	_environment()
	_river()
	_bridges()
	_layout_roads()
	_draw_roads()
	_parks()
	_terraces()
	_montmartre()
	_city_blocks()
	ParisBlocks.build(self, blocks)
	_rooftops()
	_boundary()
	_points()
	flush_sheets()
	flush_batch()
	flush_collision()


func _materials() -> void:
	_m.sidewalk = MatKit.pavers(C_SIDEWALK, 3.0, 21)
	_m.asphalt = MatKit.pavement("asphalt", C_ASPHALT, 16.0, 22)
	_m.cobble = MatKit.pavers(C_COBBLE, 2.4, 23)
	_m.plaza = MatKit.pavers(Color("BDB09A"), 6.0, 24)
	_m.gravel = MatKit.pavement("concrete", C_GRAVEL, 10.0, 25)
	_m.lawn = MatKit.grass(C_LAWN, 12.0, 26)
	_m.quay = MatKit.masonry(C_QUAY, 4.0, 27)
	_m.stone = MatKit.masonry(C_STONE, 4.0, 28)
	_m.curb = MatKit.flat(C_CURB, 0.85)
	_m.water = _water_material()
	_m.gold = MatKit.flat(C_GOLD, 0.35, 0.8)


func _water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.22, 0.31, 0.30);
uniform vec3 shallow : source_color = vec3(0.31, 0.42, 0.41);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float wave(vec2 p, vec2 d, float f, float s) { return sin(dot(p, d) * f + TIME * s); }
void fragment() {
	vec2 p = wpos.xz;
	float h = wave(p, vec2(0.8, 0.6), 0.9, 1.3) + wave(p, vec2(-0.3, 0.95), 1.7, 1.9) * 0.6 + wave(p, vec2(0.95, -0.2), 3.1, 2.7) * 0.3;
	vec3 n = normalize(vec3(cos(dot(p, vec2(0.8, 0.6)) * 0.9 + TIME * 1.3) * 0.09, 1.0, cos(dot(p, vec2(-0.3, 0.95)) * 1.7 + TIME * 1.9) * 0.07));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep, shallow, 0.5 + 0.12 * h);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# ---------------------------------------------------------------- environment

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.33, 0.5, 0.74)
	sm.sky_horizon_color = Color(0.84, 0.79, 0.7) # warm haze low on the horizon (4 pm)
	sm.sky_curve = 0.18
	sm.ground_horizon_color = Color(0.72, 0.66, 0.58)
	sm.ground_bottom_color = Color(0.3, 0.28, 0.25)
	sm.sun_angle_max = 10.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.72) # blue sky fill in the shadows
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.76, 0.68)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("FFF1DC")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = Vector3(-35, -45, 0) # 4 pm: 35 degrees up in the south-west, shining north-east
	add_child(sun)


# ---------------------------------------------------------------- the Seine

static func river_z(x: float) -> float:
	if _rz.is_empty():
		_rz.resize(701)
		for i in 701:
			_rz[i] = _river_spline(float(i) - 350.0)
	var f := clampf(x + 350.0, 0.0, 699.999)
	var i := int(f)
	return lerpf(_rz[i], _rz[i + 1], f - i)


static func _river_spline(x: float) -> float:
	var c: Array = RIVER_CTRL
	var i := 0
	while i < c.size() - 2 and x > (c[i + 1] as Vector2).x:
		i += 1
	var p0: Vector2 = c[maxi(i - 1, 0)]
	var p1: Vector2 = c[i]
	var p2: Vector2 = c[i + 1]
	var p3: Vector2 = c[mini(i + 2, c.size() - 1)]
	var t := clampf((x - p1.x) / (p2.x - p1.x), 0.0, 1.0)
	var m1 := (p2.y - p0.y) / maxf(p2.x - p0.x, 1.0) * (p2.x - p1.x)
	var m2 := (p3.y - p1.y) / maxf(p3.x - p1.x, 1.0) * (p2.x - p1.x)
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * p1.y + (t3 - 2 * t2 + t) * m1 + (-2 * t3 + 3 * t2) * p2.y + (t3 - t2) * m2


## Half width of the Ile de la Cite (0 where there is none): pointed west tip at 168, east tip at 266.
static func island_half(x: float) -> float:
	return 22.0 * smoothstep(168.0, 192.0, x) * (1.0 - smoothstep(248.0, 266.0, x))


static func water_half(x: float) -> float:
	return WATER_HALF + island_half(x)


## Lower quay width: none along the island (the walls go straight down to the water there).
static func quay_w(x: float) -> float:
	return QUAY_W * (1.0 - smoothstep(146.0, 166.0, x))


## Lower quay height: down a ramp in the west, up a ramp before the island.
static func quay_y(x: float) -> float:
	if x < -222.0:
		return QUAY_Y * smoothstep(-262.0, -222.0, x)
	if x > 100.0:
		return QUAY_Y * (1.0 - smoothstep(100.0, 144.0, x))
	return QUAY_Y


static func outer_half(x: float) -> float:
	return water_half(x) + quay_w(x)


## Half width of the whole river corridor: trench, promenade, quay road, sidewalk.
static func corridor_half(x: float) -> float:
	return outer_half(x) + PROMENADE + QUAY_ROAD_W + SIDEWALK


func _under_bridge(x: float, side: float, margin := 0.6) -> bool:
	for b: Dictionary in BRIDGES:
		if absf(x - b.x) < b.w * 0.5 + margin:
			if b.spans == "full" or b.spans == "island" or (b.spans == "north" and side < 0) or (b.spans == "south" and side > 0):
				return true
	return false


func _river() -> void:
	var n := int((2.0 * HX) / STEP)
	var xs := PackedFloat32Array()
	for i in n + 1:
		xs.append(-HX + i * STEP)
	# Ground of both banks: columns from the map edge to the trench, in 25 m pieces.
	for i in n:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var zc0 := river_z(x0)
		var zc1 := river_z(x1)
		for side: float in [-1.0, 1.0]:
			var e0 := zc0 + side * outer_half(x0)
			var e1 := zc1 + side * outer_half(x1)
			var far := side * HZ
			var pieces := 8
			for k in pieces:
				var u0 := float(k) / pieces
				var u1 := float(k + 1) / pieces
				face(_m.sidewalk, [Vector3(x0, 0, lerpf(far, e0, u0)), Vector3(x1, 0, lerpf(far, e1, u0)),
					Vector3(x1, 0, lerpf(far, e1, u1)), Vector3(x0, 0, lerpf(far, e0, u1))], Vector3.UP, false, COL_GROUND)
	# The trench, column by column.
	for i in n:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var zc0 := river_z(x0)
		var zc1 := river_z(x1)
		var q0 := quay_y(x0)
		var q1 := quay_y(x1)
		var w0 := water_half(x0)
		var w1 := water_half(x1)
		var o0 := outer_half(x0)
		var o1 := outer_half(x1)
		var ih0 := island_half(x0)
		var ih1 := island_half(x1)
		var xm := (x0 + x1) * 0.5
		face(_m.water, [Vector3(x0, WATER_Y, zc0 - w0), Vector3(x1, WATER_Y, zc1 - w1), Vector3(x1, WATER_Y, zc1 + w1),
			Vector3(x0, WATER_Y, zc0 + w0)], Vector3.UP, false)
		for side: float in [-1.0, 1.0]:
			var out := Vector3(0, 0, -side) # walls on this side face the river
			var wz0 := zc0 + side * w0
			var wz1 := zc1 + side * w1
			var oz0 := zc0 + side * o0
			var oz1 := zc1 + side * o1
			if o0 - w0 > 0.05 or o1 - w1 > 0.05:
				face(_m.cobble, [Vector3(x0, q0, wz0), Vector3(x1, q1, wz1), Vector3(x1, q1, oz1), Vector3(x0, q0, oz0)],
					Vector3.UP, false, COL_GROUND)
			if q0 < -0.01 or q1 < -0.01:
				face(_m.quay, [Vector3(x0, q0, oz0), Vector3(x1, q1, oz1), Vector3(x1, 0, oz1), Vector3(x0, 0, oz0)], out, true, COL_WALL)
			# The quay's edge down into the water.
			var top0 := q0 if o0 - w0 > 0.05 else 0.0
			var top1 := q1 if o1 - w1 > 0.05 else 0.0
			face(_m.quay, [Vector3(x0, WATER_Y - 0.3, wz0), Vector3(x1, WATER_Y - 0.3, wz1), Vector3(x1, top1, wz1),
				Vector3(x0, top0, wz0)], out, false)
			# Stone coping between the trench and the quay road.
			var pz0 := oz0 + side * PROMENADE
			var pz1 := oz1 + side * PROMENADE
			face(_m.plaza, [Vector3(x0, 0.03, oz0), Vector3(x1, 0.03, oz1), Vector3(x1, 0.03, pz1), Vector3(x0, 0.03, pz0)], Vector3.UP, false)
			# Quay road.
			var rz0 := pz0 + side * QUAY_ROAD_W
			var rz1 := pz1 + side * QUAY_ROAD_W
			face(_m.asphalt, [Vector3(x0, 0.04, pz0), Vector3(x1, 0.04, pz1), Vector3(x1, 0.04, rz1), Vector3(x0, 0.04, rz0)], Vector3.UP, false)
			# Parapets: on the bank where the drop to the lower quay is real, on every water edge.
			if 0.0 - (q0 + q1) * 0.5 > 1.0 and not _under_bridge(xm, side):
				_parapet_piece(x0, x1, oz0, oz1, 0.0, 0.0, side)
			_parapet_piece(x0, x1, wz0, wz1, top0, top1, -side)
			# Island: top, its walls, its parapet.
			if ih0 > 0.05 or ih1 > 0.05:
				var iz0 := zc0 + side * ih0
				var iz1 := zc1 + side * ih1
				face(_m.plaza, [Vector3(x0, 0, zc0), Vector3(x1, 0, zc1), Vector3(x1, 0, iz1), Vector3(x0, 0, iz0)], Vector3.UP, false, COL_GROUND)
				face(_m.quay, [Vector3(x0, WATER_Y - 0.3, iz0), Vector3(x1, WATER_Y - 0.3, iz1), Vector3(x1, 0, iz1), Vector3(x0, 0, iz0)],
					Vector3(0, 0, side), false)
				if not _bridge_lands(xm, side):
					_parapet_piece(x0, x1, iz0 - side * 0.5, iz1 - side * 0.5, 0.0, 0.0, side)
	# Cars-only walls over every water edge: nobody falls in (design 32), missiles fly over.
	_water_barriers(xs)


## Does a bridge land on the island's edge here?
func _bridge_lands(x: float, side: float) -> bool:
	for b: Dictionary in BRIDGES:
		if absf(x - b.x) < b.w * 0.5 + 0.6:
			if b.spans == "island" or (b.spans == "north" and side < 0) or (b.spans == "south" and side > 0):
				return true
	return false


## One 2.5 m piece of a stone parapet whose inner face is at z0/z1, standing toward `toward` (+1 south).
func _parapet_piece(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, toward: float) -> void:
	var t := 0.5 * toward
	var h := PARAPET_H
	var a0 := Vector3(x0, y0, z0)
	var a1 := Vector3(x1, y1, z1)
	var b0 := Vector3(x0, y0, z0 + t)
	var b1 := Vector3(x1, y1, z1 + t)
	var up := Vector3(0, h, 0)
	face(_m.stone, [a0, a1, a1 + up, a0 + up], Vector3(0, 0, -toward), true, COL_WALL)
	face(_m.stone, [b0, b1, b1 + up, b0 + up], Vector3(0, 0, toward), true, COL_WALL)
	face(_m.stone, [a0 + up, a1 + up, b1 + up, b0 + up], Vector3.UP, true, COL_WALL)


func _water_barriers(xs: PackedFloat32Array) -> void:
	var body := StaticBody3D.new()
	body.name = "WaterBarrier"
	body.collision_layer = VEHICLE_BARRIER_LAYER
	body.collision_mask = 0
	add_child(body)
	for i in range(0, xs.size() - 4, 4):
		var x0 := xs[i]
		var x1 := xs[i + 4]
		for side: float in [-1.0, 1.0]:
			var edges := [water_half(x0) - 0.6, water_half(x1) - 0.6]
			var ys := [quay_y(x0) if quay_w(x0) > 0.05 else 0.0, quay_y(x1) if quay_w(x1) > 0.05 else 0.0]
			_barrier_box(body, Vector3(x0, ys[0], river_z(x0) + side * edges[0]), Vector3(x1, ys[1], river_z(x1) + side * edges[1]))
			if island_half(x0) > 1.0 and island_half(x1) > 1.0:
				_barrier_box(body, Vector3(x0, 0, river_z(x0) + side * (island_half(x0) + 0.6)),
					Vector3(x1, 0, river_z(x1) + side * (island_half(x1) + 0.6)))


func _barrier_box(body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	box.size = Vector3(flat.length() + 0.5, 14.0, 1.0)
	cs.shape = box
	var mid := (a + b) * 0.5
	cs.transform = Transform3D(Basis(Vector3.UP, atan2(-flat.z, flat.x)), Vector3(mid.x, minf(a.y, b.y) + 7.0, mid.z))
	body.add_child(cs)


# ---------------------------------------------------------------- bridges

func _bridges() -> void:
	for b: Dictionary in BRIDGES:
		var bx: float = b.x
		var zc := river_z(bx)
		var o := outer_half(bx) + 3.0
		var ih := island_half(bx)
		var spans: Array = []
		match String(b.spans):
			"full":
				spans = [[-o, o]]
			"island":
				spans = [[-o, -ih + 3.0], [ih - 3.0, o]]
			"north":
				spans = [[-o, -ih + 3.0]]
			"south":
				spans = [[ih - 3.0, o]]
		for sp: Array in spans:
			_bridge_span(bx, b.w, zc + float(sp[0]), zc + float(sp[1]), b.h)
		if b.name == "alexandre":
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var p := Vector3(bx + sx * (b.w * 0.5 + 1.4), 0, zc + sz * (outer_half(bx) + 1.25))
					var mb := MeshBuilder.new()
					mb.box(_m.stone, Vector3(2.4, 13.0, 2.4), Transform3D(Basis(), p + Vector3(0, 6.5, 0)), 0.08)
					mb.box(_m.stone, Vector3(3.0, 1.2, 3.0), Transform3D(Basis(), p + Vector3(0, 0.6, 0)), 0.06)
					mb.box(_m.gold, Vector3(1.6, 2.6, 1.6), Transform3D(Basis(), p + Vector3(0, 14.3, 0)), 0.2)
					batch_builder(mb)
					solid(Vector3(2.4, 14.0, 2.4), Transform3D(Basis(), p + Vector3(0, 7.0, 0)))


## One arched span from z0 to z1 at bx: deck (asphalt, drivable), stone fascias, balustrades, piers.
func _bridge_span(bx: float, w: float, z0: float, z1: float, hump: float) -> void:
	var xa := bx - w * 0.5
	var xb := bx + w * 0.5
	var steps := maxi(4, int((z1 - z0) / 2.0))
	var zs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for k in steps + 1:
		var z := lerpf(z0, z1, float(k) / steps)
		var s := (z - (z0 + z1) * 0.5) / ((z1 - z0) * 0.5)
		zs.append(z)
		ys.append(hump * pow(1.0 - s * s, 2.0))
	for k in steps:
		var a := ys[k] + 0.04
		var c := ys[k + 1] + 0.04
		face(_m.asphalt, [Vector3(xa, a, zs[k]), Vector3(xb, a, zs[k]), Vector3(xb, c, zs[k + 1]), Vector3(xa, c, zs[k + 1])],
			Vector3.UP, false)
		face(_m.asphalt, [Vector3(xa, ys[k], zs[k]), Vector3(xb, ys[k], zs[k]), Vector3(xb, ys[k + 1], zs[k + 1]),
			Vector3(xa, ys[k + 1], zs[k + 1])], Vector3.UP, false, COL_GROUND)
		var depth := 1.3
		for sx: float in [-1.0, 1.0]:
			var x := bx + sx * w * 0.5
			face(_m.stone, [Vector3(x, a, zs[k]), Vector3(x, c, zs[k + 1]), Vector3(x, ys[k + 1] - depth, zs[k + 1]),
				Vector3(x, ys[k] - depth, zs[k])], Vector3(sx, 0, 0), true)
			# Balustrade: a stone rail on the deck's edge (posts read from its top moulding).
			var xi := x - sx * 0.55
			face(_m.stone, [Vector3(xi, a, zs[k]), Vector3(xi, c, zs[k + 1]), Vector3(xi, c + 1.0, zs[k + 1]), Vector3(xi, a + 1.0, zs[k])],
				Vector3(-sx, 0, 0), true, COL_WALL)
			face(_m.stone, [Vector3(x, a + 1.0, zs[k]), Vector3(x, c + 1.0, zs[k + 1]), Vector3(x, c + 1.2, zs[k + 1]), Vector3(x, a + 1.2, zs[k])],
				Vector3(sx, 0, 0), true)
			face(_m.stone, [Vector3(xi - sx * 0.1, a + 1.2, zs[k]), Vector3(xi - sx * 0.1, c + 1.2, zs[k + 1]), Vector3(x, c + 1.2, zs[k + 1]),
				Vector3(x, a + 1.2, zs[k])], Vector3.UP, true)
			face(_m.stone, [Vector3(xi, a + 1.0, zs[k]), Vector3(xi, c + 1.0, zs[k + 1]), Vector3(xi - sx * 0.1, c + 1.2, zs[k + 1]),
				Vector3(xi - sx * 0.1, a + 1.2, zs[k])], Vector3(-sx, 1, 0), true)
		face(_m.stone, [Vector3(xa, ys[k] - depth, zs[k]), Vector3(xb, ys[k] - depth, zs[k]), Vector3(xb, ys[k + 1] - depth, zs[k + 1]),
			Vector3(xa, ys[k + 1] - depth, zs[k + 1])], Vector3.DOWN, false)
	# Piers in the water at both water edges and, for wide spans, in the middle.
	var zc := river_z(bx)
	var wh := water_half(bx)
	var ih := island_half(bx)
	var piers: Array[float] = []
	for side: float in [-1.0, 1.0]:
		var pz := zc + side * (wh - 1.8)
		if pz > z0 and pz < z1:
			piers.append(pz)
		if ih > 3.0:
			var iz := zc + side * (ih + 1.8)
			if iz > z0 and iz < z1:
				piers.append(iz)
	if ih < 3.0 and zc > z0 and zc < z1:
		piers.append(zc)
	for pz: float in piers:
		var mb := MeshBuilder.new()
		var top := hump * 0.6 - 1.3
		mb.box(_m.quay, Vector3(w + 1.0, top - WATER_Y + 0.5, 3.4), Transform3D(Basis(), Vector3(bx, (top + WATER_Y - 0.5) * 0.5, pz)), 0.15)
		batch_builder(mb)


# ---------------------------------------------------------------- roads

func _layout_roads() -> void:
	var e := ETOILE
	var star := {
		"champs": [Vector2(42, -80), 24.0],
		"kleber": [Vector2(-206, -70), 18.0],
		"marceau": [Vector2(-118, 14), 18.0],
		"george_v": [Vector2(-52, 12), 18.0],
		"grande_armee": [Vector2(-290, -150), 18.0],
		"wagram": [Vector2(-150, -240), 18.0],
		"friedland": [Vector2(-40, -240), 18.0],
	}
	for k: String in star:
		var to: Vector2 = star[k][0]
		var dir := (to - e).normalized()
		roads.append({"name": k, "pts": PackedVector2Array([e + dir * (RING_R - 2.0), to]), "w": star[k][1]})
	# North bank streets
	_road("francois_1er", [Vector2(-206, -38), Vector2(-150, -48), Vector2(-96, -56), Vector2(-42, -62)], 14.0)
	_road("galilee", [Vector2(-214, -96), Vector2(-150, -104), Vector2(-80, -106), Vector2(-14, -104)], 14.0)
	_road("rivoli", [Vector2(42, -128), Vector2(290, -128)], 18.0)
	_road("royale", [Vector2(82, -114), Vector2(82, -240)], 16.0)
	_road("haussmann", [Vector2(-40, -186), Vector2(30, -186)], 16.0)
	_road("opera_av", [Vector2(60, -150), Vector2(150, -128)], 16.0)
	_road("concorde_s", [Vector2(42, -46), Vector2(178, -46)], 16.0)
	_road("gp_east", [Vector2(42, -114), Vector2(42, 12)], 16.0)
	_road("tuileries_w", [Vector2(122, -114), Vector2(122, -46)], 12.0)
	_road("louvre_w", [Vector2(178, -128), Vector2(178, 12)], 14.0)
	_road("clichy", [Vector2(150, -150), Vector2(150, -128)], 14.0)
	# South bank
	_road("iena_s", [Vector2(-190, 90), Vector2(-190, 240)], 18.0)
	_road("champ_x", [Vector2(-290, 180), Vector2(-60, 180)], 16.0)
	_road("bourdonnais", [Vector2(-80, 90), Vector2(-80, 240)], 16.0)
	_road("invalides_bd", [Vector2(69, 80), Vector2(69, 240)], 16.0)
	_road("st_germain", [Vector2(60, 132), Vector2(150, 140), Vector2(290, 152)], 16.0)
	_road("st_germain_s", [Vector2(60, 196), Vector2(290, 196)], 12.0)
	for ax: float in [112.0, 205.0, 250.0]:
		_road("alley_%d" % ax, [Vector2(ax, 100), Vector2(ax, 240)], 12.0)
	_road("alley_160", [Vector2(160, 141), Vector2(160, 240)], 12.0)


func _road(name: String, pts: Array, w: float) -> void:
	roads.append({"name": name, "pts": PackedVector2Array(pts), "w": w})


func _draw_roads() -> void:
	var all: Array[PackedVector2Array] = []
	for r: Dictionary in roads:
		var w: float = r.w
		for piece: PackedVector2Array in Geometry2D.offset_polyline(r.pts, w * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
			if not Geometry2D.is_polygon_clockwise(piece):
				var clipped := _clip_to_map(piece)
				for c: PackedVector2Array in clipped:
					poly_face(_m.asphalt, c, 0.04)
					all.append(c)
	# Etoile: the ring and its island (the Arc stands there, phase 3).
	var ring := PackedVector2Array()
	for k in 64:
		var a := TAU * k / 64.0
		ring.append(ETOILE + Vector2(cos(a), sin(a)) * RING_R)
	band(_m.asphalt, ring, 18.0, 0.045, true)
	var island := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		island.append(ETOILE + Vector2(cos(a), sin(a)) * (RING_R - 9.0))
	poly_face(_m.cobble, island, 0.05)
	_road_polys = all
	# Curbs: granite along every road edge that meets the sidewalk (the ring's outer disk joins the
	# union so its avenues meet it cleanly; the island gets its own curb).
	var merged: Array[PackedVector2Array] = []
	for p in all:
		merged.append(p)
	var disk := PackedVector2Array()
	for k in 64:
		var a := TAU * k / 64.0
		disk.append(ETOILE + Vector2(cos(a), sin(a)) * (RING_R + 9.0))
	merged.append(disk)
	for p in _union(merged):
		band(_m.curb, p, 0.35, 0.05, true)
	band(_m.curb, island, 0.35, 0.06, true)


func _clip_to_map(p: PackedVector2Array) -> Array[PackedVector2Array]:
	var rect := PackedVector2Array([Vector2(-HX, -HZ), Vector2(HX, -HZ), Vector2(HX, HZ), Vector2(-HX, HZ)])
	var out: Array[PackedVector2Array] = []
	for c: PackedVector2Array in Geometry2D.intersect_polygons(p, rect):
		if not Geometry2D.is_polygon_clockwise(c):
			out.append(c)
	return out


func _union(polys: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in polys:
		var cur := p
		var changed := true
		while changed:
			changed = false
			for i in out.size():
				var m := Geometry2D.merge_polygons(cur, out[i])
				if m.size() == 1 or (m.size() > 1 and _area(m[0]) > maxf(_area(cur), _area(out[i])) + 0.1):
					cur = m[0]
					out.remove_at(i)
					changed = true
					break
		out.append(cur)
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


# ---------------------------------------------------------------- parks, plazas, terraces

func _parks() -> void:
	var cdm_n := river_z(-190.0) + corridor_half(-190.0)
	# Champ de Mars: lawns cut by gravel walks, the tower in the middle (phase 2).
	_lawn_rect(-262, cdm_n + 4, -200, 172)
	_lawn_rect(-180, cdm_n + 4, -90, 172)
	_lawn_rect(-262, 188, -200, HZ - 6)
	_lawn_rect(-180, 188, -90, HZ - 6)
	poly_face(_m.gravel, _rect(-272, cdm_n, -86, HZ), 0.02)
	# Invalides esplanade + the court of the dome.
	var inv_n := river_z(0.0) + corridor_half(0.0)
	_lawn_rect(-50, inv_n + 6, -6, 166)
	_lawn_rect(6, inv_n + 6, 50, 166)
	poly_face(_m.gravel, _rect(-60, inv_n, 60, 170), 0.02)
	poly_face(_m.plaza, _rect(-46, 170, 46, HZ), 0.03)
	# Concorde: one big stone square.
	poly_face(_m.plaza, _rect(50, -106, 114, -54), 0.03)
	# Tuileries: gravel with lawn beds.
	poly_face(_m.gravel, _rect(128, -120, 172, -52), 0.02)
	for bz: float in [-112.0, -90.0, -68.0]:
		_lawn_rect(131, bz, 147, bz + 14)
		_lawn_rect(153, bz, 169, bz + 14)
	# Louvre's Cour Napoleon (pyramid phase 3) and the Grand Palais forecourt.
	poly_face(_m.plaza, _rect(184, -120, 272, -18), 0.03)
	poly_face(_m.plaza, _rect(-34, -58, 34, -6), 0.03)
	# Trocadero gardens below the terraces.
	_lawn_rect(-268, -14, -252, river_z(-240) - corridor_half(-240) - 2)
	_lawn_rect(-228, -14, -212, river_z(-240) - corridor_half(-240) - 2)


func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


func _lawn_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	if z1 - z0 < 2.0 or x1 - x0 < 2.0:
		return
	poly_face(_m.lawn, _rect(x0, z0, x1, z1), 0.06)
	band(_m.curb, _rect(x0, z0, x1, z1), 0.3, 0.07, true)


## A raised plateau: drivable top, stone retaining walls with a coping, colliders.
func _plateau(poly: PackedVector2Array, h: float, top_mat: Material) -> void:
	poly_face(top_mat, poly, h, false, COL_GROUND)
	var ccw := not Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var out := Vector3(d.y, 0, -d.x) if ccw else Vector3(-d.y, 0, d.x)
		face(_m.quay, [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)], out, true, COL_WALL)
	band(_m.stone, poly, 0.6, h + 0.02, true)


## A straight ramp from foot (y0) to top (y1), width w; registered for the AI.
func _ramp(foot: Vector2, top: Vector2, y0: float, y1: float, w: float, mat: Material) -> void:
	var d := (top - foot).normalized()
	var l := Vector2(-d.y, d.x) * w * 0.5
	var steps := 8
	for k in steps:
		var u0 := float(k) / steps
		var u1 := float(k + 1) / steps
		var p0 := foot.lerp(top, u0)
		var p1 := foot.lerp(top, u1)
		var h0 := lerpf(y0, y1, smoothstep(0.0, 1.0, u0) * 0.3 + u0 * 0.7)
		var h1 := lerpf(y0, y1, smoothstep(0.0, 1.0, u1) * 0.3 + u1 * 0.7)
		face(mat, [Vector3(p0.x + l.x, h0, p0.y + l.y), Vector3(p1.x + l.x, h1, p1.y + l.y), Vector3(p1.x - l.x, h1, p1.y - l.y),
			Vector3(p0.x - l.x, h0, p0.y - l.y)], Vector3.UP, false, COL_GROUND)
		for s: float in [-1.0, 1.0]:
			var e0 := p0 + l * s
			var e1 := p1 + l * s
			face(_m.quay, [Vector3(e0.x, minf(y0, y1), e0.y), Vector3(e1.x, minf(y0, y1), e1.y), Vector3(e1.x, h1, e1.y), Vector3(e0.x, h0, e0.y)],
				Vector3(l.x * s, 0, l.y * s), true, COL_WALL)
	ramps.append({"foot": Vector3(foot.x, y0, foot.y), "top": Vector3(top.x, y1, top.y), "w": w})


func _terraces() -> void:
	# Trocadero: three terraces up to +8 m below the Palais de Chaillot, ramps either side of the fountains.
	_plateau(_rect(-272, -88, -208, -62), 8.0, _m.plaza)
	_plateau(_rect(-272, -62, -208, -40), 5.0, _m.plaza)
	_plateau(_rect(-272, -40, -208, -18), 2.5, _m.plaza)
	for rx: float in [-258.0, -222.0]:
		_ramp(Vector2(rx, 4), Vector2(rx, -18), 0.0, 2.5, 10.0, _m.plaza)
		_ramp(Vector2(rx, -18), Vector2(rx, -40), 2.5, 5.0, 10.0, _m.plaza)
		_ramp(Vector2(rx, -40), Vector2(rx, -62), 5.0, 8.0, 10.0, _m.plaza)


func _montmartre() -> void:
	var c := MONT
	_plateau(_rect(c.x - MONT_LOW, c.y - MONT_LOW, c.x + MONT_LOW, c.y + MONT_LOW), 7.0, _m.lawn)
	_plateau(_rect(c.x - MONT_TOP, c.y - MONT_TOP, c.x + MONT_TOP, c.y + MONT_TOP), 14.0, _m.plaza)
	# Up from the Moulin Rouge side, then along the south face to the top.
	_ramp(Vector2(c.x - MONT_LOW - 40.0, c.y + 20.0), Vector2(c.x - MONT_LOW, c.y + 20.0), 0.0, 7.0, 12.0, _m.cobble)
	_ramp(Vector2(c.x + 34.0, c.y + MONT_TOP + 8.0), Vector2(c.x - 4.0, c.y + MONT_TOP + 8.0), 7.0, 14.0, 12.0, _m.cobble)
	poly_face(_m.cobble, _rect(c.x - MONT_TOP, c.y + MONT_TOP + 2.0, c.x - 4.0, c.y + MONT_TOP + 14.0), 14.0, false, COL_GROUND)


# ---------------------------------------------------------------- city blocks

## Urban zones minus roads, plazas, parks and landmarks = the blocks (pan coupe corners).
func _city_blocks() -> void:
	var zones: Array[PackedVector2Array] = [_rect(-HX, -HZ, HX, HZ)]
	var cut: Array[PackedVector2Array] = []
	cut.append(_corridor())
	var ring := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		ring.append(ETOILE + Vector2(cos(a), sin(a)) * (RING_R + 9.0 + SIDEWALK))
	cut.append(ring)
	for r: Dictionary in roads:
		for piece: PackedVector2Array in Geometry2D.offset_polyline(r.pts, float(r.w) * 0.5 + SIDEWALK, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
			if not Geometry2D.is_polygon_clockwise(piece):
				cut.append(piece)
	cut.append(_rect(-280, -92, -204, 20)) # Trocadero
	cut.append(_rect(-40, -62, 40, 10)) # Grand Palais
	cut.append(_rect(-4, -114, 46, -58)) # Champs-Elysees gardens (the roof ramp comes down here)
	cut.append(_rect(46, -110, 118, -50)) # Concorde
	cut.append(_rect(126, -122, 174, -50)) # Tuileries
	cut.append(_rect(182, -122, 280, -16)) # Louvre (the building comes in phase 3)
	cut.append(_rect(MONT.x - MONT_LOW - 44.0, MONT.y - MONT_LOW - 4.0, 280, MONT.y + MONT_LOW + 4.0)) # Montmartre
	cut.append(_rect(-280, 60, -84, 240)) # Champ de Mars
	cut.append(_rect(-62, 60, 62, 240)) # Invalides
	cut.append(_rect(30, -205, 90, -160)) # Opera (phase 3)
	for c in cut:
		var next: Array[PackedVector2Array] = []
		for z in zones:
			next.append_array(_cut(z, c, 0))
		zones = next
	zones = _union(zones) # pieces split round a hole join up again (no facade down the middle of a block)
	for z in zones:
		if _area(z) < 500.0:
			continue
		var core := Geometry2D.offset_polygon(z, -5.0, Geometry2D.JOIN_MITER)
		if core.is_empty():
			continue
		for inner: PackedVector2Array in Geometry2D.offset_polygon(z, -2.5, Geometry2D.JOIN_MITER):
			for b: PackedVector2Array in Geometry2D.offset_polygon(inner, 2.5, Geometry2D.JOIN_SQUARE):
				if Geometry2D.is_polygon_clockwise(b) or _area(b) < 400.0:
					continue
				var cen := _centroid(b)
				var roof := cen.x > -212.0 and cen.x < -14.0 and cen.y > -140.0 and cen.y < 20.0
				blocks.append({"poly": _simplify(b), "roof": roof, "h": ROOF_Y if roof else TALL_Y})


## zone minus cutter. A cutter wholly inside the zone would leave a hole (which a block can't have):
## then the zone is split through the cutter first, so each half has the cut on its edge.
func _cut(zone: PackedVector2Array, cutter: PackedVector2Array, depth: int) -> Array[PackedVector2Array]:
	var res := Geometry2D.clip_polygons(zone, cutter)
	var outers: Array[PackedVector2Array] = []
	var holes := false
	for piece: PackedVector2Array in res:
		if Geometry2D.is_polygon_clockwise(piece):
			holes = true
		else:
			outers.append(piece)
	if not holes or depth > 3:
		return outers
	var cx := _centroid(cutter).x
	var out: Array[PackedVector2Array] = []
	for half: PackedVector2Array in [_rect(-1000, -1000, cx, 1000), _rect(cx, -1000, 1000, 1000)]:
		for part: PackedVector2Array in Geometry2D.intersect_polygons(zone, half):
			if not Geometry2D.is_polygon_clockwise(part):
				out.append_array(_cut(part, cutter, depth + 1))
	return out


func _corridor() -> PackedVector2Array:
	var north := PackedVector2Array()
	var south := PackedVector2Array()
	var x := -HX - 30.0
	while x <= HX + 30.0:
		north.append(Vector2(x, river_z(x) - corridor_half(x)))
		south.append(Vector2(x, river_z(x) + corridor_half(x)))
		x += 5.0
	south.reverse()
	north.append_array(south)
	return north


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / p.size()


## Drop points closer than 1.5 m and nearly straight runs (round joins leave many tiny edges).
static func _simplify(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 1.5:
			out.append(v)
	if out.size() > 3 and out[0].distance_to(out[out.size() - 1]) < 1.5:
		out.remove_at(out.size() - 1)
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for i in out.size():
			var a := out[(i - 1 + out.size()) % out.size()]
			var b := out[i]
			var c := out[(i + 1) % out.size()]
			if absf((b - a).normalized().cross((c - b).normalized())) < 0.03:
				out.remove_at(i)
				changed = true
				break
	return out


# ---------------------------------------------------------------- rooftops (TM2's legacy)

## The quarter's roofs are one circuit: up from the Trocadero, across the streets on steel bridges,
## down a ramp into the Champs-Elysees gardens.
const CROSSINGS := [
	[Vector2(-185, -57), Vector2(-185, -29)], # over Rue Francois 1er
	[Vector2(-139, -15), Vector2(-108, -15)], # over Avenue Marceau
	[Vector2(-81, -26), Vector2(-62, -26)], # over Avenue George V
	[Vector2(-55, -67), Vector2(-55, -45)], # over Rue Francois 1er, east
]


func _rooftops() -> void:
	var steel := MatKit.steel(Color("2A2E2A"), 0.35)
	_viaduct(Vector2(-234, -72), Vector2(-199, -72), 8.0, ROOF_Y, 10.0, steel)
	_ramp(Vector2(40, -80), Vector2(-10, -80), 0.0, ROOF_Y, 12.0, _m.quay)
	for c: Array in CROSSINGS:
		_viaduct(c[0], c[1], ROOF_Y, ROOF_Y, 8.0, steel)
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		ramps.append({"foot": Vector3(a.x, ROOF_Y, a.y), "top": Vector3(b.x, ROOF_Y, b.y), "w": 8.0})
	poly_face(_m.lawn, _rect(-2, -108, 38, -96), 0.06)
	poly_face(_m.lawn, _rect(-2, -64, 38, -56), 0.06)


## A steel deck on lattice side girders from a to b (heights y0 -> y1), on two legs; drivable.
func _viaduct(a: Vector2, b: Vector2, y0: float, y1: float, w: float, steel: Material) -> void:
	var d := (b - a).normalized()
	var l := Vector2(-d.y, d.x) * w * 0.5
	var mb := MeshBuilder.new()
	var len := a.distance_to(b)
	var yaw := atan2(-d.y, d.x)
	var pitch := atan2(y1 - y0, len)
	var mid := (a + b) * 0.5
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	var center := Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
	mb.box(steel, Vector3(len, 0.5, w), Transform3D(basis, center + Vector3(0, -0.25, 0)), 0.04)
	for s: float in [-1.0, 1.0]:
		var side := Vector3(l.x, 0, l.y) * s
		mb.box(steel, Vector3(len, 0.18, 0.3), Transform3D(basis, center + side + Vector3(0, 1.3, 0)), 0.02)
		mb.box(steel, Vector3(len, 0.6, 0.3), Transform3D(basis, center + side + Vector3(0, -0.1, 0)), 0.02)
		var n := int(len / 1.6)
		for k in n + 1:
			var t := float(k) / n - 0.5
			var p := center + Vector3(d.x, 0, d.y) * t * len + Vector3(0, (y1 - y0) * t, 0) + side
			mb.box(steel, Vector3(0.14, 1.4, 0.14), Transform3D(basis * Basis(Vector3.BACK, 0.55 if k % 2 == 0 else -0.55), p + Vector3(0, 0.6, 0)), 0.0)
	batch_builder(mb, true)
	var pa := Vector3(a.x, y0, a.y)
	var pb := Vector3(b.x, y1, b.y)
	var lv := Vector3(l.x, 0, l.y)
	face(steel, [pa + lv, pb + lv, pb - lv, pa - lv], Vector3.UP, false, COL_GROUND)
	for s: float in [-1.0, 1.0]:
		face(steel, [pa + lv * s, pb + lv * s, pb + lv * s + Vector3(0, 1.4, 0), pa + lv * s + Vector3(0, 1.4, 0)], lv * s, false, COL_WALL)
	if y0 > 1.0 or y1 > 1.0:
		ramps.append({"foot": pa, "top": pb, "w": w})


# ---------------------------------------------------------------- boundary

func _boundary() -> void:
	# Walls round the map (the city beyond is the backdrop); barricades close every road that leaves it.
	for s: Array in [[Vector3(0, 10, -HZ - 1), Vector3(2 * HX + 4, 40, 2)], [Vector3(0, 10, HZ + 1), Vector3(2 * HX + 4, 40, 2)],
			[Vector3(-HX - 1, 10, 0), Vector3(2, 40, 2 * HZ + 4)], [Vector3(HX + 1, 10, 0), Vector3(2, 40, 2 * HZ + 4)]]:
		solid(s[1], Transform3D(Basis(), s[0]))
	var mb := MeshBuilder.new()
	var concrete := MatKit.paint(Color(0.58, 0.56, 0.52), 0.35, 0.05, 0.5, 2.0, 0.2, 31)
	var steel := MatKit.steel(Color(0.28, 0.24, 0.2), 0.6)
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		for end: Vector2 in [pts[0], pts[pts.size() - 1]]:
			if absf(end.x) < HX - 1.0 and absf(end.y) < HZ - 1.0:
				continue
			var along := Vector2(1, 0) if absf(end.y) >= HZ - 1.0 else Vector2(0, 1)
			var p := Vector2(clampf(end.x, -HX + 1.5, HX - 1.5), clampf(end.y, -HZ + 1.5, HZ - 1.5))
			var w: float = r.w + 2.0 * SIDEWALK
			var yaw := atan2(-along.y, along.x)
			for k in int(w / 3.2) + 1:
				var t := -w * 0.5 + k * 3.2 + 1.6
				var q := p + along * t
				mb.box(concrete, Vector3(3.0, 1.1, 0.9), Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, 0.55, q.y)), 0.12)
			mb.box(steel, Vector3(w, 2.6, 0.12), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 2.4, p.y) + Vector3(along.y, 0, -along.x) * 0.6), 0.02)
	batch_builder(mb, true, 0.4)


# ---------------------------------------------------------------- gameplay points

func _at(x: float, z: float, yaw_deg: float, y := 0.3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, y, z))


func _points() -> void:
	for t: Transform3D in [_at(82, -80, 90), _at(-150, -125, 0), _at(-190, 204, 90), _at(0, 120, 180), _at(180, 160, 90),
			_at(196, -40, 0), _at(-80, 150, 0)]:
		spawn_points.append(t)
		respawn_points.append(t)
	weapon_points.assign([Vector3(-60, 0.6, river_z(-60) - outer_half(-60) - 10.0), Vector3(60, 0.6, river_z(60) + outer_half(60) + 10.0),
		Vector3(-120, QUAY_Y + 0.6, river_z(-120) - 20.0), Vector3(40, QUAY_Y + 0.6, river_z(40) + 20.0),
		Vector3(-150, 0.6, -134), Vector3(-80, 0.6, -128), Vector3(82, 0.6, -60), Vector3(150, 0.6, -100),
		Vector3(-190, 0.6, 175), Vector3(-130, 0.6, 205), Vector3(0, 0.6, 175), Vector3(112, 0.6, 170),
		Vector3(228, 0.6, 196), Vector3(-240, 8.6, -75), Vector3(MONT.x, 14.6, MONT.y), Vector3(196, 0.6, -100)])
	for i in weapon_points.size():
		weapon_kinds.append("")
	health_points.assign([Vector3(-240, 8.6, -80), Vector3(MONT.x + 8, 14.6, MONT.y), Vector3(-30, 0.6, 150), Vector3(230, 0.6, 130)])
	mega_points.assign([Vector3(0, QUAY_Y + 0.6, river_z(0) - 20.0)])
	turbo_points.assign([Vector3(-150, 0.6, -210), Vector3(-10, 0.6, -95), Vector3(100, 0.6, -128), Vector3(-160, 0.6, 140),
		Vector3(30, 0.6, 196), Vector3(205, 0.6, 120), Vector3(-200, QUAY_Y + 0.6, river_z(-200) + 20.0),
		Vector3(80, QUAY_Y + 0.6, river_z(80) - 20.0)])


# ---------------------------------------------------------------- queries

## The drivable surface under (x, z) (roofs, terraces, bridges, quays), not the tall blocks' tops.
func ground(x: float, z: float, lift := 0.0) -> Vector3:
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z), 1)
		if _buildings:
			q.exclude = [_buildings.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			return (hit.position as Vector3) + Vector3(0, lift, 0)
	return Vector3(x, lift, z)


func level_of(p: Vector3) -> String:
	if p.y < -2.0:
		return "quay"
	if p.y > ROOF_Y - 2.0 and p.x > -215.0 and p.x < -35.0 and p.z < 20.0:
		return "roof"
	if p.y > 1.5:
		if p.x < -200.0:
			return "troca"
		if Vector2(p.x, p.z).distance_to(MONT) < 90.0:
			return "hill"
	return "street"


func buildings_body() -> StaticBody3D:
	if _buildings == null:
		_buildings = StaticBody3D.new()
		_buildings.name = "Buildings"
		_buildings.collision_layer = 1
		_buildings.collision_mask = 0
		add_child(_buildings)
	return _buildings


func radar_lines() -> Array:
	var north := PackedVector2Array()
	var south := PackedVector2Array()
	var x := -HX
	while x <= HX:
		north.append(Vector2(x, river_z(x) - outer_half(x)))
		south.append(Vector2(x, river_z(x) + outer_half(x)))
		x += 10.0
	var wall := PackedVector2Array([Vector2(-HX, -HZ), Vector2(HX, -HZ), Vector2(HX, HZ), Vector2(-HX, HZ), Vector2(-HX, -HZ)])
	return [wall, north, south]


func spot(name: String) -> Transform3D:
	match name:
		"player":
			return spawn_points[0]
	return spawn_points[0]
