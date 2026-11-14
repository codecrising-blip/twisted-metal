class_name GraphicsSettings
extends RefCounted
## Two graphics levels, switched with G in the pause menu and saved in user://settings.cfg.
##   LOW  (default) made for the owner's laptop: Intel HD 5500, OpenGL / Compatibility renderer.
##        No MSAA, no glow, 3D drawn at 85% resolution (the HUD stays sharp), fewer particles,
##        NO real shadows (a soft round shadow under each car instead, like TM2) and NO dynamic lights
##        at all apart from the sun: every omni/spot light, including ones made later by effects
##        (fire pits, tasers, missiles, explosions), is switched off as it enters the scene. On that
##        renderer a light shades everything it touches again, and the merged stage touches it all.
##   HIGH for stronger PCs: 4x MSAA, glow, full resolution, 4096 soft shadows with 4 splits to
##        220 m, full particles, all lights; with the Forward+ renderer also SSAO, SSIL and SSR.
## `-- high` or `-- low` on the command line overrides the saved choice for one run.

const PATH := "user://settings.cfg"
const HEADLIGHT_GROUP := &"headlight_beam"
const EXTRA_LIGHT_GROUP := &"extra_light" # decorative lights: HIGH only

static var high := false
static var _loaded := false
static var _watching := false
const BLOB_GROUP := &"blob_shadow" # soft round shadows under cars: LOW only


static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		high = cfg.get_value("graphics", "high", false)
	var args := OS.get_cmdline_user_args()
	if "high" in args:
		high = true
	elif "low" in args:
		high = false


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("graphics", "high", high)
	cfg.save(PATH)


static func label() -> String:
	return "HIGH" if high else "LOW"


## Particle count multiplier for FxKit.
static func particles() -> float:
	return 1.0 if high else 0.6


static func toggle(tree: SceneTree) -> void:
	high = not high
	save()
	apply(tree)


## Applies the level to the viewport, every sun, every WorldEnvironment and every headlight beam.
static func apply(tree: SceneTree) -> void:
	load_saved()
	if not _watching:
		_watching = true
		tree.node_added.connect(_on_node_added)
	ModelLib.apply_quality() # Blender models: albedo only on LOW, normal + roughness maps on HIGH
	var vp := tree.root
	vp.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0 if high else 0.85
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	for n in vp.find_children("*", "DirectionalLight3D", true, false):
		var sun := n as DirectionalLight3D
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 220.0 if high else 90.0
		sun.shadow_blur = 1.4 if high else 1.0
		sun.shadow_enabled = high
	var forward_plus := RenderingServer.get_rendering_device() != null
	for n in vp.find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env:
			env.glow_enabled = high
		if env and forward_plus:
			env.ssao_enabled = true
			env.ssil_enabled = high
			env.ssr_enabled = high
	for n in tree.get_nodes_in_group(HEADLIGHT_GROUP):
		# Switched on by the player (any level), but the real light only on HIGH; LOW fakes the beam.
		(n as Light3D).visible = (n as Node).get_meta("on", false) and high
	for n in tree.get_nodes_in_group(VehicleFx.HEADLIGHT_FAKE_GROUP):
		VehicleFx.update_headlight_fx(n as Node3D, (n as Node).get_meta("on", false))
	for n in tree.get_nodes_in_group(EXTRA_LIGHT_GROUP):
		(n as Light3D).visible = high
	for n in tree.get_nodes_in_group(BLOB_GROUP):
		(n as Node3D).visible = not high
	for n in vp.find_children("*", "Light3D", true, false):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		l.light_cull_mask = 0xFFFFF if high else 0
		if not (l.is_in_group(HEADLIGHT_GROUP) or l.is_in_group(EXTRA_LIGHT_GROUP)):
			l.visible = high


## LOW: every omni/spot light that appears later (effects) is cut off from everything as it arrives.
static func _on_node_added(n: Node) -> void:
	if not high and n is Light3D and not (n is DirectionalLight3D):
		(n as Light3D).light_cull_mask = 0
		(n as Light3D).visible = false
