class_name Sinner
extends CharacterBody3D
## Brimstone's Sinner Bomber (round 28, design 01 ch 10, stronger than Black's): a pale, hooded sinner with
## dynamite strapped to his back. Round 30 (owner: a man can't run down cars this fast): he is HURLED out of
## the bed on a flat, fast arc (throw_speed, out to "range" m, bending a little toward the lock). Thrown into
## a car he clings to it; into a wall he blows at once; at the end of his range he lands, rolls and runs on
## at run_mult of his old sprint, blowing after run_time s. Clinging he blows after "fuse" s: damage and a
## small throw. The driver
## shakes him off with a jump, a wall hit over shake_wall m/s or a 150-degree handbrake slide: he drops
## behind and blows for shake_damage. He can be shot down (hp: ~9 rounds) or burnt by Thumper's flame, and
## pops anyway when his run time is up (pop_damage in pop_radius). Projectiles hit him on layer 64.

enum State { FLY, ROLL, RUN, CLING, DROP }

const LAYER := 64
const GRAVITY := 30.0
const TURN := 3.2 # rad/s: how fast he swings round toward his car (round 29: smooth arcs)
const ACCEL := 45.0 # m/s²: building up to his sprint
const FLY_GRAVITY := 7.0 # round 30: a flat, hurled arc (he still drops at the end of it)
const FLY_TURN := 1.2 # rad/s he bends toward the lock in the air
const ROLL_TIME := 0.5

var owner_car: Vehicle
var lock: Vehicle
var def: Dictionary
var state := State.FLY
var victim: Vehicle
var _hp := 5.0
var _t := 0.0
var _fuse := 0.0
var _offset := Vector3.ZERO
var _model: Node3D
var _anim: AnimationPlayer
var _fuse_snd: AudioStreamPlayer3D
var _spark := 0.0
var _scan := 0.0
var _done := false
var _victim_floor := true
var _from := Vector3.ZERO # where he was thrown from (the range counts from here)
var _punched := false # round 31 (owner): one big punch into the windshield before he blows


static func start(v: Vehicle, d: Dictionary) -> Sinner:
	var s := Sinner.new()
	s.owner_car = v
	s.def = d
	s.lock = v.target if is_instance_valid(v.target) and not v.target.is_dead else null
	v.get_parent().add_child(s)
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.5))
	var bed: Vector3 = v.model.get_meta("sinner", Vector3(0, size.y * 0.75, size.z * 0.25))
	s.global_position = v.model.to_global(bed)
	var fwd := v.flat_forward()
	if is_instance_valid(s.lock): # thrown at the lock if it is ahead (within 40 degrees)
		var to := s.lock.global_position - v.global_position
		to.y = 0.0
		if to.length() > 1.0 and absf(fwd.signed_angle_to(to.normalized(), Vector3.UP)) < deg_to_rad(40.0):
			fwd = to.normalized()
	var own := Vector3(v.linear_velocity.x, 0.0, v.linear_velocity.z)
	s.velocity = fwd * float(d.get("throw_speed", 46.0)) + own.project(fwd).limit_length(20.0) * 0.5 + Vector3.UP * 3.2
	s._from = s.global_position
	s.look_at(s.global_position + fwd, Vector3.UP)
	GameFeel.play("pedestrian_scream", s.global_position, v.get_parent(), float(d.get("sound_db", 0.0)) - 2.0, randf_range(1.05, 1.2))
	GameFeel.play("launch_napalm", s.global_position, v.get_parent(), -10.0, 1.2, true)
	var plate := v.model.find_child("bed_plate", true, false) as Node3D
	if plate: # round 29 (owner's sheet): the well's floor slams up and flings him out
		var tw := plate.create_tween()
		tw.tween_property(plate, "position:y", 0.42, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(plate, "position:y", 0.0, 0.35).set_delay(0.12).set_ease(Tween.EASE_IN_OUT)
		GameFeel.play("crash", plate.global_position, v, -10.0, 1.6)
	return s


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 # the world: he slides along walls
	add_to_group(&"sinners")
	_hp = float(def.get("hp", 5.0))
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	floor_snap_length = 0.6
	_model = _body()
	add_child(_model)
	_anim = _model.get_meta("anim")
	_anim.play("prone" if _anim.has_animation("prone") else _run_clip())
	_anim.speed_scale = 1.2 # round 29 (owner): a calm, driven sprint, not arms flailing twelve times a second
	_fuse_snd = GameFeel.loop("taser_loop", self, -10.0, 8.0)
	if _fuse_snd:
		_fuse_snd.pitch_scale = 2.6 # a hissing, spitting fuse
		_fuse_snd.play()


## The burnt-driver dummy (driver_m.glb) made a sinner: pale skin, a burlap hood, a bundle of dynamite on
## his back with a lit fuse, a loop of chain round his waist.
func _body() -> Node3D:
	var scene: PackedScene = load("res://assets/models/driver_m.glb")
	var m := scene.instantiate() as Node3D
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.74, 0.68, 0.6)
	skin.roughness = 0.75
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = skin
	var anim: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	for a in anim.get_animation_list():
		anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	m.set_meta("anim", anim)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var burlap := MatKit.paint(Color(0.42, 0.33, 0.22), 0.4, 0.0, 0.6, 0.6, 0.1, 81)
	var red := MatKit.paint(Color(0.55, 0.08, 0.05), 0.4, 0.0, 0.4, 0.6, 0.3, 82)
	var iron := MatKit.steel(Color(0.2, 0.2, 0.2), 0.6)
	var head := BoneAttachment3D.new()
	head.bone_name = "head"
	sk.add_child(head)
	var mb := MeshBuilder.new()
	mb.sphere(burlap, 0.17, Transform3D(Basis().scaled(Vector3(1.0, 1.25, 1.05)), Vector3(0, 0.1, 0)), 10, 7)
	mb.cylinder(burlap, 0.12, 0.12, Transform3D(Basis(), Vector3(0, -0.06, 0)), 8, 0.14) # the sack tied at the neck
	mb.commit(head, false)
	var chest := BoneAttachment3D.new()
	chest.bone_name = "chest"
	sk.add_child(chest)
	var back := MeshBuilder.new()
	for k in 5:
		back.cylinder(red, 0.045, 0.42, Transform3D(Basis(), Vector3(-0.1 + k * 0.05, 0.0, 0.17)), 8)
	back.box(iron, Vector3(0.3, 0.04, 0.12), Transform3D(Basis(), Vector3(0, 0.12, 0.16)), 0.0)
	back.box(iron, Vector3(0.3, 0.04, 0.12), Transform3D(Basis(), Vector3(0, -0.12, 0.16)), 0.0)
	back.commit(chest, false)
	var hips := BoneAttachment3D.new()
	hips.bone_name = "hips"
	sk.add_child(hips)
	var chain := MeshBuilder.new()
	chain.torus(iron, 0.2, 0.025, Transform3D(Basis(), Vector3(0, 0.05, 0)), 14, 5)
	chain.commit(hips, false)
	m.set_meta("fuse", chest)
	m.set_meta("skel", sk)
	return m


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_spark -= delta
	if _spark <= 0.0: # the lit fuse spits sparks (it shows him in the dark)
		_spark = 0.12
		var fuse: Node3D = _model.get_meta("fuse")
		FxKit.spark(get_parent(), fuse.global_position + fuse.global_basis.z * 0.2 + Vector3.UP * 0.25, Vector3.UP)
	match state:
		State.FLY:
			_fly(delta)
		State.ROLL:
			_roll(delta)
		State.RUN:
			_run(delta)
		State.CLING:
			_cling(delta)
		State.DROP:
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if _t > 0.6 or (is_on_floor() and _t > 0.25):
				_blow(float(def.get("shake_damage", 10.0)), 4.0, null)


## Hurled: a flat arc bending toward the lock. A car he meets: he clings. A wall: he blows at once. The end
## of his range (or the ground): he rolls.
func _fly(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if is_instance_valid(lock) and not lock.is_dead and flat.length() > 1.0:
		var to := lock.global_position - global_position
		to.y = 0.0
		var ang := flat.normalized().signed_angle_to(to.normalized(), Vector3.UP)
		flat = flat.rotated(Vector3.UP, clampf(ang, -FLY_TURN * delta, FLY_TURN * delta))
	velocity = Vector3(flat.x, velocity.y - FLY_GRAVITY * delta, flat.z)
	if flat.length() > 1.0:
		global_basis = Basis.looking_at(flat, Vector3.UP)
	var before := global_position
	move_and_slide()
	if _touch_car() or _sweep_car(before, global_position):
		return
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.6: # a wall
			_blow(float(def.get("wall_damage", 25.0)), float(def.get("wall_radius", 5.0)), null)
			return
	var gone := Vector2(global_position.x - _from.x, global_position.z - _from.z).length()
	if gone >= float(def.get("range", 45.0)) or (is_on_floor() and _t > 0.2):
		state = State.ROLL
		_t = 0.0
		GameFeel.play("land_thud", global_position, get_parent(), -6.0, 1.3)
		FxKit.puff(get_parent(), global_position + Vector3.UP * 0.3, 0.6)


## Landed: he tumbles along the ground, losing speed, then gets up running.
func _roll(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(Vector3.ZERO, 40.0 * delta)
	velocity = Vector3(flat.x, velocity.y - GRAVITY * delta, flat.z)
	move_and_slide()
	_model.rotation.x = -TAU * 1.5 * clampf(_t / ROLL_TIME, 0.0, 1.0)
	if _touch_car():
		_model.rotation.x = 0.0
		return
	if _t >= ROLL_TIME:
		_model.rotation.x = 0.0
		state = State.RUN
		_t = 0.0
		_anim.play(_run_clip(), 0.15)
		_anim.speed_scale = 1.2


## A car (not his own) where he is: he grabs it. True if he did.
func _touch_car() -> bool:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead:
			continue
		var local := o.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.9)
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		if absf(local.x) < size.x * 0.5 + 0.6 and absf(local.z) < size.z * 0.5 + 0.6 and local.y > -0.5 and local.y < size.y + 1.0:
			_grab(o)
			return true
	return false


## Round 31 (owner: "it flies over the cars close to me; it must connect as long as he is in its horizontal
## path"): the step he just flew, seen from above, against every car's box (0.7 m wider). Height only has to be
## somewhere between under the car and 4 m over its roof: a car he passes over is a car he lands on.
func _sweep_car(a: Vector3, b: Vector3) -> bool:
	var best: Vehicle = null
	var best_t := 2.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead:
			continue
		var inv := o.global_transform.affine_inverse()
		var la := inv * a
		var lb := inv * b
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		var half := Vector2(size.x * 0.5 + 0.7, size.z * 0.5 + 0.7)
		var p0 := Vector2(la.x, la.z)
		var d := Vector2(lb.x, lb.z) - p0
		var t0 := 0.0
		var t1 := 1.0
		var miss := false
		for k in 2:
			var lo := -half[k]
			var hi := half[k]
			if absf(d[k]) < 1e-5:
				if p0[k] < lo or p0[k] > hi:
					miss = true
					break
			else:
				var ta := (lo - p0[k]) / d[k]
				var tb := (hi - p0[k]) / d[k]
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
				if t0 > t1:
					miss = true
					break
		if miss:
			continue
		var ly := lerpf(la.y, lb.y, t0)
		if ly > -1.5 and ly < size.y + 4.0 and t0 < best_t:
			best_t = t0
			best = o
	if best:
		global_position = a.lerp(b, best_t)
		_grab(best)
		return true
	return false


func _run(delta: float) -> void:
	if _t > float(def.get("run_time", 2.0)):
		_blow(float(def.get("pop_damage", 12.0)), float(def.get("pop_radius", 3.0)), null)
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.4
		if not is_instance_valid(lock) or lock.is_dead or lock.is_hidden():
			lock = _nearest()
	var speed := float(def.get("run_speed", 26.0)) * Roster.SPEED_SCALE * 0.85 * float(def.get("run_mult", 0.6))
	var dir := -global_basis.z
	if is_instance_valid(lock):
		var to := lock.global_position - global_position
		to.y = 0.0
		if to.length() > 0.5:
			dir = to.normalized()
	# Round 29 (owner: "too chaotic"): he swings round in a smooth arc (TURN rad/s) and builds up speed,
	# instead of snapping to the target every frame; the body turns with his path, eased.
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var cur := flat.normalized() if flat.length() > 0.5 else dir
	var ang := cur.signed_angle_to(dir, Vector3.UP)
	cur = cur.rotated(Vector3.UP, clampf(ang, -TURN * delta, TURN * delta))
	var spd := move_toward(flat.length(), speed, ACCEL * delta)
	flat = cur * spd
	velocity = Vector3(flat.x, velocity.y - GRAVITY * delta, flat.z)
	move_and_slide()
	if flat.length() > 1.0:
		var face := Basis.looking_at(flat, Vector3.UP)
		global_basis = global_basis.slerp(face, minf(1.0, delta * 8.0)).orthonormalized()
	_touch_car()


## The plain sprint (round 29) when the dummy has it, else the old burning run.
func _run_clip() -> String:
	return "sprint" if _anim.has_animation("sprint") else "run_burn"


func _nearest() -> Vehicle:
	var best: Vehicle = null
	var best_d := 70.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == owner_car or o.is_dead or o.is_hidden():
			continue
		var d := o.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## On the car: on its hood (or its roof when it is low), facing the driver, holding on.
func _grab(o: Vehicle) -> void:
	state = State.CLING
	victim = o
	_t = 0.0
	_fuse = 0.0
	_punched = false
	collision_mask = 0
	var hood: Vector2 = o.stats.get("hood", Vector2(1.2, -1.4))
	_offset = Vector3(0.0, hood.x + 0.05, hood.y)
	_anim.play("kneel", 0.15)
	_anim.speed_scale = 1.6
	if o.has_signal("wall_slammed"):
		o.wall_slammed.connect(_on_wall)
	GameFeel.play("land_thud", global_position, get_parent(), -4.0, 1.2)
	GameFeel.play("pedestrian_scream", global_position, get_parent(), -2.0, 0.95)
	if o.is_player:
		o.notice.emit(o, "SINNER ON YOU - JUMP, SLAM A WALL OR SPIN TO SHAKE HIM")


func _cling(delta: float) -> void:
	var o := victim
	if not is_instance_valid(o) or o.is_dead:
		_shake_off()
		return
	global_transform = o.global_transform * Transform3D(Basis(Vector3.UP, PI), _offset)
	_fuse += delta
	# Shaken off: a jump (wheels off and going up), a big slide (a handbrake U-turn).
	var up := o.linear_velocity.y
	if not o.is_on_floor() and up > 4.0 and _t > 0.15:
		_shake_off()
		return
	if o.slide_degrees() > 150.0:
		_shake_off()
		return
	_punch_step(o)
	if _fuse >= float(def.get("fuse", 2.0)):
		var dmg := float(def.get("damage", 40.0)) * WeaponData.DAMAGE_SCALE
		o.take_damage(dmg, owner_car)
		o.hit_react(Vector3.UP, dmg)
		o.blast_knock(Vector3.UP * 5.0 + o.global_basis.x * randf_range(-3.0, 3.0), 0.15, true)
		if o.is_player and GameFeel.camera:
			GameFeel.camera.add_shake(float(def.get("shake", 0.5)))
		_blow(0.0, 0.0, o)


## Round 31 (owner): before he blows he winds up and PUNCHES the windshield: the body leans back and pulls
## the right fist back (punch_wind s), then snaps forward, arm straight out; the punch lands punch_at s into the
## fuse: punch_damage, glass, sparks, the car jolts and its nose is driven down, a shake for its driver.
func _punch_step(o: Vehicle) -> void:
	var land := float(def.get("punch_at", 1.6))
	var wind := float(def.get("punch_wind", 0.3))
	var k := 0.0 # 0 kneeling, -1 wound back, 1 thrust
	if _fuse < land:
		k = -sin(clampf((_fuse - (land - wind)) / wind, 0.0, 1.0) * PI * 0.5)
	else:
		k = lerpf(-1.0, 1.0, clampf((_fuse - land) / 0.06, 0.0, 1.0)) # the snap: 0.06 s
	if _fuse > land - wind:
		if _anim.is_playing():
			_anim.pause()
		# wound: he rears up off the hood and leans back; the punch: he slams forward and down onto the glass
		_model.rotation.x = 0.55 * maxf(0.0, -k) - 0.7 * maxf(0.0, k)
		_model.position = Vector3(0.0, 0.45 * maxf(0.0, -k) + 0.1 * maxf(0.0, k), -0.6 * maxf(0.0, k) + 0.2 * maxf(0.0, -k))
		_arm(k)
	if _punched or _fuse < land:
		return
	_punched = true
	var world := get_parent()
	var fist := global_position + Vector3.UP * 1.1 - global_basis.z * 0.9
	var dmg := float(def.get("punch_damage", 15.0)) * WeaponData.DAMAGE_SCALE
	o.take_damage(dmg, owner_car)
	o.hit_react(o.global_basis.z, dmg * 2.0)
	o.push(-o.flat_forward() * float(def.get("punch_slow", 5.0)) + Vector3.DOWN * 3.0)
	o.angular_velocity += o.global_basis.x * -1.6 # the nose is driven down
	FxKit.crash_burst(world, fist, o.global_basis.y, 0.7)
	for i in 3:
		FxKit.spark(world, fist + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.2), randf_range(-0.3, 0.3)), o.global_basis.z)
	GameFeel.play("ram_impact", fist, world, 2.0, 1.25, true)
	GameFeel.play("glass_shatter_1", fist, world, -2.0, 1.1, true)
	if o.is_player and GameFeel.camera:
		GameFeel.camera.add_shake(0.55)
	if o.is_player or (is_instance_valid(owner_car) and owner_car.is_player):
		GameFeel.hitstop(get_tree(), 0.07, 0.05)


## The right arm: wound back (k = -1, elbow behind him, fist at the shoulder) .. thrust straight at the
## windshield (k = 1). Bones are aimed in skeleton space (their +Y runs along the bone) from the kneel pose.
func _arm(k: float) -> void:
	var sk: Skeleton3D = _model.get_meta("skel")
	var ua := sk.find_bone("upper_arm.R")
	var fa := sk.find_bone("forearm.R")
	if ua < 0 or fa < 0:
		return
	var fwd := Vector3(-0.08, 0.22, -1.0).normalized() # model space: he faces -Z
	var back_u := Vector3(0.35, -0.45, 0.85).normalized()
	var back_f := Vector3(-0.1, 0.75, -0.6).normalized()
	var u_dir := back_u.slerp(fwd, (k + 1.0) * 0.5)
	var f_dir := back_f.slerp(fwd, (k + 1.0) * 0.5)
	for pair in [[ua, u_dir], [fa, f_dir]]:
		var b: int = pair[0]
		var want: Vector3 = pair[1]
		var g := sk.get_bone_global_pose(b)
		var cur := g.basis.y.normalized()
		if cur.cross(want).length() < 1e-4 and cur.dot(want) > 0.0:
			continue
		var turned := Basis(Quaternion(cur, want)) * g.basis
		var parent := sk.get_bone_parent(b)
		var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
		sk.set_bone_pose_rotation(b, (pg.basis.inverse() * turned).get_rotation_quaternion())


func _on_wall(car: Vehicle, impact: float) -> void:
	if state == State.CLING and car == victim and impact > float(def.get("shake_wall", 15.0)):
		_shake_off()


func _shake_off() -> void:
	if state != State.CLING:
		return
	state = State.DROP
	_t = 0.0
	var o := victim
	if is_instance_valid(o):
		if o.wall_slammed.is_connected(_on_wall):
			o.wall_slammed.disconnect(_on_wall)
		velocity = o.linear_velocity * 0.4 - o.flat_forward() * 6.0 + Vector3.UP * 3.0
		if o.is_player:
			o.notice.emit(o, "SHOOK HIM OFF")
	victim = null
	collision_mask = 1
	_model.rotation.x = 0.0
	_model.position = Vector3.ZERO
	_anim.play(_run_clip(), 0.2)
	_anim.speed_scale = 1.2


## Shot or burnt while he runs.
func projectile_hit(damage: float, _shooter: Vehicle) -> void:
	if _done or state == State.CLING:
		return
	_hp -= damage
	if _hp <= 0.0:
		_blow(float(def.get("pop_damage", 12.0)), float(def.get("pop_radius", 3.0)), null)


func _blow(damage: float, radius: float, on_car: Vehicle) -> void:
	if _done:
		return
	_done = true
	var world := get_parent()
	var at := global_position + Vector3.UP * 0.8
	if is_instance_valid(victim) and victim.wall_slammed.is_connected(_on_wall):
		victim.wall_slammed.disconnect(_on_wall)
	FxKit.explosion(world, at, 1.6 if on_car else 1.0, Color(1.0, 0.5, 0.15))
	GameFeel.flash(world, at, 2.5, Color(1.0, 0.75, 0.4), 0.1)
	GameFeel.scorch(world, global_position + Vector3.UP * 0.2, 2.0)
	if damage > 0.0:
		Specials.blast(world, at, radius, damage, owner_car)
	if on_car and (on_car.is_player or (is_instance_valid(owner_car) and owner_car.is_player)):
		GameFeel.hitstop(get_tree(), 0.06, 0.05)
	queue_free()
