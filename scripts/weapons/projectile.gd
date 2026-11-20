class_name Projectile
extends Node3D
## Bullets, missiles, cones, skulls, ghost missiles and napalm cans. Moves itself and
## ray-casts each step so fast shots never tunnel. Anything in the world with
## projectile_hit(damage, shooter) (stands, glass, sign letters) takes the hit too.
## Napalm cans are thrown (gravity) and wait for the next fire press: fire_again() drops them.

const HIT_MASK := 1 | 2 | Breakable.COVER_LAYER | BurningDriver.LAYER # world, vehicles, cover round palms and street lights, burning drivers
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
var ignore: Array[RID] = [] # bodies this shot passes through (the Sweet Bot that fired it)


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
	if p.def.get("kind", "") == "skull": # round 23: the rider flares red, faces burst out round the bike
		SpiritSkull.launch(by, from, p.direction)
	if p.def.get("kind", "bullet") != "bullet":
		var col: Color = p.def.get("color", Color(1, 0.6, 0.2))
		var big := float(p.def.get("damage", 10.0)) >= 40.0
		# Release beat (juice guide): a pop bigger than the missile, a puff of launch smoke, the
		# launch sound with its peak on this frame, and the car kicks back and dips a little.
		var small: bool = p.def.get("small", false)
		GameFeel.muzzle(parent, from, col, 1.6 if big else (0.5 if small else 1.0))
		GameFeel.play("launch_" + id, from, parent, float(p.def.get("sound_db", 0.0)), 1.0, true)
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
			# Round 22: "glow" > 1 (Roadkill's charged missiles) = the whole missile lit in its colour (a normal
			# missile only lights its nose and tail), inside a tight additive halo. Pushing the emission much
			# higher only bleaches the colour through the tonemapper (lime went yellow, crimson went pink).
			var g := float(def.get("glow", 1.0))
			var lit := g > 1.0
			var body: Material = MeshKit.emissive(color, 0.6 * g) if lit else MeshKit.mat(Color(0.26, 0.26, 0.28), 0.4, 0.6)
			MeshKit.cylinder(holder, 0.12 * s, 0.9 * s, Vector3.ZERO, body, Vector3(90, 0, 0), 8)
			MeshKit.cylinder(holder, 0.12 * s, 0.3 * s, Vector3(0, 0, -0.6 * s), MeshKit.emissive(color, 1.0 * g if lit else 3.0), Vector3(-90, 0, 0), 8, 0.0)
			MeshKit.sphere(holder, 0.13 * s, Vector3(0, 0, 0.5 * s), MeshKit.emissive(color.lerp(Color.WHITE, 0.15 if lit else 0.4), 6.0), Vector3(1, 1, 1.4), 6)
			if lit:
				var halo := MeshKit.emissive(color, 1.0)
				halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				halo.albedo_color = Color(color.r, color.g, color.b, 0.3)
				var hm := MeshKit.sphere(holder, 0.27 * s, Vector3(0, 0, 0.1 * s), halo, Vector3(1, 1, 2.9), 8)
				hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# Round 23: two sparks orbit it as it flies (the body spins about the flight axis): a charged dart.
				_body = Node3D.new()
				holder.add_child(_body)
				for k in 2:
					var dot := MeshKit.sphere(_body, 0.05 * s + 0.03, Vector3(cos(PI * k), sin(PI * k), 0.0) * (0.3 * s + 0.12), MeshKit.emissive(color.lerp(Color.WHITE, 0.35), 1.4), Vector3.ONE, 6)
					dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					Streak.attach(dot, color, 0.12, 0.05)
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
			_cone_visual(color)
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
		"clamp":
			_body = Node3D.new() # Outlaw's wheel clamp (round 18): a yellow iron boot tumbling end over end
			add_child(_body)
			WheelClamp.build_boot(_body)
			_add_light(color, 1.2, 4.0)
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


## Sweet Tooth's Napalm Cone. Round 23 (owner: "the specials must look like special weapons, not plain
## fireballs"): the Blender cone (tools/blender/build_napalm_cone.py: a waffle cone, scorched tip, molten napalm
## scoop dripping over the rim) flying point first and spinning, the game's own fire (FoamFire) pouring off the
## scoop and streaming back, two ribbons of flame spiralling round it as it spins, embers. The charged one is
## bigger, burns white-hot at the scoop and throws rings of fire behind it as it goes (`_ring_step`).
func _cone_visual(color: Color) -> void:
	var charged: bool = def.get("charged", false)
	var big := 2.3 if charged else 1.5
	_body = Node3D.new()
	add_child(_body)
	if ModelLib.has("napalm_cone"):
		var m := ModelLib.instance("napalm_cone", "cone")
		m.scale = Vector3.ONE * big
		_body.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var waffle := MeshKit.mat(Color(0.55, 0.34, 0.14), 0.9)
		MeshKit.cylinder(_body, 0.36 * big, 1.0 * big, Vector3(0, 0, -0.2 * big), waffle, Vector3(-90, 0, 0), 8, 0.02)
		MeshKit.sphere(_body, 0.42 * big, Vector3(0, 0, 0.35 * big), MeshKit.emissive(Color(1.0, 0.45, 0.12), 3.5), Vector3.ONE, 10)
	# A soft glow round the scoop only (the old halo round the whole cone made it read as a fireball).
	var core := Color(1.0, 0.85, 0.5) if charged else Color(1.0, 0.45, 0.1)
	var halo := MeshKit.emissive(core, 1.5)
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(core.r, core.g, core.b, 0.16 if charged else 0.1)
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var h := MeshKit.sphere(self, 0.42 * big, Vector3(0, 0, 0.5 * big), halo, Vector3(1, 1, 1.0), 10)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo = h
	# The game's fire off the scoop, streaming back (it keeps most of the cone's speed: a tail, not a column).
	var fire := FoamFire.new()
	fire.box = Vector3(0.28, 0.28, 0.18) * big
	fire.position = Vector3(0, 0, 0.5 * big)
	fire.rate = 150.0 if charged else 110.0
	fire.life = 0.3
	fire.size = 0.62 * big
	fire.rise = 0.6
	fire.inherit = 0.93
	fire.drag = 1.6
	fire.glow = 0.85
	fire.on = true
	add_child(fire)
	fire.prime(direction * float(def.get("speed", 60.0)))
	# Two flame ribbons wound round it: points on the spinning body leave a spiral behind.
	for k in 2:
		var p := Node3D.new()
		var a := PI * k
		p.position = Vector3(cos(a), sin(a), 0.1) * 0.42 * big
		_body.add_child(p)
		Streak.attach(p, Color(1.0, 0.55, 0.12) if not charged else Color(1.0, 0.85, 0.45), 0.22, 0.07 * big)
	_add_trail(_embers(big))
	_add_light(color, 3.0 * big, 8.0)


## Sparks and embers shed from the burning cone (additive: immune to the black-quad bug).
static func _embers(big: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = FxKit.particle_mesh(true)
	p.amount = int(20 * big)
	p.lifetime = 0.45
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4 * big
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	p.color_ramp = FxKit._ramp([Color(1, 0.9, 0.5, 1), Color(1.0, 0.5, 0.12, 0.8), Color(0.9, 0.2, 0.05, 0)])
	return p


var _ring_t := 0.0

## The charged cone throws a ring of fire behind it every few metres, square to its path, growing and fading.
func _ring_step(delta: float) -> void:
	_ring_t -= delta
	if _ring_t > 0.0:
		return
	_ring_t = 0.07
	var world := get_parent()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	var r := MeshInstance3D.new()
	r.mesh = torus
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(r)
	r.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5), global_position + direction * 0.6)
	r.scale = Vector3.ONE * 0.7
	var tw := r.create_tween().set_parallel(true)
	tw.tween_property(r, "scale", Vector3.ONE * 2.6, 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.32)
	tw.chain().tween_callback(r.queue_free)


## Mr. Grimm's skull. Round 21 gave it the sculpted bone skull, round 22 a see-through ghost of it; round 23 (owner's
## Head-On video): a SPIRIT FACE, pinkish red, three faces closing into one, gold sparkles behind (SpiritSkull). It
## flies dead straight (no tracking at all) and hits for 65.
func _skull_visual(_color: Color) -> void:
	add_child(SpiritSkull.new())
	_add_trail(SpiritSkull.sparkles())
	_add_light(Color(1.0, 0.15, 0.12), 4.0, 11.0)



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
		_body.rotate_object_local(Vector3.RIGHT if def.get("kind", "") == "clamp" else Vector3.FORWARD, 14.0 * delta)
	if _wig: # corkscrew, opening up after launch
		var a := _wig_phase + _age * 22.0
		_wig.position = Vector3(cos(a), sin(a), 0.0) * minf(0.45, _age * 2.0)
	if _halo: # the glow round the scoop throbs
		var k := 1.0 + 0.14 * sin(_age * 26.0)
		_halo.scale = Vector3(k, k, k * 1.1)
	if def.get("charged", false) and def.get("kind", "") == "cone":
		_ring_step(delta)
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
	var skip: Array[RID] = ignore.duplicate()
	if is_instance_valid(shooter) and not (def.get("hits_owner", false) and _age > 0.15):
		skip.append(shooter.get_rid()) # Sweet Bot's missiles can hit Sweet Tooth (owner, round 16)
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if def.get("kind", "bullet") == "bullet":
		# Round 12 (owner): machine-gun rounds meet a car's box made 10% bigger than its body.
		var car_hit := _bullet_car(from, to, hit, STRAIGHT_REACH_UP)
		if not car_hit.is_empty():
			hit = car_hit
	elif float(def.get("homing", 0.0)) <= 0.0 and def.get("kind", "") in ["missile", "cone", "skull", "clamp"]:
		# Round 21: straight shots fly level (zero angle) from launchers of every height, so a car's box
		# reaches up STRAIGHT_REACH_UP higher for them: a level shot from a tall truck still hits a low car.
		var car_hit := _bullet_car(from, to, hit, STRAIGHT_REACH_UP)
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

const STRAIGHT_REACH_UP := 1.4 # round 21: m a car's box reaches up for level shots (launchers up to ~3 m)

func _bullet_car(from: Vector3, to: Vector3, ray_hit: Dictionary, reach_up := 0.0) -> Dictionary:
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
		var half := Vector3(size.x, size.y - Vehicle.BODY_CLEARANCE + reach_up, size.z) * 0.5 * BULLET_BOX
		var centre := Vector3(0.0, (size.y + Vehicle.BODY_CLEARANCE + reach_up) * 0.5, 0.0)
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
		if def.has("clamp"):
			v.clamp_for(float(def["clamp"]), pos, shooter)
		if def.has("burn"):
			v.ignite(float(def["burn"]), shooter)
	elif collider is Breakable: # falls away from the shot; explosive and fire shots set wood alight
		(collider as Breakable).weapon_hit(dmg, shooter, pos - direction * 3.0, kind != "bullet" and kind != "freeze" and kind != "clamp")
	elif collider != null and collider.has_method("projectile_hit"):
		collider.projectile_hit(dmg, shooter)
	if kind == "bullet":
		FxKit.spark(world, pos, normal)
		if collider != null and not (collider is Vehicle) and randf() < 0.25:
			GameFeel.play("ricochet", pos, world, -12.0) # TM 2012 ricochets off walls and ground
	elif kind == "clamp": # iron on steel: a clank and a spray of sparks, no fireball
		GameFeel.play("ram_impact", pos, world, -6.0, 1.5, true)
		for k in 2:
			FxKit.spark(world, pos, (normal + Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6))).normalized())
		if not (collider is Vehicle):
			FxKit.puff(world, pos, 0.3)
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
		if kind == "skull": # round 23: the spirit face blows apart in gold sparks over the fireball
			SpiritSkull.burst(world, pos)
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
