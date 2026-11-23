class_name ModelLib
## Models made in Blender (round 10): assets/models/<file>.glb plus baked textures
## <atlas>_albedo / _normal / _orm (.webp). The scripts that make them are in tools/blender/.
## A .glb holds named meshes; their surfaces carry placeholder materials that are swapped here:
##   "atlas" -> the baked texture set (weathered paint, rust, dust, occlusion baked in)
##   "glass" -> dark glass        "glow" -> unshaded lights (colour from the vertices)
## Graphics LOW uses the albedo only (occlusion and grime are baked into it); HIGH adds the normal
## map and the roughness / metallic map.

const DIR := "res://assets/models/"

static var _scenes := {} # file -> Node3D (kept as a template, never in the tree)
static var _cutouts := {}
static var _atlas := {} # atlas name -> StandardMaterial3D
static var _meshes := {} # "file|node|atlas" -> ArrayMesh
static var _glass: StandardMaterial3D
static var _glow: StandardMaterial3D
static var _tints := {}


static func has(file: String) -> bool:
	return ResourceLoader.exists(DIR + file + ".glb")


static func _template(file: String) -> Node3D:
	if not _scenes.has(file):
		var ps := load(DIR + file + ".glb") as PackedScene
		_scenes[file] = ps.instantiate() if ps else null
	return _scenes[file]


## The baked material of an atlas. One per atlas, shared by everything that uses it.
static func atlas(name: String) -> StandardMaterial3D:
	if _atlas.has(name):
		return _atlas[name]
	var m := StandardMaterial3D.new()
	m.resource_name = "atlas:" + name
	m.albedo_texture = load(DIR + name + "_albedo.webp")
	m.set_meta("atlas", name)
	_atlas[name] = m
	_quality(m)
	return m


static func _quality(m: StandardMaterial3D) -> void:
	var name: String = m.get_meta("atlas")
	if GraphicsSettings.high:
		var orm: Texture2D = load(DIR + name + "_orm.webp")
		m.normal_enabled = true
		m.normal_texture = load(DIR + name + "_normal.webp")
		m.roughness = 1.0
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 0.75
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	else:
		m.normal_enabled = false
		m.normal_texture = null
		m.roughness_texture = null
		m.metallic_texture = null
		m.roughness = 0.82
		m.metallic = 0.0


## Called when the graphics level changes.
static func apply_quality() -> void:
	for name: String in _atlas:
		_quality(_atlas[name])


static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.02, 0.025, 0.03, 0.9)
		_glass.roughness = 0.12
		_glass.metallic = 0.3
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _glass


## A see-through picture (Paris's iron railings, round 27): <name>.png beside the .glb, alpha-tested,
## both sides drawn.
static func cutout(name: String) -> StandardMaterial3D:
	if not _cutouts.has(name):
		var m := StandardMaterial3D.new()
		m.resource_name = "cutout:" + name
		m.albedo_texture = load(DIR + name + ".png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6
		m.metallic = 0.4
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_cutouts[name] = m
	return _cutouts[name]


## Round 29: stained glass lit from inside (Brimstone): its own picture, glowing through.
static func stained(name: String) -> StandardMaterial3D:
	if not _cutouts.has(name):
		var m := StandardMaterial3D.new()
		m.resource_name = "stained:" + name
		var tex: Texture2D = load(DIR + name + ".png")
		m.albedo_texture = tex
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission_energy_multiplier = 0.85
		m.roughness = 0.15
		m.metallic = 0.2
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_cutouts[name] = m
	return _cutouts[name]


## Lights: unshaded, colour from the vertices (written in Blender).
static func glow() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.vertex_color_use_as_albedo = true
	return _glow


## A light in one colour (for meshes whose lights are white in the file, like the pickup pad).
static func glow_tint(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _tints.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		_tints[key] = m
	return _tints[key]


## The mesh of node `node` in <file>.glb with its materials in place. atlas_name defaults to the file.
static func mesh(file: String, node: String, atlas_name := "") -> ArrayMesh:
	var key := "%s|%s|%s" % [file, node, atlas_name]
	if _meshes.has(key):
		return _meshes[key]
	var root := _template(file)
	var src: MeshInstance3D = null
	if root:
		src = root.find_child(node, true, false) as MeshInstance3D
	if src == null or src.mesh == null:
		push_warning("ModelLib: no mesh '%s' in %s.glb" % [node, file])
		_meshes[key] = null
		return null
	var out := (src.mesh as ArrayMesh).duplicate() as ArrayMesh
	for i in out.get_surface_count():
		var slot := out.surface_get_material(i)
		var slot_name := (slot.resource_name if slot else "").to_lower()
		if slot_name.begins_with("glass"):
			out.surface_set_material(i, glass())
		elif slot_name.begins_with("glow"):
			out.surface_set_material(i, glow())
		elif slot_name.begins_with("rail"):
			out.surface_set_material(i, cutout(file + "_rail"))
		elif slot_name.begins_with("stained"):
			out.surface_set_material(i, stained(file + "_stained"))
		else:
			out.surface_set_material(i, atlas(atlas_name if atlas_name != "" else file))
	_meshes[key] = out
	return out


static func instance(file: String, node: String, atlas_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(file, node, atlas_name)
	mi.name = node
	return mi


## Index of the surface whose material is the glow material (-1 if none): to tint or switch off lights.
static func glow_surface(m: Mesh) -> int:
	if m == null:
		return -1
	for i in m.get_surface_count():
		if m.surface_get_material(i) == glow():
			return i
	return -1


## Where the markers (empties) and meshes of a file sit: node name -> Transform3D in the file's space.
static func marks(file: String) -> Dictionary:
	var out := {}
	var root := _template(file)
	if root == null:
		return out
	for n in root.find_children("*", "Node3D", true, false):
		out[String(n.name)] = _to_root(n as Node3D, root)
	return out


static func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
