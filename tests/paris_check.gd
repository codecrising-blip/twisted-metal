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
		_check(not _in_block(p), "pickup %s outside the buildings" % p)
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
