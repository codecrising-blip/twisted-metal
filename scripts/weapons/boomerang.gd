class_name Boomerang
extends Node3D
## Roadkill's Boomerang Blast (design 01, Roadkill): a spinning blade of welded scrap thrown ahead with
## light homing, out to "range" metres or until it cuts a car, then it swings back toward where Roadkill
## is NOW. Going out it deals "damage", coming back "return_damage" (twice, as in the series); one car can
## take both. Walls break it either way; palms, street lights and stands are cut through. If Roadkill
## drives through his returning blade he catches it: the special charge it cost comes back at once (round 21).

const HEIGHT := 1.2 # flies this high over the ground
const HIT_RADIUS := 5.5 # a car's aim point this close is cut (round 21, owner: 2.5x the first 2.2)
const CATCH_RADIUS := 3.0
const BACK_TURN := 7.0 # rad/s it bends toward Roadkill on the way back

var owner_car: Vehicle
var def := {}
var lock: Vehicle

var _dir := Vector3.FORWARD
var _back := false
var _travel := 0.0
var _t := 0.0
var _cut := {} # car -> true, per leg (out / back)
var _blade: Node3D
var _whirr: AudioStreamPlayer3D
var _done := false
var refund := 0 # special charges given back when Roadkill catches it (it was paid for as a secondary)
var end_reason := "" # "caught", "wall <name>", "time" (tests read it)


static func start(v: Vehicle, d: Dictionary) -> Boomerang:
	var b := Boomerang.new()
	b.owner_car = v
	b.def = d
	b.lock = v.target if is_instance_valid(v.target) and not v.target.is_dead else null
	v.get_parent().add_child(b)
	var size: Vector3 = v.stats.get("size", Vector3(2.2, 1.8, 5.0))
	b._dir = v.flat_forward()
	if b.lock:
		var to := b.lock.global_position - v.global_position
		to.y = 0.0
		if to.length() > 1.0 and b._dir.angle_to(to.normalized()) < deg_to_rad(50.0):
			b._dir = b._dir.slerp(to.normalized(), 0.6).normalized()
	b.global_position = v.global_position + v.flat_forward() * (size.z * 0.5 + 0.8) + Vector3.UP * HEIGHT
	GameFeel.play("special_roadkill", b.global_position, v.get_parent(), -2.0 + float(d.get("sound_db", 0.0)), 1.0, true)
	GameFeel.muzzle(v.get_parent(), b.global_position, Color(1.0, 0.6, 0.25), 1.2)
	if v.is_player and GameFeel.camera:
		GameFeel.camera.add_shake(0.12)
	return b


func _ready() -> void:
	_blade = Node3D.new()
	add_child(_blade)
	_build_blade()
	Streak.attach(self, Color(1.0, 0.62, 0.25), 0.22, 0.7)
	_whirr = GameFeel.loop("skid_loop", self, -10.0, 14.0)
	if _whirr:
		_whirr.pitch_scale = 2.4 # a saw's whine, not rubber
		_whirr.play()


## A rusty saw blade cut from scrap: a thick disc, eight hooked teeth, weld beads and a bolted hub,
## its edge glowing hot from the spin.
func _build_blade() -> void:
	var steel := MeshKit.mat(Color(0.3, 0.27, 0.24), 0.45, 0.8)
	var rust := MeshKit.mat(Color(0.32, 0.15, 0.07), 0.85, 0.3)
	var hot := MeshKit.emissive(Color(1.0, 0.45, 0.12), 2.5)
	MeshKit.cylinder(_blade, 0.5, 0.06, Vector3.ZERO, steel, Vector3.ZERO, 16)
	MeshKit.cylinder(_blade, 0.18, 0.14, Vector3.ZERO, rust, Vector3.ZERO, 10)
	MeshKit.cylinder(_blade, 0.07, 0.18, Vector3.ZERO, steel, Vector3.ZERO, 6)
	for k in 8:
		var a := TAU * k / 8.0
		var r := Vector3(cos(a), 0.0, sin(a))
		MeshKit.box(_blade, Vector3(0.22, 0.05, 0.1), r * 0.55, hot, Vector3(0, -rad_to_deg(a) + 35.0, 0)) # hooked teeth
		MeshKit.box(_blade, Vector3(0.05, 0.075, 0.24), r * 0.33, rust, Vector3(0, -rad_to_deg(a), 0)) # weld beads
	for mi in _blade.find_children("*", "MeshInstance3D", false, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_blade.rotate_y(delta * 32.0)
	_blade.rotation.x = 0.25 * sin(_t * 9.0) # a wobble as it cuts the air
	if _t > float(def.get("life", 4.0)) or (_back and not _owner_ok() and _t > 1.5):
		end_reason = "time"
		_break(global_position, Vector3.UP, false)
		return
	var speed := float(def.get("return_speed" if _back else "speed", 45.0))
	var want := _dir
	if _back and _owner_ok():
		want = owner_car.global_position + Vector3.UP * HEIGHT - global_position
		want.y = 0.0
		want = want.normalized() if want.length() > 0.1 else _dir
		_dir = _turn(_dir, want, BACK_TURN, delta)
	elif not _back and is_instance_valid(lock) and not lock.is_dead and not lock.is_hidden():
		want = lock.global_position - global_position
		want.y = 0.0
		if want.length() > 0.5 and _dir.angle_to(want.normalized()) < deg_to_rad(70.0):
			_dir = _turn(_dir, want.normalized(), float(def.get("homing", 1.0)), delta)
	var from := global_position
	var to := from + _dir * speed * delta
	to.y = _ground_y(to) + HEIGHT
	# Walls stop it; props it can cut are cut and it flies on.
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | Breakable.COVER_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is Node and (c as Node).has_meta("cover_of"):
			c = (c as Node).get_meta("cover_of")
		if c is Breakable:
			(c as Breakable).weapon_hit(float(def.get("damage", 16.0)) * WeaponData.DAMAGE_SCALE, owner_car, from - _dir * 3.0, false)
			FxKit.spark(get_parent(), hit.position, hit.normal)
		elif (hit.normal as Vector3).y < 0.6:
			end_reason = "wall %s at %s" % [String((c as Node).name) if c is Node else "?", hit.position]
			_break(hit.position, hit.normal, true)
			return
	global_position = to
	_travel += speed * delta
	if not _back and _travel >= float(def.get("range", 55.0)):
		_turn_back()
	_cut_cars()


func _owner_ok() -> bool:
	return is_instance_valid(owner_car) and not owner_car.is_dead


static func _turn(from: Vector3, to: Vector3, rate: float, delta: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle < 0.0001:
		return to
	return from.slerp(to, minf(1.0, rate * delta / angle)).normalized()


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - HEIGHT


func _turn_back() -> void:
	_back = true
	_cut.clear()
	GameFeel.play("ricochet", global_position, get_parent(), -8.0, 0.8)


func _cut_cars() -> void:
	if is_instance_valid(_rearm) and _rearm.aim_point().distance_to(global_position) > HIT_RADIUS + 2.5:
		_cut.erase(_rearm)
		_rearm = null
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or v.is_dead or _cut.has(v):
			continue
		if v == owner_car:
			if _back and v.global_position.distance_to(global_position) < CATCH_RADIUS:
				_catch()
				return
			continue
		if v.aim_point().distance_to(global_position) > HIT_RADIUS + v.stats.get("size", Vector3(2, 2, 5)).x * 0.25:
			continue
		_cut[v] = true
		var dmg := float(def.get("return_damage" if _back else "damage", 16.0)) * WeaponData.DAMAGE_SCALE
		v.take_damage(dmg, owner_car)
		v.push(_dir * float(def.get("push", 3.0)) * v.knockback)
		v.hit_react(_dir, dmg)
		Projectile.hit_feel(v, def, _dir)
		var at := v.aim_point().lerp(global_position, 0.5)
		GameFeel.play("ram_impact", at, get_parent(), -4.0, 1.6, true)
		GameFeel.flash(get_parent(), at, 1.4, Color(1.0, 0.75, 0.4), 0.08)
		for k in 3:
			FxKit.spark(get_parent(), at, (-_dir + Vector3(randf_range(-0.7, 0.7), 0.9, randf_range(-0.7, 0.7))).normalized())
		if v.is_player or (is_instance_valid(owner_car) and owner_car.is_player):
			GameFeel.hitstop(get_tree(), 0.04)
		if not _back:
			_turn_back() # it cut a car: back it comes at once...
			_cut[v] = true
			_rearm = v # ...and can cut it again on the way back once it has left it (48 both ways)
			return


var _rearm: Vehicle # the car cut going out: cut again only after the blade has left it


func _catch() -> void:
	_done = true
	end_reason = "caught"
	owner_car.refund_special(refund) # round 21 (owner): the charge comes back at once
	GameFeel.play("weapon_switch", global_position, get_parent(), -2.0, 0.7)
	FxKit.spark(get_parent(), global_position, Vector3.UP)
	if owner_car.is_player:
		owner_car.notice.emit(owner_car, "BLADE CAUGHT - CHARGE BACK")
	_finish()


## Hit a wall (or ran out of time): it bursts into scrap.
func _break(at: Vector3, normal: Vector3, loud: bool) -> void:
	_done = true
	if loud:
		GameFeel.play("ram_impact", at, get_parent(), -6.0, 1.3, true)
		FxKit.shatter(get_parent(), at, Vector3.ONE * 0.3, normal, 6.0, Color(0.35, 0.3, 0.26), false)
		for k in 3:
			FxKit.spark(get_parent(), at, (normal + Vector3(randf_range(-0.8, 0.8), 0.6, randf_range(-0.8, 0.8))).normalized())
	else:
		FxKit.puff(get_parent(), at, 0.3)
	_finish()


func _finish() -> void:
	if is_instance_valid(_whirr):
		_whirr.stop()
	queue_free()
