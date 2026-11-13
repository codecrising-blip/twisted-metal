extends Node3D
## One stage of the tournament: Sweet Tooth (player) against the AI. Last car running wins.
## Right now it runs the quality preview: Sweet Tooth vs Outlaw only (`-- full` for all five).
## The player has 3 lives (owner, session 3): a wreck costs one and you come back after 6 seconds
## in the same fight; the last one lost is game over. Stage 1 = TM2 Los Angeles with 4 enemies.
## Run with `-- junkyard` after the project path to play the old Junkyard instead.

## Quality preview (owner, session 5): only the two detailed cars, one on one in Los Angeles.
## You play one (pick it in the pause menu), the AI drives the other.
const PREVIEW_DRIVERS := ["sweet_tooth", "outlaw"]
## The whole test roster (the other three still have their simple prototype models).
## Run with `-- full` after the project path; the smoke test uses it too.
const FULL_DRIVERS := ["sweet_tooth", "outlaw", "junkyard_dog", "mr_grimm", "spectre"]
const START_LIVES := 3
const RESPAWN_DELAY := 6.0
const FALL_LIMIT := -25.0 # below this a car fell out of the world: put it back
const MUSIC_DIR := "res://audio/music"
## Themes in story order (owner's list, session 6): the M music test steps through them in this order.
const MUSIC_ORDER := ["los_angeles", "paris", "manslaughter", "egypt", "tokyo", "antarctica", "hong_kong",
	"warhawk", "rome", "amazonia", "minion", "calypso", "unpicked_1", "unpicked_2"]

static var player_car := "sweet_tooth" # survives scene reloads
static var full_roster := false # true = FULL_DRIVERS (tests, `-- full`)
## Music test (owner, session 6): M in the pause menu swaps the stage's theme for any other track in
## audio/music (unpicked ones too), to hear whether it fits. "" = the stage's own theme. Kept until quit.
static var music_pick := ""

var state := "playing" # playing | won | lost
var lives := START_LIVES # counts the life in use; spare lives = lives - 1
var player: Vehicle
var enemies: Array[Vehicle] = []
var arena: Node3D
var camera: ChaseCamera
var hud: Hud
var music: AudioStreamPlayer

var drivers: Array = PREVIEW_DRIVERS
var _respawn_timer := -1.0


func _ready() -> void:
	InputSetup.setup()
	GraphicsSettings.load_saved()
	AudioSettings.setup()
	if full_roster or "full" in OS.get_cmdline_user_args():
		drivers = FULL_DRIVERS
	arena = JunkyardArena.new() if "junkyard" in OS.get_cmdline_user_args() else LosAngelesArena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build()
	arena.easter_egg.connect(_on_easter_egg)

	player = _spawn(player_car, arena.spawn_points[0], true)
	player.controller = PlayerController.new()
	player.protect()
	var enemy_cars: Array = drivers.filter(func(id: String): return id != player_car)
	for i in enemy_cars.size():
		var e := _spawn(enemy_cars[i], arena.spawn_points[(i + 1) % arena.spawn_points.size()], false)
		var brain := AIDriver.new()
		brain.arena = arena
		e.controller = brain
		e.auto_target = false
		enemies.append(e)
	_spawn_pickups()
	GraphicsSettings.apply(get_tree())

	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	add_child(camera)
	camera.current = true
	camera.follow(player)
	GameFeel.camera = camera
	get_tree().create_timer(0.15).timeout.connect(func() -> void: GameFeel.prewarm(self, camera))

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	GameFeel.hud = hud
	hud.bind(player, camera)
	hud.restart_requested.connect(_restart)
	hud.driver_requested.connect(_pick_driver)
	hud.music_requested.connect(_cycle_music)
	hud.drivers.assign(drivers.map(func(id: String): return String(Roster.get_car(id).get("name", id))))
	hud.set_enemies_left(enemies.size())
	hud.set_lives(lives - 1)
	if arena.has_method("radar_lines"):
		hud.set_radar_lines(arena.radar_lines())
	var stage_line: String = arena.title + ("  -  " + arena.subtitle if arena.subtitle != "" else "")
	hud.show_message(arena.title, "%s\n%s  -  %s\n%s\n(ESC: pick another driver)" % [arena.subtitle, player.display_name, player.stats.get("driver", ""), player.stats.get("tagline", "")], 4.0)
	print("Stage: ", stage_line)

	_start_music()


func _spawn(id: String, xform: Transform3D, is_player: bool) -> Vehicle:
	var v := Vehicle.new()
	v.name = id.to_pascal_case()
	v.setup(id, is_player)
	v.arena_center = arena.center
	add_child(v)
	v.global_transform = xform
	v.destroyed.connect(_on_destroyed)
	v.damaged.connect(_on_damaged)
	v.wall_slammed.connect(_on_wall_slammed)
	return v


func _spawn_pickups() -> void:
	# Each weapon spot always gives the same weapon (owner, session 6): learn the map, come back for it.
	var spot_rng := RandomNumberGenerator.new()
	spot_rng.seed = 2026
	var kinds: Array = WeaponData.PICKUP_WEAPONS.duplicate()
	for i in arena.weapon_points.size():
		if i % kinds.size() == 0: # a fresh shuffle of the whole mix for every round of spots
			for k in range(kinds.size() - 1, 0, -1):
				var j := spot_rng.randi_range(0, k)
				var tmp = kinds[k]
				kinds[k] = kinds[j]
				kinds[j] = tmp
		var kind: String = kinds[i % kinds.size()]
		if "weapon_kinds" in arena and i < arena.weapon_kinds.size() and arena.weapon_kinds[i] != "":
			kind = arena.weapon_kinds[i] # the stage says what goes where (LA, round 9)
		var pk := Pickup.create(self, kind, arena.weapon_points[i])
		pk.random_weapon = false
	for p in arena.health_points:
		Pickup.create(self, "health", p)
	for p in arena.mega_points:
		Pickup.create(self, "mega", p)
	if "turbo_points" in arena:
		for p: Vector3 in arena.turbo_points:
			Pickup.create(self, "turbo", p)


func _physics_process(delta: float) -> void:
	for v: Vehicle in [player] + enemies:
		if is_instance_valid(v) and not v.is_dead and v.global_position.y < FALL_LIMIT:
			v.velocity = Vector3.ZERO
			v.speed = 0.0
			v.global_transform = _safest_spawn()
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		hud.set_countdown(ceili(_respawn_timer))
		if _respawn_timer <= 0.0:
			_respawn_player()


## Spawn point farthest from every living enemy.
func _safest_spawn() -> Transform3D:
	var best: Transform3D = arena.respawn_points[0]
	var best_d := -1.0
	for t: Transform3D in arena.respawn_points:
		var d := INF
		for e in enemies:
			if is_instance_valid(e) and not e.is_dead:
				d = minf(d, e.global_position.distance_to(t.origin))
		if d > best_d:
			best_d = d
			best = t
	return best


func _respawn_player() -> void:
	_respawn_timer = -1.0
	hud.set_countdown(-1)
	var wreck := player
	player = _spawn(player_car, _safest_spawn(), true)
	player.controller = PlayerController.new()
	player.protect()
	camera.follow(player)
	hud.bind(player, camera)
	hud.show_message("BACK IN THE FIGHT", "", 1.5)
	get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(wreck):
			wreck.queue_free())


## Plays the stage's own theme, audio/music/<arena.music>.(ogg|mp3|wav), or the track picked with M in
## the pause menu. Silent when the stage has no theme yet.
func _start_music() -> void:
	var tracks := music_tracks()
	var path := music_pick if music_pick in tracks else _stage_theme(tracks)
	if music == null:
		music = AudioStreamPlayer.new()
		music.bus = AudioSettings.MUSIC_BUS
		music.volume_db = -6.0
		music.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(music)
	music.stop()
	hud.music_label = _track_label(path)
	if path == "":
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", true)
	music.stream = stream
	music.play()


## Every playable track: the themes in audio/music and the ones in audio/music/unpicked.
static func music_tracks() -> Array[String]:
	var out: Array[String] = []
	for dir_path: String in [MUSIC_DIR, MUSIC_DIR + "/unpicked"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			var file := f.trim_suffix(".import").trim_suffix(".remap")
			var path := dir_path + "/" + file
			if file.get_extension().to_lower() in ["ogg", "mp3", "wav"] and not out.has(path):
				out.append(path)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia := MUSIC_ORDER.find(a.get_file().get_basename())
		var ib := MUSIC_ORDER.find(b.get_file().get_basename())
		ia = MUSIC_ORDER.size() if ia < 0 else ia
		ib = MUSIC_ORDER.size() if ib < 0 else ib
		return ia < ib if ia != ib else a < b)
	return out


func _stage_theme(tracks: Array[String]) -> String:
	var wanted: String = arena.get("music") if arena.get("music") else ""
	for t in tracks:
		if t.get_file().get_basename() == wanted and not t.contains("/unpicked/"):
			return t
	return ""


func _track_label(path: String) -> String:
	if path == "":
		return "NONE"
	var label := path.get_file().get_basename().replace("_", " ").to_upper()
	return label + ("  (this stage's theme)" if path == _stage_theme(music_tracks()) else "")


## M in the pause menu: the next track (after the last one, back to the stage's own theme).
func _cycle_music() -> void:
	var tracks := music_tracks()
	if tracks.is_empty():
		return
	var current := music_pick if music_pick in tracks else _stage_theme(tracks)
	var i := tracks.find(current)
	music_pick = tracks[(i + 1) % tracks.size()]
	if music_pick == _stage_theme(tracks):
		music_pick = ""
	_start_music()


func _on_damaged(v: Vehicle, amount: float, _attacker: Vehicle) -> void:
	if amount <= 0.0 or camera == null or not is_instance_valid(player):
		return
	if v == player:
		camera.add_shake(amount / 35.0)
	elif v.global_position.distance_to(player.global_position) < 20.0 and amount > 10.0:
		camera.add_shake(amount / 90.0)


## Slamming into a wall: sparks off the nose, a jolt, the camera kicks if it was you.
func _on_wall_slammed(v: Vehicle, impact: float) -> void:
	var nose := v.global_position + Vector3.UP * 0.8 - v._last_wall_normal * 1.2
	for k in 3:
		FxKit.spark(self, nose + Vector3(randf_range(-0.8, 0.8), randf_range(0, 0.6), randf_range(-0.8, 0.8)), v._last_wall_normal)
	v.hit_react(-v._last_wall_normal, impact * 0.6)
	GameFeel.play("wall_slam", nose, self)
	if v == player:
		camera.add_shake(clampf(impact / 45.0, 0.1, 0.7))


func _on_easter_egg(title: String, text: String) -> void:
	hud.show_message(title, text, 4.0)


func _on_destroyed(v: Vehicle, killer: Vehicle) -> void:
	var by := " by %s" % killer.display_name.to_upper() if is_instance_valid(killer) and killer != v else ""
	hud.add_feed("%s WRECKED%s" % [v.display_name.to_upper(), by])
	if is_instance_valid(player) and v.global_position.distance_to(player.global_position) < 30.0:
		camera.add_shake(0.6)
	if v == player or killer == player: # the kill moment: everything slows for a breath
		GameFeel.slowmo(get_tree(), 0.45, 0.3)
	if state != "playing":
		return
	if v == player:
		lives -= 1
		var who := "Taken out by %s." % killer.display_name if is_instance_valid(killer) and killer != v else "Burned out."
		if lives <= 0:
			state = "lost"
			hud.game_over = true
			hud.set_lives(0)
			hud.show_message("GAME OVER", who + "\nNo lives left.  ENTER / CREATE to try again")
			return
		hud.set_lives(lives - 1)
		_respawn_timer = RESPAWN_DELAY
		hud.show_message("WRECKED", who + "\n%d spare %s left" % [lives - 1, "life" if lives - 1 == 1 else "lives"], RESPAWN_DELAY - 1.0)
		return
	var alive := enemies.filter(func(e: Vehicle): return not e.is_dead).size()
	hud.set_enemies_left(alive)
	if alive == 0:
		state = "won"
		hud.game_over = true
		_respawn_timer = -1.0
		hud.set_countdown(-1)
		hud.show_message("%s WINS" % player.display_name.to_upper(), "%s is quiet again.\nENTER / CREATE to play again" % arena.title.capitalize())


func _restart() -> void:
	get_tree().reload_current_scene()


func _pick_driver(index: int) -> void:
	player_car = drivers[index]
	_restart()
