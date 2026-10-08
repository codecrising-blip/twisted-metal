extends Node3D
## Junkyard deathmatch: Sweet Tooth (player) against the AI. Last car running wins.

const PLAYER_CAR := "sweet_tooth"
const ENEMY_CARS := ["outlaw", "junkyard_dog"]
const MUSIC_DIR := "res://audio/music"

var state := "playing" # playing | won | lost
var player: Vehicle
var enemies: Array[Vehicle] = []
var arena: JunkyardArena
var camera: ChaseCamera
var hud: Hud
var music: AudioStreamPlayer


func _ready() -> void:
	InputSetup.setup()
	_environment()

	arena = JunkyardArena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build()

	player = _spawn(PLAYER_CAR, arena.spawn_points[0], true)
	player.controller = PlayerController.new()
	for i in ENEMY_CARS.size():
		var e := _spawn(ENEMY_CARS[i], arena.spawn_points[i + 1], false)
		e.controller = AIDriver.new()
		e.auto_target = false
		enemies.append(e)
	_spawn_pickups()

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
	hud.set_enemies_left(enemies.size())
	hud.show_message("JUNKYARD", "%s  -  %s\n%s" % [player.display_name, player.stats.get("driver", ""), player.stats.get("tagline", "")], 4.0)

	_start_music()


func _spawn(id: String, xform: Transform3D, is_player: bool) -> Vehicle:
	var v := Vehicle.new()
	v.name = id.to_pascal_case()
	v.setup(id, is_player)
	add_child(v)
	v.global_transform = xform
	v.destroyed.connect(_on_destroyed)
	v.damaged.connect(_on_damaged)
	return v


func _spawn_pickups() -> void:
	for p in arena.weapon_points:
		var w := Pickup.new()
		w.kind = WeaponData.PICKUP_WEAPONS.pick_random()
		add_child(w)
		w.global_position = p
	for p in arena.health_points:
		var h := Pickup.new()
		h.kind = "health"
		h.random_weapon = false
		add_child(h)
		h.global_position = p


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.03, 0.05)
	sky_mat.sky_horizon_color = Color(0.2, 0.12, 0.09)
	sky_mat.ground_horizon_color = Color(0.12, 0.08, 0.07)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.24, 0.27)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.11, 0.1, 0.11)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.5
	# Forward+ only extras. The project defaults to the Compatibility renderer (OpenGL)
	# because Forward+ (Vulkan) crashed on the owner's PC.
	if RenderingServer.get_rendering_device() != null: # Forward+ or Mobile (Vulkan)
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.5, 0.48, 0.46)
		env.ssao_enabled = true
		env.ssr_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.8
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.light_energy = 0.85
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	moon.rotation_degrees = Vector3(-48, -35, 0)
	add_child(moon)


## Plays the first track found in audio/music (ogg, mp3 or wav). Silent if the folder is empty.
func _start_music() -> void:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	var tracks: Array[String] = []
	for f in dir.get_files():
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in ["ogg", "mp3", "wav"] and not tracks.has(name):
			tracks.append(name)
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
	if amount <= 0.0 or camera == null:
		return
	if v == player:
		camera.add_shake(amount / 35.0)
	elif v.global_position.distance_to(player.global_position) < 20.0 and amount > 10.0:
		camera.add_shake(amount / 90.0)


func _on_destroyed(v: Vehicle, killer: Vehicle) -> void:
	var by := " by %s" % killer.display_name.to_upper() if is_instance_valid(killer) else ""
	hud.add_feed("%s WRECKED%s" % [v.display_name.to_upper(), by])
	if v.global_position.distance_to(player.global_position) < 30.0:
		camera.add_shake(0.6)
	if state != "playing":
		return
	if v == player:
		state = "lost"
		hud.game_over = true
		var who := "Taken out by %s." % killer.display_name if is_instance_valid(killer) else "Burned out."
		hud.show_message("YOU'RE WRECKED", who + "\nENTER to try again")
		return
	var alive := enemies.filter(func(e: Vehicle): return not e.is_dead).size()
	hud.set_enemies_left(alive)
	if alive == 0:
		state = "won"
		hud.game_over = true
		hud.show_message("%s WINS" % player.display_name.to_upper(), "The Junkyard is quiet again.\nENTER to play again")


func _restart() -> void:
	get_tree().reload_current_scene()
