class_name JunkyardArena
extends Node3D
## The Junkyard stage, built in code: fenced yard, crusher building with a roof ramp,
## crushed-car stacks forming lanes, a jump mound in the middle, a crane, a wrecked bus,
## burning barrels and sodium street lights. Fixed seed, so the layout is the same every run.

const HALF := 80.0 # yard is 160 x 160 m

var spawn_points: Array[Transform3D] = []
var weapon_points: Array[Vector3] = []
var health_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _m := {} # materials


func build() -> void:
	_rng.seed = 1999
	_materials()
	_ground()
	_fence()
	_outer_piles()
	_crusher(Vector3(-42, 0, -40))
	_center_mound()
	_crane(Vector3(40, 0, 38))
	_bus(Vector3(46, 0, -36), 25.0)
	_junk_rows()
	_tire_piles()
	_barrels()
	_light_poles()
	_puddles()
	_debris()
	_points()


func _materials() -> void:
	_m.mud = MeshKit.grime(Color(0.3, 0.25, 0.18), Color(0.11, 0.09, 0.07), 0.06, 0.95, 0.0, 0.12)
	_m.fence_a = MeshKit.grime(Color(0.36, 0.2, 0.1), Color(0.1, 0.07, 0.05), 0.08, 0.8, 0.4, 0.25)
	_m.fence_b = MeshKit.grime(Color(0.28, 0.26, 0.24), Color(0.12, 0.08, 0.06), 0.08, 0.7, 0.5, 0.25)
	_m.concrete = MeshKit.grime(Color(0.3, 0.3, 0.29), Color(0.1, 0.1, 0.1), 0.05, 0.95, 0.0, 0.15)
	_m.dark = MeshKit.mat(Color(0.03, 0.03, 0.03), 0.9)
	_m.metal = MeshKit.mat(Color(0.18, 0.18, 0.19), 0.5, 0.8)
	_m.tire = MeshKit.mat(Color(0.04, 0.04, 0.04), 0.95)
	_m.rust = MeshKit.grime(Color(0.4, 0.2, 0.08), Color(0.12, 0.06, 0.03), 0.15, 0.9, 0.3, 0.4)
	_m.yellow = MeshKit.grime(Color(0.7, 0.55, 0.1), Color(0.25, 0.16, 0.05), 0.1, 0.8, 0.2, 0.3)
	_m.puddle = MeshKit.mat(Color(0.02, 0.025, 0.035), 0.02, 0.3)
	_m.silhouette = MeshKit.mat(Color(0.015, 0.015, 0.02), 1.0)
	var car_colors := [
		Color(0.45, 0.08, 0.06), Color(0.1, 0.18, 0.35), Color(0.15, 0.25, 0.12),
		Color(0.6, 0.58, 0.52), Color(0.55, 0.42, 0.1), Color(0.2, 0.2, 0.22),
	]
	_m.cars = []
	for c in car_colors:
		_m.cars.append(MeshKit.grime(c, Color(0.18, 0.08, 0.04), 0.12, 0.85, 0.3, 0.4))


# ---------------------------------------------------------------- terrain & walls

func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	shape.shape = box
	shape.position = Vector3(0, -1, 0)
	body.add_child(shape)
	# Tiles instead of one huge plane: each mesh is lit by a limited number of lights.
	var tile := 32.0
	var n := 6
	for ix in n:
		for iz in n:
			var mi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(tile, tile)
			mi.mesh = plane
			mi.material_override = _m.mud
			mi.position = Vector3((ix - n * 0.5 + 0.5) * tile, 0, (iz - n * 0.5 + 0.5) * tile)
			body.add_child(mi)
	var outer := MeshInstance3D.new()
	var big := PlaneMesh.new()
	big.size = Vector2(400, 400)
	outer.mesh = big
	outer.material_override = _m.mud
	outer.position = Vector3(0, -0.02, 0)
	body.add_child(outer)


func _fence() -> void:
	var seg := 8.0
	var h := 6.5
	for side in 4:
		var count := int(HALF * 2.0 / seg)
		for i in count:
			var t := -HALF + seg * 0.5 + i * seg
			var pos: Vector3
			var rot_y := 0.0
			match side:
				0: pos = Vector3(t, h * 0.5, -HALF)
				1: pos = Vector3(t, h * 0.5, HALF)
				2:
					pos = Vector3(-HALF, h * 0.5, t)
					rot_y = 90.0
				3:
					pos = Vector3(HALF, h * 0.5, t)
					rot_y = 90.0
			var lean := _rng.randf_range(-2.0, 2.0)
			var mat: Material = _m.fence_a if _rng.randf() < 0.6 else _m.fence_b
			var body := MeshKit.solid_box(self, Vector3(seg + 0.1, h + _rng.randf_range(-0.6, 0.6), 0.3), pos, mat, Vector3(lean, rot_y, 0))
			# Corrugation ribs.
			for r in 4:
				MeshKit.box(body, Vector3(seg, 0.12, 0.38), Vector3(0, -2.0 + r * 1.3, 0), mat)
			var post_pos := pos + (Vector3(seg * 0.5, 0, 0) if rot_y == 0.0 else Vector3(0, 0, seg * 0.5))
			MeshKit.cylinder(self, 0.18, h + 1.0, Vector3(post_pos.x, (h + 1.0) * 0.5, post_pos.z), _m.metal, Vector3.ZERO, 6)
	# Barbed wire along the top.
	for side in 4:
		for k in 2:
			var y := h + 0.4 + k * 0.35
			var along_x := side < 2
			var c := Vector3(0, y, -HALF if side == 0 else HALF) if along_x else Vector3(-HALF if side == 2 else HALF, y, 0)
			MeshKit.cylinder(self, 0.03, HALF * 2.0, c, _m.metal, Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0), 4)


## Mountains of junk behind the fence, black against the sky.
func _outer_piles() -> void:
	for i in 26:
		var a := float(i) / 26.0 * TAU + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(HALF + 14.0, HALF + 40.0)
		var size := Vector3(_rng.randf_range(14, 30), _rng.randf_range(8, 24), _rng.randf_range(14, 30))
		MeshKit.box(self, size, Vector3(cos(a) * r, size.y * 0.3, sin(a) * r), _m.silhouette,
			Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 90), _rng.randf_range(-20, 20)))


# ---------------------------------------------------------------- landmarks

func _crusher(at: Vector3) -> void:
	var size := Vector3(22, 9, 14)
	MeshKit.solid_box(self, size, at + Vector3(0, size.y * 0.5, 0), _m.concrete)
	MeshKit.box(self, Vector3(22.3, 0.3, 14.3), at + Vector3(0, 8.85, 0), _m.rust)
	# Big shutter door and dark windows on the front (facing the yard, +Z).
	MeshKit.box(self, Vector3(8, 6, 0.2), at + Vector3(-3, 3, 7.05), _m.rust)
	for i in 7:
		MeshKit.box(self, Vector3(8, 0.1, 0.25), at + Vector3(-3, 0.6 + i * 0.8, 7.1), _m.dark)
	for x in [5.0, 8.5]:
		MeshKit.box(self, Vector3(2.2, 1.4, 0.2), at + Vector3(x, 5.5, 7.05), MeshKit.emissive(Color(0.6, 0.45, 0.2), 0.25))
	# Flickering neon sign.
	var sign := Label3D.new()
	sign.text = "SALVAGE & CRUSH"
	sign.font_size = 160
	sign.pixel_size = 0.01
	sign.outline_size = 0
	sign.modulate = Color(2.2, 0.25, 0.15)
	sign.position = at + Vector3(0, 7.6, 7.15)
	add_child(sign)
	var neon := FlickerLight.new()
	neon.light_color = Color(1.0, 0.2, 0.15)
	neon.base_energy = 1.6
	neon.amount = 0.6
	neon.speed = 20.0
	neon.omni_range = 10.0
	neon.position = at + Vector3(0, 7.6, 9.0)
	add_child(neon)
	# Ramp up to the roof along the east wall: high end touches the roof edge.
	var ramp_len := 26.0
	var ramp := MeshKit.prism(self, Vector3(ramp_len, size.y, 6.0), at + Vector3(size.x * 0.5 + ramp_len * 0.5, size.y * 0.5, -0.0), _m.concrete, Vector3.ZERO, 0.0)
	MeshKit.solid_mesh(self, ramp)


func _center_mound() -> void:
	# Platform of crushed cars with a ramp at each end: a straight run from the player spawn is a jump.
	var plat := MeshKit.solid_box(self, Vector3(12, 3.5, 10), Vector3(0, 1.75, 0), _m.concrete)
	for layer in 3:
		for side in [-1.0, 1.0]:
			var mat: Material = _m.cars[_rng.randi() % _m.cars.size()]
			MeshKit.box(plat, Vector3(12.2, 1.1, 0.3), Vector3(0, -1.2 + layer * 1.15, 5.0 * side), mat, Vector3(0, _rng.randf_range(-1, 1), 0))
			MeshKit.box(plat, Vector3(0.3, 1.1, 10.2), Vector3(6.0 * side, -1.2 + layer * 1.15, 0), mat)
	for dir in [-1.0, 1.0]:
		var ramp := MeshKit.prism(self, Vector3(12, 3.5, 8), Vector3(0, 1.75, dir * 11.0), _m.rust, Vector3(0, -90.0 * dir, 0), 0.0)
		MeshKit.solid_mesh(self, ramp)


func _crane(at: Vector3) -> void:
	var height := 26.0
	MeshKit.solid_box(self, Vector3(6, 2, 6), at + Vector3(0, 1, 0), _m.concrete)
	var tower := StaticBody3D.new()
	tower.position = at
	add_child(tower)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.4, height, 3.4)
	shape.shape = bs
	shape.position = Vector3(0, height * 0.5 + 2.0, 0)
	tower.add_child(shape)
	for cx in [-1.5, 1.5]:
		for cz in [-1.5, 1.5]:
			MeshKit.box(tower, Vector3(0.35, height, 0.35), Vector3(cx, height * 0.5 + 2.0, cz), _m.yellow)
	for i in int(height / 3.0):
		var y := 3.5 + i * 3.0
		for face in 4:
			var rot := Vector3(0, face * 90.0, 45.0)
			var off := Vector3(0, y, 1.5).rotated(Vector3.UP, deg_to_rad(face * 90.0))
			MeshKit.box(tower, Vector3(4.2, 0.18, 0.18), off, _m.yellow, rot)
	# Operator cab, boom toward the yard, counterweight behind.
	MeshKit.box(tower, Vector3(3.5, 3, 3.5), Vector3(0, height + 3.5, 0), _m.yellow)
	MeshKit.box(tower, Vector3(2.4, 1.2, 0.1), Vector3(0, height + 4.0, -1.8), MeshKit.emissive(Color(0.5, 0.4, 0.2), 0.3))
	var boom_dir := (Vector3.ZERO - at).normalized()
	var boom_yaw := atan2(-boom_dir.x, -boom_dir.z)
	var boom := Node3D.new()
	boom.position = Vector3(0, height + 5.5, 0)
	boom.rotation.y = boom_yaw
	tower.add_child(boom)
	MeshKit.box(boom, Vector3(1.2, 1.2, 30), Vector3(0, 0, -13), _m.yellow)
	MeshKit.box(boom, Vector3(3, 2.5, 4), Vector3(0, -0.5, 4), _m.concrete)
	MeshKit.cylinder(boom, 0.06, 15, Vector3(0, -7.5, -26), _m.metal, Vector3.ZERO, 4)
	MeshKit.cylinder(boom, 1.6, 0.8, Vector3(0, -15.2, -26), _m.dark)
	# A crushed car stuck to the magnet.
	MeshKit.box(boom, Vector3(4.2, 1.2, 2.0), Vector3(0, -16.3, -26), _m.cars[0], Vector3(0, 30, 6))
	# Warning light.
	var blinker := Blinker.new()
	blinker.period = 0.8
	tower.add_child(blinker)
	var lamp := MeshKit.sphere(tower, 0.35, Vector3(0, height + 5.4, 0), MeshKit.emissive(Color(1, 0.05, 0.05), 8.0))
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.1, 0.05)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.position = Vector3(0, height + 5.8, 0)
	tower.add_child(light)
	blinker.group_a.append_array([lamp, light])


## School bus lying on its side.
func _bus(at: Vector3, yaw: float) -> void:
	var body := MeshKit.solid_box(self, Vector3(11, 2.8, 3.0), at + Vector3(0, 1.4, 0), _m.yellow, Vector3(0, yaw, 0))
	MeshKit.box(body, Vector3(10.6, 0.05, 1.0), Vector3(0, 1.42, 0.2), _m.dark)
	MeshKit.box(body, Vector3(11.05, 0.3, 3.05), Vector3(0, -0.9, 0), _m.dark)
	for x in [-3.8, 3.2]:
		for z in [-1.0, 1.0]:
			MeshKit.cylinder(body, 0.55, 0.4, Vector3(x, z * 1.0, -1.6), _m.tire, Vector3(90, 0, 0))


# ---------------------------------------------------------------- junk

func _junk_rows() -> void:
	_stack_row(Vector3(-62, 0, 20), Vector3(-30, 0, 20))
	_stack_row(Vector3(-25, 0, 26), Vector3(-25, 0, 56))
	_stack_row(Vector3(16, 0, -15), Vector3(62, 0, -15))
	_stack_row(Vector3(15, 0, -62), Vector3(15, 0, -26))
	_stack_row(Vector3(22, 0, 20), Vector3(40, 0, 20))
	_stack_row(Vector3(-62, 0, -12), Vector3(-44, 0, -12))
	# Loose stacks scattered around.
	for p in [Vector3(-12, 0, 40), Vector3(12, 0, 44), Vector3(28, 0, 60), Vector3(-45, 0, 62),
			Vector3(64, 0, 28), Vector3(-64, 0, 45), Vector3(30, 0, -55), Vector3(-20, 0, -20),
			Vector3(22, 0, 8), Vector3(-15, 0, -60), Vector3(66, 0, -64), Vector3(-66, 0, -66)]:
		_stack(p, _rng.randf_range(0, 180), _rng.randi_range(1, 4))


func _stack_row(a: Vector3, b: Vector3) -> void:
	var dir := (b - a)
	var length := dir.length()
	dir = dir.normalized()
	var yaw := rad_to_deg(atan2(dir.x, dir.z)) + 90.0
	var step := 4.8
	var n := int(length / step) + 1
	for i in n:
		if _rng.randf() < 0.12:
			continue # gaps to drive through
		_stack(a + dir * i * step, yaw + _rng.randf_range(-6, 6), _rng.randi_range(2, 4))


## A pile of crushed cars. One collider for the pile, one mesh per car.
func _stack(pos: Vector3, yaw: float, count: int) -> void:
	var h := 1.1
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees.y = yaw
	add_child(body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.4, count * h, 2.2)
	shape.shape = bs
	shape.position = Vector3(0, count * h * 0.5, 0)
	body.add_child(shape)
	for i in count:
		var mat: Material = _m.cars[_rng.randi() % _m.cars.size()]
		var car := Node3D.new()
		car.position = Vector3(_rng.randf_range(-0.25, 0.25), h * 0.5 + i * h, _rng.randf_range(-0.15, 0.15))
		car.rotation_degrees = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-8, 8), _rng.randf_range(-3, 3))
		body.add_child(car)
		MeshKit.box(car, Vector3(4.2, h * 0.95, 2.0), Vector3.ZERO, mat)
		MeshKit.box(car, Vector3(2.0, 0.22, 2.04), Vector3(0.2, 0.15, 0), _m.dark) # squashed windows
		if _rng.randf() < 0.5:
			MeshKit.cylinder(car, 0.35, 0.2, Vector3(-1.4, -0.3, 1.02), _m.tire, Vector3(90, 0, 0), 10)


func _tire_piles() -> void:
	for p in [Vector3(-8, 0, 26), Vector3(34, 0, -4), Vector3(-36, 0, 8), Vector3(52, 0, 60), Vector3(-58, 0, -32), Vector3(4, 0, -48)]:
		var count := _rng.randi_range(3, 6)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = p
		add_child(body)
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 1.4
		cs.height = count * 0.45
		shape.shape = cs
		shape.position = Vector3(0, count * 0.225, 0)
		body.add_child(shape)
		for i in count:
			MeshKit.torus(body, 0.6, 1.25, Vector3(_rng.randf_range(-0.15, 0.15), 0.22 + i * 0.45, _rng.randf_range(-0.15, 0.15)), _m.tire, Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)))


func _barrels() -> void:
	var spots := [
		Vector3(-9, 0, 9), Vector3(9, 0, -9), Vector3(-34, 0, -28), Vector3(-52, 0, -28),
		Vector3(33, 0, 46), Vector3(60, 0, -24), Vector3(-62, 0, 26), Vector3(20, 0, 66),
		Vector3(-20, 0, -66), Vector3(70, 0, 70), Vector3(-70, 0, -70), Vector3(5, 3.5, -4),
		Vector3(-42, 9, -44), Vector3(40, 0, 6), Vector3(-30, 0, 46),
	]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = p
		add_child(body)
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.5
		cs.height = 1.2
		shape.shape = cs
		shape.position = Vector3(0, 0.6, 0)
		body.add_child(shape)
		MeshKit.cylinder(body, 0.48, 1.2, Vector3(0, 0.6, 0), _m.rust, Vector3.ZERO, 12)
		MeshKit.torus(body, 0.46, 0.52, Vector3(0, 0.3, 0), _m.dark)
		MeshKit.torus(body, 0.46, 0.52, Vector3(0, 0.9, 0), _m.dark)
		var fire := FxKit.fire(1.0, 28)
		fire.position = Vector3(0, 1.3, 0)
		body.add_child(fire)
		fire.emitting = true
		var smoke := FxKit.smoke(1.0, 10)
		smoke.position = Vector3(0, 2.2, 0)
		body.add_child(smoke)
		smoke.emitting = true
		var light := FlickerLight.new()
		light.light_color = Color(1.0, 0.48, 0.15)
		light.base_energy = 4.0
		light.omni_range = 16.0
		light.position = Vector3(0, 2.0, 0)
		light.shadow_enabled = i < 5
		body.add_child(light)


func _light_poles() -> void:
	for p: Vector3 in [Vector3(-60, 0, 60), Vector3(60, 0, -60), Vector3(-6, 0, -66), Vector3(66, 0, 12), Vector3(-70, 0, 10)]:
		var pole := Node3D.new()
		pole.position = p
		add_child(pole)
		MeshKit.cylinder(pole, 0.2, 12, Vector3(0, 6, 0), _m.metal, Vector3.ZERO, 6)
		var inward := (-p).normalized()
		var arm_end := inward * 2.5 + Vector3.UP * 11.8
		MeshKit.box(pole, Vector3(0.15, 0.15, 2.6), inward * 1.25 + Vector3.UP * 11.8, _m.metal, Vector3(0, rad_to_deg(atan2(inward.x, inward.z)), 0))
		MeshKit.box(pole, Vector3(0.8, 0.25, 0.5), arm_end, MeshKit.emissive(Color(1.0, 0.65, 0.3), 5.0))
		var spot := SpotLight3D.new()
		spot.position = arm_end - Vector3.UP * 0.3
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.light_color = Color(1.0, 0.65, 0.32)
		spot.light_energy = 12.0
		spot.spot_range = 30.0
		spot.spot_angle = 50.0
		spot.shadow_enabled = true
		pole.add_child(spot)
	# A body to collide with at the base.
	for p in [Vector3(-60, 0, 60), Vector3(60, 0, -60), Vector3(-6, 0, -66), Vector3(66, 0, 12), Vector3(-70, 0, 10)]:
		var body := StaticBody3D.new()
		body.position = p
		add_child(body)
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.3
		cs.height = 12
		shape.shape = cs
		shape.position = Vector3(0, 6, 0)
		body.add_child(shape)


func _puddles() -> void:
	for i in 22:
		var p := Vector3(_rng.randf_range(-74, 74), 0.015, _rng.randf_range(-74, 74))
		var r := _rng.randf_range(1.5, 4.5)
		var mi := MeshKit.cylinder(self, r, 0.02, p, _m.puddle, Vector3(0, _rng.randf_range(0, 180), 0), 16)
		mi.scale = Vector3(1.0, 1.0, _rng.randf_range(0.4, 0.9))


func _debris() -> void:
	var mats: Array = [_m.rust, _m.metal, _m.tire, _m.fence_a] + _m.cars
	for i in 180:
		var p := Vector3(_rng.randf_range(-76, 76), 0, _rng.randf_range(-76, 76))
		var s := Vector3(_rng.randf_range(0.2, 1.3), _rng.randf_range(0.05, 0.35), _rng.randf_range(0.2, 1.3))
		p.y = s.y * 0.5
		MeshKit.box(self, s, p, mats[_rng.randi() % mats.size()], Vector3(_rng.randf_range(-8, 8), _rng.randf_range(0, 180), _rng.randf_range(-8, 8)))


# ---------------------------------------------------------------- gameplay points

func _points() -> void:
	# Player starts south, looking north straight at the jump mound.
	spawn_points = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 62)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -62)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(62, 0.05, 0)),
		Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-62, 0.05, -2)),
	]
	weapon_points = [
		Vector3(-30, 0, 0), Vector3(30, 0, 0), Vector3(0, 0, 30), Vector3(0, 0, -30),
		Vector3(-55, 0, 40), Vector3(58, 0, -50), Vector3(-60, 0, -22), Vector3(25, 0, 55),
		Vector3(-12, 0, -52), Vector3(48, 0, 12),
	]
	health_points = [
		Vector3(0, 3.5, 0), # top of the mound
		Vector3(-42, 9, -38), # crusher roof
		Vector3(58, 0, 58),
		Vector3(-60, 0, -60),
	]
