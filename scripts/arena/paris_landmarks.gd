class_name ParisLandmarks
extends RefCounted
## Paris's landmarks (round 29, owner: "add the rest of the map like the tower and the other things").
## The models are Blender builds (tools/blender/build_paris_landmarks.py: paris_tower / paris_monuments /
## paris_buildings .glb); here they are placed, batched with the stage (static: one draw call per
## material for all of them) and given box colliders a car meets. Blender's front (-Y) is +Z here, so
## yaw 0 = the front faces south. Not built yet: the Grand Palais hall, the tower's lift and its fall,
## the Mona Lisa passage (design 32, later phases).

const TOWER_FILE := "paris_tower"
const MON_FILE := "paris_monuments"
const BLD_FILE := "paris_buildings"

## Louvre: the palace round its court (x 214..259, z -96..-34), open to the west; the pyramid in the middle.
const LOUVRE := [
	["louvre_pavilion", Vector2(205, -104), 0.0], ["louvre_wing", Vector2(229, -104), 0.0], ["louvre_wing", Vector2(260, -104), 0.0],
	["louvre_pavilion", Vector2(205, -26), 180.0], ["louvre_wing", Vector2(229, -26), 180.0], ["louvre_wing", Vector2(260, -26), 180.0],
	["louvre_wing", Vector2(267, -80), -90.0], ["louvre_wing", Vector2(267, -50), -90.0], # backs on the edge wall
]
const PYRAMID := Vector2(235, -65)
const CONCORDE := Vector2(82, -80)
const MOULIN := Vector2(166, -190)
const MOULIN_HUB := Vector3(-5.0, 17.2, 4.4) # the sails' hub in the Moulin Rouge's own space
const OPERA := Vector2(50.5, -186)
const OPERA_SCALE := 0.92
const INVALIDES := Vector2(0, 208) # its back on the south edge wall (no strip behind it)
const NOTRE_DAME_X := 222.0
const SACRE_COEUR_Z := -187.0
const CHAILLOT := [Vector2(-258, -85), Vector2(-221, -85)]
const CHAILLOT_DEPTH := 0.75


static func build(arena: ParisArena) -> void:
	if not ModelLib.has(TOWER_FILE) or not ModelLib.has(MON_FILE) or not ModelLib.has(BLD_FILE):
		push_warning("ParisLandmarks: models missing (run tools/blender/build_paris_landmarks.py)")
		return
	var t := ParisArena.TOWER
	_put(arena, TOWER_FILE, "eiffel", Vector3(t.x, 0, t.y), 0.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]: # the four feet (the lattice leans in above a car's roof)
			arena.solid(Vector3(8.5, 12.0, 8.5), Transform3D(Basis(), Vector3(t.x + sx * 21.0, 6.0, t.y + sz * 21.0)))
	# The Arc de Triomphe on the Etoile, its main arch on the Champs-Elysees' line: you drive through it.
	var e := ParisArena.ETOILE
	var cd := (Vector2(42, -80) - e).normalized()
	var arc_yaw := atan2(cd.x, cd.y)
	var arc_xf := _put(arena, MON_FILE, "arc", Vector3(e.x, 0, e.y), rad_to_deg(arc_yaw))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			arena.solid(Vector3(12.0, 40.0, 5.5), arc_xf * Transform3D(Basis(), Vector3(sx * 12.0, 20.0, sz * 6.25)))
	arena.solid(Vector3(36.0, 16.0, 18.0), arc_xf * Transform3D(Basis(), Vector3(0, 32.0, 0)))
	# Place de la Concorde: the obelisk between two fountains.
	_put(arena, MON_FILE, "obelisk", Vector3(CONCORDE.x, 0, CONCORDE.y), 0.0)
	arena.solid(Vector3(4.6, 6.0, 4.6), Transform3D(Basis(), Vector3(CONCORDE.x, 3.0, CONCORDE.y)))
	arena.solid(Vector3(1.9, 22.0, 1.9), Transform3D(Basis(), Vector3(CONCORDE.x, 16.0, CONCORDE.y)))
	for dz: float in [-24.0, 24.0]:
		var f := Vector3(CONCORDE.x, 0, CONCORDE.y + dz)
		_put(arena, MON_FILE, "fountain", f, 0.0)
		var water := ModelLib.mesh(MON_FILE, "fountain_water")
		if water:
			arena.batch_mesh(water, Transform3D(Basis(), f + Vector3(0, 0.42, 0)), false, arena.water_material())
		arena.solid(Vector3(3.2, 9.0, 3.2), Transform3D(Basis(), f + Vector3(0, 4.5, 0)))
	# The Louvre and its pyramid (lighter glass than the cars' windows: it is a glass pyramid).
	for p: Array in LOUVRE:
		var node: String = p[0]
		var at: Vector2 = p[1]
		var xf := _put(arena, BLD_FILE, node, Vector3(at.x, 0, at.y), p[2])
		var size := Vector3(30.0, 23.0, 16.0) if node == "louvre_wing" else Vector3(18.0, 30.0, 18.0)
		arena.solid(size, xf * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)))
	var pyr := ModelLib.mesh(MON_FILE, "pyramid")
	if pyr:
		pyr = pyr.duplicate() as ArrayMesh
		for i in pyr.get_surface_count():
			if pyr.surface_get_material(i) == ModelLib.glass():
				pyr.surface_set_material(i, _pyramid_glass())
		arena.batch_mesh(pyr, Transform3D(Basis(), Vector3(PYRAMID.x, 0, PYRAMID.y)))
	_pyramid_collider(arena, Vector3(PYRAMID.x, 0, PYRAMID.y), 22.0, 14.0)
	# Notre-Dame on the island, its towers to the west (the parvis in front of them).
	var nd := Vector3(NOTRE_DAME_X, 0, ParisArena.river_z(NOTRE_DAME_X))
	var nd_xf := _put(arena, BLD_FILE, "notre_dame", nd, -90.0)
	for b: Array in [[Vector3(21, 22, 30), Vector3(0, 11, -2)], [Vector3(22, 36, 8), Vector3(0, 18, 17)],
			[Vector3(25, 21, 7), Vector3(0, 10.5, -6)], [Vector3(11, 21, 6), Vector3(0, 10.5, -19.5)]]:
		arena.solid(b[0], nd_xf * Transform3D(Basis(), b[1]))
	# Sacre-Coeur on Montmartre's top terrace, facing south over the city (the climb arrives at its feet).
	var m := ParisArena.MONT
	var sc := Vector3(m.x, 14.0, SACRE_COEUR_Z)
	_put(arena, BLD_FILE, "sacre_coeur", sc, 0.0)
	for b: Array in [[Vector3(26, 16, 18), Vector3(0, 8, 0)], [Vector3(10, 12, 6), Vector3(0, 6, 11.5)], [Vector3(5, 30, 5), Vector3(0, 15, -11)]]:
		arena.solid(b[0], Transform3D(Basis(), sc + b[1]))
	# The Moulin Rouge at the foot of the hill, its sails turning.
	var mr := Vector3(MOULIN.x, 0, MOULIN.y)
	_put(arena, MON_FILE, "moulin", mr, 0.0)
	arena.solid(Vector3(18.0, 10.0, 10.0), Transform3D(Basis(), mr + Vector3(0, 5.0, 0)))
	var sails := ModelLib.instance(MON_FILE, "moulin_sails")
	if sails.mesh:
		sails.position = mr + MOULIN_HUB
		arena.add_child(sails)
		var tw := sails.create_tween().set_loops()
		tw.tween_property(sails, "rotation:z", -TAU, 14.0).from(0.0)
	# The Opera, the Invalides, the Palais de Chaillot's two wings on the Trocadero.
	var op := Vector3(OPERA.x, 0, OPERA.y)
	_put(arena, BLD_FILE, "opera", op, 0.0, OPERA_SCALE)
	arena.solid(Vector3(44.0, 22.0, 36.0), Transform3D(Basis(), op + Vector3(0, 11.0, -2.0))) # back to the block behind
	var inv := Vector3(INVALIDES.x, 0, INVALIDES.y)
	_put(arena, BLD_FILE, "invalides", inv, 180.0)
	arena.solid(Vector3(34.0, 16.0, 34.0), Transform3D(Basis(), inv + Vector3(0, 8.0, 0)))
	for c: Vector2 in CHAILLOT: # 6 m deep: a wide lane between them and the viaduct up to the roofs
		var xf := Transform3D(Basis().scaled(Vector3(1.0, 1.0, CHAILLOT_DEPTH)), Vector3(c.x, 8.0, c.y))
		var mesh := ModelLib.mesh(BLD_FILE, "chaillot")
		if mesh:
			arena.batch_mesh(mesh, xf)
		arena.solid(Vector3(26.0, 15.0, 8.0 * CHAILLOT_DEPTH), Transform3D(Basis(), Vector3(c.x, 15.5, c.y)))


## One landmark into the stage's batch; returns its transform (for the colliders).
static func _put(arena: ParisArena, file: String, node: String, at: Vector3, yaw_deg: float, scale := 1.0) -> Transform3D:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale), at)
	var mesh := ModelLib.mesh(file, node)
	if mesh:
		arena.batch_mesh(mesh, xf)
	return xf


## Where the landmarks stand (pickups and trees keep out of these): centre, half size.
static func footprints() -> Array:
	var out: Array = [[ParisArena.TOWER, Vector2(26, 26)], [PYRAMID, Vector2(12, 12)], [CONCORDE, Vector2(3, 3)],
		[MOULIN, Vector2(10, 6)], [OPERA, Vector2(23, 17)], [INVALIDES, Vector2(18, 18)],
		[Vector2(ParisArena.MONT.x, SACRE_COEUR_Z), Vector2(14, 15)], [Vector2(NOTRE_DAME_X, ParisArena.river_z(NOTRE_DAME_X)), Vector2(23, 13)],
		[ParisArena.ETOILE, Vector2(21, 21)]]
	for p: Array in LOUVRE:
		out.append([p[1], Vector2(15, 9) if p[0] == "louvre_wing" and absf(p[2]) < 100.0 else Vector2(9, 15) if p[0] == "louvre_wing" else Vector2(9, 9)])
	for c: Vector2 in CHAILLOT:
		out.append([c, Vector2(13, 3)])
	return out


static func _pyramid_glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.55, 0.66, 0.72, 0.5)
	g.roughness = 0.06
	g.metallic = 0.5
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g


## The pyramid as a convex collider: four sloping faces you bounce off (52 degrees: too steep to climb).
static func _pyramid_collider(arena: ParisArena, at: Vector3, base: float, height: float) -> void:
	var h := base * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([at + Vector3(-h, 0, -h), at + Vector3(h, 0, -h), at + Vector3(h, 0, h), at + Vector3(-h, 0, h), at + Vector3(0, height, 0)])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	arena._solids().add_child(cs)
