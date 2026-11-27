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
	"main_menu": [KEY_BACKSPACE], # round 24: pause menu -> back to the front end
	# Round 30 (owner): the end-of-match screen: OPTIONS restarts (or goes on to the next stage of the tour),
	# SHARE (Create) goes back to the main menu. Triangle does nothing there any more.
	"end_restart": [KEY_ENTER],
	"end_menu": [KEY_BACKSPACE],
	# Round 25: the front end's own actions (Godot's ui_accept / ui_cancel have no pad buttons, so the pad did nothing).
	"menu_up": [KEY_UP, KEY_W],
	"menu_down": [KEY_DOWN, KEY_S],
	"menu_left": [KEY_LEFT, KEY_A],
	"menu_right": [KEY_RIGHT, KEY_D],
	"menu_ok": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
	"menu_back": [KEY_ESCAPE, KEY_BACKSPACE],
	"menu_done": [KEY_TAB], # driver select: fight now with the opponents picked so far
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
	# Round 22: the pause menu's opponent pick (6 7 8 9 0 = the same five cars as 1-5).
	"pick_6": [KEY_6],
	"pick_7": [KEY_7],
	"pick_8": [KEY_8],
	"pick_9": [KEY_9],
	"pick_10": [KEY_0],
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
	"main_menu": [JOY_BUTTON_Y], # Triangle, only read while paused (round 24; round 30: not after the match)
	"end_restart": [JOY_BUTTON_START], # Options, after the match
	"end_menu": [JOY_BUTTON_BACK], # Share / Create, after the match
	"menu_up": [JOY_BUTTON_DPAD_UP],
	"menu_down": [JOY_BUTTON_DPAD_DOWN],
	"menu_left": [JOY_BUTTON_DPAD_LEFT],
	"menu_right": [JOY_BUTTON_DPAD_RIGHT],
	"menu_ok": [JOY_BUTTON_A], # Cross
	"menu_back": [JOY_BUTTON_B], # Circle
	"menu_done": [JOY_BUTTON_Y, JOY_BUTTON_START], # Triangle / Options
}

# action -> [[axis, direction], ...]
const PAD_AXES := {
	"fire_weapon": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"fire_guns": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"accelerate": [[JOY_AXIS_LEFT_Y, -1.0]],
	"brake": [[JOY_AXIS_LEFT_Y, 1.0]],
	"steer_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"steer_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"menu_up": [[JOY_AXIS_LEFT_Y, -1.0]],
	"menu_down": [[JOY_AXIS_LEFT_Y, 1.0]],
	"menu_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"menu_right": [[JOY_AXIS_LEFT_X, 1.0]],
}
const MENU_DEADZONE := 0.5 # the stick has to be pushed well over before a menu moves


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
	for action in ["menu_up", "menu_down", "menu_left", "menu_right"]:
		InputMap.action_set_deadzone(action, MENU_DEADZONE)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
