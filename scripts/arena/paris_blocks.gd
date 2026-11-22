class_name ParisBlocks
extends RefCounted
## Haussmann city blocks on the footprints ParisArena cut out of the street plan.
## Each block: stone facades to the cornice, a zinc mansard, a roof. The quarter between the Etoile and
## the Seine has drivable roofs at ROOF_Y (TM2's legacy); the rest are taller and closed.
## Phase 1 massing; the Blender kit (tools/blender/build_haussmann.py) dresses the facades.

const MANSARD_RUN := 1.3 # how far the mansard steps back from the facade
const CORNICE_OUT := 0.45


static func build(arena: ParisArena, blocks: Array[Dictionary]) -> void:
	var stone := MatKit.masonry(ParisArena.C_STONE, 4.0, 41)
	var zinc := MatKit.paint(ParisArena.C_ZINC, 0.15, 0.05, 0.25, 3.0, 0.35, 42)
	var deck := MatKit.pavers(Color("7C858C"), 3.0, 43)
	var body := arena.buildings_body()
	for b: Dictionary in blocks:
		var poly: PackedVector2Array = b.poly
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var h: float = b.h
		var mans_h := 1.8 if b.roof else 3.0
		var cornice := h - mans_h
		var inner_set := Geometry2D.offset_polygon(poly, -MANSARD_RUN, Geometry2D.JOIN_MITER)
		var inner: PackedVector2Array = inner_set[0] if inner_set.size() == 1 else poly
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var c := poly[(i + 1) % n]
			if _on_boundary(a, c):
				continue
			var d := (c - a).normalized()
			var out := Vector3(d.y, 0, -d.x) # counter-clockwise polygon in (x, z): the outside is to the right
			arena.face(stone, [Vector3(a.x, 0, a.y), Vector3(c.x, 0, c.y), Vector3(c.x, cornice, c.y), Vector3(a.x, cornice, a.y)], out)
			var o := Vector2(out.x, out.z) * CORNICE_OUT
			arena.face(stone, [Vector3(a.x + o.x, cornice, a.y + o.y), Vector3(c.x + o.x, cornice, c.y + o.y),
				Vector3(c.x + o.x, cornice + 0.4, c.y + o.y), Vector3(a.x + o.x, cornice + 0.4, a.y + o.y)], out)
			arena.face(stone, [Vector3(a.x, cornice + 0.4, a.y), Vector3(c.x, cornice + 0.4, c.y), Vector3(c.x + o.x, cornice + 0.4, c.y + o.y),
				Vector3(a.x + o.x, cornice + 0.4, a.y + o.y)], Vector3.UP)
		if inner.size() == n:
			for i in n:
				var a := poly[i]
				var c := poly[(i + 1) % n]
				if _on_boundary(a, c):
					continue
				var ia := inner[i]
				var ic := inner[(i + 1) % n]
				var d := (c - a).normalized()
				arena.face(zinc, [Vector3(a.x, cornice + 0.4, a.y), Vector3(c.x, cornice + 0.4, c.y), Vector3(ic.x, h, ic.y), Vector3(ia.x, h, ia.y)],
					Vector3(d.y, 0.6, -d.x), true, ArenaKit.COL_GROUND if b.roof else ArenaKit.COL_NONE)
			arena.poly_face(deck if b.roof else zinc, inner, h, false, ArenaKit.COL_GROUND if b.roof else ArenaKit.COL_NONE)
		else:
			arena.poly_face(deck if b.roof else zinc, poly, h, false, ArenaKit.COL_GROUND if b.roof else ArenaKit.COL_NONE)
		for piece: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(poly):
			var pts := PackedVector3Array()
			for v in piece:
				pts.append(Vector3(v.x, 0.0, v.y))
				pts.append(Vector3(v.x, cornice + 0.3, v.y))
			var cs := CollisionShape3D.new()
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			cs.shape = shape
			body.add_child(cs)


## Facades on the map's edge face the backdrop: nobody sees them, so they are not built.
static func _on_boundary(a: Vector2, c: Vector2) -> bool:
	var hx := ParisArena.HX - 0.2
	var hz := ParisArena.HZ - 0.2
	return (absf(a.x) >= hx and absf(c.x) >= hx and signf(a.x) == signf(c.x)) \
		or (absf(a.y) >= hz and absf(c.y) >= hz and signf(a.y) == signf(c.y))
