class_name Pickup
extends Area3D
## Weapon, turbo, health or mega health pickup. Respawns after being taken, unless it is a one-off
## (dropped by a broken stand or tower). Owner, play-test 1: each pickup shows its weapon's shape and
## color (fire and homing must never be confused), soft light instead of a glaring glow, and a
## message says what you got ("FIRE MISSILE LOADED"). Turbo pickups refill the turbo bar completely.

const MSG_TURBO := "TURBO REFILLED"

var kind := "homing" # a weapon id, "turbo", "health" or "mega"
var random_weapon := true # re-roll the weapon each respawn
var respawns := true
var active := true
var bob := true

var _visual: Node3D
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
	s.radius = 2.0 if kind == "mega" else 1.8
	shape.shape = s
	shape.position = Vector3.UP * 1.0
	add_child(shape)
	add_to_group("pickups")
	body_entered.connect(_on_body_entered)
	_t = randf() * 10.0
	_build()


func is_health() -> bool:
	return kind == "health" or kind == "mega"


func is_turbo() -> bool:
	return kind == "turbo"


func _build() -> void:
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.position = Vector3.UP * 1.3
	_visual.scale = Vector3.ONE * 1.25
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 130.0 # far ones still show on the radar
	_visual.add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if active:
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


func _on_body_entered(body: Node3D) -> void:
	if not active or not (body is Vehicle):
		return
	var v := body as Vehicle
	if v.is_dead:
		return
	if is_health():
		if v.health >= v.max_health:
			return
		var mega := kind == "mega"
		v.heal(v.max_health * (WeaponData.MEGA_HEALTH_RATIO if mega else WeaponData.HEALTH_PICKUP_RATIO))
		v.notice.emit(v, "MEGA HEALTH" if mega else "HEALTH")
	elif is_turbo():
		if v.turbo >= 99.5:
			return # leave it for someone who needs it
		v.refill_turbo()
		v.notice.emit(v, MSG_TURBO)
	else:
		v.add_ammo(kind, int(WeaponData.get_def(kind).get("ammo", 1)))
		v.notice.emit(v, loaded_message(kind))
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
	if id == "health" or id == "mega":
		color = Color(0.95, 0.75, 0.2) if id == "mega" else Color(0.85, 0.12, 0.1)
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
		"health", "mega":
			# White case with a red (gold for mega) cross.
			var s := 1.4 if id == "mega" else 1.0
			mb.box(MatKit.flat(Color(0.88, 0.88, 0.84), 0.5), Vector3(1.0, 1.0, 0.36) * s, MeshBuilder.at(Vector3.ZERO), 0.08)
			mb.box(glow, Vector3(0.7, 0.2, 0.4) * s, MeshBuilder.at(Vector3.ZERO), 0.0)
			mb.box(glow, Vector3(0.2, 0.7, 0.4) * s, MeshBuilder.at(Vector3.ZERO), 0.0)
			if id == "mega":
				mb.torus(glow, 1.0, 0.06, MeshBuilder.at(Vector3.ZERO, Vector3(90, 0, 0)), 24, 4)
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
