class_name Breakable
extends StaticBody3D
## Stage props that break: hot dog stands, tunnel glass, palm trees, sign letters, tower legs.
## Small props shatter when a car drives into them and only cost it about 10% of its speed
## (design 2.0.1 rule 2). Big ones only take damage from weapons and rams.
## Builders put the meshes under `visual` (origin at the base) and add the collision shape.

signal broken(prop: Breakable, by: Vehicle)

enum Style { SHATTER, TOPPLE }

## Owner, round 9: every breakable goes down to ~0.6 s of machine-gun fire (0.55 x 12.5 rounds/s = 6.9 a second).
const MG_HEALTH := 4.2
## Round 9 (owner: hide behind palms and street lights from long-range fire): a wider column around
## the prop that only shots hit (physics layer 6). Cars still only meet the thin trunk or pole.
const COVER_LAYER := 32
var _cover: StaticBody3D
var health := MG_HEALTH
var smash_on_contact := true # a car driving into it breaks it at once
var ram_damage_mult := 0.0 # otherwise: ram damage = car speed * this
var style := Style.SHATTER
var debris_color := Color(0.6, 0.6, 0.6)
var loot := "" # "weapon" | "health" | "" -> one-off pickup where it stood
var loot_offset := Vector3.ZERO
var visual: Node3D
var is_broken := false
## How it breaks, looks and sounds (juice guide, round 8): "glass", "wood", "palm", "metal", "prop"
## (small street props) or "" (plain debris, no sound).
var kind := ""
var size_hint := Vector3(2.0, 2.0, 0.3) # rough extent of the visible part, for where the debris comes from
var topple_height := 5.0 # how tall it is when it falls over (where it lands)

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


## Missile cover: a column of `radius` and `height` that catches shots aimed past this prop.
func add_cover(radius: float, height: float) -> void:
	_cover = StaticBody3D.new()
	_cover.name = "Cover"
	_cover.collision_layer = COVER_LAYER
	_cover.collision_mask = 0
	_cover.set_meta("cover_of", self)
	add_child(_cover)
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	shape.shape = c
	shape.position = Vector3(0, height * 0.5, 0)
	_cover.add_child(shape)


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
	if _cover:
		_cover.collision_layer = 0
	_break_feel(by)
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
	# Aftermath: it hits the ground with a thud and a ring of dust where its top lands.
	tw.tween_callback(func():
		var top := global_position + away * topple_height * 0.95
		var thud := "metal_fall" if kind == "metal" else "land_thud"
		GameFeel.play(thud, top, get_parent(), -4.0, 0.7 if kind != "metal" else 0.85, true)
		FxKit.dust_ring(get_parent(), Specials.ground_below(get_parent(), top + Vector3.UP * 3.0), 1.2)
		GameFeel.shake(top, 0.2, 35.0))


## The break itself, by kind: the sound (peak on this frame), what flies off and where to (along the
## car that hit it), a flash, dust, a camera bump and, if you did it, a blink of hit-stop.
func _break_feel(by: Vehicle) -> void:
	var world := get_parent()
	var center := global_position + global_basis * Vector3(0, size_hint.y * 0.5, 0)
	var push := Vector3.ZERO
	if is_instance_valid(by):
		push = by.linear_velocity
		push.y = 0.0
		if push.length() < 2.0:
			push = (global_position - by.global_position) * Vector3(1, 0, 1)
	var dir := push.normalized() if push.length() > 0.1 else Vector3.UP
	var speed := push.length()
	var you: bool = is_instance_valid(by) and by.is_player
	match kind:
		"glass":
			GameFeel.play("glass_shatter", center, world, 2.0, 1.0, true)
			FxKit.shatter(world, center, global_basis * (size_hint * 0.5), dir, speed, Color(0.75, 0.92, 1.0), true)
			FxKit.shard_litter(world, center, dir, Color(0.7, 0.88, 1.0))
			GameFeel.flash(world, center, 2.4, Color(0.85, 0.95, 1.0), 0.08)
			FxKit.puff(world, center, 0.6)
			GameFeel.shake(center, 0.18, 35.0)
			if you:
				GameFeel.hitstop(get_tree(), 0.035, 0.1)
		"wood":
			GameFeel.play("wood_break", center, world, 2.0, 1.0, true)
			FxKit.shatter(world, center, global_basis * (size_hint * 0.5), dir, speed, debris_color, false)
			FxKit.puff(world, center, 0.9)
			GameFeel.shake(center, 0.25, 35.0)
			if you:
				GameFeel.hitstop(get_tree(), 0.045, 0.1)
		"palm":
			GameFeel.play("palm_break", center, world, 0.0, 1.0, true)
			_debris()
		"metal":
			GameFeel.play("metal_fall", center, world, 0.0, 1.1, true)
			FxKit.crash_burst(world, global_position + Vector3.UP * 1.0, dir if dir != Vector3.UP else Vector3.FORWARD, 0.5)
			_debris()
		"wreck": # a burnt shell bursts: what fuel was left goes up, panels fly
			FxKit.explosion(world, center, 1.3, Color(1.0, 0.5, 0.15))
			GameFeel.play("metal_fall", center, world, 0.0, 0.9, true)
			FxKit.crash_burst(world, center, dir if dir != Vector3.UP else Vector3.FORWARD, 0.8)
			FxKit.shatter(world, center, global_basis * (size_hint * 0.5), dir, speed, debris_color, false)
			if you:
				GameFeel.hitstop(get_tree(), 0.05, 0.1)
		"prop":
			GameFeel.play("crash", center, world, -10.0, 1.35, true)
			_debris()
			if you:
				GameFeel.shake(center, 0.1, 20.0)
		_:
			_debris()


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
