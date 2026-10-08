class_name Hud
extends CanvasLayer
## Everything on screen: bars, weapons, target lock, kill feed, messages, help,
## plus the gritty full-screen filter (grain, vignette, desaturation, damage flash).
## Runs while paused so it can handle pause / restart.

signal restart_requested

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.07;
uniform float vignette = 0.6;
uniform float desaturate = 0.25;
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
SHIFT  ............  turbo
J or L-MOUSE  .....  machine guns
K or R-MOUSE  .....  fire selected weapon
Q / E  ............  change weapon
C  ................  jump  (energy)
F  ................  freeze (energy)
B  ................  look back
ESC pause   ENTER restart   F1 hide help"""


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

var _post: ShaderMaterial
var _player_name: Label
var _driver: Label
var _title_font: SystemFont
var _health: ProgressBar
var _turbo: ProgressBar
var _energy: ProgressBar
var _weapons: VBoxContainer
var _target_box: VBoxContainer
var _target_name: Label
var _target_health: ProgressBar
var _reticle: Reticle
var _title: Label
var _sub: Label
var _feed: VBoxContainer
var _enemies: Label
var _help: Label
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
	_player_name.text = player.display_name.to_upper()
	_driver.text = String(player.stats.get("driver", ""))
	player.weapons_changed.connect(func(_v): _refresh_weapons())
	player.damaged.connect(_on_player_damaged)
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

	# Top-left: who you are and your bars.
	var status := VBoxContainer.new()
	status.position = Vector2(28, 22)
	status.add_theme_constant_override("separation", 4)
	root.add_child(status)
	_player_name = _label("", 34, Color(0.92, 0.9, 0.85), true)
	status.add_child(_player_name)
	_driver = _label("", 16, Color(0.6, 0.58, 0.55))
	status.add_child(_driver)
	_health = _bar(status, "HEALTH", Color(0.85, 0.1, 0.08), 320)
	_turbo = _bar(status, "TURBO", Color(1.0, 0.55, 0.1), 220)
	_energy = _bar(status, "ENERGY", Color(0.25, 0.55, 1.0), 220)

	# Top-center: locked target.
	_target_box = VBoxContainer.new()
	_pin(_target_box, 0.5, 0.0, Rect2(-160, 22, 320, 0))
	_target_box.visible = false
	root.add_child(_target_box)
	_target_name = _label("", 22, Color(1, 0.35, 0.3), true)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_box.add_child(_target_name)
	_target_health = _plain_bar(Color(0.85, 0.1, 0.08), 320)
	_target_box.add_child(_target_health)

	# Top-right: enemies left and kill feed.
	var right := VBoxContainer.new()
	_pin(right, 1.0, 0.0, Rect2(-420, 22, 396, 0))
	right.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(right)
	_enemies = _label("", 22, Color(0.92, 0.9, 0.85), true)
	_enemies.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemies)
	_feed = VBoxContainer.new()
	right.add_child(_feed)

	# Bottom-right: weapons.
	_weapons = VBoxContainer.new()
	_pin(_weapons, 1.0, 1.0, Rect2(-520, -220, 496, 196))
	_weapons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_weapons)

	# Bottom-left: controls.
	_help = _label(HELP_TEXT, 15, Color(0.8, 0.78, 0.72, 0.85))
	_pin(_help, 0.0, 1.0, Rect2(28, -290, 480, 266))
	root.add_child(_help)
	get_tree().create_timer(14.0, true).timeout.connect(func(): _help.visible = false)

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


func _bar(parent: Control, caption: String, color: Color, width: float) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var cap := _label(caption, 14, Color(0.7, 0.68, 0.64))
	cap.custom_minimum_size = Vector2(70, 0)
	row.add_child(cap)
	var bar := _plain_bar(color, width)
	row.add_child(bar)
	return bar


func _plain_bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 16)
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
	_health.value = player.health / player.max_health * 100.0
	_turbo.value = player.turbo
	_energy.value = player.energy
	_update_target()


func _handle_input() -> void:
	if Input.is_action_just_pressed("toggle_help"):
		_help.visible = not _help.visible
	if Input.is_action_just_pressed("pause") and not game_over:
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			show_message("PAUSED", "ESC to resume   ENTER to restart")
		else:
			clear_message()
	if Input.is_action_just_pressed("restart") and (game_over or get_tree().paused):
		get_tree().paused = false
		restart_requested.emit()


func _update_target() -> void:
	var t := player.target
	var valid := is_instance_valid(t) and not t.is_dead and not player.is_dead
	_target_box.visible = valid
	_reticle.visible = false
	if not valid:
		return
	_target_name.text = t.display_name.to_upper()
	_target_health.value = t.health / t.max_health * 100.0
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
	for c in _weapons.get_children():
		c.queue_free()
	if not is_instance_valid(player):
		return
	var current := player.selected_weapon()
	for id in player.weapon_order:
		var def := WeaponData.get_def(id)
		var count: int = player.ammo.get(id, 0)
		var is_sel: bool = id == current
		var text := "%s%s  x%d" % ["> " if is_sel else "  ", String(def.get("label", id)).to_upper(), count]
		if def.get("special", false):
			text += "  SP"
		var color: Color = def.get("color", Color.WHITE) if is_sel else Color(0.6, 0.58, 0.55)
		var l := _label(text, 24 if is_sel else 18, color, is_sel)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_weapons.add_child(l)


func _on_player_damaged(_v: Vehicle, amount: float, _attacker: Vehicle) -> void:
	if amount <= 0.0:
		return
	_damage_flash = maxf(_damage_flash, clampf(amount / 25.0, 0.25, 1.0))
	_post.set_shader_parameter("damage", _damage_flash)


# ---------------------------------------------------------------- public

func set_enemies_left(n: int) -> void:
	_enemies.text = "ENEMIES LEFT: %d" % n


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
