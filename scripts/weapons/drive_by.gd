class_name DriveBy
extends Node3D
## Thumper's secondary (round 28, design 01 ch 9): two of Bruce's crew lean out of the side windows with small
## machine guns for "time" s. Each side picks the nearest car arc_from..arc_to degrees off its side within
## range (and in sight) and sprays it: real rounds ("drive_by_round"), dps a side. The only side attack in
## the game. The gunmen are the model's "gunman_l" / "gunman_r" nodes (they lean out and back in); without
## them a plain arm and gun stand in.

var car: Vehicle
var def: Dictionary
var _time := 0.0
var _gap := 0.1
var _cd := [0.0, 0.0]
var _men: Array[Node3D] = []
var _rest: Array[Vector3] = []
var _snd: AudioStreamPlayer3D


static func start(v: Vehicle, d: Dictionary) -> DriveBy:
	var db := DriveBy.new()
	db.car = v
	db.def = d
	v.add_child(db)
	return db


func _ready() -> void:
	_time = float(def.get("time", 6.0))
	_gap = WeaponData.get_def("drive_by_round").get("damage", 0.55) / maxf(float(def.get("dps", 5.0)), 0.1)
	var size: Vector3 = car.stats.get("size", Vector3(2.3, 1.5, 5.8))
	for side: float in [-1.0, 1.0]:
		var man := car.model.find_child("gunman_l" if side < 0.0 else "gunman_r", true, false) as Node3D
		if man == null:
			man = _stand_in(side, size)
		man.visible = true
		_men.append(man)
		_rest.append(man.position)
	_snd = GameFeel.loop("guns_loop", self, -4.0, 14.0)
	if _snd:
		_snd.pitch_scale = 1.25 # lighter guns than the car's
	GameFeel.play("weapon_switch", car.global_position + Vector3.UP, car, 0.0, 0.8)


## A forearm and a small gun out of the window, when the model has no gunmen of its own.
func _stand_in(side: float, size: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "gunman_stand_in"
	n.position = Vector3(side * size.x * 0.5, size.y * 0.75, -0.2)
	var mb := MeshBuilder.new()
	mb.box(MatKit.flat(Color(0.32, 0.22, 0.16), 0.8), Vector3(0.5, 0.14, 0.14), Transform3D(Basis(), Vector3(side * 0.2, 0, 0)), 0.02)
	mb.box(MatKit.flat(Color(0.08, 0.08, 0.08), 0.5, 0.6), Vector3(0.12, 0.12, 0.55), Transform3D(Basis(), Vector3(side * 0.45, 0.02, -0.1)), 0.01)
	mb.commit(n, false)
	n.set_meta("stand_in", true)
	car.model.add_child(n)
	return n


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car) or car.is_dead:
		_finish()
		return
	_time -= delta
	var out := clampf(minf(float(def.get("time", 6.0)) - _time, _time) / 0.35, 0.0, 1.0) # lean out, lean back in
	var firing := false
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var man := _men[i]
		man.position = _rest[i] + Vector3(side * 0.35 * out, 0.0, 0.0)
		if out < 0.9:
			man.rotation = Vector3(0.0, -side * PI * 0.5 * out, 0.0) # turning to face out of his window
			continue
		_cd[i] -= delta
		var t := _pick(side)
		if t == null:
			man.rotation = Vector3(0.0, -side * PI * 0.5, 0.0)
			continue
		firing = true
		man.look_at(t.aim_point(), Vector3.UP)
		while _cd[i] <= 0.0:
			_cd[i] += _gap
			var from := man.global_position + (t.aim_point() - man.global_position).normalized() * 0.6
			var dir := (t.aim_point() - from).normalized()
			dir = dir.rotated(Vector3.UP, randf_range(-0.03, 0.03))
			Projectile.spawn(car.get_parent(), "drive_by_round", from, dir, car, null)
			if randf() < 0.35:
				FxKit.spark(car.get_parent(), from, dir)
	if _snd:
		if firing and not _snd.playing:
			_snd.play()
		elif not firing and _snd.playing:
			_snd.stop()
	if _time <= 0.0:
		_finish()


## The nearest live car this side covers, in range and in sight.
func _pick(side: float) -> Vehicle:
	var right := car.global_basis.x * side
	var fwd := car.flat_forward()
	var reach := float(def.get("range", 30.0))
	var best: Vehicle = null
	var best_d := INF
	var space := car.get_world_3d().direct_space_state
	for node in car.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == car or o.is_dead or o.is_hidden():
			continue
		var to := o.global_position - car.global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 1.0:
			continue
		if to.dot(right) <= 0.0:
			continue
		var off := rad_to_deg(fwd.angle_to(to / d)) # 0 ahead .. 180 behind; the side arc is 60..120
		if off < float(def.get("arc_from", 60.0)) or off > float(def.get("arc_to", 120.0)):
			continue
		var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 1.3, o.aim_point(), 1)
		q.exclude = [car.get_rid(), o.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = o
	return best


func _finish() -> void:
	for i in _men.size():
		var man := _men[i]
		if not is_instance_valid(man):
			continue
		if man.has_meta("stand_in"):
			man.queue_free()
		else:
			man.position = _rest[i]
			man.rotation = Vector3.ZERO
			man.visible = false
	set_physics_process(false)
	queue_free()
