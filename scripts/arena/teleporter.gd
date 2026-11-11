class_name Teleporter
extends Area3D
## Drive onto the pad and come out at `destination`, keeping your speed (TM2 Los Angeles: tunnel
## roof to the caged super health).

var destination := Transform3D.IDENTITY
var color := Color(0.4, 1.0, 0.6)

var _cooldown := {} # vehicle instance id -> seconds left
var _ring: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 2.6
	c.height = 3.0
	shape.shape = c
	shape.position = Vector3.UP * 1.5
	add_child(shape)
	body_entered.connect(_on_body_entered)

	MeshKit.cylinder(self, 3.2, 0.25, Vector3.UP * 0.12, MeshKit.mat(Color(0.15, 0.15, 0.17), 0.4, 0.8), Vector3.ZERO, 24)
	MeshKit.cylinder(self, 2.7, 0.06, Vector3.UP * 0.27, MeshKit.emissive(color, 2.5), Vector3.ZERO, 24)
	_ring = Node3D.new()
	add_child(_ring)
	MeshKit.torus(_ring, 2.5, 2.8, Vector3.UP * 1.2, MeshKit.emissive(color, 3.0))
	MeshKit.torus(_ring, 1.6, 1.8, Vector3.UP * 2.4, MeshKit.emissive(color, 3.0))
	var swirl := FxKit.fire(1.2, 30)
	swirl.color_ramp = null
	swirl.color = Color(color.r, color.g, color.b, 0.5)
	swirl.emission_sphere_radius = 2.2
	swirl.position = Vector3.UP * 0.4
	add_child(swirl)
	swirl.emitting = true
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 10.0
	light.position = Vector3.UP * 2.0
	light.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	light.visible = GraphicsSettings.high
	add_child(light)


func _process(delta: float) -> void:
	_ring.rotation.y += delta * 1.5
	_ring.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.3
	for id in _cooldown.keys():
		_cooldown[id] -= delta
		if _cooldown[id] <= 0.0:
			_cooldown.erase(id)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Vehicle):
		return
	var v := body as Vehicle
	if v.is_dead or _cooldown.has(v.get_instance_id()):
		return
	_cooldown[v.get_instance_id()] = 2.0
	FxKit.explosion(get_parent(), v.global_position + Vector3.UP, 0.8, color)
	GameFeel.play("teleport", v.global_position + Vector3.UP, get_parent())
	var keep := maxf(absf(v.speed), 8.0)
	v.global_transform = destination
	v.speed = keep
	var fwd := -destination.basis.z
	v.velocity = Vector3(fwd.x, 0.0, fwd.z).normalized() * keep
	FxKit.explosion(get_parent(), destination.origin + Vector3.UP, 0.8, color)
	GameFeel.play("teleport", destination.origin + Vector3.UP, get_parent())
	v.notice.emit(v, "TELEPORTED")
