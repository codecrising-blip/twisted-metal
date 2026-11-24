extends SceneTree
## Paris (stage 2) sanity: the ground is where the layout says, every point stands on something
## drivable and outside the buildings, ramps and bridges are solid.
##   godot --headless --path . -s tests/paris_check.gd

var _arena: ParisArena
var _fails := 0
var _frames := 0


func _initialize() -> void:
	_arena = ParisArena.new()
	root.add_child(_arena)
	_arena.build()


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run()
	print("PARIS CHECK OK" if _fails == 0 else "PARIS CHECK FAILED: %d" % _fails)
	quit(0 if _fails == 0 else 1)
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)


func _ray_y(x: float, z: float, from := 60.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from, z), Vector3(x, -30, z), 1)
	var hit := _arena.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if hit else -999.0


func _in_block(p: Vector3) -> bool:
	for b: Dictionary in _arena.blocks:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), b.poly):
			return true
	return false


## Round 29 (owner: "tight spaces between the buildings I can slide into but cannot move"): street-level
## spots a car fits on whose free width across some direction is under SLOT_W = a slot that grabs a car.
const SLOT_W := 3.8


func _fits(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.0, 1.6)
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()


func _slots() -> Array:
	var space := _arena.get_world_3d().direct_space_state
	var ground: RID = (_arena.get_node("Ground") as CollisionObject3D).get_rid()
	var found := []
	var x := -ParisArena.HX + 1.0
	while x < ParisArena.HX - 0.5:
		var z := -ParisArena.HZ + 1.0
		while z < ParisArena.HZ - 0.5:
			var y := _ray_y(x, z, 40.0)
			if y > -7.0 and y < 15.0:
				var p := Vector3(x, y, z)
				if _fits(space, p):
					for dir: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
						var o := p + Vector3.UP * 0.8
						var q1 := PhysicsRayQueryParameters3D.create(o, o + dir * 4.0, 1)
						q1.exclude = [ground]
						var q2 := PhysicsRayQueryParameters3D.create(o, o - dir * 4.0, 1)
						q2.exclude = [ground]
						var r1 := space.intersect_ray(q1)
						var r2 := space.intersect_ray(q2)
						if r1.is_empty() or r2.is_empty():
							continue
						if r1.collider is Breakable or r2.collider is Breakable:
							continue
						if (r1.normal as Vector3).dot(r2.normal) > -0.7:
							continue # an inside corner (walls meeting), not two walls facing each other
						if (r1.position as Vector3).distance_to(r2.position) < SLOT_W:
							found.append(p)
							if OS.has_environment("SLOT_DEBUG"):
								print("  ", p, " dir ", dir, " ", r1.collider.name, r1.position, " | ", r2.collider.name, r2.position)
							break
			z += 2.0
		x += 2.0
	return found


func _run() -> void:
	var a := _arena
	_check(a.blocks.size() > 10, "blocks: %d" % a.blocks.size())
	_check(a.spawn_points.size() >= 6, "spawn points for 5 enemies + player")
	for t: Transform3D in a.spawn_points:
		var y := _ray_y(t.origin.x, t.origin.z, t.origin.y + 2.0)
		_check(absf(y - (t.origin.y - 0.3)) < 0.6, "spawn %s stands on ground (hit %.2f)" % [t.origin, y])
		_check(not _in_block(t.origin), "spawn %s outside the buildings" % t.origin)
	for p: Vector3 in a.weapon_points + a.health_points + a.mega_points + a.turbo_points:
		var y := _ray_y(p.x, p.z, p.y + 2.0)
		_check(absf(y - (p.y - 0.6)) < 0.7, "pickup %s on its ground (hit %.2f)" % [p, y])
		_check(not _in_block(p) or p.y > ParisArena.ROOF_Y, "pickup %s outside the buildings (or on a roof)" % p)
		_check(_fits(_arena.get_world_3d().direct_space_state, p - Vector3(0, 0.6, 0)), "pickup %s clear of landmarks and walls" % p)
	for r: Dictionary in a.ramps:
		var top: Vector3 = r.top
		var y := _ray_y(top.x, top.z, top.y + 3.0)
		_check(absf(y - top.y) < 0.8, "ramp top %s solid (hit %.2f)" % [top, y])
	for b: Dictionary in ParisArena.BRIDGES:
		var x: float = b.x
		var z := ParisArena.river_z(x) + (ParisArena.island_half(x) + 6.0 if b.spans == "south" else -ParisArena.island_half(x) - 6.0)
		_check(_ray_y(x, z) > -0.5, "bridge %s deck solid" % b.name)
	var qz := ParisArena.river_z(-120.0) - ParisArena.water_half(-120.0) - 5.0
	_check(absf(_ray_y(-120.0, qz) - ParisArena.QUAY_Y) < 0.3, "lower quay at -5")
	for blk: Dictionary in a.blocks:
		if blk.roof:
			var c := ParisArena._centroid(blk.poly)
			if Geometry2D.is_point_in_polygon(c, blk.poly):
				_check(absf(_ray_y(c.x, c.y) - ParisArena.ROOF_Y) < 0.3, "roof deck at %s" % c)
	# Round 29: every rooftop crossing lands on a roof deck at both ends, past the mansard.
	for c: Array in ParisArena.CROSSINGS:
		for e: Vector2 in [c[0], c[1]]:
			var y := _ray_y(e.x, e.y, ParisArena.ROOF_Y + 3.0)
			_check(absf(y - ParisArena.ROOF_Y) < 0.1, "crossing end %s on a roof (hit %.2f)" % [e, y])
			var under := false
			for blk: Dictionary in a.blocks:
				if blk.roof and Geometry2D.is_point_in_polygon(e, blk.poly):
					under = true
			_check(under, "crossing end %s stands over a roof block" % e)
	var tl: Vector2 = ParisArena.TROCA_LINK[1]
	_check(absf(_ray_y(tl.x + 6.0, tl.y, ParisArena.ROOF_Y + 3.0) - ParisArena.ROOF_Y) < 0.1, "Trocadero link reaches the roof")
	var cr: Vector2 = ParisArena.CHAMPS_RAMP[1]
	_check(absf(_ray_y(cr.x - 6.0, cr.y, ParisArena.ROOF_Y + 3.0) - ParisArena.ROOF_Y) < 0.1, "Champs ramp reaches the roof")
	# Round 29: the Seine is shallow and drivable: the bed is solid, nothing invisible over the water.
	for rx: float in [-200.0, -60.0, 60.0, 200.0]:
		var zc := ParisArena.river_z(rx)
		_check(absf(_ray_y(rx, zc - ParisArena.water_half(rx) * 0.5) - ParisArena.BED_Y) < 0.1 or ParisArena.island_half(rx) > 3.0,
			"riverbed at %.0f" % rx)
	_check(_arena.find_child("WaterBarrier", true, false) == null, "no invisible water barrier")
	var bed_x := -60.0
	var bz := ParisArena.river_z(bed_x)
	var q := PhysicsRayQueryParameters3D.create(Vector3(bed_x, ParisArena.BED_Y + 1.0, bz - 12.0), Vector3(bed_x, ParisArena.BED_Y + 1.0, bz + 12.0), 1)
	_check(_arena.get_world_3d().direct_space_state.intersect_ray(q).is_empty(), "nothing across the river at wheel height")
	var hs := 0
	for p: Vector3 in a.health_points:
		if p.y < 1.5:
			hs += 1
	_check(hs == 3, "three health pickups at street level (got %d)" % hs)
	_check(a.mega_points.size() == 1 and a.mega_points[0].y > 5.0, "the mega health is up top")
	var slots := _slots()
	var groups := []
	for p: Vector3 in slots:
		var put := false
		for g: Array in groups:
			if (g[0] as Vector3).distance_to(p) < 8.0:
				g.append(p)
				put = true
				break
		if not put:
			groups.append([p])
	for g: Array in groups:
		print("SLOT %d spots near %s" % [g.size(), g[0]])
	_check(groups.is_empty(), "no narrow slots at street level (%d)" % groups.size())
	# Round 29: the landmarks stand (the tower's feet, the arc's piers) and the arc lets cars through.
	_check(_ray_y(ParisArena.TOWER.x + 21.0, ParisArena.TOWER.y + 21.0) > 10.0, "Eiffel tower foot is solid")
	var e := ParisArena.ETOILE
	_check(absf(_ray_y(e.x, e.y, 20.0)) < 0.3, "the Arc de Triomphe's main arch is open to drive through")
