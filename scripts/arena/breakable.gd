class_name Breakable
extends StaticBody3D
## Stage props that break: hot dog stands, tunnel glass, palm trees, sign letters, tower legs.
## Small props shatter when a car drives into them and only cost it about 10% of its speed
## (design 2.0.1 rule 2). Big ones only take damage from weapons and rams.
## Builders put the meshes under `visual` (origin at the base) and add the collision shape.

signal broken(prop: Breakable, by: Vehicle)
## Emitted as it starts to break, before it falls or shatters: props drawn elsewhere (Paris's trees are
## drawn by their row's MultiMesh) give it a visual of its own here.
signal breaking(prop: Breakable)

enum Style { SHATTER, TOPPLE }

## Owner, round 9: every breakable goes down to ~0.6 s of machine-gun fire (0.55 x 12.5 rounds/s = 6.9 a second).
const MG_HEALTH := 4.2
## Round 12 (owner): glass, the weapon stands and the tower legs take a quarter of that (two rounds).
const MG_HEALTH_LIGHT := MG_HEALTH * 0.25
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
## How it breaks, looks and sounds (juice guide, round 8): "glass", "wood", "palm", "tree", "metal", "prop"
## (small street props) or "" (plain debris, no sound).
var kind := ""
var size_hint := Vector3(2.0, 2.0, 0.3) # rough extent of the visible part, for where the debris comes from
var topple_height := 5.0 # how tall it is when it falls over (where it lands)
var fall_mass := 220.0 # kg of the piece that falls (TOPPLE)
## Round 31 (owner: "trees spawn suddenly on my face as I ram into them"): a big crown swatted by a car went
## flying ahead along the car's path at up to 19 m/s, so it filled the chase camera. Big trees set this: a car
## knocks them over to the side of its path, slowly, the crown falling away from the road ahead.
var swat_aside := false
var stump_radius := 0.0 # > 0: a short broken stump stays where it stood
## Round 32 (owner: Paris trees fell "very separate, like steel rods, not wood"): a tree is not thrown, it falls OVER.
## The trunk splinters just above its stump and swings down about it (gravity speeding it up, pushed a little along
## by the car), the crown slams into the ground or a wall with a crunch of branches, rebounds twice and lies there.
var hinge := false
var crown_radius := 2.4 # where the crown meets the ground first (hinge falls)
var _pivot: Node3D
var _axis := Vector3.RIGHT
var _theta := 0.0
var _omega := 0.0
var _slide := Vector3.ZERO
var _bounces := 0
## Set by weapon_hit(): where the shot or blast came from, and whether it sets wood on fire.
var hit_from := Vector3.INF
var hit_burns := false

var _fall_body: Node3D # the falling piece: a RigidBody3D, or a hinge-fall pivot
var _fall_t := 0.0
var _fall_landed := false
var _fall_fires: Array = [] # flames (FoamFire) and smoke on a burning palm or tree
var _fall_sound: AudioStreamPlayer3D

const FALL_GONE := 4.5 # seconds a fallen trunk or pole lies there before it is cleared away
const FALL_BURN_GONE := 6.5 # a burning one lasts a little longer
static var _char_mat: StandardMaterial3D

static var _debris_mesh: BoxMesh


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)


func _ready() -> void:
	add_to_group(&"breakables") # blasts look these up (Specials.blast)
	set_physics_process(false)


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


## A weapon's hit (owner, round 10): `from` is where the shot or the blast came from (it falls away
## from there), `burns` = an explosive or fire weapon (wood catches fire as it goes down).
func weapon_hit(damage: float, by: Vehicle, from: Vector3, burns: bool) -> void:
	if is_broken:
		return
	hit_from = from
	hit_burns = burns
	projectile_hit(damage, by)


func break_apart(by: Vehicle) -> void:
	if is_broken:
		return
	is_broken = true
	breaking.emit(self)
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


## Owner, round 10 ("the knock-down is funny, make it devastating"): the trunk or pole snaps at the
## base and becomes a real rigid body. A car swats it forward and aside at its own speed, a blast
## throws it away from the blast; it spins, slams down, bounces and slides to rest. Wood hit by an
## explosive or fire weapon burns as it falls and lies there charred. Then it is cleared away.
## The falling piece only touches the world (cars drive through it: no lost momentum).
func _topple(by: Vehicle) -> void:
	if hinge:
		_hinge_topple(by)
		return
	var world := get_parent()
	var by_weapon := hit_from != Vector3.INF
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = fall_mass
	body.gravity_scale = Vehicle.GRAVITY / 9.8
	body.angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.12
	body.physics_material_override = pm
	world.add_child(body)
	body.global_transform = Transform3D(global_basis.orthonormalized(), global_position + Vector3.UP * 0.25)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var thick := clampf(minf(size_hint.x, size_hint.z), 0.3, 1.2)
	box.size = Vector3(maxf(size_hint.x * 0.6, thick), topple_height * 0.92, thick)
	shape.shape = box
	shape.position = Vector3(0, topple_height * 0.5, 0)
	body.add_child(shape)
	visual.reparent(body, true)
	_fall_body = body
	var push := _fall_push(by)
	var dir := push.normalized()
	var speed := push.length()
	var tip := Vector3.UP.cross(dir).normalized() # turning about this drops the top along dir
	if by_weapon:
		body.linear_velocity = dir * 7.5 + Vector3.UP * 6.0
		body.angular_velocity = tip * randf_range(3.0, 4.2) + Vector3.UP * randf_range(-2.0, 2.0)
	else:
		body.linear_velocity = dir * speed * 0.45 + Vector3.UP * (1.5 + speed * 0.06)
		body.angular_velocity = tip * (1.4 + speed * 0.09) + Vector3.UP * randf_range(-1.6, 1.6)
	# Lamps go dark the moment they snap.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m and (m.emission_enabled or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
				mi.set_surface_override_material(i, _charred())
	if kind == "metal":
		for k in 3:
			FxKit.spark(world, global_position + Vector3.UP * (0.4 + k * 0.5), (dir + Vector3.UP).normalized())
	if hit_burns and kind == "palm":
		_set_alight(body)
	if stump_radius > 0.0:
		var stump := MeshKit.cylinder(self, stump_radius, 0.55, Vector3(0, 0.27, 0), _charred() if hit_burns else MeshKit.mat(debris_color * 0.8, 0.9), Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), 7, stump_radius * 0.8)
		stump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fall_t = 0.0
	_fall_landed = false
	set_physics_process(true)


## Which way it falls and how hard (m/s): away from a blast, or along the car's path (aside for big crowns).
func _fall_push(by: Vehicle) -> Vector3:
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var speed := 9.0
	if hit_from != Vector3.INF:
		dir = global_position - hit_from
	elif is_instance_valid(by):
		var cv := by.linear_velocity
		cv.y = 0.0
		var off := global_position - by.global_position
		off.y = 0.0
		if cv.length() > 3.0:
			var fwd := cv.normalized()
			var side := off - fwd * off.dot(fwd) # which side of the car's path it stood on
			var aside := side.normalized() if side.length() > 0.05 else Vector3(-fwd.z, 0, fwd.x)
			dir = fwd * 0.8 + aside * 0.6
			speed = clampf(cv.length(), 8.0, 42.0)
			if swat_aside:
				dir = fwd * 0.3 + aside
				speed = clampf(cv.length() * 0.45, 6.0, 12.0)
		else:
			dir = off
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	return dir * speed


func _hinge_topple(by: Vehicle) -> void:
	var world := get_parent()
	var push := _fall_push(by)
	var dir := push.normalized()
	var hard := hit_from != Vector3.INF
	_axis = Vector3.UP.cross(dir).normalized() # turning about it by +theta drops the top along dir
	_pivot = Node3D.new()
	world.add_child(_pivot)
	_pivot.global_position = global_position + Vector3.UP * 0.45 # it splinters just above the stump
	visual.reparent(_pivot, true)
	_fall_body = _pivot
	_theta = 0.0
	_bounces = 0
	_omega = 1.5 if hard else 0.3 + push.length() * 0.035
	_slide = dir * (2.5 if hard else minf(push.length() * 0.1, 2.2)) # the broken foot skids a little along
	var stump := MeshKit.cylinder(self, stump_radius * 1.15, 0.6, Vector3(0, 0.3, 0), _charred() if hit_burns else MeshKit.mat(debris_color * 0.75, 0.95), Vector3.ZERO, 8, stump_radius)
	stump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 5: # jagged splinters standing up from the break, pale raw wood
		var a := TAU * k / 5.0 + randf_range(-0.3, 0.3)
		var sp := MeshKit.box(self, Vector3(0.09, randf_range(0.25, 0.5), 0.07), Vector3(cos(a) * stump_radius * 0.75, 0.7, sin(a) * stump_radius * 0.75), MeshKit.mat(Color(0.74, 0.62, 0.45), 0.9))
		sp.rotation = Vector3(randf_range(-0.3, 0.3), a, randf_range(-0.3, 0.3))
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hit_burns:
		_set_alight(_pivot)
	_fall_t = 0.0
	_fall_landed = false
	set_physics_process(true)


## The swing about the stump: theta'' = 1.5 g / L sin(theta) (a falling rod), until the crown meets the ground or
## something solid; then two small rebounds and it lies still.
func _hinge_step(delta: float, world: Node) -> void:
	if _omega == 0.0 and _fall_landed:
		return
	if _bounces == 0:
		_omega += 1.5 * 12.0 / topple_height * sin(_theta + 0.06) * delta
	else:
		_omega += 1.5 * 12.0 / topple_height * delta # back down after a rebound
	_theta += _omega * delta
	_slide = _slide.move_toward(Vector3.ZERO, 5.0 * delta)
	_pivot.global_position += _slide * delta
	var rot := Basis(_axis, _theta)
	var tip := _pivot.global_position + rot * Vector3.UP * topple_height
	var hit := _omega > 0.0 and (_theta > 1.62 or tip.y - Specials.ground_below(world, tip + Vector3.UP * 3.0).y < crown_radius)
	if _omega > 0.0 and not hit: # a wall or a building in the way stops it there
		var q := PhysicsRayQueryParameters3D.create(_pivot.global_position + rot * Vector3.UP * 2.0, tip + rot * Vector3.UP * 0.5, 1)
		var w := get_world_3d().direct_space_state.intersect_ray(q)
		hit = not w.is_empty() and not (w.collider as Node).is_in_group(&"ground")
	if hit:
		if _bounces == 0:
			_crown_lands(world, tip)
		_bounces += 1
		_omega = -_omega * (0.2 if _bounces == 1 else 0.12)
		if _bounces >= 3 or absf(_omega) < 0.05:
			_omega = 0.0
			_fall_landed = true
		_theta += _omega * delta
	_pivot.global_basis = Basis(_axis, _theta)


func _crown_lands(world: Node, tip: Vector3) -> void:
	var at := tip - Basis(_axis, _theta) * Vector3.UP * crown_radius * 0.6
	var g := Specials.ground_below(world, at + Vector3.UP * 3.0)
	var heavy := clampf(fall_mass / 250.0, 0.6, 1.6)
	GameFeel.play("land_thud", at, world, 0.0, 0.62, true)
	GameFeel.play("wood_break", at, world, -6.0, 0.7, true) # branches cracking under it
	FxKit.leaves(world, at + Vector3.UP * 1.0, 1.3)
	FxKit.dust_ring(world, g, 1.1 * heavy)
	FxKit.puff(world, g + Vector3.UP * 0.6, 0.9 * heavy)
	GameFeel.shake(at, 0.25 * heavy, 45.0)
	if hit_burns:
		FxKit.spark(world, g + Vector3.UP * 0.3, Vector3.UP) # embers

static func _charred() -> StandardMaterial3D:
	if _char_mat == null:
		_char_mat = StandardMaterial3D.new()
		_char_mat.albedo_color = Color(0.035, 0.03, 0.028)
		_char_mat.roughness = 1.0
	return _char_mat


## Wood on fire: flames along the trunk and in the crown, the whole thing scorched black.
func _set_alight(body: Node3D) -> void:
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.02, 0.015, 0.01, 0.72)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.roughness = 1.0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = soot
	# Round 12 (perf): two flames and a thinner smoke (three emitters cost too much overdraw on HIGH).
	var fire := FoamFire.new() # the game's fire along the trunk and in the crown (round 18); it falls with it
	fire.position = Vector3(0, topple_height * 0.6, 0)
	fire.box = Vector3(0.35, topple_height * 0.38, 0.35)
	fire.size = 1.0
	fire.rate = 34.0
	fire.life = 0.7
	fire.rise = 2.0
	fire.rise_in = 6.0
	body.add_child(fire)
	fire.on = true
	_fall_fires.append(fire)
	var smoke := FxKit.smoke(1.3, 6)
	smoke.position = Vector3(0, topple_height * 0.8, 0)
	body.add_child(smoke)
	smoke.emitting = true
	_fall_fires.append(smoke)
	_fall_sound = GameFeel.loop("fire_loop", body, -9.0, 7.0)
	if _fall_sound:
		_fall_sound.play()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_fall_body):
		set_physics_process(false)
		return
	_fall_t += delta
	var world := get_parent()
	if _pivot:
		_hinge_step(delta, world)
	elif not _fall_landed and _fall_t > 0.12:
		var top := _fall_body.to_global(Vector3(0, topple_height, 0))
		var g := Specials.ground_below(world, top + Vector3.UP * 2.0)
		if top.y - g.y < 0.9 or _fall_t > 2.5:
			_fall_landed = true
			var heavy := clampf(fall_mass / 250.0, 0.6, 1.6)
			GameFeel.play("metal_fall" if kind == "metal" else "land_thud", top, world, -2.0, 0.85 if kind == "metal" else 0.7, true)
			FxKit.dust_ring(world, g, 1.3 * heavy)
			FxKit.puff(world, g + Vector3.UP * 0.4, 0.8 * heavy)
			GameFeel.shake(top, 0.3 * heavy, 45.0)
			if kind == "metal":
				FxKit.spark(world, g + Vector3.UP * 0.2, Vector3.UP)
			elif hit_burns:
				FxKit.spark(world, g + Vector3.UP * 0.2, Vector3.UP) # a burst of embers where the crown lands
	var gone := FALL_BURN_GONE if hit_burns and kind in ["palm", "tree"] else FALL_GONE
	if _fall_t > gone - 1.2:
		for f in _fall_fires:
			if f is FoamFire:
				(f as FoamFire).on = false
			else:
				(f as CPUParticles3D).emitting = false
		if is_instance_valid(_fall_sound):
			_fall_sound.volume_db -= 30.0 * delta
	if _fall_t > gone:
		# Cleared away: it sinks out of sight in a breath of dust (ash if it burned), never pops.
		set_physics_process(false)
		var body := _fall_body
		_fall_body = null
		_pivot = null
		if body is RigidBody3D:
			(body as RigidBody3D).freeze = true
			(body as RigidBody3D).collision_mask = 0
		FxKit.puff(world, body.to_global(Vector3(0, topple_height * 0.5, 0)), 0.9)
		var tw := body.create_tween()
		tw.tween_property(body, "global_position:y", body.global_position.y - 1.6, 0.9).set_ease(Tween.EASE_IN)
		tw.tween_callback(body.queue_free)


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
		"tree": # the trunk splits: a crack, pale splinters off the break, leaves shaken out of the crown
			var foot := global_position + Vector3.UP * 0.7
			GameFeel.play("palm_break", foot, world, 0.0, 0.85, true)
			GameFeel.play("wood_break", foot, world, -3.0, 0.8, true)
			FxKit.shatter(world, foot, Vector3(0.35, 0.3, 0.35), dir, speed * 0.6, Color(0.74, 0.62, 0.45), false)
			FxKit.leaves(world, global_position + global_basis * Vector3(0, topple_height * 0.75, 0), 1.0)
			GameFeel.shake(foot, 0.2, 35.0)
			if you:
				GameFeel.hitstop(get_tree(), 0.04, 0.1)
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
