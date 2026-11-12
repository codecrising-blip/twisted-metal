class_name Projectile
extends Node3D
## Bullets, missiles, cones, skulls, ghost missiles and napalm cans. Moves itself and
## ray-casts each step so fast shots never tunnel. Anything in the world with
## projectile_hit(damage, shooter) (stands, glass, sign letters) takes the hit too.
## Napalm cans are thrown (gravity) and wait for the next fire press: fire_again() drops them.

const HIT_MASK := 1 | 2 # world + vehicles
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
		GameFeel.muzzle(parent, from, col, 1.6 if big else (0.5 if p.def.get("small", false) else 1.0))
		GameFeel.play("launch_" + id, from, parent)
		if big and is_instance_valid(by): # a heavy shot kicks the car back a little
			by.push(-p.direction * 1.5)
			if by.is_player:
				GameFeel.shake(from, 0.18)
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
			var body := MeshKit.mat(Color(0.26, 0.26, 0.28), 0.4, 0.6)
			MeshKit.cylinder(self, 0.12 * s, 0.9 * s, Vector3.ZERO, body, Vector3(90, 0, 0), 8)
			MeshKit.cylinder(self, 0.12 * s, 0.3 * s, Vector3(0, 0, -0.6 * s), MeshKit.emissive(color, 3.0), Vector3(-90, 0, 0), 8, 0.0)
			MeshKit.sphere(self, 0.13 * s, Vector3(0, 0, 0.5 * s), MeshKit.emissive(color.lerp(Color.WHITE, 0.4), 6.0), Vector3(1, 1, 1.4), 6)
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
		Streak.attach(self, def["trail"], float(def.get("trail_len", 0.4)), float(def.get("trail_w", 0.5)))


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

	if _body:
		_body.rotate_object_local(Vector3.FORWARD, 14.0 * delta)
	var step: Vector3
	if _thrown():
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
	if _thrown():
		rotate_object_local(Vector3.RIGHT, delta * 6.0) # tumbling
	var mask := 2 if def.get("through_walls", false) else HIT_MASK
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.position, hit.normal, hit.collider)
		return
	global_position = to
	if not _thrown():
		_orient()


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
	elif collider != null and collider.has_method("projectile_hit"):
		collider.projectile_hit(dmg, shooter)
	if kind == "bullet":
		FxKit.spark(world, pos, normal)
		if collider != null and not (collider is Vehicle) and randf() < 0.25:
			GameFeel.play("ricochet", pos, world, -12.0) # TM 2012 ricochets off walls and ground
	elif kind == "freeze":
		FxKit.explosion(world, pos, 0.6, Color(0.5, 0.85, 1.0))
	elif kind == "cone":
		FxKit.explosion(world, pos, 1.2 + dmg / 60.0, Color(1.0, 0.5, 0.15))
	elif kind != "gas":
		FxKit.explosion(world, pos, (0.4 if def.get("small", false) else 0.8) + dmg / 40.0, def.get("color", Color(1, 0.5, 0.15)))
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
