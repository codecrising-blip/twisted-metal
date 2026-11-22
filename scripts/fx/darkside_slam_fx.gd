class_name DarksideSlamFx
extends Node3D
## Darkside Slam (round 28): his one red slit flares, sparks stream off the ram plate, the air ripples behind
## him in long dark streaks and the camera shakes as he passes. Lives on the car; finish() lets it die down.

var car: Vehicle
var _marks: Array[Node3D] = []
var _spark := 0.0
var _slit: MeshInstance3D
var _ending := false
var _t := 0.0


static func start(v: Vehicle) -> DarksideSlamFx:
	var fx := DarksideSlamFx.new()
	fx.car = v
	v.model.add_child(fx)
	return fx


func _ready() -> void:
	var size: Vector3 = car.stats.get("size", Vector3(2.9, 3.6, 7.6))
	for sx: float in [-1.0, 1.0]:
		var m := Node3D.new()
		m.position = Vector3(sx * size.x * 0.45, size.y * 0.35, size.z * 0.4)
		add_child(m)
		_marks.append(m)
		Streak.attach(m, Color(0.85, 0.08, 0.05, 0.5), 0.35, 0.5)
	var slit := car.model.find_child("slit", true, false) as MeshInstance3D
	if slit:
		_slit = slit


func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(car) or car.is_dead:
		queue_free()
		return
	var on := car.slam_time > 0.0 and not _ending
	if _slit:
		_slit.scale = Vector3.ONE * (1.0 + (0.6 if on else 0.0) + 0.1 * sin(_t * 30.0))
	if on:
		_spark -= delta
		if _spark <= 0.0:
			_spark = 0.05 if GraphicsSettings.high else 0.1
			var size: Vector3 = car.stats.get("size", Vector3(2.9, 3.6, 7.6))
			var front := car.global_position - car.global_basis.z * (size.z * 0.5) + Vector3.UP * 0.35
			FxKit.spark(car.get_parent(), front + car.global_basis.x * randf_range(-1.2, 1.2), Vector3.UP - car.global_basis.z)
		if GameFeel.camera:
			GameFeel.shake(car.global_position, 0.12, 30.0)


func finish() -> void:
	_ending = true
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free() # their streaks fade out where they were
	get_tree().create_timer(0.8, false).timeout.connect(queue_free)
