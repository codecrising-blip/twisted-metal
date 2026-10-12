class_name Specials
extends RefCounted
## Fires each driver's special weapon. Simple projectiles go through Projectile; specials with
## their own behaviour (taser link, chain bomb) are nodes that live in the world.


static func fire(v: Vehicle, id: String) -> void:
	var def := WeaponData.get_def(id)
	match def.get("handler", ""):
		"taser":
			TaserLink.start(v, def)
		"chain_bomb":
			ChainBomb.start(v, def)
		_:
			if def.get("kind", "") == "lob":
				_napalm(v, id, def)
			else:
				v.launch(id, v.target)


## Napalm Cone: lobbed in a high arc to where the locked target will be when it lands.
static func _napalm(v: Vehicle, id: String, def: Dictionary) -> void:
	var from := v.launch_point()
	var fwd := v.flat_forward()
	var t := v.target
	var aim: Vector3
	var flight := 1.2
	if is_instance_valid(t) and not t.is_dead:
		var flat_dist := Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length()
		flight = clampf(flat_dist / 50.0, 1.0, 1.4)
		aim = t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * flight
	else:
		aim = v.global_position + fwd * 40.0
	var flat := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var d := flat.length()
	var min_r: float = def.get("min_range", 12.0)
	var max_r: float = def.get("max_range", 70.0)
	if d < min_r:
		flat = (flat / d if d > 0.1 else fwd) * min_r
	elif d > max_r:
		flat = flat / d * max_r
	var dy := aim.y + 0.5 - from.y
	var vel := flat / flight
	vel.y = (dy + 0.5 * Projectile.LOB_GRAVITY * flight * flight) / flight
	Projectile.spawn_lob(v.get_parent(), id, from, vel, v)


## Splash and fire pool where a Napalm Cone lands. The direct hit was already applied.
static func napalm_splash(world: Node, pos: Vector3, direct: Vehicle, shooter: Vehicle, def: Dictionary) -> void:
	if world == null or not world.is_inside_tree():
		return
	FxKit.explosion(world, pos, 1.5, Color(1.0, 0.5, 0.15))
	var radius: float = def.get("splash_radius", 4.0)
	for node in world.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == direct or o == shooter or o.is_dead:
			continue
		if o.aim_point().distance_to(pos) <= radius + 1.0:
			o.take_damage(float(def.get("splash", 15.0)) * WeaponData.DAMAGE_SCALE, shooter)
			o.ignite(float(def.get("burn", 4.0)), shooter)
	var ground := ground_below(world, pos)
	FirePool.spawn(world, ground, def.get("pool_radius", 2.0), def.get("pool_time", 5.0), def.get("burn", 4.0), shooter)


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
