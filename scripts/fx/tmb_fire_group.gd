class_name TmbFireGroup
extends Node3D
## A fire made of TMB flame sheets (round 17, the owner's standard): a car burning, a wreck's pyre, a
## pool of burning fuel, a palm alight, the pit of fire. Switch it with `on`; it flares up and dies
## down smoothly, `level` caps how big it burns, and when the thing it sits on moves the tips stream
## back against the motion.

var on := false
var level := 1.0
var rise := 4.0 # strength per second while flaring up
var fall := 1.5 # ...and while dying down
var lean_scale := 0.1 # metres of sweep per m/s of motion
var sheets: Array = []
var _s := 0.0
var _last := Vector3.INF


## A flame sheet standing at `at` (this node's space), (width, height) in metres.
func add(size: Vector2, at := Vector3.ZERO) -> void:
	sheets.append(TmbFire.sheet(self, size, at))


## Flames scattered over a disc of `radius` (pools, pits): `count` sheets of about `size`.
func scatter(radius: float, count: int, size: Vector2, rng: RandomNumberGenerator = null) -> void:
	for k in count:
		var a := TAU * (float(k) + (rng.randf() if rng else randf()) * 0.6) / float(count)
		var r := radius * sqrt((rng.randf() if rng else randf()) * 0.85 + 0.05)
		var s := size * ((rng.randf_range(0.75, 1.2)) if rng else randf_range(0.75, 1.2))
		add(s, Vector3(cos(a) * r, 0.0, sin(a) * r))


func _process(delta: float) -> void:
	var target := level if on else 0.0
	if _s == target and _s <= 0.0:
		_last = Vector3.INF
		return
	_s = move_toward(_s, target, (rise if target > _s else fall) * delta)
	var lean := Vector3.ZERO
	var p := global_position
	if _last != Vector3.INF and delta > 0.0:
		var v := (p - _last) / delta
		v.y = 0.0
		lean = -v.limit_length(25.0) * lean_scale
	_last = p
	TmbFire.set_all(sheets, _s, lean)
