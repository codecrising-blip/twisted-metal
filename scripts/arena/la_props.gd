class_name LaProps
extends Node3D
## Street furniture and battle damage inside the Los Angeles arena, so it reads as a wrecked city
## block and not an empty lot (owner, session 5): street lights that topple when hit, burnt car
## wrecks, billboards for Calypso's contest, power poles with sagging wires, traffic lights, jersey
## barriers, dumpsters, a shipping container stack, rubble, manholes and oil stains.
## Each kind of prop is built once into one mesh and reused, so it stays cheap on the HD 5500.
## Solid props share one StaticBody3D with a box per prop. Places avoid the road, spawns, pickups,
## ramps, storefronts and the existing stands and palms.

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _meshes := {}


func build() -> void:
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


func _solid(size: Vector3, pos: Vector3, yaw_deg := 0.0) -> void:
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = pos
	shape.rotation_degrees.y = yaw_deg
	_body.add_child(shape)


func _place(mesh: Mesh, pos: Vector3, yaw_deg := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	(parent if parent else self).add_child(mi)
	return mi


static func _ground_at(x: float, z: float) -> Vector3:
	return LosAngelesArena.on_mesh(x, z)


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
	_meshes.lamp = mb.build_mesh(0.6)
	return _meshes.lamp


## Lamps along the outer edge of the ring road, facing the road. They topple when a car hits them.
func _street_lights() -> void:
	var h := LosAngelesArena.ROAD_H
	var edge := h + LosAngelesArena.ROAD_W * 0.5 + 2.0
	for t: float in [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]:
		for side in 4:
			var basis := Basis(Vector3.UP, side * PI * 0.5)
			var pos := basis * Vector3(t, 0, edge)
			if side == 3 and absf(t) < 40.0:
				continue # the tunnels cross the road on the west side
			if pos.distance_to(Vector3(20, 0, 110)) < 8.0 or pos.distance_to(Vector3(110, 0, 30)) < 8.0:
				continue
			var lamp := Breakable.new()
			lamp.style = Breakable.Style.TOPPLE
			lamp.health = 10.0
			lamp.debris_color = Color(0.3, 0.32, 0.3)
			lamp.position = _ground_at(pos.x, pos.z)
			lamp.rotation.y = side * PI * 0.5 # arm reaches over the road
			add_child(lamp)
			lamp.add_box_shape(Vector3(0.5, 8.0, 0.5), Vector3(0, 4.0, 0))
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
	_meshes[key] = mb.build_mesh(0.8)
	return _meshes[key]


func _wrecks() -> void:
	var spots := [[Vector3(104, 0, -104), 35.0], [Vector3(-104, 0, 106), -50.0], [Vector3(62, 0, 112), 80.0],
		[Vector3(20, 0, -110), 10.0], [Vector3(108, 0, 58), 170.0], [Vector3(-44, 0, -30), 120.0],
		[Vector3(-108, 0, -104), -20.0]]
	for i in spots.size():
		var p: Vector3 = spots[i][0]
		var yaw: float = spots[i][1]
		var g := _ground_at(p.x, p.z)
		_place(_wreck_mesh(i % 3), g, yaw)
		_solid(Vector3(1.9, 1.3, 4.7), g + Vector3(0, 0.65, 0), yaw)
		if i % 3 == 0:
			var smoke := FxKit.smoke(0.9, 10)
			smoke.position = g + Vector3(0, 1.3, 0)
			smoke.color_ramp = null
			smoke.color = Color(0.15, 0.14, 0.13, 0.35)
			add_child(smoke)
			smoke.emitting = true


# ---------------------------------------------------------------- billboards

func _billboards() -> void:
	var boards := [
		[Vector3(-10, 0, -117), 180.0, "CALYPSO'S CONTEST", "WIN ONE WISH. ANY WISH.", Color(0.75, 0.12, 0.1)],
		[Vector3(112, 0, -40), 90.0, "LAST ONE DRIVING", "GETS EVERYTHING", Color(0.85, 0.65, 0.1)],
		[Vector3(-117, 0, 98), -90.0, "QUAKE ZONE", "NO ENTRY  -  BY ORDER OF THE CITY", Color(0.15, 0.35, 0.6)],
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
		mb.commit(node, true, 0.3)
		for line in 2:
			var l := Label3D.new()
			l.text = b[2] if line == 0 else b[3]
			l.font_size = 200 if line == 0 else 110
			l.pixel_size = 0.009
			l.outline_size = 0
			l.modulate = Color(0.92, 0.9, 0.84) if line == 0 else Color(0.1, 0.08, 0.07)
			l.shaded = true
			l.position = Vector3(0, 12.6 if line == 0 else 10.4, -0.06)
			l.rotation_degrees.y = 180.0
			node.add_child(l)
		for x: float in [-4.5, 4.5]:
			_solid(Vector3(0.6, 9.0, 0.6), pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(x, 4.5, 0.4))


# ---------------------------------------------------------------- power lines

func _power_lines() -> void:
	var wood := MatKit.paint(Color(0.3, 0.24, 0.17), 0.3, 0.0, 0.6, 0.8, 0.95, 90)
	var dark := _dark()
	var wire := MatKit.flat(Color(0.03, 0.03, 0.03), 0.8)
	var mb := MeshBuilder.new()
	var runs := [[Vector3(118, 0, -90), Vector3(118, 0, 0)], [Vector3(-90, 0, -118), Vector3(60, 0, -118)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var count := int(a.distance_to(b) / 30.0) + 1
		var tops: Array[Vector3] = []
		for k in count:
			var p := a.lerp(b, float(k) / (count - 1))
			if p.distance_to(Vector3(110, 0, 30)) < 6.0:
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
	mb.commit(self, true, 0.4)


# ---------------------------------------------------------------- traffic lights

func _traffic_lights() -> void:
	var dark := _dark()
	var steel := _steel()
	var mb := MeshBuilder.new()
	var lamps := [MatKit.lamp(Color(0.9, 0.08, 0.05), 2.5), MatKit.lamp(Color(0.25, 0.2, 0.05), 0.2), MatKit.lamp(Color(0.05, 0.2, 0.08), 0.2)]
	for corner: Vector3 in [Vector3(94, 0, 94), Vector3(-94, 0, 94), Vector3(94, 0, -94), Vector3(-94, 0, -94)]:
		var g := _ground_at(corner.x, corner.z)
		var inward := -Vector3(corner.x, 0, corner.z).normalized()
		mb.cylinder(steel, 0.14, 6.0, MeshBuilder.at(g + Vector3(0, 3.0, 0)), 8)
		var arm_end := g + Vector3(0, 6.0, 0) + inward * 5.0
		mb.cylinder(steel, 0.08, 5.0, MeshBuilder.along((g + Vector3(0, 6.0, 0) + arm_end) * 0.5, arm_end - g - Vector3(0, 6.0, 0)), 6)
		var yaw := rad_to_deg(atan2(inward.x, inward.z))
		mb.box(dark, Vector3(0.45, 1.3, 0.4), MeshBuilder.at(arm_end + Vector3(0, -0.7, 0), Vector3(0, yaw, 0)), 0.05)
		for k in 3:
			var lp := arm_end + Vector3(0, -0.3 - k * 0.4, 0) + inward * 0.21
			mb.cylinder(lamps[k], 0.13, 0.04, MeshBuilder.along(lp, inward), 10)
		_solid(Vector3(0.4, 6.0, 0.4), g + Vector3(0, 3.0, 0))
	mb.commit(self, true, 0.3)


# ---------------------------------------------------------------- barriers, bins, containers

func _barrier_mesh() -> ArrayMesh:
	if _meshes.has("barrier"):
		return _meshes.barrier
	var mb := MeshBuilder.new()
	var conc := _concrete()
	mb.loft(conc, [MeshBuilder.section(-1.5, 0.4, 0.3, 0.4, 0.05, 0.12), MeshBuilder.section(1.5, 0.4, 0.3, 0.4, 0.05, 0.12)], Transform3D.IDENTITY, 1)
	mb.box(MatKit.flat(Color(0.62, 0.5, 0.12), 0.8), Vector3(0.62, 0.12, 2.9), MeshBuilder.at(Vector3(0, 0.12, 0)), 0.0)
	_meshes.barrier = mb.build_mesh(0.7)
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
	_meshes.dumpster = mb.build_mesh(0.6)
	return _meshes.dumpster


func _barriers_and_bins() -> void:
	# Barrier rows parallel to the walls, out of the driving lines.
	var rows := [[Vector3(-113, 0, -52), 0.0, 3], [Vector3(-113, 0, 40), 0.0, 3], [Vector3(80, 0, -112), 90.0, 4],
		[Vector3(-50, 0, 112), 90.0, 3], [Vector3(112, 0, -80), 0.0, 3]]
	for r in rows:
		var start: Vector3 = r[0]
		var yaw: float = r[1]
		var n: int = r[2]
		var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1)
		for k in n:
			var p := start + dir * (k * 3.05)
			var g := _ground_at(p.x, p.z)
			_place(_barrier_mesh(), g, yaw + _rng.randf_range(-4, 4))
		var mid := start + dir * ((n - 1) * 3.05 * 0.5)
		_solid(Vector3(0.75, 0.85, n * 3.05), _ground_at(mid.x, mid.z) + Vector3(0, 0.42, 0), yaw)
	for spot in [[Vector3(-20, 0, 119), 0.0], [Vector3(-119, 0, 47), 90.0], [Vector3(119, 0, 52), -90.0], [Vector3(30, 0, 119), 5.0]]:
		var g := _ground_at(spot[0].x, spot[0].z)
		_place(_dumpster_mesh(), g, spot[1])
		_solid(Vector3(1.9, 1.5, 1.3), g + Vector3(0, 0.75, 0), spot[1])


func _container_stack() -> void:
	var colors := [Color(0.5, 0.18, 0.12), Color(0.15, 0.28, 0.4), Color(0.45, 0.4, 0.2)]
	var mb := MeshBuilder.new()
	var base := _ground_at(52, 70)
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
	mb.commit(self, true, 0.5)
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
			c += Vector3(-30, 0, -45) # around the burnt building
		var g := _ground_at(c.x, c.z)
		var s := Vector3(_rng.randf_range(0.2, 0.55), _rng.randf_range(0.12, 0.35), _rng.randf_range(0.2, 0.6))
		mb.box(conc, s, MeshBuilder.at(g + Vector3(0, s.y * 0.35, 0), Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 360), _rng.randf_range(-20, 20))), 0.03)
		if i % 6 == 0:
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.6, 1.0), _rng.randf_range(-1, 1)).normalized()
			mb.cylinder(rebar, 0.015, 0.9, MeshBuilder.along(g + d * 0.4, d), 4, -1.0, false)
	mb.commit(self, false, 0.6)


func _stain_mat() -> StandardMaterial3D:
	if _meshes.has("stain"):
		return _meshes.stain
	var m := StandardMaterial3D.new()
	m.albedo_texture = FxKit.soft_texture()
	m.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.35
	m.disable_receive_shadows = false
	_meshes.stain = m
	return m


func _road_marks() -> void:
	var h := LosAngelesArena.ROAD_H
	var iron := MatKit.steel(Color(0.12, 0.12, 0.12), 0.6, 0.4)
	var mb := MeshBuilder.new()
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		for t: float in [-50.0, 5.0, 48.0]:
			var p := basis * Vector3(t, 0, h + 3.0)
			if side == 0 and absf(p.x) < 28.0:
				continue # the humps
			if side == 3 and absf(p.z) < 40.0:
				continue
			mb.cylinder(iron, 0.38, 0.03, MeshBuilder.at(_ground_at(p.x, p.z) + Vector3(0, 0.05, 0)), 14)
	mb.commit(self, false)
	# Oil stains and tire marks as soft dark patches lying on the ground.
	for i in 40:
		var side := i % 4
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		var p := basis * Vector3(_rng.randf_range(-62, 62), 0, h + _rng.randf_range(-6.0, 6.0))
		if side == 3 and absf(p.z) < 40.0:
			continue
		var g := LosAngelesArena.on_mesh(p.x, p.z, 0.1)
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		var long := i % 3 == 0
		q.size = Vector2(0.5, _rng.randf_range(6.0, 12.0)) if long else Vector2.ONE * _rng.randf_range(1.0, 3.2)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = _stain_mat()
		mi.position = g
		mi.rotation.y = basis.get_euler().y + (_rng.randf_range(-0.2, 0.2) if long else _rng.randf() * TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
