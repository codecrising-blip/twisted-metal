class_name PlayerController
extends RefCounted
## Reads the keyboard / gamepad into the vehicle's control fields.


func drive(v: Vehicle, _delta: float) -> void:
	v.in_throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	v.in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	v.in_handbrake = Input.is_action_pressed("handbrake")
	v.in_turbo = Input.is_action_pressed("turbo")
	v.in_fire_guns = Input.is_action_pressed("fire_guns")
	if Input.is_action_just_pressed("fire_weapon"):
		v.want_fire_weapon = true
	if Input.is_action_just_pressed("weapon_next"):
		v.cycle_weapon(1)
	if Input.is_action_just_pressed("weapon_prev"):
		v.cycle_weapon(-1)
	if Input.is_action_just_pressed("energy_jump"):
		v.want_jump = true
	if Input.is_action_just_pressed("energy_freeze"):
		v.want_freeze = true
