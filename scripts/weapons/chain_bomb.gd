class_name ChainBomb
extends Node3D
## Junkyard Dog's special (owner's design): a spiked bomb on the crane chain, thrown straight ahead.
## Press fire again to blow it: area damage 30 at the center down to 15 at the 7 m edge, plus a push.
## A direct hit hooks it onto that car (+10 on that car). At the end of the chain it drops to the
## ground and blows by itself after 3 s, blinking red faster and faster.

enum State { FLYING, STUCK, DROPPED }

var owner_car: Vehicle
var def := {}
var state := State.FLYING
var stuck_to: Vehicle

var _dir := Vector3.FORWARD
var _traveled := 0.0
var _fuse := -1.0
var _fall := 0.0
var _stuck_offset := Vector3.ZERO
var _blink := 0.0
var _lamp: MeshInstance3D
var _lamp_on: Material
var _lamp_off: Material
var _light: OmniLight3D
var _chain: ZigLine
var _done := false


static func start(v: Vehicle, d: Dictionary) -> ChainBomb:
	var b := ChainBomb.new()
	b.owner_car = v
	b.def = d
	b._dir = v.flat_forward()
	v.get_parent().add_child(b)
	# Thrown from the crane but flies about a meter off the ground, so it hits cars, not roofs.
	var from := v.launch_point()
	b.global_position = Vector3(from.x, v.global_position.y + 1.0, from.z)
	v.set_live_special(b)
	return b


func _ready() -> void:
	var iron := MeshKit.mat(Color(0.12, 0.11, 0.1), 0.5, 0.8)
	MeshKit.sphere(self, 0.55, Vector3.ZERO, iron, Vector3.ONE, 12)
	for i in 8:
		var a := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spike := MeshKit.cylinder(self, 0.1, 0.45, a * 0.6, iron, Vector3.ZERO, 6, 0.0)
		spike.basis = Basis(Quaternion(Vector3.UP, a))
	_lamp_on = MeshKit.emissive(Color(1.0, 0.1, 0.05), 8.0)
	_lamp_off = MeshKit.emissive(Color(0.4, 0.02, 0.02), 0.5)
	_lamp = MeshKit.sphere(self, 0.16, Vector3(0, 0.55, 0), _lamp_on, Vector3.ONE, 8)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.light_energy = 2.0
	_light.omni_range = 6.0
	add_child(_light)
	_chain = ZigLine.new()
	_chain.material = MeshKit.mat(Color(0.3, 0.3, 0.3), 0.4, 0.9)
	_chain.segments = 12
	_chain.thickness = 0.09
	add_child(_chain)


## Second press: blow it now.
func fire_again() -> void:
	detonate()


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(owner_car) or owner_car.is_dead:
		detonate()
		return
	var space := get_world_3d().direct_space_state
	match state:
		State.FLYING:
			var step := _dir * float(def.get("speed", 45.0)) * delta
			var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1 | 2)
			q.exclude = [owner_car.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				if hit.collider is Vehicle:
					stuck_to = hit.collider as Vehicle
					_stuck_offset = stuck_to.global_transform.affine_inverse() * hit.position
					state = State.STUCK
					_fuse = float(def.get("fuse", 3.0))
				else:
					global_position = hit.position + hit.normal * 0.6
					_drop()
				return
			global_position += step
			_traveled += step.length()
			if _traveled >= float(def.get("chain", 25.0)):
				_drop()
		State.STUCK:
			if not is_instance_valid(stuck_to) or stuck_to.is_dead:
				_drop()
				return
			global_position = stuck_to.global_transform * _stuck_offset
			if owner_car.global_position.distance_to(global_position) > float(def.get("chain", 25.0)) * 1.6:
				detonate() # chain pulled taut: it goes off
				return
			_tick_fuse(delta)
		State.DROPPED:
			_fall += Projectile.LOB_GRAVITY * delta
			var down := Vector3.DOWN * _fall * delta
			var q := PhysicsRayQueryParameters3D.create(global_position, global_position + down + Vector3.DOWN * 0.55, 1)
			if space.intersect_ray(q).is_empty():
				global_position += down
			else:
				_fall = 0.0
			_tick_fuse(delta)
	if not _done:
		_chain.draw(owner_car.launch_point(), global_position, 0.0, 1.2 if state != State.FLYING else 0.3)


func _drop() -> void:
	state = State.DROPPED
	_fuse = float(def.get("fuse", 3.0))


func _tick_fuse(delta: float) -> void:
	_fuse -= delta
	# Blink faster as the fuse runs out.
	_blink -= delta
	if _blink <= 0.0:
		_blink = clampf(_fuse * 0.12, 0.05, 0.35)
		var on := _lamp.material_override != _lamp_on
		_lamp.material_override = _lamp_on if on else _lamp_off
		_light.visible = on
	if _fuse <= 0.0:
		detonate()


func detonate() -> void:
	if _done:
		return
	_done = true
	var world := get_parent()
	var radius: float = def.get("radius", 7.0)
	var center := global_position
	for o in Specials.cars_near(world, center, radius + 1.0, null): # friendly fire: Billy Ray too
		var d := clampf(o.aim_point().distance_to(center) / radius, 0.0, 1.0)
		var dmg: float = lerpf(def.get("damage", 30.0), def.get("edge_damage", 15.0), d)
		if o == stuck_to: # the bomb is on it: full center damage plus the hook bonus (40)
			dmg = float(def.get("damage", 30.0)) + float(def.get("stuck_bonus", 10.0))
		o.take_damage(dmg * WeaponData.DAMAGE_SCALE, owner_car)
		var push := o.global_position - center
		push.y = 0.0
		o.apply_impulse(push.normalized() * 14.0 * o.knockback + Vector3.UP * 5.0)
	FxKit.explosion(world, center, 2.4, Color(1.0, 0.45, 0.1))
	if is_instance_valid(owner_car):
		owner_car.set_live_special(null)
	queue_free()
