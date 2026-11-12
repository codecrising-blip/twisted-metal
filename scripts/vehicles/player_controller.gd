class_name PlayerController
extends RefCounted
## Reads the keyboard / gamepad into the vehicle's control fields, and turns quick taps on the D-pad,
## the left stick or the arrows / WASD into energy-move combos (owner, play-test 1):
##   Up Up Left jump     Up Up Right shield     Left Right Up freeze      Right Left Up secondary
##   Left Right Down rear freeze    Right Left Down invisibility    Down Down Right mines
##   Down Down Left rear attack
## Each tap within COMBO_GAP of the last one, the three within COMBO_TIME. Holding a direction to
## steer or drive is one tap, so normal driving doesn't set moves off.

const COMBOS := {
	"UUL": "jump", "UUR": "shield", "LRU": "freeze", "RLU": "secondary",
	"LRD": "rear_freeze", "RLD": "invisible", "DDR": "mines", "DDL": "rear_attack",
}
const COMBO_GAP := 0.3
const COMBO_TIME := 0.6
const DIRECT := ["jump", "freeze", "rear_freeze", "shield", "invisible", "mines", "rear_attack", "secondary"]
const DOUBLE_TAP := 0.3 # Square twice this fast, held = turbo

var _taps: Array = [] # [letter, time]
var _stick := ""
var _gas_last := -10.0
var _pad_turbo := false


func drive(v: Vehicle, _delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	v.in_throttle = clampf(Input.get_action_strength("accelerate"), 0.0, 1.0) - clampf(Input.get_action_strength("brake"), 0.0, 1.0)
	v.in_steer = clampf(Input.get_action_strength("steer_right"), 0.0, 1.0) - clampf(Input.get_action_strength("steer_left"), 0.0, 1.0)
	v.in_handbrake = Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("pad_gas"):
		_pad_turbo = now - _gas_last < DOUBLE_TAP
		_gas_last = now
	if not Input.is_action_pressed("pad_gas"):
		_pad_turbo = false
	v.in_turbo = Input.is_action_pressed("turbo") or _pad_turbo
	v.in_fire_guns = Input.is_action_pressed("fire_guns")
	v.in_fire_weapon = Input.is_action_pressed("fire_weapon") # held: charged shots
	if Input.is_action_just_pressed("fire_weapon"):
		v.want_fire_weapon = true
	if Input.is_action_just_pressed("weapon_next"):
		v.cycle_weapon(1)
	if Input.is_action_just_pressed("weapon_prev"):
		v.cycle_weapon(-1)
	if Input.is_action_just_pressed("headlights"):
		v.toggle_headlights()
	for move: String in DIRECT:
		if Input.is_action_just_pressed("move_" + move):
			v.want_move = move
	var combo := _combo(now)
	if combo != "":
		v.want_move = combo


## The newest taps; a finished combo's move, or "".
func _combo(now: float) -> String:
	var fresh: Array[String] = []
	for d: String in ["up", "down", "left", "right"]:
		if Input.is_action_just_pressed("dir_" + d):
			fresh.append(d.substr(0, 1).to_upper())
	# The left stick taps when it is pushed past 70% toward a new direction.
	var sx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var big := maxf(absf(sx), absf(sy))
	var dir := ""
	if big > 0.7:
		dir = ("R" if sx > 0.0 else "L") if absf(sx) > absf(sy) else ("D" if sy > 0.0 else "U")
	if dir != "" and dir != _stick:
		fresh.append(dir)
	if dir != "" or big < 0.35:
		_stick = dir
	for letter in fresh:
		if not _taps.is_empty() and now - float(_taps[-1][1]) > COMBO_GAP:
			_taps.clear()
		_taps.append([letter, now])
		while _taps.size() > 3:
			_taps.pop_front()
		if _taps.size() == 3 and now - float(_taps[0][1]) <= COMBO_TIME:
			var key := "".join(PackedStringArray(_taps.map(func(t: Array) -> String: return String(t[0]))))
			if COMBOS.has(key):
				_taps.clear()
				return COMBOS[key]
	return ""
