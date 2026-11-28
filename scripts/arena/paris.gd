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
const WATER_Y := -5.45 # round 29 (owner): the Seine is shallow, you drive through it to the other bank
const BED_Y := -6.0 # the riverbed under it (0.55 m of water: wheels and sills under, the body above)
const BANK := 2.6 # the cobbled bank from a lower quay down into the water
const QUAY_Y := -5.0
const QUAY_W := 10.0 # lower quay (design 8 m; 10 so Axel's 2.8 m body has room at speed)
const WATER_HALF := 15.0
const PROMENADE := 2.5 # stone coping between the trench and the quay road
const QUAY_ROAD_W := 16.0
const SIDEWALK := 5.0
const ROOF_Y := 13.0 # drivable roofs of the Haussmann quarter (TM2's legacy)
const TALL_Y := 20.4 # the other blocks (not drivable)
const PARAPET_H := 0.9
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
const C_STONE := Color("C9B898") # round 31 (owner: "too bright and white"): was D8C9AC
const C_QUAY := Color("C4B597")
const C_ASPHALT := Color("3A3B3E")
const C_COBBLE := Color("6B6458")
const C_SIDEWALK := Color("A89D88") # round 31: was B9AE98
const C_GRAVEL := Color("CDBA8E")
const C_LAWN := Color("6F8F48")
const C_CURB := Color("8C877E")
const C_ZINC := Color("6F7C86")
const C_GOLD := Color("C9A54A")

const BACKDROP := "res://assets/backdrops/paris_city.jpg"

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
var _splash_t := {} # car -> seconds to its next splash


## Round 30 (owner): the Seine slows nobody. A car in it only throws water up round it.
func _physics_process(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or v.is_dead:
			continue
		var p := v.global_position
		if p.y > WATER_Y + 0.35 or absf(p.z - river_z(p.x)) > water_half(p.x) - 0.3:
			_splash_t.erase(v)
			continue
		var lv := v.linear_velocity
		var sp := Vector2(lv.x, lv.z).length()
		var t: float = float(_splash_t.get(v, 0.0)) - delta
		if t <= 0.0:
			if sp > 2.5:
				FxKit.splash(self, Vector3(p.x, WATER_Y + 0.1, p.z) - Vector3(lv.x, 0, lv.z).normalized() * 1.2, clampf(sp / 12.0, 0.6, 1.4))
			t = 0.14
		_splash_t[v] = t


func build() -> void:
	_materials()
	_environment()
	_river()
	_bridges()
	_quay_ramps()
	_layout_roads()
	_draw_roads()
	_parks()
	_terraces()
	_montmartre()
	_city_blocks()
	ParisBlocks.build(self, blocks)
	ParisLandmarks.build(self)
	_rooftops()
	_boundary()
	_trees()
	_points()
	flush_sheets()
	flush_batch()
	flush_collision()


func _materials() -> void:
	_m.sidewalk = MatKit.pavers(C_SIDEWALK.darkened(0.18), 2.0, 21)
	_m.asphalt = MatKit.pavement("asphalt", C_ASPHALT, 16.0, 22)
	_m.cobble = MatKit.pavers(C_COBBLE, 1.2, 23)
	_m.plaza = MatKit.pavers(Color("A39782"), 6.0, 24) # round 31: was BDB09A (the white squares)
	_m.gravel = MatKit.pavement("concrete", C_GRAVEL, 10.0, 25)
	_m.lawn = MatKit.grass(C_LAWN, 12.0, 26)
	_m.quay = ashlar(C_QUAY, 27)
	_m.stone = ashlar(C_STONE, 28)
	_m.curb = MatKit.flat(C_CURB, 0.85)
	_m.water = _water_material()
	_m.gold = MatKit.flat(C_GOLD, 0.35, 0.8)


## Paris limestone in big dressed blocks (courses 0.6 m, blocks 1.2 m, staggered), thin joints and a
## slightly different tone per block. UVs in metres; one picture = 4.8 m.
static func ashlar(base: Color, seed := 1) -> StandardMaterial3D:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.05
	var tones := {}
	for y in n:
		var row := y / 32
		for x in n:
			var xx := (x + (16 if row % 2 == 1 else 0) * 2) % n
			var col := xx / 64
			var key := row * 8 + col
			if not tones.has(key):
				tones[key] = rng.randf_range(-0.05, 0.05)
			var t: float = tones[key] + noise.get_noise_2d(x, y) * 0.05 + rng.randf_range(-0.015, 0.015)
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			if y % 32 < 2 or xx % 64 < 2:
				c = c.darkened(0.22)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.88
	m.uv1_scale = Vector3.ONE / 4.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Zinc roofing (the roofs you drive on and the flat tops): standing seams every 0.6 m, patina.
static func zinc_roof() -> StandardMaterial3D:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 61
	noise.frequency = 0.02
	var base := C_ZINC
	for y in n:
		for x in n:
			var t := noise.get_noise_2d(x, y) * 0.08 + noise.get_noise_2d(x * 4.0, y * 0.3) * 0.03
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			var sx := x % 43
			if sx < 2:
				c = Color("A7B0B5")
			elif sx == 2:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.55
	m.metallic = 0.35
	m.uv1_scale = Vector3.ONE / 3.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.17, 0.23, 0.21);
uniform vec3 shallow : source_color = vec3(0.25, 0.32, 0.29);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float wave(vec2 p, vec2 d, float f, float s) { return sin(dot(p, d) * f + TIME * s); }
void fragment() {
	vec2 p = wpos.xz;
	float h = wave(p, vec2(0.8, 0.6), 0.9, 1.3) + wave(p, vec2(-0.3, 0.95), 1.7, 1.9) * 0.6 + wave(p, vec2(0.95, -0.2), 3.1, 2.7) * 0.3;
	vec3 n = normalize(vec3(cos(dot(p, vec2(0.8, 0.6)) * 0.9 + TIME * 1.3) * 0.035 + cos(dot(p, vec2(0.95, -0.2)) * 3.1 + TIME * 2.7) * 0.02,
		1.0, cos(dot(p, vec2(-0.3, 0.95)) * 1.7 + TIME * 1.9) * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep, shallow, 0.5 + 0.12 * h);
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# ---------------------------------------------------------------- environment

## Round 32: the owner's pick of four lights (round 31 sheet, panel D): an overcast day. Soft grey light, weak
## shadows, muted colour; the panorama (tools/blender/build_paris_backdrop.py) is rendered under the same sky.
const LOOK := {"exposure": 0.9, "sun": 0.55, "sun_col": Color("E4E8EE"), "amb": Color(0.62, 0.64, 0.68), "amb_e": 1.0,
	"fog": Color(0.6, 0.62, 0.64), "fog_d": 0.0028, "sat": 0.75, "con": 1.06, "sky": Color(0.8, 0.82, 0.86),
	"haze": Color(0.62, 0.64, 0.67), "haze_a": 0.22} # the panorama carries its own haze
const SKY_SHADER := """
shader_type sky;
uniform sampler2D pano : source_color, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform vec3 haze = vec3(0.0);
uniform float haze_amt = 0.0;
void sky() {
	vec3 c = texture(pano, SKY_COORDS).rgb * tint;
	float low = 1.0 - clamp(EYEDIR.y * 2.5, 0.0, 1.0);
	COLOR = mix(c, haze, haze_amt * low * low);
}
"""


func _environment() -> void:
	var md: Dictionary = LOOK
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	# Round 30 (owner: "the map has no background from there"): the city beyond the edge walls, one pre-rendered
	# panorama, its lower part blended into the haze of the day.
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var pano := ShaderMaterial.new()
	pano.shader = sh
	pano.set_shader_parameter("pano", load(BACKDROP))
	var t: Color = md.sky
	var hz: Color = md.haze
	pano.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	pano.set_shader_parameter("haze", Vector3(hz.r, hz.g, hz.b))
	pano.set_shader_parameter("haze_amt", md.haze_a)
	var sky := Sky.new()
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = md.amb # sky fill in the shadows
	env.ambient_light_energy = md.amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = md.exposure
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = md.fog
	env.fog_density = md.fog_d
	env.fog_sky_affect = 0.0
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = md.sat
	env.adjustment_contrast = md.con
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = md.sun_col
	sun.light_energy = md.sun
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


## Round 31 (owner: the channels round the Ile de la Cite were "so narrow", cars hit the walls and the AI stayed
## stuck there all match): each channel is widened by ISLAND_WIDEN of the island's half width (15 -> ~23 m of
## water), the banks and their blocks give way, the island keeps its size.
const ISLAND_WIDEN := 0.35

static func water_half(x: float) -> float:
	return WATER_HALF + island_half(x) * (1.0 + ISLAND_WIDEN)


## Lower quay width. Round 30 (owner: fallen into the water by Notre-Dame there was no way out): the lower
## quays run on past the island (they used to stop, leaving the island's channels walled in on both sides).
static func quay_w(_x: float) -> float:
	return QUAY_W


## Lower quay height: down a ramp in the west; up to the street at x 144 (the old exit) and straight back down
## before Pont Neuf, along the island at -5 (round 30: a way out of the water by Notre-Dame); up again at the east
## end, past Petit Pont so the tallest car clears its deck.
static func quay_y(x: float) -> float:
	if x < -222.0:
		return QUAY_Y * smoothstep(-262.0, -222.0, x)
	if x > 100.0 and x < 144.0:
		return QUAY_Y * (1.0 - smoothstep(100.0, 144.0, x))
	if x >= 144.0 and x < 172.0:
		return QUAY_Y * smoothstep(144.0, 172.0, x)
	if x > 252.0:
		return QUAY_Y * (1.0 - smoothstep(252.0, 275.0, x))
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
		# The riverbed (round 29: drivable, under 0.55 m of water), from bank foot to bank foot.
		face(_m.quay, [Vector3(x0, BED_Y, zc0 - w0 + BANK), Vector3(x1, BED_Y, zc1 - w1 + BANK), Vector3(x1, BED_Y, zc1 + w1 - BANK),
			Vector3(x0, BED_Y, zc0 + w0 - BANK)], Vector3.UP, false, COL_GROUND)
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
			var top0 := q0 if o0 - w0 > 0.05 else 0.0
			var top1 := q1 if o1 - w1 > 0.05 else 0.0
			var fz0 := wz0 - side * BANK # foot of the bank on the riverbed
			var fz1 := wz1 - side * BANK
			if maxf(top0, top1) < -4.0:
				# A lower quay: a cobbled bank slopes down into the water, nothing in the way (owner: cross the river).
				face(_m.cobble, [Vector3(x0, top0, wz0), Vector3(x1, top1, wz1), Vector3(x1, BED_Y, fz1), Vector3(x0, BED_Y, fz0)],
					Vector3(0, 1, -side * 0.6).normalized(), false, COL_GROUND)
			else:
				# Street level straight above the water (along the island): a stone wall and a parapet.
				face(_m.quay, [Vector3(x0, BED_Y - 0.3, fz0), Vector3(x1, BED_Y - 0.3, fz1), Vector3(x1, BED_Y, fz1),
					Vector3(x0, BED_Y, fz0)], out, false)
				face(_m.quay, [Vector3(x0, BED_Y - 0.3, wz0), Vector3(x1, BED_Y - 0.3, wz1), Vector3(x1, top1, wz1),
					Vector3(x0, top0, wz0)], out, false, COL_WALL)
				face(_m.quay, [Vector3(x0, BED_Y, fz0), Vector3(x1, BED_Y, fz1), Vector3(x1, BED_Y, wz1), Vector3(x0, BED_Y, wz0)],
					Vector3.UP, false, COL_GROUND)
				if not _under_bridge(xm, side):
					_parapet_piece(x0, x1, wz0, wz1, top0, top1, -side)
			# Stone coping between the trench and the quay road.
			var pz0 := oz0 + side * PROMENADE
			var pz1 := oz1 + side * PROMENADE
			face(_m.plaza, [Vector3(x0, 0.03, oz0), Vector3(x1, 0.03, oz1), Vector3(x1, 0.03, pz1), Vector3(x0, 0.03, pz0)], Vector3.UP, false)
			# Quay road.
			var rz0 := pz0 + side * QUAY_ROAD_W
			var rz1 := pz1 + side * QUAY_ROAD_W
			face(_m.asphalt, [Vector3(x0, 0.04, pz0), Vector3(x1, 0.04, pz1), Vector3(x1, 0.04, rz1), Vector3(x0, 0.04, rz0)], Vector3.UP, false)
			# Parapet on the bank where the drop to the lower quay is real.
			if 0.0 - (q0 + q1) * 0.5 > 1.0 and not _under_bridge(xm, side):
				_parapet_piece(x0, x1, oz0, oz1, 0.0, 0.0, side)
			# Island: top, its walls (solid now that cars wade round it), its parapet.
			if ih0 > 0.05 or ih1 > 0.05:
				var iz0 := zc0 + side * ih0
				var iz1 := zc1 + side * ih1
				face(_m.plaza, [Vector3(x0, 0, zc0), Vector3(x1, 0, zc1), Vector3(x1, 0, iz1), Vector3(x0, 0, iz0)], Vector3.UP, false, COL_GROUND)
				face(_m.quay, [Vector3(x0, BED_Y - 0.3, iz0), Vector3(x1, BED_Y - 0.3, iz1), Vector3(x1, 0, iz1), Vector3(x0, 0, iz0)],
					Vector3(0, 0, side), false, COL_WALL)
				if not _bridge_lands(xm, side):
					_parapet_piece(x0, x1, iz0 - side * 0.5, iz1 - side * 0.5, 0.0, 0.0, side)


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
	# Piers in the water at both water edges and, for wide spans, in the middle. Round 30: the lower quays run under
	# every bridge now, so each pier follows its bank or the island's edge over the bridge's width (a straight block
	# placed by the bridge's centre stood out onto the quay where the island widens: Pont Neuf, Petit Pont).
	var top := hump * 0.6 - 1.3
	var x0 := xa - 0.5
	var x1 := xb + 0.5
	var ih := island_half(bx)
	for side: float in [-1.0, 1.0]:
		# Round 31: only the bank's pier (slim); the deck rests on the island's own wall on the island side (that
		# pier stood 3.4 m out into the channel and closed the passage under the bridge).
		_pier(x0, x1, top, func(x: float) -> float: return river_z(x) + side * (water_half(x) - 0.1), -side, z0, z1)
	if ih < 3.0:
		_pier(x0, x1, top, func(x: float) -> float: return river_z(x) - PIER_T * 0.5, 1.0, z0, z1)


## A bridge pier from under the riverbed up to `top`: one face on `edge(x)` (world z), 3.4 m thick toward `dir`
## (+1 = south), laid in 1 m steps from x0 to x1; only if its middle is under the span z0..z1.
const PIER_T := 1.8 # round 31: pier thickness out from its edge (3.4 before)

func _pier(x0: float, x1: float, top: float, edge: Callable, dir: float, z0: float, z1: float) -> void:
	var mid := float(edge.call((x0 + x1) * 0.5)) + dir * PIER_T * 0.5
	if mid <= z0 or mid >= z1:
		return
	var n := maxi(1, ceili(x1 - x0))
	var lo := Vector3(0, BED_Y - 0.3, 0)
	var hi := Vector3(0, top, 0)
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for k in n + 1:
		var x := lerpf(x0, x1, float(k) / n)
		var z := float(edge.call(x))
		a.append(Vector3(x, 0, z))
		b.append(Vector3(x, 0, z + dir * PIER_T))
	for k in n:
		face(_m.quay, [a[k] + lo, a[k + 1] + lo, a[k + 1] + hi, a[k] + hi], Vector3(0, 0, -dir), true, COL_WALL)
		face(_m.quay, [b[k] + lo, b[k + 1] + lo, b[k + 1] + hi, b[k] + hi], Vector3(0, 0, dir), true, COL_WALL)
		face(_m.quay, [a[k] + hi, a[k + 1] + hi, b[k + 1] + hi, b[k] + hi], Vector3.UP, true, COL_GROUND)
	face(_m.quay, [a[0] + lo, b[0] + lo, b[0] + hi, a[0] + hi], Vector3.LEFT, true, COL_WALL)
	face(_m.quay, [a[n] + lo, b[n] + lo, b[n] + hi, a[n] + hi], Vector3.RIGHT, true, COL_WALL)


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
	_road("lepic", [Vector2(82, MONT.y + MONT_TOP + 6.0), Vector2(150, MONT.y + MONT_TOP + 6.0)], 12.0) # straight at Montmartre's climb
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
var _plateaus: Array = [] # [poly, h] of every raised terrace (round 31: the edge fence stands over them)

func _plateau(poly: PackedVector2Array, h: float, top_mat: Material) -> void:
	_plateaus.append([poly, h])
	poly_face(top_mat, poly, h, false, COL_GROUND)
	var ccw := not Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var out := Vector3(d.y, 0, -d.x) if ccw else Vector3(-d.y, 0, d.x)
		face(_m.quay, [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)], out, true, COL_WALL)
	band(_m.stone, poly, 0.6, h + 0.02, true)


## Round 29 (owner: "too many sharp edges ... especially on the ways up the roof tops"): every ramp and
## sloped viaduct is straight in the middle with a quadratic fillet of RAMP_FILLET metres at both ends,
## so it leaves the ground and arrives on the level above with no kink (LA's ramp feet, round 9).
const RAMP_FILLET := 6.0


## Height `s` metres along a ramp of length `len` from y0 to y1 (flat at both ends).
static func ramp_height(s: float, len: float, y0: float, y1: float) -> float:
	var f := minf(RAMP_FILLET, len * 0.3)
	var m := (y1 - y0) / (len - f)
	s = clampf(s, 0.0, len)
	if s < f:
		return y0 + m * s * s / (2.0 * f)
	if s > len - f:
		var r := len - s
		return y1 - m * r * r / (2.0 * f)
	return y0 + m * (s - f * 0.5)


## A straight ramp from foot (y0) to top (y1), width w; registered for the AI. `run_on` m of flat deck
## at y1 carry on past the top (over a roof's mansard edge onto the deck).
func _ramp(foot: Vector2, top: Vector2, y0: float, y1: float, w: float, mat: Material, run_on := 0.0) -> void:
	var d := (top - foot).normalized()
	var l := Vector2(-d.y, d.x) * w * 0.5
	var len := foot.distance_to(top)
	var steps := maxi(12, int(len / 1.5))
	for k in steps:
		var p0 := foot.lerp(top, float(k) / steps)
		var p1 := foot.lerp(top, float(k + 1) / steps)
		var h0 := ramp_height(len * k / steps, len, y0, y1)
		var h1 := ramp_height(len * (k + 1) / steps, len, y0, y1)
		face(mat, [Vector3(p0.x + l.x, h0, p0.y + l.y), Vector3(p1.x + l.x, h1, p1.y + l.y), Vector3(p1.x - l.x, h1, p1.y - l.y),
			Vector3(p0.x - l.x, h0, p0.y - l.y)], Vector3.UP, false, COL_GROUND)
		for s: float in [-1.0, 1.0]:
			var e0 := p0 + l * s
			var e1 := p1 + l * s
			face(_m.quay, [Vector3(e0.x, minf(y0, y1), e0.y), Vector3(e1.x, minf(y0, y1), e1.y), Vector3(e1.x, h1, e1.y), Vector3(e0.x, h0, e0.y)],
				Vector3(l.x * s, 0, l.y * s), true, COL_WALL)
	# The high end closed down to the lower level (round 30: from behind you drove in under the ramp).
	if absf(y1 - y0) > 0.5:
		var hi := top if y1 > y0 else foot
		face(_m.quay, [Vector3(hi.x + l.x, minf(y0, y1), hi.y + l.y), Vector3(hi.x - l.x, minf(y0, y1), hi.y - l.y),
			Vector3(hi.x - l.x, maxf(y0, y1), hi.y - l.y), Vector3(hi.x + l.x, maxf(y0, y1), hi.y + l.y)], Vector3(d.x, 0, d.y) * signf(y1 - y0), true, COL_WALL)
	if run_on > 0.0:
		var q := top + d * run_on
		face(mat, [Vector3(top.x + l.x, y1, top.y + l.y), Vector3(q.x + l.x, y1, q.y + l.y), Vector3(q.x - l.x, y1, q.y - l.y),
			Vector3(top.x - l.x, y1, top.y - l.y)], Vector3.UP, false, COL_GROUND)
	ramps.append({"foot": Vector3(foot.x, y0, foot.y), "top": Vector3(top.x, y1, top.y), "w": w})


func _terraces() -> void:
	# Trocadero: three terraces up to +8 m below the Palais de Chaillot, ramps either side of the fountains.
	# (round 29: they reach the west edge wall; a 3 m strip between them and the wall trapped cars)
	_plateau(_rect(-HX, -92, -204, -62), 8.0, _m.plaza) # to the block behind (round 30: a 4 m gap trapped cars)
	_plateau(_rect(-HX, -62, -204, -40), 5.0, _m.plaza)
	_plateau(_rect(-HX, -40, -204, -18), 2.5, _m.plaza) # to the blocks (round 30: 4 m strip)
	for rx: float in [-258.0, -222.0]:
		_ramp(Vector2(rx, 4), Vector2(rx, -18), 0.0, 2.5, 10.0, _m.plaza)
		_ramp(Vector2(rx, -18), Vector2(rx, -40), 2.5, 5.0, 10.0, _m.plaza)
		_ramp(Vector2(rx, -40), Vector2(rx, -62), 5.0, 8.0, 10.0, _m.plaza)


func _montmartre() -> void:
	var c := MONT
	_plateau(_rect(c.x - MONT_LOW, -HZ, c.x + MONT_LOW, c.y + MONT_LOW), 7.0, _m.lawn) # to the north wall (round 29)
	_plateau(_rect(c.x - MONT_TOP, c.y - MONT_TOP, c.x + MONT_TOP, c.y + MONT_TOP), 14.0, _m.plaza)
	# Round 29: the old ramps started 5 m in front of a building and 4 m from the terrace's edge (nobody
	# could line up for them). Now one straight climb east from Rue Lepic: up to the first terrace, a few
	# metres flat, then up along the top terrace's south wall; near the top you veer left onto it.
	var z := c.y + MONT_TOP + 6.0
	_ramp(Vector2(c.x - MONT_LOW - 40.0, z), Vector2(c.x - MONT_LOW, z), 0.0, 7.0, 12.0, _m.cobble)
	_ramp(Vector2(c.x - MONT_LOW + 4.0, z), Vector2(c.x + MONT_TOP, z), 7.0, 14.0, 12.0, _m.cobble)


# ---------------------------------------------------------------- city blocks

## Urban zones minus roads, plazas, parks and landmarks = the blocks (pan coupe corners).
func _city_blocks() -> void:
	# Round 29 (owner: tight spaces): the zones reach 10 m past the map so a block's corner is never
	# chamfered against the edge wall (that left wedges a car slid into); blocks are clipped to the map last.
	var zones: Array[PackedVector2Array] = [_rect(-HX - 10.0, -HZ - 10.0, HX + 10.0, HZ + 10.0)]
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
			for grown: PackedVector2Array in Geometry2D.offset_polygon(inner, 2.5, Geometry2D.JOIN_SQUARE):
				if Geometry2D.is_polygon_clockwise(grown):
					continue
				for b: PackedVector2Array in Geometry2D.intersect_polygons(grown, _rect(-HX, -HZ, HX, HZ)):
					if Geometry2D.is_polygon_clockwise(b) or _area(b) < 400.0:
						continue
					_add_block(b)


func _add_block(b: PackedVector2Array) -> void:
	for i in b.size(): # a block within 4 m of the edge wall reaches it: no strip a car slides into
		if absf(b[i].x) > HX - 4.0:
			b[i].x = signf(b[i].x) * HX
		if absf(b[i].y) > HZ - 4.0:
			b[i].y = signf(b[i].y) * HZ
	b = _square_to_wall(b)
	var cen := _centroid(b)
	var roof := cen.x > -212.0 and cen.x < -14.0 and cen.y > -140.0 and cen.y < 20.0
	blocks.append({"poly": _simplify(b), "roof": roof, "h": ROOF_Y if roof else TALL_Y})


## Inward normal of the edge wall a point stands on (ZERO if it is not on one).
func _wall_normal(v: Vector2) -> Vector2:
	if absf(v.x) >= HX - 0.01:
		return Vector2(-signf(v.x), 0)
	if absf(v.y) >= HZ - 0.01:
		return Vector2(0, -signf(v.y))
	return Vector2.ZERO


## Round 29 (owner: tight spaces): a facade that leaves the edge wall at a sharp angle (a road running
## out of the map at a slant) makes a wedge of street a car slides into and sticks in. The block is
## squared off there: filled out along the wall until the facade stands 8 m off it, then straight back.
func _square_to_wall(b: PackedVector2Array) -> PackedVector2Array:
	var n := b.size()
	var out := PackedVector2Array()
	for i in n:
		var v := b[i]
		var on := _wall_normal(v)
		var prev := b[(i - 1 + n) % n]
		var next := b[(i + 1) % n]
		var facade := Vector2.INF
		var along := Vector2.INF
		if on != Vector2.ZERO and _wall_normal(prev) == on and _wall_normal(next) != on:
			facade = next
			along = prev
		elif on != Vector2.ZERO and _wall_normal(next) == on and _wall_normal(prev) != on:
			facade = prev
			along = next
		if facade == Vector2.INF:
			out.append(v)
			continue
		var f := (facade - v).normalized()
		var rise := f.dot(on) # how steeply the facade leaves the wall (1 = square)
		if rise > 0.94 or rise < 0.05 or f.dot(along - v) > 0.0:
			out.append(v) # square enough, or the sharp side is inside the block
			continue
		var t := minf(8.0 / rise, v.distance_to(facade) * 0.9)
		var p := v + f * t
		var foot := p - on * (rise * t)
		if facade == next:
			out.append_array([v, foot, p])
		else:
			out.append_array([p, foot, v])
	return out


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
## down a ramp into the Champs-Elysees gardens. Round 29 (owner: "complete the bridges on the rooftops"):
## two crossings hung in the air short of both roofs and the Trocadero viaduct stopped 10 m before its
## block; every end now lands 5 m inside a roof (past the mansard, on the deck). tests/paris_check.gd
## checks that both ends of every crossing stand on a roof deck.
const CROSSINGS := [
	[Vector2(-185, -59), Vector2(-185, -24.5)], # over Rue Francois 1er
	[Vector2(-142.5, -15), Vector2(-103.5, -15)], # over Avenue Marceau
	[Vector2(-93.5, -26), Vector2(-51.5, -26)], # over Avenue George V
	[Vector2(-55, -77.5), Vector2(-55, -43.5)], # over Rue Francois 1er, east
]
const TROCA_LINK := [Vector2(-238, -72), Vector2(-190.5, -72)] # Trocadero top (+8) up to the roofs (+13)
const CHAMPS_RAMP := [Vector2(52, -80), Vector2(-3.5, -80)] # the gardens (0) up to the roofs (+13)


func _rooftops() -> void:
	var steel := MatKit.steel(Color("4A504C"), 0.35)
	_viaduct(TROCA_LINK[0], TROCA_LINK[1], 8.0, ROOF_Y, 10.0, steel, 7.0)
	for lx: float in [-201.0]: # steel legs where the link crosses the street
		for s: float in [-1.0, 1.0]:
			var leg := Vector3(lx, 0, -72.0 + s * 4.2)
			var top := ramp_height(lx - TROCA_LINK[0].x, TROCA_LINK[0].distance_to(TROCA_LINK[1]), 8.0, ROOF_Y) - 0.5
			var mb := MeshBuilder.new()
			mb.box(steel, Vector3(0.7, top, 0.7), Transform3D(Basis(), leg + Vector3(0, top * 0.5, 0)), 0.04)
			mb.box(steel, Vector3(1.2, 0.4, 1.2), Transform3D(Basis(), leg + Vector3(0, 0.2, 0)), 0.05)
			batch_builder(mb, true)
			solid(Vector3(0.8, top, 0.8), Transform3D(Basis(), leg + Vector3(0, top * 0.5, 0)))
	_ramp(CHAMPS_RAMP[0], CHAMPS_RAMP[1], 0.0, ROOF_Y, 12.0, _m.quay, 3.5) # just over the mansard (round 30)
	for c: Array in CROSSINGS:
		_viaduct(c[0], c[1], ROOF_Y, ROOF_Y, 8.0, steel)
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		ramps.append({"foot": Vector3(b.x, ROOF_Y, b.y), "top": Vector3(a.x, ROOF_Y, a.y), "w": 8.0}) # both ways (round 31)
	poly_face(_m.lawn, _rect(-2, -108, 38, -96), 0.06)
	poly_face(_m.lawn, _rect(-2, -64, 38, -56), 0.06)


## A steel deck on lattice side girders from a to b (heights y0 -> y1 on the filleted ramp profile),
## `run_on` m more of flat deck past b; drivable. Built in short straight pieces that follow the profile.
func _viaduct(a: Vector2, b: Vector2, y0: float, y1: float, w: float, steel: Material, run_on := 0.0) -> void:
	var d := (b - a).normalized()
	var l := Vector2(-d.y, d.x) * w * 0.5
	var lv := Vector3(l.x, 0, l.y)
	var len := a.distance_to(b)
	var total := len + run_on
	var steps := maxi(2, int(total / 2.0))
	var yaw := atan2(-d.y, d.x)
	var mb := MeshBuilder.new()
	var at := func(t: float) -> Vector3:
		var p := a + d * t
		return Vector3(p.x, ramp_height(t, len, y0, y1) if t < len else y1, p.y)
	for k in steps:
		var pa: Vector3 = at.call(total * k / steps)
		var pb: Vector3 = at.call(total * (k + 1) / steps)
		var seg := pa.distance_to(pb)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(pb.y - pa.y, Vector2(pb.x - pa.x, pb.z - pa.z).length()))
		var mid := (pa + pb) * 0.5
		mb.box(steel, Vector3(seg + 0.06, 0.5, w), Transform3D(basis, mid + Vector3(0, -0.25, 0)), 0.0)
		for s: float in [-1.0, 1.0]:
			mb.box(steel, Vector3(seg + 0.06, 0.18, 0.3), Transform3D(basis, mid + lv * s + Vector3(0, 1.3, 0)), 0.0)
			mb.box(steel, Vector3(seg + 0.06, 0.6, 0.3), Transform3D(basis, mid + lv * s + Vector3(0, -0.1, 0)), 0.0)
			mb.box(steel, Vector3(0.14, 1.4, 0.14), Transform3D(basis * Basis(Vector3.BACK, 0.55 if k % 2 == 0 else -0.55),
				mid + lv * s + Vector3(0, 0.6, 0)), 0.0)
		face(steel, [pa + lv, pb + lv, pb - lv, pa - lv], Vector3.UP, false, COL_GROUND)
		for s: float in [-1.0, 1.0]:
			face(steel, [pa + lv * s, pb + lv * s, pb + lv * s + Vector3(0, 1.4, 0), pa + lv * s + Vector3(0, 1.4, 0)], lv * s, false, COL_WALL2)
			# A sloped link's sides are skirted down to where it starts (round 30: cars drove in under it
			# from the side on the terrace and wedged where the gap closed).
			if absf(y1 - y0) > 0.5:
				var base := minf(y0, y1)
				face(steel, [Vector3(pa.x, base, pa.z) + lv * s, Vector3(pb.x, base, pb.z) + lv * s, pb + lv * s, pa + lv * s], lv * s, true, COL_WALL)
	batch_builder(mb, true)
	if y0 > 1.0 or y1 > 1.0:
		ramps.append({"foot": Vector3(a.x, y0, a.y), "top": Vector3(b.x, y1, b.y), "w": w})


# ---------------------------------------------------------------- trees

## Plane trees in rows: the Champs-Elysees, every quay, the parks. One shared mesh, one MultiMesh per
## row group (so groups out of view are skipped), faded out past 170 m.
func _trees() -> void:
	var rows: Array = [] # Array of Array[Vector2]
	var e := ETOILE
	var champ_end := Vector2(42, -80)
	var cd := (champ_end - e).normalized()
	var cl := Vector2(-cd.y, cd.x)
	for side: float in [-1.0, 1.0]:
		var row: Array[Vector2] = []
		var t := RING_R + 16.0
		while t < e.distance_to(champ_end) - 4.0:
			row.append(e + cd * t + cl * side * 15.5)
			t += 9.0
		rows.append(row)
	for side: float in [-1.0, 1.0]:
		var row: Array[Vector2] = []
		var x := -HX + 6.0
		while x < HX - 6.0:
			row.append(Vector2(x, river_z(x) + side * (corridor_half(x) - SIDEWALK * 0.5)))
			x += 10.0
		rows.append(row)
	var cdm_n := river_z(-190.0) + corridor_half(-190.0)
	for px: float in [-268.0, -94.0, -206.0, -174.0]:
		var row: Array[Vector2] = []
		var z := cdm_n + 6.0
		while z < HZ - 6.0:
			row.append(Vector2(px, z))
			z += 9.0
		rows.append(row)
	var inv_n := river_z(0.0) + corridor_half(0.0)
	for px: float in [-55.0, 55.0]:
		var row: Array[Vector2] = []
		var z := inv_n + 4.0
		while z < 166.0:
			row.append(Vector2(px, z))
			z += 9.0
		rows.append(row)
	var tu: Array[Vector2] = []
	for x in range(130, 174, 8):
		tu.append(Vector2(x, -117))
		tu.append(Vector2(x, -55))
	rows.append(tu)
	_lamps(rows)
	var mesh := _tree_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 75
	for row: Array in rows:
		var xs: Array[Transform3D] = []
		for p: Vector2 in row:
			if _blocked(p):
				continue
			var s := rng.randf_range(0.85, 1.15)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.08), s)), Vector3(p.x, 0, p.y)))
		if xs.is_empty():
			continue
		var mmi := scatter(mesh, xs, true)
		mmi.visibility_range_end = 170.0
		mmi.visibility_range_end_margin = 10.0
		for i in xs.size():
			_tree_body(mesh, mmi, i, xs[i])


## Round 29 (owner: "make the trees hittable"): every plane tree is a TOPPLE breakable like LA's palms
## (a car swats it down, a blast throws it, fire or explosives set it alight; its crown hides you from
## missiles). It is drawn by its row's MultiMesh while it stands; as it breaks its instance is hidden
## and the falling trunk gets a mesh of its own, so standing trees cost no extra draw calls.
func _tree_body(mesh: Mesh, mmi: MultiMeshInstance3D, index: int, xf: Transform3D) -> void:
	var b := Breakable.new()
	b.style = Breakable.Style.TOPPLE
	b.kind = "tree" # wood: it splits, sheds leaves, and burns when a fire or explosive weapon fells it
	b.hinge = true # round 32: it falls over about its stump instead of being thrown
	b.crown_radius = 2.6
	b.size_hint = Vector3(1.2, 8.0, 1.2)
	b.topple_height = 9.0
	b.fall_mass = 420.0
	b.swat_aside = true # round 31: a rammed crown falls beside the road, not into the camera
	b.stump_radius = 0.26
	b.debris_color = Color(0.5, 0.47, 0.38)
	var rot := xf.basis.orthonormalized()
	b.transform = Transform3D(rot, xf.origin)
	add_child(b)
	b.add_box_shape(Vector3(0.7, 4.5, 0.7), Vector3(0, 2.25, 0))
	b.add_cover(1.6, 9.0)
	var scale_only := rot.inverse() * xf.basis
	b.breaking.connect(func(_p: Breakable) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = Transform3D(scale_only, Vector3.ZERO)
		b.visual.add_child(mi)
		mmi.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), xf.origin)))


## Cast-iron street lamps (dark green, a lantern on a fluted post) between the trees of the avenues
## and on the quays' stone coping.
func _lamps(tree_rows: Array) -> void:
	var spots: Array[Transform3D] = []
	for r in 2:
		var row: Array = tree_rows[r]
		for k in range(0, row.size() - 1, 3):
			var p: Vector2 = (row[k] as Vector2).lerp(row[k + 1], 0.5)
			spots.append(Transform3D(Basis(), Vector3(p.x, 0.03, p.y)))
	for side: float in [-1.0, 1.0]:
		var x := -HX + 15.0
		while x < HX - 15.0:
			if not _under_bridge(x, side, 4.0):
				spots.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.03, river_z(x) + side * (outer_half(x) + 1.6))))
			x += 26.0
	var keep: Array[Transform3D] = []
	for t in spots:
		if not _blocked(Vector2(t.origin.x, t.origin.z)) or absf(t.origin.z - river_z(t.origin.x)) < corridor_half(t.origin.x):
			keep.append(t)
	var mmi := scatter(_lamp_mesh(), keep, true)
	mmi.visibility_range_end = 140.0


func _lamp_mesh() -> Mesh:
	var mb := MeshBuilder.new()
	var iron := MatKit.paint(Color("23302A"), 0.35, 0.2, 0.3, 1.0, 0.45, 53)
	var lit := MatKit.flat(Color("F2E3B8"), 0.3)
	mb.cylinder(iron, 0.24, 0.7, Transform3D(Basis(), Vector3(0, 0.35, 0)), 8, 0.16)
	mb.cylinder(iron, 0.1, 3.6, Transform3D(Basis(), Vector3(0, 2.5, 0)), 8, 0.07)
	mb.cylinder(iron, 0.14, 0.2, Transform3D(Basis(), Vector3(0, 4.3, 0)), 8, 0.12)
	mb.box(iron, Vector3(0.9, 0.06, 0.06), Transform3D(Basis(), Vector3(0, 3.7, 0)), 0.0)
	mb.cylinder(lit, 0.2, 0.55, Transform3D(Basis(), Vector3(0, 4.68, 0)), 6, 0.27)
	mb.cylinder(iron, 0.31, 0.12, Transform3D(Basis(), Vector3(0, 5.0, 0)), 6, 0.08)
	mb.cylinder(iron, 0.04, 0.3, Transform3D(Basis(), Vector3(0, 5.2, 0)), 4, 0.01)
	return mb.build_mesh(0.0, 0.0, true)


## Inside a road, a block or off the map: no tree there.
func _blocked(p: Vector2) -> bool:
	if absf(p.x) > HX - 2.0 or absf(p.y) > HZ - 2.0:
		return true
	for r in _road_polys:
		if Geometry2D.is_point_in_polygon(p, r):
			return true
	if p.distance_to(ETOILE) < RING_R + 11.0:
		return true
	for f: Array in ParisLandmarks.footprints():
		var c: Vector2 = f[0]
		var h: Vector2 = f[1]
		if absf(p.x - c.x) < h.x + 3.0 and absf(p.y - c.y) < h.y + 3.0:
			return true
	for b: Dictionary in blocks:
		if Geometry2D.is_point_in_polygon(p, b.poly):
			return true
	for br: Dictionary in BRIDGES:
		if absf(p.x - float(br.x)) < float(br.w) * 0.5 + 5.0 and absf(p.y - river_z(p.x)) < corridor_half(p.x) + 2.0:
			return true
	return false


## A London plane: pale mottled trunk, a few heavy limbs, a broad crown. The crown is a dark inner mass
## under a shell of leaf clusters cut out of a picture, so its edge breaks up like foliage (round blobs
## read as toys).
func _tree_mesh() -> Mesh:
	var mb := MeshBuilder.new()
	# Round 32 (owner: the trees read as steel rods): plane-tree bark is a patchwork of olive-brown, grey and cream
	# flakes, rough and matt; the trunk flares at the root and forks into crooked limbs.
	var bark := MatKit.paint(Color("6F6450"), 0.85, 0.0, 0.85, 0.7, 0.05, 52)
	var inner := MatKit.flat(Color("2F4220"), 0.95)
	var leaves := _leaf_material()
	mb.cylinder(bark, 0.42, 0.7, Transform3D(Basis(), Vector3(0, 0.35, 0)), 9, 0.27) # root flare
	mb.cylinder(bark, 0.27, 4.0, Transform3D(Basis(Vector3(1, 0, 0.4).normalized(), 0.05), Vector3(0, 2.6, 0)), 9, 0.19)
	for k in 5:
		var a := TAU * k / 5.0 + 0.4
		var lean := 0.45 + 0.12 * (k % 3)
		var limb := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), lean)
		var limb_l := 2.2 + 0.3 * (k % 2)
		mb.cylinder(bark, 0.15, limb_l, Transform3D(limb, Vector3(0, 4.5, 0) + limb * Vector3(0, limb_l * 0.5, 0)), 6, 0.07)
	var clumps := [Vector3(0, 7.4, 0), Vector3(1.9, 6.6, 0.6), Vector3(-1.7, 6.8, 0.9), Vector3(0.4, 6.5, -2.0),
		Vector3(-0.4, 8.6, 0.2), Vector3(1.6, 7.9, -1.3)]
	var radii := [2.6, 2.0, 2.1, 2.0, 1.8, 1.7]
	for k in clumps.size():
		var r: float = radii[k]
		var xf := Transform3D(Basis().scaled(Vector3(1.0, 0.8, 1.0)), clumps[k])
		mb.sphere(inner, r * 0.72, xf, 6, 4)
		mb.sphere(leaves, r * 1.05, xf.rotated_local(Vector3.UP, k * 0.9), 8, 5)
	return mb.build_mesh(0.0, 0.0, true)


## Clusters of leaves in a few greens on a transparent ground, tiled over the crown shells.
static func _leaf_material() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var greens := [Color("4C6A2A"), Color("5E7D33"), Color("6E8B3D"), Color("3D5622"), Color("7A9446")]
	for k in 420:
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randi_range(2, 4)
		var c: Color = greens[rng.randi() % greens.size()]
		c = c.lightened(0.12) if cy < n / 2 and rng.randf() < 0.3 else c
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y * 2 <= r * r:
					img.set_pixel((cx + x + n) % n, (cy + y + n) % n, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# ---------------------------------------------------------------- boundary

func _boundary() -> void:
	# Walls round the map (the city beyond is the backdrop); barricades close every road that leaves it.
	for s: Array in [[Vector3(0, 10, -HZ - 1), Vector3(2 * HX + 4, 40, 2)], [Vector3(0, 10, HZ + 1), Vector3(2 * HX + 4, 40, 2)],
			[Vector3(-HX - 1, 10, 0), Vector3(2, 40, 2 * HZ + 4)], [Vector3(HX + 1, 10, 0), Vector3(2, 40, 2 * HZ + 4)]]:
		solid(s[1], Transform3D(Basis(), s[0]))
	_edge_walls()
	_outer_ring()
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
			# Round 30 (owner: cars drove through the barricades at the map's edges): solid.
			solid(Vector3(w, 3.8, 1.8), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 1.9, p.y) + Vector3(along.y, 0, -along.x) * 0.3))
	batch_builder(mb, true, 0.4)


## Round 31 (owner: "fill the void at the end of the map with something real"): the city goes on past the edge
## walls: a street, then a row of Haussmann block shells (the far kit's painted facades, 4 draw calls for all),
## with gaps where a barricaded road or the Seine leaves the map. Nothing to drive on, no collision.
func _outer_ring() -> void:
	var gaps: Array = [] # [side, centre along the side, half width]
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		for end: Vector2 in [pts[0], pts[pts.size() - 1]]:
			var w: float = r.w * 0.5 + SIDEWALK + 2.0
			if absf(end.y) >= HZ - 1.0:
				gaps.append([signf(end.y) * 2.0, end.x, w])
			elif absf(end.x) >= HX - 1.0:
				gaps.append([signf(end.x), end.y, w])
	for ex: float in [-HX, HX]:
		gaps.append([signf(ex), river_z(ex), corridor_half(ex) + 2.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var mb := MeshBuilder.new()
	var sts := {}
	# side: -1/+1 = west/east (x = -+HX, running along z), -2/+2 = north/south (z = -+HZ, running along x)
	for side: float in [-2.0, 2.0, -1.0, 1.0]:
		var along_x := absf(side) > 1.5
		var half := HX if along_x else HZ
		var reach := 40.0 if along_x else 8.0 # the north and south rows turn the corners
		var t := -half - reach
		while t < half + reach:
			var w := rng.randf_range(34.0, 52.0)
			var t0 := t
			var t1 := t + w
			t = t1 + rng.randf_range(10.0, 14.0)
			var clear := true
			for g: Array in gaps:
				if float(g[0]) == side and t1 > float(g[1]) - float(g[2]) and t0 < float(g[1]) + float(g[2]):
					clear = false
			if not clear:
				continue
			var s := signf(side)
			var near := (HZ if along_x else HX) + 11.0
			var far := near + rng.randf_range(20.0, 28.0)
			var poly: PackedVector2Array
			if along_x:
				poly = PackedVector2Array([Vector2(t0, s * near), Vector2(t1, s * near), Vector2(t1, s * far), Vector2(t0, s * far)])
			else:
				poly = PackedVector2Array([Vector2(s * near, t0), Vector2(s * far, t0), Vector2(s * far, t1), Vector2(s * near, t1)])
			ParisBlocks.ring_block(self, poly, rng.randf() < 0.45, mb, sts)
	ParisBlocks.ring_commit(self, mb, sts)


## Round the map: a stone wall with a cast-iron railing (like the parks' fences), and the river closed
## by a wall at both ends. Faces only inward: nothing outside is ever seen from the stage.
func _edge_walls() -> void:
	var h := 3.2
	var rail: StandardMaterial3D = null
	if ResourceLoader.exists("res://assets/models/haussmann_rail.png"):
		rail = ModelLib.cutout("haussmann_rail").duplicate() as StandardMaterial3D
		rail.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 1.2, 1.0)
		rail.uv1_offset = Vector3(0, (h + 1.2) / 1.2, 0)
	var sides := [[Vector2(-HX, -HZ), Vector2(HX, -HZ), Vector3(0, 0, 1)], [Vector2(HX, HZ), Vector2(-HX, HZ), Vector3(0, 0, -1)],
		[Vector2(-HX, HZ), Vector2(-HX, -HZ), Vector3(1, 0, 0)], [Vector2(HX, -HZ), Vector2(HX, HZ), Vector3(-1, 0, 0)]]
	for sd: Array in sides:
		var a: Vector2 = sd[0]
		var b: Vector2 = sd[1]
		var inward: Vector3 = sd[2]
		var n := int(a.distance_to(b) / 25.0)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var q0 := Vector3(p0.x, 0, p0.y)
			var q1 := Vector3(p1.x, 0, p1.y)
			# where the river crosses the edge the wall goes down to the water
			var y0 := 0.0
			if absf(p0.x) >= HX - 0.1 and absf(p0.y - river_z(p0.x)) < outer_half(p0.x) + 1.0:
				y0 = BED_Y - 0.3
			face(_m.quay, [q0 + Vector3(0, y0, 0), q1 + Vector3(0, y0, 0), q1 + Vector3(0, h, 0), q0 + Vector3(0, h, 0)], inward, true)
			face(_m.stone, [q0 + Vector3(0, h, 0), q1 + Vector3(0, h, 0), q1 + Vector3(0, h, 0) + inward * 0.5,
				q0 + Vector3(0, h, 0) + inward * 0.5], Vector3.UP, true)
			face(_m.stone, [q0 + Vector3(0, h - 0.3, 0) + inward * 0.5, q1 + Vector3(0, h - 0.3, 0) + inward * 0.5,
				q1 + Vector3(0, h, 0) + inward * 0.5, q0 + Vector3(0, h, 0) + inward * 0.5], inward, true)
			if rail and _edge_top(p0, p1, inward) <= 0.0:
				face(rail, [q0 + Vector3(0, h, 0) + inward * 0.25, q1 + Vector3(0, h, 0) + inward * 0.25,
					q1 + Vector3(0, h + 1.2, 0) + inward * 0.25, q0 + Vector3(0, h + 1.2, 0) + inward * 0.25], inward, true)
			_edge_fence(p0, p1, inward, h)
	if _fence_mb:
		batch_builder(_fence_mb, true, 0.4)
	# the river's two ends: walls across the trench from the water up to the street
	for ex: float in [-HX, HX]:
		var zc := river_z(ex)
		var o := outer_half(ex)
		var inward := Vector3(-signf(ex), 0, 0)
		face(_m.quay, [Vector3(ex, BED_Y - 0.3, zc - o), Vector3(ex, BED_Y - 0.3, zc + o), Vector3(ex, 0, zc + o), Vector3(ex, 0, zc - o)],
			inward, true, COL_WALL)


## Round 31 (owner: on a roof at the west edge he saw the end of the map and hit "a wall of air"): a real
## security fence on the edge wall all round, steel posts every 5 m, chain link, an outrigger with barbed
## wire, always FENCE_OVER m above the highest place a car can stand beside it (a 6 m jump never clears it).
## Where a terrace or a drivable roof meets the edge, the stone wall first rises to its height.
const FENCE_OVER := 7.5
var _fence_mb: MeshBuilder
var _chain: StandardMaterial3D

func _edge_fence(a: Vector2, b: Vector2, inward: Vector3, wall_h: float) -> void:
	if _chain == null:
		_chain = MatKit.chainlink()
		_fence_mb = MeshBuilder.new()
	var top := _edge_top(a, b, inward)
	var q0 := Vector3(a.x, 0, a.y)
	var q1 := Vector3(b.x, 0, b.y)
	var base := wall_h
	if top > 0.0: # the wall goes up to the terrace / roof, then a coping
		base = top + 1.1
		face(_m.quay, [q0 + Vector3(0, wall_h, 0), q1 + Vector3(0, wall_h, 0), q1 + Vector3(0, base, 0), q0 + Vector3(0, base, 0)], inward, true, COL_WALL)
		face(_m.stone, [q0 + Vector3(0, base, 0), q1 + Vector3(0, base, 0), q1 + Vector3(0, base, 0) + inward * 0.5,
			q0 + Vector3(0, base, 0) + inward * 0.5], Vector3.UP, true)
	var tip := top + FENCE_OVER
	var f0 := q0 + inward * 0.2
	var f1 := q1 + inward * 0.2
	face(_chain, [f0 + Vector3(0, base, 0), f1 + Vector3(0, base, 0), f1 + Vector3(0, tip, 0), f0 + Vector3(0, tip, 0)], inward, false, COL_WALL)
	var steel := _m.get("fence_steel") as Material
	if steel == null:
		steel = MatKit.steel(Color(0.2, 0.2, 0.19), 0.7)
		_m["fence_steel"] = steel
	var along := (q1 - q0)
	var n := maxi(1, int(along.length() / 5.0))
	var yaw := atan2(-along.z, along.x)
	for k in n + 1:
		var p := f0 + along * (float(k) / n)
		_fence_mb.box(steel, Vector3(0.16, tip - base, 0.16), Transform3D(Basis(), p + Vector3(0, (base + tip) * 0.5, 0)), 0.0)
		# the outrigger leans in over the stage and carries the barbed wire
		_fence_mb.box(steel, Vector3(0.1, 1.3, 0.1), Transform3D(Basis(along.normalized(), -0.6), p + Vector3(0, tip + 0.5, 0) + inward * 0.35), 0.0)
	for w: float in [0.25, 0.6]:
		var y := tip + 0.3 + w * 1.2
		_fence_mb.box(steel, Vector3(along.length(), 0.05, 0.05), Transform3D(Basis(Vector3.UP, yaw), (f0 + f1) * 0.5 + Vector3(0, y, 0) + inward * w), 0.0)
	_fence_mb.box(steel, Vector3(along.length(), 0.12, 0.12), Transform3D(Basis(Vector3.UP, yaw), (f0 + f1) * 0.5 + Vector3(0, tip, 0)), 0.0)


## The highest place a car can stand within 4 m of this stretch of the edge: drivable roofs, terraces (0 = street).
func _edge_top(a: Vector2, b: Vector2, inward: Vector3) -> float:
	var top := 0.0
	var inn := Vector2(inward.x, inward.z)
	var n := maxi(2, int(a.distance_to(b) / 2.0))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		for d: float in [1.0, 3.5]:
			var q := p + inn * d
			for bl: Dictionary in blocks:
				if bl.roof and Geometry2D.is_point_in_polygon(q, bl.poly):
					top = maxf(top, float(bl.h))
			for pl: Array in _plateaus:
				if Geometry2D.is_point_in_polygon(q, pl[0]):
					top = maxf(top, float(pl[1]))
	return top


# ---------------------------------------------------------------- gameplay points

func _at(x: float, z: float, yaw_deg: float, y := 0.3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(x, y, z))


func _points() -> void:
	for t: Transform3D in [_at(108, -80, 90), _at(-150, -125, 0), _at(-190, 204, 90), _at(0, 120, 180), _at(160, 175, 0),
			_at(196, -40, 0), _at(-80, 150, 0)]:
		spawn_points.append(t)
		respawn_points.append(t)
	weapon_points.assign([Vector3(-60, 0.6, river_z(-60) - outer_half(-60) - 10.0), Vector3(60, 0.6, river_z(60) + outer_half(60) + 10.0),
		Vector3(-120, QUAY_Y + 0.6, river_z(-120) - 20.0), Vector3(40, QUAY_Y + 0.6, river_z(40) + 20.0),
		Vector3(-150, 0.6, -134), Vector3(-80, 0.6, -128), Vector3(82, 0.6, -60), Vector3(150, 0.6, -100),
		Vector3(-190, 0.6, 175), Vector3(-130, 0.6, 205), Vector3(0, 0.6, 175), Vector3(112, 0.6, 170),
		Vector3(228, 0.6, 196), Vector3(-240, 8.6, -75), Vector3(236, 14.6, -170), Vector3(226, 0.6, -88)])
	for i in weapon_points.size():
		weapon_kinds.append("")
	# Round 29 (owner): three health on the street, the rest up top, the mega on the rooftop circuit.
	health_points.assign([Vector3(TOWER.x, 0.6, TOWER.y), Vector3(230, 0.6, 130), Vector3(160, 0.6, -150),
		Vector3(-240, 8.6, -81), Vector3(214, 14.6, -170)])
	mega_points.assign([Vector3(-172, ROOF_Y + 0.6, -78)])
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


## Round 31 (owner: the AI got stuck at the Trocadero "stairs" and in the river): every terrace is a level of
## its own (they were one "troca" and one "hill", so the AI drove straight at the next terrace's wall).
func level_of(p: Vector3) -> String:
	if p.y < -2.0:
		return "quay"
	if p.y > 1.5:
		if Vector2(p.x, p.z).distance_to(MONT) < 90.0:
			return "hill1" if p.y < 10.5 else "hill2"
		if p.y > ROOF_Y - 2.0:
			return _roof_level(Vector2(p.x, p.z)) # the rooftop circuit (the Champs ramp's top was "street")
		if p.x < -200.0:
			return "troca1" if p.y < 3.75 else ("troca2" if p.y < 6.5 else "troca3")
	return "street"


## Round 31: every drivable roof block is a level of its own ("roof<i>", the steel crossings join them), or the AI
## drove straight across the gap between two roofs and fell into the street.
func _roof_level(q: Vector2) -> String:
	var best := -1
	var best_d := 6.0
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		if not b.roof:
			continue
		var poly: PackedVector2Array = b.poly
		if Geometry2D.is_point_in_polygon(q, poly):
			return "roof%d" % i
		for k in poly.size():
			var c := Geometry2D.get_closest_point_to_segment(q, poly[k], poly[(k + 1) % poly.size()])
			if c.distance_to(q) < best_d:
				best_d = c.distance_to(q)
				best = i
	return "roof%d" % best if best >= 0 else "roof"


## Round 31: the AI's path finding (ParisNav, built on the first request).
var nav: ParisNav

func nav_point(asker: Object, from: Vector3, to: Vector3) -> Vector3:
	if nav == null:
		nav = ParisNav.new(self)
	return nav.next_point(asker, from, to)


## Levels the AI leaves only by a ramp (round 31): the street has parapets over the river, the roofs have
## parapets all round. (Terraces have open edges: it drives off them.)
const FENCED_LEVELS := ["street", "roof"]


## Round 31: the lower quays' ramps up to the street, for the AI (they are part of the trench, so they were
## never on the ramp list: an AI in the river had no way out). foot = on the quay, top = at the street.
func _quay_ramps() -> void:
	for side: float in [-1.0, 1.0]:
		for pair: Array in [[-222.0, -262.0], [100.0, 144.0], [172.0, 144.0], [252.0, 274.0]]:
			var xf: float = pair[0]
			var xt: float = pair[1]
			var zf := river_z(xf) + side * (water_half(xf) + quay_w(xf) * 0.5)
			var zt := river_z(xt) + side * (water_half(xt) + quay_w(xt) * 0.5)
			ramps.append({"foot": Vector3(xf, quay_y(xf), zf), "top": Vector3(xt, quay_y(xt), zt), "w": quay_w(xf)})


func water_material() -> Material:
	return _m.water


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
