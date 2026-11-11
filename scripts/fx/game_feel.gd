class_name GameFeel
extends RefCounted
## "Game feel" (owner's reference videos, session 6): every hit needs an answer you can see and feel.
## Hit-stop on big hits, a short slow-motion on kills, camera shake by distance, muzzle flashes,
## a white flash and shockwave ring on explosions, scorch marks left on the ground, and a sound
## hook. Cheap on purpose (the owner's laptop): flashes are a single short-lived mesh, no lights.
## Skipped on purpose (owner): squash/stretch (toy look) and floating damage numbers.

const MAX_SCORCH := 14

static var camera: ChaseCamera # set by main.gd: shakes are scaled by distance to it
static var hud: Node # set by main.gd: screen white-outs
static var _time_until := 0 # ms: an active hit-stop / slow-motion ends then
static var _scorches: Array[Node3D] = []
static var _sounds := {} # name -> AudioStream or null (missing)
static var _flash_mat: StandardMaterial3D
static var _ring_mat: StandardMaterial3D
static var _scorch_mat: StandardMaterial3D


## Freeze the action for a blink (big hits). Real seconds, not game seconds.
static func hitstop(tree: SceneTree, seconds := 0.06, scale := 0.05) -> void:
	_slow(tree, seconds, scale)


## Slow motion for a moment (a kill).
static func slowmo(tree: SceneTree, seconds := 0.45, scale := 0.3) -> void:
	_slow(tree, seconds, scale)


static func _slow(tree: SceneTree, seconds: float, scale: float) -> void:
	if tree == null or DisplayServer.get_name() == "headless":
		return # tests run in real time
	_time_until = maxi(_time_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = minf(Engine.time_scale, scale)
	if not is_instance_valid(_ticker):
		_ticker = _Ticker.new()
		_ticker.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_ticker)


static var _ticker: Node


## Puts the clock back to normal speed when the hit-stop / slow motion is over (real time).
class _Ticker extends Node:
	func _process(_delta: float) -> void:
		if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= GameFeel._time_until:
			Engine.time_scale = 1.0


## Camera shake that fades with distance from the camera (amount ~0.1 small .. 1.0 huge).
static func shake(pos: Vector3, amount: float, reach := 45.0) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var d := camera.global_position.distance_to(pos)
	if d < reach:
		camera.add_shake(amount * (1.0 - d / reach))


## A sound by name from res://audio/sfx/<name>.ogg or .wav, if the owner has dropped it in. The pitch
## is nudged every time so repeats don't sound fake. Names: see audio/sfx/README.md.
static func play(name: String, pos: Vector3, parent: Node, volume_db := 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not _sounds.has(name):
		var stream: AudioStream = null
		for ext in ["ogg", "wav", "mp3"]:
			var path := "res://audio/sfx/%s.%s" % [name, ext]
			if ResourceLoader.exists(path):
				stream = load(path)
				break
		_sounds[name] = stream
	var s: AudioStream = _sounds[name]
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.unit_size = 18.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## White-hot ball that pops and fades: the first frame of every explosion or launch.
static func flash(parent: Node, pos: Vector3, radius: float, color := Color(1.0, 0.9, 0.7), time := 0.12) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mi.mesh = sphere
	mi.material_override = _flash_mat.duplicate()
	(mi.material_override as StandardMaterial3D).albedo_color = color
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.4
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, time)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Flat ring that races out along the ground (big blasts).
static func shockwave(parent: Node, pos: Vector3, radius: float, color := Color(1.0, 0.8, 0.5)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	mi.mesh = torus
	mi.material_override = _ring_mat.duplicate()
	(mi.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.45)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.3
	mi.scale = Vector3(1.0, 0.3, 1.0)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.3, radius), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


## Dark burn mark on the ground (the fight leaves a mess). Only the newest few stay.
static func scorch(parent: Node, pos: Vector3, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var ground := Specials.ground_below(parent, pos + Vector3.UP)
	if pos.y - ground.y > 2.5:
		return # went off in the air
	if _scorch_mat == null:
		_scorch_mat = StandardMaterial3D.new()
		_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_scorch_mat.albedo_texture = FxKit.soft_texture()
		_scorch_mat.albedo_color = Color(0.03, 0.025, 0.02, 0.8)
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	mi.mesh = quad
	mi.material_override = _scorch_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = ground + Vector3.UP * 0.12
	mi.rotation.y = randf() * TAU
	_scorches.assign(_scorches.filter(func(n: Node3D) -> bool: return is_instance_valid(n)))
	_scorches.append(mi)
	while _scorches.size() > MAX_SCORCH:
		_scorches.pop_front().queue_free()


## Launch flash at a gun or launcher: a quick bright pop, pointing the way the shot goes.
static func muzzle(parent: Node, pos: Vector3, color: Color, size := 1.0) -> void:
	flash(parent, pos, 0.9 * size, color.lerp(Color.WHITE, 0.5), 0.08)


## The first time an effect is drawn its shaders are built, which stalls a frame or several (the
## lag at the start and on the first hit). Draw one of each, tiny and far off, as the match starts.
static func prewarm(parent: Node3D, cam: Camera3D) -> void:
	if parent == null or cam == null or not parent.is_inside_tree():
		return
	var p := cam.global_position - cam.global_basis.z * 40.0 + Vector3.DOWN * 3.0
	FxKit.explosion(parent, p, 1.0)
	FxKit.spark(parent, p, Vector3.UP)
	shockwave(parent, p, 1.0)
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = p
	var fire := FxKit.fire(0.3, 6)
	holder.add_child(fire)
	fire.emitting = true
	var smoke := FxKit.smoke(0.3, 4)
	holder.add_child(smoke)
	smoke.emitting = true
	holder.get_tree().create_timer(0.6).timeout.connect(holder.queue_free)


## White-out like a flash-bang (napalm right on you: 0.3 s, a SAT strike: 1 s).
static func flash_bang(seconds: float) -> void:
	if hud and is_instance_valid(hud) and hud.has_method("flash_bang"):
		hud.flash_bang(seconds)
