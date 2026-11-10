class_name Specials
extends RefCounted
## Fires every weapon (pickups and drivers' specials). Plain missiles go straight through
## Vehicle.launch(); weapons with their own behaviour are dispatched on WeaponData "handler".
## Nodes that stay in the world and listen to the next fire press (taser link, chain bomb, napalm
## can, remote bomb) are registered with Vehicle.set_live_special().


static func fire(v: Vehicle, id: String, charged := false) -> void:
	var def := WeaponData.get_def(id)
	match def.get("handler", ""):
		"taser":
			TaserLink.start(v, def)
		"chain_bomb":
			ChainBomb.start(v, def)
		"cone":
			_cone(v, id, def, charged)
		"napalm":
			_throw(v, id, def)
		"mine":
			Mine.drop(v, def)
		"salvo":
			_salvo(v, id, def)
		"sat":
			SatStrike.start(v, id, def)
		_:
			v.launch(id, v.target)


## Napalm Cone (Sweet Tooth). Tap: homing cone. Charged: twice the damage, straight path.
static func _cone(v: Vehicle, id: String, def: Dictionary, charged: bool) -> void:
	if not charged:
		v.launch(id, v.target)
		return
	var from := v.launch_point()
	var dir := v.flat_forward()
	var t := v.target
	if is_instance_valid(t) and not t.is_dead:
		var to_t := (t.aim_point() - from).normalized()
		if dir.angle_to(to_t) < deg_to_rad(25.0):
			dir = to_t # aimed at launch like a power missile, then no tracking
	Projectile.spawn(v.get_parent(), id, from, dir, v, null, {
		"damage": def.get("charged_damage", 90.0), "speed": def.get("charged_speed", 64.0),
		"homing": 0.0, "charged": true,
	})


## Napalm can: thrown up and ahead (carrying some of the car's speed); the next fire press with
## Napalm still selected drops it.
static func _throw(v: Vehicle, id: String, def: Dictionary) -> void:
	var fwd := v.flat_forward()
	var carry := Vector3(v.velocity.x, 0.0, v.velocity.z) * 0.6
	var vel := fwd * float(def.get("throw", 30.0)) + carry + Vector3.UP * float(def.get("lift", 10.0))
	var p := Projectile.spawn_lob(v.get_parent(), id, v.launch_point() + Vector3.UP * 0.4, vel, v)
	v.set_live_special(p, id)


## Zoomy: ten light missiles in a quick fan, all chasing the same lock.
static func _salvo(v: Vehicle, id: String, def: Dictionary) -> void:
	var lock := v.target if is_instance_valid(v.target) and not v.target.is_dead else null
	var count := int(def.get("salvo", 10))
	var gap := float(def.get("salvo_gap", 0.06))
	for i in count:
		var one := func() -> void:
			if not is_instance_valid(v) or v.is_dead or not v.is_inside_tree():
				return
			var dir := v.flat_forward().rotated(Vector3.UP, randf_range(-0.35, 0.35)) + Vector3.UP * randf_range(0.04, 0.22)
			var side := v.global_basis.x * randf_range(-0.6, 0.6)
			var aim: Vehicle = lock if is_instance_valid(lock) and not lock.is_dead else null
			Projectile.spawn(v.get_parent(), id, v.launch_point() + side, dir, v, aim)
		if i == 0:
			one.call()
		else:
			v.get_tree().create_timer(i * gap, false, true).timeout.connect(one)


## Damage every car within `radius` of `pos`, the shooter too (friendly fire, owner play-test 2):
## `damage` inside `core`, falling to `edge` at the rim. Burning for `burn` seconds if > 0.
## `skip` already took a direct hit.
static func blast(world: Node, pos: Vector3, radius: float, damage: float, shooter: Vehicle,
		edge := -1.0, core := 0.0, burn := 0.0, skip: Vehicle = null) -> void:
	if world == null or not world.is_inside_tree():
		return
	var rim := damage if edge < 0.0 else edge
	for node in world.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == skip or o.is_dead:
			continue
		var d := o.aim_point().distance_to(pos)
		if d > radius + 1.0:
			continue
		var t := clampf((d - core) / maxf(radius - core, 0.01), 0.0, 1.0)
		o.take_damage(lerpf(damage, rim, t) * WeaponData.DAMAGE_SCALE, shooter)
		if burn > 0.0:
			o.ignite(burn, shooter)


## Where a napalm can bursts: a fireball, everything near takes the hit and burns, a pool of fire stays.
static func napalm_burst(world: Node, pos: Vector3, direct: Vehicle, shooter: Vehicle, def: Dictionary) -> void:
	if world == null or not world.is_inside_tree():
		return
	FxKit.explosion(world, pos, 2.2, Color(1.0, 0.5, 0.12))
	blast(world, pos, float(def.get("radius", 6.0)), float(def.get("damage", 30.0)), shooter, -1.0, 0.0,
		float(def.get("burn", 5.0)), direct)
	var ground := ground_below(world, pos)
	FirePool.spawn(world, ground, def.get("pool_radius", 4.5), def.get("pool_time", 6.0), def.get("burn", 5.0), shooter)


## Point on the world surface under pos (or pos itself if nothing is below).
static func ground_below(world: Node, pos: Vector3) -> Vector3:
	var space := (world as Node3D).get_world_3d().direct_space_state if world is Node3D else null
	if space == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else pos


## Live vehicles other than `me` within `radius` of `pos`.
static func cars_near(world: Node, pos: Vector3, radius: float, me: Vehicle) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for node in world.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o != me and not o.is_dead and o.aim_point().distance_to(pos) <= radius:
			out.append(o)
	return out
