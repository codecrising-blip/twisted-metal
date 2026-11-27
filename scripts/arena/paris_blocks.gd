class_name ParisBlocks
extends RefCounted
## Haussmann city blocks on the footprints ParisArena cut out of the street plan.
## Every facade is a row of 3 m bays from the Blender kit (tools/blender/build_haussmann.py): a ground
## floor with shops, doors or shutters, the 2nd and top floors with continuous iron balconies, a stone
## cornice and a zinc mansard. The quarter between the Etoile and the Seine is low (roofs you drive on at
## ROOF_Y, TM2's legacy); the other blocks are taller and closed, with chimney stacks.
## Performance (owner's HD 5500): one mesh per material per block, kit detail within NEAR metres, past it
## a plain shell with a painted facade; facades on the map's edge are not built.

const KIT := "haussmann"
const BAY := 3.0
const G_H := 4.68
const F_H := 3.12
const CORNICE_H := 0.52
const MANS_LOW := 1.56
const MANS_TALL := 2.72
const RUN_LOW := 1.3 # how far the mansard steps back
const RUN_TALL := 0.95
const NEAR := 115.0
const MARGIN := 8.0
const GROUND_KINDS := ["g_shop_red", "g_shop_green", "g_shop_navy", "g_shop_black", "g_door", "g_door", "g_shutter",
	"g_shop_black", "g_burnt", "g_shop_red", "g_door", "g_shop_green"]

static var _shell_mats := {}


static func build(arena: ParisArena, blocks: Array[Dictionary]) -> void:
	var use_kit := ModelLib.has(KIT)
	var deck := ParisArena.zinc_roof()
	var zinc := deck
	var body := arena.buildings_body()
	var rng := RandomNumberGenerator.new()
	for bi in blocks.size():
		var b: Dictionary = blocks[bi]
		var poly: PackedVector2Array = b.poly
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		rng.seed = 7919 * (bi + 1)
		var low: bool = b.roof
		var h := ParisArena.ROOF_Y if low else ParisArena.TALL_Y
		var run := RUN_LOW if low else RUN_TALL
		var center := ParisArena._centroid(poly)
		var origin := Vector3(center.x, 0, center.y)
		var near := {} # material -> SurfaceTool
		var shell := MeshBuilder.new()
		var wall_st := SurfaceTool.new()
		wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var floors := _floors(low)
		var cornice_y := G_H + F_H * floors.size()
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var c := poly[(i + 1) % n]
			if _on_boundary(a, c):
				continue
			var d := (c - a).normalized()
			var out := Vector3(d.y, 0, -d.x)
			var length := a.distance_to(c)
			_shell_edge(shell, wall_st, a, c, out, cornice_y, h, run, low, origin)
			if not use_kit:
				continue
			var bays := maxi(1, roundi(length / BAY))
			var fill := length < 2.2
			var s := length / (1.0 if fill else bays * BAY)
			var basis := Basis(Vector3(-d.x, 0, -d.y) * s, Vector3.UP, out)
			for k in (1 if fill else bays):
				var t := (k + 0.5) * length / (1 if fill else bays)
				var p := Vector3(a.x + d.x * t, 0, a.y + d.y * t) - origin
				var corner := length < 7.0
				var gk: String = "g_pier" if fill else ("g_shop_black" if corner else GROUND_KINDS[rng.randi() % GROUND_KINDS.size()])
				_add(near, gk, Transform3D(basis, p))
				if gk.begins_with("g_shop") and rng.randf() < 0.55:
					_add(near, "awning_red" if rng.randf() < 0.5 else "awning_green", Transform3D(basis, p))
				for f in floors.size():
					var fk: String = "f_pier" if fill else floors[f]
					_add(near, fk, Transform3D(basis, p + Vector3(0, G_H + F_H * f, 0)))
				_add(near, "cornice", Transform3D(basis, p + Vector3(0, cornice_y, 0)))
				var mk := "mans_low" if low else "mans_tall"
				if not fill and rng.randf() < 0.6:
					mk += "_dormer"
				_add(near, mk, Transform3D(basis, p + Vector3(0, cornice_y + CORNICE_H, 0)))
				if not low and not fill and k % 3 == 1 and rng.randf() < 0.8:
					var ch := p - out * (run + 1.2) + Vector3(0, h, 0)
					_add(near, "chimney", Transform3D(Basis(Vector3(-d.x, 0, -d.y), Vector3.UP, out), ch))
		# Roof: a deck you drive on (low) or flat zinc (tall), inside the mansard.
		var inner_set := Geometry2D.offset_polygon(poly, -run, Geometry2D.JOIN_MITER)
		for inner: PackedVector2Array in inner_set:
			if not Geometry2D.is_polygon_clockwise(inner):
				arena.poly_face(deck if low else zinc, inner, h, false, ArenaKit.COL_GROUND)
		# The mansard slopes are solid too (round 30: tall roofs were hollow down to the cornice, a car that
		# got up there sank into them).
		var sloped := _slope_collision(arena, poly, inner_set, cornice_y + CORNICE_H, h)
		_commit(arena, near, shell, wall_st, _shell_mat(low), origin, use_kit)
		for piece: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(poly):
			var pts := PackedVector3Array()
			for v in piece:
				pts.append(Vector3(v.x, 0.0, v.y))
				pts.append(Vector3(v.x, cornice_y + 0.3 if sloped else h, v.y)) # no slopes: solid to the roof
			var cs := CollisionShape3D.new()
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			cs.shape = shape
			body.add_child(cs)


static func _floors(low: bool) -> Array[String]:
	if low:
		return ["f_balcony", "f_balcony"]
	return ["f_balcony", "f_window", "f_window", "f_balcony"]


static func _add(near: Dictionary, node: String, xf: Transform3D) -> void:
	var mesh := ModelLib.mesh(KIT, node)
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if not near.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			near[mat] = st
		(near[mat] as SurfaceTool).append_from(mesh, i, xf)


## The far shell of one facade: wall painted with the kit's own facade (rendered in Blender by
## render_haussmann_far.py, three bays wide), cornice ledge, mansard slope.
static func _shell_edge(mb: MeshBuilder, wall_st: SurfaceTool, a: Vector2, c: Vector2, out: Vector3, cornice_y: float, h: float, run: float, low: bool, origin: Vector3) -> void:
	_shell_mat(low)
	var A := Vector3(a.x, 0, a.y) - origin
	var C := Vector3(c.x, 0, c.y) - origin
	var u1 := a.distance_to(c) / (3.0 * BAY)
	var n := out
	# clockwise seen from outside: A, top of A, top of C / A, top of C, C
	var pts := [A, A + Vector3(0, cornice_y, 0), C + Vector3(0, cornice_y, 0), A, C + Vector3(0, cornice_y, 0), C]
	var uvs := [Vector2(0, 1), Vector2(0, 0), Vector2(u1, 0), Vector2(0, 1), Vector2(u1, 0), Vector2(u1, 1)]
	var p0: Vector3 = pts[0]
	var p1: Vector3 = pts[1]
	var p2: Vector3 = pts[2]
	var cr := (p1 - p0).cross(p2 - p0)
	if cr.dot(n) > 0.0:
		pts = [A, C + Vector3(0, cornice_y, 0), A + Vector3(0, cornice_y, 0), A, C, C + Vector3(0, cornice_y, 0)]
		uvs = [Vector2(0, 1), Vector2(u1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(u1, 1), Vector2(u1, 0)]
	wall_st.set_normal(n)
	wall_st.set_color(Color.WHITE)
	for k in 6:
		wall_st.set_uv(uvs[k])
		wall_st.add_vertex(pts[k])
	var o := out * 0.5
	var top := Vector3(0, cornice_y + CORNICE_H, 0)
	mb.quad(_shell_mats.stone, A + o + Vector3(0, cornice_y, 0), C + o + Vector3(0, cornice_y, 0), C + o + top, A + o + top, out)
	mb.quad(_shell_mats.stone, A + top, C + top, C + o + top, A + o + top, Vector3.UP)
	var r := -out * run
	mb.quad(_shell_mats.zinc, A + top, C + top, C + r + Vector3(0, h, 0), A + r + Vector3(0, h, 0), (out + Vector3.UP * 0.6).normalized())


static func _shell_mat(low: bool) -> StandardMaterial3D:
	if _shell_mats.is_empty():
		_shell_mats.stone = MatKit.flat(ParisArena.C_STONE.darkened(0.05), 0.9)
		_shell_mats.zinc = MatKit.flat(ParisArena.C_ZINC, 0.6)
	var key := "low" if low else "tall"
	if not _shell_mats.has(key):
		var m := StandardMaterial3D.new()
		var path := "res://assets/models/haussmann_far_%s.png" % key
		m.albedo_texture = load(path) if ResourceLoader.exists(path) else _facade_texture(low)
		m.roughness = 0.9
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_shell_mats[key] = m
	return _shell_mats[key]


## Fallback when the rendered facade is missing: stone, dark windows, iron balcony lines, a shop band.
static func _facade_texture(low: bool) -> ImageTexture:
	var floors := _floors(low)
	var hm := G_H + F_H * floors.size()
	var px := 32.0 # per metre
	var w := int(BAY * 3.0 * px)
	var hh := int(hm * px)
	var img := Image.create(w, hh, false, Image.FORMAT_RGB8)
	img.fill(ParisArena.C_STONE.darkened(0.08))
	var y := func(m: float) -> int: return int((hm - m) * px)
	var dark := Color(0.13, 0.13, 0.15)
	for b in 3:
		var x0 := b * BAY * px
		img.fill_rect(Rect2i(int(x0 + 0.5 * px), y.call(3.64), int(2.0 * px), int(3.64 * px)), Color(0.12, 0.1, 0.09))
		for f in floors.size():
			var base := G_H + F_H * f
			img.fill_rect(Rect2i(int(x0 + 0.88 * px), y.call(base + 2.62), int(1.24 * px), int(2.48 * px)), dark)
	img.fill_rect(Rect2i(0, y.call(0.42), w, int(0.42 * px)), Color("8F8A80"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _slope_collision(arena: ParisArena, poly: PackedVector2Array, inner_set: Array[PackedVector2Array], y0: float, y1: float) -> bool:
	if inner_set.size() != 1 or inner_set[0].size() != poly.size():
		return false
	var inner := inner_set[0]
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var a := Vector3(poly[i].x, y0, poly[i].y)
		var c := Vector3(poly[j].x, y0, poly[j].y)
		var ia := Vector3(inner[i].x, y1, inner[i].y)
		var ic := Vector3(inner[j].x, y1, inner[j].y)
		for tri: Array in [[a, c, ic], [a, ic, ia]]:
			var t0: Vector3 = tri[0]
			var t1: Vector3 = tri[1]
			var t2: Vector3 = tri[2]
			if (t1 - t0).cross(t2 - t0).y > 0.0:
				arena.col_ground.append_array([t0, t2, t1])
			else:
				arena.col_ground.append_array([t0, t1, t2])
	return true


static func _commit(arena: Node3D, near: Dictionary, shell: MeshBuilder, wall_st: SurfaceTool, wall_mat: Material, origin: Vector3, use_kit: bool) -> void:
	var holder := Node3D.new()
	holder.position = origin
	arena.add_child(holder)
	for mat: Material in near:
		var mi := MeshInstance3D.new()
		var st: SurfaceTool = near[mat]
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.visibility_range_end = NEAR
		mi.visibility_range_end_margin = MARGIN
		if mat == ModelLib.glass():
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	var walls := MeshInstance3D.new()
	walls.mesh = wall_st.commit()
	walls.material_override = wall_mat
	holder.add_child(walls)
	for mi: MeshInstance3D in shell.commit(holder, true) + [walls]:
		if use_kit:
			mi.visibility_range_begin = NEAR
			mi.visibility_range_begin_margin = MARGIN


## Facades on the map's edge face the backdrop: nobody sees them, so they are not built.
static func _on_boundary(a: Vector2, c: Vector2) -> bool:
	var hx := ParisArena.HX - 0.2
	var hz := ParisArena.HZ - 0.2
	return (absf(a.x) >= hx and absf(c.x) >= hx and signf(a.x) == signf(c.x)) \
		or (absf(a.y) >= hz and absf(c.y) >= hz and signf(a.y) == signf(c.y))
