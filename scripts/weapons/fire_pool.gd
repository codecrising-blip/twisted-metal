class_name FirePool
extends Area3D
## A patch of fire on the ground. Sets every car inside on fire, its owner's too (Burning renews,
## never stacks).
## Used by the Napalm Cone and by stage hazards (time <= 0 burns forever).

var radius := 2.0
var time := 5.0
var burn := 4.0
var source: Vehicle
var show_flames := true # false: the stage draws its own fire there (the pit of fire)

var _tick := 0.0
var _light: OmniLight3D
var _flames: FoamFire # the game's fire over the pool (round 18)


static func spawn(parent: Node, pos: Vector3, pool_radius: float, seconds: float, burn_seconds: float, by: Vehicle, flames := true) -> FirePool:
	var p := FirePool.new()
	p.show_flames = flames
	p.radius = pool_radius
	p.time = seconds
	p.burn = burn_seconds
	p.source = by
	parent.add_child(p)
	p.global_position = pos
	return p


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # vehicles
	monitorable = false
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = 3.0
	shape.shape = c
	shape.position = Vector3.UP * 1.5
	add_child(shape)

	var glow := MeshKit.emissive(Color(1.0, 0.35, 0.05), 1.8)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1.0, 0.4, 0.05, 0.7)
	MeshKit.cylinder(self, radius, 0.05, Vector3.UP * 0.06, glow, Vector3.ZERO, 16)
	if show_flames:
		_flames = FoamFire.new()
		_flames.box = Vector3(radius * 0.72, 0.03, radius * 0.72)
		_flames.position = Vector3.UP * 0.05
		_flames.size = clampf(0.7 + radius * 0.3, 0.8, 2.2)
		_flames.rate = clampf(radius * radius * 7.0, 14.0, 70.0)
		_flames.life = 0.8
		_flames.rise = 2.0
		_flames.rise_in = 8.0
		add_child(_flames)
		_flames.on = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.light_energy = 2.5
	_light.omni_range = radius * 3.0 + 4.0
	_light.position = Vector3.UP * 1.5
	add_child(_light)
	var crackle := GameFeel.loop("fire_loop", self, -14.0 + radius * 1.5, 3.0 + radius * 1.5)
	if crackle:
		crackle.play()


func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for body in get_overlapping_bodies():
			if body is Vehicle: # the one who started it burns too (friendly fire)
				(body as Vehicle).ignite(burn, source)
	if time <= 0.0:
		return # permanent stage fire
	time -= delta
	if time < 1.0:
		_light.light_energy = 2.5 * maxf(time, 0.0)
		if _flames:
			_flames.on = false
	if time <= 0.0:
		queue_free()
