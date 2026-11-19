class_name Pickup
extends Area3D
## Weapon, turbo, health or mega health pickup. Respawns after being taken, unless it is a one-off
## (dropped by a broken stand or tower). Owner, play-test 1: each pickup shows its weapon's shape and
## color (fire and homing must never be confused), soft light instead of a glaring glow, and a
## message says what you got ("FIRE MISSILE LOADED"). Turbo pickups refill the turbo bar completely.

const MSG_TURBO := "TURBO REFILLED"

var kind := "homing" # a weapon id, "turbo", "health", "mega" or "full" (health and energy to 100%)
var random_weapon := true # re-roll the weapon each respawn
var respawns := true
var active := true
var bob := true

var _visual: Node3D
var _pad: MeshInstance3D
var _ring: MeshInstance3D # round 12: the bright colour ring around the base
var _respawn := 0.0
var _t := 0.0

static var _meshes := {} # kind -> ArrayMesh, shared by every pickup of that kind


static func create(parent: Node, pickup_kind: String, pos: Vector3, one_off := false) -> Pickup:
	var p := Pickup.new()
	p.kind = pickup_kind
	p.random_weapon = WeaponData.DEFS.has(pickup_kind) and not one_off
	p.respawns = not one_off
	parent.add_child(p)
	p.global_position = pos
	return p


func _ready() -> void:
	collision_layer = 8 # layer 4: pickups
	collision_mask = 2 # vehicles
	monitorable = false
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 2.3 if kind == "full" else (2.0 if kind == "mega" else 1.8)
	shape.shape = s
	shape.position = Vector3.UP * 1.0
	add_child(shape)
	add_to_group("pickups")
	body_entered.connect(_on_body_entered)
	_t = randf() * 10.0
	_build()


func is_health() -> bool:
	return kind == "health" or kind == "mega" or kind == "full"


func is_turbo() -> bool:
	return kind == "turbo"


func _build() -> void:
	if _visual:
		_visual.queue_free()
	if _pad:
		_pad.queue_free()
		_pad = null
	if _ring:
		_ring.queue_free()
		_ring = null
	_visual = Node3D.new()
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 130.0 # far ones still show on the radar
	_visual.add_child(mi)
	if ModelLib.has("pickups") and ModelLib.mesh("pickups", kind) != null:
		# Round 10 (owner: "serious, not cartoonish"): real ordnance and supply cases made in Blender,
		# turning slowly over a steel drop plate whose marker lamps carry the item's colour.
		_blender = true
		mi.mesh = ModelLib.mesh("pickups", kind)
		_brighten(mi)
		_visual.position = Vector3.UP * HOVER
		_visual.scale = Vector3.ONE * ITEM_SCALE
		_pad = MeshInstance3D.new()
		_pad.mesh = ModelLib.mesh("pickups", "pad")
		_pad.position = Vector3.UP * 0.02
		_pad.rotation.y = randf() * TAU
		_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pad.visibility_range_end = 90.0
		add_child(_pad)
		_pad_lamps(true)
		_ring = ring_for(kind)
		add_child(_ring)
	else:
		_blender = false
		mi.mesh = mesh_for(kind)
		_visual.position = Vector3.UP * 1.3
		_visual.scale = Vector3.ONE * 1.25


const HOVER := 1.4 # metres above the plate
const ITEM_SCALE := 1.56 # round 15 (owner): 1.3x bigger (was 1.2)
const ITEM_GLOW := 0.12 # round 15 (owner): the items' own colours a little brighter (self-lit share)
static var _bright: StandardMaterial3D


## The item (not its plate) in a self-lit copy of the baked material, so its colours read from afar
## and in shadow.
static func _brighten(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var atlas := ModelLib.atlas("pickups")
	if _bright == null:
		_bright = atlas.duplicate() as StandardMaterial3D
		_bright.emission_enabled = true
		_bright.emission = Color.WHITE
		_bright.emission_texture = atlas.albedo_texture
		_bright.emission_energy_multiplier = ITEM_GLOW
	for i in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_material(i) == atlas:
			mi.set_surface_override_material(i, _bright)
var _blender := false


## Round 12 (owner): one bright colour per kind on the base, so each item reads from afar.
## Fire, napalm and power are kept clearly apart: yellow, orange, red.
const KIND_COLORS := {
	"homing": Color(0.6, 0.2, 1.0), # purple
	"fire": Color(1.0, 0.88, 0.05), # yellow
	"napalm": Color(1.0, 0.45, 0.0), # orange
	"power": Color(1.0, 0.04, 0.03), # red
	"sat": Color(1.0, 0.15, 0.7), # magenta pink
	"remote": Color(0.0, 0.0, 0.0), # black, with a white rim
	"zoomy": Color(1.0, 1.0, 1.0), # white
	"turbo": Color(0.1, 0.95, 1.0), # cyan
	"health": Color(0.12, 0.35, 1.0), # blue
	"mega": Color(0.12, 0.95, 0.18), # green
	"full": Color(0.78, 0.0, 0.08), # royal red, with a blue collar, bigger and brighter
}
const RING_RIM := {"remote": Color(1.0, 1.0, 1.0), "full": Color(0.15, 0.4, 1.0)}

static var _rings := {}
static var _ring_mats := {}


## The colour that marks this pickup's kind (ring, pad lamps).
func kind_color() -> Color:
	return KIND_COLORS.get(kind, WeaponData.get_def(kind).get("color", Color.WHITE))


## A flat ring on the ground around the base (inner 1.1 m, outer 1.5 m; full health 1.3 to 2.1 plus
## its blue collar), unshaded so it reads at full strength in any light. One mesh per kind, shared.
static func ring_for(id: String) -> MeshInstance3D:
	if not _rings.has(id):
		var big := id == "full"
		var inner := 1.3 if big else 1.1
		var outer := 2.1 if big else 1.5
		var am := ArrayMesh.new()
		_annulus(am, inner, outer, 0.05, _ring_mat(KIND_COLORS.get(id, Color.WHITE)))
		if RING_RIM.has(id):
			_annulus(am, outer, outer + (0.35 if big else 0.14), 0.05, _ring_mat(RING_RIM[id]))
		_rings[id] = am
	var mi := MeshInstance3D.new()
	mi.mesh = _rings[id]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 140.0
	return mi


static func _ring_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _ring_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.disable_fog = true # keeps its colour across the map
		_ring_mats[key] = m
	return _ring_mats[key]


static func _annulus(am: ArrayMesh, r0: float, r1: float, y: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p00 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, y, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, y, sin(a1) * r1)
		st.set_normal(Vector3.UP)
		for v: Vector3 in [p00, p01, p11, p00, p11, p10]: # clockwise seen from above (the visible side)
			st.add_vertex(v)
	st.set_material(mat)
	st.commit(am)


## The plate's marker lamps in the item's colour. Round 12 (owner): while the item is gone the
## whole base (plate and ring) is gone too, no empty collar left behind.
func _pad_lamps(on: bool) -> void:
	if _ring:
		_ring.visible = on
	if _pad == null:
		return
	_pad.visible = on
	var i := ModelLib.glow_surface(_pad.mesh)
	if i >= 0:
		var c := kind_color()
		_pad.set_surface_override_material(i, ModelLib.glow_tint(c if on else Color(c.r * 0.12, c.g * 0.12, c.b * 0.12)))


func _process(delta: float) -> void:
	_t += delta
	if active:
		if _blender: # a slow, steady turn and the faintest drift: hardware, not a toy
			_visual.rotation.y = _t * 0.9
			if kind == "full" and _ring: # the brightest of them all: its ring breathes
				_ring_mat(KIND_COLORS["full"]).albedo_color = (KIND_COLORS["full"] as Color).lerp(Color(1.0, 0.3, 0.32), 0.5 + 0.5 * sin(_t * 3.0))
			if bob:
				_visual.position.y = HOVER + sin(_t * 1.7) * 0.05
			return
		_visual.rotation.y = _t * 1.6
		if bob:
			_visual.position.y = 1.3 + sin(_t * 2.5) * 0.15
		return
	_respawn -= delta
	if _respawn <= 0.0:
		if random_weapon:
			kind = WeaponData.PICKUP_WEAPONS.pick_random()
			_build()
		active = true
		_visual.visible = true
		_pad_lamps(true)


func _on_body_entered(body: Node3D) -> void:
	if not active or not (body is Vehicle):
		return
	var v := body as Vehicle
	if v.is_dead:
		return
	if kind == "full":
		if v.health >= v.max_health and v.energy >= 100.0:
			return
		v.heal(v.max_health) # everything back: health and energy (HOLLYWOOD prize, round 9)
		v.energy = 100.0
		v.notice.emit(v, "FULL HEALTH")
	elif is_health():
		if v.health >= v.max_health:
			return
		var mega := kind == "mega"
		v.heal(v.max_health * (WeaponData.MEGA_HEALTH_RATIO if mega else WeaponData.HEALTH_PICKUP_RATIO))
		# Round 11 (owner): health also refills energy, 5 s of regen (mega: 8 s).
		var secs := WeaponData.MEGA_HEALTH_ENERGY_S if mega else WeaponData.HEALTH_ENERGY_S
		v.energy = minf(100.0, v.energy + secs * Vehicle.ENERGY_REGEN)
		v.notice.emit(v, "MEGA HEALTH" if mega else "HEALTH")
	elif is_turbo():
		if v.turbo >= 99.5:
			return # leave it for someone who needs it
		v.refill_turbo()
		v.notice.emit(v, MSG_TURBO)
	else:
		v.add_ammo(kind, int(WeaponData.get_def(kind).get("ammo", 1)))
		v.notice.emit(v, loaded_message(kind))
		# Roadkill (owner, round 11): a little energy for every weapon he picks up.
		v.energy = minf(100.0, v.energy + float(v.stats.get("pickup_energy", 0.0)))
	GameFeel.play("pickup_health" if is_health() else ("pickup_turbo" if is_turbo() else "pickup_weapon"), global_position, get_parent())
	if not respawns:
		queue_free()
		return
	active = false
	match kind:
		"mega":
			_respawn = WeaponData.MEGA_RESPAWN
		"health":
			_respawn = WeaponData.HEALTH_RESPAWN
		"turbo":
			_respawn = WeaponData.TURBO_RESPAWN
		_:
			_respawn = WeaponData.WEAPON_RESPAWN
	_visual.visible = false
	_pad_lamps(false)


## "FIRE MISSILE LOADED", "SAT LOADED", ...
static func loaded_message(id: String) -> String:
	return "%s LOADED" % String(WeaponData.get_def(id).get("label", id)).to_upper()


# ---------------------------------------------------------------- looks

## One merged mesh per kind: a dark pad with a ring in the weapon's color, and the weapon itself
## floating above it. Soft glow only on small accents.
static func mesh_for(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var mb := MeshBuilder.new()
	var color: Color = WeaponData.get_def(id).get("color", Color.WHITE)
	if id == "health" or id == "mega" or id == "full":
		color = {"health": Color(0.2, 0.45, 0.95), "mega": Color(0.15, 0.8, 0.2), "full": Color(0.85, 0.12, 0.1)}[id]
	elif id == "turbo":
		color = Color(0.2, 0.6, 1.0)
	var metal := MatKit.flat(Color(0.32, 0.33, 0.35), 0.45, 0.6)
	var dark := MatKit.flat(Color(0.07, 0.07, 0.08), 0.7)
	var paint := MatKit.flat(color.darkened(0.15), 0.55)
	var glow := MatKit.lamp(color, 0.9)
	# Pad (stays level while the item spins: the pad is round).
	mb.cylinder(dark, 1.0, 0.08, MeshBuilder.at(Vector3(0, -0.95, 0)), 20)
	mb.torus(glow, 0.95, 0.05, MeshBuilder.at(Vector3(0, -0.9, 0)), 24, 4)
	match id:
		"homing":
			# Slim missile, blue nose and fins, a seeker ring around the head.
			_missile(mb, metal, paint, glow, 1.0)
			mb.torus(glow, 0.2, 0.035, MeshBuilder.along(Vector3(0, 0, -0.35), Vector3.FORWARD), 14, 4)
		"fire":
			# Missile with an orange-red flame cone at the tail.
			_missile(mb, metal, paint, glow, 1.0)
			mb.cylinder(glow, 0.15, 0.5, MeshBuilder.along(Vector3(0, 0, 0.95), Vector3.BACK), 8, 0.0, false)
			mb.cylinder(MatKit.lamp(Color(1.0, 0.8, 0.2), 0.9), 0.08, 0.35, MeshBuilder.along(Vector3(0, 0, 0.9), Vector3.BACK), 6, 0.0, false)
		"power":
			# Fat warhead with black and yellow hazard bands.
			_missile(mb, metal, paint, glow, 1.45)
			for z: float in [-0.15, 0.15]:
				mb.cylinder(MatKit.flat(Color(0.85, 0.7, 0.1), 0.6), 0.2, 0.09, MeshBuilder.along(Vector3(0, 0, z), Vector3.FORWARD), 12)
		"napalm":
			# Red gas can with a yellow band and a spout.
			mb.box(MatKit.flat(Color(0.62, 0.08, 0.06), 0.55), Vector3(0.75, 0.95, 0.4), MeshBuilder.at(Vector3.ZERO), 0.06)
			mb.box(MatKit.flat(Color(0.85, 0.65, 0.12), 0.6), Vector3(0.77, 0.16, 0.42), MeshBuilder.at(Vector3(0, 0.1, 0)), 0.02)
			mb.box(dark, Vector3(0.45, 0.1, 0.12), MeshBuilder.at(Vector3(-0.08, 0.55, 0)), 0.02)
			mb.cylinder(metal, 0.07, 0.35, MeshBuilder.at(Vector3(0.26, 0.62, 0), Vector3(0, 0, -35)), 8)
			mb.sphere(glow, 0.09, MeshBuilder.at(Vector3(0.36, 0.76, 0)), 8, 4)
		"remote":
			# Black bomb with an antenna and a red light.
			mb.sphere(dark, 0.5, MeshBuilder.at(Vector3.ZERO), 14, 8)
			mb.cylinder(metal, 0.2, 0.14, MeshBuilder.at(Vector3(0, 0.5, 0)), 10)
			mb.cylinder(metal, 0.025, 0.7, MeshBuilder.at(Vector3(0.1, 0.85, 0)), 4)
			mb.sphere(glow, 0.1, MeshBuilder.at(Vector3(0, 0.6, 0.16)), 8, 4)
		"zoomy":
			# Pod of six thin missiles with yellow-green tips.
			for k in 6:
				var a := TAU * k / 6.0
				var o := Vector3(cos(a) * 0.22, sin(a) * 0.22, 0)
				mb.cylinder(metal, 0.06, 0.9, MeshBuilder.along(o, Vector3.FORWARD), 6)
				mb.cylinder(glow, 0.06, 0.14, MeshBuilder.along(o + Vector3(0, 0, -0.52), Vector3.FORWARD), 6, 0.0)
			mb.cylinder(paint, 0.34, 0.25, MeshBuilder.along(Vector3(0, 0, 0.25), Vector3.FORWARD), 12)
		"sat":
			# Satellite: body, two solar wings, a dish.
			mb.box(metal, Vector3(0.4, 0.4, 0.55), MeshBuilder.at(Vector3.ZERO), 0.04)
			for sx: float in [-1.0, 1.0]:
				mb.box(MatKit.flat(Color(0.12, 0.14, 0.32), 0.3, 0.4), Vector3(0.75, 0.03, 0.42), MeshBuilder.at(Vector3(sx * 0.62, 0, 0)), 0.0)
				mb.box(paint, Vector3(0.08, 0.05, 0.05), MeshBuilder.at(Vector3(sx * 0.24, 0, 0)), 0.0)
			mb.lathe(paint, PackedVector2Array([Vector2(0.02, 0.0), Vector2(0.18, 0.04), Vector2(0.32, 0.14)]), MeshBuilder.at(Vector3(0, -0.22, 0), Vector3(180, 0, 0)), 14, true)
			mb.sphere(glow, 0.06, MeshBuilder.at(Vector3(0, -0.3, 0)), 8, 4)
		"turbo":
			# Nitro bottle: blue tank, steel valve, a flame band.
			mb.cylinder(paint, 0.26, 0.9, MeshBuilder.at(Vector3.ZERO, Vector3(0, 0, 25)), 14)
			mb.sphere(paint, 0.26, MeshBuilder.at(Vector3(-0.19, 0.41, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), 14, 6)
			mb.cylinder(metal, 0.08, 0.25, MeshBuilder.at(Vector3(-0.26, 0.58, 0), Vector3(0, 0, 25)), 8)
			mb.cylinder(MatKit.lamp(Color(1.0, 0.55, 0.12), 0.9), 0.27, 0.12, MeshBuilder.at(Vector3(0.03, -0.06, 0), Vector3(0, 0, 25)), 14)
		"health", "mega", "full":
			# Owner, round 9: a white cross on a coloured plate: blue (health), a bigger yellow one
			# (mega), the biggest on red (full: health and energy). Dark steel rim, the cross raised
			# on both faces so it reads from every side as it turns.
			var s: float = {"health": 1.0, "mega": 1.3, "full": 1.6}[id]
			var bg: Color = {"health": Color(0.1, 0.32, 0.8), "mega": Color(0.92, 0.7, 0.1), "full": Color(0.78, 0.08, 0.06)}[id]
			var plate := MatKit.lamp(bg, 0.35) # a soft glow so it reads from afar, not a glare
			var white := MatKit.lamp(Color(0.95, 0.95, 0.92), 0.6)
			var rim := MatKit.steel(Color(0.22, 0.22, 0.24), 0.6, 0.6)
			mb.box(rim, Vector3(1.08, 1.08, 0.26) * s, MeshBuilder.at(Vector3.ZERO), 0.06)
			mb.box(plate, Vector3(0.96, 0.96, 0.3) * s, MeshBuilder.at(Vector3.ZERO), 0.04)
			mb.box(white, Vector3(0.66, 0.2, 0.36) * s, MeshBuilder.at(Vector3.ZERO), 0.01)
			mb.box(white, Vector3(0.2, 0.66, 0.36) * s, MeshBuilder.at(Vector3.ZERO), 0.01)
		_:
			_missile(mb, metal, paint, glow, 1.0)
	var mesh := mb.build_mesh(0.0, 0.0, true) # body parts share one material: 2 draw calls a pickup
	_meshes[id] = mesh
	return mesh


## A missile lying along Z (nose at -Z): body, colored nose cone and four fins.
static func _missile(mb: MeshBuilder, metal: Material, paint: Material, glow: Material, s: float) -> void:
	mb.cylinder(metal, 0.12 * s, 1.1, MeshBuilder.along(Vector3.ZERO, Vector3.FORWARD), 10)
	mb.cylinder(glow, 0.12 * s, 0.32 * s, MeshBuilder.along(Vector3(0, 0, -0.55 - 0.16 * s), Vector3.FORWARD), 10, 0.0)
	for k in 4:
		var a := TAU * k / 4.0
		var o := Vector3(cos(a), sin(a), 0) * 0.17 * s
		mb.box(paint, Vector3(0.22 * s, 0.03, 0.3) if k % 2 == 0 else Vector3(0.03, 0.22 * s, 0.3), MeshBuilder.at(o + Vector3(0, 0, 0.42)), 0.0)
