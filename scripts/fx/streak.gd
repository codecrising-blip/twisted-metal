class_name Streak
extends MeshInstance3D
## A glowing ribbon left behind a moving node (missile trails, TM style: each missile has its own
## colour and length). One draw call: the ribbon is rebuilt every frame from the last positions
## and always faces the camera. It lives in the world, not on the missile, so after the missile
## is gone the trail fades out where it was.

var follow: Node3D
var color := Color.WHITE
var length_time := 0.4 # seconds of history = trail length (speed x time)
var width := 0.5

var _points: Array[Vector3] = []
var _times: Array[float] = []
var _t := 0.0
var _im: ImmediateMesh

static var _mat: StandardMaterial3D


static func attach(target: Node3D, trail_color: Color, seconds: float, trail_width: float) -> Streak:
	var s := Streak.new()
	s.follow = target
	s.color = trail_color
	s.length_time = seconds
	s.width = trail_width
	target.get_parent().add_child(s)
	return s


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.disable_receive_shadows = true
	material_override = _mat


func _process(delta: float) -> void:
	_t += delta
	var alive := is_instance_valid(follow) and follow.is_inside_tree()
	if alive:
		var p := follow.global_position
		if _points.is_empty() or _points[_points.size() - 1].distance_squared_to(p) > 0.01:
			_points.append(p)
			_times.append(_t)
	while not _times.is_empty() and _t - _times[0] > length_time:
		_times.pop_front()
		_points.pop_front()
	if not alive and _points.size() < 2:
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _points.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.UP * 100.0
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := _points[i]
		var along := (_points[mini(i + 1, n - 1)] - _points[maxi(i - 1, 0)])
		var side := along.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		var fresh := 1.0 - clampf((_t - _times[i]) / length_time, 0.0, 1.0) # 1 at the missile, 0 at the tail end
		var w := width * (0.25 + 0.75 * fresh)
		var c := color.lerp(Color.WHITE, 0.2 * fresh * fresh * fresh) # hot white right behind the missile
		c.a = 0.9 * fresh * fresh
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * w * 0.5)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * w * 0.5)
	_im.surface_end()
