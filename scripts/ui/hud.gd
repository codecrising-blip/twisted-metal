class_name Hud
extends CanvasLayer
## Everything on screen: status panel (bottom left: health, turbo, energy, lives), weapons panel
## (bottom right), radar (top right), target lock, kill feed, messages, help, respawn countdown,
## plus a light full-screen filter (faint grain and vignette, damage flash).
## Runs while paused so it can handle pause / restart.

signal restart_requested
signal driver_requested(index: int)
signal music_requested # pause menu M: try the next theme

var music_label := "" # shown in the pause menu

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.02;
uniform float vignette = 0.25;
uniform float desaturate = 0.0;
uniform float damage = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);
	c += (hash(SCREEN_UV * 900.0 + fract(TIME * 13.0) * 50.0) - 0.5) * grain;
	float d = length(SCREEN_UV - vec2(0.5));
	c *= 1.0 - smoothstep(0.35, 0.85, d) * vignette;
	c = mix(c, vec3(0.55, 0.0, 0.0), damage * (0.25 + smoothstep(0.3, 0.8, d) * 0.5));
	COLOR = vec4(c, 1.0);
}
"""

const HELP_TEXT := """W / S  ............  gas / brake-reverse
A / D  ............  steer
SPACE  ............  handbrake (power slide)
SHIFT  ............  turbo (refill: blue turbo pickups)
J or L-MOUSE  .....  machine guns
K or R-MOUSE  .....  fire selected weapon
                     Napalm Cone: tap = homing, hold 2 s = charged
                     Napalm / Remote / taser: press again to
                     drop / blow / mash
Q / E  ............  change weapon
C  ................  jump  (energy)
F  ................  freeze (energy)
B  ................  look back
ESC pause (pick another driver there)
ENTER restart   F1 hide help"""


class Reticle extends Control:
	var locked := false

	func _draw() -> void:
		var s := size
		var col := Color(1.0, 0.2, 0.12, 0.95) if locked else Color(1, 1, 1, 0.5)
		var l := minf(18.0, s.x * 0.3)
		for corner in [Vector2.ZERO, Vector2(s.x, 0), Vector2(0, s.y), s]:
			var dx := l if corner.x == 0.0 else -l
			var dy := l if corner.y == 0.0 else -l
			draw_line(corner, corner + Vector2(dx, 0), col, 3.0)
			draw_line(corner, corner + Vector2(0, dy), col, 3.0)


var player: Vehicle
var camera: Camera3D
var game_over := false
var drivers: Array[String] = [] # names for the pause menu's driver pick (keys 1-5)

var _post: ShaderMaterial
var _whiteout: ColorRect
var _whiteout_tween: Tween
var _title_font: SystemFont
var _status: HudStatus
var _weapons: HudWeapons
var _radar: Radar
var _target_box: VBoxContainer
var _target_name: Label
var _target_health: ProgressBar
var _target_trail: ProgressBar # pale bar that catches up after a hit: shows how much it just lost
var _trail_target: Vehicle
var _trail_hold := 0.0
var _reticle: Reticle
var _title: Label
var _sub: Label
var _feed: VBoxContainer
var _countdown: Label
var _notice: Label
var _notice_tween: Tween
var _help: Label
var _fps: Label
var _message_tween: Tween
var _damage_flash := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_title_font = SystemFont.new()
	_title_font.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Bebas Neue", "Arial Black", "DejaVu Sans Condensed"])
	_title_font.font_weight = 800
	_build()


func bind(p: Vehicle, cam: Camera3D) -> void:
	player = p
	camera = cam
	_status.player = p
	_weapons.player = p
	_radar.player = p
	player.weapons_changed.connect(func(_v): _refresh_weapons())
	player.damaged.connect(_on_player_damaged)
	player.notice.connect(func(_v, text): show_notice(text))
	_refresh_weapons()


# ---------------------------------------------------------------- build

func _build() -> void:
	var post_rect := ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = POST_SHADER
	_post = ShaderMaterial.new()
	_post.shader = shader
	post_rect.material = _post
	add_child(post_rect)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_reticle = Reticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.visible = false
	root.add_child(_reticle)

	# Bottom-left: who you are, health, turbo, energy, lives.
	_status = HudStatus.new()
	_status.font = _title_font
	_pin(_status, 0.0, 1.0, Rect2(24, -24 - HudStatus.H, HudStatus.W, HudStatus.H))
	root.add_child(_status)

	# Top-center: locked target.
	_target_box = VBoxContainer.new()
	_pin(_target_box, 0.5, 0.0, Rect2(-160, 22, 320, 0))
	_target_box.visible = false
	root.add_child(_target_box)
	_target_name = _label("", 22, Color(1, 0.35, 0.3), true)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_box.add_child(_target_name)
	var bars := Control.new()
	bars.custom_minimum_size = Vector2(320, 10)
	_target_box.add_child(bars)
	_target_trail = _plain_bar(Color(0.95, 0.92, 0.85), 320)
	bars.add_child(_target_trail)
	_target_health = _plain_bar(Color(0.85, 0.1, 0.08), 320)
	_target_health.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bars.add_child(_target_health)

	# Top-right: radar (enemies left under it), kill feed below.
	_radar = Radar.new()
	_radar.font = _title_font
	_pin(_radar, 1.0, 0.0, Rect2(-24 - Radar.SIZE, 20, Radar.SIZE, Radar.SIZE + 30))
	root.add_child(_radar)
	var right := VBoxContainer.new()
	_pin(right, 1.0, 0.0, Rect2(-420, 262, 396, 0))
	right.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(right)
	_feed = VBoxContainer.new()
	right.add_child(_feed)

	# Bottom-right: weapons.
	_weapons = HudWeapons.new()
	_weapons.font = _title_font
	_pin(_weapons, 1.0, 1.0, Rect2(-24 - HudWeapons.W, -24 - HudWeapons.H, HudWeapons.W, HudWeapons.H))
	root.add_child(_weapons)

	# Left: controls (hidden after a few seconds, F1 shows them again).
	_help = _label(HELP_TEXT, 15, Color(0.85, 0.83, 0.77, 0.9))
	_pin(_help, 0.0, 0.0, Rect2(28, 30, 480, 266))
	root.add_child(_help)
	get_tree().create_timer(14.0, true).timeout.connect(func(): _help.visible = false)

	# Top-left corner: frames per second (F3), so the owner can tell how fast it runs.
	_fps = _label("", 16, Color(0.75, 1.0, 0.75))
	_pin(_fps, 0.0, 0.0, Rect2(8, 4, 160, 22))
	root.add_child(_fps)

	# Center: big messages.
	var center := VBoxContainer.new()
	_pin(center, 0.5, 0.5, Rect2(-500, -160, 1000, 260))
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_title = _label("", 84, Color(0.95, 0.92, 0.85), true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_title)
	_sub = _label("", 24, Color(0.8, 0.76, 0.7))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_sub)
	_countdown = _label("", 120, Color(1.0, 0.85, 0.35), true)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_countdown)

	# Lower center: short notices (taser link lost, teleported...).
	_notice = _label("", 26, Color(0.75, 0.88, 1.0), true)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_notice, 0.5, 1.0, Rect2(-300, -210, 600, 40))
	root.add_child(_notice)
	# Full-screen white-out (napalm right on you, a SAT strike).
	_whiteout = ColorRect.new()
	_whiteout.color = Color(1.0, 0.98, 0.92, 0.0)
	_whiteout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_whiteout.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_whiteout)


## Anchor a control to a screen point (0..1) with an offset rect in pixels from that point.
func _pin(c: Control, ax: float, ay: float, r: Rect2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if ax >= 1.0 else (Control.GROW_DIRECTION_BOTH if ax == 0.5 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if ay >= 1.0 else Control.GROW_DIRECTION_END


func _label(text: String, size: int, color: Color, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title:
		l.add_theme_font_override("font", _title_font)
	return l


func _plain_bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 10)
	bar.show_percentage = false
	bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.border_color = Color(0.3, 0.28, 0.26, 0.8)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


# ---------------------------------------------------------------- runtime

func _process(delta: float) -> void:
	_handle_input()
	if _damage_flash > 0.0:
		_damage_flash = maxf(0.0, _damage_flash - delta * 1.8)
		_post.set_shader_parameter("damage", _damage_flash)
	if not is_instance_valid(player):
		return
	_update_target()


func _handle_input() -> void:
	if Input.is_action_just_pressed("toggle_help"):
		_help.visible = not _help.visible
	if Input.is_action_just_pressed("toggle_fps"):
		_fps.visible = not _fps.visible
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()
	if Input.is_action_just_pressed("pause") and not game_over:
		get_tree().paused = not get_tree().paused
		GameFeel.ui("menu_select", get_tree())
		if get_tree().paused:
			_show_pause()
		else:
			clear_message()
	if Input.is_action_just_pressed("restart") and (game_over or get_tree().paused):
		get_tree().paused = false
		restart_requested.emit()
	if get_tree().paused and not game_over and Input.is_action_just_pressed("toggle_graphics"):
		GraphicsSettings.toggle(get_tree())
		_show_pause()
	if get_tree().paused and not game_over and Input.is_action_just_pressed("cycle_music"):
		music_requested.emit()
		_show_pause()
	if game_over or get_tree().paused:
		for i in mini(drivers.size(), 5):
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				get_tree().paused = false
				GameFeel.ui("menu_select", get_tree())
				driver_requested.emit(i)
				return


func _show_pause() -> void:
	show_message("PAUSED", "ESC to resume   ENTER to restart   G graphics: %s\nM music: %s\n\n%s" % [GraphicsSettings.label(), music_label, _driver_menu()])


func _driver_menu() -> String:
	var parts: PackedStringArray = []
	for i in mini(drivers.size(), 5):
		parts.append("%d  %s" % [i + 1, drivers[i].to_upper()])
	return "PICK A DRIVER:   " + "     ".join(parts)


func _update_target() -> void:
	var t := player.target
	var valid := is_instance_valid(t) and not t.is_dead and not player.is_dead
	_target_box.visible = valid
	_reticle.visible = false
	if not valid:
		return
	_target_name.text = t.display_name.to_upper()
	var hp := t.health / t.max_health * 100.0
	if t != _trail_target:
		_trail_target = t
		_target_trail.value = hp
	if hp < _target_health.value - 0.01:
		_trail_hold = 0.45 # just hit: hold the pale part a moment, then let it drain
	_target_health.value = hp
	_trail_hold -= get_process_delta_time()
	if _trail_hold <= 0.0:
		_target_trail.value = move_toward(_target_trail.value, hp, 45.0 * get_process_delta_time())
	_target_trail.value = maxf(_target_trail.value, hp)
	if camera == null:
		return
	var p := t.global_position + Vector3.UP * 1.4
	if camera.is_position_behind(p):
		return
	var screen := camera.unproject_position(p)
	var dist := camera.global_position.distance_to(p)
	var s := clampf(900.0 / maxf(dist, 1.0), 36.0, 180.0)
	_reticle.visible = true
	_reticle.locked = true
	_reticle.size = Vector2(s, s * 0.75)
	_reticle.position = screen - _reticle.size * 0.5
	_reticle.queue_redraw()


func _refresh_weapons() -> void:
	_weapons.queue_redraw() # the panel redraws itself every frame anyway


func _on_player_damaged(_v: Vehicle, amount: float, _attacker: Vehicle) -> void:
	if amount <= 0.0:
		return
	_damage_flash = maxf(_damage_flash, clampf(amount / 20.0, 0.08, 1.0))
	_status.hit()
	_post.set_shader_parameter("damage", _damage_flash)


# ---------------------------------------------------------------- public

func set_enemies_left(n: int) -> void:
	_radar.enemies_left = n


## Arena outline for the radar: polylines of world (x, z) points.
func set_radar_lines(lines: Array) -> void:
	_radar.lines = lines


## Spare lives (owner: 3 lives for the whole tournament, shown as 2, 1, 0 spare).
func set_lives(spare: int) -> void:
	_status.spare_lives = spare


## Big respawn countdown in the middle; -1 hides it.
func set_countdown(seconds: int) -> void:
	_countdown.text = str(seconds) if seconds >= 0 else ""


## Flash-bang: the screen goes white and clears over `seconds`.
func flash_bang(seconds: float) -> void:
	if _whiteout_tween:
		_whiteout_tween.kill()
	_whiteout.color.a = 0.92
	_whiteout_tween = create_tween()
	_whiteout_tween.tween_interval(seconds * 0.35)
	_whiteout_tween.tween_property(_whiteout, "color:a", 0.0, seconds * 0.65)


func show_notice(text: String) -> void:
	if _notice_tween:
		_notice_tween.kill()
	_notice.text = text
	_notice.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.4)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func add_feed(text: String) -> void:
	var l := _label(text, 18, Color(0.95, 0.75, 0.6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func show_message(title: String, sub := "", seconds := 0.0) -> void:
	if _message_tween:
		_message_tween.kill()
	_title.text = title
	_sub.text = sub
	_title.modulate.a = 1.0
	_sub.modulate.a = 1.0
	if seconds > 0.0:
		_message_tween = create_tween()
		_message_tween.tween_interval(seconds)
		_message_tween.tween_property(_title, "modulate:a", 0.0, 1.0)
		_message_tween.parallel().tween_property(_sub, "modulate:a", 0.0, 1.0)


func clear_message() -> void:
	if _message_tween:
		_message_tween.kill()
	_title.text = ""
	_sub.text = ""
