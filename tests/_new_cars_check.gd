extends SceneTree
## Round 28: Thumper, Brimstone and Darkside do what the design says (quick check while building).
##   godot --headless --path . -s tests/_new_cars_check.gd

var _fails := 0


## Holds whatever inputs the test sets (no controller = inputs cleared every frame).
class Idle:
	extends RefCounted
	func drive(_v: Vehicle, _d: float) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _put(v: Vehicle, x: float, z: float, yaw: float) -> void:
	v.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), LosAngelesArena.ground(x, z, 0.1))
	v.velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.speed = 0.0


func _run() -> void:
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.full_roster = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	for e: Vehicle in main.enemies:
		e.controller = null
		_put(e, 120, 120 + main.enemies.find(e) * 10, 0)
	main.player.controller = null
	_put(main.player, -120, 120, 0)
	var th: Vehicle = main._spawn("thumper", Transform3D(Basis.IDENTITY, LosAngelesArena.ground(0, 40, 0.1)), false)
	var br: Vehicle = main._spawn("brimstone", Transform3D(Basis.IDENTITY, LosAngelesArena.ground(-40, 40, 0.1)), false)
	var ds: Vehicle = main._spawn("darkside", Transform3D(Basis.IDENTITY, LosAngelesArena.ground(40, -40, 0.1)), false)
	var dummy: Vehicle = main._spawn("outlaw", Transform3D(Basis.IDENTITY, LosAngelesArena.ground(0, 30, 0.1)), false)
	for v: Vehicle in [th, br, ds, dummy]:
		v.controller = Idle.new()
		v.auto_target = false
	await _frames(10)

	# ---- Thumper (round 29): Megafire = a bar of 8 tabs, 0.7 s a tab, a full tab to light it, 4 s to refill one.
	_put(th, 0, 40, 0)
	_put(dummy, 0, 32, 0)
	await _frames(10)
	_check(th.fuel_tank == 8.0 and th.fuel >= 7.99, "Thumper's Megafire bar: 8 tabs, full at the start (%.1f / %.1f)" % [th.fuel, th.fuel_tank])
	th.selected = th.weapon_order.find("megafire")
	th.in_fire_weapon = true # a tap: lit, let go at once
	await _frames(2)
	th.in_fire_weapon = false
	await _frames(20)
	_check(th.flaming, "a tap still burns on (the ignition costs a whole tab)")
	await _frames(40)
	_check(not th.flaming and absf(th.fuel - 7.0) < 0.15, "the tap burned exactly one tab (%.2f left)" % th.fuel)
	var h0 := dummy.health
	th.in_fire_weapon = true # hold for a second on a car 8 m ahead
	await _frames(60)
	th.in_fire_weapon = false
	await _frames(45)
	_check(dummy.health < h0 - 25.0, "Megafire burns hard (%.1f -> %.1f in about a second)" % [h0, dummy.health])
	_check(dummy.burn_time > 0.0 or dummy.health < h0 - 25.0, "and sets it burning")
	th.ignite(4.0, dummy)
	_check(th.burn_time <= 0.0, "Hot Engine: Thumper never burns")
	_check(not th.flaming, "the flame stops when fire is let go")
	# the whole bar on Outlaw: about 80% of her health (owner)
	_put(dummy, 0, 32, 0)
	dummy.heal(999.0)
	dummy.burn_time = 0.0
	th.fuel = 8.0
	await _frames(5)
	h0 = dummy.health
	th.in_fire_weapon = true
	await _frames(360)
	th.in_fire_weapon = false
	var left := th.fuel
	await _frames(150)
	var share := (h0 - dummy.health) / dummy.max_health
	_check(share > 0.74 and share < 0.9, "the full bar takes %.0f%% of Outlaw (owner: about 80%%)" % (share * 100.0))
	_check(left < 0.15, "and empties the bar in about 5.6 s (%.2f)" % left)
	th.fuel = 0.6
	th.in_fire_weapon = true
	await _frames(5)
	_check(not th.flaming, "no ignition without a full tab")
	th.in_fire_weapon = false
	await _frames(242)
	_check(th.fuel > 1.55 and th.fuel < 1.68, "a tab refills in 4 s (%.2f)" % th.fuel)
	# Earthquake Slam (round 29): costs 2 tabs, throws a car beside him away and rolls it.
	_put(th, 0, 40, 0)
	_put(dummy, 5, 40, 0)
	dummy.heal(999.0)
	await _frames(5)
	h0 = dummy.health
	th.fuel = 8.0
	var d0 := dummy.global_position.distance_to(th.global_position)
	th.energy_move("secondary")
	await _frames(4)
	var vy := dummy.linear_velocity.y
	var spin := dummy.angular_velocity.length()
	await _frames(40)
	_check(th.fuel > 5.95 and th.fuel < 6.3, "Earthquake Slam costs 2 tabs (%.2f left, a little refilled since)" % th.fuel)
	_check(dummy.global_position.distance_to(th.global_position) > d0 + 4.0, "it throws a car beside him away (%.1f -> %.1f m)" % [d0, dummy.global_position.distance_to(th.global_position)])
	_check(vy > 3.0 and spin > 1.0, "lifting it on the near side so it rolls (up %.1f m/s, spin %.1f)" % [vy, spin])
	_check(dummy.health < h0 - 5.0, "and hurts it (%.1f -> %.1f)" % [h0, dummy.health])
	await _frames(120)
	_put(dummy, 0, 32, 0)
	_put(th, 0, 40, 0)
	dummy.heal(999.0)

	# ---- Brimstone: the sinner runs down a car and blows on it; the sermon reflects damage.
	_put(br, -40, 40, 0)
	_put(dummy, -40, 0, 0)
	dummy.heal(999.0)
	await _frames(5)
	h0 = dummy.health
	br.target = dummy
	br.selected = br.weapon_order.find("sinner_bomber")
	br.want_fire_weapon = true
	await _frames(2)
	var runners := root.find_children("*", "Sinner", true, false)
	_check(runners.size() == 1, "Sinner Bomber throws a sinner")
	var clung := false
	for i in 300:
		await physics_frame
		for s in root.find_children("*", "Sinner", true, false):
			if (s as Sinner).state == Sinner.State.CLING:
				clung = true
		if dummy.health < h0 - 20.0:
			break
	_check(clung, "the sinner runs to the car and clings to it")
	_check(dummy.health < h0 - 30.0, "and blows on it (%.1f -> %.1f)" % [h0, dummy.health])
	br.ammo["sinner_bomber"] = 2
	br.energy_move("secondary")
	_check(br.sermon_time > 5.0, "Hellfire Sermon is on for 6 s")
	var dh := dummy.health
	var bh := br.health
	br.take_damage(20.0, dummy)
	_check(absf((dh - dummy.health) - 6.0) < 0.6, "the sermon sends 30%% back (%.1f)" % (dh - dummy.health))
	_check(dummy.burn_time > 0.0, "and sets the attacker burning")
	_check(br.health < bh, "Brimstone still takes the hit")

	# ---- Darkside: the slam pins the first car and crushes it into a wall; the ash cloud drains energy.
	_put(ds, 70, 60, 0)
	_put(dummy, 70, 38, 0)
	dummy.heal(999.0)
	dummy.burn_time = 0.0
	await _frames(5)
	h0 = dummy.health
	ds.selected = ds.weapon_order.find("darkside_slam")
	ds.want_fire_weapon = true
	var pinned := false
	var fast := 0.0
	for i in 200:
		await physics_frame
		fast = maxf(fast, ds.linear_velocity.length())
		if dummy.pinned_by == ds:
			pinned = true
		if i == 40:
			_check(not ds.freeze_for(2.0) and ds.frozen_time <= 0.0, "nothing freezes a slamming Darkside")
	_check(fast > float(ds.stats.max_speed) * 1.2, "the slam charges well past his top speed (%.1f m/s)" % fast)
	_check(pinned, "the slam pins the first car it hits")
	_check(dummy.health <= h0 - 30.0, "pinned: 30 at least (%.1f -> %.1f)" % [h0, dummy.health])
	_check(ds.slam_time <= 0.0, "the slam is over")
	_put(ds, -70, 60, 0)
	_put(dummy, -70, 69, 0)
	dummy.energy = 100.0
	await _frames(5)
	ds.ammo["darkside_slam"] = 2
	ds.energy = 20.0
	ds.energy_move("secondary")
	await _frames(90)
	_check(dummy.energy < 90.0, "Ash Cloud drains a car behind him (%.1f)" % dummy.energy)
	dummy.want_move = "shield"
	var before := dummy.shield_time
	dummy.energy_move("shield")
	_check(dummy.shield_time <= before, "no energy moves inside the ash")
	ds.energy = 100.0
	ds.energy_move("shield")
	_check(ds.shield_time > 3.5, "Iron Curtain: Darkside's shield lasts 4 s")
	print("NEW CARS: %s" % ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	quit(0 if _fails == 0 else 1)
