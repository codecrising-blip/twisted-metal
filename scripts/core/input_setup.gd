class_name InputSetup
extends RefCounted
## Registers every input action in code so project.godot stays readable.
## Keyboard + mouse and gamepad are both mapped. Change bindings here.

const KEYS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"turbo": [KEY_SHIFT],
	"fire_guns": [KEY_J, KEY_CTRL],
	"fire_weapon": [KEY_K, KEY_ALT],
	"weapon_prev": [KEY_Q],
	"weapon_next": [KEY_E],
	"look_back": [KEY_B],
	"headlights": [KEY_H],
	"camera_mode": [KEY_V],
	# Energy moves, one key each (easy play). The combos below work too.
	"move_jump": [KEY_1, KEY_C],
	"move_freeze": [KEY_2, KEY_F],
	"move_rear_freeze": [KEY_3],
	"move_shield": [KEY_4],
	"move_invisible": [KEY_5],
	"move_mines": [KEY_6],
	"move_rear_attack": [KEY_7],
	"move_secondary": [KEY_8],
	# Combo taps (owner, play-test 1): the arrows / WASD double as the D-pad.
	"dir_up": [KEY_W, KEY_UP],
	"dir_down": [KEY_S, KEY_DOWN],
	"dir_left": [KEY_A, KEY_LEFT],
	"dir_right": [KEY_D, KEY_RIGHT],
	"pause": [KEY_ESCAPE],
	"restart": [KEY_ENTER],
	"toggle_help": [KEY_F1],
	"toggle_graphics": [KEY_G], # pause menu: graphics LOW / HIGH
	"cycle_music": [KEY_M], # pause menu: try another theme on this stage (owner's music test)
	"music_down": [KEY_MINUS], # pause menu: volumes (round 5)
	"music_up": [KEY_EQUAL],
	"sfx_down": [KEY_BRACKETLEFT],
	"sfx_up": [KEY_BRACKETRIGHT],
	"toggle_fps": [KEY_F3], # frames-per-second counter
	# Pause menu: pick a driver (restarts the stage).
	"pick_1": [KEY_1],
	"pick_2": [KEY_2],
	"pick_3": [KEY_3],
	"pick_4": [KEY_4],
	"pick_5": [KEY_5],
}

const MOUSE := {
	"fire_guns": MOUSE_BUTTON_LEFT,
	"fire_weapon": MOUSE_BUTTON_RIGHT,
}

## PlayStation pad (owner, round 7; Godot's names: A = Cross, B = Circle, X = Square, Y = Triangle,
## BACK = Create, START = Options, LEFT_STICK = L3, RIGHT_STICK = R3).
##   Square gas (double-tap and hold = turbo)    Triangle reverse (double-tap and hold = reverse turbo)
##   Cross and Circle handbrake (drift going forward or backward)    L3 headlights    R3 rear view
##   (press again to look forward)    R2 machine guns    L2 fire weapon    R1/L1 switch weapon
##   Touchpad / Options pause and resume    Create camera mode (in the pause menu: restart)
## Godot 4.3 reads the touchpad as one button (no left / right half), so the camera sits on Create,
## the button just left of the touchpad. D-pad and the left stick steer, up drives, down reverses,
## and both enter the energy combos.
const PAD_BUTTONS := {
	"accelerate": [JOY_BUTTON_X, JOY_BUTTON_DPAD_UP],
	"pad_gas": [JOY_BUTTON_X], # Square alone: its double-tap is turbo
	"brake": [JOY_BUTTON_Y, JOY_BUTTON_DPAD_DOWN],
	"pad_reverse": [JOY_BUTTON_Y], # Triangle alone: its double-tap is turbo in reverse
	"steer_left": [JOY_BUTTON_DPAD_LEFT],
	"steer_right": [JOY_BUTTON_DPAD_RIGHT],
	"handbrake": [JOY_BUTTON_A, JOY_BUTTON_B],
	"headlights": [JOY_BUTTON_LEFT_STICK],
	"rear_view": [JOY_BUTTON_RIGHT_STICK], # toggle: look back until pressed again
	"weapon_prev": [JOY_BUTTON_LEFT_SHOULDER],
	"weapon_next": [JOY_BUTTON_RIGHT_SHOULDER],
	"camera_mode": [JOY_BUTTON_BACK],
	"dir_up": [JOY_BUTTON_DPAD_UP],
	"dir_down": [JOY_BUTTON_DPAD_DOWN],
	"dir_left": [JOY_BUTTON_DPAD_LEFT],
	"dir_right": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START, JOY_BUTTON_TOUCHPAD],
	"restart": [JOY_BUTTON_BACK], # only read while paused or after the match
}

# action -> [[axis, direction], ...]
const PAD_AXES := {
	"fire_weapon": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"fire_guns": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"accelerate": [[JOY_AXIS_LEFT_Y, -1.0]],
	"brake": [[JOY_AXIS_LEFT_Y, 1.0]],
	"steer_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"steer_right": [[JOY_AXIS_LEFT_X, 1.0]],
}


static func setup() -> void:
	if InputMap.has_action("accelerate"):
		return # already registered (scene reload)
	for action in KEYS:
		_ensure(action)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		_ensure(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE[action]
		InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		_ensure(action)
		for button in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		_ensure(action)
		for pair: Array in PAD_AXES[action]:
			var ev := InputEventJoypadMotion.new()
			ev.axis = pair[0]
			ev.axis_value = pair[1]
			InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
