class_name Bolt
extends MeshInstance3D
## Lightning drawn the way the owner's reference clips build it (round 9, juice guide section 2): a
## jagged main path made by midpoint displacement (never a regular zigzag), thick at the source and
## thinning toward the end, a white-hot core inside two layers of coloured glow, branches splitting off,
## and a faint afterimage of the previous flash. Every strand is a camera-facing ribbon in ONE dynamic
## mesh with one additive material: the whole bolt is a single draw call.
## Use: begin(), add any number of strands with strand() / zap(), then finish().

var tint := Color(0.35, 0.6, 1.0) # the glow colour (the core is always near white)

var _im := ImmediateMesh.new()
var _open := false
static var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.no_depth_test = false
	material_override = _mat
	# The mesh moves every frame, so its bounds are unknown to the culler: never cull it.
	extra_cull_margin = 16384.0


func begin() -> void:
	_im.clear_surfaces()
	_open = false


func finish() -> void:
	if _open:
		_im.surface_end()
	_open = false


## A jagged path from a to b: midpoint displacement, `levels` deep (2^levels segments), sideways
## kicks up to `rough` x the length of each piece.
static func jagged(a: Vector3, b: Vector3, levels := 4, rough := 0.22) -> Array[Vector3]:
	var pts: Array[Vector3] = [a, b]
	for l in levels:
		var next: Array[Vector3] = [pts[0]]
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var seg := q - p
			var len := seg.length()
			var side := seg.cross(Vector3.UP)
			if side.length() < 0.01:
				side = seg.cross(Vector3.RIGHT)
			var up := side.cross(seg).normalized()
			side = side.normalized()
			var kick := (side * randf_range(-1, 1) + up * randf_range(-0.7, 0.7)) * len * rough
			next.append((p + q) * 0.5 + kick)
			next.append(q)
		pts = next
	return pts


## One lightning strand through `pts`: width w0 at the start tapering to w1 at the end, drawn as an
## outer glow, an inner glow and a white core. alpha scales it all (afterimages, branches).
func strand(pts: Array[Vector3], w0: float, w1: float, alpha := 1.0) -> void:
	var outer := Color(tint.r, tint.g, tint.b, 0.3 * alpha)
	var inner := tint.lerp(Color.WHITE, 0.25)
	inner.a = 0.7 * alpha
	var core := Color(1.0, 1.0, 1.0, 0.95 * alpha)
	_ribbon(pts, w0 * 7.0, w1 * 7.0, outer)
	_ribbon(pts, w0 * 2.8, w1 * 2.8, inner)
	_ribbon(pts, w0, w1, core)


## A lightning strike from a to b with branches. strength 0..1 thickens it.
func zap(a: Vector3, b: Vector3, strength: float, branches := 3, alpha := 1.0) -> Array[Vector3]:
	var pts := jagged(a, b, 4, 0.2 + 0.08 * strength)
	var w0 := 0.07 + 0.07 * strength
	strand(pts, w0, w0 * 0.35, alpha)
	for k in branches:
		var i := randi_range(2, pts.size() - 4)
		var start := pts[i]
		var along := (pts[i + 1] - pts[i]).normalized()
		var off := (along + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1))).normalized()
		var end := start + off * randf_range(0.8, 2.4) * (0.7 + strength)
		var t := float(i) / pts.size()
		strand(jagged(start, end, 2, 0.3), lerpf(w0, w0 * 0.35, t) * 0.6, 0.005, alpha * 0.8)
	return pts


## A camera-facing ribbon through the points (vertex colours, additive).
func _ribbon(pts: Array[Vector3], w0: float, w1: float, col: Color) -> void:
	if pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := cam.global_position if cam else Vector3(0, 50, 0)
	if not _open:
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_open = true
	var n := pts.size()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in n:
		var p := pts[i]
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var to_eye := (eye - p).normalized()
		var side := dir.cross(to_eye)
		if side.length() < 0.001:
			side = Vector3.UP
		side = side.normalized() * lerpf(w0, w1, float(i) / (n - 1)) * 0.5
		var l := p + side
		var r := p - side
		if i > 0:
			for v: Vector3 in [prev_l, prev_r, r, prev_l, r, l]:
				_im.surface_set_color(col)
				_im.surface_add_vertex(v)
		prev_l = l
		prev_r = r
