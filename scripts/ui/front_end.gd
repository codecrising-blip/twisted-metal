class_name FrontEnd
extends Control
## The game's front end (round 24, owner): main menu (Story Mode, Deathmatch, Options) over the burning city with the
## Head-On "Los Angeles Revisited" theme -> players (Story 1-2, Deathmatch 1-4) -> the stage on a world map (every
## stage of the tour pinned where it is; only Los Angeles is open) -> each player picks a driver, TM2 style: the
## driver's picture (one pose before, a wilder one after you pick: assets/portraits, tools/portraits/build.sh), the car
## turning on a stand, its numbers -> a title card -> the match (scenes/main.tscn, set up through main.gd's statics).
## Everything is built in code. Keys / pad: arrows or d-pad + Enter / Cross, Escape / Circle goes back.

const MENU_MUSIC := "res://audio/music/main_menu.ogg"
const BACKDROP := "res://assets/backdrops/los_angeles_city.jpg"
const WORLD_MAP := "res://assets/ui/world_map.webp"
const MAIN_SCENE := "res://scenes/main.tscn"
const CARS := ["sweet_tooth", "outlaw", "mr_grimm", "roadkill", "axel", "thumper", "darkside", "brimstone"]
## Round 26 (owner): drivers whose pictures are in but whose cars are not built yet. They are in the line-up with their
## picture and numbers (design chapter 1), the stand stays empty under COMING SOON, and they can't be picked.
## Round 28: Thumper and Darkside are built (Brimstone too: his picture comes later from the owner).
const SOON := {}
## The tour in story order (CLAUDE.md); lat / lon place the pins. Only "open" ones can be played yet.
const STAGES := [
	{"id": "los_angeles", "name": "LOS ANGELES", "sub": "RELIEF ZONE ONE", "lat": 34.05, "lon": -118.24, "open": true},
	{"id": "paris", "name": "PARIS", "sub": "CITY OF LIGHTS OUT", "lat": 48.86, "lon": 2.35, "label": Vector2(4, 6), "open": true},
	{"id": "chernobyl", "name": "CHERNOBYL", "sub": "VS MANSLAUGHTER", "lat": 51.27, "lon": 30.22},
	{"id": "egypt", "name": "EGYPT", "sub": "", "lat": 29.98, "lon": 31.13},
	{"id": "tokyo", "name": "TOKYO", "sub": "", "lat": 35.68, "lon": 139.69},
	{"id": "london", "name": "LONDON", "sub": "VS PRIMEVAL", "lat": 51.51, "lon": -0.13, "label": Vector2(-70, -30)},
	{"id": "antarctica", "name": "ANTARCTICA", "sub": "", "lat": -77.85, "lon": 166.67},
	{"id": "hong_kong", "name": "HONG KONG", "sub": "", "lat": 22.32, "lon": 114.17},
	{"id": "new_york", "name": "NEW YORK", "sub": "VS WARHAWK", "lat": 40.71, "lon": -74.0},
	{"id": "athens", "name": "ATHENS", "sub": "", "lat": 37.98, "lon": 23.73, "label": Vector2(12, 0)},
	{"id": "rome", "name": "ROME", "sub": "", "lat": 41.9, "lon": 12.5},
	{"id": "amazonia", "name": "AMAZONIA", "sub": "VS MINION", "lat": -3.4, "lon": -62.2},
]
## Enemies on each stage (owner, session 3: LA 4 rising to 9; design doc 05).
const STAGE_ENEMIES := {"los_angeles": 4, "paris": 5, "chernobyl": 4, "egypt": 6, "tokyo": 6, "london": 5, "antarctica": 7,
	"hong_kong": 7, "new_york": 6, "athens": 8, "rome": 9, "amazonia": 8}
const FIRE := Color(1.0, 0.45, 0.1)
const BONE := Color(0.93, 0.9, 0.84)
const DIM := Color(0.55, 0.52, 0.48)

var _font: SystemFont
var _screen := ""
var _root: Control # the current screen's nodes
var _music: AudioStreamPlayer
var _bg: TextureRect
var _flash: ColorRect
var _mode := "story"
var _players := 1
var _stage := 0
var _cars: Array[String] = []
var _picking := 0 # which player is choosing a driver
var _picking_foes := false # round 25 (owner): after the players, they pick who they fight
var _foes: Array[String] = []
var _car_i := 0
var _index := 0 # highlighted entry on list screens
var _items: Array = [] # [label, action] on list screens
var _busy := false
var _t := 0.0
# car select
var _portrait: TextureRect
var _stand: Node3D
var _car_name: Label
var _car_info: Label
var _soon: Label # COMING SOON over the empty stand
var _no_pic: Label # round 28: a driver whose picture isn't in yet (Brimstone)
var _bars: Array = []
# world map
var _map: TextureRect
var _map_view: Control
var _pins: Array = []
var _stage_name: Label
var _stage_info: Label
var _leg: Line2D # the tour's leg into the highlighted stage
var _sel_bar: TextureRect # the glowing strip behind the highlighted menu entry


func _ready() -> void:
	_fill(self)
	InputSetup.setup()
	GraphicsSettings.load_saved()
	AudioSettings.setup()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Bebas Neue", "Arial Black", "DejaVu Sans Condensed"])
	_font.font_weight = 800
	_build_background()
	_root = Control.new()
	_fill(_root)
	add_child(_root)
	_flash = ColorRect.new()
	_fill(_flash)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_start_music()
	var main_script: GDScript = load("res://scripts/main.gd")
	if main_script.tour_card: # round 30: back from a won stage of the tour: straight to the next match card
		main_script.tour_card = false
		_mode = "story"
		_players = maxi(1, main_script.menu_cars.size())
		_cars.assign(main_script.menu_cars)
		_stage = maxi(0, STAGES.map(func(st: Dictionary) -> String: return String(st.id)).find(main_script.stage))
		_random_foes()
		_show_matchcards()
		return
	_show_main()


# ------------------------------------------------------------------ look

func _build_background() -> void:
	var bg_col := ColorRect.new()
	_fill(bg_col)
	bg_col.color = Color(0.02, 0.015, 0.012)
	add_child(bg_col)
	_bg = TextureRect.new()
	var tex := load(BACKDROP) as Texture2D
	_bg.texture = tex
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(0.55, 0.42, 0.36)
	add_child(_bg)
	# dark at the top and bottom, the city glowing through the middle
	var shade := TextureRect.new()
	_fill(shade)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.92))
	g.set_color(1, Color(0.05, 0.0, 0.0, 0.9))
	g.add_point(0.45, Color(0, 0, 0, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)
	# embers drifting up from the burning street
	var embers := CPUParticles2D.new()
	embers.amount = 90
	embers.lifetime = 5.0
	embers.preprocess = 5.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(1100, 10)
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(0, -12)
	embers.initial_velocity_min = 30.0
	embers.initial_velocity_max = 90.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 4.0
	embers.color_ramp = _ramp([Color(1, 0.8, 0.4, 0.0), Color(1, 0.55, 0.15, 0.9), Color(0.9, 0.2, 0.05, 0.0)])
	embers.name = "Embers"
	add_child(embers)


static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / maxf(cols.size() - 1, 1))
	g.offsets = offs
	return g


func _label(parent: Control, text: String, size: int, color := BONE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.0))
	l.add_theme_constant_override("outline_size", maxi(4, size / 10))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _view() -> Vector2:
	return get_viewport_rect().size


## Anchors a control across the whole width at height y (labels centre their text in it).
static func _wide(c: Control, y: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = y
	c.offset_bottom = y + h


static func _fill(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _clear() -> void:
	for c in _root.get_children():
		c.queue_free()
	_items.clear()
	_pins.clear()
	_bars.clear()
	_stand = null
	_portrait = null
	_map = null
	_leg = null
	_sel_bar = null


func _title(text: String, sub := "") -> void:
	var t := _label(_root, text, 64, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(t, 26, 84)
	if sub != "":
		var s := _label(_root, sub, 24, FIRE, HORIZONTAL_ALIGNMENT_CENTER)
		_wide(s, 104, 34)


func _hint(text: String) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.65)
	_root.add_child(bar)
	_wide(bar, _view().y - 46, 46)
	var h := _label(bar, text, 20, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_fill(h)
	h.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _flash_screen(alpha := 0.8, seconds := 0.3, col := Color(1, 1, 1)) -> void:
	_flash.color = Color(col.r, col.g, col.b, alpha)
	create_tween().tween_property(_flash, "color:a", 0.0, seconds)


func _shake(amount := 14.0) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(_root, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * (1.0 - i / 6.0), 0.035)
	tw.tween_property(_root, "position", Vector2.ZERO, 0.04)


func _sound(name: String, db := -4.0) -> void:
	GameFeel.ui(name, get_tree(), db)


func _start_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = AudioSettings.MUSIC_BUS
	_music.volume_db = -5.0
	add_child(_music)
	var s := load(MENU_MUSIC) as AudioStream
	if s:
		if "loop" in s:
			s.set("loop", true)
		_music.stream = s
		_music.play()


func _process(delta: float) -> void:
	_t += delta
	_read_input()
	var vs := _view()
	if _bg: # the city drifts slowly behind the menus
		_bg.position.x = -60.0 + sin(_t * 0.05) * 60.0
		_bg.size = vs + Vector2(160, 40)
	var embers := get_node_or_null("Embers") as CPUParticles2D
	if embers:
		embers.position = Vector2(vs.x * 0.5, vs.y + 10)
	if _stand:
		_stand.rotate_y(delta * 0.45)
	if _screen == "cars" and _portrait and not _busy: # the picture breathes
		var k := 1.0 + 0.012 * sin(_t * 1.7)
		_portrait.scale = Vector2(k, k)
	if _sel_bar and _index < _items.size():
		var sel: Label = _items[_index][0]
		_sel_bar.position.y = lerpf(_sel_bar.position.y, sel.position.y + 4.0, 0.3)
		_sel_bar.modulate.a = 0.75 + 0.25 * sin(_t * 4.0)
	for i in _items.size(): # the highlighted entry pulses
		var l: Label = _items[i][0]
		var on := i == _index
		l.add_theme_color_override("font_color", FIRE.lerp(Color(1, 0.85, 0.5), 0.5 + 0.5 * sin(_t * 6.0)) if on else BONE)
		l.scale = l.scale.lerp(Vector2.ONE * (1.12 if on else 1.0), 0.2)
	if _map and _screen == "stage":
		for i in _pins.size():
			var ring: Control = _pins[i]
			var sel := i == _stage
			var k := (1.0 + 0.35 * fposmod(_t * 1.2, 1.0)) if sel else 1.0
			ring.scale = Vector2(k, k)
			ring.modulate.a = (1.0 - fposmod(_t * 1.2, 1.0)) if sel else 0.6


# ------------------------------------------------------------------ input

## The menus read their own actions every frame (keys, D-pad, left stick, Cross = OK, Circle = back,
## Triangle / Options / Tab = fight now on the driver select).
func _read_input() -> void:
	if _busy:
		return
	var up := Input.is_action_just_pressed("menu_up")
	var down := Input.is_action_just_pressed("menu_down")
	var left := Input.is_action_just_pressed("menu_left")
	var right := Input.is_action_just_pressed("menu_right")
	var ok := Input.is_action_just_pressed("menu_ok")
	var back := Input.is_action_just_pressed("menu_back")
	var done := Input.is_action_just_pressed("menu_done")
	if not (up or down or left or right or ok or back or done):
		return
	match _screen:
		"main", "options":
			if up or down:
				_index = posmod(_index + (1 if down else -1), _items.size())
				_sound("weapon_switch", -8.0)
			elif (left or right) and _screen == "options":
				_option_step(_items[_index][1], 1 if right else -1)
			elif ok:
				_activate(_items[_index][1])
			elif back:
				if _screen == "options":
					_show_main()
		"players":
			var most := 2 if _mode == "story" else 4
			if left or right or up or down:
				_players = clampi(_players + (1 if (right or up) else -1), 1, most)
				_sound("weapon_switch", -8.0)
				_show_players()
			elif ok:
				_sound("menu_select")
				if _mode == "story": # round 30 (owner): the tournament always starts in Los Angeles
					_stage = 0
					_cars.clear()
					_foes.clear()
					_picking = 0
					_picking_foes = false
					_show_cars()
				else:
					_show_stage()
			elif back:
				_show_main()
		"stage":
			if left or right or up or down:
				_stage = posmod(_stage + (1 if (right or down) else -1), STAGES.size())
				_sound("weapon_switch", -8.0)
				_focus_stage(true)
			elif ok:
				if STAGES[_stage].get("open", false):
					_sound("menu_select")
					_cars.clear()
					_foes.clear()
					_picking = 0
					_picking_foes = false
					_show_cars()
				else:
					_sound("not_available")
					_shake(6.0)
			elif back:
				_show_players()
		"cards":
			if ok or done:
				_sound("menu_select")
				_show_loading()
			elif back and _mode == "deathmatch":
				_show_cars()
		"cars":
			if left or right:
				_car_i = posmod(_car_i + (1 if right else -1), line_up().size())
				_sound("weapon_switch", -8.0)
				_show_car()
			elif ok:
				_pick_car()
			elif done and _picking_foes:
				_sound("menu_select")
				_show_matchcards() # fight now: the opponents picked so far (none = the usual field)
			elif back:
				if _picking_foes and not _foes.is_empty():
					_foes.pop_back()
					_show_cars()
				elif _picking_foes:
					_picking_foes = false
					_cars.pop_back()
					_picking = _cars.size()
					_show_cars()
				elif _picking > 0:
					_picking -= 1
					_cars.pop_back()
					_show_cars()
				elif _mode == "story":
					_show_players()
				else:
					_show_stage()


func _activate(action: String) -> void:
	_sound("menu_select")
	match action:
		"story":
			_mode = "story"
			_players = 1
			_show_players()
		"deathmatch":
			_mode = "deathmatch"
			_players = 1
			_show_players()
		"options":
			_show_options()
		"quit":
			get_tree().quit()
		"graphics", "music", "sfx":
			_option_step(action, 1)
		"back":
			_show_main()


# ------------------------------------------------------------------ main menu and options

func _show_main() -> void:
	_clear()
	_screen = "main"
	_index = 0
	var logo := _label(_root, "TWISTED METAL", 128, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(logo, 60, 160)
	logo.add_theme_color_override("font_outline_color", Color(0.45, 0.03, 0.0))
	logo.add_theme_constant_override("outline_size", 18)
	var tag := _label(_root, "CALYPSO'S TOURNAMENT", 30, FIRE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(tag, 222, 44)
	_list([["STORY MODE", "story"], ["DEATHMATCH", "deathmatch"], ["OPTIONS", "options"], ["QUIT", "quit"]], 340)
	_hint("D-PAD choose     CROSS select")


func _list(entries: Array, top: float) -> void:
	var vs := _view()
	# a red-hot strip behind the highlighted entry, fading out to both sides
	_sel_bar = TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.5, 0.04, 0.0, 0.0), Color(0.62, 0.08, 0.0, 0.85), Color(0.5, 0.04, 0.0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	_sel_bar.texture = gt
	_sel_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sel_bar.stretch_mode = TextureRect.STRETCH_SCALE
	_sel_bar.size = Vector2(760, 58)
	_sel_bar.position = Vector2(vs.x * 0.5 - 380, top + 4)
	_root.add_child(_sel_bar)
	for i in entries.size():
		var l := _label(_root, entries[i][0], 46, BONE, HORIZONTAL_ALIGNMENT_CENTER)
		_wide(l, top + i * 74, 64)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.pivot_offset = Vector2(vs.x * 0.5, 32)
		_items.append([l, entries[i][1]])


func _show_options() -> void:
	_clear()
	_screen = "options"
	_index = 0
	_title("OPTIONS")
	_list([["", "graphics"], ["", "music"], ["", "sfx"], ["BACK", "back"]], 220)
	_refresh_options()
	_hint("D-PAD UP / DOWN choose     LEFT / RIGHT change     CIRCLE back")


func _refresh_options() -> void:
	for it in _items:
		var l: Label = it[0]
		match String(it[1]):
			"graphics":
				l.text = "GRAPHICS   <  %s  >" % GraphicsSettings.label()
			"music":
				l.text = "MUSIC   <  %d%%  >" % roundi(AudioSettings.music * 100.0)
			"sfx":
				l.text = "EFFECTS   <  %d%%  >" % roundi(AudioSettings.sfx * 100.0)


func _option_step(action: String, step: int) -> void:
	match action:
		"graphics":
			GraphicsSettings.toggle(get_tree())
		"music":
			AudioSettings.change("music", step)
		"sfx":
			AudioSettings.change("sfx", step)
		_:
			return
	_sound("weapon_switch", -6.0)
	_refresh_options()


# ------------------------------------------------------------------ players

func _show_players() -> void:
	_clear()
	_screen = "players"
	_title("STORY MODE" if _mode == "story" else "DEATHMATCH", "HOW MANY PLAYERS?")
	var most := 2 if _mode == "story" else 4
	_players = clampi(_players, 1, most)
	var vs := _view()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	_root.add_child(row)
	_wide(row, vs.y * 0.34, 130)
	for n in range(1, most + 1):
		var l := _label(row, "%dP" % n, 96 if n == _players else 64, FIRE if n == _players else DIM, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(170, 120)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _players > 1:
		var note := _label(_root, "SPLIT SCREEN IS NOT BUILT YET: PLAYERS 2-%d PICK THEIR CARS, THE AI DRIVES THEM FOR NOW" % _players, 22, DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_wide(note, vs.y * 0.6, 34)
	_hint("D-PAD players     CROSS continue     CIRCLE back")


# ------------------------------------------------------------------ the world map: stage select

static func map_point(lat: float, lon: float, w: float, h: float) -> Vector2:
	return Vector2((lon + 180.0) / 360.0 * w, (90.0 - lat) / 180.0 * h)


func _show_stage() -> void:
	_clear()
	_screen = "stage"
	_title("CHOOSE YOUR BATTLEGROUND" if _mode == "deathmatch" else "THE TOURNAMENT", "")
	_map_view = Control.new()
	_map_view.clip_contents = true
	var vs := _view()
	_map_view.position = Vector2(60, 140)
	_map_view.size = Vector2(vs.x - 520, vs.y - 220)
	_root.add_child(_map_view)
	var frame := ReferenceRect.new()
	frame.border_color = Color(1.0, 0.45, 0.1, 0.6)
	frame.border_width = 2.0
	frame.editor_only = false
	frame.position = _map_view.position - Vector2(3, 3)
	frame.size = _map_view.size + Vector2(6, 6)
	_root.add_child(frame)
	_map = TextureRect.new()
	_map.texture = load(WORLD_MAP)
	_map.size = Vector2(2048, 1024)
	_map_view.add_child(_map)
	# the tour's leg into the highlighted stage (from the stage before it), an ember arc
	_leg = Line2D.new()
	_leg.width = 3.0
	_leg.joint_mode = Line2D.LINE_JOINT_ROUND
	_leg.gradient = _ramp([Color(1.0, 0.5, 0.15, 0.0), Color(1.0, 0.55, 0.2, 0.9)])
	_map.add_child(_leg)
	for i in STAGES.size():
		var s: Dictionary = STAGES[i]
		var p := map_point(s.lat, s.lon, 2048, 1024)
		var open: bool = s.get("open", false)
		var dot := ColorRect.new()
		dot.size = Vector2(12, 12)
		dot.position = p - Vector2(6, 6)
		dot.color = FIRE if open else Color(0.75, 0.7, 0.65)
		_map.add_child(dot)
		var ring := ReferenceRect.new()
		ring.editor_only = false
		ring.border_color = FIRE if open else Color(0.8, 0.75, 0.7)
		ring.border_width = 2.0
		ring.size = Vector2(30, 30)
		ring.position = p - Vector2(15, 15)
		ring.pivot_offset = Vector2(15, 15)
		_map.add_child(ring)
		_pins.append(ring)
		var name := _label(_map, s.name, 18, BONE if open else DIM)
		name.position = p + (s.get("label", Vector2(12, -14)) as Vector2)
	# the side panel
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.6)
	panel.position = Vector2(vs.x - 430, 140)
	panel.size = Vector2(380, vs.y - 220)
	_root.add_child(panel)
	_stage_name = _label(panel, "", 52, BONE)
	_stage_name.position = Vector2(24, 24)
	_stage_info = _label(panel, "", 22, DIM)
	_stage_info.position = Vector2(26, 100)
	_stage_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_stage_info.size = Vector2(330, 300)
	_focus_stage(false)
	_hint("D-PAD stage     CROSS choose     CIRCLE back")


## Zoom the map onto the highlighted stage and show what it is.
func _focus_stage(animate: bool) -> void:
	var s: Dictionary = STAGES[_stage]
	var open: bool = s.get("open", false)
	_stage_name.text = s.name
	_stage_name.add_theme_color_override("font_color", FIRE if open else BONE)
	var lines: PackedStringArray = ["STAGE %d OF %d" % [_stage + 1, STAGES.size()]]
	if String(s.sub) != "":
		lines.append(s.sub)
	lines.append("")
	lines.append("OPEN" if open else "LOCKED: NOT BUILT YET")
	if _mode == "story" and _stage > 0:
		lines.append("THE TOUR STARTS IN LOS ANGELES")
	_stage_info.text = "\n".join(lines)
	_leg.clear_points()
	if _stage > 0:
		var a: Dictionary = STAGES[_stage - 1]
		var from := map_point(a.lat, a.lon, 2048, 1024)
		var to := map_point(s.lat, s.lon, 2048, 1024)
		var mid := (from + to) * 0.5 + Vector2(0, -from.distance_to(to) * 0.22)
		for i in 33:
			var k := i / 32.0
			_leg.add_point(from.lerp(mid, k).lerp(mid.lerp(to, k), k))
	var zoom := 1.6
	var p := map_point(s.lat, s.lon, 2048, 1024) * zoom
	var target := _map_view.size * 0.5 - p
	target.x = clampf(target.x, _map_view.size.x - 2048 * zoom, 0)
	target.y = clampf(target.y, _map_view.size.y - 1024 * zoom, 0)
	if animate:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_map, "position", target, 0.45)
		tw.tween_property(_map, "scale", Vector2(zoom, zoom), 0.45)
	else:
		_map.scale = Vector2(zoom, zoom)
		_map.position = target


# ------------------------------------------------------------------ driver select (TM2 style)

func _show_cars() -> void:
	_clear()
	_screen = "cars"
	_car_i = CARS.find(Engine.get_meta("last_car", "sweet_tooth")) if _picking == 0 and not _picking_foes else 0
	_car_i = maxi(_car_i, 0)
	if _picking_foes:
		_title("OPPONENT %d OF %d" % [_foes.size() + 1, foe_slots(_players)], "CHOOSE WHO YOU FIGHT")
	else:
		_title("PLAYER %d" % (_picking + 1), "CHOOSE YOUR DRIVER")
	# the driver's picture, top left (round 25: the owner's art, red frame and all; the box takes each picture's
	# own shape: the after-pick pictures are wider)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(_portrait)
	var flames := CPUParticles2D.new()
	flames.amount = 60
	flames.lifetime = 1.0
	flames.preprocess = 1.0
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flames.emission_rect_extents = Vector2(184, 4)
	flames.position = Vector2(240, 640)
	flames.direction = Vector2(0, -1)
	flames.spread = 12.0
	flames.gravity = Vector2(0, -80)
	flames.initial_velocity_min = 40.0
	flames.initial_velocity_max = 120.0
	flames.scale_amount_min = 4.0
	flames.scale_amount_max = 10.0
	flames.color_ramp = _ramp([Color(1, 0.9, 0.5, 0.9), Color(1, 0.45, 0.1, 0.7), Color(0.6, 0.05, 0.0, 0.0)])
	_root.add_child(flames)
	# the car on a turning stand, in the middle
	var vs := _view()
	var vp := _car_view(_root, Vector2(430, 140), Vector2(vs.x - 850, 470), Color(0.6, 0.5, 0.45), 0.7)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.9, 0.8)
	vp.add_child(sun)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.45, 0.12)
	fire.light_energy = 3.0
	fire.omni_range = 9.0
	fire.position = Vector3(0, 0.3, 3.5)
	vp.add_child(fire)
	var cam := Camera3D.new()
	cam.fov = 36.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.3, 7.4), Vector3(0, 0.75, 0))
	_turntable(vp, 2.9, 0.14, Color(0.3, 0.28, 0.26), 0.45, 2.93, 2.99, Color(0.85, 0.3, 0.06))
	_stand = Node3D.new()
	vp.add_child(_stand)
	_soon = _label(_root, "COMING SOON", 46, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_soon.position = Vector2(430, 330)
	_soon.size = Vector2(vs.x - 850, 70)
	_soon.visible = false
	_no_pic = _label(_root, "PICTURE\nCOMING", 40, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_no_pic.position = Vector2(PORTRAIT_X - 180.0, 330.0)
	_no_pic.size = Vector2(360, 120)
	_no_pic.visible = false
	# name with arrows, numbers on the right
	_car_name = _label(_root, "", 54, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_car_name.position = Vector2(430, 600)
	_car_name.size = Vector2(vs.x - 850, 70)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.6)
	panel.position = Vector2(vs.x - 400, 150)
	panel.size = Vector2(350, 488)
	_root.add_child(panel)
	var y := 24.0
	for stat in ["SPEED", "ARMOR", "HANDLING", "SPECIAL"]:
		var l := _label(panel, stat, 22, DIM)
		l.position = Vector2(22, y)
		var row: Array = []
		for k in 10:
			var seg := ColorRect.new()
			seg.size = Vector2(24, 14)
			seg.position = Vector2(22 + k * 30, y + 34)
			panel.add_child(seg)
			row.append(seg)
		_bars.append(row)
		y += 72.0
	_car_info = _label(panel, "", 20, BONE)
	_car_info.position = Vector2(22, y + 6)
	_car_info.size = Vector2(310, 180)
	_car_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	if _picking_foes:
		_hint("D-PAD driver     CROSS pick     TRIANGLE / OPTIONS fight now     CIRCLE back")
		_foe_strip(vs)
	else:
		_hint("D-PAD driver     CROSS select     CIRCLE back")
	_show_car()


## Every driver in the select, the built ones first.
static func line_up() -> Array:
	return CARS + SOON.keys()


static func is_soon(id: String) -> bool:
	return SOON.has(id)


func _show_car() -> void:
	var id: String = line_up()[_car_i]
	var soon := is_soon(id)
	var stats: Dictionary = SOON[id] if soon else Roster.get_car(id)
	_car_name.text = "<   %s   >" % String(stats.get("name", id)).to_upper()
	_set_portrait(_portrait_tex(id, "idle"))
	_portrait.modulate = Color.WHITE
	for c in _stand.get_children():
		c.queue_free()
	_soon.text = "TAKEN" if taken(id) else "COMING SOON"
	_soon.visible = soon or taken(id) # round 30: a car already in this match can't be picked again
	if not soon:
		var model := VehicleModels.build(id)
		var s: Vector3 = stats.get("size", Vector3(2.2, 1.8, 5.0))
		var fit := 4.6 / maxf(s.z, s.x * 1.4)
		model.scale = Vector3.ONE * clampf(fit, 0.6, 1.3)
		_stand.add_child(model)
	_stand.rotation.y = PI + 0.75 # the front three-quarter first (cars face -Z, the camera looks from +Z)
	var vals := [int(stats.get("spd", 5)), int(stats.get("arm", 5)), int(stats.get("hnd", 5)), int(stats.get("spc", 5))]
	for i in _bars.size():
		for k in 10:
			(_bars[i][k] as ColorRect).color = FIRE if k < vals[i] else Color(0.2, 0.18, 0.16)
	if soon:
		_car_info.text = "SPECIAL: %s\nSECONDARY: %s\nDRIVER: %s\n\n\"%s\"" % [String(stats.special).to_upper(),
			String(stats.secondary).to_upper(), String(stats.driver).to_upper(), String(stats.tagline)]
		return
	var sp := WeaponData.get_def(String(stats.get("special", "")))
	var second_id := String(stats.get("secondary", ""))
	var info := "SPECIAL: %s" % String(sp.get("label", "-")).to_upper()
	if second_id != "": # Sweet Bot has no weapon entry of its own: fall back on its id
		var second := WeaponData.get_def(second_id)
		info += "\nSECONDARY: %s" % String(second.get("label", second_id.replace("_", " "))).to_upper()
	info += "\nDRIVER: %s\n\n\"%s\"" % [String(stats.get("driver", "")).to_upper(), String(stats.get("tagline", ""))]
	_car_info.text = info


## PORTRAIT_H tall, as wide as the picture's shape, centred on PORTRAIT_X.
const PORTRAIT_H := 490.0
const PORTRAIT_X := 236.0


func _set_portrait(tex: Texture2D) -> void:
	_portrait.texture = tex
	if _no_pic:
		_no_pic.visible = tex == null
	var aspect := float(tex.get_width()) / float(tex.get_height()) if tex else 0.75
	_portrait.size = Vector2(PORTRAIT_H * aspect, PORTRAIT_H)
	_portrait.position = Vector2(PORTRAIT_X - _portrait.size.x * 0.5, 146.0)
	_portrait.pivot_offset = _portrait.size * 0.5


static func _portrait_tex(id: String, pose: String) -> Texture2D:
	var p := "res://assets/portraits/%s_%s.webp" % [id, pose]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## How many opponents the players pick: LA's field of 4, less the other human players (they are opponents too).
static func foe_slots(players: int) -> int:
	return maxi(1, 4 - (players - 1))


## The opponents picked so far, as small name tags under the stand.
func _foe_strip(vs: Vector2) -> void:
	var names: PackedStringArray = []
	for id in _foes:
		names.append(String(Roster.get_car(id).get("name", id)).to_upper())
	for i in range(_foes.size(), foe_slots(_players)):
		names.append("?")
	var l := _label(_root, "VS   " + "   /   ".join(names), 24, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector2(430, 668)
	l.size = Vector2(vs.x - 850, 36)


## Picked: the picture cuts to the driver's wilder pose with a flash, a punch-in and a shake, and the one heavy
## "choice" boom (round 28, owner: no special-weapon sounds here: no siren, no laugh), then on to the next player
## or the match.
func _pick_car() -> void:
	var id: String = line_up()[_car_i]
	if is_soon(id) or taken(id): # not built yet, or already in this match (round 30): a refusal
		_sound("not_available")
		_shake(6.0)
		_soon.text = "TAKEN" if taken(id) else "COMING SOON"
		_soon.visible = true
		_soon.add_theme_color_override("font_color", FIRE)
		create_tween().tween_callback(_soon_dim).set_delay(0.35)
		return
	_busy = true
	if _picking_foes:
		_foes.append(id)
	else:
		_cars.append(id)
	_set_portrait(_portrait_tex(id, "select"))
	_flash_screen(0.85, 0.35)
	_shake(16.0)
	_portrait.scale = Vector2(1.18, 1.18)
	create_tween().tween_property(_portrait, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sound("menu_select", -1.0)
	_car_name.add_theme_color_override("font_color", FIRE)
	_car_name.text = String(Roster.get_car(id).get("name", id)).to_upper()
	if _picking == 0 and not _picking_foes:
		Engine.set_meta("last_car", id)
	await get_tree().create_timer(1.0 if _picking_foes else 1.6).timeout
	_car_name.add_theme_color_override("font_color", BONE)
	_busy = false
	if not _picking_foes and _cars.size() < _players:
		_picking += 1
		_show_cars()
	elif _mode == "story": # round 30: the tournament's opponents are drawn at random
		_random_foes()
		_show_matchcards()
	elif not _picking_foes or _foes.size() < foe_slots(_players):
		_picking_foes = true
		_show_cars()
	else:
		_show_matchcards()


func _soon_dim() -> void:
	if is_instance_valid(_soon):
		_soon.add_theme_color_override("font_color", DIM)


## Round 30 (owner): a car can be in a match once: picked by a player or as an opponent, it is taken.
func taken(id: String) -> bool:
	return _cars.has(id) or _foes.has(id)


## The tournament's opponents: drawn at random from the cars nobody picked, the stage's field less the other
## human players.
func _random_foes() -> void:
	_foes.clear()
	var pool: Array = CARS.filter(func(id: String) -> bool: return not _cars.has(id))
	pool.shuffle()
	var want := maxi(1, int(STAGE_ENEMIES.get(String(STAGES[_stage].id), 4)) - (_players - 1))
	for id: String in pool:
		if _foes.size() >= want:
			break
		_foes.append(id)


# ------------------------------------------------------------------ the match card (round 30)

## Before every match (owner): the map closes in on the stage and the opponents' cars come up one by one in
## a row of cards, each turning on its own stand under a hard light. Cars only: no drivers, no names.
func _show_matchcards() -> void:
	_clear()
	_screen = "cards"
	var s: Dictionary = STAGES[_stage]
	var vs := _view()
	_title(s.name, "TOURNAMENT  -  STAGE %d" % (_stage + 1) if _mode == "story" else "DEATHMATCH")
	# the world map, closing in on the stage's pin
	var view := Control.new()
	view.clip_contents = true
	view.position = Vector2(60, 150)
	view.size = Vector2(vs.x - 120, vs.y * 0.34)
	_root.add_child(view)
	var map := TextureRect.new()
	map.texture = load(WORLD_MAP)
	map.size = Vector2(2048, 1024)
	view.add_child(map)
	var p := map_point(s.lat, s.lon, 2048, 1024)
	var pin := ReferenceRect.new()
	pin.editor_only = false
	pin.border_color = FIRE
	pin.border_width = 3.0
	pin.size = Vector2(34, 34)
	pin.position = p - Vector2(17, 17)
	pin.pivot_offset = Vector2(17, 17)
	map.add_child(pin)
	var dot := ColorRect.new()
	dot.color = FIRE
	dot.size = Vector2(12, 12)
	dot.position = p - Vector2(6, 6)
	map.add_child(dot)
	var zoom := 2.4
	map.scale = Vector2(0.9, 0.9)
	map.position = view.size * 0.5 - p * 0.9
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(map, "scale", Vector2(zoom, zoom), 1.4)
	tw.tween_property(map, "position", view.size * 0.5 - p * zoom, 1.4)
	var pulse := create_tween().set_loops()
	pulse.tween_property(pin, "scale", Vector2(1.6, 1.6), 0.5)
	pulse.tween_property(pin, "scale", Vector2.ONE, 0.5)
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Color(1.0, 0.45, 0.1, 0.6)
	frame.border_width = 2.0
	frame.position = view.position - Vector2(3, 3)
	frame.size = view.size + Vector2(6, 6)
	_root.add_child(frame)
	var vs_l := _label(_root, "VS", 64, FIRE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(vs_l, vs.y * 0.36 + 136, 70)
	# the cards
	var foes: Array = _cars.slice(1) + _foes
	if foes.is_empty():
		var l := _label(_root, "THE USUAL FIELD", 40, DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_wide(l, vs.y * 0.62, 60)
	var n := foes.size()
	var cw := minf(260.0, (vs.x - 160.0) / maxf(n, 1) - 20.0)
	var ch := cw * 0.85
	var x0 := (vs.x - (cw + 20.0) * n + 20.0) * 0.5
	for i in n:
		var card := _match_card(String(foes[i]), Vector2(cw, ch), i)
		card.position = Vector2(x0 + i * (cw + 20.0), vs.y * 0.36 + 216)
		_root.add_child(card)
		card.modulate.a = 0.0
		var target_y := card.position.y
		card.position.y += 60.0
		var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.6 + i * 0.3)
		t.tween_callback(func() -> void:
			_sound("menu_select", -8.0)
			_flash_screen(0.25, 0.15, FIRE))
		t.tween_property(card, "position:y", target_y, 0.35)
		t.parallel().tween_property(card, "modulate:a", 1.0, 0.2)
	_hint("CROSS / OPTIONS fight" + ("     CIRCLE back" if _mode == "deathmatch" else ""))
	var auto := get_tree().create_timer(2.6 + n * 0.3 + 3.0)
	auto.timeout.connect(func() -> void:
		if _screen == "cards" and not _busy:
			_show_loading())


## One opponent's card: a dark frame with a fire-coloured edge and the car turning on a stand inside it, seen low
## from the front three-quarter (its own little 3D world).
func _match_card(id: String, size: Vector2, index: int) -> Control:
	var card := Control.new()
	card.size = size
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.02, 0.85)
	bg.size = size
	card.add_child(bg)
	var vp := _car_view(card, Vector2(4, 4), size - Vector2(8, 8), Color(0.5, 0.42, 0.38), 0.6)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -40 + index * 13, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.92, 0.85)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.4, 0.1)
	rim.light_energy = 4.0
	rim.omni_range = 10.0
	rim.position = Vector3(-2.5, 1.5, -3.5)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 34.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(5.2, 1.9, 8.6), Vector3(0, 0.35, 0)) # front three-quarter, a little above
	_turntable(vp, 2.6, 0.12, Color(0.22, 0.2, 0.19), 0.5, 2.62, 2.7, Color(0.9, 0.32, 0.06))
	var stand := Node3D.new()
	vp.add_child(stand)
	var model := VehicleModels.build(id)
	var st: Dictionary = Roster.get_car(id)
	var sz: Vector3 = st.get("size", Vector3(2.2, 1.8, 5.0))
	model.scale = Vector3.ONE * clampf(4.2 / maxf(sz.z, sz.x * 1.4), 0.5, 1.2)
	stand.add_child(model)
	stand.rotation.y = PI + 0.5
	var spin := stand.create_tween().set_loops()
	spin.tween_property(stand, "rotation:y", PI + 0.5 + TAU, 9.0).from(PI + 0.5)
	var edge := ReferenceRect.new()
	edge.editor_only = false
	edge.border_color = FIRE
	edge.border_width = 3.0
	edge.size = size
	card.add_child(edge)
	return card


# ------------------------------------------------------------------ to the match

func _show_loading() -> void:
	_clear()
	_screen = "loading"
	_busy = true
	var s: Dictionary = STAGES[_stage]
	var vs := _view()
	var t := _label(_root, s.name, 120, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(t, vs.y * 0.34, 150)
	var sub := _label(_root, s.sub, 36, FIRE, HORIZONTAL_ALIGNMENT_CENTER)
	_wide(sub, vs.y * 0.34 + 150, 50)
	_flash_screen(0.6, 0.5, FIRE)
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, 1.6)
	await get_tree().create_timer(1.8).timeout
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.player_car = _cars[0]
	main_script.menu_mode = _mode
	main_script.menu_cars = _cars.duplicate()
	main_script.menu_foes = _foes.duplicate()
	main_script.stage = String(STAGES[_stage].id)
	main_script.opponent_car = ""
	main_script.full_roster = false
	get_tree().change_scene_to_file(MAIN_SCENE)


## A transparent 3D view of its own (ACES, coloured ambient light) for a car on a stand, inside `parent`.
func _car_view(parent: Control, pos: Vector2, size: Vector2, ambient: Color, ambient_energy: float) -> SubViewport:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.position = pos
	holder.size = size
	parent.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	vp.add_child(env)
	return vp


## The stand under the car: a dark disc of radius r with a glowing ring round its edge.
func _turntable(vp: SubViewport, r: float, h: float, disc_color: Color, rough: float, ring_in: float, ring_out: float, ring_color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r + 0.1
	cm.height = h
	disc.mesh = cm
	disc.position = Vector3(0, -h * 0.5, 0)
	disc.material_override = MeshKit.mat(disc_color, rough, 0.6)
	vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = ring_in
	tm.outer_radius = ring_out
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = ring_color
	ring.material_override = rm
	vp.add_child(ring)
