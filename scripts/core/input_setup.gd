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
	"energy_jump": [KEY_C],
	"energy_freeze": [KEY_F],
	"look_back": [KEY_B],
	"pause": [KEY_ESCAPE],
	"restart": [KEY_ENTER],
	"toggle_help": [KEY_F1],
	"toggle_graphics": [KEY_G], # pause menu: graphics LOW / HIGH
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

const PAD_BUTTONS := {
	"fire_guns": JOY_BUTTON_A,
	"fire_weapon": JOY_BUTTON_X,
	"handbrake": JOY_BUTTON_B,
	"turbo": JOY_BUTTON_Y,
	"weapon_prev": JOY_BUTTON_LEFT_SHOULDER,
	"weapon_next": JOY_BUTTON_RIGHT_SHOULDER,
	"energy_jump": JOY_BUTTON_DPAD_UP,
	"energy_freeze": JOY_BUTTON_DPAD_DOWN,
	"look_back": JOY_BUTTON_RIGHT_STICK,
	"pause": JOY_BUTTON_START,
	"restart": JOY_BUTTON_START,
	"toggle_help": JOY_BUTTON_BACK,
}

# action -> [axis, direction]
const PAD_AXES := {
	"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"steer_left": [JOY_AXIS_LEFT_X, -1.0],
	"steer_right": [JOY_AXIS_LEFT_X, 1.0],
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
		var ev := InputEventJoypadButton.new()
		ev.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
