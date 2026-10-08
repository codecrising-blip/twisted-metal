class_name Projectile
extends Node3D
## Bullets and missiles. Moves itself and ray-casts each step so fast shots never tunnel.

const HIT_MASK := 1 | 2 # world + vehicles

static var spawned_total := 0 # used by tests

var weapon_id := ""
var def := {}
var shooter: Vehicle
var target: Vehicle
var direction := Vector3.FORWARD
var _life := 1.0
var _trail: CPUParticles3D


static func spawn(parent: Node, id: String, from: Vector3, dir: Vector3, by: Vehicle, lock: Vehicle) -> Projectile:
	var p := Projectile.new()
	p.weapon_id = id
	p.def = WeaponData.get_def(id)
	p.shooter = by
	p.target = lock
	p.direction = dir.normalized()
	p._life = p.def.get("life", 1.0)
	parent.add_child(p)
	p.global_position = from
	p._orient()
	p._build_visual()
	spawned_total += 1
	return p


func _build_visual() -> void:
	var color: Color = def.get("color", Color.WHITE)
	match def.get("kind", "bullet"):
		"bullet":
			MeshKit.box(self, Vector3(0.07, 0.07, 1.6), Vector3.ZERO, MeshKit.emissive(color, 4.0))
		"missile":
			MeshKit.cylinder(self, 0.12, 0.9, Vector3.ZERO, MeshKit.mat(Color(0.3, 0.3, 0.32), 0.4, 0.6), Vector3(90, 0, 0), 8)
			MeshKit.sphere(self, 0.16, Vector3(0, 0, 0.5), MeshKit.emissive(color, 5.0), Vector3(1, 1, 1.6), 8)
			_add_trail(FxKit.smoke(0.35, 24))
			_add_light(color, 2.0, 5.0)
		"freeze":
			MeshKit.sphere(self, 0.35, Vector3.ZERO, MeshKit.emissive(color, 4.0), Vector3.ONE, 10)
			var t := FxKit.fire(0.5, 20)
			t.color_ramp = null
			t.color = Color(0.6, 0.9, 1.0, 0.6)
			_add_trail(t)
			_add_light(color, 2.5, 6.0)
		"ghost":
			# Flaming laughing clown skull.
			var face := MeshKit.emissive(Color(1.0, 0.9, 0.75), 1.5)
			MeshKit.sphere(self, 0.55, Vector3.ZERO, face, Vector3(1, 1.1, 1), 12)
			var black := MeshKit.mat(Color(0.02, 0.02, 0.02))
			MeshKit.sphere(self, 0.13, Vector3(-0.2, 0.12, -0.45), black, Vector3(1, 1.3, 0.6), 8)
			MeshKit.sphere(self, 0.13, Vector3(0.2, 0.12, -0.45), black, Vector3(1, 1.3, 0.6), 8)
			MeshKit.box(self, Vector3(0.5, 0.08, 0.1), Vector3(0, -0.25, -0.48), MeshKit.emissive(Color(0.9, 0.05, 0.05), 3.0))
			var flames := FxKit.fire(1.4, 40)
			_add_trail(flames)
			_add_light(color, 4.0, 9.0)


func _add_trail(p: CPUParticles3D) -> void:
	_trail = p
	add_child(p)
	p.emitting = true


func _add_light(color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	add_child(l)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_explode(global_position, Vector3.UP, null)
		return

	var homing: float = def.get("homing", 0.0)
	if homing > 0.0 and is_instance_valid(target) and not target.is_dead:
		var desired := (target.global_position + Vector3.UP * 1.0 - global_position).normalized()
		var angle := direction.angle_to(desired)
		if angle > 0.001:
			direction = direction.slerp(desired, minf(1.0, homing * delta / angle)).normalized()

	var from := global_position
	var to := from + direction * float(def.get("speed", 50.0)) * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.position, hit.normal, hit.collider)
		return
	global_position = to
	_orient()


func _orient() -> void:
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)


func _explode(pos: Vector3, normal: Vector3, collider: Object) -> void:
	var world := get_parent()
	if collider is Vehicle:
		var v := collider as Vehicle
		v.take_damage(float(def.get("damage", 1.0)), shooter)
		if def.has("freeze"):
			v.freeze(float(def["freeze"]))
	var kind: String = def.get("kind", "bullet")
	if kind == "bullet":
		FxKit.spark(world, pos, normal)
	elif kind == "freeze":
		FxKit.explosion(world, pos, 0.6, Color(0.5, 0.85, 1.0))
	else:
		FxKit.explosion(world, pos, 0.8 + float(def.get("damage", 10.0)) / 40.0, def.get("color", Color(1, 0.5, 0.15)))
	# Let the smoke trail finish instead of vanishing with the missile.
	if _trail and is_instance_valid(_trail):
		var keep := _trail.global_position
		remove_child(_trail)
		world.add_child(_trail)
		_trail.global_position = keep
		_trail.emitting = false
		var tw := _trail.create_tween()
		tw.tween_interval(_trail.lifetime + 0.2)
		tw.tween_callback(_trail.queue_free)
	queue_free()
