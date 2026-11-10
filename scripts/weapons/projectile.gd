class_name Projectile
extends Node3D
## Bullets, missiles, skulls, ghost missiles and lobbed bombs. Moves itself and ray-casts each
## step so fast shots never tunnel. Anything in the world with projectile_hit(damage, shooter)
## (stands, glass, sign letters) takes the hit too.

const HIT_MASK := 1 | 2 # world + vehicles
const LOB_GRAVITY := 30.0

static var spawned_total := 0 # used by tests

var weapon_id := ""
var def := {}
var shooter: Vehicle
var target: Vehicle
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO # lobbed shots only
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


## A shot that falls under gravity (Napalm Cone).
static func spawn_lob(parent: Node, id: String, from: Vector3, launch_velocity: Vector3, by: Vehicle) -> Projectile:
	var p := spawn(parent, id, from, launch_velocity, by, null)
	p.velocity = launch_velocity
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
		"lob":
			# Ice cream cone on fire: waffle cone, pink scoop, flames.
			MeshKit.cylinder(self, 0.32, 0.9, Vector3(0, 0, 0.35), MeshKit.mat(Color(0.8, 0.55, 0.25)), Vector3(-90, 0, 0), 8, 0.0)
			MeshKit.sphere(self, 0.36, Vector3(0, 0, -0.15), MeshKit.emissive(Color(1.0, 0.45, 0.65), 1.5), Vector3.ONE, 10)
			_add_trail(FxKit.fire(1.1, 36))
			_add_light(color, 3.0, 8.0)
		"skull":
			_skull_visual(color)
		"ghost":
			var glow := MeshKit.emissive(Color(0.55, 0.9, 1.0), 3.0)
			glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.albedo_color = Color(0.55, 0.9, 1.0, 0.6)
			MeshKit.sphere(self, 0.3, Vector3.ZERO, glow, Vector3(1, 1, 2.2), 10)
			var t := FxKit.fire(0.6, 26)
			t.color_ramp = null
			t.color = Color(0.5, 0.85, 1.0, 0.5)
			_add_trail(t)
			_add_light(color, 2.5, 7.0)


## Mr. Grimm's flaming skull (TM2): bone skull, dark eye holes, a row of teeth, fire behind.
func _skull_visual(color: Color) -> void:
	var bone := MeshKit.emissive(Color(0.95, 0.9, 0.78), 0.6)
	var black := MeshKit.mat(Color(0.02, 0.02, 0.02))
	MeshKit.sphere(self, 0.6, Vector3(0, 0.08, 0.05), bone, Vector3(1, 1.05, 1.1), 12)
	MeshKit.box(self, Vector3(0.62, 0.32, 0.5), Vector3(0, -0.38, -0.22), bone) # jaw
	for side in [-1.0, 1.0]:
		MeshKit.sphere(self, 0.17, Vector3(0.22 * side, 0.12, -0.5), black, Vector3(1.1, 1.0, 0.5), 8)
		MeshKit.sphere(self, 0.05, Vector3(0.22 * side, 0.12, -0.56), MeshKit.emissive(Color(1.0, 0.3, 0.05), 6.0), Vector3.ONE, 6)
	MeshKit.prism(self, Vector3(0.16, 0.18, 0.1), Vector3(0, -0.08, -0.6), black, Vector3(180, 0, 0))
	for i in 6:
		MeshKit.box(self, Vector3(0.07, 0.12, 0.06), Vector3(-0.2 + i * 0.08, -0.32, -0.48), MeshKit.mat(Color(0.98, 0.95, 0.85)))
	var flames := FxKit.fire(1.6, 48)
	flames.position = Vector3(0, 0.2, 0.4)
	_add_trail(flames)
	_add_light(color, 4.0, 10.0)


func _add_trail(p: CPUParticles3D) -> void:
	_trail = p
	add_child(p)
	p.emitting = true


func _add_light(color: Color, energy: float, light_range: float) -> void:
	if not GraphicsSettings.high:
		return # LOW: a moving light per missile is too costly on old GPUs; the trail still glows
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

	var step: Vector3
	if def.get("kind", "") == "lob":
		velocity.y -= LOB_GRAVITY * delta
		direction = velocity.normalized()
		step = velocity * delta
	else:
		var homing: float = def.get("homing", 0.0)
		if homing > 0.0 and is_instance_valid(target) and not target.is_dead:
			var desired := (target.aim_point() - global_position).normalized()
			var angle := direction.angle_to(desired)
			if angle > 0.001:
				direction = direction.slerp(desired, minf(1.0, homing * delta / angle)).normalized()
		step = direction * float(def.get("speed", 50.0)) * delta

	var from := global_position
	var to := from + step
	var mask := 2 if def.get("through_walls", false) else HIT_MASK
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
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
	var dmg := float(def.get("damage", 1.0)) * WeaponData.DAMAGE_SCALE
	if collider is Vehicle:
		var v := collider as Vehicle
		v.take_damage(dmg, shooter)
		if def.has("freeze"):
			v.freeze(float(def["freeze"]))
		if def.has("burn"):
			v.ignite(float(def["burn"]), shooter)
	elif collider != null and collider.has_method("projectile_hit"):
		collider.projectile_hit(dmg, shooter)
	var kind: String = def.get("kind", "bullet")
	if kind == "lob":
		Specials.napalm_splash(world, pos, collider as Vehicle, shooter, def)
	elif kind == "bullet":
		FxKit.spark(world, pos, normal)
	elif kind == "freeze":
		FxKit.explosion(world, pos, 0.6, Color(0.5, 0.85, 1.0))
	else:
		FxKit.explosion(world, pos, 0.8 + dmg / 40.0, def.get("color", Color(1, 0.5, 0.15)))
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
