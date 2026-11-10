class_name Pickup
extends Area3D
## Weapon, health or mega health pickup. Respawns after being taken, unless it is a one-off
## (dropped by a broken stand or tower).

var kind := "homing" # a weapon id, "health" or "mega"
var random_weapon := true # re-roll the weapon each respawn
var respawns := true
var active := true
var bob := true

var _visual: Node3D
var _respawn := 0.0
var _t := 0.0


static func create(parent: Node, pickup_kind: String, pos: Vector3, one_off := false) -> Pickup:
	var p := Pickup.new()
	p.kind = pickup_kind
	p.random_weapon = pickup_kind != "health" and pickup_kind != "mega" and not one_off
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


func _build() -> void:
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.position = Vector3.UP * 1.3
	add_child(_visual)
	var color: Color
	if is_health():
		var mega := kind == "mega"
		color = Color(1.0, 0.8, 0.15) if mega else Color(1.0, 0.15, 0.15)
		var s := 1.6 if mega else 1.0
		var white := MeshKit.emissive(Color(0.95, 0.95, 0.9), 1.2)
		var red := MeshKit.emissive(color, 2.5)
		MeshKit.box(_visual, Vector3(1.1, 1.1, 0.3) * s, Vector3.ZERO, white)
		MeshKit.box(_visual, Vector3(0.75, 0.22, 0.34) * s, Vector3.ZERO, red)
		MeshKit.box(_visual, Vector3(0.22, 0.75, 0.34) * s, Vector3.ZERO, red)
		if mega:
			MeshKit.torus(_visual, 1.2, 1.4, Vector3.ZERO, MeshKit.emissive(color, 3.0), Vector3(90, 0, 0))
	else:
		color = WeaponData.get_def(kind).get("color", Color.WHITE)
		MeshKit.box(_visual, Vector3(0.8, 0.8, 0.8), Vector3.ZERO, MeshKit.emissive(color, 2.2), Vector3(45, 0, 45))
		MeshKit.box(_visual, Vector3(1.15, 0.12, 1.15), Vector3(0, -0.9, 0), MeshKit.mat(Color(0.1, 0.1, 0.1), 0.5, 0.6))


func _process(delta: float) -> void:
	_t += delta
	if active:
		_visual.rotation.y = _t * 1.8
		if bob:
			_visual.position.y = 1.3 + sin(_t * 2.5) * 0.18
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
		var ratio := WeaponData.MEGA_HEALTH_RATIO if kind == "mega" else WeaponData.HEALTH_PICKUP_RATIO
		v.heal(v.max_health * ratio)
	else:
		v.add_ammo(kind, int(WeaponData.get_def(kind).get("ammo", 1)))
	if not respawns:
		queue_free()
		return
	active = false
	if kind == "mega":
		_respawn = WeaponData.MEGA_RESPAWN
	elif kind == "health":
		_respawn = WeaponData.HEALTH_RESPAWN
	else:
		_respawn = WeaponData.WEAPON_RESPAWN
	_visual.visible = false
