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

static var player_car := "sweet_tooth" # survives scene reloads
static var full_roster := false # true = FULL_DRIVERS (tests, `-- full`)

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

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.bind(player, camera)
	hud.restart_requested.connect(_restart)
	hud.driver_requested.connect(_pick_driver)
	hud.drivers.assign(drivers.map(func(id: String): return String(Roster.get_car(id).get("name", id))))
	hud.set_enemies_left(enemies.size())
	hud.set_lives(lives - 1)
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
	return v


func _spawn_pickups() -> void:
	for p in arena.weapon_points:
		Pickup.create(self, WeaponData.PICKUP_WEAPONS.pick_random(), p)
	for p in arena.health_points:
		Pickup.create(self, "health", p)
	for p in arena.mega_points:
		Pickup.create(self, "mega", p)


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


## Plays the first track found in audio/music (ogg, mp3 or wav). Silent if the folder is empty.
func _start_music() -> void:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	var tracks: Array[String] = []
	for f in dir.get_files():
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() in ["ogg", "mp3", "wav"] and not tracks.has(file):
			tracks.append(file)
	if tracks.is_empty():
		return
	tracks.sort()
	var stream := load(MUSIC_DIR + "/" + tracks[0]) as AudioStream
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", true)
	music = AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -6.0
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	music.play()


func _on_damaged(v: Vehicle, amount: float, _attacker: Vehicle) -> void:
	if amount <= 0.0 or camera == null or not is_instance_valid(player):
		return
	if v == player:
		camera.add_shake(amount / 35.0)
	elif v.global_position.distance_to(player.global_position) < 20.0 and amount > 10.0:
		camera.add_shake(amount / 90.0)


func _on_easter_egg(title: String, text: String) -> void:
	hud.show_message(title, text, 4.0)


func _on_destroyed(v: Vehicle, killer: Vehicle) -> void:
	var by := " by %s" % killer.display_name.to_upper() if is_instance_valid(killer) and killer != v else ""
	hud.add_feed("%s WRECKED%s" % [v.display_name.to_upper(), by])
	if is_instance_valid(player) and v.global_position.distance_to(player.global_position) < 30.0:
		camera.add_shake(0.6)
	if state != "playing":
		return
	if v == player:
		lives -= 1
		var who := "Taken out by %s." % killer.display_name if is_instance_valid(killer) and killer != v else "Burned out."
		if lives <= 0:
			state = "lost"
			hud.game_over = true
			hud.set_lives(0)
			hud.show_message("GAME OVER", who + "\nNo lives left.  ENTER to try again")
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
		hud.show_message("%s WINS" % player.display_name.to_upper(), "%s is quiet again.\nENTER to play again" % arena.title.capitalize())


func _restart() -> void:
	get_tree().reload_current_scene()


func _pick_driver(index: int) -> void:
	player_car = drivers[index]
	_restart()
