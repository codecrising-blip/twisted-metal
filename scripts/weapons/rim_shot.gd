class_name RimShot
extends Node3D
## Axel's secondary, Rim Shot (design 01, Axel; round 21): one of his spiked tyres rolls out along the
## ground at "speed" m/s and bounces off walls up to "bounces" times within "life" s. Every car it rolls
## through takes "damage" and a shove, and it rolls on (it stops after "max_hits" cars). Palms, lights and
## stands it runs into are knocked down. Counter: jump it, or watch its sparks on the ground.

const RADIUS := 0.75 # the tyre's radius: it rolls this high
const HIT_REACH := 2.4 # a car's aim point this close to the tyre is hit

var owner_car: Vehicle
var def := {}

var _dir := Vector3.FORWARD
var _t := 0.0
var _bounces := 0
var _hits := 0
var _hit := {}
var _wheel: Node3D
var _roll: AudioStreamPlayer3D
var _spark_t := 0.0
var _done := false


static func start(v: Vehicle, d: Dictionary) -> RimShot:
	var r := RimShot.new()
	r.owner_car = v
	r.def = d
	v.get_parent().add_child(r)
	var size: Vector3 = v.stats.get("size", Vector3(3.8, 2.8, 2.8))
	r._dir = v.flat_forward()
	var t := v.target
	if is_instance_valid(t) and not t.is_dead:
		var to := t.global_position - v.global_position
		to.y = 0.0
		if to.length() > 1.0 and r._dir.angle_to(to.normalized()) < deg_to_rad(20.0):
			r._dir = to.normalized() # rolled at a car that is nearly dead ahead
	var at := v.global_position + v.flat_forward() * (size.z * 0.5 + 1.2)
	r.global_position = Specials.ground_below(v.get_parent(), at + Vector3.UP * 2.0) + Vector3.UP * RADIUS
	GameFeel.play("ram_impact", r.global_position, v.get_parent(), -4.0 + float(d.get("sound_db", 0.0)), 0.7, true)
	GameFeel.muzzle(v.get_parent(), r.global_position, Color(1.0, 0.7, 0.35), 1.2)
	FxKit.dust_ring(v.get_parent(), r.global_position - Vector3.UP * RADIUS, 0.6)
	if v.is_player and GameFeel.camera:
		GameFeel.camera.add_shake(0.15)
	return r


func _ready() -> void:
	_wheel = Node3D.new()
	add_child(_wheel)
	_build()
	Streak.attach(self, Color(1.0, 0.65, 0.3), 0.15, 0.5)
	_roll = GameFeel.loop("skid_loop", self, -8.0, 14.0)
	if _roll:
		_roll.pitch_scale = 0.7
		_roll.play()


## A fat black tyre on a bronze rim, rows of steel spikes round its tread.
func _build() -> void:
	var rubber := MeshKit.mat(Color(0.05, 0.045, 0.045), 0.9, 0.0)
	var rim := MeshKit.mat(Color(0.38, 0.27, 0.2), 0.4, 0.8)
	var steel := MeshKit.mat(Color(0.62, 0.62, 0.6), 0.35, 0.9)
	MeshKit.cylinder(_wheel, RADIUS, 0.6, Vector3.ZERO, rubber, Vector3(0, 0, 90), 20)
	MeshKit.cylinder(_wheel, RADIUS * 0.55, 0.64, Vector3.ZERO, rim, Vector3(0, 0, 90), 14)
	MeshKit.cylinder(_wheel, RADIUS * 0.18, 0.72, Vector3.ZERO, steel, Vector3(0, 0, 90), 8)
	for k in 12:
		var a := TAU * k / 12.0
		for side: float in [-0.18, 0.18]:
			var p := Vector3(side, cos(a) * RADIUS, sin(a) * RADIUS)
			MeshKit.cylinder(_wheel, 0.06, 0.26, p + Vector3(0, cos(a), sin(a)) * 0.1, steel, Vector3(rad_to_deg(a) + 90.0, 0, 0), 4, 0.0)
	for mi in _wheel.find_children("*", "MeshInstance3D", false, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t > float(def.get("life", 4.0)):
		_end(false)
		return
	var speed := float(def.get("speed", 45.0))
	var from := global_position
	var to := from + _dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + _dir * RADIUS, 1 | Breakable.COVER_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is Node and (c as Node).has_meta("cover_of"):
			c = (c as Node).get_meta("cover_of")
		if c is Breakable:
			(c as Breakable).weapon_hit(float(def.get("damage", 20.0)) * WeaponData.DAMAGE_SCALE, owner_car, from - _dir * 3.0, false)
		elif (hit.normal as Vector3).y < 0.6: # a wall: bounce off it, or break up on the last one
			if _bounces >= int(def.get("bounces", 3)):
				_end(true)
				return
			_bounces += 1
			var n := Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
			_dir = (_dir - 2.0 * _dir.dot(n) * n).normalized()
			GameFeel.play("ricochet", hit.position, get_parent(), -2.0, 0.8)
			for k in 4:
				FxKit.spark(get_parent(), hit.position, (n + Vector3(randf_range(-0.6, 0.6), 0.7, randf_range(-0.6, 0.6))).normalized())
			GameFeel.shake(hit.position, 0.15)
			return
	var g := Specials.ground_below(get_parent(), to + Vector3.UP * 2.0)
	to.y = g.y + RADIUS
	global_position = to
	# Roll it: turned to face its way, spun about its axle by the distance covered.
	_wheel.global_basis = Basis.looking_at(_dir, Vector3.UP)
	_wheel.rotate_object_local(Vector3.RIGHT, -_t * speed / RADIUS)
	_spark_t -= delta
	if _spark_t <= 0.0: # its spikes strike sparks off the ground
		_spark_t = 0.05
		FxKit.spark(get_parent(), g + Vector3.UP * 0.05, (Vector3.UP - _dir * 0.6).normalized())
	_strike()


func _strike() -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or v.is_dead or v == owner_car or _hit.has(v):
			continue
		if v.aim_point().distance_to(global_position) > HIT_REACH + float(v.stats.get("size", Vector3(2, 2, 5)).x) * 0.25:
			continue
		_hit[v] = true
		_hits += 1
		var dmg := float(def.get("damage", 20.0)) * WeaponData.DAMAGE_SCALE
		v.take_damage(dmg, owner_car)
		v.push(_dir * float(def.get("push", 6.0)) * v.knockback + Vector3.UP * 2.0)
		v.hit_react(_dir, dmg)
		Projectile.hit_feel(v, def, _dir)
		var at := v.aim_point().lerp(global_position, 0.5)
		GameFeel.play("ram_impact", at, get_parent(), -2.0, 1.2, true)
		GameFeel.flash(get_parent(), at, 1.4, Color(1.0, 0.8, 0.5), 0.08)
		for k in 4:
			FxKit.spark(get_parent(), at, (-_dir + Vector3(randf_range(-0.7, 0.7), 0.9, randf_range(-0.7, 0.7))).normalized())
		if v.is_player or (is_instance_valid(owner_car) and owner_car.is_player):
			GameFeel.hitstop(get_tree(), 0.04)
		if _hits >= int(def.get("max_hits", 2)):
			_end(true)
			return


func _end(loud: bool) -> void:
	_done = true
	var world := get_parent()
	if loud:
		GameFeel.play("ram_impact", global_position, world, -6.0, 0.9, true)
		FxKit.shatter(world, global_position, Vector3.ONE * 0.4, Vector3.UP, 5.0, Color(0.1, 0.09, 0.09), false)
	FxKit.puff(world, global_position, 0.5)
	if is_instance_valid(_roll):
		_roll.stop()
	queue_free()
