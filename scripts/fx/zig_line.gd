class_name ZigLine
extends Node3D
## A line between two world points made of stretched boxes. With jitter it is a lightning bolt
## (taser); without, a chain or cable. Call draw() every frame; it keeps itself at the origin.

var segments := 10
var thickness := 0.08
var material: Material

var _parts: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	for i in segments:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_parts.append(mi)


## sag pulls the middle down (chains); jitter shakes points sideways (lightning).
func draw(from: Vector3, to: Vector3, jitter := 0.0, sag := 0.0, width := -1.0) -> void:
	var w := thickness if width < 0.0 else width
	var points: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		var p := from.lerp(to, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		if jitter > 0.0 and i > 0 and i < segments:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter
		points.append(p)
	for i in segments:
		var a := points[i]
		var b := points[i + 1]
		var mi := _parts[i]
		var length := a.distance_to(b)
		if length < 0.001:
			mi.visible = false
			continue
		mi.visible = true
		var dir := (b - a) / length
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		mi.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3(w, w, length)), (a + b) * 0.5)


