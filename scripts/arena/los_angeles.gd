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
## Look (owner's references, session 5): golden-hour dusk with a purple-pink sky, stone pavers on
## the battleground, dry grass below, stone retaining walls, curbs striped at the bends, sidewalks,
## real shop buildings with depth (LaBuildings), tall LA fan palms and date palms, the HOLLYWOOD sign
## on its hill. Fixed seed: the layout is the same every run.

signal easter_egg(title: String, text: String)

const HALF := 155.0 # inner face of the outer wall
const WALL_CHAMFER := 24.0
const MAP_HALF := 160 # heightmap reach (1 m samples); the plateau ends just past the wall
const PLAT_H := 5.0 # battleground height above the roads: about three Outlaws stacked (owner)
const PLAT_A := 100.0 # battleground half size in x (superellipse)
const PLAT_B := 92.0 # ... in z
const RAMP_L := 22.0
const RAMP_W := 14.0
const RAMP_FILLET := 6.0 # the curve where a ramp meets the road (round 9)
const RAMP_ANGLES := [12.0, 105.0, 192.0, 322.0] # degrees around the battleground (0 = east, 90 = south)
const ROAD_W := 18.0
const HILL_H := 3.0
const HILL_AT := [0.33, 0.6, 0.86] # where the three hills sit along the road loop (0..1)
const HILL_SIDE := 22.0 # how far from the road's middle a hill's side runs out (gentle, under 20 degrees)
const ROOF_Y := 9.0 # tunnel roof
const ROAD_NORTH_Z := -128.0 # the north straight through the tunnels
const TUNNEL_X := 32.0 # tunnels run from -TUNNEL_X to TUNNEL_X
const TUNNEL_Z0 := -146.0
const TUNNEL_Z1 := -110.0
const DECK_Y := 6.0 # caged deck, above the battleground
const DECK_CENTER := Vector3(55, PLAT_H, -42)
const TOWER_AT := Vector3(52, PLAT_H, 48)
const BURNT_AT := Vector3(-52, PLAT_H, -38)
const VEHICLE_BARRIER_LAYER := 16 # physics layer 5: only cars collide with it
const BARRIER_H := 120.0
const SIGN_Z := -200.0 # where the hills' sign area is in the baked backdrop
const SIGN3D_Z := -178.0 # the real 3D letters, on a scaffold past the north fence
const SIGN_BASE_Y := 21.0 # above the fence: hit them with a missile fired nose-up (the tunnel-roof ramps) # the HOLLYWOOD letters, on the hill north of the arena
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
var music := "los_angeles" # audio/music/los_angeles.mp3
var subtitle := "Relief Zone One"
var next_line := "Prepare for Paris" # round 12: the win line on the target plate
var spawn_points: Array[Transform3D] = []
var respawn_points: Array[Transform3D] = []
var weapon_points: Array[Vector3] = []
var health_points: Array[Vector3] = []
var mega_points: Array[Vector3] = []
var turbo_points: Array[Vector3] = [] # five spots (owner, session 6)
var weapon_kinds: Array[String] = [] # the weapon each weapon point always gives ("" = from the mix)
var ramps: Array[Dictionary] = [] # {foot, top}: the AI drives to the foot, then up
var center := Vector3(0, PLAT_H, 0)
var wander_half := 130.0

var _rng := RandomNumberGenerator.new()
var _m := {} # materials
var _tower_legs := 4
var _tower_upper: Node3D
var _shrub: ArrayMesh
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
	_curbs()
	_cracks()
	_outer_wall()
	LaBuildings.new().build(self)
	_tunnels()
	_overpass_and_cage()
	_fire_pit()
	_burnt_building(BURNT_AT)
	_power_tower()
	_hot_dog_stands()
	_palms()
	_bushes()
	_hollywood_sign()
	var props := LaProps.new()
	props.name = "Props"
	add_child(props)
	props.build(self)
	_points()
	_flush_batch()


# ---------------------------------------------------------------- static batching

## Owner's performance plan (session 6): everything in the stage that never moves or breaks is
## merged into ONE mesh per material, so the static stage costs about one draw call per material
## instead of one per piece (roads, lines, cracks, walls, buildings, props, signs, cables...).
## Breakables, pickups and cars stay separate. Call batch_* while building; _flush_batch() at the end.
var _batch := {} # "material id|shadows" -> {st, mat, shadows}
static var _text_mats := {}


func batch_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, shadows := true, override: Material = null) -> void:
	for i in mesh.get_surface_count():
		var mat: Material = override if override else mesh.surface_get_material(i)
		if mat == null:
			continue
		var key := "%d|%d" % [mat.get_instance_id(), int(shadows)]
		if not _batch.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[key] = {"st": st, "mat": mat, "shadows": shadows}
		(_batch[key].st as SurfaceTool).append_from(mesh, i, xf)


## A finished MeshBuilder (instead of mb.commit(self, ...)). xf places it (a billboard's frame).
func batch_builder(mb: MeshBuilder, shadows := true, grime := 0.0, xf := Transform3D.IDENTITY) -> void:
	batch_mesh(mb.build_mesh(grime, 0.0, true), xf, shadows) # plain paints fold into 2 shared materials


## Text as real geometry (replaces Label3D, which costs a draw call each). The text faces +Z of xf.
## neon = unshaded and bright (shop signs); otherwise lit paint.
## The biggest font size (up to `largest`) at which `text` fits a w x h metre frame (round 13: signs'
## lettering ran off their boards).
static func fit_font(text: String, pixel_size: float, w: float, h: float, largest: int) -> int:
	var tm := TextMesh.new()
	tm.text = text
	tm.pixel_size = pixel_size
	var fs := largest
	while fs > 12:
		tm.font_size = fs
		var size := tm.get_aabb().size
		if size.x <= w and size.y <= h:
			break
		fs -= 4
	return fs


func batch_text(text: String, xf: Transform3D, font_size: int, pixel_size: float, color: Color, neon := false) -> void:
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = font_size
	tm.pixel_size = pixel_size
	tm.depth = 0.0
	var arrays := tm.get_mesh_arrays()
	if arrays.is_empty() or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var key := "%s|%d" % [color.to_html(), int(neon)]
	if not _text_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8 # one-sided: readable from the front only, like the old labels
		if neon:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_text_mats[key] = m
	batch_mesh(_indexed(raw), xf, false, _text_mats[key])


## append_from() drops non-indexed parts once the merged mesh holds indexed ones: index first.
static func _indexed(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.index()
	return st.commit()


func _flush_batch() -> void:
	for key: String in _batch:
		var e: Dictionary = _batch[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (e.st as SurfaceTool).commit()
		mi.material_override = e.mat
		if not e.shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batch.clear()


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


## Height of a ramp's driving surface (a plane from the battleground edge down to the foot).
static func ramp_y(rp: Dictionary, x: float, z: float) -> float:
	var along: float = (Vector3(x, 0, z) - Vector3(rp.top.x, 0, rp.top.z)).dot(rp.dir)
	return ramp_profile(along)


## Ramp height `along` metres out from its top edge. Round 9 (owner: drive smoothly onto the ramps):
## the foot curves into the road over RAMP_FILLET metres instead of a sharp kink that bounced the
## car's nose up and scraped its belly.
static func ramp_profile(along: float) -> float:
	var m := PLAT_H / RAMP_L
	var half := RAMP_FILLET * 0.5
	if along <= RAMP_L - half:
		return PLAT_H * (1.0 - clampf(along / RAMP_L, 0.0, 1.0))
	if along >= RAMP_L + half:
		return 0.0
	var d := RAMP_L + half - along
	return m / (2.0 * RAMP_FILLET) * d * d


## Signed distance (m, approx.) from the battleground edge: > 0 inside.
## Round 13 (AI routes by level, not by height: the cage deck at 11 m and the tunnel roof at 9 m are
## only 2 m apart but not joined). road | battle | roof | deck.
const FENCED_LEVELS := ["deck"] # left only by its ramp

static func level_of(p: Vector3) -> String:
	if p.y > PLAT_H + DECK_Y - 1.5 and absf(p.x - DECK_CENTER.x) < 16.0 and absf(p.z - DECK_CENTER.z) < 16.0:
		return "deck"
	if p.y > ROOF_Y - 1.5 and absf(p.x) < TUNNEL_X + 1.0 and p.z > TUNNEL_Z0 - 1.0 and p.z < TUNNEL_Z1 + 1.0:
		return "roof"
	if p.y > 1.0 and edge_distance(p.x, p.z) > -0.5:
		return "battle"
	return "road"


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
		if along > -1.0 and along < RAMP_L + RAMP_FILLET * 0.5 and across < RAMP_W * 0.5:
			h = maxf(h, ramp_profile(along))
	if h < 0.5:
		for hill: Dictionary in hills():
			var rel := Vector2(x, z) - (hill.p as Vector2)
			var a: float = rel.dot(hill.d) / 12.0
			var c: float = absf(rel.dot(Vector2(-hill.d.y, hill.d.x)))
			# Full height across the road, then a long gentle side (round 7: the sides fell 3 m in
			# ~4 m, a 49 degree bank the car's body hit like an invisible wall when crossing at an angle).
			if absf(a) < 1.0 and c < HILL_SIDE:
				h += HILL_H * pow(cos(a * PI * 0.5), 2.0) * (1.0 - smoothstep(ROAD_W * 0.5, HILL_SIDE, c))
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


# ---------------------------------------------------------------- merged geometry helpers

var _solid_body: StaticBody3D


## One shared collider for merged static geometry (draw calls are the HD 5500's bottleneck, so
## the visible parts are merged with MeshBuilder and only box shapes are added here).
func _solid(size: Vector3, xf: Transform3D) -> void:
	if _solid_body == null:
		_solid_body = StaticBody3D.new()
		_solid_body.name = "MergedColliders"
		_solid_body.collision_layer = 1
		_solid_body.collision_mask = 0
		add_child(_solid_body)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.transform = xf
	_solid_body.add_child(shape)


## Box (visual + collider) in arena space, merged into mb.
func _solid_box_mb(mb: MeshBuilder, mat: Material, size: Vector3, xf: Transform3D, bevel := 0.0) -> void:
	mb.box(mat, size, xf, bevel)
	_solid(size, xf)


## A straight beam from a to b (square section t) into mb.
static func _beam(mb: MeshBuilder, mat: Material, a: Vector3, b: Vector3, t: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	var dir := (b - a).normalized()
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	mb.box(mat, Vector3(t, t, a.distance_to(b)), Transform3D(basis, (a + b) * 0.5), 0.0)


# ---------------------------------------------------------------- look

func _materials() -> void:
	_m.ground = MatKit.grass(Color(0.3, 0.36, 0.2), 14.0, 7) # low ground around the road: dry grass
	_m.deck = MatKit.pavers(Color(0.6, 0.55, 0.46), 8.0, 11) # the raised battleground: stone pavers
	_m.sidewalk = MatKit.pavement("concrete", Color(0.5, 0.48, 0.44), 6.0, 13)
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
	_m.retain = MatKit.masonry(Color(0.5, 0.45, 0.38), 4.0, 140)
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
	env.ambient_light_color = Color(0.62, 0.52, 0.44) # round 10: light through smoke, brown-amber (no violet)
	env.ambient_light_energy = 0.8 # kept readable (owner: TM2-bright, not Black-dark)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.36, 0.26) # smoke from the burning city
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0 # the backdrop already has its haze
	if RenderingServer.get_rendering_device() != null: # Forward+ / Mobile only
		env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.84 # gritty, not candy (owner: "serious"; round 10: a war zone)
	env.adjustment_contrast = 1.14
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.68, 0.44) # a low sun through smoke
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = SUN_ROTATION
	add_child(sun)


const SUN_ROTATION := Vector3(-26, -62, 0) # low evening sun in the west-south-west


## The sky the backdrop is baked with (and the fallback when the backdrop image is missing).
static func sky_material() -> ProceduralSkyMaterial:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.17, 0.15) # smoke overhead
	sky_mat.sky_horizon_color = Color(0.62, 0.36, 0.2) # fire glow on the horizon
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.45, 0.3, 0.2)
	sky_mat.ground_bottom_color = Color(0.16, 0.12, 0.1)
	sky_mat.sun_angle_max = 8.0
	return sky_mat


# ---------------------------------------------------------------- ground

func _terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group(&"ground") # Vehicle: drivable terrain is never mistaken for a wall
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var n := MAP_HALF * 2 + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			data[j * n + i] = height_at(i - MAP_HALF, j - MAP_HALF)
	# Collision (performance, round 5): a 1 m heightmap made every car's move cost ~2 ms per physics
	# tick on Godot Physics. The same surface as a trimesh with big triangles where the ground is
	# flat and small ones only where it bends costs ~8x less (13k triangles instead of 205k).
	var faces := PackedVector3Array()
	_ground_faces(data, n, -MAP_HALF, -MAP_HALF, MAP_HALF * 2, MAP_HALF * 2, faces)
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	var shape := CollisionShape3D.new()
	shape.shape = trimesh
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
	var cells := 40 # per chunk side (80 m): few big meshes = few draw calls
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
							tools[which].set_uv(Vector2(x, z))
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
	batch_builder(mb, false)


## Collision faces for the rectangle [x0, x0+sx] x [z0, z0+sz] of the 1 m height grid: two triangles
## when every sample inside lies on the patch through its corners (within 2 cm), else split in four.
func _ground_faces(data: PackedFloat32Array, n: int, x0: int, z0: int, sx: int, sz: int, faces: PackedVector3Array) -> void:
	var h := func(x: int, z: int) -> float: return data[(z + MAP_HALF) * n + x + MAP_HALF]
	var h00: float = h.call(x0, z0)
	var h10: float = h.call(x0 + sx, z0)
	var h01: float = h.call(x0, z0 + sz)
	var h11: float = h.call(x0 + sx, z0 + sz)
	var flat := sx <= 1 and sz <= 1
	if not flat:
		flat = true
		for j in sz + 1:
			var v := float(j) / sz
			for i in sx + 1:
				var u := float(i) / sx
				var want := lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)
				if absf(data[(z0 + j + MAP_HALF) * n + x0 + i + MAP_HALF] - want) > 0.02:
					flat = false
					break
			if not flat:
				break
	if flat:
		var p00 := Vector3(x0, h00, z0)
		var p10 := Vector3(x0 + sx, h10, z0)
		var p01 := Vector3(x0, h01, z0 + sz)
		var p11 := Vector3(x0 + sx, h11, z0 + sz)
		faces.append_array([p00, p10, p01, p10, p11, p01])
		return
	var hx := maxi(1, sx / 2)
	var hz := maxi(1, sz / 2)
	_ground_faces(data, n, x0, z0, hx, hz, faces)
	if sx > hx:
		_ground_faces(data, n, x0 + hx, z0, sx - hx, hz, faces)
	if sz > hz:
		_ground_faces(data, n, x0, z0 + hz, hx, sz - hz, faces)
	if sx > hx and sz > hz:
		_ground_faces(data, n, x0 + hx, z0 + hz, sx - hx, sz - hz, faces)


func _normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 1.0, z) - height_at(x + 1.0, z), 2.0, height_at(x, z - 1.0) - height_at(x, z + 1.0)).normalized()


## A strip laid on the ground along a polyline (roads, painted lines, cracks). Wide strips are
## split across into ~2.5 m lanes so they follow the ground (a ramp's crest, a hill's shoulders)
## instead of cutting under it.
func _drape(points: PackedVector3Array, width: float, lift: float, mat: Material, closed := false, offset := 0.0, surface := Callable()) -> void:
	var count := points.size()
	if count < 2:
		return
	var lanes := maxi(1, ceili(width / 2.5))
	var rows: Array[PackedVector3Array] = [] # rows[i][k]: k = 0 is the left edge
	for i in count:
		var prev := points[i - 1] if (i > 0 or closed) else points[i]
		var next := points[(i + 1) % count] if (i < count - 1 or closed) else points[i]
		var tangent := next - prev
		tangent.y = 0.0
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var c := points[i] + side * offset
		var row := PackedVector3Array()
		for k in lanes + 1:
			var q := c + side * width * (float(k) / lanes - 0.5)
			if surface.is_valid(): # a known plane (ramps): the 2 m ground mesh rounds their edges off
				row.append(Vector3(q.x, float(surface.call(q.x, q.z)) + lift, q.z))
			else:
				row.append(on_mesh(q.x, q.z, lift))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := count if closed else count - 1
	for i in segs:
		var j := (i + 1) % count
		for k in lanes:
			var li := rows[i][k]
			var lj := rows[j][k]
			var ri := rows[i][k + 1]
			var rj := rows[j][k + 1]
			for p: Vector3 in [li, lj, ri, ri, lj, rj]: # clockwise from above = front face
				st.set_normal(_normal_at(p.x, p.z))
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
	st.index()
	batch_mesh(st.commit(), Transform3D.IDENTITY, false, mat)


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
	batch_builder(mb, true, 0.6)


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
		ramps.append({"foot": foot + dir * 10.0, "top": top - dir * 8.0, "w": RAMP_W})
	batch_builder(mb, true, 0.5)
	for rp: Dictionary in ramp_list():
		var pts := PackedVector3Array()
		var base := Vector3(rp.top.x, 0, rp.top.z) - (rp.dir as Vector3) * 2.0
		for k in 16:
			pts.append(base + (rp.dir as Vector3) * ((RAMP_L + 2.0 + RAMP_FILLET * 0.5) * k / 15.0))
		var plane := func(x: float, z: float) -> float: return ramp_y(rp, x, z)
		_drape(pts, RAMP_W - 0.1, 0.05, _m.asphalt, false, 0.0, plane)
		for s: float in [-1.0, 1.0]:
			_drape(pts, 0.3, 0.08, _m.yellow_line, false, s * (RAMP_W * 0.5 - 0.7), plane)
		# Chevrons pointing up the ramp.
		for k in 3:
			var c := base + (rp.dir as Vector3) * (6.0 + k * 6.0)
			for s: float in [-1.0, 1.0]:
				var chev := PackedVector3Array([c + (rp.side as Vector3) * s * 3.5 + (rp.dir as Vector3) * 1.5, c])
				_drape(chev, 0.5, 0.09, _m.white_line, false, 0.0, plane)


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


## Raised curbs on both road edges (red and white at the bends), a sidewalk along the outside.
## Visual only: the cars ride over them without a bump.
func _curbs() -> void:
	var pts := road_points()
	var n := pts.size()
	var mb := MeshBuilder.new()
	var curb := MatKit.paint(Color(0.62, 0.6, 0.55), 0.3, 0.1, 0.8, 1.0, 0.9, 160)
	var red := MatKit.paint(Color(0.6, 0.14, 0.1), 0.4, 0.1, 0.7, 1.0, 0.85, 161)
	var white := MatKit.paint(Color(0.82, 0.8, 0.74), 0.4, 0.1, 0.7, 1.0, 0.85, 162)
	var nrm: Array[Vector3] = []
	var tan: Array[Vector3] = []
	for i in n:
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		tan.append(t)
		nrm.append(Vector3(-t.z, 0, t.x))
	for side: float in [-1.0, 1.0]:
		for i in n:
			var j := (i + 1) % n
			var bend := tan[(i - 4 + n) % n].angle_to(tan[(i + 4) % n]) > 0.16
			var mat: Material = (red if (i / 2) % 2 == 0 else white) if bend else curb
			var o_in := side * (ROAD_W * 0.5 - 0.05)
			var o_out := side * (ROAD_W * 0.5 + 0.45)
			var a_in := pts[i] + nrm[i] * o_in
			var b_in := pts[j] + nrm[j] * o_in
			var a_out := pts[i] + nrm[i] * o_out
			var b_out := pts[j] + nrm[j] * o_out
			var h := 0.14
			var ya := mesh_height(a_in.x, a_in.z)
			var yb := mesh_height(b_in.x, b_in.z)
			var yao := mesh_height(a_out.x, a_out.z)
			var ybo := mesh_height(b_out.x, b_out.z)
			mb.quad(mat, Vector3(a_in.x, ya + h, a_in.z), Vector3(b_in.x, yb + h, b_in.z), Vector3(b_out.x, ybo + h, b_out.z), Vector3(a_out.x, yao + h, a_out.z), Vector3.UP)
			mb.quad(mat, Vector3(a_in.x, ya - 0.05, a_in.z), Vector3(b_in.x, yb - 0.05, b_in.z), Vector3(b_in.x, yb + h, b_in.z), Vector3(a_in.x, ya + h, a_in.z), -nrm[i] * side)
	batch_builder(mb, false, 0.5)
	# Sidewalk slabs along the outer edge (the loop runs clockwise, so the outside is -side).
	_drape(pts, 3.0, 0.06, _m.sidewalk, true, -(ROAD_W * 0.5 + 0.45 + 1.5))


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


## The writing on the outer wall: [text, spot near the wall, (unused), colour, font size].
static func _wall_tags() -> Array:
	var people_w := Color(0.84, 0.84, 0.8)
	var people_r := Color(0.78, 0.18, 0.16)
	var knows := Color(0.92, 0.76, 0.22)
	# Round 12 (owner): mostly praise for Calypso, one opposing line per stage (yellow, no name), the
	# HOLLYWOOD riddle. CALYPSO WILL SAVE US moved up to a billboard; THANK YOU CALYPSO and
	# WE BELIEVE IN CALYPSO are kept for later stages, BREAD AND CIRCUSES for Rome.
	return [
		["HE GAVE US EVERYTHING", Vector3(-35, 1.5, HALF - 0.85), 0.0, people_w, 220],
		["WHOEVER CAN SUPPLY THEM WITH ILLUSIONS\nIS EASILY THEIR MASTER", Vector3(HALF - 0.85, 1.55, 35), 90.0, knows, 120],
		["CALYPSO SEES US", Vector3(-HALF + 0.85, 1.5, 110), -90.0, people_r, 220],
		["A SYMBOL IS ONLY AS STRONG\nAS WHAT HOLDS IT UP.", Vector3(30, 1.7, -HALF + 0.85), 180.0, knows, 130],
	]


static func _behind_writing(p: Vector3, writing: Array) -> bool:
	for w: Array in writing:
		var c: Vector3 = w[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(w[1]) + 1.2:
			return true
	return false


## Where writing goes on the outer wall near `p`: on the steel plate's face (round 11, owner: the
## writing floated a metre in front of the wall), facing into the arena. Same height as p.
## The plate's inner face is WALL_FACE metres outside the line between the corners.
const WALL_FACE := 0.2

func _on_wall(p: Vector3) -> Transform3D:
	var corners := _wall_corners()
	var best := Transform3D(Basis.IDENTITY, p)
	var best_d := INF
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var flat := Vector3(p.x, 0.0, p.z)
		var t := clampf((flat - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var on := a.lerp(b, t)
		var d := on.distance_to(flat)
		if d < best_d:
			best_d = d
			var out := ((a + b) * 0.5).normalized()
			# local +Z (the side the text reads from) points into the arena
			best = Transform3D(Basis.looking_at(out, Vector3.UP), on + out * (WALL_FACE - 0.012) + Vector3.UP * p.y)
	return best


## Outer wall: rusted steel plate (owner: "steel walls") with a chain-link fence on top, so the city
## below shows through. The collider is the full 8 m.
func _outer_wall() -> void:
	var h := 8.0
	var barrier_h := 2.8
	var corners := _wall_corners()
	# Where the writing goes, and how wide it is (the ribs are left out behind it).
	var writing: Array = []
	for t: Array in _wall_tags():
		var tm := TextMesh.new()
		tm.text = t[0]
		tm.font_size = t[4]
		tm.pixel_size = 0.007
		writing.append([_on_wall(t[1]).origin, tm.get_aabb().size.x * 0.5 + 0.5])
	var mb := MeshBuilder.new()
	# The chain-link: one flat sheet per side, all in one mesh (it was a thin box per side: two
	# see-through layers to shade and a draw call each).
	var fence := SurfaceTool.new()
	fence.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		# No way out of the stage (owner, round 6): an invisible wall far above the fence that only
		# cars hit (layer 5), so missiles still fly over the fence.
		var barrier := StaticBody3D.new()
		barrier.collision_layer = VEHICLE_BARRIER_LAYER
		barrier.collision_mask = 0
		barrier.position = mid + Vector3.UP * (h + BARRIER_H * 0.5)
		barrier.rotation_degrees.y = yaw
		add_child(barrier)
		var bshape := CollisionShape3D.new()
		var bbox := BoxShape3D.new()
		bbox.size = Vector3(length, BARRIER_H, 2.0)
		bshape.shape = bbox
		barrier.add_child(bshape)
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		mb.box(_m.wall_steel, Vector3(length, barrier_h, 1.6), Transform3D(basis, mid + Vector3.UP * barrier_h * 0.5), 0.02)
		mb.box(_m.rib, Vector3(length + 0.1, 0.22, 1.9), Transform3D(basis, mid + Vector3.UP * (barrier_h + 0.05)), 0.02)
		mb.box(_m.hazard, Vector3(length, 0.5, 1.64), Transform3D(basis, mid + Vector3.UP * 0.25), 0.0)
		var ribs := int(length / 3.0)
		for k in ribs + 1:
			var t := -length * 0.5 + k * length / ribs
			if _behind_writing(mid + dir * t, writing):
				continue # the plate stays flat where something is painted on it (round 11)
			mb.box(_m.rib, Vector3(0.25, barrier_h, 1.8), Transform3D(basis, mid + dir * t + Vector3.UP * barrier_h * 0.5), 0.03)
			if k % 2 == 0:
				mb.box(_m.rib, Vector3(0.16, h - barrier_h, 0.16), Transform3D(basis, mid + dir * t + Vector3.UP * (barrier_h + (h - barrier_h) * 0.5)), 0.02)
		mb.box(_m.rib, Vector3(length, 0.12, 0.12), Transform3D(basis, mid + Vector3.UP * (h - 0.1)), 0.0)
		for wire in 3:
			mb.box(_m.rib, Vector3(length, 0.03, 0.03), Transform3D(basis, mid + Vector3.UP * (h + 0.15 + wire * 0.22) + out * (0.15 + wire * 0.15)), 0.0)
		var f0 := mid - dir * length * 0.5 + Vector3.UP * (barrier_h + 0.1)
		var f1 := mid + dir * length * 0.5 + Vector3.UP * (barrier_h + 0.1)
		var up := Vector3.UP * (h - barrier_h - 0.2)
		fence.set_normal(-out)
		for v: Vector3 in [f0, f0 + up, f1 + up, f0, f1 + up, f1]:
			fence.add_vertex(v)
	var fence_mi := MeshInstance3D.new()
	fence_mi.name = "Fence"
	fence_mi.mesh = fence.commit()
	fence_mi.material_override = _m.chainlink
	fence_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fence_mi)
	batch_builder(mb, true, 0.8)
	# Writing on the walls (owner, round 10). Two voices:
	#  - the people, in white, red and blue: they blame City Hall and thank Calypso, who "stayed";
	#  - THE ONE WHO KNOWS, always in the same ochre yellow: real sayings about crowds, circuses and
	#    who profits (sources in docs/design/14-texts-los-angeles.md), and a riddle for the stage's secret.
	# Every spot is clear of the buildings on the walls (one used to hide behind the donut shop).
	var tags := _wall_tags()
	for t in tags:
		var xf := _on_wall(t[1])
		batch_text(t[0], xf * Transform3D(Basis.IDENTITY, Vector3(0.05, -0.05, -0.006)), t[4], 0.007, Color(0.05, 0.05, 0.05)) # drop shadow
		batch_text(t[0], xf, t[4], 0.007, t[3])


## Twin tunnels on the north straight: the road runs through them along x, a divider between the
## tubes, glass walls you can smash through, a freeway deck on top reached from the battleground.
func _tunnels() -> void:
	var cz := ROAD_NORTH_Z
	var length := TUNNEL_X * 2.0
	var width := TUNNEL_Z1 - TUNNEL_Z0
	var zc := (TUNNEL_Z0 + TUNNEL_Z1) * 0.5
	MeshKit.solid_box(self, Vector3(length, 1.0, width), Vector3(0, ROOF_Y - 0.5, zc), _m.deck)
	var mb := MeshBuilder.new()
	for z: float in [cz - 9.0, cz + 9.0]:
		for i in 8:
			mb.box(_m.white_line, Vector3(4.0, 0.04, 0.25), MeshBuilder.at(Vector3(-28 + i * 8.0, ROOF_Y + 0.02, z)), 0.0)
	for z: float in [TUNNEL_Z0 + 0.6, TUNNEL_Z1 - 0.6]:
		mb.box(_m.yellow_line, Vector3(length, 0.05, 0.6), MeshBuilder.at(Vector3(0, ROOF_Y + 0.03, z)), 0.0)
	# Freeway sign at the roof's east end, facing west along the deck (keeps the view north clear).
	var sign_post := Vector3(TUNNEL_X - 1.5, ROOF_Y, zc)
	for dz: float in [-4.5, 4.5]:
		MeshKit.cylinder(self, 0.25, 6.0, sign_post + Vector3(0, 3.0, dz), _m.steel)
	MeshKit.box(self, Vector3(0.3, 3.2, 11.0), sign_post + Vector3(0, 6.6, 0), MeshKit.mat(Color(0.1, 0.4, 0.22), 0.6))
	batch_text("101  HOLLYWOOD FWY", Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), sign_post + Vector3(-0.2, 6.6, 0)),
		fit_font("101  HOLLYWOOD FWY", 0.012, 10.0, 2.6, 140), 0.012, Color(0.95, 0.95, 0.92), true)
	# Walls along x: pillars every 8 m with glass between. The roof ramps cover bays on the south side.
	var ramp_bays := [1, 2, 5, 6]
	for wall_z: float in [TUNNEL_Z0 + 0.5, cz, TUNNEL_Z1 - 0.5]:
		var thick := 2.0 if wall_z == cz else 1.0
		for i in 9:
			var x := -TUNNEL_X + i * 8.0
			_solid_box_mb(mb, _m.concrete_dark, Vector3(1.4, ROOF_Y - 1.0, thick + 0.4), MeshBuilder.at(Vector3(x, (ROOF_Y - 1.0) * 0.5, wall_z)))
		for i in 8:
			var xc := -TUNNEL_X + 4.0 + i * 8.0
			if wall_z == TUNNEL_Z1 - 0.5 and i in ramp_bays:
				_solid_box_mb(mb, _m.concrete_dark, Vector3(6.6, ROOF_Y - 1.0, thick), MeshBuilder.at(Vector3(xc, (ROOF_Y - 1.0) * 0.5, wall_z)))
			else:
				_glass_panel(Vector3(xc, 0, wall_z), thick)
	# Divider noses: wedges that deflect cars into one tube or the other.
	for s: float in [-1.0, 1.0]:
		# Prism: width across the road (local x -> world z), apex pointing out of the tunnel
		# (local y -> world x), height up (local z -> world y).
		var nose := MeshKit.prism(self, Vector3(2.4, 5.0, ROOF_Y - 1.0), Vector3(s * (TUNNEL_X + 2.5), (ROOF_Y - 1.0) * 0.5, cz), _m.concrete_dark)
		nose.basis = Basis(Vector3(0, 0, 1), Vector3(s, 0, 0), Vector3(0, s, 0))
		MeshKit.solid_mesh(self, nose)
		mb.box(_m.hazard, Vector3(0.1, 0.6, 2.6), MeshBuilder.at(Vector3(s * (TUNNEL_X + 0.1), 2.0, cz)), 0.0)
	for z: float in [(TUNNEL_Z0 + cz) * 0.5, (cz + TUNNEL_Z1) * 0.5]:
		for x: float in [-20.0, 0.0, 20.0]:
			mb.box(_tunnel_lamp(), Vector3(6.0, 0.1, 1.0), MeshBuilder.at(Vector3(x, ROOF_Y - 1.06, z)), 0.0)
			var l := OmniLight3D.new()
			l.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
			l.visible = GraphicsSettings.high
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
			mb.box(_m.yellow_line, Vector3(9.0, 0.05, 1.2), MeshBuilder.at(Vector3(x, PLAT_H + (ROOF_Y - PLAT_H) * t + 0.06, z), Vector3(rad_to_deg(atan((ROOF_Y - PLAT_H) / run)), 0, 0)), 0.0)
		ramps.append({"foot": Vector3(x, PLAT_H, z0 + 10.0), "top": Vector3(x, ROOF_Y, z1 - 8.0), "w": 14.0})
	# The gap between the two ramps' supports was a closed pit: a car that fell in had no way out
	# (owner, round 7). Filled to battleground height: a concrete apron in front of the tunnel.
	var fz0 := -PLAT_B + 0.5
	MeshKit.solid_box(self, Vector3(18.2, PLAT_H, absf(TUNNEL_Z1 - fz0) + 1.0), Vector3(0, PLAT_H * 0.5, (fz0 + TUNNEL_Z1) * 0.5), _m.concrete_dark)
	batch_builder(mb)
	# Teleporter on the roof: straight into the cage with the super health.
	var tp := Teleporter.new()
	add_child(tp)
	tp.global_position = Vector3(-TUNNEL_X + 8.0, ROOF_Y, TUNNEL_Z0 + 8.0)
	tp.destination = Transform3D(Basis(Vector3.UP, PI), DECK_CENTER + Vector3(0, DECK_Y + 0.1, -9))


var _tunnel_lamp_mat: StandardMaterial3D

func _tunnel_lamp() -> StandardMaterial3D:
	if _tunnel_lamp_mat == null:
		_tunnel_lamp_mat = MeshKit.emissive(Color(1.0, 0.95, 0.8), 3.0)
	return _tunnel_lamp_mat


func _glass_panel(at: Vector3, thick: float) -> void:
	var b := Breakable.new()
	b.health = Breakable.MG_HEALTH_LIGHT
	b.kind = "glass"
	b.size_hint = Vector3(6.6, ROOF_Y - 1.4, 0.3)
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
	ramps.append({"foot": c + Vector3(0, 0, 52), "top": c + Vector3(0, DECK_Y, 6), "w": 12.0})
	var fence_h := 4.5
	var y := DECK_Y + fence_h * 0.5
	var runs := [
		[Vector3(-15, 0, -15), Vector3(15, 0, -15)],
		[Vector3(-15, 0, -15), Vector3(-15, 0, 15)],
		[Vector3(15, 0, -15), Vector3(15, 0, 15)],
		[Vector3(-15, 0, 15), Vector3(-6.5, 0, 15)],
		[Vector3(6.5, 0, 15), Vector3(15, 0, 15)],
	]
	var cage := MeshBuilder.new()
	for run in runs:
		var a: Vector3 = c + run[0]
		var b: Vector3 = c + run[1]
		var mid := (a + b) * 0.5
		var along_x := absf(b.x - a.x) > 0.1
		var size := Vector3(a.distance_to(b), fence_h, 0.12) if along_x else Vector3(0.12, fence_h, a.distance_to(b))
		MeshKit.solid_box(self, size, mid + Vector3.UP * y, _m.chainlink).add_to_group(&"see_through") # the taser sees through fences
		var posts := int(a.distance_to(b) / 5.0) + 1
		for k in posts:
			var p := a.lerp(b, float(k) / maxf(1.0, posts - 1))
			cage.cylinder(_m.steel, 0.12, fence_h + 0.4, MeshBuilder.at(p + Vector3.UP * (DECK_Y + (fence_h + 0.4) * 0.5)), 6)
		cage.box(_m.steel, size + Vector3(0.1, -fence_h + 0.12, 0.1), MeshBuilder.at(mid + Vector3.UP * (DECK_Y + fence_h)), 0.0)
	batch_builder(cage)
	var warn_xf := Transform3D(Basis.IDENTITY, c + Vector3(-11, DECK_Y + 3.0, 15.15))
	# The sign is painted on a steel plate wired to the fence (round 11: on bare chain-link the
	# lettering seemed to float).
	var plate := MeshBuilder.new()
	plate.box(_m.steel, Vector3(4.6, 1.9, 0.05), MeshBuilder.at(warn_xf.origin + Vector3(0, -0.05, -0.05)), 0.01)
	for px: float in [-2.1, 2.1]:
		for py: float in [-0.8, 0.7]:
			plate.cylinder(_m.steel, 0.04, 0.08, MeshBuilder.at(warn_xf.origin + Vector3(px, py - 0.05, -0.02), Vector3(90, 0, 0)), 6)
	batch_builder(plate)
	var depot_fs := fit_font("CALYPSO RELIEF\nDEPOT 7", 0.012, 4.1, 1.6, 120) # inside the 4.6 x 1.9 m plate
	batch_text("CALYPSO RELIEF\nDEPOT 7", warn_xf * Transform3D(Basis.IDENTITY, Vector3(0.03, -0.03, -0.02)), depot_fs, 0.012, Color(0.05, 0.05, 0.05))
	batch_text("CALYPSO RELIEF\nDEPOT 7", warn_xf, depot_fs, 0.012, Color(0.95, 0.2, 0.15))
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
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
	st.index()
	batch_mesh(st.commit(), Transform3D.IDENTITY, false, mat)


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
	FirePool.spawn(self, bottom, 4.5, 0.0, 4.0, null, false) # burns cars; the flames below draw it
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		var p := bottom + Vector3(cos(a) * 2.6, 0.4, sin(a) * 2.6)
		var pipe := MeshKit.cylinder(self, 0.55, 3.4, p, _m.rust, Vector3(0, 0, 0), 10)
		pipe.basis = Basis(Quaternion(Vector3.UP, Vector3(-cos(a) * 0.5, 1.0, -sin(a) * 0.5).normalized()))
	# Round 5 (frames at the pit): on LOW the pit is one column of fewer flames, two side fires and
	# light smoke (was ~110 big see-through quads stacked on each other; now ~45).
	var high := GraphicsSettings.high
	# Round 18 (owner's pick): the pit burns with the game's fire, a tall rolling column of hair-strand
	# puffs in the middle and two or three lower fires round it (fewer puffs on LOW).
	var pit := FoamFire.new()
	pit.position = bottom + Vector3.UP * 0.3
	pit.box = Vector3(3.0, 0.1, 3.0)
	pit.size = 3.6
	pit.rate = 40.0 if high else 28.0
	pit.life = 1.6
	pit.rise = 5.8
	pit.inherit = 0.0
	add_child(pit)
	pit.on = true
	for k in (3 if high else 2):
		var a := k * TAU / 3.0 + 0.5
		var side := FoamFire.new()
		side.position = ground(cos(a) * 6.0, sin(a) * 6.0, 0.1)
		side.box = Vector3(1.0, 0.05, 1.0)
		side.size = 1.6
		side.rate = 14.0
		side.life = 0.9
		side.rise = 2.4
		side.inherit = 0.0
		add_child(side)
		side.on = true
	var smoke := FxKit.smoke(3.0, 16 if high else 10)
	smoke.position = bottom + Vector3.UP * 7.0
	add_child(smoke)
	smoke.emitting = true
	var light := FlickerLight.new()
	light.light_color = Color(1.0, 0.36, 0.1)
	light.base_energy = 1.6
	light.omni_range = 14.0
	light.position = bottom + Vector3.UP * 4.0
	add_child(light)
	var slabs := MeshBuilder.new()
	for k in 10:
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(8.0, 18.0)
		var p := ground(cos(a) * r, sin(a) * r, 0.1)
		slabs.box(_m.concrete_dark, Vector3(_rng.randf_range(2, 4), 0.3, _rng.randf_range(1.5, 3)), MeshBuilder.at(p, Vector3(_rng.randf_range(-6, 6), _rng.randf_range(0, 180), _rng.randf_range(-6, 6))), 0.08)
	batch_builder(slabs)


## Burnt-out building you can drive through (north and south doors, 10 m wide).
func _burnt_building(c: Vector3) -> void:
	var w := 22.0
	var d := 16.0
	var h := 13.0
	var door := 10.0
	var side := (w - door) * 0.5
	var b := c.y
	var mb := MeshBuilder.new()
	_solid_box_mb(mb, _m.brick, Vector3(1.0, h, d), MeshBuilder.at(c + Vector3(-w * 0.5 + 0.5, h * 0.5, 0)))
	_solid_box_mb(mb, _m.brick, Vector3(1.0, h * 0.8, d), MeshBuilder.at(c + Vector3(w * 0.5 - 0.5, h * 0.4, 0)))
	for s: float in [-1.0, 1.0]:
		var z := c.z + s * (d * 0.5 - 0.5)
		_solid_box_mb(mb, _m.brick, Vector3(side, h, 1.0), MeshBuilder.at(Vector3(c.x - w * 0.5 + side * 0.5, b + h * 0.5, z)))
		_solid_box_mb(mb, _m.brick, Vector3(side, h * 0.85, 1.0), MeshBuilder.at(Vector3(c.x + w * 0.5 - side * 0.5, b + h * 0.425, z)))
		_solid_box_mb(mb, _m.brick, Vector3(door, h - 6.0, 1.0), MeshBuilder.at(Vector3(c.x, b + 6.0 + (h - 6.0) * 0.5, z)))
		mb.box(_m.char, Vector3(door + 0.4, 0.6, 1.2), MeshBuilder.at(Vector3(c.x, b + 6.0, z)), 0.0)
		for k in 3:
			var x := c.x - w * 0.5 + 2.0 + k * 3.2 if k < 2 else c.x + w * 0.5 - 3.0
			mb.box(_m.dark, Vector3(1.8, 2.2, 1.1), MeshBuilder.at(Vector3(x, b + 9.0, z)), 0.0)
			mb.box(_m.char, Vector3(2.0, 1.5, 1.12), MeshBuilder.at(Vector3(x, b + 10.8, z)), 0.0)
	_solid_box_mb(mb, _m.char, Vector3(w, 0.6, d), MeshBuilder.at(c + Vector3(0, 6.3, 0))) # first floor
	mb.box(_m.char, Vector3(w * 0.6, 0.5, d * 0.7), MeshBuilder.at(c + Vector3(-3, h - 0.3, -1), Vector3(0, 0, -8)), 0.0)
	batch_builder(mb)
	var smoke := FxKit.smoke(2.5, 24)
	smoke.position = c + Vector3(2, h + 1.0, 0)
	add_child(smoke)
	smoke.emitting = true
	var embers := FoamFire.new() # still burning on the first floor (the game's fire, round 18)
	embers.position = c + Vector3(-6, 6.6, 0)
	embers.box = Vector3(1.4, 0.05, 1.0)
	embers.size = 1.2
	embers.rate = 14.0
	embers.life = 0.8
	embers.inherit = 0.0
	add_child(embers)
	embers.on = true
	var glow := FlickerLight.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.base_energy = 2.0
	glow.omni_range = 12.0
	glow.position = c + Vector3(-5, 4.0, 0)
	glow.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	glow.visible = GraphicsSettings.high
	add_child(glow)


## High-voltage tower: shoot (or ram) its four legs and it falls, dropping three weapons.
func _power_tower() -> void:
	var at := TOWER_AT
	_tower_upper = Node3D.new()
	_tower_upper.position = at
	add_child(_tower_upper)
	var top := 30.0
	var tb := MeshBuilder.new() # the upper body: one mesh per material, falls as one piece
	var corners := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]
	for k in corners:
		var s: Vector3 = k
		var leg := Breakable.new()
		leg.health = Breakable.MG_HEALTH_LIGHT
		leg.smash_on_contact = false
		leg.ram_damage_mult = 1.0
		leg.debris_color = Color(0.45, 0.46, 0.48)
		leg.kind = "metal"
		leg.size_hint = Vector3(1.8, 9.0, 1.8)
		leg.position = at + s * 5.0
		add_child(leg)
		leg.add_box_shape(Vector3(1.4, 9.0, 1.4), Vector3(-s.x * 0.7, 4.5, -s.z * 0.7))
		var lb := MeshBuilder.new()
		lb.box(_m.concrete, Vector3(1.8, 0.7, 1.8), MeshBuilder.at(Vector3(0, 0.35, 0)), 0.05)
		_beam(lb, _m.steel, Vector3(0, 0.6, 0), Vector3(-s.x * 1.4, 9.0, -s.z * 1.4), 0.45)
		lb.commit(leg.visual)
		leg.broken.connect(_on_tower_leg_broken)
		_beam(tb, _m.steel, s * 3.6 + Vector3.UP * 9.0, s * 1.2 + Vector3.UP * top, 0.4)
	for level in 5:
		var y0 := 9.0 + level * 4.2
		var y1 := y0 + 4.2
		var r0 := lerpf(3.6, 1.2, (y0 - 9.0) / (top - 9.0))
		var r1 := lerpf(3.6, 1.2, (y1 - 9.0) / (top - 9.0))
		for f in 4:
			var a := Vector3(-1, 0, -1).rotated(Vector3.UP, f * PI * 0.5)
			var b := Vector3(-1, 0, -1).rotated(Vector3.UP, (f + 1) * PI * 0.5)
			_beam(tb, _m.steel, a * r0 + Vector3.UP * y0, b * r1 + Vector3.UP * y1, 0.15)
			_beam(tb, _m.steel, b * r0 + Vector3.UP * y0, a * r1 + Vector3.UP * y1, 0.15)
	for y: float in [21.0, 26.0]:
		var arm := 8.0 if y < 25.0 else 6.0
		_beam(tb, _m.steel, Vector3(-arm, y, 0), Vector3(arm, y, 0), 0.4)
		for x: float in [-arm + 0.5, arm - 0.5]:
			for k in 3:
				tb.cylinder(_insulator(), 0.22, 0.25, MeshBuilder.at(Vector3(x, y - 0.6 - k * 0.3, 0)), 8)
	# Round 10 (owner: "how is the sign pinned to the tower, and why does it float when the tower is
	# down?"): a ring of beams joins the leg tops, the warning sign hangs from the front beam on two
	# steel hangers, and sign, hangers and lettering are all part of the upper body, so they come
	# down with it.
	for f in 4:
		var ra := Vector3(-3.6, 9.0, -3.6).rotated(Vector3.UP, f * PI * 0.5)
		var rb := Vector3(-3.6, 9.0, -3.6).rotated(Vector3.UP, (f + 1) * PI * 0.5)
		_beam(tb, _m.steel, ra, rb, 0.3)
	var sign_c := Vector3(0, 6.9, 3.6)
	for hx: float in [-1.9, 1.9]:
		_beam(tb, _m.steel, Vector3(hx, 9.0, 3.6), Vector3(hx, sign_c.y + 0.9, 3.6), 0.12)
		tb.box(_m.steel, Vector3(0.3, 0.3, 0.22), MeshBuilder.at(Vector3(hx, sign_c.y + 0.9, 3.6)), 0.02) # clamp
	_beam(tb, _m.steel, Vector3(-2.4, sign_c.y + 1.25, 3.6), Vector3(2.4, sign_c.y + 1.25, 3.6), 0.14) # top rail
	tb.box(MatKit.paint(Color(0.7, 0.55, 0.08), 0.6, 0.6, 0.6, 2.0, 0.7, 120), Vector3(4.6, 2.4, 0.08), MeshBuilder.at(sign_c), 0.0)
	tb.commit(_tower_upper)
	for face: float in [1.0, -1.0]:
		var tm := TextMesh.new()
		tm.text = "DANGER\nHIGH VOLTAGE"
		tm.font_size = 90
		tm.pixel_size = 0.009
		tm.depth = 0.0
		var label := MeshInstance3D.new()
		label.mesh = tm
		var ink := StandardMaterial3D.new()
		ink.albedo_color = Color(0.05, 0.04, 0.03)
		ink.roughness = 0.8
		label.material_override = ink
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.transform = Transform3D(Basis(Vector3.UP, 0.0 if face > 0.0 else PI), sign_c + Vector3(0, 0, 0.05 * face))
		_tower_upper.add_child(label)
	# Power lines running off over the wall toward the city (merged into the static stage).
	var wires := MeshBuilder.new()
	var wire_mat := MatKit.flat(Color(0.08, 0.08, 0.08), 0.6)
	for x: float in [-7.5, 7.5, -5.5, 5.5]:
		var y := 20.0 if absf(x) > 6.0 else 25.0
		var a := at + Vector3(x, y, 0)
		var b := Vector3(HALF + 70.0, 18.0, HALF + 30.0 + x)
		var prev := a
		for k in 12:
			var t := float(k + 1) / 12.0
			var p := a.lerp(b, t) - Vector3(0, 6.0 * 4.0 * t * (1.0 - t), 0)
			wires.cylinder(wire_mat, 0.05, prev.distance_to(p), MeshBuilder.along((prev + p) * 0.5, p - prev), 4, -1.0, false)
			prev = p
	batch_builder(wires, false)


var _insulator_mat: StandardMaterial3D

func _insulator() -> StandardMaterial3D:
	if _insulator_mat == null:
		_insulator_mat = MeshKit.mat(Color(0.3, 0.45, 0.6), 0.2, 0.3)
	return _insulator_mat


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
		# Round 7: two stands moved off the ramp sides (a 2-3 m slot beside a ramp traps a car).
		[Vector3(-30, 0, 52), 0.0], [Vector3(80, 0, 14), 90.0], [Vector3(-12, 0, -58), 180.0],
		[Vector3(-123, 0, 6), 90.0], [Vector3(96, 0, 70), -60.0], [Vector3(-60, 0, 108), 0.0],
	]
	for s in spots:
		var p: Vector3 = s[0]
		_hot_dog_stand(ground(p.x, p.z), s[1])


## Stand with a giant hot dog on the roof. Breaks into a weapon. All stands share one mesh.
func _hot_dog_stand(pos: Vector3, yaw: float) -> void:
	var b := Breakable.new()
	b.health = Breakable.MG_HEALTH_LIGHT
	b.kind = "wood"
	b.size_hint = Vector3(4.2, 3.0, 3.0)
	b.loot = "weapon"
	b.debris_color = Color(0.95, 0.85, 0.6)
	b.position = pos
	b.rotation_degrees.y = yaw
	add_child(b)
	b.add_box_shape(Vector3(4.2, 3.0, 3.0), Vector3(0, 1.5, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = _stand_mesh()
	b.visual.add_child(mi)
	var l := Label3D.new()
	l.text = "HOT DOGS"
	l.font_size = 90
	l.pixel_size = 0.01
	l.shaded = true
	l.modulate = Color(0.5, 0.08, 0.06)
	l.position = Vector3(0, 2.15, -1.48)
	l.rotation_degrees.y = 180.0
	b.visual.add_child(l)


var _stand_mesh_cache: ArrayMesh

func _stand_mesh() -> ArrayMesh:
	if _stand_mesh_cache:
		return _stand_mesh_cache
	var mb := MeshBuilder.new()
	var cart := MatKit.paint(Color(0.7, 0.67, 0.6), 0.7, 0.5, 0.75, 1.5, 0.6, 130)
	var stripe := MatKit.paint(Color(0.48, 0.1, 0.08), 0.7, 0.4, 0.6, 1.5, 0.6, 131)
	var bun := MatKit.paint(Color(0.66, 0.46, 0.26), 0.6, 0.0, 0.6, 1.0, 0.8, 132)
	var sausage := MatKit.paint(Color(0.42, 0.16, 0.1), 0.5, 0.0, 0.5, 1.0, 0.6, 133)
	var mustard := MatKit.flat(Color(0.7, 0.58, 0.12), 0.6)
	var dark := MatKit.flat(Color(0.06, 0.06, 0.07), 0.8)
	mb.box(cart, Vector3(4.0, 2.4, 2.8), MeshBuilder.at(Vector3(0, 1.2, 0)), 0.06)
	mb.box(stripe, Vector3(4.04, 0.4, 2.84), MeshBuilder.at(Vector3(0, 0.5, 0)), 0.03)
	mb.box(dark, Vector3(2.6, 1.0, 0.1), MeshBuilder.at(Vector3(0, 1.6, -1.42)), 0.0)
	for i in 6:
		mb.box(stripe if i % 2 == 0 else cart, Vector3(0.66, 0.22, 3.3), MeshBuilder.at(Vector3(-1.66 + i * 0.66, 2.55, 0), Vector3(10, 0, 0)), 0.02)
	for s: float in [-1.0, 1.0]:
		mb.sphere(bun, 0.6, MeshBuilder.at(Vector3(0, 3.25, s * 0.32), Vector3.ZERO, Vector3(3.4, 0.7, 0.75)), 14, 8)
	mb.sphere(sausage, 0.45, MeshBuilder.at(Vector3(0, 3.55, 0), Vector3.ZERO, Vector3(5.0, 0.9, 0.9)), 14, 8)
	for i in 7:
		var flip := 1.0 if i % 2 == 0 else -1.0
		mb.box(mustard, Vector3(0.5, 0.06, 0.1), MeshBuilder.at(Vector3(-1.5 + i * 0.5, 3.96, 0.1 * flip), Vector3(0, 30.0 * flip, 0)), 0.0)
	_stand_mesh_cache = mb.build_mesh(0.6, 0.0, true)
	return _stand_mesh_cache


## Palms on the low ground: tall LA fan palms along the outside of the road, date palms on the
## inside. They topple when hit.
func _palms() -> void:
	var pts := road_points()
	var k := 0
	while k < pts.size():
		var p := pts[k]
		var nxt := pts[(k + 1) % pts.size()]
		var dir := (nxt - p).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var s := 1.0 if (k / 9) % 2 == 0 else -1.0
		var outside := s < 0.0
		var spot := p + side * s * (ROAD_W * 0.5 + (4.6 if outside else 3.5))
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
			_palm(ground(spot.x, spot.z), outside)


func _palm(pos: Vector3, fan := false) -> void:
	var b := Breakable.new()
	b.style = Breakable.Style.TOPPLE
	b.health = Breakable.MG_HEALTH
	b.kind = "palm"
	b.size_hint = Vector3(1.0, 6.0, 1.0)
	b.topple_height = 7.0
	b.fall_mass = 320.0
	b.stump_radius = 0.24
	b.debris_color = Color(0.45, 0.36, 0.24)
	b.position = pos
	b.rotation.y = _rng.randf() * TAU
	add_child(b)
	b.add_box_shape(Vector3(1.0, 5.0, 1.0), Vector3(0, 2.5, 0))
	b.add_cover(1.5, 6.5) # hide behind it from missiles (round 9)
	var mi := MeshInstance3D.new()
	mi.mesh = _fan_palm_mesh(_rng.randi() % 2) if fan else _palm_mesh(_rng.randi() % 3)
	var s := _rng.randf_range(0.85, 1.15)
	mi.scale = Vector3(s, s, s)
	b.visual.add_child(mi)


## LA fan palm (the tall skinny one): slim ringed trunk, a shaggy skirt of dead fronds under a
## round crown of fan leaves. Two variants, one mesh each.
func _fan_palm_mesh(variant: int) -> ArrayMesh:
	var key := "fan%d" % variant
	if _palm_meshes.has(key):
		return _palm_meshes[key]
	var r := RandomNumberGenerator.new()
	r.seed = 400 + variant
	var bark := MatKit.paint(Color(0.42, 0.36, 0.28), 0.2, 0.0, 0.6, 0.5, 0.95, 154)
	var skirt := MatKit.paint(Color(0.4, 0.31, 0.2), 0.1, 0.0, 0.7, 0.6, 0.97, 155)
	var leaf := MatKit.paint(Color(0.26, 0.35, 0.17), 0.1, 0.0, 0.5, 1.0, 0.8, 156)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mb := MeshBuilder.new()
	var height := 16.0 + variant * 3.0
	var lean := Vector3(r.randf_range(0.4, 1.2), 0, 0)
	var segs := 8
	var prev := Vector3.ZERO
	for k in segs:
		var t := float(k + 1) / segs
		var p := Vector3.UP * height * t + lean * t * t
		var rad := lerpf(0.36, 0.24, t)
		var dir := p - prev
		mb.cylinder(bark, rad, dir.length() + 0.05, MeshBuilder.along((prev + p) * 0.5, dir), 8, rad * 0.96, false)
		prev = p
	var top := prev
	mb.cylinder(skirt, 0.95, 2.6, MeshBuilder.at(top + Vector3(0, -1.0, 0)), 10, 0.6)
	for k in 10: # ragged hanging ends of the skirt
		var a := TAU * k / 10.0
		mb.box(skirt, Vector3(0.35, 0.9, 0.05), MeshBuilder.at(top + Vector3(cos(a) * 0.95, -2.6, sin(a) * 0.95), Vector3(0, -rad_to_deg(a) + 90.0, 0)), 0.0)
	for k in 16:
		var yaw := TAU * k / 16.0 + r.randf_range(-0.1, 0.1)
		var out := Vector3(cos(yaw), 0, sin(yaw))
		var tilt := r.randf_range(-0.25, 0.55)
		var stem_end := top + (out + Vector3.UP * tilt).normalized() * 1.8
		var fwd := (stem_end - top).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		mb.box(leaf, Vector3(0.08, 0.05, 1.8), Transform3D(Basis(side, side.cross(fwd), -fwd), (top + stem_end) * 0.5), 0.0)
		for f in 5: # the fan: five leaflet blades spread from the stem's end
			var spread := (f - 2) * 0.32
			var bdir := (fwd.rotated(Vector3.UP, spread) + Vector3.DOWN * 0.15).normalized()
			var bend := stem_end + bdir * 1.3
			var bside := bdir.cross(Vector3.UP).normalized()
			mb.box(leaf, Vector3(0.32, 0.03, 1.3), Transform3D(Basis(bside, bside.cross(bdir), -bdir), (stem_end + bend) * 0.5), 0.0)
	_palm_meshes[key] = mb.build_mesh(0.25, 0.0, true)
	return _palm_meshes[key]


var _palm_meshes := {}

## Three palm variants, each one mesh: a thick ringed trunk with a gentle lean, a crown of
## drooping two-part fronds, a few dead ones hanging below, a cluster of dates.
func _palm_mesh(variant: int) -> ArrayMesh:
	if _palm_meshes.has(variant):
		return _palm_meshes[variant]
	var r := RandomNumberGenerator.new()
	r.seed = 300 + variant
	var bark := MatKit.paint(Color(0.4, 0.33, 0.24), 0.2, 0.0, 0.6, 0.5, 0.95, 150)
	var ring := MatKit.paint(Color(0.3, 0.24, 0.17), 0.2, 0.0, 0.6, 0.5, 0.95, 151)
	var leaf := MatKit.paint(Color(0.22, 0.32, 0.14), 0.1, 0.0, 0.5, 1.0, 0.8, 152)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dead := MatKit.paint(Color(0.42, 0.34, 0.2), 0.1, 0.0, 0.5, 1.0, 0.9, 153)
	dead.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mb := MeshBuilder.new()
	var height := 11.0 + variant * 2.0
	var lean := Vector3(r.randf_range(0.8, 1.8), 0, 0)
	var segs := 7
	var prev := Vector3.ZERO
	for k in segs:
		var t := float(k + 1) / segs
		var p := Vector3.UP * height * t + lean * t * t
		var rad := lerpf(0.42, 0.27, t)
		var dir := p - prev
		mb.cylinder(bark, rad, dir.length() + 0.05, MeshBuilder.along((prev + p) * 0.5, dir), 8, rad * 0.94, false)
		mb.torus(ring, rad, 0.05, MeshBuilder.along(p, dir), 8, 4)
		prev = p
	var top := prev
	mb.sphere(bark, 0.42, MeshBuilder.at(top), 8, 5)
	for k in 14:
		var yaw := TAU * k / 14.0 + r.randf_range(-0.15, 0.15)
		var out := Vector3(cos(yaw), 0, sin(yaw))
		var rise := r.randf_range(0.15, 0.45) if k % 2 == 0 else r.randf_range(-0.05, 0.2)
		var a := top
		var b := top + out * 2.6 + Vector3.UP * rise * 2.6
		var c := b + out * 2.4 + Vector3.DOWN * r.randf_range(1.0, 1.8)
		for part in 2:
			var p0 := a if part == 0 else b
			var p1 := b if part == 0 else c
			var w := 1.05 if part == 0 else 0.75
			var mid := (p0 + p1) * 0.5
			var fwd := (p1 - p0).normalized()
			var side := fwd.cross(Vector3.UP).normalized()
			var up := side.cross(fwd)
			var basis := Basis(side, up, -fwd)
			mb.box(leaf, Vector3(w, 0.04, p0.distance_to(p1) + 0.1), Transform3D(basis.rotated(fwd, 0.25 * (1.0 if k % 2 == 0 else -1.0)), mid), 0.0)
	for k in 4:
		var yaw := TAU * k / 4.0 + 0.4
		var out := Vector3(cos(yaw), 0, sin(yaw))
		var a := top + Vector3.DOWN * 0.3
		var b := a + out * 0.8 + Vector3.DOWN * 2.4
		var fwd := (b - a).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		mb.box(dead, Vector3(0.7, 0.04, a.distance_to(b)), Transform3D(Basis(side, side.cross(fwd), -fwd), (a + b) * 0.5), 0.0)
	for k in 5:
		mb.sphere(ring, 0.16, MeshBuilder.at(top + Vector3(cos(k * 1.3) * 0.4, -0.5 - (k % 2) * 0.2, sin(k * 1.3) * 0.4)), 6, 4)
	_palm_meshes[variant] = mb.build_mesh(0.3, 0.0, true)
	return _palm_meshes[variant]


## Low shrubs along the foot of the battleground's walls and around the ramps' sides:
## one MultiMesh, so a hundred of them cost a couple of draw calls.
func _bushes() -> void:
	var xforms: Array[Transform3D] = []
	for k in 260:
		var a := TAU * k / 260.0 + _rng.randf_range(-0.01, 0.01)
		var r := 1.0 / pow(pow(absf(cos(a)) / PLAT_A, 4.0) + pow(absf(sin(a)) / PLAT_B, 4.0), 0.25)
		var p := Vector3(cos(a), 0, sin(a)) * (r + _rng.randf_range(2.2, 3.4))
		if _rng.randf() < 0.35:
			continue
		var skip := false
		for rp: Dictionary in ramp_list():
			var rel := p - Vector3(rp.top.x, 0, rp.top.z)
			if absf(rel.dot(rp.side)) < RAMP_W * 0.5 + 2.0 and rel.dot(rp.dir) < RAMP_L + 4.0:
				skip = true
		if absf(p.x) < 24.0 and p.z < -80.0:
			skip = true # the tunnel-roof ramps
		if skip or road_distance(p.x, p.z) < ROAD_W * 0.5 + 2.0:
			continue
		var s := _rng.randf_range(0.8, 1.5)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s)), ground(p.x, p.z)))
	var shrubs := _scatter(_bush_mesh(), xforms)
	shrubs.visibility_range_end = 170.0
	add_child(shrubs)


## One shrub (a few low-poly lumps of dark and olive green), shared by every bush on the stage.
## Round 5: ~120 triangles (was 384 x 537 bushes = 37% of the whole stage's triangles).
func _bush_mesh() -> ArrayMesh:
	if _shrub:
		return _shrub
	var mb := MeshBuilder.new()
	var green := MatKit.paint(Color(0.2, 0.28, 0.14), 0.1, 0.0, 0.5, 1.0, 0.9, 170)
	var olive := MatKit.paint(Color(0.32, 0.34, 0.18), 0.1, 0.0, 0.5, 1.0, 0.9, 171)
	for k in 3:
		var a := TAU * k / 3.0
		mb.sphere(green if k % 2 == 0 else olive, 0.75, MeshBuilder.at(Vector3(cos(a) * 0.5, 0.45, sin(a) * 0.5), Vector3(0, k * 40.0, 0), Vector3(1.0, 0.75, 1.0)), 5, 3)
	mb.sphere(green, 0.8, MeshBuilder.at(Vector3(0, 0.7, 0), Vector3(0, 20, 0), Vector3(1.0, 0.8, 1.0)), 6, 3)
	_shrub = mb.build_mesh(0.4, 0.0, true)
	return _shrub


## Many copies of one mesh in a single draw (per material): bushes, scrub.
func _scatter(mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# ---------------------------------------------------------------- beyond the wall

## The hills north of the arena (outside the walls, out of reach) with the HOLLYWOOD sign on the
## slope. Chaparral: scrub over dry earth, eroded ridges running down. Each letter breaks when
## shot. Too high to hit from the ground: try the tunnel roof.
static func hill_height(x: float, z: float) -> float:
	var t := clampf((-165.0 - z) / 125.0, 0.0, 1.0)
	var lateral := exp(-pow((x + 10.0) / 190.0, 2.0)) * 0.65 + 0.35
	var rise := 88.0 * sin(t * PI * 0.5)
	var peaks := 16.0 * exp(-pow((x + 10.0) / 45.0, 2.0)) + 12.0 * exp(-pow((x - 150.0) / 60.0, 2.0)) \
		+ 9.0 * exp(-pow((x + 175.0) / 55.0, 2.0))
	# Eroded spurs: sharp ridges and rounded gullies running down the slope. Gentler under the sign.
	var spur := (0.45 - absf(sin(x * 0.052 + sin(z * 0.035) * 0.9))) * 14.0
	spur *= lerpf(0.3, 1.0, smoothstep(35.0, 80.0, absf(x + 10.0)))
	return -25.0 + (rise + (peaks + spur) * smoothstep(0.15, 0.7, t)) * lateral


## The HOLLYWOOD secret (owner, round 6): the hills behind stay a picture, but the nine letters
## are real, on a steel scaffold just past the north fence and high above it. Fire a missile with the
## nose up (driving up the tunnel-roof ramps, or off a jump) to hit them; knock all nine down and
## Calypso pays out.
func _hollywood_sign() -> void:
	var word := "HOLLYWOOD"
	var u := 1.3
	var t := 0.95 * u
	var paint := MatKit.paint(Color(0.88, 0.87, 0.83), 0.25, 0.15, 0.45, 3.0, 0.4, 150)
	var steel := MatKit.steel(Color(0.2, 0.2, 0.21), 0.6, 1.0)
	var x0 := -10.0 - 4.5 * 9.0
	var frame := MeshBuilder.new()
	# Scaffold: a deck truss under the letters, legs down behind the fence, cross braces.
	frame.box(steel, Vector3(84.0, 0.5, 0.5), MeshBuilder.at(Vector3(-10.0, SIGN_BASE_Y - 0.3, SIGN3D_Z)), 0.0)
	frame.box(steel, Vector3(84.0, 0.4, 0.4), MeshBuilder.at(Vector3(-10.0, SIGN_BASE_Y - 0.3, SIGN3D_Z - 3.0)), 0.0)
	for k in 8:
		var lx := x0 + k * 11.5
		for dz: float in [0.0, -3.0]:
			frame.box(steel, Vector3(0.45, SIGN_BASE_Y + 14.0, 0.45), MeshBuilder.at(Vector3(lx, (SIGN_BASE_Y - 14.0) * 0.5, SIGN3D_Z + dz)), 0.0)
		frame.box(steel, Vector3(0.25, 0.25, 4.2), MeshBuilder.at(Vector3(lx, SIGN_BASE_Y - 3.0, SIGN3D_Z - 1.5), Vector3(-45, 0, 0)), 0.0)
		if k < 7:
			frame.box(steel, Vector3(13.0, 0.22, 0.22), MeshBuilder.at(Vector3(lx + 5.75, SIGN_BASE_Y - 5.0, SIGN3D_Z), Vector3(0, 0, 28)), 0.0)
	batch_builder(frame, false)
	for i in word.length():
		var x := x0 + 4.5 + i * 9.0
		var letter := Breakable.new()
		letter.style = Breakable.Style.TOPPLE
		letter.smash_on_contact = false
		letter.health = Breakable.MG_HEALTH
		letter.debris_color = Color(0.92, 0.92, 0.88)
		letter.kind = "metal"
		letter.size_hint = Vector3(5.0 * u, 7.5 * u, 1.0)
		letter.topple_height = 7.5 * u
		letter.position = Vector3(x, SIGN_BASE_Y, SIGN3D_Z)
		add_child(letter)
		letter.add_box_shape(Vector3(5.0 * u, 7.5 * u, 1.2), Vector3(0, 3.75 * u, 0))
		var lmb := MeshBuilder.new()
		for stroke: Array in LaOutside.glyph_strokes(word[i]):
			for k in stroke.size() - 1:
				var a: Vector2 = stroke[k]
				var b: Vector2 = stroke[k + 1]
				var pa := Vector3((a.x - 2.0) * u, (a.y + 0.5) * u, 0)
				var pb := Vector3((b.x - 2.0) * u, (b.y + 0.5) * u, 0)
				var dir := (pb - pa).normalized()
				var across := Vector3(-dir.y, dir.x, 0)
				var length := pa.distance_to(pb) + t # overlap at the joints
				lmb.box(paint, Vector3(t, 0.5, length), Transform3D(Basis(across, Vector3.BACK, dir), (pa + pb) * 0.5), 0.0)
		lmb.commit(letter.visual, false, 0.4)
		letter.broken.connect(_on_letter_broken)
		_letters_left += 1


func _on_letter_broken(_letter: Breakable, _by: Vehicle) -> void:
	_letters_left -= 1
	if _letters_left > 0:
		return
	# The sign went up in 1923 as an advertisement for a housing estate ("HOLLYWOODLAND"): a true
	# story, and the answer to the riddle painted on the north wall.
	easter_egg.emit("HOLLYWOODLAND, 1923", "Calypso: \"A sign to sell a hill. I only sell wishes...\nTake this. You are doing so well.\"")
	# Owner, round 9: the prize is a FULL HEALTH (health and energy to 100%), up on the tunnel roof.
	Pickup.create(self, "full", Vector3(0, ROOF_Y, (TUNNEL_Z0 + TUNNEL_Z1) * 0.5 + 6.0), true)


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
	# Item placement (owner, round 9): missiles, napalm and turbo on the road; SAT, Zoomy and Remote in
	# the corners; health and power missiles on the hilltops; a mix in the middle. Every spot always
	# gives the same thing (`weapon_kinds`, parallel to `weapon_points`).
	while weapon_kinds.size() < weapon_points.size(): # spots added earlier (the cage) take from the mix
		weapon_kinds.append("")
	var road_kinds := ["homing", "fire", "napalm", "fire", "homing", "napalm"]
	var n := 0
	for k in 16:
		var p := _road_item_point((k + 0.5) / 16.0)
		if p == Vector3.INF:
			continue
		weapon_points.append(p)
		weapon_kinds.append(road_kinds[n % road_kinds.size()])
		n += 1
	var corner_kinds := {Vector2(1, -1): "sat", Vector2(-1, -1): "zoomy", Vector2(1, 1): "remote", Vector2(-1, 1): "zoomy"}
	for c: Vector2 in corner_kinds:
		weapon_points.append(_corner_point(c))
		weapon_kinds.append(corner_kinds[c])
	var hill_list := hills()
	for i in hill_list.size():
		var top: Vector2 = (hill_list[i] as Dictionary).p
		var at := Vector3(top.x, height_at(top.x, top.y) + 1.4, top.y) # on the crest: grab it as you fly over
		if i == 0:
			weapon_points.append(at)
			weapon_kinds.append("power")
		else:
			health_points.append(at + (Vector3.UP * 1.2 if i == 1 else Vector3.ZERO)) # the middle hill's floats: jump for it
	var middle := {Vector3(-35, 0, 20): "power", Vector3(35, 0, -15): "homing", Vector3(0, 0, -40): "remote",
		Vector3(-60, 0, 60): "fire", Vector3(20, 0, 68): "zoomy", Vector3(-70, 0, -10): "napalm", Vector3(-20, 0, -70): "sat"}
	for m: Vector3 in middle:
		weapon_points.append(ground(m.x, m.z))
		weapon_kinds.append(middle[m])
	for r: Array in [[Vector3(-20, ROOF_Y, TUNNEL_Z1 - 8.0), "homing"], [Vector3(10, ROOF_Y, TUNNEL_Z0 + 10.0), "power"], [Vector3(24, ROOF_Y, TUNNEL_Z0 + 10.0), "fire"]]:
		weapon_points.append(r[0])
		weapon_kinds.append(r[1])
	health_points.append_array([
		ground(26, 22), # by the pit of fire
		ground(BURNT_AT.x + 16.0, BURNT_AT.z), # by the burnt building
		ground(-75, 32), # west side of the battleground (was on the edge wall)
	])
	# Turbo (owner, round 4: five spots): three on the road, one in the middle, one on the tunnel roof.
	for f: float in [0.2, 0.5, 0.8]:
		var p := Vector3.INF
		var ff := f
		while p == Vector3.INF and ff < f + 0.1:
			p = _road_item_point(ff)
			ff += 0.01
		turbo_points.append(p)
	turbo_points.append(ground(40, 15))
	turbo_points.append(Vector3(-4, ROOF_Y, (TUNNEL_Z0 + TUNNEL_Z1) * 0.5))


## A spot on the road for an item at `frac` around the loop, or Vector3.INF when it would sit on a
## hill, by a ramp foot or against a tunnel's divider (round 9: items merged into walls). By the
## tunnels it moves into a lane.
func _road_item_point(frac: float) -> Vector3:
	var p: Vector3 = road_at(frac).p
	for hill: Dictionary in hills():
		if Vector2(p.x, p.z).distance_to(hill.p) < 24.0:
			return Vector3.INF
	for rp: Dictionary in ramp_list():
		if Vector2(p.x, p.z).distance_to(Vector2(rp.foot.x, rp.foot.z)) < 16.0:
			return Vector3.INF
	if absf(p.z - ROAD_NORTH_Z) < 12.0 and absf(p.x) < TUNNEL_X + 14.0:
		if absf(p.x) > TUNNEL_X - 6.0:
			return Vector3.INF # the tunnel mouths and their divider noses
		p.z = ROAD_NORTH_Z + 7.0 # inside, in the south tube's lane
	return ground(p.x, p.z)


## A clear spot in a corner of the low ground (between the road and the outer wall's corner).
func _corner_point(sign: Vector2) -> Vector3:
	var best := Vector3.ZERO
	for t in range(132, 95, -2):
		var x := sign.x * t
		var z := sign.y * t
		if absf(x) + absf(z) > HALF * 2.0 - WALL_CHAMFER - 14.0:
			continue
		if road_distance(x, z) < ROAD_W * 0.5 + 5.0 or edge_distance(x, z) > -8.0:
			continue
		best = ground(x, z)
		break
	return best


func _spot(x: float, z: float, yaw_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), ground(x, z, 0.1))
