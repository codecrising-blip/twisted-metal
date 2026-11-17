class_name TmbFire
## Fire the Twisted Metal: Black way (round 17, the owner's standard for the whole game): upright
## sheets of streaky flame (tmb_fire.gdshader) standing on whatever burns. A burning body gets one
## on each main bone, so the flames move with every limb and rise from it whatever pose it is in;
## set() drives a whole group: how strong (0 = out) and how far the tips are swept back.

const SHADER := preload("res://scripts/fx/tmb_fire.gdshader")

## Bones of the driver dummies that carry a sheet, with its (width, height).
const BODY_SHEETS := {
	"chest": Vector2(0.75, 1.2), "spine": Vector2(0.65, 1.0), "hips": Vector2(0.62, 0.85), "head": Vector2(0.48, 0.85),
	"upper_arm.L": Vector2(0.3, 0.55), "upper_arm.R": Vector2(0.3, 0.55),
	"forearm.L": Vector2(0.3, 0.6), "forearm.R": Vector2(0.3, 0.6),
	"thigh.L": Vector2(0.36, 0.62), "thigh.R": Vector2(0.36, 0.62),
	"shin.L": Vector2(0.28, 0.5), "shin.R": Vector2(0.28, 0.5),
}


## One sheet standing on `parent` at `at` (its base), `size` = (width, height) in metres.
static func sheet(parent: Node3D, size: Vector2, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, size.y * 0.42, 0) # the base sits a little below the point
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("speed", randf_range(2.1, 2.8))
	mat.set_shader_parameter("intensity", 0.0) # out until something lights it (set_all)
	mi.material_override = mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0 # the sheet is turned in the shader
	mi.position = at
	parent.add_child(mi)
	return mi


## Sheets on a skinned body (the driver dummies): one per bone in BODY_SHEETS, riding the bone.
static func on_body(model: Node3D) -> Array:
	var sheets: Array = []
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone: String in BODY_SHEETS:
		if skel.find_bone(bone) < 0:
			continue
		var att := BoneAttachment3D.new()
		skel.add_child(att)
		att.bone_name = bone
		sheets.append(sheet(att, BODY_SHEETS[bone]))
	return sheets


## Drives a group of sheets: `strength` 0..1 and `lean`, the world offset of the tips (put it against
## the direction of travel so a runner trails flames).
static func set_all(sheets: Array, strength: float, lean := Vector3.ZERO) -> void:
	for s in sheets:
		if is_instance_valid(s):
			var mat := (s as MeshInstance3D).material_override as ShaderMaterial
			mat.set_shader_parameter("intensity", strength)
			mat.set_shader_parameter("lean", lean)
			(s as MeshInstance3D).visible = strength > 0.01
