class_name ArenaKit
extends Node3D
## Shared building blocks for every stage (LosAngelesArena and ParisArena extend it).
##   - Static batching (owner, session 6): everything that never moves or breaks is merged into ONE mesh
##     per material: batch_mesh / batch_builder / batch_text while building, flush_batch() at the end.
##   - One shared body for the box colliders of merged geometry (solid).
##   - Hand-laid faces that also feed the collision (face, poly_face, band; flush_sheets, flush_collision).

signal easter_egg(title: String, text: String)

var _batch := {} # "material id|shadows" -> {st, mat, shadows}
var _solid_body: StaticBody3D
static var _text_mats := {}


func batch_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, shadows := true, override: Material = null) -> void:
	for i in mesh.get_surface_count():
		var mat: Material = override if override else mesh.surface_get_material(i)
		if mat == null:
			continue
		var key := "%d|%d" % [mat.get_instance_id(), int(shadows)]
		if not _batch.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[key] = {"st": st, "mat": mat, "shadows": shadows}
		(_batch[key].st as SurfaceTool).append_from(mesh, i, xf)


func batch_builder(mb: MeshBuilder, shadows := true, grime := 0.0, xf := Transform3D.IDENTITY) -> void:
	batch_mesh(mb.build_mesh(grime, 0.0, true), xf, shadows)


func batch_text(text: String, xf: Transform3D, font_size: int, pixel_size: float, color: Color, neon := false) -> void:
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = font_size
	tm.pixel_size = pixel_size
	tm.depth = 0.0
	var arrays := tm.get_mesh_arrays()
	if arrays.is_empty() or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var key := "%s|%d" % [color.to_html(), int(neon)]
	if not _text_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		if neon:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_text_mats[key] = m
	batch_mesh(indexed(raw), xf, false, _text_mats[key])


## append_from() drops non-indexed parts once the merged mesh holds indexed ones: index first.
static func indexed(mesh: Mesh, surface := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, surface)
	st.index()
	return st.commit()


func flush_batch() -> void:
	for key: String in _batch:
		var e: Dictionary = _batch[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (e.st as SurfaceTool).commit()
		mi.material_override = e.mat
		if not e.shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batch.clear()


## Hand-laid faces (quads or triangles, any corner order), merged per material like the batch.
## outward = the side the face is seen from (winding and normal follow it); UVs in metres by box
## projection, like MeshBuilder. collide: COL_NONE, COL_GROUND (drivable, group "ground"), COL_WALL, COL_WALL2.
## Round 31 (owner: flips felt "rough, as if something invisible comes out of the ground", a car hanging over a
## corner shook like crazy): ground and walls are solid from their outward side only again. Two-sided faces
## (round 30) let a body that sank a little into a face be pushed out through its back, and at ledges the wall
## below pushed the overhanging car both ways in turn. Only COL_WALL2 (a thin sheet hit from both sides, like a
## rooftop bridge's railing) stays two-sided.
const COL_NONE := 0
const COL_GROUND := 1
const COL_WALL := 2
const COL_WALL2 := 3
var _sheets := {} # "material id|shadows" -> {st, mat, shadows}
var col_ground := PackedVector3Array()
var col_wall := PackedVector3Array()
var col_wall2 := PackedVector3Array()


func face(mat: Material, pts: Array, outward: Vector3, shadows := true, collide := COL_NONE) -> void:
	var key := "%d|%d" % [mat.get_instance_id(), int(shadows)]
	if not _sheets.has(key):
		var nst := SurfaceTool.new()
		nst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sheets[key] = {"st": nst, "mat": mat, "shadows": shadows}
	var st: SurfaceTool = _sheets[key].st
	for k in range(1, pts.size() - 1):
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[k]
		var c: Vector3 = pts[k + 1]
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-8:
			continue
		# The right-hand normal of a front (clockwise) triangle points inward.
		if cr.dot(outward) > 0.0:
			var t := b
			b = c
			c = t
		var n := (c - a).cross(b - a).normalized()
		var an := n.abs()
		st.set_normal(n)
		st.set_color(Color.WHITE)
		for p: Vector3 in [a, b, c]:
			if an.y >= an.x and an.y >= an.z:
				st.set_uv(Vector2(p.x, p.z))
			elif an.x >= an.z:
				st.set_uv(Vector2(p.z, -p.y))
			else:
				st.set_uv(Vector2(p.x, -p.y))
			st.add_vertex(p)
		if collide == COL_GROUND:
			col_ground.append_array([a, b, c])
		elif collide == COL_WALL:
			col_wall.append_array([a, b, c])
		elif collide == COL_WALL2:
			col_wall2.append_array([a, b, c])


## A flat 2D polygon (x, z) at height y, facing up.
func poly_face(mat: Material, poly: PackedVector2Array, y: float, shadows := false, collide := COL_NONE) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		face(mat, [Vector3(poly[idx[t]].x, y, poly[idx[t]].y), Vector3(poly[idx[t + 1]].x, y, poly[idx[t + 1]].y),
			Vector3(poly[idx[t + 2]].x, y, poly[idx[t + 2]].y)], Vector3.UP, shadows, collide)


## A closed band along a polyline (x, z) at height y (curbs, rings); open unless closed.
func band(mat: Material, pts: PackedVector2Array, w: float, y: float, closed := false, collide := COL_NONE) -> void:
	var n := pts.size()
	for i in (n if closed else n - 1):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var d := (b - a).normalized()
		var l := Vector2(-d.y, d.x) * w * 0.5
		face(mat, [Vector3(a.x + l.x, y, a.y + l.y), Vector3(b.x + l.x, y, b.y + l.y), Vector3(b.x - l.x, y, b.y - l.y),
			Vector3(a.x - l.x, y, a.y - l.y)], Vector3.UP, false, collide)


func flush_sheets() -> void:
	for key: String in _sheets:
		var e: Dictionary = _sheets[key]
		var st: SurfaceTool = e.st
		st.index()
		batch_mesh(st.commit(), Transform3D.IDENTITY, e.shadows, e.mat)
	_sheets.clear()


## The collected collision faces as two bodies: drivable ("Ground", group ground) and walls.
func flush_collision() -> void:
	for pair: Array in [[col_ground, "Ground", true, false], [col_wall, "Walls", false, false], [col_wall2, "ThinWalls", false, true]]:
		var faces: PackedVector3Array = pair[0]
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = pair[1]
		if pair[2]:
			body.add_to_group(&"ground")
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = pair[3]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	col_ground = PackedVector3Array()
	col_wall = PackedVector3Array()
	col_wall2 = PackedVector3Array()


func _solids() -> StaticBody3D:
	if _solid_body == null:
		_solid_body = StaticBody3D.new()
		_solid_body.name = "MergedColliders"
		_solid_body.collision_layer = 1
		_solid_body.collision_mask = 0
		add_child(_solid_body)
	return _solid_body


## A box collider (no visual) in arena space.
func solid(size: Vector3, xf: Transform3D) -> void:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.transform = xf
	_solids().add_child(shape)


func scatter(mesh: Mesh, xforms: Array[Transform3D], shadows := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi
