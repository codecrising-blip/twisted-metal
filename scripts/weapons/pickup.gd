class_name Pickup
extends Area3D
## Weapon crate or health pickup. Respawns after being taken.

const RESPAWN_SECONDS := 14.0
const HEALTH_AMOUNT := 40.0

var kind := "homing" # a weapon id, or "health"
var random_weapon := true # re-roll the weapon each respawn
var active := true

var _visual: Node3D
var _light: OmniLight3D
var _respawn := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 8 # layer 4: pickups
	collision_mask = 2 # vehicles
	monitorable = false
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.8
	shape.shape = s
	shape.position = Vector3.UP * 1.0
	add_child(shape)
	add_to_group("pickups")
	body_entered.connect(_on_body_entered)
	_build()


func _build() -> void:
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.position = Vector3.UP * 1.3
	add_child(_visual)
	var color: Color
	if kind == "health":
		color = Color(1.0, 0.15, 0.15)
		var white := MeshKit.emissive(Color(0.95, 0.95, 0.9), 1.2)
		var red := MeshKit.emissive(color, 2.5)
		MeshKit.box(_visual, Vector3(1.1, 1.1, 0.3), Vector3.ZERO, white)
		MeshKit.box(_visual, Vector3(0.75, 0.22, 0.34), Vector3.ZERO, red)
		MeshKit.box(_visual, Vector3(0.22, 0.75, 0.34), Vector3.ZERO, red)
	else:
		color = WeaponData.get_def(kind).get("color", Color.WHITE)
		MeshKit.box(_visual, Vector3(0.8, 0.8, 0.8), Vector3.ZERO, MeshKit.emissive(color, 2.2), Vector3(45, 0, 45))
		MeshKit.box(_visual, Vector3(1.15, 0.12, 1.15), Vector3(0, -0.9, 0), MeshKit.mat(Color(0.1, 0.1, 0.1), 0.5, 0.6))
	if _light == null:
		_light = OmniLight3D.new()
		_light.omni_range = 5.0
		_light.light_energy = 1.5
		_light.position = Vector3.UP * 1.3
		add_child(_light)
	_light.light_color = color


func _process(delta: float) -> void:
	_t += delta
	if active:
		_visual.rotation.y = _t * 1.8
		_visual.position.y = 1.3 + sin(_t * 2.5) * 0.18
		return
	_respawn -= delta
	if _respawn <= 0.0:
		if random_weapon and kind != "health":
			kind = WeaponData.PICKUP_WEAPONS.pick_random()
			_build()
		active = true
		_visual.visible = true
		_light.visible = true


func _on_body_entered(body: Node3D) -> void:
	if not active or not (body is Vehicle):
		return
	var v := body as Vehicle
	if v.is_dead:
		return
	if kind == "health":
		if v.health >= v.max_health:
			return
		v.heal(HEALTH_AMOUNT)
	else:
		v.add_ammo(kind, int(WeaponData.get_def(kind).get("ammo", 1)))
	active = false
	_respawn = RESPAWN_SECONDS
	_visual.visible = false
	_light.visible = false
