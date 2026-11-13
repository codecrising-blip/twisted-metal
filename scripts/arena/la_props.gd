class_name LaProps
extends Node3D
## Street furniture and battle damage inside the Los Angeles arena, so it reads as a wrecked city
## block and not an empty lot (owner, session 5): street lights that topple when hit, burnt car
## wrecks, billboards for Calypso's contest, power poles with sagging wires, traffic lights, jersey
## barriers, dumpsters, a shipping container stack, rubble, manholes and oil stains.
## Each kind of prop is built once into one mesh and reused, so it stays cheap on the HD 5500.
## Solid props share one StaticBody3D with a box per prop. Every place is checked against the
## layout (road, ramps, hills, battleground edge, tunnels) by _free().


var _rng := RandomNumberGenerator.new()
var _arena: LosAngelesArena # static props go into its merged stage mesh
var _body: StaticBody3D
var _meshes := {}


func build(arena: LosAngelesArena) -> void:
	_arena = arena
	_rng.seed = 4242
	_body = StaticBody3D.new()
	_body.name = "PropColliders"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_street_lights()
	_wrecks()
	_billboards()
	_power_lines()
	_traffic_lights()
	_barriers_and_bins()
	_container_stack()
	_rubble()
	_road_marks()
	_street_bits()


func _solid(size: Vector3, pos: Vector3, yaw_deg := 0.0) -> void:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = pos
	shape.rotation_degrees.y = yaw_deg
	_body.add_child(shape)


## A prop mesh. Static ones (no parent) are merged into the stage; parts of breakables get a node.
func _place(mesh: Mesh, pos: Vector3, yaw_deg := 0.0, parent: Node3D = null) -> MeshInstance3D:
	if parent == null:
		_arena.batch_mesh(mesh, transform * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	(parent if parent else self).add_child(mi)
	return mi


static func _ground_at(x: float, z: float) -> Vector3:
	return LosAngelesArena.on_mesh(x, z)


## True if a prop of this radius fits here: off the road, away from ramps, hills, the tunnels,
## the battleground's cliff edge and the walls.
static func _free(p: Vector3, radius: float, road_gap := 2.0) -> bool:
	if LosAngelesArena.road_distance(p.x, p.z) < LosAngelesArena.ROAD_W * 0.5 + road_gap + radius:
		return false
	if absf(LosAngelesArena.edge_distance(p.x, p.z)) < 4.0 + radius:
		return false
	for rp: Dictionary in LosAngelesArena.ramp_list():
		var mid: Vector3 = (Vector3(rp.top.x, 0, rp.top.z) + rp.foot) * 0.5
		if Vector2(p.x - mid.x, p.z - mid.z).length() < LosAngelesArena.RAMP_L * 0.5 + 8.0 + radius:
			return false
	for hill: Dictionary in LosAngelesArena.hills():
		if Vector2(p.x, p.z).distance_to(hill.p) < 18.0 + radius:
			return false
	if absf(p.x) < LosAngelesArena.TUNNEL_X + 10.0 and p.z < LosAngelesArena.TUNNEL_Z1 + 30.0:
		return false
	if absf(p.x) > LosAngelesArena.HALF - 3.0 - radius or absf(p.z) > LosAngelesArena.HALF - 3.0 - radius:
		return false
	return absf(p.x) + absf(p.z) < 2.0 * LosAngelesArena.HALF - LosAngelesArena.WALL_CHAMFER - 5.0 - radius


# ---------------------------------------------------------------- materials

func _steel() -> StandardMaterial3D:
	return MatKit.steel(Color(0.22, 0.22, 0.23), 0.55, 1.0)


func _dark() -> StandardMaterial3D:
	return MatKit.steel(Color(0.07, 0.07, 0.075), 0.35, 1.0)


func _concrete() -> StandardMaterial3D:
	return MatKit.paint(Color(0.55, 0.54, 0.5), 0.5, 0.0, 0.7, 2.0, 0.92, 61)


# ---------------------------------------------------------------- street lights

func _lamp_mesh() -> ArrayMesh:
	if _meshes.has("lamp"):
		return _meshes.lamp
	var mb := MeshBuilder.new()
	var pole := MatKit.paint(Color(0.3, 0.32, 0.3), 0.15, 0.5, 0.6, 1.0, 0.6, 62)
	mb.cylinder(pole, 0.2, 0.5, MeshBuilder.at(Vector3(0, 0.25, 0)), 8)
	mb.cylinder(pole, 0.12, 8.5, MeshBuilder.at(Vector3(0, 4.5, 0)), 8, 0.08)
	var a := Vector3(0, 8.6, 0)
	var b := Vector3(0, 9.2, -2.6)
	mb.cylinder(pole, 0.06, a.distance_to(b), MeshBuilder.along((a + b) * 0.5, b - a), 6)
	mb.box(_dark(), Vector3(0.5, 0.18, 0.9), MeshBuilder.at(Vector3(0, 9.15, -2.9)), 0.05)
	mb.box(MatKit.lamp(Color(1.0, 0.85, 0.6), 0.8), Vector3(0.36, 0.03, 0.7), MeshBuilder.at(Vector3(0, 9.05, -2.9)), 0.0)
	mb.box(_dark(), Vector3(0.24, 0.4, 0.16), MeshBuilder.at(Vector3(0, 2.2, 0.14)), 0.02)
	_meshes.lamp = mb.build_mesh(0.6, 0.0, true)
	return _meshes.lamp


## Lamps along the road edges, arm over the road. They topple when a car hits them.
func _street_lights() -> void:
	var pts := LosAngelesArena.road_points()
	var k := 4
	var side := 1.0
	while k < pts.size():
		var p := pts[k]
		var dir := (pts[(k + 1) % pts.size()] - pts[(k - 1 + pts.size()) % pts.size()]).normalized()
		var across := Vector3(-dir.z, 0, dir.x)
		var pos := p + across * side * (LosAngelesArena.ROAD_W * 0.5 + 1.6)
		var toward_road := -across * side
		k += 13
		side = -side
		if not _free(pos, 0.3, -1.4) or LosAngelesArena.road_distance(pos.x, pos.z) < LosAngelesArena.ROAD_W * 0.5 + 1.0:
			continue
		var lamp := Breakable.new()
		lamp.style = Breakable.Style.TOPPLE
		lamp.health = Breakable.MG_HEALTH
		lamp.debris_color = Color(0.3, 0.32, 0.3)
		lamp.kind = "metal"
		lamp.size_hint = Vector3(0.5, 8.0, 0.5)
		lamp.topple_height = 8.0
		lamp.position = _ground_at(pos.x, pos.z)
		lamp.basis = Basis.looking_at(toward_road, Vector3.UP) # arm (local -Z) reaches over the road
		add_child(lamp)
		lamp.add_box_shape(Vector3(0.5, 8.0, 0.5), Vector3(0, 4.0, 0))
		lamp.add_cover(1.1, 6.0) # hide behind it from missiles (round 9)
		_place(_lamp_mesh(), Vector3.ZERO, 0.0, lamp.visual)


# ---------------------------------------------------------------- wrecks

## A burnt-out sedan shell: no glass, no tires, scorched paint, rust.
func _wreck_mesh(variant: int) -> ArrayMesh:
	var key := "wreck_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	var burnt := MatKit.paint(Color(0.16, 0.12, 0.1), 0.9, 0.95, 0.9, 1.5, 0.95, 70 + variant)
	var paint := MatKit.paint([Color(0.35, 0.12, 0.1), Color(0.18, 0.24, 0.3), Color(0.4, 0.38, 0.32)][variant % 3], 0.9, 0.9, 0.8, 1.5, 0.8, 73 + variant)
	var black := MatKit.flat(Color(0.02, 0.02, 0.02), 0.95)
	var rim := MatKit.steel(Color(0.2, 0.15, 0.12), 0.9, 0.6)
	var tilt := 4.0 if variant % 2 == 0 else -3.0
	var lower := [MeshBuilder.section(-2.3, 0.62, 0.86, 0.26, 0.1), MeshBuilder.section(-1.7, 0.7, 0.92, 0.3, 0.12),
		MeshBuilder.section(1.8, 0.72, 0.92, 0.32, 0.12), MeshBuilder.section(2.35, 0.66, 0.86, 0.26, 0.1)]
	mb.loft(paint if variant == 1 else burnt, lower, MeshBuilder.at(Vector3.ZERO, Vector3(0, 0, tilt)), 3)
	var cab := [MeshBuilder.section(-0.8, 1.02, 0.88, 0.02, 0.01, 0.84), MeshBuilder.section(-0.2, 1.25, 0.86, 0.24, 0.08, 0.72),
		MeshBuilder.section(0.9, 1.22, 0.86, 0.22, 0.08, 0.72), MeshBuilder.section(1.5, 1.02, 0.88, 0.02, 0.01, 0.82)]
	mb.loft(burnt, cab, MeshBuilder.at(Vector3(0, -0.04, 0), Vector3(0, 0, tilt)), 3)
	# Empty window holes.
	for side: float in [-1.0, 1.0]:
		mb.box(black, Vector3(0.02, 0.3, 1.6), MeshBuilder.at(Vector3(0.84 * side, 1.12, 0.35), Vector3(0, 0, tilt - 18.0 * side)), 0.0)
	mb.box(black, Vector3(1.4, 0.28, 0.02), MeshBuilder.at(Vector3(0, 1.1, -0.58), Vector3(-40, 0, tilt)), 0.0)
	# Bare rims sitting on the ground, one wheel missing.
	for x: float in [-0.82, 0.82]:
		for z: float in [-1.45, 1.45]:
			if variant == 2 and x > 0.0 and z > 0.0:
				continue
			mb.cylinder(rim, 0.3, 0.2, MeshBuilder.at(Vector3(x, 0.3, z), Vector3(0, 0, 90)), 10)
	mb.box(black, Vector3(1.7, 0.1, 4.4), MeshBuilder.at(Vector3(0, 0.32, 0)), 0.0)
	_meshes[key] = mb.build_mesh(0.8, 0.0, true)
	return _meshes[key]


func _wrecks() -> void:
	# On the battleground they are cover; out on the low ground they are just wrecks.
	var candidates := [[Vector3(28, 0, 66), 20.0], [Vector3(-68, 0, 18), 75.0], [Vector3(12, 0, -68), 160.0],
		[Vector3(-28, 0, -24), 120.0], [Vector3(130, 0, -128), 35.0], [Vector3(-118, 0, 128), -50.0],
		[Vector3(104, 0, 128), 80.0], [Vector3(-140, 0, -110), -20.0], [Vector3(140, 0, 30), 170.0]]
	var spots: Array = []
	for c in candidates:
		if _free(c[0], 2.5):
			spots.append(c)
	# Round 9 (owner: "they stop my momentum for no reason"): a wreck bursts apart when you drive
	# into it or shoot it, so it is cover for a moment, never a dead stop.
	for i in spots.size():
		var p: Vector3 = spots[i][0]
		var yaw: float = spots[i][1]
		var b := Breakable.new()
		b.kind = "wreck"
		b.size_hint = Vector3(1.9, 1.3, 4.7)
		b.debris_color = Color(0.16, 0.12, 0.1)
		b.position = _ground_at(p.x, p.z)
		b.rotation_degrees.y = yaw
		add_child(b)
		b.add_box_shape(Vector3(1.9, 1.3, 4.7), Vector3(0, 0.65, 0))
		_place(_wreck_mesh(i % 3), Vector3.ZERO, 0.0, b.visual)
		if i % 3 == 0:
			var smoke := FxKit.smoke(0.9, 10)
			smoke.position = Vector3(0, 1.3, 0)
			smoke.color_ramp = null
			smoke.color = Color(0.15, 0.14, 0.13, 0.35)
			b.visual.add_child(smoke)
			smoke.emitting = true


# ---------------------------------------------------------------- billboards

func _billboards() -> void:
	var boards := [
		[Vector3(-60, 0, LosAngelesArena.HALF - 5.0), 0.0, "CALYPSO'S CONTEST", "WIN ONE WISH. ANY WISH.", Color(0.65, 0.12, 0.1)],
		[Vector3(LosAngelesArena.HALF - 5.0, 0, -62), 90.0, "LAST ONE DRIVING", "GETS EVERYTHING", Color(0.75, 0.58, 0.12)],
		[Vector3(-LosAngelesArena.HALF + 5.0, 0, -78), -90.0, "QUAKE ZONE", "NO ENTRY  -  BY ORDER OF THE CITY", Color(0.15, 0.32, 0.55)],
	]
	var steel := _steel()
	var dark := _dark()
	for b in boards:
		var pos: Vector3 = _ground_at(b[0].x, b[0].z)
		var yaw: float = b[1]
		var node := Node3D.new()
		node.position = pos
		node.rotation_degrees.y = yaw
		add_child(node)
		var mb := MeshBuilder.new()
		for x: float in [-4.5, 4.5]:
			mb.box(steel, Vector3(0.5, 9.0, 0.5), MeshBuilder.at(Vector3(x, 4.5, 0.4)), 0.04)
			mb.box(steel, Vector3(0.2, 0.2, 2.6), MeshBuilder.at(Vector3(x, 5.0, 1.4), Vector3(-45, 0, 0)), 0.0)
		mb.box(dark, Vector3(15.0, 5.6, 0.4), MeshBuilder.at(Vector3(0, 11.6, 0.2)), 0.06)
		mb.box(MatKit.paint(b[4], 0.6, 0.3, 0.5, 4.0, 0.7, 80), Vector3(14.4, 5.0, 0.05), MeshBuilder.at(Vector3(0, 11.6, -0.02)), 0.0)
		mb.box(steel, Vector3(15.6, 0.15, 1.2), MeshBuilder.at(Vector3(0, 8.7, -0.4)), 0.0)
		for k in 3:
			mb.box(dark, Vector3(0.3, 0.3, 0.8), MeshBuilder.at(Vector3(-5.0 + k * 5.0, 14.6, -0.5), Vector3(30, 0, 0)), 0.03)
		_arena.batch_builder(mb, true, 0.3, node.transform)
		for line in 2:
			var txf := node.transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 12.6 if line == 0 else 10.4, -0.06))
			_arena.batch_text(b[2] if line == 0 else b[3], txf, 200 if line == 0 else 110, 0.009,
				Color(0.92, 0.9, 0.84) if line == 0 else Color(0.1, 0.08, 0.07))
		for x: float in [-4.5, 4.5]:
			_solid(Vector3(0.6, 9.0, 0.6), pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(x, 4.5, 0.4))


# ---------------------------------------------------------------- power lines

func _power_lines() -> void:
	var wood := MatKit.paint(Color(0.3, 0.24, 0.17), 0.3, 0.0, 0.6, 0.8, 0.95, 90)
	var dark := _dark()
	var wire := MatKit.flat(Color(0.03, 0.03, 0.03), 0.8)
	var mb := MeshBuilder.new()
	var runs := [[Vector3(-LosAngelesArena.HALF + 6.0, 0, 75), Vector3(-LosAngelesArena.HALF + 6.0, 0, 128)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var count := int(a.distance_to(b) / 30.0) + 1
		var tops: Array[Vector3] = []
		for k in count:
			var p := a.lerp(b, float(k) / (count - 1))
			if LosAngelesArena.road_distance(p.x, p.z) < LosAngelesArena.ROAD_W * 0.5 + 2.0:
				continue
			var g := _ground_at(p.x, p.z)
			mb.cylinder(wood, 0.16, 11.0, MeshBuilder.at(g + Vector3(0, 5.5, 0)), 7, 0.12)
			var across := (b - a).normalized().cross(Vector3.UP)
			mb.box(wood, Vector3(0.14, 0.14, 2.4), MeshBuilder.at(g + Vector3(0, 10.2, 0), Vector3(0, rad_to_deg(atan2(across.x, across.z)), 0)), 0.0)
			mb.cylinder(dark, 0.22, 0.7, MeshBuilder.at(g + Vector3(0, 8.6, 0) + across * 0.3), 8)
			tops.append(g + Vector3(0, 10.3, 0))
			_solid(Vector3(0.4, 11.0, 0.4), g + Vector3(0, 5.5, 0))
		var across_all := (b - a).normalized().cross(Vector3.UP)
		for k in tops.size() - 1:
			for w: float in [-1.0, 0.0, 1.0]:
				var p0 := tops[k] + across_all * w
				var p1 := tops[k + 1] + across_all * w
				var prev := p0
				for s in 6:
					var t := float(s + 1) / 6.0
					var p := p0.lerp(p1, t) - Vector3(0, sin(t * PI) * 1.2, 0)
					mb.cylinder(wire, 0.02, prev.distance_to(p), MeshBuilder.along((prev + p) * 0.5, p - prev), 3, -1.0, false)
					prev = p
	_arena.batch_builder(mb, true, 0.4)


# ---------------------------------------------------------------- traffic lights

func _traffic_lights() -> void:
	var dark := _dark()
	var steel := _steel()
	var mb := MeshBuilder.new()
	var lamps := [MatKit.lamp(Color(0.9, 0.08, 0.05), 2.5), MatKit.lamp(Color(0.25, 0.2, 0.05), 0.2), MatKit.lamp(Color(0.05, 0.2, 0.08), 0.2)]
	for f: float in [0.18, 0.47, 0.74, 0.93]:
		var r := LosAngelesArena.road_at(f)
		var dir: Vector3 = r.dir
		var across := Vector3(-dir.z, 0, dir.x)
		var outer := across if (r.p as Vector3).dot(across) > 0.0 else -across
		var corner: Vector3 = r.p + outer * (LosAngelesArena.ROAD_W * 0.5 + 2.2)
		if not _free(corner, 0.3, -1.6):
			continue
		var g := _ground_at(corner.x, corner.z)
		var inward := -outer
		mb.cylinder(steel, 0.14, 6.0, MeshBuilder.at(g + Vector3(0, 3.0, 0)), 8)
		var arm_end := g + Vector3(0, 6.0, 0) + inward * 5.0
		mb.cylinder(steel, 0.08, 5.0, MeshBuilder.along((g + Vector3(0, 6.0, 0) + arm_end) * 0.5, arm_end - g - Vector3(0, 6.0, 0)), 6)
		var yaw := rad_to_deg(atan2(inward.x, inward.z))
		mb.box(dark, Vector3(0.45, 1.3, 0.4), MeshBuilder.at(arm_end + Vector3(0, -0.7, 0), Vector3(0, yaw, 0)), 0.05)
		for k in 3:
			var lp := arm_end + Vector3(0, -0.3 - k * 0.4, 0) + inward * 0.21
			mb.cylinder(lamps[k], 0.13, 0.04, MeshBuilder.along(lp, inward), 10)
		_solid(Vector3(0.4, 6.0, 0.4), g + Vector3(0, 3.0, 0))
	_arena.batch_builder(mb, true, 0.3)


# ---------------------------------------------------------------- barriers, bins, containers

func _barrier_mesh() -> ArrayMesh:
	if _meshes.has("barrier"):
		return _meshes.barrier
	var mb := MeshBuilder.new()
	var conc := _concrete()
	mb.loft(conc, [MeshBuilder.section(-1.5, 0.4, 0.3, 0.4, 0.05, 0.12), MeshBuilder.section(1.5, 0.4, 0.3, 0.4, 0.05, 0.12)], Transform3D.IDENTITY, 1)
	mb.box(MatKit.flat(Color(0.62, 0.5, 0.12), 0.8), Vector3(0.62, 0.12, 2.9), MeshBuilder.at(Vector3(0, 0.12, 0)), 0.0)
	_meshes.barrier = mb.build_mesh(0.7, 0.0, true)
	return _meshes.barrier


func _dumpster_mesh() -> ArrayMesh:
	if _meshes.has("dumpster"):
		return _meshes.dumpster
	var mb := MeshBuilder.new()
	var green := MatKit.paint(Color(0.12, 0.24, 0.16), 0.8, 0.8, 0.8, 1.5, 0.7, 95)
	var dark := _dark()
	mb.box(green, Vector3(1.9, 1.3, 1.3), MeshBuilder.at(Vector3(0, 0.8, 0)), 0.05)
	mb.box(dark, Vector3(2.0, 0.08, 1.4), MeshBuilder.at(Vector3(0, 1.5, 0.05), Vector3(-8, 0, 0)), 0.02)
	for x: float in [-0.75, 0.75]:
		for z: float in [-0.5, 0.5]:
			mb.cylinder(dark, 0.08, 0.1, MeshBuilder.at(Vector3(x, 0.08, z), Vector3(0, 0, 90)), 8)
	_meshes.dumpster = mb.build_mesh(0.6, 0.0, true)
	return _meshes.dumpster


func _barriers_and_bins() -> void:
	# Barrier rows on the battleground (cover to fight around), plus a few along its edge. Keep them
	# well clear of ramp sides and walls: a 2 m slot traps a car (round 7, beside the cage ramp).
	var rows := [[Vector3(-46, 0, -6), 0.0, 4], [Vector3(36, 0, 22), 90.0, 4], [Vector3(-12, 0, 66), 90.0, 3],
		[Vector3(78, 0, -16), 0.0, 3], [Vector3(-84, 0, -66), 0.0, 3], [Vector3(-36, 0, 76), 90.0, 3]]
	for r in rows:
		var start: Vector3 = r[0]
		var yaw: float = r[1]
		var n: int = r[2]
		var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1)
		# Round 9 (owner: "concrete lines stop my momentum, make them work like a ramp"): each row is a
		# low concrete kicker, sloped on both sides, to drive over and jump with turbo.
		var mid := start + dir * ((n - 1) * 3.05 * 0.5)
		_kicker(_ground_at(mid.x, mid.z), yaw, n * 3.05)
	var h := LosAngelesArena.HALF
	for spot in [[Vector3(-84, 0, h - 5.0), 0.0], [Vector3(52, 0, h - 5.0), 5.0], [Vector3(h - 5.0, 0, 84), -90.0],
			[Vector3(-h + 5.0, 0, 70), 90.0], [Vector3(-h + 5.0, 0, -50), 90.0], [Vector3(84, 0, -h + 5.0), 180.0]]:
		if LosAngelesArena.road_distance(spot[0].x, spot[0].z) < LosAngelesArena.ROAD_W * 0.5 + 2.5:
			continue
		var g := _ground_at(spot[0].x, spot[0].z)
		_place(_dumpster_mesh(), g, spot[1])
		_solid(Vector3(1.9, 1.5, 1.3), g + Vector3(0, 0.75, 0), spot[1])


const KICKER_H := 0.9 # height of the concrete kickers
const KICKER_SLOPE := 3.0 # run of each slope (about 17 degrees)


## A concrete kicker ramp `length` long, its ridge along local z (rotated by yaw), sloped both ways,
## with yellow hazard stripes on the slopes. One collider (a convex prism) on the shared body.
func _kicker(base: Vector3, yaw: float, length: float) -> void:
	var hw := KICKER_SLOPE + 0.4
	var ht := 0.4
	var hl := length * 0.5
	var conc := _concrete()
	var yellow := MatKit.flat(Color(0.75, 0.6, 0.12), 0.8)
	var mb := MeshBuilder.new()
	var p := [Vector3(-hw, 0, -hl), Vector3(-ht, KICKER_H, -hl), Vector3(ht, KICKER_H, -hl), Vector3(hw, 0, -hl)]
	var q := [Vector3(-hw, 0, hl), Vector3(-ht, KICKER_H, hl), Vector3(ht, KICKER_H, hl), Vector3(hw, 0, hl)]
	mb.quad(conc, p[0], p[1], q[1], q[0], Vector3(-KICKER_H, KICKER_SLOPE, 0).normalized())
	mb.quad(conc, p[1], p[2], q[2], q[1], Vector3.UP)
	mb.quad(conc, p[2], p[3], q[3], q[2], Vector3(KICKER_H, KICKER_SLOPE, 0).normalized())
	mb.quad(conc, p[0], p[1], p[2], p[3], Vector3.BACK * -1.0)
	mb.quad(conc, q[0], q[1], q[2], q[3], Vector3.BACK)
	# Hazard stripes across both slopes, every 1.6 m.
	var n_str := int(length / 1.6)
	for k in n_str:
		var z := -hl + (k + 0.5) * length / n_str
		for sx: float in [-1.0, 1.0]:
			var lift := Vector3(sx * KICKER_H, KICKER_SLOPE, 0).normalized() * 0.015
			mb.quad(yellow, Vector3(sx * hw * 0.92, 0.08, z - 0.25) + lift, Vector3(sx * ht, KICKER_H, z - 0.25) + lift,
				Vector3(sx * ht, KICKER_H, z + 0.25) + lift, Vector3(sx * hw * 0.92, 0.08, z + 0.25) + lift, Vector3(sx * KICKER_H, KICKER_SLOPE, 0).normalized())
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), base)
	_arena.batch_builder(mb, true, 0.6, transform * xf)
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array(p + q)
	shape.shape = hull
	shape.transform = xf
	_body.add_child(shape)


func _container_stack() -> void:
	var colors := [Color(0.5, 0.18, 0.12), Color(0.15, 0.28, 0.4), Color(0.45, 0.4, 0.2)]
	var mb := MeshBuilder.new()
	var base := _ground_at(-74, 46)
	var dark := _dark()
	for i in 3:
		var paint := MatKit.paint(colors[i], 0.8, 0.85, 0.7, 2.0, 0.7, 100 + i)
		var p := base + (Vector3(0, 1.3, 0) if i < 2 else Vector3(1.0, 3.9, 0.4))
		if i == 1:
			p += Vector3(0, 0, 2.6)
		var yaw := 0.0 if i < 2 else 6.0
		mb.box(paint, Vector3(12.0, 2.6, 2.45), MeshBuilder.at(p, Vector3(0, yaw, 0)), 0.04)
		for k in 24:
			var x := -5.75 + k * 0.5
			for side: float in [-1.0, 1.0]:
				mb.box(paint, Vector3(0.18, 2.3, 0.06), MeshBuilder.at(p + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(x, 0, 1.24 * side), Vector3(0, yaw, 0)), 0.0)
		mb.box(dark, Vector3(0.08, 2.4, 2.3), MeshBuilder.at(p + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(6.02, 0, 0), Vector3(0, yaw, 0)), 0.0)
	_arena.batch_builder(mb, true, 0.5)
	_solid(Vector3(12.2, 2.6, 5.1), base + Vector3(0, 1.3, 1.3))


# ---------------------------------------------------------------- rubble, manholes, stains

func _rubble() -> void:
	var conc := _concrete()
	var rebar := MatKit.steel(Color(0.3, 0.18, 0.1), 0.95, 0.5)
	var mb := MeshBuilder.new()
	for i in 90:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, 34.0) if i < 50 else _rng.randf_range(4.0, 14.0)
		var c := Vector3(cos(a) * r, 0, sin(a) * r)
		if i >= 50:
			c += Vector3(LosAngelesArena.BURNT_AT.x, 0, LosAngelesArena.BURNT_AT.z) # around the burnt building
		var g := _ground_at(c.x, c.z)
		var s := Vector3(_rng.randf_range(0.2, 0.55), _rng.randf_range(0.12, 0.35), _rng.randf_range(0.2, 0.6))
		mb.box(conc, s, MeshBuilder.at(g + Vector3(0, s.y * 0.35, 0), Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 360), _rng.randf_range(-20, 20))), 0.03)
		if i % 6 == 0:
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.6, 1.0), _rng.randf_range(-1, 1)).normalized()
			mb.cylinder(rebar, 0.015, 0.9, MeshBuilder.along(g + d * 0.4, d), 4, -1.0, false)
	_arena.batch_builder(mb, false, 0.6)


func _stain_mat() -> StandardMaterial3D:
	if _meshes.has("stain"):
		return _meshes.stain
	var m := StandardMaterial3D.new()
	m.albedo_texture = FxKit.soft_texture()
	m.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.35
	m.disable_receive_shadows = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_meshes.stain = m
	return m


func _road_marks() -> void:
	var iron := MatKit.steel(Color(0.12, 0.12, 0.12), 0.6, 0.4)
	var pts := LosAngelesArena.road_points()
	var mb := MeshBuilder.new()
	for k in range(7, pts.size(), 23):
		var p := pts[k]
		var near_hill := false
		for hill: Dictionary in LosAngelesArena.hills():
			if Vector2(p.x, p.z).distance_to(hill.p) < 16.0:
				near_hill = true
		if near_hill:
			continue
		var dir := (pts[(k + 1) % pts.size()] - p).normalized()
		var q := p + Vector3(-dir.z, 0, dir.x) * 3.0
		mb.cylinder(iron, 0.38, 0.03, MeshBuilder.at(_ground_at(q.x, q.z) + Vector3(0, 0.05, 0)), 14)
	_arena.batch_builder(mb, false)
	# Oil stains and tire marks as soft dark patches lying on the road: all in one mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 44:
		var k := _rng.randi_range(0, pts.size() - 1)
		var p := pts[k]
		var dir := (pts[(k + 1) % pts.size()] - p).normalized()
		p += Vector3(-dir.z, 0, dir.x) * _rng.randf_range(-6.0, 6.0)
		var g := LosAngelesArena.on_mesh(p.x, p.z, 0.1)
		var long := i % 3 == 0
		var size := Vector2(0.5, _rng.randf_range(6.0, 12.0)) if long else Vector2.ONE * _rng.randf_range(1.0, 3.2)
		var yaw := atan2(-dir.x, -dir.z) + (_rng.randf_range(-0.2, 0.2) if long else _rng.randf() * TAU)
		var basis := Basis(Vector3.UP, yaw)
		var ax := basis * Vector3(size.x * 0.5, 0, 0)
		var az := basis * Vector3(0, 0, size.y * 0.5)
		var c := [g - ax - az, g + ax - az, g + ax + az, g - ax + az]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(c[idx])
	st.index()
	_arena.batch_mesh(st.commit(), transform, false, _stain_mat())


# ---------------------------------------------------------------- small street furniture

func _hydrant_mesh() -> ArrayMesh:
	if _meshes.has("hydrant"):
		return _meshes.hydrant
	var mb := MeshBuilder.new()
	var red := MatKit.paint(Color(0.55, 0.1, 0.07), 0.4, 0.3, 0.6, 0.5, 0.6, 180)
	var steel := _steel()
	mb.cylinder(red, 0.18, 0.7, MeshBuilder.at(Vector3(0, 0.35, 0)), 10)
	mb.sphere(red, 0.2, MeshBuilder.at(Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), 10, 5)
	for a: float in [0.0, 180.0]:
		mb.cylinder(steel, 0.07, 0.18, MeshBuilder.at(Vector3(0, 0.5, 0), Vector3(0, a, 90)) * MeshBuilder.at(Vector3(0, 0.18, 0)), 8)
	mb.cylinder(steel, 0.26, 0.08, MeshBuilder.at(Vector3(0, 0.04, 0)), 10)
	_meshes.hydrant = mb.build_mesh(0.6, 0.0, true)
	return _meshes.hydrant


func _trash_mesh() -> ArrayMesh:
	if _meshes.has("trash"):
		return _meshes.trash
	var mb := MeshBuilder.new()
	var green := MatKit.paint(Color(0.16, 0.24, 0.18), 0.6, 0.6, 0.7, 0.6, 0.7, 181)
	var dark := _dark()
	mb.cylinder(green, 0.32, 0.95, MeshBuilder.at(Vector3(0, 0.48, 0)), 10, 0.36)
	mb.cylinder(dark, 0.38, 0.1, MeshBuilder.at(Vector3(0, 1.0, 0)), 10)
	_meshes.trash = mb.build_mesh(0.6, 0.0, true)
	return _meshes.trash


func _cone_mesh() -> ArrayMesh:
	if _meshes.has("cone"):
		return _meshes.cone
	var mb := MeshBuilder.new()
	var orange := MatKit.paint(Color(0.75, 0.3, 0.06), 0.3, 0.0, 0.6, 0.5, 0.6, 182)
	var white := MatKit.flat(Color(0.82, 0.8, 0.75), 0.6)
	mb.cylinder(orange, 0.2, 0.72, MeshBuilder.at(Vector3(0, 0.4, 0)), 10, 0.04)
	mb.cylinder(white, 0.15, 0.1, MeshBuilder.at(Vector3(0, 0.45, 0)), 10, 0.12, false)
	mb.box(orange, Vector3(0.5, 0.05, 0.5), MeshBuilder.at(Vector3(0, 0.025, 0)), 0.02)
	_meshes.cone = mb.build_mesh(0.5, 0.0, true)
	return _meshes.cone


func _bus_stop_mesh() -> ArrayMesh:
	if _meshes.has("bus"):
		return _meshes.bus
	var mb := MeshBuilder.new()
	var steel := _steel()
	var glass := MatKit.flat(Color(0.1, 0.13, 0.15), 0.15, 0.3)
	var ad := MatKit.paint(Color(0.55, 0.12, 0.1), 0.3, 0.0, 0.5, 1.0, 0.6, 183)
	for x: float in [-1.8, 1.8]:
		for z: float in [-0.6, 0.6]:
			mb.box(steel, Vector3(0.08, 2.5, 0.08), MeshBuilder.at(Vector3(x, 1.25, z)), 0.0)
	mb.box(steel, Vector3(4.0, 0.12, 1.6), MeshBuilder.at(Vector3(0, 2.55, 0)), 0.03)
	mb.box(glass, Vector3(3.6, 1.8, 0.04), MeshBuilder.at(Vector3(0, 1.4, 0.62)), 0.0)
	mb.box(ad, Vector3(0.04, 1.8, 1.1), MeshBuilder.at(Vector3(1.8, 1.4, 0)), 0.0)
	mb.box(_dark(), Vector3(2.4, 0.08, 0.4), MeshBuilder.at(Vector3(0, 0.5, 0.35)), 0.0)
	_meshes.bus = mb.build_mesh(0.6, 0.0, true)
	return _meshes.bus


## Hydrants, trash cans and cones on the outside sidewalk (they break when hit), a bus stop.
func _street_bits() -> void:
	var pts := LosAngelesArena.road_points()
	var n := pts.size()
	var k := 6
	var kind := 0
	while k < n:
		var p := pts[k]
		var dir := (pts[(k + 1) % n] - pts[(k - 1 + n) % n]).normalized()
		var outside := -Vector3(-dir.z, 0, dir.x) # the loop runs clockwise: outside is -normal
		var pos := p + outside * (LosAngelesArena.ROAD_W * 0.5 + 1.6)
		k += 17
		kind = (kind + 1) % 4
		if not _free(pos, 0.4, -1.6) or LosAngelesArena.road_distance(pos.x, pos.z) < LosAngelesArena.ROAD_W * 0.5 + 0.9:
			continue
		var b := Breakable.new()
		b.health = Breakable.MG_HEALTH
		b.kind = "prop"
		b.size_hint = Vector3(0.6, 1.0, 0.6)
		b.debris_color = [Color(0.55, 0.1, 0.07), Color(0.16, 0.24, 0.18), Color(0.75, 0.3, 0.06), Color(0.75, 0.3, 0.06)][kind]
		b.position = _ground_at(pos.x, pos.z)
		b.rotation.y = _rng.randf() * TAU
		add_child(b)
		b.add_box_shape(Vector3(0.6, 1.0, 0.6), Vector3(0, 0.5, 0))
		var mesh: ArrayMesh = [_hydrant_mesh(), _trash_mesh(), _cone_mesh(), _cone_mesh()][kind]
		var bits: Array[MeshInstance3D] = [_place(mesh, Vector3.ZERO, 0.0, b.visual)]
		if kind >= 2: # cones come in little groups
			for c in 2:
				bits.append(_place(mesh, Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(0.8, 1.6)), _rng.randf_range(0, 90), b.visual))
		for mi in bits: # small: no shadow, not drawn from far away (draw calls on the HD 5500)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 80.0
	for f: float in [0.3, 0.68]:
		var r := LosAngelesArena.road_at(f)
		var dir: Vector3 = r.dir
		var outside := -Vector3(-dir.z, 0, dir.x)
		var pos: Vector3 = r.p + outside * (LosAngelesArena.ROAD_W * 0.5 + 3.4)
		if not _free(pos, 2.0, -3.0):
			continue
		var yaw := rad_to_deg(atan2(-outside.x, -outside.z)) + 180.0
		var g := _ground_at(pos.x, pos.z)
		_place(_bus_stop_mesh(), g, yaw)
		_solid(Vector3(4.0, 2.6, 1.4), g + Vector3(0, 1.3, 0), yaw)

