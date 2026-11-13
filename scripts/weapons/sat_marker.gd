class_name SatMarker
extends Node3D
## The SAT target on the ground (owner, round 9: "lazy in every aspect"). A segmented outer ring that
## turns, a dashed inner ring, four wedges pointing in, a broken centre ring and a disc that fills as
## the strike nears. Everything shares one tint: yellow when locked, orange as the strike nears, red
## just before the beam (heat()). The same marker, dim yellow, is the preview while SAT is selected
## (owner: a threat to the enemy, and a way to judge the distance before launching).
## Three draw calls: the turning ring, the fixed marks, the fill.

const YELLOW := Color(1.0, 0.86, 0.12)
const ORANGE := Color(1.0, 0.46, 0.05)
const RED := Color(1.0, 0.07, 0.04)

var radius := 7.5
var spin_speed := 0.5 # rad/s of the outer ring
var _mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _marks: MeshInstance3D
var _fill: MeshInstance3D


static func make(parent: Node, r: float) -> SatMarker:
	var m := SatMarker.new()
	m.radius = r
	parent.add_child(m)
	return m


## The zone's colour at progress p (0 = just fired, 1 = the beam lands).
static func heat(p: float) -> Color:
	if p < 0.35:
		return YELLOW
	if p < 0.7:
		return YELLOW.lerp(ORANGE, (p - 0.35) / 0.35)
	if p < 0.85:
		return ORANGE.lerp(RED, (p - 0.7) / 0.15)
	return RED


func _ready() -> void:
	_mat = _material()
	_fill_mat = _material()
	_ring = _instance(_ring_mesh(), _mat, 0.3)
	_marks = _instance(_marks_mesh(), _mat, 0.28)
	_fill = _instance(_disc_mesh(radius - 0.55, 40), _fill_mat, 0.22)
	set_tint(YELLOW)
	set_fill(0.0)


func _process(delta: float) -> void:
	_ring.rotation.y += spin_speed * delta


func set_tint(c: Color, alpha := 0.9, fill_alpha := 0.18) -> void:
	_mat.albedo_color = Color(c.r, c.g, c.b, alpha)
	_fill_mat.albedo_color = Color(c.r, c.g, c.b, fill_alpha)


## 0..1: how much of the disc is filled (the time that has passed).
func set_fill(f: float) -> void:
	_fill.visible = f > 0.01
	_fill.scale = Vector3(maxf(f, 0.01), 1.0, maxf(f, 0.01))


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _instance(mesh: Mesh, mat: Material, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = y
	add_child(mi)
	return mi


## Twelve thick arcs with gaps (the turning ring) and a thin solid rim outside them.
func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a := i * TAU / 12.0
		_arc(st, radius - 0.6, radius - 0.05, a, a + TAU / 12.0 * 0.72, 4)
	_arc(st, radius + 0.25, radius + 0.4, 0.0, TAU, 48)
	return st.commit()


## The fixed marks: four wedges pointing at the centre, a dashed inner ring, a broken centre ring.
func _marks_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a := i * TAU / 4.0
		var d := Vector3(sin(a), 0, cos(a))
		var s := Vector3(d.z, 0, -d.x)
		var tip := d * radius * 0.42
		var o := d * radius * 0.8
		for v: Vector3 in [tip, o + s * 0.45, o - s * 0.45]:
			st.add_vertex(v)
	for i in 24:
		var a := i * TAU / 24.0
		_arc(st, radius * 0.6, radius * 0.6 + 0.16, a, a + TAU / 24.0 * 0.5, 2)
	for i in 4:
		var a := i * TAU / 4.0 + TAU / 16.0
		_arc(st, 0.55, 0.85, a, a + TAU / 8.0, 4)
	return st.commit()


func _disc_mesh(r: float, steps: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := i * TAU / steps
		var a1 := (i + 1) * TAU / steps
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0, cos(a0)) * r)
		st.add_vertex(Vector3(sin(a1), 0, cos(a1)) * r)
	return st.commit()


static func _arc(st: SurfaceTool, r0: float, r1: float, a0: float, a1: float, steps: int) -> void:
	for k in steps:
		var b0 := lerpf(a0, a1, float(k) / steps)
		var b1 := lerpf(a0, a1, float(k + 1) / steps)
		var d0 := Vector3(sin(b0), 0, cos(b0))
		var d1 := Vector3(sin(b1), 0, cos(b1))
		for v: Vector3 in [d0 * r0, d0 * r1, d1 * r1, d0 * r0, d1 * r1, d1 * r0]:
			st.add_vertex(v)
