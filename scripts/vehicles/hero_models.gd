class_name HeroModels
extends RefCounted
## Detailed models for the preview cars, built with MeshBuilder (parts merged per material) and
## MatKit (generated paint, rust, chrome, rubber). Our own designs, carrying each character's idea:
##   Sweet Tooth: armored ice cream truck, a giant cracked "scoop" mascot head on a spring with flame
##                burners on its hat, gatling guns in the bumper, napalm mortar on the roof.
##   Outlaw:      armored police interceptor, push bar, light bar and a taser coil on the roof.
## Same conventions as VehicleModels: faces -Z, wheels touch y = 0, metadata on the model node.


# ---------------------------------------------------------------- wheels

static var _wheel_cache := {}


## Tire + rim + lug nuts, built once per style and shared by every wheel of that style.
static func _wheel_parts(radius: float, width: float, style: String) -> Array:
	var key := "%s_%.2f_%.2f" % [style, radius, width]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var rubber := MatKit.rubber()
	var rim_mat: Material = MatKit.chrome() if style == "truck" else MatKit.steel(Color(0.12, 0.12, 0.13), 0.0, 1.0)
	var hub_mat: Material = MatKit.steel(Color(0.3, 0.3, 0.31), 0.2, 1.0)
	var mb := MeshBuilder.new()
	var w := width * 0.5
	var r_in := radius * (0.62 if style == "truck" else 0.7)
	var r_out := radius - 0.04
	# Tire cross section, counter-clockwise around the rubber (lathe axis = axle).
	var prof := PackedVector2Array([
		Vector2(r_in, -w + 0.02), Vector2(r_out - 0.08, -w), Vector2(r_out - 0.02, -w + 0.05),
		Vector2(r_out, -w * 0.5), Vector2(r_out, w * 0.5), Vector2(r_out - 0.02, w - 0.05),
		Vector2(r_out - 0.08, w), Vector2(r_in, w - 0.02),
	])
	mb.lathe(rubber, prof, Transform3D.IDENTITY, 28)
	# Tread blocks in two staggered rows.
	var blocks := 22
	for i in blocks:
		for row: float in [-1.0, 1.0]:
			var a := TAU * (i + (0.5 if row > 0.0 else 0.0)) / blocks
			var pos := Vector3(cos(a) * (r_out + 0.015), row * w * 0.42, sin(a) * (r_out + 0.015))
			var xf := Transform3D(Basis(Vector3.UP, -a), pos)
			mb.box(rubber, Vector3(0.05, w * 0.7, 0.09), xf, 0.01)
	# Rim on the outer face (+Y): dish, lip, spokes, hub.
	var face := w - 0.03
	mb.lathe(rim_mat, PackedVector2Array([Vector2(r_in + 0.01, face - 0.02), Vector2(r_in - 0.03, face + 0.01),
		Vector2(r_in * 0.55, face - 0.06), Vector2(r_in * 0.3, face - 0.02), Vector2(0.0, face + 0.02)]), Transform3D.IDENTITY, 24)
	mb.torus(rim_mat, r_in - 0.015, 0.025, MeshBuilder.at(Vector3(0, face, 0)), 24, 6)
	var spokes := 6 if style == "truck" else 5
	for i in spokes:
		var a := TAU * i / spokes
		var mid := Vector3(cos(a) * r_in * 0.6, face - 0.02, sin(a) * r_in * 0.6)
		mb.box(rim_mat, Vector3(r_in * 0.75, 0.05, 0.08 if style == "truck" else 0.12), Transform3D(Basis(Vector3.UP, -a), mid), 0.015)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		mb.cylinder(hub_mat, 0.025, 0.05, MeshBuilder.at(Vector3(cos(a) * r_in * 0.22, face + 0.01, sin(a) * r_in * 0.22)), 6)
	mb.cylinder(hub_mat, r_in * 0.14, 0.06, MeshBuilder.at(Vector3(0, face + 0.01, 0)), 10)
	var holder := Node3D.new()
	var parts: Array = []
	for mi in mb.commit(holder):
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
	for p in _wheel_parts(radius, width, style):
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		holder.add_child(mi)
	m.get_meta("wheels").append(spin)
	if front:
		m.get_meta("steer").append(steer)


static func _new_model(wheel_radius: float) -> Node3D:
	var m := Node3D.new()
	m.name = "Model"
	m.set_meta("wheels", [])
	m.set_meta("steer", [])
	m.set_meta("wheel_radius", wheel_radius)
	return m


## Rotary gatling: housing, six barrels on a spinner node, muzzle ring. Returns the muzzle point.
static func _gatling(m: Node3D, mb: MeshBuilder, pos: Vector3, steel: Material, dark: Material, spinners: Array) -> Vector3:
	mb.box(steel, Vector3(0.3, 0.28, 0.5), MeshBuilder.at(pos + Vector3(0, 0, 0.1)), 0.05)
	var spinner := Node3D.new()
	spinner.position = pos + Vector3(0, 0, -0.15)
	m.add_child(spinner)
	var gb := MeshBuilder.new()
	for i in 6:
		var a := TAU * i / 6.0
		gb.cylinder(dark, 0.028, 0.8, MeshBuilder.along(Vector3(cos(a) * 0.07, sin(a) * 0.07, -0.4), Vector3.FORWARD), 6)
	gb.torus(steel, 0.08, 0.025, MeshBuilder.along(Vector3(0, 0, -0.62), Vector3.FORWARD), 12, 5)
	gb.torus(steel, 0.08, 0.025, MeshBuilder.along(Vector3(0, 0, -0.2), Vector3.FORWARD), 12, 5)
	gb.commit(spinner)
	spinners.append(spinner)
	return pos + Vector3(0, 0, -1.0)


static func _rivets(mb: MeshBuilder, mat: Material, a: Vector3, b: Vector3, count: int, outward: Vector3) -> void:
	for i in count:
		var p := a.lerp(b, float(i) / maxf(1.0, count - 1))
		mb.sphere(mat, 0.022, MeshBuilder.at(p + outward * 0.005), 6, 3)


static func _label(m: Node3D, text: String, pos: Vector3, yaw: float, size: int, color: Color, outline := Color(0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = outline
	l.position = pos
	l.rotation_degrees.y = yaw
	l.double_sided = false
	l.shaded = true
	m.add_child(l)
	return l


# ---------------------------------------------------------------- Sweet Tooth

static func sweet_tooth() -> Node3D:
	var m := _new_model(0.56)
	var cream := MatKit.paint(Color(0.9, 0.86, 0.76), 0.45, 0.35, 0.45, 2.5, 0.42, 11)
	var pink := MatKit.paint(Color(0.86, 0.25, 0.52), 0.4, 0.15, 0.3, 2.0, 0.38, 12)
	var teal := MatKit.paint(Color(0.18, 0.55, 0.58), 0.45, 0.25, 0.35, 2.0, 0.4, 13)
	var steel := MatKit.steel(Color(0.2, 0.2, 0.21), 0.4)
	var dark := MatKit.steel(Color(0.08, 0.08, 0.085), 0.1, 1.0)
	var chrome := MatKit.chrome()
	var glass := MatKit.glass()
	var black := MatKit.flat(Color(0.02, 0.02, 0.02), 0.9)
	var mb := MeshBuilder.new()

	for side: float in [-1.0, 1.0]:
		_wheel(m, Vector3(1.1 * side, 0.56, -1.95), 0.56, 0.42, true, "truck")
		_wheel(m, Vector3(1.1 * side, 0.56, 1.85), 0.56, 0.5, false, "truck")

	# Chassis rails, cross members, fuel tank.
	for side: float in [-1.0, 1.0]:
		mb.box(dark, Vector3(0.16, 0.22, 5.5), MeshBuilder.at(Vector3(0.72 * side, 0.6, 0)), 0.03)
	for z: float in [-2.4, -0.9, 0.6, 2.3]:
		mb.box(dark, Vector3(1.5, 0.12, 0.14), MeshBuilder.at(Vector3(0, 0.6, z)), 0.02)
	mb.cylinder(steel, 0.22, 0.9, MeshBuilder.at(Vector3(-0.95, 0.62, 0.0), Vector3(90, 0, 0)), 14)

	# Cab: short hood rising into a steep windshield and the roof.
	var cab := [
		MeshBuilder.section(-2.95, 1.0, 1.02, 0.38, 0.16),
		MeshBuilder.section(-2.6, 1.03, 1.1, 0.43, 0.17),
		MeshBuilder.section(-2.12, 1.08, 1.12, 0.48, 0.18),
		MeshBuilder.section(-1.8, 1.56, 1.13, 0.96, 0.2),
		MeshBuilder.section(-1.02, 1.56, 1.13, 0.96, 0.2),
	]
	mb.loft(cream, cab, Transform3D.IDENTITY, 3)
	# Windshield on the slope between z -2.12 (top 1.56) and z -1.8 (top 2.52).
	var slope := Vector3(0, 2.46 - 1.62, -1.82 + 2.08).normalized()
	var wn := Vector3(0, -slope.z, slope.y) * -1.0
	if wn.z > 0.0:
		wn = -wn
	var w0 := Vector3(0, 1.64, -2.08) + wn * 0.025
	var w1 := Vector3(0, 2.42, -1.84) + wn * 0.025
	mb.quad(glass, w0 + Vector3(-0.95, 0, 0), w0 + Vector3(0.95, 0, 0), w1 + Vector3(0.9, 0, 0), w1 + Vector3(-0.9, 0, 0), wn)
	mb.box(chrome, Vector3(0.05, 0.05, 0.85), Transform3D(Basis(Vector3.RIGHT, atan2(slope.z, slope.y)), (w0 + w1) * 0.5 + wn * 0.02), 0.0) # wiper post
	# Side windows with protective bars.
	for side: float in [-1.0, 1.0]:
		var x := 1.131 * side
		mb.quad(glass, Vector3(x, 1.72, -1.72), Vector3(x, 1.72, -1.15), Vector3(x, 2.36, -1.15), Vector3(x, 2.36, -1.72), Vector3(side, 0, 0))
		for k in 4:
			mb.cylinder(steel, 0.02, 0.66, MeshBuilder.at(Vector3(x + 0.04 * side, 2.04, -1.65 + k * 0.16)), 6)
		# Door seam, handle, mirror.
		mb.box(black, Vector3(0.01, 1.0, 0.02), MeshBuilder.at(Vector3(1.132 * side, 1.25, -1.08)), 0.0)
		mb.box(chrome, Vector3(0.04, 0.05, 0.18), MeshBuilder.at(Vector3(1.15 * side, 1.5, -1.25)), 0.01)
		mb.box(steel, Vector3(0.35, 0.04, 0.04), MeshBuilder.at(Vector3(1.28 * side, 2.0, -1.78)), 0.0)
		mb.box(chrome, Vector3(0.06, 0.32, 0.2), MeshBuilder.at(Vector3(1.47 * side, 2.02, -1.78)), 0.02)
		# Cab stripe.
		mb.box(pink, Vector3(0.02, 0.16, 1.7), MeshBuilder.at(Vector3(1.135 * side, 1.15, -1.95)), 0.0)

	# Ice cream box.
	var box_c := Vector3(0, 1.66, 0.95)
	mb.box(cream, Vector3(2.5, 2.12, 4.0), MeshBuilder.at(box_c), 0.14)
	mb.box(pink, Vector3(2.53, 0.2, 4.03), MeshBuilder.at(Vector3(0, 1.08, 0.95)), 0.12)
	mb.box(pink, Vector3(2.53, 0.1, 4.03), MeshBuilder.at(Vector3(0, 2.5, 0.95)), 0.12)
	mb.box(teal, Vector3(2.54, 0.26, 4.04), MeshBuilder.at(Vector3(0, 0.74, 0.95)), 0.1)
	# Armor plates with rivets along the lower box.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var z := -0.55 + k * 1.3
			mb.box(steel, Vector3(0.05, 0.5, 1.2), MeshBuilder.at(Vector3(1.275 * side, 0.82, z)), 0.02)
			_rivets(mb, chrome, Vector3(1.305 * side, 1.02, z - 0.52), Vector3(1.305 * side, 1.02, z + 0.52), 6, Vector3(side, 0, 0))
			_rivets(mb, chrome, Vector3(1.305 * side, 0.62, z - 0.52), Vector3(1.305 * side, 0.62, z + 0.52), 6, Vector3(side, 0, 0))
	# Serving window (right side): dark hatch, half-open glass, chrome frame, striped awning, menu.
	mb.box(black, Vector3(0.04, 0.72, 1.6), MeshBuilder.at(Vector3(1.25, 1.78, 0.6)), 0.0)
	mb.quad(glass, Vector3(1.275, 1.44, 0.6), Vector3(1.275, 1.44, 1.38), Vector3(1.275, 2.12, 1.38), Vector3(1.275, 2.12, 0.6), Vector3(1, 0, 0))
	for y: float in [1.4, 2.16]:
		mb.box(chrome, Vector3(0.06, 0.06, 1.7), MeshBuilder.at(Vector3(1.27, y, 0.6)), 0.01)
	for z: float in [-0.22, 1.42]:
		mb.box(chrome, Vector3(0.06, 0.82, 0.06), MeshBuilder.at(Vector3(1.27, 1.78, z)), 0.01)
	mb.box(chrome, Vector3(0.3, 0.05, 1.7), MeshBuilder.at(Vector3(1.38, 1.38, 0.6)), 0.01) # counter
	for i in 6:
		var stripe: Material = pink if i % 2 == 0 else cream
		mb.box(stripe, Vector3(0.7, 0.04, 0.3), Transform3D(Basis(Vector3.BACK, deg_to_rad(-22.0)), Vector3(1.55, 2.33, -0.15 + i * 0.3)), 0.0)
	for i in 6:
		var a := Vector3(1.88, 2.18, -0.3 + i * 0.3)
		mb.tri(pink if i % 2 == 0 else cream, a, a + Vector3(0, 0, 0.3), a + Vector3(0, -0.14, 0.15), Vector3(1, 0, 0))
	mb.box(dark, Vector3(0.04, 0.6, 0.9), MeshBuilder.at(Vector3(1.255, 1.85, 1.95)), 0.02) # menu board
	var menu_cols := [Color(1.0, 0.5, 0.7), Color(0.6, 0.9, 1.0), Color(1.0, 0.85, 0.4), Color(0.7, 1.0, 0.6)]
	for i in 4:
		var c: Color = menu_cols[i]
		mb.box(MatKit.lamp(c, 1.2), Vector3(0.02, 0.18, 0.32), MeshBuilder.at(Vector3(1.28, 1.98 - (i / 2) * 0.24, 1.75 + (i % 2) * 0.4)), 0.0)
	# Left side: folded stop arm and a big ice cream cone sign.
	mb.cylinder(chrome, 0.03, 0.4, MeshBuilder.at(Vector3(-1.3, 1.75, -0.6), Vector3(0, 0, 90)), 6)
	mb.cylinder(MatKit.paint(Color(0.75, 0.08, 0.08), 0.5, 0.2, 0.3), 0.26, 0.03, MeshBuilder.at(Vector3(-1.29, 1.75, -0.35), Vector3(0, 0, 90)), 8)
	var cone := MatKit.paint(Color(0.82, 0.58, 0.28), 0.3, 0.0, 0.3, 0.6, 0.6, 14)
	mb.lathe(cone, PackedVector2Array([Vector2(0.0, -0.75), Vector2(0.32, 0.0), Vector2(0.0, 0.0)]), MeshBuilder.at(Vector3(-1.45, 1.9, 0.9)), 10)
	mb.sphere(pink, 0.33, MeshBuilder.at(Vector3(-1.45, 2.1, 0.9)), 12, 7)
	mb.sphere(MatKit.paint(Color(0.96, 0.92, 0.8), 0.3, 0.1, 0.3), 0.27, MeshBuilder.at(Vector3(-1.45, 2.42, 0.9)), 12, 7)
	mb.box(steel, Vector3(0.2, 0.08, 0.08), MeshBuilder.at(Vector3(-1.33, 1.9, 0.9)), 0.0)
	# Rear: doors, ladder, lights, plate.
	mb.box(black, Vector3(0.02, 1.8, 0.01), MeshBuilder.at(Vector3(0, 1.65, 2.955)), 0.0)
	for side: float in [-1.0, 1.0]:
		mb.box(chrome, Vector3(0.05, 0.2, 0.06), MeshBuilder.at(Vector3(0.18 * side, 1.6, 2.98)), 0.01)
		mb.box(MatKit.lamp(Color(0.95, 0.05, 0.05), 2.5), Vector3(0.22, 0.32, 0.05), MeshBuilder.at(Vector3(1.0 * side, 0.95, 2.97)), 0.02)
		mb.box(MatKit.lamp(Color(1.0, 0.55, 0.1), 2.0), Vector3(0.22, 0.12, 0.05), MeshBuilder.at(Vector3(1.0 * side, 0.72, 2.97)), 0.02)
	for side: float in [-1.0, 1.0]:
		mb.cylinder(steel, 0.025, 1.9, MeshBuilder.at(Vector3(-0.9 + 0.35 * side, 1.65, 3.02)), 6)
	for k in 6:
		mb.cylinder(steel, 0.02, 0.36, MeshBuilder.at(Vector3(-0.9, 0.85 + k * 0.32, 3.02), Vector3(0, 0, 90)), 6)
	mb.box(MatKit.flat(Color(0.9, 0.85, 0.3), 0.5), Vector3(0.5, 0.25, 0.02), MeshBuilder.at(Vector3(0, 0.78, 3.13)), 0.0)
	mb.box(dark, Vector3(2.4, 0.3, 0.25), MeshBuilder.at(Vector3(0, 0.62, 3.0)), 0.05) # rear bumper

	# Front: plow with spikes, grille, lamps.
	mb.box(steel, Vector3(2.55, 0.38, 0.28), MeshBuilder.at(Vector3(0, 0.7, -3.0)), 0.06)
	for side: float in [-1.0, 1.0]:
		mb.box(steel, Vector3(0.12, 0.7, 0.12), MeshBuilder.at(Vector3(0.75 * side, 1.0, -3.05)), 0.03)
	mb.box(steel, Vector3(1.8, 0.1, 0.1), MeshBuilder.at(Vector3(0, 1.32, -3.05)), 0.03)
	for x: float in [-1.05, -0.62, -0.2, 0.2, 0.62, 1.05]:
		mb.lathe(chrome, PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.0, 0.42)]), MeshBuilder.along(Vector3(x, 0.72, -3.12), Vector3.FORWARD), 8, false)
	mb.box(dark, Vector3(1.3, 0.5, 0.05), MeshBuilder.at(Vector3(0, 1.08, -2.955)), 0.0)
	for k in 5:
		mb.box(chrome, Vector3(1.32, 0.04, 0.05), MeshBuilder.at(Vector3(0, 0.88 + k * 0.1, -2.97)), 0.01)
	for side: float in [-1.0, 1.0]:
		mb.torus(chrome, 0.16, 0.035, MeshBuilder.along(Vector3(0.82 * side, 1.12, -2.97), Vector3.FORWARD), 14, 5)
		mb.cylinder(MatKit.lamp(Color(1.0, 0.95, 0.82), 4.0), 0.15, 0.04, MeshBuilder.along(Vector3(0.82 * side, 1.12, -2.97), Vector3.FORWARD), 14)
		mb.box(MatKit.lamp(Color(1.0, 0.55, 0.1), 2.0), Vector3(0.18, 0.08, 0.04), MeshBuilder.at(Vector3(0.82 * side, 0.9, -2.96)), 0.01)
	var spinners: Array = []
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		muzzles.append(_gatling(m, mb, Vector3(1.0 * side, 0.92, -2.95), steel, dark, spinners))

	# Exhaust stacks behind the cab.
	var exhausts: Array = []
	for side: float in [-1.0, 1.0]:
		var base := Vector3(1.18 * side, 1.0, -0.9)
		mb.cylinder(chrome, 0.09, 2.4, MeshBuilder.at(base + Vector3(0, 1.2, 0)), 10)
		mb.cylinder(chrome, 0.11, 0.2, MeshBuilder.at(base + Vector3(0, 2.45, 0.02), Vector3(-25, 0, 0)), 10)
		mb.box(steel, Vector3(0.24, 0.1, 0.1), MeshBuilder.at(base + Vector3(-0.08 * side, 1.6, 0)), 0.02)
		exhausts.append(base + Vector3(0, 2.6, 0.08))

	# Roof: speaker horns, condenser, napalm mortar.
	for side: float in [-1.0, 1.0]:
		mb.lathe(chrome, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.22, 0.45)]), MeshBuilder.along(Vector3(0.45 * side, 2.92, -0.6), Vector3(0, 0.1, -1)), 12, false)
	mb.box(steel, Vector3(1.6, 0.4, 0.9), MeshBuilder.at(Vector3(0, 2.92, 2.35)), 0.05)
	for k in 9:
		mb.box(dark, Vector3(1.5, 0.3, 0.02), MeshBuilder.at(Vector3(0, 2.94, 1.95 + k * 0.1)), 0.0)
	var launcher := Vector3(0, 3.4, 1.55)
	mb.box(steel, Vector3(0.6, 0.18, 0.6), MeshBuilder.at(Vector3(0, 2.8, 1.6)), 0.04)
	mb.cylinder(dark, 0.17, 0.9, MeshBuilder.along(Vector3(0, 3.1, 1.6), Vector3(0, 1, -0.6)), 12)
	mb.torus(steel, 0.17, 0.03, MeshBuilder.along(launcher, Vector3(0, 1, -0.6)), 12, 5)
	for side: float in [-1.0, 1.0]:
		mb.cylinder(chrome, 0.03, 4.0, MeshBuilder.at(Vector3(1.1 * side, 2.78, 0.95), Vector3(90, 0, 0)), 6)

	mb.commit(m)
	_scoop_head(m, Vector3(0, 2.72, 0.25))
	_headlight_beam(m, Vector3(0, 1.12, -3.0))
	_label(m, "ICE COLD", Vector3(-1.282, 2.2, 2.2), -90.0, 56, Color(0.95, 0.3, 0.6), Color(0.15, 0.05, 0.08))
	_label(m, "ICE COLD", Vector3(1.282, 2.62, 1.7), 90.0, 48, Color(0.95, 0.3, 0.6), Color(0.15, 0.05, 0.08))

	m.set_meta("guns", muzzles)
	m.set_meta("gun_spinners", spinners)
	m.set_meta("exhaust", exhausts)
	m.set_meta("exhaust_dir", Vector3.UP)
	m.set_meta("launcher", launcher)
	m.set_meta("top", Vector3(0, 3.0, 1.2))
	return m


## Giant fiberglass mascot on a spring: "the Scoop", a strawberry scoop with a carved, wicked face,
## sitting in a waffle cone. Chocolate sauce and sprinkles on top, a cherry, melt running down the cone.
static func _scoop_head(m: Node3D, base: Vector3) -> void:
	var spring := Node3D.new()
	spring.name = "Bobble"
	spring.position = base
	m.add_child(spring)
	m.set_meta("bobble", spring)
	var steel := MatKit.steel(Color(0.25, 0.25, 0.26), 0.4)
	var berry := MatKit.paint(Color(0.93, 0.42, 0.6), 0.35, 0.0, 0.35, 1.0, 0.32, 22)
	var waffle := MatKit.paint(Color(0.84, 0.58, 0.28), 0.3, 0.0, 0.35, 0.4, 0.7, 23)
	var waffle_dark := MatKit.flat(Color(0.5, 0.3, 0.12), 0.8)
	var choc := MatKit.paint(Color(0.2, 0.09, 0.04), 0.1, 0.0, 0.1, 0.8, 0.18, 26)
	var red := MatKit.paint(Color(0.8, 0.05, 0.08), 0.2, 0.0, 0.1, 0.8, 0.15, 24)
	var socket := MatKit.flat(Color(0.03, 0.01, 0.01), 0.9)
	var eye := MatKit.lamp(Color(0.85, 1.0, 0.25), 5.0)
	# Spring coil and base plate (static on the roof).
	var sb := MeshBuilder.new()
	sb.cylinder(steel, 0.45, 0.12, MeshBuilder.at(base + Vector3(0, 0.06, 0)), 14)
	for k in 5:
		sb.torus(steel, 0.18, 0.035, MeshBuilder.at(base + Vector3(0, 0.18 + k * 0.08, 0)), 12, 5)
	sb.commit(m)
	var mb := MeshBuilder.new()
	# Waffle cone with a criss-cross grid and a rolled rim.
	var y0 := 0.44
	var y1 := 1.0
	var cone_r := func(y: float) -> float: return 0.06 + (y - y0) / (y1 - y0) * 0.56
	mb.lathe(waffle, PackedVector2Array([Vector2(0.0, y0 - 0.04), Vector2(0.06, y0), Vector2(0.62, y1), Vector2(0.0, y1)]), Transform3D.IDENTITY, 18, false)
	mb.torus(waffle, 0.62, 0.05, MeshBuilder.at(Vector3(0, y1, 0)), 18, 6)
	for i in 12:
		for dir: float in [-1.0, 1.0]:
			var a0 := TAU * i / 12.0
			var a1 := a0 + 0.9 * dir
			var lo := Vector3(cos(a0) * 0.1, y0 + 0.07, sin(a0) * 0.1) * Vector3(1.02, 1, 1.02)
			var hi := Vector3(cos(a1) * 0.63, y1 - 0.02, sin(a1) * 0.63)
			mb.cylinder(waffle_dark, 0.014, lo.distance_to(hi), MeshBuilder.along((lo + hi) * 0.5, hi - lo), 4, -1.0, false)
	# Scoop.
	var c := Vector3(0, 1.42, 0)
	var r := 0.66
	mb.sphere(berry, r, MeshBuilder.at(c), 20, 12)
	# Melt bulging over the rim and running down the cone.
	mb.torus(berry, 0.55, 0.1, MeshBuilder.at(Vector3(0, y1 + 0.05, 0)), 18, 6)
	for i in 9:
		var a := TAU * i / 9.0 + 0.3
		var length := 0.12 + fposmod(i * 0.37, 1.0) * 0.22
		var y := y1 - length * 0.6
		var rr: float = cone_r.call(y) + 0.03
		mb.sphere(berry, 0.07, MeshBuilder.at(Vector3(cos(a) * rr, y, sin(a) * rr), Vector3.ZERO, Vector3(1.0, length / 0.07 * 0.6, 1.0)), 8, 5)
	# Chocolate sauce cap with drips, sprinkles and a cherry.
	var cap := PackedVector2Array()
	for i in 7:
		var e := deg_to_rad(38.0 + 52.0 * i / 6.0)
		cap.append(Vector2(cos(e), sin(e)) * (r + 0.015))
	cap[6].x = 0.0
	mb.lathe(choc, cap, MeshBuilder.at(c), 20, true)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var e := deg_to_rad(34.0)
		var p := c + Vector3(cos(a) * cos(e), sin(e) - 0.06 * float(i % 3), sin(a) * cos(e)) * (r + 0.01)
		mb.sphere(choc, 0.075, MeshBuilder.at(p, Vector3.ZERO, Vector3(1.0, 1.8 + 0.6 * float(i % 3), 1.0)), 8, 5)
	var sprinkle_mats := [MatKit.flat(Color(1.0, 0.85, 0.2), 0.5), MatKit.flat(Color(0.3, 0.85, 0.85), 0.5), MatKit.flat(Color(0.95, 0.95, 0.92), 0.5)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 30:
		var a := rng.randf() * TAU
		var e := deg_to_rad(rng.randf_range(46.0, 84.0))
		var n := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
		var xf := MeshBuilder.along(c + n * (r + 0.03), n)
		xf.basis = xf.basis * Basis(Vector3.UP, rng.randf() * TAU)
		mb.box(sprinkle_mats[i % 3], Vector3(0.11, 0.03, 0.03), xf, 0.008)
	mb.sphere(red, 0.13, MeshBuilder.at(c + Vector3(0.06, r + 0.1, 0.02)), 12, 8)
	mb.cylinder(MatKit.flat(Color(0.25, 0.4, 0.1), 0.8), 0.014, 0.26, MeshBuilder.at(c + Vector3(0.1, r + 0.32, 0.02), Vector3(0, 0, -22)), 5)
	# The face, carved into the front of the scoop (front = -Z).
	var surf := func(x: float, y: float) -> Vector3: return c + Vector3(x, y, -sqrt(maxf(r * r - x * x - y * y, 0.01)))
	for side: float in [-1.0, 1.0]:
		var e: Vector3 = surf.call(0.24 * side, 0.1)
		var yaw := -rad_to_deg(asin(0.24 * side / r))
		mb.sphere(socket, 0.15, MeshBuilder.at(e + Vector3(0, 0, 0.03), Vector3(0, yaw, 14.0 * side), Vector3(1.15, 0.8, 0.5)), 12, 6)
		mb.sphere(eye, 0.05, MeshBuilder.at(e + Vector3(0.02 * side, -0.01, -0.035)), 8, 5)
		var b: Vector3 = surf.call(0.24 * side, 0.29)
		mb.box(choc, Vector3(0.34, 0.07, 0.09), MeshBuilder.at(b, Vector3(0, yaw, 22.0 * side)), 0.02)
	# Grin: a chocolate gash with uneven wafer teeth, ends turned up.
	for i in 11:
		var t := (i - 5) / 5.0
		var x := t * 0.44
		var y := -0.2 + t * t * 0.12
		var p: Vector3 = surf.call(x, y)
		var yaw := -rad_to_deg(asin(clampf(x / r, -1.0, 1.0)))
		mb.box(socket, Vector3(0.1, 0.17 - absf(t) * 0.06, 0.08), MeshBuilder.at(p + Vector3(0, 0, 0.02), Vector3(0, yaw, -t * 18.0)), 0.01)
		var tooth := 0.06 + 0.04 * float((i * 7) % 3) / 2.0
		mb.box(waffle, Vector3(0.07, tooth, 0.05), MeshBuilder.at(p + Vector3(0, 0.07 - absf(t) * 0.02 - tooth * 0.5, -0.02), Vector3(0, yaw, -t * 18.0)), 0.01)
	mb.commit(spring)


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


# ---------------------------------------------------------------- Outlaw

static func outlaw() -> Node3D:
	var m := _new_model(0.48)
	var black := MatKit.paint(Color(0.05, 0.05, 0.06), 0.35, 0.1, 0.35, 2.0, 0.28, 31)
	var white := MatKit.paint(Color(0.9, 0.9, 0.88), 0.35, 0.1, 0.35, 2.0, 0.3, 32)
	var steel := MatKit.steel(Color(0.18, 0.18, 0.19), 0.25)
	var dark := MatKit.steel(Color(0.07, 0.07, 0.075), 0.05, 1.0)
	var chrome := MatKit.chrome()
	var glass := MatKit.glass(Color(0.05, 0.07, 0.1), 0.85)
	var rubber := MatKit.rubber()
	var gold := MatKit.chrome(Color(0.9, 0.7, 0.25))
	var mb := MeshBuilder.new()

	for side: float in [-1.0, 1.0]:
		_wheel(m, Vector3(1.0 * side, 0.48, -1.55), 0.48, 0.36, true, "sport")
		_wheel(m, Vector3(1.0 * side, 0.48, 1.5), 0.48, 0.4, false, "sport")

	# Lower body: long hood, trunk, fender bulges.
	var body := [
		MeshBuilder.section(-2.45, 0.78, 0.95, 0.24, 0.14),
		MeshBuilder.section(-2.28, 0.82, 1.04, 0.31, 0.16),
		MeshBuilder.section(-1.6, 0.88, 1.08, 0.36, 0.18),
		MeshBuilder.section(-0.75, 0.9, 1.08, 0.38, 0.18),
		MeshBuilder.section(1.3, 0.92, 1.08, 0.4, 0.18),
		MeshBuilder.section(2.2, 0.9, 1.04, 0.36, 0.17),
		MeshBuilder.section(2.45, 0.86, 0.96, 0.28, 0.14),
	]
	mb.loft(black, body, Transform3D.IDENTITY, 3)
	# Cabin (white roof), windows on its slopes.
	var cabin := [
		MeshBuilder.section(-0.78, 1.3, 1.0, 0.03, 0.02, 0.92),
		MeshBuilder.section(-0.22, 1.55, 0.98, 0.28, 0.12, 0.8),
		MeshBuilder.section(0.78, 1.56, 0.98, 0.28, 0.12, 0.8),
		MeshBuilder.section(1.36, 1.33, 1.0, 0.04, 0.02, 0.9),
	]
	mb.loft(white, cabin, Transform3D.IDENTITY, 3)
	var ws_n := Vector3(0, 0.56, -0.25).normalized()
	ws_n = Vector3(0, 0.75, -0.66).normalized()
	mb.quad(glass, Vector3(-0.86, 1.35, -0.74), Vector3(0.86, 1.35, -0.74), Vector3(0.74, 1.79, -0.27), Vector3(-0.74, 1.79, -0.27), ws_n)
	mb.quad(glass, Vector3(-0.78, 1.79, 0.82), Vector3(0.78, 1.79, 0.82), Vector3(0.86, 1.38, 1.3), Vector3(-0.86, 1.38, 1.3), Vector3(0, 0.75, 0.66))
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side, 0.18, 0).normalized()
		for seg: Array in [[-0.12, 0.3], [0.38, 0.74]]:
			var z0: float = seg[0]
			var z1: float = seg[1]
			mb.quad(glass, Vector3(0.99 * side, 1.35, z0), Vector3(0.99 * side, 1.35, z1), Vector3(0.83 * side, 1.79, z1), Vector3(0.83 * side, 1.79, z0), n)
			# Window guard bars.
			for k in 3:
				var z := lerpf(z0, z1, (k + 1) / 4.0)
				var a := Vector3(1.0 * side, 1.36, z)
				var b := Vector3(0.85 * side, 1.78, z)
				mb.cylinder(steel, 0.014, a.distance_to(b), MeshBuilder.along((a + b) * 0.5 + n * 0.02, b - a), 5)
		# White doors with POLICE text, badge, handles, seams.
		mb.box(white, Vector3(0.02, 0.62, 1.7), MeshBuilder.at(Vector3(1.083 * side, 0.95, 0.1)), 0.0)
		mb.box(MatKit.flat(Color(0.02, 0.02, 0.02)), Vector3(0.022, 0.62, 0.015), MeshBuilder.at(Vector3(1.084 * side, 0.95, 0.35)), 0.0)
		mb.box(chrome, Vector3(0.04, 0.04, 0.14), MeshBuilder.at(Vector3(1.1 * side, 1.15, -0.25)), 0.01)
		mb.box(chrome, Vector3(0.04, 0.04, 0.14), MeshBuilder.at(Vector3(1.1 * side, 1.15, 0.6)), 0.01)
		_star(mb, gold, Vector3(1.095 * side, 1.0, -0.45), side)
		# Armored rocker panel and fender guards.
		mb.box(steel, Vector3(0.08, 0.16, 2.3), MeshBuilder.at(Vector3(1.09 * side, 0.58, 0.0)), 0.03)
		_rivets(mb, chrome, Vector3(1.135 * side, 0.58, -1.05), Vector3(1.135 * side, 0.58, 1.05), 10, Vector3(side, 0, 0))
		for z: float in [-1.55, 1.5]:
			mb.box(steel, Vector3(0.12, 0.08, 1.2), MeshBuilder.at(Vector3(1.08 * side, 1.02, z)), 0.03)
		# Mirror, A-pillar spotlight.
		mb.box(black, Vector3(0.18, 0.12, 0.08), MeshBuilder.at(Vector3(1.1 * side, 1.4, -0.6)), 0.02)
		mb.lathe(chrome, PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.09, -0.08), Vector2(0.1, 0.1), Vector2(0.0, 0.1)]), MeshBuilder.along(Vector3(1.02 * side, 1.62, -0.7), Vector3.FORWARD), 10)
		mb.cylinder(MatKit.lamp(Color(1, 0.97, 0.9), 3.0), 0.08, 0.02, MeshBuilder.along(Vector3(1.02 * side, 1.62, -0.81), Vector3.FORWARD), 10)
	# Hood bulge and the two hood guns.
	mb.box(black, Vector3(0.8, 0.08, 1.2), MeshBuilder.at(Vector3(0, 1.27, -1.5)), 0.04)
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		var p := Vector3(0.62 * side, 1.34, -1.35)
		mb.box(steel, Vector3(0.22, 0.2, 0.6), MeshBuilder.at(p), 0.04)
		for k: float in [-1.0, 1.0]:
			mb.cylinder(dark, 0.03, 0.7, MeshBuilder.along(p + Vector3(0.05 * k, 0.02, -0.55), Vector3.FORWARD), 6)
		mb.box(steel, Vector3(0.16, 0.06, 0.06), MeshBuilder.at(p + Vector3(0, 0.02, -0.9)), 0.01)
		muzzles.append(p + Vector3(0, 0.02, -0.95))
	# Push bar with rubber pads.
	for side: float in [-1.0, 1.0]:
		mb.cylinder(steel, 0.05, 0.7, MeshBuilder.at(Vector3(0.48 * side, 0.85, -2.55)), 8)
		mb.box(rubber, Vector3(0.14, 0.5, 0.08), MeshBuilder.at(Vector3(0.48 * side, 0.85, -2.62)), 0.03)
	for y: float in [0.62, 1.12]:
		mb.cylinder(steel, 0.045, 1.4, MeshBuilder.at(Vector3(0, y, -2.56), Vector3(0, 0, 90)), 8)
	# Grille, lamps, bumper, plate.
	mb.box(dark, Vector3(1.0, 0.24, 0.04), MeshBuilder.at(Vector3(0, 0.88, -2.44)), 0.0)
	for k in 4:
		mb.box(chrome, Vector3(1.02, 0.025, 0.04), MeshBuilder.at(Vector3(0, 0.79 + k * 0.06, -2.45)), 0.0)
	for side: float in [-1.0, 1.0]:
		mb.box(MatKit.lamp(Color(1.0, 0.97, 0.88), 4.0), Vector3(0.36, 0.12, 0.04), MeshBuilder.at(Vector3(0.72 * side, 0.9, -2.4), Vector3(0, 12.0 * side, 0)), 0.02)
		mb.box(MatKit.lamp(Color(1.0, 0.5, 0.1), 2.0), Vector3(0.12, 0.06, 0.04), MeshBuilder.at(Vector3(0.82 * side, 0.78, -2.38)), 0.01)
		mb.box(MatKit.lamp(Color(0.95, 0.05, 0.05), 2.5), Vector3(0.38, 0.12, 0.04), MeshBuilder.at(Vector3(0.7 * side, 1.0, 2.46)), 0.02)
		mb.cylinder(chrome, 0.045, 0.16, MeshBuilder.along(Vector3(0.55 * side, 0.52, 2.5), Vector3.BACK), 8)
	mb.box(dark, Vector3(2.0, 0.18, 0.18), MeshBuilder.at(Vector3(0, 0.58, -2.42)), 0.05)
	mb.box(dark, Vector3(2.0, 0.18, 0.16), MeshBuilder.at(Vector3(0, 0.6, 2.44)), 0.05)
	mb.box(MatKit.flat(Color(0.95, 0.95, 0.9), 0.5), Vector3(0.48, 0.15, 0.02), MeshBuilder.at(Vector3(0, 0.82, 2.47)), 0.0)
	mb.box(black, Vector3(1.9, 0.05, 0.3), MeshBuilder.at(Vector3(0, 1.4, 2.3)), 0.02) # spoiler
	for side: float in [-1.0, 1.0]:
		mb.box(black, Vector3(0.06, 0.12, 0.12), MeshBuilder.at(Vector3(0.8 * side, 1.34, 2.3)), 0.01)
	mb.cylinder(dark, 0.008, 0.8, MeshBuilder.at(Vector3(-0.6, 1.95, 1.1), Vector3(-10, 0, 0)), 4) # antenna
	# Light bar base and the taser coil mount.
	mb.box(dark, Vector3(1.5, 0.1, 0.32), MeshBuilder.at(Vector3(0, 1.88, -0.05)), 0.03)
	mb.box(steel, Vector3(0.5, 0.08, 0.5), MeshBuilder.at(Vector3(0, 1.88, 0.6)), 0.03)
	mb.commit(m)

	# Light bar lenses (blinking groups).
	var blinker := Blinker.new()
	blinker.period = 0.28
	m.add_child(blinker)
	for i in 2:
		var color := Color(1.0, 0.06, 0.06) if i == 0 else Color(0.15, 0.35, 1.0)
		var x := -0.42 if i == 0 else 0.42
		var lb := MeshBuilder.new()
		lb.box(MatKit.lamp(color, 0.5), Vector3(0.62, 0.15, 0.28), MeshBuilder.at(Vector3(x, 2.0, -0.05)), 0.04)
		lb.commit(m)
		var bright := MeshBuilder.new()
		var holder := Node3D.new()
		m.add_child(holder)
		bright.box(MatKit.lamp(color, 7.0), Vector3(0.64, 0.16, 0.3), MeshBuilder.at(Vector3(x, 2.0, -0.05)), 0.04)
		bright.commit(holder)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 3.0
		light.omni_range = 8.0
		light.position = Vector3(x, 2.3, -0.05)
		holder.add_child(light)
		if i == 0:
			blinker.group_a.append(holder)
		else:
			blinker.group_b.append(holder)
	# Taser coil: copper windings, insulator rings, a glowing ball.
	var coil := MeshBuilder.new()
	var copper := MatKit.chrome(Color(0.8, 0.45, 0.25))
	var ceramic := MatKit.flat(Color(0.85, 0.85, 0.8), 0.3)
	coil.cylinder(ceramic, 0.07, 0.5, MeshBuilder.at(Vector3(0, 2.18, 0.6)), 10)
	for k in 7:
		coil.torus(copper, 0.1, 0.022, MeshBuilder.at(Vector3(0, 1.98 + k * 0.06, 0.6)), 12, 5)
	coil.torus(ceramic, 0.16, 0.04, MeshBuilder.at(Vector3(0, 2.45, 0.6)), 14, 6)
	coil.sphere(MatKit.lamp(Color(0.55, 0.75, 1.0), 4.0), 0.1, MeshBuilder.at(Vector3(0, 2.55, 0.6)), 10, 6)
	coil.commit(m)
	var coil_light := FlickerLight.new()
	coil_light.light_color = Color(0.5, 0.7, 1.0)
	coil_light.base_energy = 1.2
	coil_light.amount = 0.8
	coil_light.speed = 30.0
	coil_light.omni_range = 4.0
	coil_light.position = Vector3(0, 2.6, 0.6)
	m.add_child(coil_light)

	_headlight_beam(m, Vector3(0, 0.95, -2.5))
	for side: float in [-1.0, 1.0]:
		_label(m, "POLICE", Vector3(1.096 * side, 1.02, 0.25), 90.0 * side, 40, Color(0.06, 0.06, 0.08), Color(0.9, 0.9, 0.88))
	_label(m, "07", Vector3(0, 1.84, 1.05), 0.0, 60, Color(0.05, 0.05, 0.06), Color(0.9, 0.9, 0.88)).rotation_degrees = Vector3(-90, 0, 0)

	m.set_meta("guns", muzzles)
	m.set_meta("exhaust", [Vector3(-0.55, 0.52, 2.6), Vector3(0.55, 0.52, 2.6)])
	m.set_meta("launcher", Vector3(0, 2.55, 0.6))
	m.set_meta("top", Vector3(0, 1.6, -1.6))
	return m


## Five-point badge star on a door (side = +1 right, -1 left).
static func _star(mb: MeshBuilder, mat: Material, center: Vector3, side: float) -> void:
	var out := Vector3(side, 0, 0)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		var r := 0.11 if i % 2 == 0 else 0.045
		pts.append(center + Vector3(0, -sin(a) * r, cos(a) * r))
	for i in 10:
		mb.tri(mat, center + out * 0.004, pts[i], pts[(i + 1) % 10], out)
