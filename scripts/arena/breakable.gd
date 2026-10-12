class_name Breakable
extends StaticBody3D
## Stage props that break: hot dog stands, tunnel glass, palm trees, sign letters, tower legs.
## Small props shatter when a car drives into them and only cost it about 10% of its speed
## (design 2.0.1 rule 2). Big ones only take damage from weapons and rams.
## Builders put the meshes under `visual` (origin at the base) and add the collision shape.

signal broken(prop: Breakable, by: Vehicle)

enum Style { SHATTER, TOPPLE }

var health := 12.0
var smash_on_contact := true # a car driving into it breaks it at once
var ram_damage_mult := 0.0 # otherwise: ram damage = car speed * this
var style := Style.SHATTER
var debris_color := Color(0.6, 0.6, 0.6)
var loot := "" # "weapon" | "health" | "" -> one-off pickup where it stood
var loot_offset := Vector3.ZERO
var visual: Node3D
var is_broken := false

static var _debris_mesh: BoxMesh


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)


func add_box_shape(size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = center
	add_child(shape)


## Called by Vehicle when it drives into this. Returns true if the car went through.
func vehicle_contact(v: Vehicle, before: Vector3) -> bool:
	if is_broken:
		return true
	if smash_on_contact:
		break_apart(v)
		return true
	if ram_damage_mult > 0.0:
		projectile_hit(Vector2(before.x, before.z).length() * ram_damage_mult, v)
	return is_broken


func projectile_hit(damage: float, by: Vehicle) -> void:
	if is_broken:
		return
	health -= damage
	if health <= 0.0:
		break_apart(by)


func break_apart(by: Vehicle) -> void:
	if is_broken:
		return
	is_broken = true
	collision_layer = 0
	_debris()
	if style == Style.TOPPLE:
		_topple(by)
	else:
		visual.visible = false
	if loot != "":
		var kind: String = WeaponData.PICKUP_WEAPONS.pick_random() if loot == "weapon" else loot
		Pickup.create(get_parent(), kind, global_position + loot_offset, true)
	broken.emit(self, by)


func _topple(by: Vehicle) -> void:
	var away := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	if is_instance_valid(by):
		away = global_position - by.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var axis := Vector3.UP.cross(away).normalized()
	var start := visual.global_basis
	var tw := create_tween()
	tw.tween_method(func(t: float):
		visual.global_basis = Basis(axis, t * deg_to_rad(84.0) * t) * start, 0.0, 1.0, 0.9)


func _debris() -> void:
	if _debris_mesh == null:
		_debris_mesh = BoxMesh.new()
		_debris_mesh.size = Vector3(0.35, 0.12, 0.3)
	var p := CPUParticles3D.new()
	p.mesh = _debris_mesh
	p.material_override = MeshKit.mat(debris_color, 0.6)
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 1.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -22, 0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.particle_flag_rotate_y = true
	get_parent().add_child(p)
	p.global_position = global_position + Vector3.UP * 1.2
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(p.queue_free)
