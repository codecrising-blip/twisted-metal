class_name HeroModels
extends RefCounted
## Detailed models for the preview cars, built with MeshBuilder (parts merged per material) and
## MatKit (generated paint, rust, steel, rubber). Our own designs, carrying each character's idea,
## made to look like war machines that have been through a lot (owner, session 5: "serious, not toys"):
##   Sweet Tooth: armored ice cream step van. Welded wedge plow, gatlings in the nose, steel mesh over
##                the windshield, roll-up steel shutter on the serving hatch, napalm mortar on the roof
##                and a scorched, cracked fiberglass cone sign that burns from the inside.
##   Outlaw:      armored police interceptor. Push bar, louvered steel over the windshield, twin hood
##                guns in an armored box, low light bar and a caged taser coil on the trunk.
## Proportions stay close to real vehicles, wheels sit under fender arches, metal is dark and worn
## (no shiny chrome), and MeshBuilder bakes road dust into the lower body.
## Same conventions as VehicleModels: faces -Z, wheels touch y = 0, metadata on the model node.

const GRIME := 1.0


# ---------------------------------------------------------------- shared parts

static var _wheel_cache := {}


## Tire + rim + lug nuts, built once per style and shared by every wheel of that style.
##   "commercial": dark steel dish wheel, 8 lugs, vent holes (trucks)
##   "steelie":    black steel police wheel with slots and a small center cap
static func _wheel_parts(radius: float, width: float, style: String) -> Array:
	var key := "%s_%.2f_%.2f" % [style, radius, width]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var rubber := MatKit.rubber()
	var rim_mat: Material = MatKit.steel(Color(0.2, 0.2, 0.2), 0.45, 0.8) if style == "commercial" else MatKit.steel(Color(0.06, 0.06, 0.065), 0.25, 0.8)
	var bare := MatKit.steel(Color(0.34, 0.33, 0.31), 0.3, 0.6)
	var hole := MatKit.flat(Color(0.02, 0.02, 0.02), 0.95)
	var mb := MeshBuilder.new()
	var w := width * 0.5
	var r_in := radius * 0.64
	var r_out := radius - 0.02
	# Tire cross section around the rubber (lathe axis = axle): bulging sidewalls, flat tread.
	var prof := PackedVector2Array([
		Vector2(r_in, -w + 0.03), Vector2(r_in + 0.05, -w), Vector2(r_out - 0.09, -w - 0.01),
		Vector2(r_out - 0.03, -w + 0.04), Vector2(r_out, -w * 0.6), Vector2(r_out, w * 0.6),
		Vector2(r_out - 0.03, w - 0.04), Vector2(r_out - 0.09, w + 0.01), Vector2(r_in + 0.05, w),
		Vector2(r_in, w - 0.03),
	])
	mb.lathe(rubber, prof, Transform3D.IDENTITY, 30)
	# Tread: chunky staggered blocks plus shoulder lugs.
	var blocks := 24
	for i in blocks:
		for row: float in [-1.0, 1.0]:
			var a := TAU * (i + (0.5 if row > 0.0 else 0.0)) / blocks
			var pos := Vector3(cos(a) * (r_out + 0.012), row * w * 0.38, sin(a) * (r_out + 0.012))
			mb.box(rubber, Vector3(0.04, w * 0.62, 0.075), Transform3D(Basis(Vector3.UP, -a), pos), 0.008)
		var sa := TAU * i / blocks
		for row: float in [-1.0, 1.0]:
			var sp := Vector3(cos(sa) * (r_out - 0.04), row * (w - 0.005), sin(sa) * (r_out - 0.04))
			mb.box(rubber, Vector3(0.06, 0.03, 0.05), Transform3D(Basis(Vector3.UP, -sa), sp), 0.006)
	# Rim on the outer face (+Y), set deep into the tire.
	var face := w - 0.06
	if style == "commercial":
		mb.lathe(rim_mat, PackedVector2Array([Vector2(r_in + 0.005, face + 0.02), Vector2(r_in - 0.03, face + 0.03),
			Vector2(r_in - 0.05, face - 0.02), Vector2(r_in * 0.62, face - 0.05), Vector2(r_in * 0.42, face - 0.01),
			Vector2(r_in * 0.3, face + 0.01), Vector2(0.0, face + 0.01)]), Transform3D.IDENTITY, 28)
		for i in 8:
			var a := TAU * i / 8.0 + 0.2
			mb.cylinder(hole, 0.035, 0.012, MeshBuilder.at(Vector3(cos(a) * r_in * 0.74, face - 0.03, sin(a) * r_in * 0.74)), 8)
		for i in 8:
			var a := TAU * i / 8.0
			mb.cylinder(bare, 0.022, 0.05, MeshBuilder.at(Vector3(cos(a) * r_in * 0.36, face + 0.02, sin(a) * r_in * 0.36)), 6)
		mb.lathe(rim_mat, PackedVector2Array([Vector2(r_in * 0.22, face), Vector2(r_in * 0.2, face + 0.07), Vector2(r_in * 0.1, face + 0.1), Vector2(0.0, face + 0.1)]), Transform3D.IDENTITY, 14)
	else:
		mb.lathe(rim_mat, PackedVector2Array([Vector2(r_in + 0.005, face + 0.02), Vector2(r_in - 0.03, face + 0.025),
			Vector2(r_in - 0.04, face - 0.03), Vector2(r_in * 0.55, face - 0.04), Vector2(r_in * 0.35, face),
			Vector2(0.0, face)]), Transform3D.IDENTITY, 28)
		for i in 6:
			var a := TAU * i / 6.0
			mb.box(hole, Vector3(0.05, 0.012, 0.11), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r_in * 0.7, face - 0.035, sin(a) * r_in * 0.7)), 0.01)
		for i in 5:
			var a := TAU * i / 5.0 + 0.3
			mb.cylinder(bare, 0.018, 0.04, MeshBuilder.at(Vector3(cos(a) * r_in * 0.25, face + 0.015, sin(a) * r_in * 0.25)), 6)
		mb.cylinder(bare, r_in * 0.13, 0.05, MeshBuilder.at(Vector3(0, face + 0.02, 0)), 12)
	var holder := Node3D.new()
	var parts: Array = []
	for mi in mb.commit(holder, true, 0.55, 0.0):
		parts.append([mi.mesh, mi.material_override])
	holder.free()
	_wheel_cache[key] = parts
	return parts


## Adds a wheel at pos; registers spin (and steer for front wheels) in the model metadata.
static func _wheel(m: Node3D, pos: Vector3, radius: float, width: float, front: bool, style: String) -> void:
	var steer := Node3D.new()
	steer.position = pos
	m.add_child(steer)
	var spin := Node3D.new()
	steer.add_child(spin)
	var side := signf(pos.x)
	var holder := Node3D.new()
	# Lathe axis is Y; turn it so the rim faces outward (+X on the right, -X on the left).
	holder.rotation_degrees = Vector3(0, 0, -90.0 * side)
	spin.add_child(holder)
	_add_parts(holder, _wheel_parts(radius, width, style))
	m.get_meta("wheels").append(spin)
	if front:
		m.get_meta("steer").append(steer)


static func _add_parts(parent: Node3D, parts: Array) -> void:
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		parent.add_child(mi)


static func _new_model(wheel_radius: float) -> Node3D:
	var m := Node3D.new()
	m.name = "Model"
	m.set_meta("wheels", [])
	m.set_meta("steer", [])
	m.set_meta("wheel_radius", wheel_radius)
	return m


## Soft dark patch on the ground under the car (contact shadow): keeps it from looking pasted on.
static var _shadow_mat: StandardMaterial3D

static func _ground_shadow(m: Node3D, size: Vector2) -> void:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.albedo_texture = FxKit.soft_texture()
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.6)
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _shadow_mat
	mi.position = Vector3(0, 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(mi)


## Rotary gatling: armored housing, six barrels on a spinner node, clamp rings. Returns the muzzle.
static func _gatling(m: Node3D, mb: MeshBuilder, pos: Vector3, housing: Material, barrel: Material, spinners: Array, length := 0.75) -> Vector3:
	mb.box(housing, Vector3(0.32, 0.3, 0.62), MeshBuilder.at(pos + Vector3(0, 0, 0.16)), 0.05)
	mb.box(housing, Vector3(0.14, 0.1, 0.3), MeshBuilder.at(pos + Vector3(0, 0.19, 0.25)), 0.02) # feed chute
	var spinner := Node3D.new()
	spinner.position = pos + Vector3(0, 0, -0.15)
	m.add_child(spinner)
	var gb := MeshBuilder.new()
	for i in 6:
		var a := TAU * i / 6.0
		gb.cylinder(barrel, 0.024, length, MeshBuilder.along(Vector3(cos(a) * 0.065, sin(a) * 0.065, -length * 0.5), Vector3.FORWARD), 6)
	for z: float in [-0.12, -length * 0.55, -length + 0.06]:
		gb.cylinder(housing, 0.1, 0.05, MeshBuilder.along(Vector3(0, 0, z), Vector3.FORWARD), 10)
	gb.cylinder(barrel, 0.03, length * 0.9, MeshBuilder.along(Vector3(0, 0, -length * 0.45), Vector3.FORWARD), 6)
	gb.commit(spinner, true, 0.4, pos.y)
	spinners.append(spinner)
	return pos + Vector3(0, 0, -length - 0.2)


## Row of hex bolt heads from a to b, sticking out along `outward`.
static func _bolts(mb: MeshBuilder, mat: Material, a: Vector3, b: Vector3, count: int, outward: Vector3) -> void:
	for i in count:
		var p := a.lerp(b, float(i) / maxf(1.0, count - 1))
		mb.cylinder(mat, 0.022, 0.025, MeshBuilder.along(p + outward * 0.01, outward), 6)


## Welded fender arch over a wheel: short steel segments following a circle in the side plane.
static func _arch(mb: MeshBuilder, mat: Material, wheel: Vector3, radius: float, x_in: float, x_out: float, thick := 0.05) -> void:
	var seg := 7
	var a0 := deg_to_rad(10.0)
	var a1 := deg_to_rad(170.0)
	var width := absf(x_out - x_in)
	var xc := (x_in + x_out) * 0.5
	for i in seg:
		var ta := lerpf(a0, a1, float(i) / seg)
		var tb := lerpf(a0, a1, float(i + 1) / seg)
		var pa := Vector3(xc, wheel.y + sin(ta) * radius, wheel.z - cos(ta) * radius)
		var pb := Vector3(xc, wheel.y + sin(tb) * radius, wheel.z - cos(tb) * radius)
		var mid := (pa + pb) * 0.5
		mb.box(mat, Vector3(width, pa.distance_to(pb) + 0.03, thick), MeshBuilder.along(mid, pb - pa), 0.012)


## Welded square mesh over a flat window. Corners a (bottom left), b (bottom right), c (top right),
## d (top left); the grid sits `lift` off the glass along n.
static func _mesh_grate(mb: MeshBuilder, mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, across: int, up: int, lift := 0.05) -> void:
	var off := n * lift
	for i in across + 1:
		var t := float(i) / across
		var p0 := a.lerp(b, t) + off
		var p1 := d.lerp(c, t) + off
		mb.cylinder(mat, 0.012, p0.distance_to(p1), MeshBuilder.along((p0 + p1) * 0.5, p1 - p0), 4, -1.0, false)
	for j in up + 1:
		var t := float(j) / up
		var p0 := a.lerp(d, t) + off * 1.3
		var p1 := b.lerp(c, t) + off * 1.3
		mb.cylinder(mat, 0.012, p0.distance_to(p1), MeshBuilder.along((p0 + p1) * 0.5, p1 - p0), 4, -1.0, false)


## Painted lettering (Label3D, lit by the scene so it reads as paint, slightly see-through = worn).
static func _paint_text(m: Node3D, text: String, pos: Vector3, yaw: float, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 0
	l.modulate = Color(color.r, color.g, color.b, 0.82)
	l.position = pos
	l.rotation_degrees.y = yaw
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	m.add_child(l)
	return l


static func _headlight_beam(m: Node3D, pos: Vector3) -> void:
	var spot := SpotLight3D.new()
	spot.position = pos
	spot.light_color = Color(1.0, 0.93, 0.8)
	spot.light_energy = 3.0
	spot.spot_range = 32.0
	spot.spot_angle = 30.0
	spot.spot_attenuation = 0.8
	spot.rotation_degrees = Vector3(-6, 0, 0)
	spot.add_to_group(GraphicsSettings.HEADLIGHT_GROUP)
	spot.visible = GraphicsSettings.high
	m.add_child(spot)


# ---------------------------------------------------------------- Sweet Tooth

static func sweet_tooth() -> Node3D:
	var R := 0.52
	var m := _new_model(R)
	var cream := MatKit.paint(Color(0.72, 0.68, 0.58), 0.8, 0.65, 0.75, 2.2, 0.58, 11)
	var crimson := MatKit.paint(Color(0.42, 0.07, 0.1), 0.75, 0.45, 0.55, 2.0, 0.55, 12)
	var armor := MatKit.steel(Color(0.16, 0.16, 0.16), 0.6, 1.4)
	var dark := MatKit.steel(Color(0.06, 0.06, 0.065), 0.3, 1.0)
	var bare := MatKit.steel(Color(0.34, 0.33, 0.31), 0.35, 0.6)
	var soot := MatKit.steel(Color(0.11, 0.09, 0.08), 0.7, 0.8)
	var olive := MatKit.paint(Color(0.22, 0.24, 0.16), 0.6, 0.4, 0.6, 1.0, 0.6, 15)
	var glass := MatKit.glass(Color(0.03, 0.04, 0.05), 0.92)
	var black := MatKit.flat(Color(0.012, 0.012, 0.012), 0.95)
	var mb := MeshBuilder.new()

	var front_z := -1.95
	var rear_z := 1.75
	for side: float in [-1.0, 1.0]:
		_wheel(m, Vector3(1.08 * side, R, front_z), R, 0.38, true, "commercial")
		_wheel(m, Vector3(1.06 * side, R, rear_z), R, 0.5, false, "commercial")

	# Under the body: frame rails, cross members, fuel tank, dark wheel wells.
	for side: float in [-1.0, 1.0]:
		mb.box(dark, Vector3(0.16, 0.2, 5.8), MeshBuilder.at(Vector3(0.6 * side, 0.66, 0.05)), 0.03)
		for z: float in [front_z, rear_z]:
			mb.box(black, Vector3(0.06, 0.7, 1.35), MeshBuilder.at(Vector3(0.78 * side, 0.85, z)), 0.0)
	for z: float in [-2.6, -0.9, 0.6, 2.5]:
		mb.box(dark, Vector3(1.2, 0.12, 0.14), MeshBuilder.at(Vector3(0, 0.66, z)), 0.02)
	mb.cylinder(olive, 0.22, 1.0, MeshBuilder.at(Vector3(-0.42, 0.58, 0.2), Vector3(90, 0, 0)), 14)

	# Cab: short engine hood, a steep windshield, then the roof running into the box.
	var cab := [
		MeshBuilder.section(-3.0, 1.33, 1.1, 0.23, 0.06),
		MeshBuilder.section(-2.4, 1.38, 1.16, 0.28, 0.08),
		MeshBuilder.section(-1.9, 1.96, 1.2, 0.86, 0.1),
		MeshBuilder.section(-1.28, 1.96, 1.2, 0.86, 0.1),
	]
	mb.loft(cream, cab, Transform3D.IDENTITY, 3, true, false)
	# Windshield on the slope (z -2.4, y 1.66) -> (z -1.9, y 2.82), behind a welded steel grate.
	var s0 := Vector3(0, 1.66, -2.4)
	var s1 := Vector3(0, 2.82, -1.9)
	var wn := Vector3(0, 0.5, -1.16).normalized()
	var wa := s0.lerp(s1, 0.08) + wn * 0.015
	var wb := s0.lerp(s1, 0.9) + wn * 0.015
	mb.quad(glass, wa + Vector3(-1.0, 0, 0), wa + Vector3(1.0, 0, 0), wb + Vector3(1.0, 0, 0), wb + Vector3(-1.0, 0, 0), wn)
	mb.box(dark, Vector3(0.08, s0.distance_to(s1) * 0.84, 0.04), MeshBuilder.along((wa + wb) * 0.5 + wn * 0.02, s1 - s0), 0.0)
	_mesh_grate(mb, dark, wa + Vector3(-1.02, 0, 0), wa + Vector3(1.02, 0, 0), wb + Vector3(1.02, 0, 0), wb + Vector3(-1.02, 0, 0), wn, 12, 6, 0.06)
	for x: float in [-1.06, 1.06]:
		mb.box(armor, Vector3(0.1, s0.distance_to(s1) * 0.9, 0.06), MeshBuilder.along((wa + wb) * 0.5 + Vector3(x, 0, 0) + wn * 0.05, s1 - s0), 0.015)
	var visor_c := s0.lerp(s1, 0.96) + wn * 0.12
	mb.box(armor, Vector3(2.34, 0.05, 0.42), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), visor_c + Vector3(0, 0.02, -0.12)), 0.02)
	_bolts(mb, bare, visor_c + Vector3(-1.05, 0.06, -0.25), visor_c + Vector3(1.05, 0.06, -0.25), 9, Vector3.UP)
	# Cab sides: armored window plates with vision slits, door seams, mirrors.
	for side: float in [-1.0, 1.0]:
		var x := 1.2 * side
		mb.box(armor, Vector3(0.05, 0.82, 0.56), MeshBuilder.at(Vector3(x + 0.015 * side, 2.18, -1.62)), 0.02)
		for y: float in [2.22, 2.34]:
			mb.box(black, Vector3(0.02, 0.045, 0.4), MeshBuilder.at(Vector3(x + 0.045 * side, y, -1.62)), 0.0)
		_bolts(mb, bare, Vector3(x + 0.04 * side, 2.55, -1.85), Vector3(x + 0.04 * side, 2.55, -1.39), 4, Vector3(side, 0, 0))
		_bolts(mb, bare, Vector3(x + 0.04 * side, 1.81, -1.85), Vector3(x + 0.04 * side, 1.81, -1.39), 4, Vector3(side, 0, 0))
		for z: float in [-1.92, -1.32]:
			mb.box(black, Vector3(0.012, 1.55, 0.018), MeshBuilder.at(Vector3(x + 0.004 * side, 1.9, z)), 0.0)
		mb.box(bare, Vector3(0.05, 0.05, 0.16), MeshBuilder.at(Vector3(x + 0.03 * side, 1.62, -1.45)), 0.01)
		var arm_a := Vector3(x, 2.35, -1.75)
		var arm_b := Vector3(1.48 * side, 2.32, -1.82)
		mb.cylinder(dark, 0.018, arm_a.distance_to(arm_b), MeshBuilder.along((arm_a + arm_b) * 0.5, arm_b - arm_a), 6)
		mb.cylinder(dark, 0.018, 0.5, MeshBuilder.at(Vector3(1.48 * side, 2.12, -1.82)), 6)
		mb.box(black, Vector3(0.07, 0.42, 0.2), MeshBuilder.at(Vector3(1.5 * side, 2.12, -1.84)), 0.025)

	# The box body, its faded stripe and lettering.
	mb.box(cream, Vector3(2.44, 1.9, 4.42), MeshBuilder.at(Vector3(0, 2.05, 0.93)), 0.12)
	mb.box(crimson, Vector3(2.47, 0.32, 4.45), MeshBuilder.at(Vector3(0, 2.62, 0.93)), 0.05)
	mb.box(crimson, Vector3(2.47, 0.06, 4.45), MeshBuilder.at(Vector3(0, 2.4, 0.93)), 0.02)
	# Lower armor: skirts between the wheels and bolted plates on the box.
	for side: float in [-1.0, 1.0]:
		var sx := 1.17 * side
		mb.box(armor, Vector3(0.1, 0.52, 2.3), MeshBuilder.at(Vector3(sx, 0.88, -0.12)), 0.03)
		mb.box(armor, Vector3(0.1, 0.52, 0.66), MeshBuilder.at(Vector3(sx, 0.88, 2.82)), 0.03)
		_bolts(mb, bare, Vector3(sx + 0.05 * side, 1.08, -1.2), Vector3(sx + 0.05 * side, 1.08, 0.95), 10, Vector3(side, 0, 0))
		for z: float in [-0.55, 0.9, 2.35]:
			mb.box(armor, Vector3(0.05, 0.5, 1.38), MeshBuilder.at(Vector3(1.235 * side, 1.38, z)), 0.02)
			_bolts(mb, bare, Vector3(1.26 * side, 1.58, z - 0.6), Vector3(1.26 * side, 1.58, z + 0.6), 6, Vector3(side, 0, 0))
			_bolts(mb, bare, Vector3(1.26 * side, 1.18, z - 0.6), Vector3(1.26 * side, 1.18, z + 0.6), 6, Vector3(side, 0, 0))
		_arch(mb, armor, Vector3(0, R, front_z), R + 0.14, 1.06 * side, 1.34 * side)
		_arch(mb, armor, Vector3(0, R, rear_z), R + 0.14, 1.04 * side, 1.38 * side)
		_paint_text(m, "ICE CREAM", Vector3(1.237 * side, 2.62, 0.93), 90.0 * side, 64, Color(0.78, 0.72, 0.6))
	# Serving hatch (right side), closed behind a roll-up steel shutter, with a counter shelf.
	mb.box(bare, Vector3(0.05, 0.86, 1.82), MeshBuilder.at(Vector3(1.23, 2.0, 0.9)), 0.02)
	for k in 9:
		mb.box(armor, Vector3(0.05, 0.075, 1.68), MeshBuilder.at(Vector3(1.25, 1.64 + k * 0.08, 0.9)), 0.012)
	mb.box(dark, Vector3(0.3, 0.05, 1.8), MeshBuilder.at(Vector3(1.37, 1.6, 0.9)), 0.01)
	for z: float in [0.1, 1.7]:
		mb.box(dark, Vector3(0.22, 0.05, 0.05), MeshBuilder.at(Vector3(1.31, 1.5, z), Vector3(0, 0, 40)), 0.0)
	# Rear: barn doors, hinges, armored slit windows, lamps, bumper, ladder, spare wheel.
	mb.box(black, Vector3(0.015, 1.75, 0.015), MeshBuilder.at(Vector3(0, 2.0, 3.146)), 0.0)
	for side: float in [-1.0, 1.0]:
		for y: float in [1.45, 2.6]:
			mb.box(dark, Vector3(0.18, 0.1, 0.05), MeshBuilder.at(Vector3(1.1 * side, y, 3.16)), 0.01)
		mb.box(armor, Vector3(0.6, 0.36, 0.04), MeshBuilder.at(Vector3(0.45 * side, 2.55, 3.16)), 0.015)
		mb.box(black, Vector3(0.44, 0.04, 0.02), MeshBuilder.at(Vector3(0.45 * side, 2.55, 3.185)), 0.0)
		mb.box(bare, Vector3(0.04, 0.18, 0.06), MeshBuilder.at(Vector3(0.12 * side, 1.95, 3.17)), 0.01)
		mb.box(dark, Vector3(0.26, 0.42, 0.08), MeshBuilder.at(Vector3(1.0 * side, 1.38, 3.14)), 0.02)
		mb.box(MatKit.lamp(Color(0.8, 0.04, 0.03), 2.2), Vector3(0.18, 0.2, 0.03), MeshBuilder.at(Vector3(1.0 * side, 1.45, 3.18)), 0.01)
		mb.box(MatKit.lamp(Color(0.9, 0.45, 0.06), 1.5), Vector3(0.18, 0.1, 0.03), MeshBuilder.at(Vector3(1.0 * side, 1.25, 3.18)), 0.01)
		for k in 3:
			mb.cylinder(dark, 0.01, 0.42, MeshBuilder.at(Vector3(1.0 * side - 0.08 + k * 0.08, 1.38, 3.22)), 4)
	mb.box(dark, Vector3(2.36, 0.3, 0.32), MeshBuilder.at(Vector3(0, 0.8, 3.28)), 0.05)
	_bolts(mb, bare, Vector3(-1.0, 0.8, 3.445), Vector3(1.0, 0.8, 3.445), 8, Vector3.BACK)
	mb.box(dark, Vector3(0.12, 0.12, 0.25), MeshBuilder.at(Vector3(0, 0.66, 3.5)), 0.02)
	for side: float in [-1.0, 1.0]:
		mb.cylinder(dark, 0.022, 2.0, MeshBuilder.at(Vector3(-0.85 + 0.2 * side, 2.0, 3.24)), 6)
	for k in 7:
		mb.cylinder(dark, 0.018, 0.4, MeshBuilder.at(Vector3(-0.85, 1.15 + k * 0.28, 3.24), Vector3(0, 0, 90)), 6)
	var spare := Node3D.new()
	spare.position = Vector3(0.5, 1.95, 3.42)
	spare.rotation_degrees = Vector3(90, 0, 0)
	m.add_child(spare)
	_add_parts(spare, _wheel_parts(R, 0.38, "commercial"))
	mb.box(dark, Vector3(0.5, 0.08, 0.2), MeshBuilder.at(Vector3(0.5, 1.95, 3.2)), 0.01)

	# Nose: grille, caged headlights, the welded wedge plow with spikes, gatlings at the corners.
	mb.box(black, Vector3(0.66, 0.36, 0.04), MeshBuilder.at(Vector3(0, 1.33, -3.005)), 0.0)
	for k in 7:
		mb.box(bare, Vector3(0.035, 0.36, 0.05), MeshBuilder.at(Vector3(-0.3 + k * 0.1, 1.33, -3.02)), 0.0)
	for side: float in [-1.0, 1.0]:
		mb.box(dark, Vector3(0.34, 0.24, 0.07), MeshBuilder.at(Vector3(0.58 * side, 1.36, -3.01)), 0.02)
		mb.box(MatKit.lamp(Color(1.0, 0.92, 0.75), 3.5), Vector3(0.26, 0.16, 0.02), MeshBuilder.at(Vector3(0.58 * side, 1.36, -3.05)), 0.01)
		for k in 3:
			mb.box(dark, Vector3(0.018, 0.26, 0.018), MeshBuilder.at(Vector3(0.58 * side - 0.09 + k * 0.09, 1.36, -3.1)), 0.0)
		mb.box(MatKit.lamp(Color(0.95, 0.5, 0.08), 1.4), Vector3(0.12, 0.06, 0.03), MeshBuilder.at(Vector3(0.58 * side, 1.18, -3.04)), 0.0)
	# Wedge plow: a center blade and two wings swept back to the body corners, welded to rails.
	var tip_z := -3.36
	mb.box(armor, Vector3(1.36, 0.74, 0.08), MeshBuilder.at(Vector3(0, 0.8, tip_z), Vector3(18, 0, 0)), 0.02)
	for side: float in [-1.0, 1.0]:
		var inner := Vector3(0.67 * side, 0.8, tip_z)
		var outer := Vector3(1.26 * side, 0.8, -2.98)
		var wing_mid := (inner + outer) * 0.5
		var yaw := -rad_to_deg(atan2(outer.z - inner.z, absf(outer.x - inner.x))) * side
		mb.box(armor, Vector3(inner.distance_to(outer) + 0.04, 0.74, 0.08), MeshBuilder.at(wing_mid, Vector3(18, yaw, 0)), 0.02)
		mb.box(dark, Vector3(0.12, 0.14, 0.5), MeshBuilder.at(Vector3(0.5 * side, 0.66, -2.98)), 0.02)
		mb.box(dark, Vector3(0.06, 0.6, 0.36), MeshBuilder.at(Vector3(0.67 * side, 0.82, -3.2)), 0.01)
	mb.box(dark, Vector3(1.4, 0.1, 0.12), MeshBuilder.at(Vector3(0, 1.15, -3.25)), 0.02)
	mb.box(dark, Vector3(1.4, 0.08, 0.12), MeshBuilder.at(Vector3(0, 0.46, -3.45)), 0.02)
	for k in 7:
		mb.box(black, Vector3(0.05, 0.03, 0.03), MeshBuilder.at(Vector3(-0.6 + k * 0.2, 1.1, -3.31), Vector3(18, 0, 0)), 0.0)
	for x: float in [-0.5, 0.0, 0.5]:
		mb.lathe(soot, PackedVector2Array([Vector2(0.0, -0.02), Vector2(0.07, 0.0), Vector2(0.0, 0.32)]), MeshBuilder.along(Vector3(x, 0.98, -3.42), Vector3(0, 0.05, -1)), 8, false)
	var spinners: Array = []
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		muzzles.append(_gatling(m, mb, Vector3(0.98 * side, 1.38, -2.95), armor, dark, spinners))

	# Exhaust stacks behind the cab: blackened, with heat shields and rain caps.
	var exhausts: Array = []
	for side: float in [-1.0, 1.0]:
		var base := Vector3(1.31 * side, 0.0, -1.12)
		mb.cylinder(soot, 0.085, 2.5, MeshBuilder.at(base + Vector3(0, 2.35, 0)), 10)
		mb.cylinder(bare, 0.11, 0.7, MeshBuilder.at(base + Vector3(0, 2.0, 0)), 10)
		for k in 6:
			mb.box(black, Vector3(0.03, 0.08, 0.03), MeshBuilder.at(base + Vector3(0.11 * side, 1.75 + k * 0.1, 0.0)), 0.0)
		for y: float in [1.5, 2.9]:
			mb.box(dark, Vector3(0.14, 0.06, 0.08), MeshBuilder.at(base + Vector3(-0.08 * side, y, 0)), 0.01)
		mb.box(soot, Vector3(0.2, 0.02, 0.2), MeshBuilder.at(base + Vector3(0, 3.62, 0.02), Vector3(-30, 0, 0)), 0.0)
		exhausts.append(base + Vector3(0, 3.62, 0.0))

	# Roof: rack, marker lights, refrigeration unit, napalm mortar with fuel cans.
	for side: float in [-1.0, 1.0]:
		mb.cylinder(dark, 0.03, 4.3, MeshBuilder.at(Vector3(1.12 * side, 3.14, 0.95), Vector3(90, 0, 0)), 6)
		for z: float in [-1.1, 0.0, 1.0, 2.0, 3.0]:
			mb.cylinder(dark, 0.025, 0.16, MeshBuilder.at(Vector3(1.12 * side, 3.06, z)), 6)
	for x: float in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		mb.box(MatKit.lamp(Color(1.0, 0.55, 0.1), 1.6), Vector3(0.1, 0.06, 0.06), MeshBuilder.at(Vector3(x, 2.86, -1.86)), 0.01)
	mb.box(armor, Vector3(1.5, 0.36, 0.95), MeshBuilder.at(Vector3(0, 3.18, 2.45)), 0.05)
	for k in 8:
		mb.box(black, Vector3(1.3, 0.24, 0.02), MeshBuilder.at(Vector3(0, 3.19, 2.02 + k * 0.12)), 0.0)
	var mortar_dir := Vector3(0, 1, -0.6).normalized()
	var mortar_base := Vector3(0, 3.12, 1.25)
	mb.cylinder(dark, 0.36, 0.2, MeshBuilder.at(mortar_base), 14)
	mb.box(armor, Vector3(0.5, 0.3, 0.5), MeshBuilder.at(mortar_base + Vector3(0, 0.22, 0)), 0.04)
	mb.cylinder(dark, 0.16, 0.95, MeshBuilder.along(mortar_base + Vector3(0, 0.3, 0) + mortar_dir * 0.45, mortar_dir), 12)
	var launcher := mortar_base + Vector3(0, 0.3, 0) + mortar_dir * 0.95
	mb.cylinder(armor, 0.2, 0.12, MeshBuilder.along(launcher - mortar_dir * 0.06, mortar_dir), 12)
	for side: float in [-1.0, 1.0]:
		mb.cylinder(olive, 0.15, 0.7, MeshBuilder.at(Vector3(0.62 * side, 3.22, 1.35), Vector3(90, 0, 0)), 12)
		mb.box(dark, Vector3(0.36, 0.03, 0.05), MeshBuilder.at(Vector3(0.62 * side, 3.22, 1.15)), 0.0)
		mb.box(dark, Vector3(0.36, 0.03, 0.05), MeshBuilder.at(Vector3(0.62 * side, 3.22, 1.55)), 0.0)
		var hose_a := Vector3(0.62 * side, 3.3, 1.0)
		var hose_b := mortar_base + Vector3(0.2 * side, 0.3, 0.1)
		mb.cylinder(black, 0.025, hose_a.distance_to(hose_b), MeshBuilder.along((hose_a + hose_b) * 0.5, hose_b - hose_a), 6)

	mb.commit(m, true, GRIME)
	_cone_sign(m, Vector3(0, 3.0, -0.1), 0.82)
	_headlight_beam(m, Vector3(0, 1.36, -3.1))
	_ground_shadow(m, Vector2(3.2, 7.4))

	m.set_meta("guns", muzzles)
	m.set_meta("gun_spinners", spinners)
	m.set_meta("exhaust", exhausts)
	m.set_meta("exhaust_dir", Vector3.UP)
	m.set_meta("launcher", launcher)
	m.set_meta("top", Vector3(0, 3.2, 1.0))
	return m


## The roof sign: a fiberglass ice cream cone, scorched and split open by bullets, bolted to a
## steel frame. Something inside it keeps burning.
static func _cone_sign(m: Node3D, base: Vector3, size := 1.0) -> void:
	var sign := Node3D.new()
	sign.name = "ConeSign"
	sign.position = base
	sign.scale = Vector3.ONE * size
	m.add_child(sign)
	m = sign
	base = Vector3.ZERO
	var dark := MatKit.steel(Color(0.06, 0.06, 0.065), 0.3, 1.0)
	var bare := MatKit.steel(Color(0.34, 0.33, 0.31), 0.35, 0.6)
	var wafer := MatKit.paint(Color(0.46, 0.31, 0.16), 0.7, 0.3, 0.85, 0.6, 0.75, 41)
	var wafer_dark := MatKit.flat(Color(0.16, 0.1, 0.05), 0.9)
	var scoop := MatKit.paint(Color(0.5, 0.36, 0.33), 0.85, 0.4, 0.9, 0.8, 0.75, 42)
	var charred := MatKit.flat(Color(0.03, 0.025, 0.02), 0.95)
	var ember := MatKit.lamp(Color(1.0, 0.35, 0.05), 3.0)
	var mb := MeshBuilder.new()
	var c := base + Vector3(0, 1.05, 0) # top of the cone
	# Frame: two raked posts and a clamp ring.
	for side: float in [-1.0, 1.0]:
		var a := base + Vector3(0.42 * side, 0.0, 0.2)
		var b := c + Vector3(0.24 * side, -0.45, 0.0)
		mb.box(dark, Vector3(0.08, a.distance_to(b), 0.08), MeshBuilder.along((a + b) * 0.5, b - a), 0.015)
		mb.box(dark, Vector3(0.3, 0.04, 0.3), MeshBuilder.at(a + Vector3(0, 0.02, 0)), 0.01)
		_bolts(mb, bare, a + Vector3(-0.1, 0.04, 0.1), a + Vector3(0.1, 0.04, 0.1), 2, Vector3.UP)
	mb.torus(dark, 0.27, 0.035, MeshBuilder.at(c + Vector3(0, -0.45, 0)), 14, 5)
	# Cone (tip down) with a waffle grid of dark grooves.
	mb.lathe(wafer, PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.06, -0.94), Vector2(0.5, 0.0), Vector2(0.0, 0.0)]), MeshBuilder.at(c), 16, false)
	for i in 8:
		for dir: float in [-1.0, 1.0]:
			var a0 := TAU * i / 8.0
			var a1 := a0 + 0.8 * dir
			var lo := c + Vector3(cos(a0) * 0.08, -0.9, sin(a0) * 0.08)
			var hi := c + Vector3(cos(a1) * 0.51, -0.02, sin(a1) * 0.51)
			mb.cylinder(wafer_dark, 0.012, lo.distance_to(hi), MeshBuilder.along((lo + hi) * 0.5, hi - lo), 4, -1.0, false)
	mb.torus(wafer, 0.5, 0.05, MeshBuilder.at(c), 16, 6)
	# Scoop: lumpy, sooty, split open across the top with a glowing crack and a blown-out hole.
	var sc := c + Vector3(0, 0.34, 0)
	mb.sphere(scoop, 0.56, MeshBuilder.at(sc, Vector3.ZERO, Vector3(1.0, 0.86, 1.0)), 18, 10)
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		mb.sphere(scoop, 0.15, MeshBuilder.at(c + Vector3(cos(a) * 0.48, 0.03, sin(a) * 0.48), Vector3.ZERO, Vector3(1.1, 0.7, 1.1)), 8, 5)
	for i in 9:
		var t := (i - 4) / 4.0
		var p := sc + Vector3(t * 0.42, 0.46 - t * t * 0.18, sin(t * 5.0) * 0.06)
		mb.box(charred, Vector3(0.12, 0.06, 0.1 + absf(sin(i * 1.7)) * 0.06), MeshBuilder.at(p, Vector3(0, i * 23.0, -t * 30.0)), 0.01)
		mb.box(ember, Vector3(0.08, 0.02, 0.05), MeshBuilder.at(p + Vector3(0, 0.025, 0), Vector3(0, i * 23.0, -t * 30.0)), 0.0)
	var hole := sc + Vector3(-0.32, 0.1, 0.36) # blown out at the back
	mb.sphere(charred, 0.17, MeshBuilder.at(hole, Vector3.ZERO, Vector3(1.0, 0.8, 0.6)), 10, 6)
	mb.sphere(ember, 0.07, MeshBuilder.at(hole + Vector3(0.04, -0.02, 0.04)), 8, 5)
	for i in 6:
		var a := TAU * i / 6.0
		mb.sphere(charred, 0.05, MeshBuilder.at(sc + Vector3(cos(a) * 0.4, 0.15 + sin(a * 2.0) * 0.1, sin(a) * 0.4), Vector3.ZERO, Vector3(1, 0.4, 1)), 6, 4)
	mb.commit(m, true, 0.25, 3.0)
	var fire := FxKit.fire(0.32, 10)
	fire.position = sc + Vector3(0, 0.4, 0)
	fire.emission_sphere_radius = 0.14
	fire.color_ramp = FxKit._ramp([Color(0.9, 0.45, 0.12, 0.45), Color(0.8, 0.22, 0.04, 0.35), Color(0.3, 0.07, 0.02, 0.2), Color(0.08, 0.05, 0.05, 0.0)])
	m.add_child(fire)
	fire.emitting = true
	var glow := FlickerLight.new()
	glow.light_color = Color(1.0, 0.45, 0.12)
	glow.base_energy = 0.8
	glow.omni_range = 4.0
	glow.position = sc + Vector3(0, 0.7, 0)
	m.add_child(glow)


# ---------------------------------------------------------------- Outlaw

static func outlaw() -> Node3D:
	var R := 0.44
	var m := _new_model(R)
	var black := MatKit.paint(Color(0.045, 0.045, 0.05), 0.65, 0.3, 0.6, 2.0, 0.42, 31)
	var white := MatKit.paint(Color(0.74, 0.74, 0.71), 0.7, 0.35, 0.7, 2.0, 0.5, 32)
	var armor := MatKit.steel(Color(0.14, 0.14, 0.145), 0.5, 1.2)
	var dark := MatKit.steel(Color(0.06, 0.06, 0.065), 0.3, 1.0)
	var bare := MatKit.steel(Color(0.34, 0.33, 0.31), 0.35, 0.6)
	var soot := MatKit.steel(Color(0.11, 0.09, 0.08), 0.7, 0.8)
	var glass := MatKit.glass(Color(0.03, 0.04, 0.05), 0.92)
	var rubber := MatKit.rubber()
	var void_mat := MatKit.flat(Color(0.012, 0.012, 0.012), 0.95)
	var brass := MatKit.paint(Color(0.55, 0.42, 0.18), 0.5, 0.1, 0.4, 0.5, 0.35, 33)
	brass.metallic = 0.8
	var mb := MeshBuilder.new()

	var front_z := -1.62
	var rear_z := 1.55
	for side: float in [-1.0, 1.0]:
		_wheel(m, Vector3(0.96 * side, R, front_z), R, 0.33, true, "steelie")
		_wheel(m, Vector3(0.96 * side, R, rear_z), R, 0.37, false, "steelie")

	# Hull: a narrow tub through the wheel zones, full-width shoulders over the wheels, door
	# panels between them. That gives real wheel openings instead of tires poking through paint.
	mb.loft(black, [MeshBuilder.section(-2.5, 0.64, 0.74, 0.29, 0.08), MeshBuilder.section(2.5, 0.64, 0.74, 0.29, 0.08)], Transform3D.IDENTITY, 2)
	var shoulder := [
		MeshBuilder.section(-2.62, 0.99, 0.98, 0.09, 0.07),
		MeshBuilder.section(-2.32, 1.03, 1.06, 0.11, 0.08),
		MeshBuilder.section(-1.0, 1.04, 1.08, 0.11, 0.08),
		MeshBuilder.section(1.3, 1.05, 1.08, 0.11, 0.08),
		MeshBuilder.section(2.35, 1.03, 1.05, 0.11, 0.08),
		MeshBuilder.section(2.62, 1.0, 0.98, 0.09, 0.07),
	]
	mb.loft(black, shoulder, Transform3D.IDENTITY, 3)
	for side: float in [-1.0, 1.0]:
		mb.box(white, Vector3(0.1, 0.58, 2.1), MeshBuilder.at(Vector3(1.0 * side, 0.64, -0.06)), 0.03)
		mb.box(white, Vector3(0.025, 0.2, 2.1), MeshBuilder.at(Vector3(1.075 * side, 1.04, -0.06)), 0.0)
		mb.box(black, Vector3(0.1, 0.58, 0.42), MeshBuilder.at(Vector3(0.94 * side, 0.62, -2.36)), 0.03)
		mb.box(black, Vector3(0.1, 0.58, 0.44), MeshBuilder.at(Vector3(0.94 * side, 0.64, 2.38)), 0.03)
		_arch(mb, armor, Vector3(0, R, front_z), R + 0.11, 0.92 * side, 1.15 * side, 0.045)
		_arch(mb, armor, Vector3(0, R, rear_z), R + 0.11, 0.92 * side, 1.17 * side, 0.045)
		# Rocker armor, door seams, handles, badge, bullet strikes.
		mb.box(armor, Vector3(0.07, 0.16, 2.2), MeshBuilder.at(Vector3(1.06 * side, 0.43, -0.06)), 0.02)
		_bolts(mb, bare, Vector3(1.095 * side, 0.43, -1.05), Vector3(1.095 * side, 0.43, 0.95), 9, Vector3(side, 0, 0))
		for z: float in [-1.08, 0.45, 0.98]:
			mb.box(void_mat, Vector3(0.012, 0.7, 0.016), MeshBuilder.at(Vector3(1.052 * side, 0.78, z)), 0.0)
		for z: float in [-0.3, 0.72]:
			mb.box(dark, Vector3(0.035, 0.035, 0.14), MeshBuilder.at(Vector3(1.07 * side, 1.0, z)), 0.01)
		var star := Vector3(1.058 * side, 0.92, -0.7)
		_star(mb, brass, star, side)
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + int(side)
		for i in 7:
			var p := Vector3(1.058 * side, rng.randf_range(0.5, 1.05), rng.randf_range(-1.0, 0.9))
			mb.cylinder(void_mat, 0.022, 0.01, MeshBuilder.along(p, Vector3(side, 0, 0)), 8)
			mb.torus(bare, 0.03, 0.008, MeshBuilder.along(p, Vector3(side, 0, 0)), 8, 4)
		_paint_text(m, "POLICE", Vector3(1.059 * side, 0.68, -0.08), 90.0 * side, 56, Color(0.04, 0.05, 0.08))

	# Cabin: white roof, windows on its slopes.
	var cabin := [
		MeshBuilder.section(-0.9, 1.15, 0.98, 0.02, 0.01, 0.95),
		MeshBuilder.section(-0.25, 1.38, 0.97, 0.24, 0.1, 0.78),
		MeshBuilder.section(0.85, 1.38, 0.97, 0.24, 0.1, 0.78),
		MeshBuilder.section(1.45, 1.15, 0.98, 0.02, 0.01, 0.92),
	]
	mb.loft(white, cabin, Transform3D.IDENTITY, 3)
	# Windshield behind louvered steel slats.
	var w0 := Vector3(0, 1.15, -0.9)
	var w1 := Vector3(0, 1.62, -0.25)
	var wn := Vector3(0, 0.65, -0.47).normalized()
	var ga := w0.lerp(w1, 0.06) + wn * 0.012
	var gb := w0.lerp(w1, 0.92) + wn * 0.012
	mb.quad(glass, ga + Vector3(-0.9, 0, 0), ga + Vector3(0.9, 0, 0), gb + Vector3(0.74, 0, 0), gb + Vector3(-0.74, 0, 0), wn)
	for k in 6:
		var t := 0.14 + k * 0.14
		var p := w0.lerp(w1, t) + wn * 0.06
		var half := lerpf(0.92, 0.76, t)
		mb.box(armor, Vector3(half * 2.0, 0.025, 0.09), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60.0)), p), 0.006)
	for x: float in [-0.5, 0.0, 0.5]:
		var a := w0.lerp(w1, 0.08) + wn * 0.05 + Vector3(x, 0, 0)
		var b := w0.lerp(w1, 0.96) + wn * 0.05 + Vector3(x * 0.85, 0, 0)
		mb.box(dark, Vector3(0.05, a.distance_to(b), 0.04), MeshBuilder.along((a + b) * 0.5, b - a), 0.01)
	# Rear window: an armor plate with a slit.
	var r0 := Vector3(0, 1.62, 0.85)
	var r1 := Vector3(0, 1.15, 1.45)
	var rn := Vector3(0, 0.6, 0.47).normalized()
	var rc := r0.lerp(r1, 0.5) + rn * 0.02
	mb.box(armor, Vector3(1.55, r0.distance_to(r1) * 0.86, 0.04), MeshBuilder.along(rc, r1 - r0), 0.015)
	mb.box(void_mat, Vector3(1.0, 0.05, 0.02), MeshBuilder.along(rc + rn * 0.022 + (r0 - r1).normalized() * 0.12, r1 - r0), 0.0)
	# Side windows (dark glass) behind welded mesh, B pillar.
	for side: float in [-1.0, 1.0]:
		var n := Vector3(0.929 * side, 0.368, 0)
		for seg: Array in [[-0.62, 0.22], [0.36, 1.12]]:
			var z0: float = seg[0]
			var z1: float = seg[1]
			var a := Vector3(0.955 * side, 1.19, z0)
			var b := Vector3(0.955 * side, 1.19, z1)
			var c := Vector3(0.8 * side, 1.58, z1)
			var d := Vector3(0.8 * side, 1.58, z0)
			mb.quad(glass, a + n * 0.01, b + n * 0.01, c + n * 0.01, d + n * 0.01, n)
			_mesh_grate(mb, dark, a, b, c, d, n, 6, 3, 0.035)
		mb.box(black, Vector3(0.05, 0.44, 0.1), MeshBuilder.along(Vector3(0.88 * side, 1.38, 0.29) + n * 0.02, Vector3(-0.155 * side, 0.39, 0)), 0.01)
		# Mirror and A-pillar spotlight.
		mb.box(black, Vector3(0.2, 0.13, 0.08), MeshBuilder.at(Vector3(1.1 * side, 1.25, -0.78)), 0.02)
		mb.lathe(dark, PackedVector2Array([Vector2(0.0, -0.11), Vector2(0.085, -0.09), Vector2(0.095, 0.08), Vector2(0.0, 0.08)]), MeshBuilder.along(Vector3(1.0 * side, 1.3, -0.88), Vector3.FORWARD), 10)
		mb.cylinder(MatKit.lamp(Color(1, 0.96, 0.88), 2.5), 0.075, 0.02, MeshBuilder.along(Vector3(1.0 * side, 1.3, -0.98), Vector3.FORWARD), 10)

	# Hood: armored gun box with twin barrels and ammo feeds.
	mb.box(black, Vector3(0.9, 0.06, 1.3), MeshBuilder.at(Vector3(0, 1.15, -1.7)), 0.03)
	mb.box(armor, Vector3(0.66, 0.24, 0.78), MeshBuilder.at(Vector3(0, 1.3, -1.6)), 0.05)
	_bolts(mb, bare, Vector3(-0.28, 1.43, -1.92), Vector3(0.28, 1.43, -1.92), 5, Vector3.UP)
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		var p := Vector3(0.17 * side, 1.31, -2.0)
		mb.cylinder(dark, 0.035, 0.85, MeshBuilder.along(p + Vector3(0, 0, -0.42), Vector3.FORWARD), 8)
		mb.cylinder(dark, 0.05, 0.14, MeshBuilder.along(p + Vector3(0, 0, -0.82), Vector3.FORWARD), 8)
		mb.cylinder(dark, 0.055, 0.2, MeshBuilder.along(p + Vector3(0, 0, -0.05), Vector3.FORWARD), 10)
		mb.box(armor, Vector3(0.12, 0.16, 0.36), MeshBuilder.at(Vector3(0.42 * side, 1.26, -1.5)), 0.02)
		muzzles.append(p + Vector3(0, 0, -0.95))
	# Nose: grille, quad lamps, bumper, heavy push bar with rubber pads.
	mb.box(void_mat, Vector3(1.0, 0.2, 0.04), MeshBuilder.at(Vector3(0, 0.88, -2.61)), 0.0)
	for k in 4:
		mb.box(bare, Vector3(1.0, 0.02, 0.04), MeshBuilder.at(Vector3(0, 0.81 + k * 0.05, -2.625)), 0.0)
	for side: float in [-1.0, 1.0]:
		for x: float in [0.62, 0.8]:
			mb.cylinder(dark, 0.08, 0.05, MeshBuilder.along(Vector3(x * side, 0.9, -2.6), Vector3.FORWARD), 12)
			mb.cylinder(MatKit.lamp(Color(1.0, 0.95, 0.85), 3.5), 0.062, 0.02, MeshBuilder.along(Vector3(x * side, 0.9, -2.63), Vector3.FORWARD), 12)
		mb.box(MatKit.lamp(Color(0.95, 0.5, 0.08), 1.4), Vector3(0.14, 0.05, 0.03), MeshBuilder.at(Vector3(0.71 * side, 0.76, -2.62)), 0.0)
	mb.box(dark, Vector3(2.0, 0.18, 0.22), MeshBuilder.at(Vector3(0, 0.52, -2.6)), 0.04)
	for side: float in [-1.0, 1.0]:
		mb.box(dark, Vector3(0.1, 0.66, 0.1), MeshBuilder.at(Vector3(0.36 * side, 0.78, -2.86)), 0.02)
		mb.box(rubber, Vector3(0.14, 0.5, 0.06), MeshBuilder.at(Vector3(0.36 * side, 0.8, -2.93)), 0.02)
		mb.box(dark, Vector3(0.08, 0.08, 0.3), MeshBuilder.at(Vector3(0.36 * side, 0.55, -2.7)), 0.01)
		var g0 := Vector3(0.42 * side, 1.0, -2.86)
		var g1 := Vector3(0.95 * side, 0.95, -2.66)
		mb.cylinder(dark, 0.035, g0.distance_to(g1), MeshBuilder.along((g0 + g1) * 0.5, g1 - g0), 8)
		var g2 := Vector3(0.42 * side, 0.62, -2.86)
		var g3 := Vector3(0.95 * side, 0.62, -2.66)
		mb.cylinder(dark, 0.035, g2.distance_to(g3), MeshBuilder.along((g2 + g3) * 0.5, g3 - g2), 8)
	for y: float in [0.62, 1.0]:
		mb.cylinder(dark, 0.04, 0.84, MeshBuilder.at(Vector3(0, y, -2.87), Vector3(0, 0, 90)), 8)
	mb.box(dark, Vector3(0.22, 0.1, 0.06), MeshBuilder.at(Vector3(0, 0.81, -2.9)), 0.01) # siren speaker
	# Tail: lamps, plate, bumper, pipes, trunk lip.
	for side: float in [-1.0, 1.0]:
		mb.box(dark, Vector3(0.42, 0.13, 0.05), MeshBuilder.at(Vector3(0.68 * side, 0.98, 2.61)), 0.015)
		mb.box(MatKit.lamp(Color(0.8, 0.04, 0.03), 2.2), Vector3(0.36, 0.08, 0.02), MeshBuilder.at(Vector3(0.68 * side, 0.98, 2.64)), 0.01)
		mb.cylinder(soot, 0.05, 0.2, MeshBuilder.along(Vector3(0.55 * side, 0.4, 2.6), Vector3.BACK), 10)
	mb.box(dark, Vector3(2.0, 0.18, 0.2), MeshBuilder.at(Vector3(0, 0.55, 2.6)), 0.04)
	mb.box(MatKit.paint(Color(0.7, 0.68, 0.6), 0.6, 0.3, 0.6, 0.5, 0.5, 34), Vector3(0.48, 0.15, 0.02), MeshBuilder.at(Vector3(0, 0.78, 2.6)), 0.0)
	mb.box(black, Vector3(1.8, 0.04, 0.16), MeshBuilder.at(Vector3(0, 1.17, 2.48)), 0.01)
	mb.cylinder(dark, 0.007, 0.8, MeshBuilder.at(Vector3(-0.62, 1.95, 1.2), Vector3(-10, 0, 0)), 4) # antenna
	# Roof: low light bar base; trunk: insulated mount for the taser coil.
	mb.box(dark, Vector3(1.3, 0.07, 0.26), MeshBuilder.at(Vector3(0, 1.655, -0.05)), 0.02)
	for x: float in [-0.5, 0.5]:
		mb.box(dark, Vector3(0.06, 0.08, 0.3), MeshBuilder.at(Vector3(x, 1.63, -0.05)), 0.0)
	mb.box(armor, Vector3(0.6, 0.06, 0.6), MeshBuilder.at(Vector3(0, 1.15, 2.0)), 0.02)
	_bolts(mb, bare, Vector3(-0.25, 1.19, 1.75), Vector3(0.25, 1.19, 1.75), 4, Vector3.UP)
	mb.commit(m, true, GRIME)

	# Light bar lenses (blinking groups).
	var blinker := Blinker.new()
	blinker.period = 0.28
	m.add_child(blinker)
	for i in 2:
		var color := Color(0.9, 0.04, 0.04) if i == 0 else Color(0.1, 0.3, 1.0)
		var x := -0.33 if i == 0 else 0.33
		var lb := MeshBuilder.new()
		lb.box(MatKit.lamp(color, 0.35), Vector3(0.6, 0.09, 0.22), MeshBuilder.at(Vector3(x, 1.73, -0.05)), 0.03)
		lb.commit(m)
		var holder := Node3D.new()
		m.add_child(holder)
		var bright := MeshBuilder.new()
		bright.box(MatKit.lamp(color, 6.0), Vector3(0.62, 0.1, 0.24), MeshBuilder.at(Vector3(x, 1.73, -0.05)), 0.03)
		bright.commit(holder)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.4
		light.omni_range = 4.5
		light.position = Vector3(x, 2.0, -0.05)
		holder.add_child(light)
		if i == 0:
			blinker.group_a.append(holder)
		else:
			blinker.group_b.append(holder)
	# Taser coil on the trunk: ceramic insulator stack, copper windings, a steel cage, the electrode.
	var coil := MeshBuilder.new()
	var copper := MatKit.paint(Color(0.55, 0.3, 0.16), 0.4, 0.2, 0.35, 0.5, 0.35, 35)
	copper.metallic = 0.85
	var ceramic := MatKit.paint(Color(0.62, 0.6, 0.55), 0.4, 0.0, 0.5, 0.5, 0.35, 36)
	var cbase := Vector3(0, 1.18, 2.0)
	for k in 3:
		coil.cylinder(ceramic, 0.11 - k * 0.012, 0.07, MeshBuilder.at(cbase + Vector3(0, 0.06 + k * 0.08, 0)), 12)
	coil.cylinder(dark, 0.05, 0.62, MeshBuilder.at(cbase + Vector3(0, 0.55, 0)), 8)
	for k in 8:
		coil.torus(copper, 0.085, 0.02, MeshBuilder.at(cbase + Vector3(0, 0.32 + k * 0.045, 0)), 12, 5)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		coil.cylinder(armor, 0.015, 0.62, MeshBuilder.at(cbase + Vector3(cos(a) * 0.2, 0.42, sin(a) * 0.2)), 5)
	coil.torus(armor, 0.2, 0.02, MeshBuilder.at(cbase + Vector3(0, 0.73, 0)), 14, 5)
	coil.torus(armor, 0.2, 0.02, MeshBuilder.at(cbase + Vector3(0, 0.12, 0)), 14, 5)
	coil.sphere(MatKit.lamp(Color(0.55, 0.75, 1.0), 3.5), 0.075, MeshBuilder.at(cbase + Vector3(0, 0.9, 0)), 10, 6)
	coil.commit(m, true, 0.2, 0.0)
	var coil_light := FlickerLight.new()
	coil_light.light_color = Color(0.5, 0.7, 1.0)
	coil_light.base_energy = 1.0
	coil_light.amount = 0.8
	coil_light.speed = 30.0
	coil_light.omni_range = 3.5
	coil_light.position = cbase + Vector3(0, 0.95, 0)
	m.add_child(coil_light)

	_headlight_beam(m, Vector3(0, 0.95, -2.7))
	_ground_shadow(m, Vector2(2.8, 6.2))
	var roof_no := _paint_text(m, "07", Vector3(0, 1.625, 0.45), 0.0, 120, Color(0.05, 0.05, 0.06))
	roof_no.rotation_degrees = Vector3(-90, 0, 0)

	m.set_meta("guns", muzzles)
	m.set_meta("exhaust", [Vector3(-0.55, 0.4, 2.72), Vector3(0.55, 0.4, 2.72)])
	m.set_meta("launcher", cbase + Vector3(0, 0.9, 0))
	m.set_meta("top", Vector3(0, 1.3, -1.6))
	return m


## Five-point badge star on a door (side = +1 right, -1 left).
static func _star(mb: MeshBuilder, mat: Material, center: Vector3, side: float) -> void:
	var out := Vector3(side, 0, 0)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		var r := 0.09 if i % 2 == 0 else 0.038
		pts.append(center + Vector3(0, -sin(a) * r, cos(a) * r))
	for i in 10:
		mb.tri(mat, center + out * 0.004, pts[i], pts[(i + 1) % 10], out)
