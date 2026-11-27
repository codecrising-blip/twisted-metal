class_name VehicleModels
extends RefCounted
## Car models: the Blender cars (BlenderCars) and, for the cars not remade yet (Junkyard Dog,
## Spectre), simple prototype builds from primitives.
## Convention: the car faces -Z, Y is up, wheels touch y = 0.
## Each model stores metadata the Vehicle script reads:
##   "wheels"   spin pivots (rotate around X)
##   "steer"    front steer pivots (rotate around Y)
##   "wheel_radius"
##   "guns"     machine gun muzzle points (local)
##   "launcher" missile launch point (local)
##   "top"      where damage smoke/fire comes out (local)
##   "lean"     how far the body rolls in turns (radians; bikes lean more)


static func build(id: String) -> Node3D:
	if BlenderCars.has(id): # round 10: the cars remade in Blender
		return BlenderCars.build(id)
	match id:
		"junkyard_dog":
			return junkyard_dog()
		"spectre":
			return spectre()
	push_error("Unknown vehicle model: %s" % id)
	return BlenderCars.build("sweet_tooth")


# ---------------------------------------------------------------- shared parts

static func _new_model(wheel_radius: float) -> Node3D:
	var m := Node3D.new()
	m.name = "Model"
	m.set_meta("wheels", [])
	m.set_meta("steer", [])
	m.set_meta("wheel_radius", wheel_radius)
	return m


static func _wheel(m: Node3D, pos: Vector3, radius: float, width: float, front: bool) -> void:
	var tire := MeshKit.mat(Color(0.05, 0.05, 0.05), 0.95)
	var hub := MeshKit.mat(Color(0.35, 0.33, 0.3), 0.4, 0.8)
	var steer := Node3D.new()
	steer.position = pos
	m.add_child(steer)
	var spin := Node3D.new()
	steer.add_child(spin)
	MeshKit.cylinder(spin, radius, width, Vector3.ZERO, tire, Vector3(0, 0, 90), 14)
	MeshKit.cylinder(spin, radius * 0.55, width + 0.04, Vector3.ZERO, hub, Vector3(0, 0, 90), 8)
	# Spokes, so the spin is visible.
	MeshKit.box(spin, Vector3(width + 0.06, radius * 0.22, radius * 1.15), Vector3.ZERO, hub)
	m.get_meta("wheels").append(spin)
	if front:
		m.get_meta("steer").append(steer)


static func _headlights(m: Node3D, points: Array, spot_pos: Vector3, round := false) -> void:
	var lamp := MeshKit.emissive(Color(1.0, 0.95, 0.8), 4.0)
	for p in points:
		if round:
			MeshKit.cylinder(m, 0.18, 0.08, p, lamp, Vector3(90, 0, 0), 12)
		else:
			MeshKit.box(m, Vector3(0.36, 0.22, 0.06), p, lamp)
	var spot := SpotLight3D.new()
	spot.position = spot_pos
	spot.light_color = Color(1.0, 0.93, 0.78)
	spot.light_energy = 4.0
	spot.spot_range = 34.0
	spot.spot_angle = 32.0
	spot.spot_attenuation = 0.8
	spot.rotation_degrees = Vector3(-6, 0, 0)
	spot.add_to_group(GraphicsSettings.HEADLIGHT_GROUP)
	spot.visible = false # switched with the headlights button (Vehicle.toggle_headlights)
	m.add_child(spot)


static func _taillights(m: Node3D, points: Array) -> void:
	var red := MeshKit.emissive(Color(0.9, 0.05, 0.05), 3.0)
	for p in points:
		MeshKit.box(m, Vector3(0.28, 0.3, 0.06), p, red)


static func _guns(m: Node3D, mounts: Array) -> void:
	var metal := MeshKit.mat(Color(0.12, 0.12, 0.13), 0.35, 0.9)
	var muzzles: Array = []
	for p in mounts:
		var pos: Vector3 = p
		MeshKit.box(m, Vector3(0.26, 0.22, 0.5), pos, metal)
		MeshKit.cylinder(m, 0.065, 0.7, pos + Vector3(0, 0, -0.5), metal, Vector3(90, 0, 0), 8)
		muzzles.append(pos + Vector3(0, 0, -0.9))
	m.set_meta("guns", muzzles)


# Cone pointing toward -Z (spikes on bumpers).
static func _spike(m: Node3D, pos: Vector3, mat: Material, length := 0.45) -> void:
	MeshKit.cylinder(m, 0.1, length, pos, mat, Vector3(-90, 0, 0), 8, 0.0)


# ---------------------------------------------------------------- Junkyard Dog

static func junkyard_dog() -> Node3D:
	var m := _new_model(0.6)
	var yellow := MeshKit.grime(Color(0.78, 0.6, 0.1), Color(0.3, 0.18, 0.05), 0.12, 0.8, 0.2)
	var rusty := MeshKit.grime(Color(0.35, 0.2, 0.1), Color(0.1, 0.06, 0.04), 0.2, 0.9, 0.3)
	var dark_metal := MeshKit.mat(Color(0.12, 0.12, 0.12), 0.5, 0.8)
	var glass := MeshKit.mat(Color(0.03, 0.05, 0.08), 0.08, 0.6)
	var chrome := MeshKit.mat(Color(0.5, 0.5, 0.52), 0.3, 1.0)

	for side in [-1.0, 1.0]:
		_wheel(m, Vector3(1.12 * side, 0.6, -1.9), 0.6, 0.5, true)
		_wheel(m, Vector3(1.12 * side, 0.6, 1.9), 0.6, 0.5, false)

	MeshKit.box(m, Vector3(2.0, 0.4, 5.6), Vector3(0, 0.85, 0), dark_metal)
	MeshKit.box(m, Vector3(2.0, 0.75, 1.2), Vector3(0, 1.35, -2.25), yellow)
	MeshKit.box(m, Vector3(2.3, 1.5, 1.6), Vector3(0, 1.85, -0.85), yellow)
	MeshKit.box(m, Vector3(2.05, 0.65, 0.06), Vector3(0, 2.15, -1.66), glass, Vector3(-8, 0, 0))
	MeshKit.box(m, Vector3(1.5, 0.6, 0.06), Vector3(0, 1.35, -2.86), dark_metal)
	for i in 6:
		MeshKit.box(m, Vector3(0.06, 0.56, 0.08), Vector3(-0.6 + i * 0.24, 1.35, -2.88), chrome)
	for side in [-1.0, 1.0]:
		MeshKit.box(m, Vector3(0.06, 0.6, 1.1), Vector3(1.16 * side, 2.15, -0.85), glass)
		MeshKit.cylinder(m, 0.09, 1.4, Vector3(1.22 * side, 2.5, -0.2), chrome)
		# Flatbed rails.
		MeshKit.box(m, Vector3(0.1, 0.35, 2.8), Vector3(1.1 * side, 1.5, 1.45), rusty)

	# Flatbed and tow boom.
	MeshKit.box(m, Vector3(2.3, 0.3, 2.8), Vector3(0, 1.2, 1.45), rusty)
	for side in [-1.0, 1.0]:
		MeshKit.box(m, Vector3(0.18, 2.6, 0.18), Vector3(0.7 * side, 2.4, 2.2), yellow, Vector3(-20, 0, 0))
	MeshKit.box(m, Vector3(1.6, 0.18, 0.18), Vector3(0, 3.6, 2.65), yellow)
	MeshKit.box(m, Vector3(0.25, 0.25, 1.4), Vector3(0, 3.5, 3.2), yellow)
	MeshKit.cylinder(m, 0.04, 1.3, Vector3(0, 2.8, 3.8), dark_metal)
	MeshKit.torus(m, 0.12, 0.28, Vector3(0, 2.0, 3.8), chrome, Vector3(90, 0, 0))

	# Amber beacon.
	var blinker := Blinker.new()
	blinker.period = 0.45
	m.add_child(blinker)
	MeshKit.cylinder(m, 0.18, 0.25, Vector3(0, 2.75, -0.85), MeshKit.emissive(Color(1.0, 0.55, 0.0), 0.5))
	var bright := MeshKit.cylinder(m, 0.2, 0.27, Vector3(0, 2.75, -0.85), MeshKit.emissive(Color(1.0, 0.6, 0.0), 6.0))
	var amber := OmniLight3D.new()
	amber.light_color = Color(1.0, 0.6, 0.1)
	amber.light_energy = 2.5
	amber.omni_range = 7.0
	amber.position = Vector3(0, 3.0, -0.85)
	m.add_child(amber)
	blinker.group_a.append_array([bright, amber])

	MeshKit.box(m, Vector3(2.5, 0.35, 0.28), Vector3(0, 0.95, -2.95), chrome)
	for x in [-0.8, 0.0, 0.8]:
		_spike(m, Vector3(x, 0.95, -3.3), chrome)
	_headlights(m, [Vector3(-0.8, 1.55, -2.88), Vector3(0.8, 1.55, -2.88)], Vector3(0, 1.55, -3.0), true)
	_taillights(m, [Vector3(-0.95, 1.2, 2.88), Vector3(0.95, 1.2, 2.88)])
	_guns(m, [Vector3(-0.8, 1.05, -2.6), Vector3(0.8, 1.05, -2.6)])
	m.set_meta("launcher", Vector3(0, 2.8, -1.7))
	m.set_meta("top", Vector3(0, 1.8, -2.2))
	return m


# ---------------------------------------------------------------- Spectre

## TM2 Spectre: white Sting Ray-style sports car, blue lower body and hood stripe, two big guns
## on the hood, quad lights low on the nose. A faint blue glow underneath (ghost car).
static func spectre() -> Node3D:
	var m := _new_model(0.45)
	var white := MeshKit.grime(Color(0.93, 0.93, 0.96), Color(0.72, 0.72, 0.78), 0.15, 0.3, 0.1)
	var blue := MeshKit.mat(Color(0.14, 0.17, 0.6), 0.35, 0.2)
	var glass := MeshKit.mat(Color(0.05, 0.07, 0.12), 0.08, 0.6)
	var chrome := MeshKit.mat(Color(0.6, 0.6, 0.62), 0.25, 1.0)
	var brass := MeshKit.mat(Color(0.55, 0.5, 0.35), 0.4, 0.7)
	var dark := MeshKit.mat(Color(0.05, 0.05, 0.06), 0.6)

	for side in [-1.0, 1.0]:
		_wheel(m, Vector3(0.95 * side, 0.45, -1.45), 0.45, 0.34, true)
		_wheel(m, Vector3(0.95 * side, 0.45, 1.45), 0.45, 0.36, false)

	MeshKit.box(m, Vector3(2.0, 0.45, 4.5), Vector3(0, 0.62, 0.0), blue)
	MeshKit.box(m, Vector3(2.02, 0.07, 4.4), Vector3(0, 0.8, 0.0), white) # side pinstripe
	MeshKit.box(m, Vector3(2.0, 0.3, 4.5), Vector3(0, 1.0, 0.0), white)
	MeshKit.box(m, Vector3(1.9, 0.18, 1.9), Vector3(0, 1.18, -1.25), white, Vector3(-4, 0, 0))
	MeshKit.prism(m, Vector3(2.0, 0.45, 0.5), Vector3(0, 0.95, -2.45), white, Vector3(-90, 90, 0))
	# Hood stripe: wide blue band with white pinstripes.
	MeshKit.box(m, Vector3(0.55, 0.02, 2.0), Vector3(0, 1.28, -1.25), blue, Vector3(-4, 0, 0))
	for x in [-0.3, 0.3]:
		MeshKit.box(m, Vector3(0.04, 0.025, 2.0), Vector3(x, 1.29, -1.25), white, Vector3(-4, 0, 0))
	# Fastback cabin.
	MeshKit.box(m, Vector3(1.6, 0.42, 1.5), Vector3(0, 1.36, 0.45), white)
	MeshKit.box(m, Vector3(1.5, 0.44, 0.06), Vector3(0, 1.36, -0.36), glass, Vector3(-35, 0, 0))
	MeshKit.box(m, Vector3(1.4, 0.06, 1.1), Vector3(0, 1.5, 1.4), glass, Vector3(14, 0, 0))
	for side in [-1.0, 1.0]:
		MeshKit.box(m, Vector3(0.04, 0.32, 1.2), Vector3(0.81 * side, 1.38, 0.4), glass)
	MeshKit.box(m, Vector3(1.9, 0.25, 0.5), Vector3(0, 1.05, 2.05), white)
	# Grille and quad headlights low on the nose.
	MeshKit.box(m, Vector3(1.4, 0.18, 0.06), Vector3(0, 0.75, -2.28), dark)
	for i in 6:
		MeshKit.box(m, Vector3(0.04, 0.16, 0.08), Vector3(-0.55 + i * 0.22, 0.75, -2.3), chrome)
	_headlights(m, [Vector3(-0.8, 0.78, -2.27), Vector3(-0.55, 0.78, -2.27), Vector3(0.55, 0.78, -2.27), Vector3(0.8, 0.78, -2.27)], Vector3(0, 0.8, -2.4), true)
	_taillights(m, [Vector3(-0.7, 1.0, 2.31), Vector3(-0.45, 1.0, 2.31), Vector3(0.45, 1.0, 2.31), Vector3(0.7, 1.0, 2.31)])
	MeshKit.box(m, Vector3(2.1, 0.12, 0.15), Vector3(0, 0.5, -2.27), chrome)
	# The two big hood guns.
	var muzzles: Array = []
	for x in [-0.6, 0.6]:
		MeshKit.box(m, Vector3(0.3, 0.3, 0.8), Vector3(x, 1.45, -1.0), brass)
		for k in 4:
			MeshKit.box(m, Vector3(0.32, 0.02, 0.04), Vector3(x, 1.38 + k * 0.05, -0.65 - k * 0.12), dark)
		MeshKit.cylinder(m, 0.06, 1.0, Vector3(x, 1.45, -1.85), brass, Vector3(90, 0, 0), 8)
		muzzles.append(Vector3(x, 1.45, -2.4))
	m.set_meta("guns", muzzles)
	# Ghostly underglow.
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 0.75, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 4.0
	glow.position = Vector3(0, 0.25, 0)
	m.add_child(glow)

	m.set_meta("launcher", Vector3(0, 1.75, -0.6))
	m.set_meta("top", Vector3(0, 1.5, 0.6))
	return m
