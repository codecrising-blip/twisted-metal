class_name ParisNav
extends RefCounted
## Round 31 (owner: "fix the AI behaviour in the whole map": stuck in the Notre-Dame channels, at the Trocadero
## "stairs" to the mega health, trying roads that were closed): a path-finding grid for Paris. The drivable
## surfaces are sampled every CELL metres (two layers where something passes over something else: bridges over
## the Seine, the Trocadero link over the street); neighbours are joined when the step between them is small
## and nothing solid stands between them at bonnet height. The AI asks next_point() for where to drive.
## Built on the first request (the stage's collision has to be in the physics space by then).

const CELL := 4.0
const TOP := 60.0 # rays start this high
const MAX_STEP := 1.3 # height between neighbours a car drives up (ramps, fillets, banks)
const EYE := 1.0 # the wall test runs this far over the ground
const LOOK := 26.0 # the AI aims at the furthest path point it can see within this distance

var arena: Node3D
var astar := AStar3D.new()
var nx := 0
var nz := 0
var x0 := 0.0
var z0 := 0.0
var _ids := {} # cell index -> Array[int] of point ids (one per layer)
var _space: PhysicsDirectSpaceState3D
var built := false
var _cache := {} # requester instance id -> {to, path, t}


func _init(a: Node3D) -> void:
	arena = a


func build() -> void:
	built = true
	_space = arena.get_world_3d().direct_space_state
	var hx: float = arena.HX
	var hz: float = arena.HZ
	x0 = -hx + CELL * 0.5
	z0 = -hz + CELL * 0.5
	nx = int(2.0 * hx / CELL)
	nz = int(2.0 * hz / CELL)
	var next_id := 0
	for iz in nz:
		for ix in nx:
			var x := x0 + ix * CELL
			var z := z0 + iz * CELL
			var ids: Array[int] = []
			var from_y := TOP
			for layer in 2:
				var hit := _down(Vector3(x, from_y, z), -10.0)
				if hit.is_empty():
					break
				var p: Vector3 = hit.position
				if _is_ground(hit) and hit.normal.y > 0.7 and _clearance(p):
					astar.add_point(next_id, p)
					ids.append(next_id)
					next_id += 1
				from_y = p.y - 2.6 # a second surface under this one (a bridge's deck over the river)
				if from_y < -9.0:
					break
			if not ids.is_empty():
				_ids[iz * nx + ix] = ids
	for key: int in _ids:
		var ix: int = key % nx
		var iz: int = key / nx
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var jx := ix + d.x
			var jz := iz + d.y
			if jx < 0 or jx >= nx or jz >= nz or not _ids.has(jz * nx + jx):
				continue
			for a: int in _ids[key]:
				for b: int in _ids[jz * nx + jx]:
					var pa := astar.get_point_position(a)
					var pb := astar.get_point_position(b)
					if absf(pa.y - pb.y) <= MAX_STEP * (1.42 if d.x != 0 and d.y != 0 else 1.0) and _link(pa, pb):
						astar.connect_points(a, b)
	_prune()


## Only what a car can get to from the stage's spawn points stays (the city floor runs on under the terraces:
## the second layer found a hidden "street" inside them, walled in on every side).
func _prune() -> void:
	var seen := {}
	var queue: Array[int] = []
	for t: Transform3D in arena.spawn_points:
		var id := _nearest(t.origin)
		if id >= 0 and not seen.has(id):
			seen[id] = true
			queue.append(id)
	while not queue.is_empty():
		var id: int = queue.pop_back()
		for n: int in astar.get_point_connections(id):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	for key: int in _ids.keys():
		var keep: Array[int] = []
		for id: int in _ids[key]:
			if seen.has(id):
				keep.append(id)
			else:
				astar.set_point_disabled(id, true)
		if keep.is_empty():
			_ids.erase(key)
		else:
			_ids[key] = keep


## Two neighbouring cells are joined when nothing solid stands between them at two heights, tested a little past
## the far cell (a railing right on the cell's edge let the path board a bridge from its side).
func _link(a: Vector3, b: Vector3) -> bool:
	var past := Vector3(b.x - a.x, 0, b.z - a.z).normalized() * 1.2
	for h: float in [0.5, 1.2]:
		var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * h - past * 0.5, b + Vector3.UP * h + past, 1)
		var hit := _space.intersect_ray(q)
		if not hit.is_empty() and not _breakable(hit) and not (_is_ground(hit) and (hit.normal as Vector3).y > 0.7):
			return false
	return true


## Where to drive next on the way from `from` to `to`: a point on the path, the furthest one in sight within
## LOOK m. INF when there is no path (then the caller drives straight on).
func next_point(asker: Object, from: Vector3, to: Vector3) -> Vector3:
	if not built:
		build()
	var key := asker.get_instance_id()
	var now := Time.get_ticks_msec()
	var c: Dictionary = _cache.get(key, {})
	# The path is kept while the goal stays put and the car stays on it (recomputing it every few frames made the
	# car swing between two routes of about the same length round a block).
	var on := -1
	if not c.is_empty() and (c.to as Vector3).distance_to(to) < 8.0 and now - int(c.t) < 6000:
		on = _closest_index(c.path, from)
		if on < 0 or (c.path[on] as Vector3).distance_to(from) > 9.0:
			on = -1
	if on < 0:
		var a := _nearest(from)
		var b := _nearest(to)
		if a < 0 or b < 0:
			return Vector3.INF
		c = {"to": to, "path": astar.get_point_path(a, b), "t": now}
		_cache[key] = c
		on = 0
	var path: PackedVector3Array = c.path
	if path.size() < 2:
		return Vector3.INF
	var best := path[mini(on + 1, path.size() - 1)]
	for i in range(on + 1, path.size()):
		var p := path[i]
		if p.distance_to(from) > LOOK:
			break
		if absf(p.y - from.y) < 2.5 and _open(from, p):
			best = p
	return best


func _closest_index(path: PackedVector3Array, p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in path.size():
		var d := path[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## The nearest grid point on the surface under/near p (the cell's layer closest in height).
func _nearest(p: Vector3) -> int:
	var ix := clampi(roundi((p.x - x0) / CELL), 0, nx - 1)
	var iz := clampi(roundi((p.z - z0) / CELL), 0, nz - 1)
	var best := -1
	var best_d := INF
	for r in 3: # search rings out to 2 cells
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var k := (iz + dz) * nx + (ix + dx)
				if ix + dx < 0 or ix + dx >= nx or iz + dz < 0 or iz + dz >= nz or not _ids.has(k):
					continue
				for id: int in _ids[k]:
					var q := astar.get_point_position(id)
					var dd := Vector2(q.x - p.x, q.z - p.z).length() + absf(q.y - p.y) * 3.0
					if dd < best_d:
						best_d = dd
						best = id
		if best >= 0:
			return best
	return astar.get_closest_point(p) if astar.get_point_count() > 0 else -1


func _down(from: Vector3, to_y: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, to_y, from.z), 1)
	return _space.intersect_ray(q)


func _is_ground(hit: Dictionary) -> bool:
	var c: Object = hit.collider
	return c is Node and (c as Node).is_in_group(&"ground")


## Room for a car standing here (nothing solid 0.6 - 2.4 m over it: under a bridge's deck is fine at 3.7 m).
func _clearance(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.4, p + Vector3.UP * 0.6, 1)
	q.hit_from_inside = true
	var hit := _space.intersect_ray(q)
	return hit.is_empty() or _breakable(hit)


## Nothing solid between two points at bonnet height (props a car knocks over don't count).
func _open(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * EYE, b + Vector3.UP * EYE, 1)
	var hit := _space.intersect_ray(q)
	if hit.is_empty() or _breakable(hit):
		return true
	return _is_ground(hit) and (hit.normal as Vector3).y > 0.7 # the slope of a ramp rising ahead


func _breakable(hit: Dictionary) -> bool:
	return hit.collider is Breakable or hit.collider is Vehicle
