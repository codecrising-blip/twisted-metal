class_name TyreDash
extends Node3D
## Axel's secondary (round 23, owner's design; it replaces Rim Shot for him): "Tyre Dash". His two giant tyres
## close in on him until he is a squashed ball of two tyres and he tears off at high speed for "time" s,
## bouncing off walls like a pinball. The rules live in Vehicle (dash_time): the gas is held down for him,
## "speed_mult" x his top speed, "handling" x his steering, "armor" x every hit he takes; walls throw him back
## (Vehicle._dash_bounce), and every car he rams takes "ram_damage" once; a wall bounce lets him hit the same car
## again (good in tight spaces, risky in the open: he still takes damage if his hits don't land).
## This node is the look: the tyres slam shut (and open again at the end), Axel and his frame squeezed between
## them, sparks spraying off the tyres, dust, a whine, and a bang of sparks at every bounce.

const CLOSE_TIME := 0.18
const OPEN_TIME := 0.3
const CLOSED_X := 0.3 # the tyres move in to this share of their rest distance from the middle
const BODY_SQUEEZE := 0.32 # Axel and his frame squeezed to this width between them

var car: Vehicle
var def := {}
var _pivots: Array[Node3D] = []
var _rest_x: Array[float] = []
var _body: Node3D
var _k := 0.0
var _closing := true
var _spark_t := 0.0
var _whine: AudioStreamPlayer3D
var _streaks: Array[Streak] = []
var _tops: Array[Node3D] = []


static func start(v: Vehicle, d: Dictionary) -> TyreDash:
	var t := TyreDash.new()
	t.car = v
	t.def = d
	v.add_child(t)
	return t


func _ready() -> void:
	var model := car.model
	for w: Node3D in model.get_meta("wheels", []):
		var pivot := w.get_parent() as Node3D
		if pivot and not _pivots.has(pivot):
			_pivots.append(pivot)
			_rest_x.append(pivot.position.x)
	for c in model.get_children(): # the body: the first child that is not a wheel pivot
		if c is Node3D and not _pivots.has(c):
			_body = c
			break
	var world := car.get_parent()
	var db := float(def.get("sound_db", 0.0))
	GameFeel.play("ram_impact", car.global_position, world, -2.0 + db, 0.6, true)
	GameFeel.play("special_axel", car.global_position, world, -6.0 + db, 1.3, true)
	FxKit.dust_ring(world, car.global_position, 1.4)
	GameFeel.shake(car.global_position, 0.3)
	_whine = GameFeel.loop("skid_loop", self, -6.0, 14.0)
	if _whine:
		_whine.pitch_scale = 1.6
		_whine.play()
	for p in _pivots: # speed streaks off the top of each tyre
		var top := Node3D.new()
		p.add_child(top)
		top.position = Vector3(0.0, float(car.model.get_meta("wheel_radius", 1.0)) * 0.9, 0.0)
		_tops.append(top)
		_streaks.append(Streak.attach(top, Color(1.0, 0.7, 0.35), 0.18, 0.35))
	if car.is_player:
		car.notice.emit(car, "TYRE DASH")


func _process(delta: float) -> void:
	if not is_instance_valid(car):
		queue_free()
		return
	if _closing:
		_k = minf(1.0, _k + delta / CLOSE_TIME)
		if car.dash_time <= 0.0 or car.is_dead:
			_closing = false
			_opened()
	else:
		_k = maxf(0.0, _k - delta / OPEN_TIME)
	var e := _k * _k * (3.0 - 2.0 * _k)
	for i in _pivots.size():
		var p := _pivots[i]
		if is_instance_valid(p):
			p.position.x = _rest_x[i] * lerpf(1.0, CLOSED_X, e)
			p.scale = Vector3(1.0 + 0.22 * e, 1.0 - 0.06 * e, 1.0 - 0.06 * e) # squashed together, a little fatter
	if is_instance_valid(_body):
		_body.scale = Vector3(lerpf(1.0, BODY_SQUEEZE, e), 1.0 - 0.1 * e, 1.0 - 0.05 * e)
	if not _closing and _k <= 0.0:
		queue_free()
		return
	if _closing and car.is_on_floor():
		_spark_t -= delta
		if _spark_t <= 0.0: # the tyres throw sparks and grit as they tear along
			_spark_t = 0.05
			var back := -car.flat_forward()
			for i in _pivots.size():
				var at := car.global_transform * Vector3(_rest_x[i] * CLOSED_X, 0.1, 0.6)
				FxKit.spark(car.get_parent(), at, (back + Vector3.UP * 0.8).normalized())
			if randf() < 0.3:
				FxKit.puff(car.get_parent(), car.global_position - car.flat_forward() * 1.5, 0.35)


## A wall (or a car) threw him back: a bang of sparks and a clank where he hit.
func bounce_fx(at: Vector3, normal: Vector3, power: float) -> void:
	var world := car.get_parent()
	FxKit.crash_burst(world, at + Vector3.UP * 0.5, normal, clampf(power, 0.3, 1.0))
	GameFeel.play("ram_impact", at, world, -4.0, 1.2, true)
	GameFeel.shake(at, 0.3 + 0.3 * power)
	car.squish(-normal, 0.06)


func _opened() -> void:
	var world := car.get_parent()
	GameFeel.play("ram_impact", car.global_position, world, -8.0, 0.8, true)
	FxKit.puff(world, car.global_position, 0.6)
	if is_instance_valid(_whine):
		_whine.stop()
	for s in _streaks:
		if is_instance_valid(s):
			s.follow = null
	for t in _tops:
		if is_instance_valid(t):
			t.queue_free()
