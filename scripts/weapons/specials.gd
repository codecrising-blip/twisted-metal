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
		"boomerang":
			Boomerang.start(v, def)
		"rim_shot":
			RimShot.start(v, def)
		"charged_salvo":
			_charged_salvo(v, id, def)
		"crowd_ring":
			CrowdRing.start(v, def)
		_:
			v.launch(id, v.target)


## Napalm Cone (Sweet Tooth). Tap: homing cone. Charged: twice the damage, dead straight (round 22: no aim at launch).
static func _cone(v: Vehicle, id: String, def: Dictionary, charged: bool) -> void:
	if not charged:
		v.launch(id, v.target)
		return
	var from := v.straight_from(v.launch_point())
	var dir := v.level_forward() # round 21: straight shots fly level with the ground
	Projectile.spawn(v.get_parent(), id, from, dir, v, null, {
		"damage": def.get("charged_damage", 90.0), "speed": def.get("charged_speed", 64.0),
		"homing": 0.0, "charged": true, "push": 11.0, "squish": 0.1, "shake": 0.8, "trail_w": 1.8, "trail_len": 0.4,
	})


## Napalm can: thrown up and ahead (carrying some of the car's speed); the next fire press with
## Napalm still selected drops it.
static func _throw(v: Vehicle, id: String, def: Dictionary) -> void:
	var fwd := v.flat_forward()
	var carry := Vector3(v.velocity.x, 0.0, v.velocity.z) * 0.6
	var vel := fwd * float(def.get("throw", 30.0)) + carry + Vector3.UP * float(def.get("lift", 10.0))
	var p := Projectile.spawn_lob(v.get_parent(), id, v.launch_point() + Vector3.UP * 0.4, vel, v)
	v.set_live_special(p, id)


## Roadkill's charged missiles (round 21): one missile for every charge_time / salvo_max s the button
## was held (a tap = one), up to salvo_max; held red_after s past the full charge they are red and the six
## share red_total. They stream out in a narrow fan, all chasing the same lock.
static func _charged_salvo(v: Vehicle, id: String, def: Dictionary) -> void:
	var hold := v.released_hold
	var most := int(def.get("salvo_max", 6))
	var full := float(def.get("charge_time", 2.4))
	var count := clampi(1 + int(hold / (full / most)), 1, most)
	var red := hold >= full + float(def.get("red_after", 2.0))
	var over := {}
	if red:
		count = most
		var rc: Color = def.get("red_color", Color(1.0, 0.12, 0.08))
		over = {"damage": float(def.get("red_total", 70.0)) / most, "color": rc, "trail": rc.lerp(Color.WHITE, 0.15),
			"speed": float(def.get("red_speed", 70.0)), "shake": 0.25} # crimson and faster (round 22)
	var lock := v.target if is_instance_valid(v.target) and not v.target.is_dead else null
	var gap := float(def.get("salvo_gap", 0.09))
	for i in count:
		var one := func() -> void:
			if not is_instance_valid(v) or v.is_dead or not v.is_inside_tree():
				return
			var fan := (float(i) - (count - 1) * 0.5) * 0.06
			var dir := v.aim_forward().rotated(Vector3.UP, fan) + Vector3.UP * 0.05
			var aim: Vehicle = lock if is_instance_valid(lock) and not lock.is_dead else null
			Projectile.spawn(v.get_parent(), id, v.launch_point() + v.global_basis.x * fan * 4.0, dir, v, aim, over)
		if i == 0:
			one.call()
		else:
			v.get_tree().create_timer(i * gap, false, true).timeout.connect(one)


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
		var hit := lerpf(damage, rim, t) * WeaponData.DAMAGE_SCALE
		o.take_damage(hit, shooter)
		o.hit_react(o.global_position - pos, hit)
		if burn > 0.0:
			o.ignite(burn, shooter)
	blast_props(world, pos, radius, damage, shooter)


## Stage props caught in a blast (owner, round 10): trees, street lights, stands, glass, wrecks.
## They take the hit as a weapon hit from the blast's centre, so trees go down burning, away from it.
static func blast_props(world: Node, pos: Vector3, radius: float, damage: float, shooter: Vehicle) -> void:
	for node in world.get_tree().get_nodes_in_group(&"breakables"):
		var b := node as Breakable
		if b == null or b.is_broken:
			continue
		var rel := b.global_position - pos
		if Vector2(rel.x, rel.z).length() > radius + 0.5 or rel.y > radius + 1.0 or rel.y < -(radius + b.topple_height):
			continue
		b.weapon_hit(damage * WeaponData.DAMAGE_SCALE, shooter, pos, true)
	for node in world.get_tree().get_nodes_in_group(&"bots"): # a Sweet Bot takes the blast (round 18)
		var bot := node as SweetBot
		if bot and bot.global_position.distance_to(pos) < radius + 1.0:
			bot.blast_hit(damage * WeaponData.DAMAGE_SCALE, shooter)
	for node in world.get_tree().get_nodes_in_group(&"drivers"): # burning drivers are thrown, dead
		var d := node as BurningDriver
		if d and d.global_position.distance_to(pos) < radius + 1.0:
			d.blast(pos, shooter)


## Where a napalm can bursts: a fireball, everything near takes the hit and burns, a pool of fire stays.
static func napalm_burst(world: Node, pos: Vector3, direct: Vehicle, shooter: Vehicle, def: Dictionary) -> void:
	if world == null or not world.is_inside_tree():
		return
	FxKit.explosion(world, pos, 2.2, Color(1.0, 0.5, 0.12))
	# Round 9 (juice guide): the can bursts in a splash of burning fuel: a flash, a low ring of heat
	# racing out, fuel fireballs thrown round the rim, embers, and the pool left burning.
	GameFeel.flash(world, pos, 4.0, Color(1.0, 0.7, 0.3), 0.12)
	GameFeel.shockwave(world, pos, float(def.get("radius", 6.0)) * 1.6, Color(1.0, 0.5, 0.1))
	for k in 5:
		var a := TAU * k / 5.0 + randf() * 0.7
		var rim := pos + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 3.5)
		FxKit.explosion(world, rim + Vector3.UP * 0.4, 0.7, Color(1.0, 0.45, 0.1), false)
		FxKit.spark(world, rim, Vector3(cos(a), 1.2, sin(a)).normalized())
	GameFeel.scorch(world, pos, float(def.get("pool_radius", 4.5)) * 1.2)
	if is_instance_valid(shooter) and shooter.is_player or (direct and direct.is_player):
		GameFeel.hitstop(world.get_tree(), 0.05, 0.05)
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
