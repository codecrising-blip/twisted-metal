class_name Projectile
extends Node3D
## Bullets, missiles, cones, skulls, ghost missiles and napalm cans. Moves itself and
## ray-casts each step so fast shots never tunnel. Anything in the world with
## projectile_hit(damage, shooter) (stands, glass, sign letters) takes the hit too.
## Napalm cans are thrown (gravity) and wait for the next fire press: fire_again() drops them.

const HIT_MASK := 1 | 2 | Breakable.COVER_LAYER # world + vehicles + cover around palms and street lights
const LOB_GRAVITY := 30.0

static var spawned_total := 0 # used by tests

var weapon_id := ""
var def := {}
var shooter: Vehicle
var target: Vehicle
var direction := Vector3.FORWARD
var _flyby := false
var velocity := Vector3.ZERO # thrown shots only
var _life := 1.0
var _trail: CPUParticles3D
var _body: Node3D # parts that spin in flight (cones)
var _wig: Node3D # zoomy: the missile corkscrews round its true path (looks only, hits are unchanged)
var _wig_phase := 0.0
var _halo: MeshInstance3D # cone: the fireball halo throbs in flight
var _drop_mark: MeshInstance3D # napalm can: where it lands if you drop it now
var _age := 0.0


## overrides: changes to the weapon's numbers for this one shot (a charged Napalm Cone).
static func spawn(parent: Node, id: String, from: Vector3, dir: Vector3, by: Vehicle, lock: Vehicle, overrides := {}) -> Projectile:
	var p := Projectile.new()
	p.weapon_id = id
	p.def = WeaponData.get_def(id)
	if not overrides.is_empty():
		p.def = p.def.duplicate()
		p.def.merge(overrides, true)
	p.shooter = by
	p.target = lock
	p.direction = dir.normalized()
	p._life = p.def.get("life", 1.0)
	parent.add_child(p)
	p.global_position = from
	p._orient()
	p._build_visual()
	p._add_streak()
	p.add_to_group("projectiles") # the AI watches for homing shots coming at it
	if p.def.get("kind", "bullet") != "bullet":
		var col: Color = p.def.get("color", Color(1, 0.6, 0.2))
		var big := float(p.def.get("damage", 10.0)) >= 40.0
		# Release beat (juice guide): a pop bigger than the missile, a puff of launch smoke, the
		# launch sound with its peak on this frame, and the car kicks back and dips a little.
		var small: bool = p.def.get("small", false)
		GameFeel.muzzle(parent, from, col, 1.6 if big else (0.5 if small else 1.0))
		GameFeel.play("launch_" + id, from, parent, 0.0, 1.0, true)
		if not small:
			FxKit.puff(parent, from - p.direction * 0.6, 0.5 if big else 0.35)
		if p.def.get("kind", "") == "cone": # the mortar coughs out a ball of flame with it
			FxKit.explosion(parent, from + p.direction * 0.8, 0.5 + float(p.def.get("damage", 45.0)) / 150.0, Color(1.0, 0.5, 0.15), false)
		if is_instance_valid(by):
			var kick := 1.5 if big else (0.0 if small else 0.6)
			if kick > 0.0:
				by.push(-p.direction * kick)
				by.squish(p.direction, 0.015 if big else 0.008)
			if by.is_player and not small:
				GameFeel.shake(from, 0.18 if big else 0.08)
	spawned_total += 1
	return p


## A shot that falls under gravity (napalm can, remote bomb).
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
			# Each missile has its own look and trail (TM): fire = short orange, homing = purple,
			# power = fat warhead with a long red trail, zoomy = thin with a long white trail.
			var s := float(def.get("model_scale", 1.0))
			var holder: Node3D = self
			if def.get("small", false): # zoomy (round 9): a swarm that corkscrews, each on its own phase
				_wig = Node3D.new()
				add_child(_wig)
				holder = _wig
				_wig_phase = randf() * TAU
			var body := MeshKit.mat(Color(0.26, 0.26, 0.28), 0.4, 0.6)
			MeshKit.cylinder(holder, 0.12 * s, 0.9 * s, Vector3.ZERO, body, Vector3(90, 0, 0), 8)
			MeshKit.cylinder(holder, 0.12 * s, 0.3 * s, Vector3(0, 0, -0.6 * s), MeshKit.emissive(color, 3.0), Vector3(-90, 0, 0), 8, 0.0)
			MeshKit.sphere(holder, 0.13 * s, Vector3(0, 0, 0.5 * s), MeshKit.emissive(color.lerp(Color.WHITE, 0.4), 6.0), Vector3(1, 1, 1.4), 6)
			if not def.get("small", false):
				_add_light(color, 2.0, 5.0)
		"freeze":
			MeshKit.sphere(self, 0.35, Vector3.ZERO, MeshKit.emissive(color, 4.0), Vector3.ONE, 10)
			var t := FxKit.fire(0.5, 20)
			t.color_ramp = null
			t.color = Color(0.6, 0.9, 1.0, 0.6)
			_add_trail(t)
			_add_light(color, 2.5, 6.0)
		"cone":
			# Sweet Tooth's flaming cone, point first and spinning: a scorched waffle cone, a molten
			# scoop and a fireball halo around it, flames pouring off the back. The charged one is
			# twice the size and white-hot.
			var charged: bool = def.get("charged", false)
			var big := 2.3 if charged else 1.5
			_body = Node3D.new()
			add_child(_body)
			var waffle := MeshKit.mat(Color(0.55, 0.34, 0.14), 0.9)
			var c1 := MeshKit.cylinder(_body, 0.36 * big, 1.0 * big, Vector3(0, 0, -0.2 * big), waffle, Vector3(-90, 0, 0), 8, 0.02)
			c1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			MeshKit.torus(_body, 0.3 * big, 0.38 * big, Vector3(0, 0, 0.12 * big), MeshKit.mat(Color(0.18, 0.1, 0.05), 0.9), Vector3(90, 0, 0))
			var core := Color(1.0, 0.9, 0.6) if charged else Color(1.0, 0.45, 0.12)
			MeshKit.sphere(_body, 0.42 * big, Vector3(0, 0, 0.35 * big), MeshKit.emissive(core, 3.5), Vector3.ONE, 10)
			var halo := MeshKit.emissive(Color(1.0, 0.4, 0.08), 2.0)
			halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			halo.albedo_color = Color(1.0, 0.45, 0.1, 0.35)
			halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var h := MeshKit.sphere(self, 0.85 * big, Vector3(0, 0, 0.2 * big), halo, Vector3(1, 1, 1.3), 10)
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_halo = h
			_add_trail(FxKit.fire(1.2 * big, int(30 * big)))
			_add_light(color, 3.0 * big, 8.0)
		"gas":
			# A dented red gas can tumbling through the air, leaking fire.
			var can := MeshKit.mat(Color(0.62, 0.08, 0.06), 0.6, 0.3)
			MeshKit.box(self, Vector3(0.55, 0.75, 0.3), Vector3.ZERO, can)
			MeshKit.box(self, Vector3(0.57, 0.12, 0.32), Vector3(0, 0.1, 0), MeshKit.mat(Color(0.85, 0.65, 0.1), 0.6))
			MeshKit.cylinder(self, 0.06, 0.25, Vector3(0.18, 0.48, 0), MeshKit.mat(Color(0.2, 0.2, 0.2), 0.5, 0.6), Vector3(0, 0, -30), 6)
			_add_trail(FxKit.fire(0.7, 22))
			_add_light(color, 2.0, 6.0)
			# Tell (round 9): a faint orange ring on the ground under the can, where its fire would spread
			# if you dropped it now.
			var mark := StandardMaterial3D.new()
			mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mark.albedo_color = Color(1.0, 0.45, 0.08, 0.45)
			var pr := float(def.get("pool_radius", 4.5))
			_drop_mark = MeshKit.torus(self, pr - 0.18, pr, Vector3.ZERO, mark)
			_drop_mark.top_level = true
			_drop_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _add_streak() -> void:
	if def.has("trail"):
		Streak.attach(_wig if _wig else self, def["trail"], float(def.get("trail_len", 0.4)), float(def.get("trail_w", 0.5)))


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
	# A missile passing close to the camera whooshes by (once).
	if not _flyby and GameFeel.camera and def.get("kind", "bullet") in ["missile", "cone", "skull", "ghost"]:
		if global_position.distance_squared_to(GameFeel.camera.global_position) < 81.0:
			_flyby = true
			GameFeel.play("missile_flyby", global_position, get_parent(), -4.0)

	_age += delta
	if _body:
		_body.rotate_object_local(Vector3.FORWARD, 14.0 * delta)
	if _wig: # corkscrew, opening up after launch
		var a := _wig_phase + _age * 22.0
		_wig.position = Vector3(cos(a), sin(a), 0.0) * minf(0.45, _age * 2.0)
	if _halo: # the fireball throbs
		var k := 1.0 + 0.14 * sin(_age * 26.0)
		_halo.scale = Vector3(k, k, k * 1.3)
	if _drop_mark:
		var g := Specials.ground_below(get_parent(), global_position)
		_drop_mark.global_position = g + Vector3.UP * 0.15
		_drop_mark.global_basis = Basis.IDENTITY.scaled(Vector3(1.0, 0.3, 1.0))
		_drop_mark.visible = global_position.y - g.y > 1.5
	var step: Vector3
	if _thrown():
		velocity.y -= LOB_GRAVITY * delta
		direction = velocity.normalized()
		step = velocity * delta
	else:
		var homing: float = def.get("homing", 0.0)
		if homing > 0.0 and is_instance_valid(target) and not target.is_dead and not target.is_hidden():
			var to_t := target.aim_point() - global_position
			var desired := to_t.normalized()
			var angle := direction.angle_to(desired)
			if def.has("seek") and rad_to_deg(angle) > float(def["seek"]):
				target = null # round 12: off the seeker's edge, the lock is gone; straight on from here
			elif angle > 0.001:
				var rate := homing
				if def.has("seek"): # weaker as it closes in, so a late hard turn makes it overshoot
					rate *= lerpf(WeaponData.NEAR_TURN, 1.0, clampf(to_t.length() / WeaponData.NEAR_RANGE, 0.0, 1.0))
				direction = direction.slerp(desired, minf(1.0, rate * delta / angle)).normalized()
		step = direction * float(def.get("speed", 50.0)) * delta

	var from := global_position
	var to := from + step
	if _thrown():
		rotate_object_local(Vector3.RIGHT, delta * 6.0) # tumbling
	var mask := 2 if def.get("through_walls", false) else HIT_MASK
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if def.get("kind", "bullet") == "bullet":
		# Round 12 (owner): machine-gun rounds meet a car's box made 10% bigger than its body.
		var car_hit := _bullet_car(from, to, hit)
		if not car_hit.is_empty():
			hit = car_hit
	if not hit.is_empty():
		_explode(hit.position, hit.normal, hit.collider)
		return
	global_position = to
	if not _thrown():
		_orient()


## Bullets: the nearest car whose body box, scaled by BULLET_BOX, the step from -> to crosses before
## whatever the ray hit. Returns a ray-style hit ({position, normal, collider}) or {}.
const BULLET_BOX := 1.1

func _bullet_car(from: Vector3, to: Vector3, ray_hit: Dictionary) -> Dictionary:
	var limit := 1.0
	if not ray_hit.is_empty():
		limit = from.distance_to(ray_hit.position) / maxf(from.distance_to(to), 0.0001)
	var best: Vehicle = null
	var best_t := limit
	for n in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Vehicle
		if v == null or v == shooter or v.is_dead or v.global_position.distance_squared_to(from) > 40000.0:
			continue
		var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.0))
		var half := Vector3(size.x, size.y - Vehicle.BODY_CLEARANCE, size.z) * 0.5 * BULLET_BOX
		var centre := Vector3(0.0, (size.y + Vehicle.BODY_CLEARANCE) * 0.5, 0.0)
		var inv := v.global_transform.affine_inverse()
		var t := segment_box(inv * from - centre, inv * to - centre, half)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = v
	if best == null:
		return {}
	return {"position": from.lerp(to, best_t), "normal": -direction, "collider": best}


## Where (0..1) the segment a -> b first enters the box of half size `half` around the origin; -1 if never.
static func segment_box(a: Vector3, b: Vector3, half: Vector3) -> float:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 0.000001:
			if absf(a[i]) > half[i]:
				return -1.0
			continue
		var ta := (-half[i] - a[i]) / d[i]
		var tb := (half[i] - a[i]) / d[i]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return -1.0
	return t0


func _thrown() -> bool:
	return def.has("lift")


## What a hit does to the car beyond damage, by weapon (owner, session 6): an elastic dip for some
## weight classes, a steering twitch (homing), a roll-over (power), camera shake and a white-out
## for the player.
static func hit_feel(v: Vehicle, d: Dictionary, dir: Vector3) -> void:
	var cls: String = v.stats.get("class", "medium")
	var classes: Array = d.get("squish_classes", ["light", "medium", "heavy", "super"])
	if d.has("squish") and classes.has(cls):
		var by_weight := {"light": 1.0, "medium": 0.85, "heavy": 0.6, "super": 0.35}
		v.squish(dir, float(d["squish"]) * float(by_weight.get(cls, 0.8)))
	if d.has("wobble"):
		v.wobble(float(d["wobble"]))
	if d.get("flip", false):
		var along := Vector3(dir.x, 0.0, dir.z).normalized()
		v.blast_knock(along * 5.0 + Vector3.UP * float(WeaponData.FLIP_UP.get(cls, 7.0)), float(WeaponData.FLIP_ROLL.get(cls, 1.0)), false)
	if v.is_player:
		if d.has("shake") and GameFeel.camera:
			GameFeel.camera.add_shake(float(d["shake"]))
		if d.has("flashbang"):
			GameFeel.flash_bang(float(d["flashbang"]))


## The next fire press after throwing: a napalm can drops straight down.
func fire_again() -> void:
	if def.get("kind", "") == "gas":
		velocity = Vector3(0, -float(def.get("drop_speed", 26.0)), 0)


func _orient() -> void:
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)


func _explode(pos: Vector3, normal: Vector3, collider: Object) -> void:
	var world := get_parent()
	if collider is Node and (collider as Node).has_meta("cover_of"): # caught by a palm's / lamp's cover
		collider = (collider as Node).get_meta("cover_of")
	var kind: String = def.get("kind", "bullet")
	var dmg := float(def.get("damage", 1.0)) * WeaponData.DAMAGE_SCALE
	if kind == "gas":
		Specials.napalm_burst(world, pos, collider as Vehicle, shooter, def)
		if collider is Vehicle:
			(collider as Vehicle).take_damage(dmg, shooter)
			(collider as Vehicle).ignite(float(def.get("burn", 5.0)), shooter)
			Projectile.hit_feel(collider as Vehicle, def, direction) # a direct hit whites out the screen
	elif collider is Vehicle:
		var v := collider as Vehicle
		v.take_damage(dmg, shooter)
		# Feel it: shove the car the way the shot was going, jolt the body, freeze a blink on big hits.
		var push := float(def.get("push", 0.0))
		if push > 0.0:
			var along := Vector3(direction.x, 0.0, direction.z).normalized()
			v.push(along * push * v.knockback + Vector3.UP * push * 0.3 * v.knockback)
		v.hit_react(direction, dmg)
		Projectile.hit_feel(v, def, direction)
		if dmg >= 30.0 and (v.is_player or (is_instance_valid(shooter) and shooter.is_player)):
			GameFeel.hitstop(get_tree(), 0.05 + minf(dmg, 90.0) / 1500.0)
		if def.has("freeze"):
			v.freeze_for(float(def["freeze"]))
		if def.has("burn"):
			v.ignite(float(def["burn"]), shooter)
	elif collider is Breakable: # falls away from the shot; explosive and fire shots set wood alight
		(collider as Breakable).weapon_hit(dmg, shooter, pos - direction * 3.0, kind != "bullet" and kind != "freeze")
	elif collider != null and collider.has_method("projectile_hit"):
		collider.projectile_hit(dmg, shooter)
	if kind == "bullet":
		FxKit.spark(world, pos, normal)
		if collider != null and not (collider is Vehicle) and randf() < 0.25:
			GameFeel.play("ricochet", pos, world, -12.0) # TM 2012 ricochets off walls and ground
	elif kind == "freeze": # an ice burst, not a fireball: crystals, frost mist, a cold flash
		GameFeel.play("freeze_impact", pos, world, -2.0, 1.0, true)
		GameFeel.flash(world, pos, 1.6, Color(0.75, 0.92, 1.0), 0.08)
		FxKit.shatter(world, pos, Vector3.ONE * 0.4, normal, 2.0, Color(0.7, 0.92, 1.0), true)
		FxKit.puff(world, pos, 0.5)
	elif kind == "cone":
		# Round 9 (juice guide): a white-hot pop, a fireball that rolls up out of the hit a beat later,
		# a ring of heat along the ground, embers, a scorch. The charged cone does it all bigger.
		var big := 1.0 + dmg / 90.0
		FxKit.explosion(world, pos, 1.2 + dmg / 60.0, Color(1.0, 0.5, 0.15))
		GameFeel.flash(world, pos, 2.2 * big, Color(1.0, 0.8, 0.45), 0.1)
		GameFeel.shockwave(world, pos - Vector3.UP * 0.8, 6.0 * big, Color(1.0, 0.55, 0.15))
		for k in 3:
			FxKit.spark(world, pos, (normal + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))).normalized())
		GameFeel.scorch(world, pos, 2.0 * big)
		var up := pos + Vector3.UP * 1.6 * big
		world.get_tree().create_timer(0.07, false).timeout.connect(func() -> void:
			if is_instance_valid(world) and world.is_inside_tree():
				FxKit.explosion(world, up, 0.9 * big, Color(1.0, 0.38, 0.08), false))
	elif kind != "gas":
		var small: bool = def.get("small", false)
		FxKit.explosion(world, pos, (0.4 if small else 0.8) + dmg / 40.0, def.get("color", Color(1, 0.5, 0.15)))
		if small: # zoomy: each of the ten pops white-hot with a spark, so the salvo crackles
			GameFeel.flash(world, pos, 1.0, Color(1.0, 0.95, 0.7), 0.06)
			FxKit.spark(world, pos, normal)
	if _drop_mark:
		_drop_mark.queue_free()
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
