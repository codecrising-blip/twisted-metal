extends SceneTree
## Map check (round 7, owner: "look for similar issues along the map"): every 2 m spot a car fits on,
## and whether a car there can drive (or drop) back to the middle of the battleground. Spots you can
## get into but not out of = traps. Also narrow slots (free width 2-3.6 m) that grab a car.
## Run: godot --headless --path . -s tests/map_check.gd   (prints TRAP clusters and SLOT spots; want none).
const STEP := 2.0
const HALF := 154
var space: PhysicsDirectSpaceState3D
var ground_rid: RID
func _initialize() -> void:
	_run.call_deferred()
func _ray(a: Vector3, b: Vector3, exclude_ground := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	if exclude_ground:
		q.exclude = [ground_rid]
	return space.intersect_ray(q)
func _fits(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.1)
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()
func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	for v: Vehicle in [main.player] + main.enemies:
		v.global_position = Vector3(0, 300, 0)
		v.freeze = true
	await physics_frame
	space = main.get_world_3d().direct_space_state
	ground_rid = (main.arena.get_node("Ground") as CollisionObject3D).get_rid()
	# Nodes: every surface (several levels) a car fits on.
	var nodes := [] # [Vector3]
	var at := {} # Vector2i -> [node indices]
	var n := int(HALF * 2 / STEP)
	for i in n + 1:
		for j in n + 1:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var top := 40.0
			var cell := []
			for level in 4:
				var r := _ray(Vector3(x, top, z), Vector3(x, -5, z))
				if r.is_empty():
					break
				var p: Vector3 = r.position
				if (r.normal as Vector3).y > 0.75 and _fits(p):
					cell.append(nodes.size())
					nodes.append(p)
				top = p.y - 1.2
				if top < 0.0:
					break
			at[Vector2i(i, j)] = cell
	print("TRAP nodes ", nodes.size())
	# Edges (reversed for the search): from a to b if a car can go a -> b.
	var back := []
	var fwd := []
	back.resize(nodes.size())
	fwd.resize(nodes.size())
	for k in nodes.size():
		back[k] = []
		fwd[k] = []
	for i in n + 1:
		for j in n + 1:
			for a: int in at[Vector2i(i, j)]:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var key := Vector2i(i, j) + d
					if not at.has(key):
						continue
					for b: int in at[key]:
						var pa: Vector3 = nodes[a]
						var pb: Vector3 = nodes[b]
						var rise := pb.y - pa.y
						if rise > 1.1:
							continue # too steep to climb in 2 m
						var hgt := maxf(pa.y, pb.y) + 0.9
						if not _ray(Vector3(pa.x, hgt, pa.z), Vector3(pb.x, hgt, pb.z), true).is_empty():
							continue # a wall in between
						if rise < -1.1 and not _ray(Vector3(pb.x, pa.y + 0.9, pb.z), Vector3(pb.x, pb.y + 0.5, pb.z)).is_empty():
							continue # something between the ledge and the spot below
						back[b].append(a)
						fwd[a].append(b)
	# Search back from the middle of the battleground.
	var goal := -1
	for b: int in at[Vector2i(n / 2 + 20, n / 2)]:
		goal = b
	var seen := PackedByteArray()
	seen.resize(nodes.size())
	var queue := [goal]
	seen[goal] = 1
	while not queue.is_empty():
		var c: int = queue.pop_back()
		for a: int in back[c]:
			if seen[a] == 0:
				seen[a] = 1
				queue.append(a)
	var into := PackedByteArray()
	into.resize(nodes.size())
	queue = [goal]
	into[goal] = 1
	while not queue.is_empty():
		var c: int = queue.pop_back()
		for b: int in fwd[c]:
			if into[b] == 0:
				into[b] = 1
				queue.append(b)
	var traps := []
	for k in nodes.size():
		if seen[k] == 0 and into[k] == 1: # you can get in, but not back out
			traps.append(nodes[k])
	print("TRAP unreachable spots ", traps.size())
	# Group into clusters (8 m).
	var clusters := []
	for p: Vector3 in traps:
		var put := false
		for c: Array in clusters:
			if (c[0] as Vector3).distance_to(p) < 12.0:
				c.append(p)
				put = true
				break
		if not put:
			clusters.append([p])
	for c: Array in clusters:
		var mid := Vector3.ZERO
		for p: Vector3 in c:
			mid += p
		print("TRAP cluster of %d around %s" % [c.size(), mid / c.size()])
	# Narrow slots: free spots whose free width across some direction is 2-3.6 m.
	var slots := []
	for p: Vector3 in nodes:
		for dir: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
			var o := p + Vector3.UP * 0.7
			var r1 := _ray(o, o + dir * 4.0, true)
			var r2 := _ray(o, o - dir * 4.0, true)
			if r1.is_empty() or r2.is_empty():
				continue
			var w := (r1.position as Vector3).distance_to(r2.position)
			if w < 3.6:
				slots.append(p)
				break
	var sc := []
	for p: Vector3 in slots:
		var put := false
		for c: Array in sc:
			if (c[0] as Vector3).distance_to(p) < 10.0:
				c.append(p)
				put = true
				break
		if not put:
			sc.append([p])
	for c: Array in sc:
		print("SLOT %d spots near %s" % [c.size(), c[0]])
	quit()
