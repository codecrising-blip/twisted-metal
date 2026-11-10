class_name MeshBuilder
extends RefCounted
## Builds detailed models from code and merges every part that shares a material into one mesh,
## so a car with hundreds of parts costs only a handful of draw calls (important on the owner's
## Intel HD 5500). Parts are added with a Transform3D; call commit() once at the end.
##
## Winding: Godot treats clockwise triangles (seen from outside) as front faces. Every helper here
## decides the winding from an outward direction, so callers never think about it.
##   box()       chamfered box (bevelled edges catch the light; plain boxes look like toys)
##   loft()      smooth body through rounded-rectangle sections along Z (car bodies, cabins, fenders)
##   lathe()     surface of revolution around Y from a (radius, y) profile (wheels, lamps, tubes, heads)
##   cylinder(), sphere(), torus(), quad(), tri()

var _masters := {} # Material -> SurfaceTool


func _master(mat: Material) -> SurfaceTool:
	if not _masters.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_masters[mat] = st
	return _masters[mat]


func _flush(mat: Material, st: SurfaceTool, xf: Transform3D, smooth: bool) -> void:
	# Every part reaches the master indexed: append_from() drops the triangles of a non-indexed
	# part once the master holds indexed ones. Smooth parts share vertices before normals are made;
	# flat parts are indexed after, so faces with different normals keep separate vertices.
	if smooth:
		st.index()
		st.generate_normals()
	else:
		st.generate_normals()
		st.index()
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		_master(mat).append_from(mesh, 0, xf)


## One mesh per material under `parent`. Returns the created MeshInstance3D nodes.
## grime 0..1 bakes road dust into the vertex colors: brown dirt rising from the bottom (up to
## about 1.4 m), darker undersides and a little blotchy variation, so cars sit in the world instead
## of looking factory clean. y_offset = height of `parent` above the ground (for parts on the roof).
## Materials show it when vertex_color_use_as_albedo is on (every MatKit material).
func commit(parent: Node3D, shadows := true, grime := 0.0, y_offset := 0.0) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mat: Material in _masters:
		var mi := MeshInstance3D.new()
		mi.mesh = _with_grime((_masters[mat] as SurfaceTool).commit(), grime, y_offset)
		mi.material_override = mat
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	_masters.clear()
	return out


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# Cross product of a clockwise (front) triangle points inward in Godot's convention.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(st, a, b, c, outward)
	_tri(st, a, c, d, outward)


## Single triangle / quad in local space of `xf` (flat).
func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, xf := Transform3D.IDENTITY) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, a, b, c, outward)
	_flush(mat, st, xf, false)


func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, xf := Transform3D.IDENTITY) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, a, b, c, d, outward)
	_flush(mat, st, xf, false)


## Box with chamfered edges. size = full size; bevel = chamfer width (0 = sharp box).
func box(mat: Material, size: Vector3, xf := Transform3D.IDENTITY, bevel := 0.04) -> void:
	var h := size * 0.5
	var c := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if c <= 0.0005:
		for axis in 3:
			for s: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				var v := Vector3.ZERO
				u[(axis + 1) % 3] = h[(axis + 1) % 3]
				v[(axis + 2) % 3] = h[(axis + 2) % 3]
				var ctr := n * h[axis]
				_quad(st, ctr - u - v, ctr + u - v, ctr + u + v, ctr - u + v, n)
		_flush(mat, st, xf, false)
		return
	# p(corner signs, which face the point belongs to)
	var p := func(sx: float, sy: float, sz: float, axis: int) -> Vector3:
		var q := Vector3(sx * (h.x - c), sy * (h.y - c), sz * (h.z - c))
		q[axis] = [sx, sy, sz][axis] * h[axis]
		return q
	# Six main faces.
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			var pts: Array[Vector3] = []
			for k in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var sg := Vector3.ZERO
				sg[axis] = s
				sg[a1] = k[0]
				sg[a2] = k[1]
				pts.append(p.call(sg.x, sg.y, sg.z, axis))
			var n := Vector3.ZERO
			n[axis] = s
			_quad(st, pts[0], pts[1], pts[2], pts[3], n)
	# Twelve edge bevels.
	for axis in 3: # edge runs along this axis
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = []
				for e: float in [-1.0, 1.0]:
					var sg := Vector3.ZERO
					sg[axis] = e
					sg[a1] = s1
					sg[a2] = s2
					pts.append(p.call(sg.x, sg.y, sg.z, a1))
					pts.append(p.call(sg.x, sg.y, sg.z, a2))
				var n := Vector3.ZERO
				n[a1] = s1
				n[a2] = s2
				_quad(st, pts[0], pts[1], pts[3], pts[2], n)
	# Eight corner triangles.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_tri(st, p.call(sx, sy, sz, 0), p.call(sx, sy, sz, 1), p.call(sx, sy, sz, 2), Vector3(sx, sy, sz))
	_flush(mat, st, xf, false)


## Section for loft(): a rounded rectangle at depth z.
##   cy = center height, hw = half width at the bottom, tw = half width at the top (taper),
##   hh = half height, r = corner radius.
static func section(z: float, cy: float, hw: float, hh: float, r := 0.1, tw := -1.0) -> Dictionary:
	return {"z": z, "cy": cy, "hw": hw, "tw": hw if tw < 0.0 else tw, "hh": hh, "r": r}


static func _ring(s: Dictionary, seg: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var hh: float = s.hh
	var r: float = minf(s.r, minf(hh, minf(s.hw, s.tw)) * 0.95)
	var corners := [
		[Vector2(s.hw - r, s.cy - hh + r), -PI * 0.5],
		[Vector2(s.tw - r, s.cy + hh - r), 0.0],
		[Vector2(-s.tw + r, s.cy + hh - r), PI * 0.5],
		[Vector2(-s.hw + r, s.cy - hh + r), PI],
	]
	for c in corners:
		var ctr: Vector2 = c[0]
		var a0: float = c[1]
		for i in seg + 1:
			var a := a0 + PI * 0.5 * float(i) / seg
			pts.append(Vector3(ctr.x + cos(a) * r, ctr.y + sin(a) * r, s.z))
	return pts


## Smooth skin through sections (ordered by z). Caps close the ends.
func loft(mat: Material, sections: Array, xf := Transform3D.IDENTITY, seg := 3, cap_start := true, cap_end := true, cap_mat: Material = null) -> void:
	var rings: Array[PackedVector3Array] = []
	for s: Dictionary in sections:
		rings.append(_ring(s, seg))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings[0].size()
	for i in rings.size() - 1:
		var r0 := rings[i]
		var r1 := rings[i + 1]
		var axis0 := Vector3(0, sections[i].cy, sections[i].z)
		var axis1 := Vector3(0, sections[i + 1].cy, sections[i + 1].z)
		for j in n:
			var k := (j + 1) % n
			var mid := (r0[j] + r0[k] + r1[j] + r1[k]) * 0.25
			var out := mid - (axis0 + axis1) * 0.5
			out.z = 0.0
			_quad(st, r0[j], r0[k], r1[k], r1[j], out)
	_flush(mat, st, xf, true)
	for end in 2:
		if (end == 0 and not cap_start) or (end == 1 and not cap_end):
			continue
		var ring := rings[0] if end == 0 else rings[rings.size() - 1]
		var sec: Dictionary = sections[0] if end == 0 else sections[sections.size() - 1]
		var ctr := Vector3(0, sec.cy, sec.z)
		var dir := Vector3(0, 0, -1.0 if end == 0 else 1.0)
		if sections.size() > 1 and float(sections[sections.size() - 1].z) < float(sections[0].z):
			dir = -dir
		var cap := SurfaceTool.new()
		cap.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in n:
			_tri(cap, ctr, ring[j], ring[(j + 1) % n], dir)
		_flush(cap_mat if cap_mat else mat, cap, xf, false)


## Surface of revolution around local Y. profile = (radius, y) points traced with the solid on the
## left (bottom-outer upward for a closed shape, counter-clockwise), so the outward side is known.
func lathe(mat: Material, profile: PackedVector2Array, xf := Transform3D.IDENTITY, seg := 16, smooth := true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var d := p1 - p0
		var n2 := Vector2(d.y, -d.x) # right of travel = outward
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var am := (a0 + a1) * 0.5
			var out := Vector3(cos(am) * n2.x, n2.y, sin(am) * n2.x)
			if p0.x > 0.0001:
				_tri(st, v00, v01, v11 if p1.x > 0.0001 else v10, out)
			if p1.x > 0.0001:
				_tri(st, v00, v11, v10, out)
	_flush(mat, st, xf, smooth)


func cylinder(mat: Material, r: float, h: float, xf := Transform3D.IDENTITY, seg := 12, top_r := -1.0, caps := true) -> void:
	var tr := r if top_r < 0.0 else top_r
	# Sharp rim: sides smooth, caps flat.
	lathe(mat, PackedVector2Array([Vector2(r, -h * 0.5), Vector2(tr, h * 0.5)]), xf, seg, true)
	if caps:
		lathe(mat, PackedVector2Array([Vector2(0.0, -h * 0.5), Vector2(r, -h * 0.5)]), xf, seg, false)
		lathe(mat, PackedVector2Array([Vector2(tr, h * 0.5), Vector2(0.0, h * 0.5)]), xf, seg, false)


func sphere(mat: Material, r: float, xf := Transform3D.IDENTITY, seg := 14, rings := 8) -> void:
	var prof := PackedVector2Array()
	for i in rings + 1:
		var a := -PI * 0.5 + PI * float(i) / rings
		prof.append(Vector2(cos(a) * r, sin(a) * r))
	prof[0].x = 0.0
	prof[rings].x = 0.0
	lathe(mat, prof, xf, seg, true)


## Ring around local Y: tube radius `tube` at distance `radius` from the axis.
func torus(mat: Material, radius: float, tube: float, xf := Transform3D.IDENTITY, seg := 18, tube_seg := 8) -> void:
	var prof := PackedVector2Array()
	for i in tube_seg + 1:
		var a := -PI * 0.5 + TAU * float(i) / tube_seg
		prof.append(Vector2(radius + cos(a) * tube, sin(a) * tube))
	lathe(mat, prof, xf, seg, true)


## Everything added so far as ONE mesh with a surface per material (for MultiMesh instancing).
func build_mesh(grime := 0.0, y_offset := 0.0) -> ArrayMesh:
	var out := ArrayMesh.new()
	for mat: Material in _masters:
		var part := _with_grime((_masters[mat] as SurfaceTool).commit(), grime, y_offset)
		if part.get_surface_count() == 0:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(0))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	_masters.clear()
	return out


static func _with_grime(mesh: ArrayMesh, grime: float, y_offset: float) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var mud := Color(0.5, 0.42, 0.33)
	for i in verts.size():
		var v := verts[i]
		var y := v.y + y_offset
		var dust := (1.0 - smoothstep(0.1, 1.5, y)) * 0.8 + 0.12
		var blotch := fposmod(sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453, 1.0)
		dust = clampf(dust + (blotch - 0.5) * 0.25, 0.0, 1.0) * grime
		var c := Color(1, 1, 1).lerp(mud, dust)
		var under := clampf(-norms[i].y, 0.0, 1.0) if i < norms.size() else 0.0
		c = c.darkened(under * 0.5 * grime)
		cols[i] = c
	arrays[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Transform helpers.
static func at(pos: Vector3, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scale)
	return Transform3D(b, pos)


## Basis whose +Y points along dir (for tubes and barrels).
static func along(pos: Vector3, dir: Vector3, scale := Vector3.ONE) -> Transform3D:
	var d := dir.normalized()
	var q := Quaternion(Vector3.RIGHT, PI) if d.dot(Vector3.UP) < -0.9999 else Quaternion(Vector3.UP, d)
	var b := Basis(q).scaled(scale)
	return Transform3D(b, pos)
