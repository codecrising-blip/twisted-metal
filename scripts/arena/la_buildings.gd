class_name LaBuildings
extends RefCounted
## The shops along the Los Angeles arena's outer wall, built as real buildings with depth (owner,
## session 5: the old ones were "as thin as a finger"). Our own designs of LA street types:
## a two-storey motel with a walkway and a pole sign, a liquor store with barred windows, a donut
## shop with a giant donut on the roof, an old theater with a marquee and a blade sign, a taco
## stand with picnic tables, a pawn shop with roll-down shutters, an auto parts garage.
## Quake damage on all of them: cracks, soot, boarded or broken windows, rubble at the base.
## Every building goes into ONE MeshBuilder (one mesh per material for all of them) so the whole
## street costs about 20 draw calls; colliders go to the arena's shared static body.
## Each building stands with its back to the wall; its depth shrinks if the road comes close.

var _mb := MeshBuilder.new()
var _arena: LosAngelesArena
var _F := Transform3D.IDENTITY
var _m := {}
var _rng := RandomNumberGenerator.new()


func build(arena: LosAngelesArena) -> void:
	_arena = arena
	_rng.seed = 777
	_materials()
	var H := LosAngelesArena.HALF
	if _place(Vector3(-100, 0, H), Vector3(0, 0, -1), 28.0, 11.0):
		_motel()
	if _place(Vector3(36, 0, H), Vector3(0, 0, -1), 22.0, 12.0):
		_liquor()
	if _place(Vector3(H, 0, -30), Vector3(-1, 0, 0), 20.0, 12.0):
		_donuts()
	if _place(Vector3(H, 0, 100), Vector3(-1, 0, 0), 26.0, 14.0):
		_theater()
	if _place(Vector3(-H, 0, 55), Vector3(1, 0, 0), 16.0, 10.0):
		_tacos()
	if _place(Vector3(-H, 0, -100), Vector3(1, 0, 0), 26.0, 12.0):
		_auto_parts()
	if _place(Vector3(100, 0, -H), Vector3(0, 0, 1), 20.0, 11.0):
		_pawn()
	arena.batch_builder(_mb, true, 0.7) # merged with the rest of the static stage


# ---------------------------------------------------------------- frame and helpers

var _w := 20.0
var _d := 10.0


## Sets the building frame (back on the wall, front facing inward, local -Z = inward) and the
## depth that keeps the front clear of the road. False if no room at all.
func _place(wall_point: Vector3, inward: Vector3, width: float, want_depth: float) -> bool:
	var basis := Basis.looking_at(inward, Vector3.UP)
	var along := basis.x
	var d := want_depth
	while d >= 6.0:
		var ok := true
		for t: float in [-0.5, 0.0, 0.5]:
			var p := wall_point + inward * (d + 4.0) + along * width * t
			if LosAngelesArena.road_distance(p.x, p.z) < LosAngelesArena.ROAD_W * 0.5 + 2.0:
				ok = false
		if ok:
			break
		d -= 1.0
	if d < 6.0:
		return false
	_F = Transform3D(basis, wall_point)
	_w = width
	_d = d
	return true


func _xf(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return _F * MeshBuilder.at(pos, rot, scale)


func _box(mat: Material, size: Vector3, pos: Vector3, rot := Vector3.ZERO, bevel := 0.0) -> void:
	_mb.box(mat, size, _xf(pos, rot), bevel)


func _cyl(mat: Material, r: float, h: float, pos: Vector3, rot := Vector3.ZERO, seg := 8) -> void:
	_mb.cylinder(mat, r, h, _xf(pos, rot), seg)


func _solid(size: Vector3, pos: Vector3) -> void:
	_arena._solid(size, _xf(pos))


## Text facing out of the front (toward the arena), merged into the static stage as geometry.
## neon = unshaded and bright. turn = extra yaw (blade signs).
func _text(text: String, pos: Vector3, px: int, color: Color, pixel := 0.012, neon := true, turn := 0.0) -> void:
	_arena.batch_text(text, _F * Transform3D(Basis(Vector3.UP, PI), pos) * Transform3D(Basis(Vector3.UP, turn)), px, pixel, color, neon)


func _materials() -> void:
	_m.cream = MatKit.paint(Color(0.72, 0.66, 0.55), 0.12, 0.05, 0.75, 3.0, 0.93, 201)
	_m.salmon = MatKit.paint(Color(0.66, 0.46, 0.38), 0.12, 0.05, 0.75, 3.0, 0.93, 202)
	_m.teal = MatKit.paint(Color(0.38, 0.5, 0.47), 0.12, 0.05, 0.75, 3.0, 0.93, 203)
	_m.brick = MatKit.masonry(Color(0.46, 0.25, 0.19), 3.0, 204)
	_m.gray = MatKit.paint(Color(0.5, 0.49, 0.46), 0.15, 0.1, 0.8, 3.0, 0.93, 205)
	_m.trim = MatKit.paint(Color(0.78, 0.76, 0.7), 0.2, 0.05, 0.6, 2.0, 0.85, 206)
	_m.dark = MatKit.flat(Color(0.05, 0.05, 0.055), 0.85)
	_m.glass = MatKit.flat(Color(0.07, 0.09, 0.11), 0.12, 0.4)
	_m.roof = MatKit.paint(Color(0.2, 0.19, 0.18), 0.1, 0.0, 0.6, 2.0, 0.97, 207)
	_m.steel = MatKit.steel(Color(0.26, 0.27, 0.28), 0.55, 1.0)
	_m.wood = MatKit.paint(Color(0.48, 0.38, 0.26), 0.3, 0.0, 0.6, 1.0, 0.95, 208)
	_m.soot = MatKit.flat(Color(0.03, 0.025, 0.02), 1.0)
	_m.awning_red = MatKit.paint(Color(0.5, 0.11, 0.09), 0.2, 0.0, 0.6, 2.0, 0.9, 209)
	_m.awning_green = MatKit.paint(Color(0.14, 0.32, 0.2), 0.2, 0.0, 0.6, 2.0, 0.9, 210)
	_m.awning_yellow = MatKit.paint(Color(0.7, 0.55, 0.12), 0.2, 0.0, 0.6, 2.0, 0.9, 211)
	_m.bulb = MatKit.lamp(Color(1.0, 0.85, 0.55), 2.5)
	_m.neon_pink = MatKit.lamp(Color(1.0, 0.25, 0.5), 3.0)
	_m.neon_cyan = MatKit.lamp(Color(0.3, 0.9, 1.0), 2.5)


# ---------------------------------------------------------------- parts

## Walls, roof, parapet, cornice, plinth, roof clutter, cracks. y0 = height of a lower block.
func _shell(wall: Material, h: float) -> void:
	var w := _w
	var d := _d
	_box(wall, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5), Vector3.ZERO, 0.05)
	_solid(Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))
	_box(_m.roof, Vector3(w - 0.3, 0.08, d - 0.3), Vector3(0, h + 0.04, -d * 0.5))
	for side: float in [-1.0, 1.0]:
		_box(_m.trim, Vector3(0.3, 0.7, d), Vector3(side * (w * 0.5 - 0.15), h + 0.35, -d * 0.5))
	_box(_m.trim, Vector3(w, 0.7, 0.3), Vector3(0, h + 0.35, -d + 0.15))
	_box(_m.trim, Vector3(w + 0.3, 0.3, 0.35), Vector3(0, h - 0.2, -d - 0.05), Vector3.ZERO, 0.04)
	_box(_m.dark, Vector3(w + 0.06, 0.45, 0.08), Vector3(0, 0.22, -d - 0.02))
	# Roof clutter: AC units, a vent stack.
	for k in 1 + int(w / 12.0):
		var x := -w * 0.5 + 3.0 + k * 7.0 + _rng.randf_range(-1, 1)
		var z := -d * _rng.randf_range(0.3, 0.7)
		_box(_m.steel, Vector3(1.8, 1.0, 1.4), Vector3(x, h + 0.55, z), Vector3(0, _rng.randf_range(-10, 10), 0), 0.05)
		_box(_m.dark, Vector3(1.4, 0.05, 1.0), Vector3(x, h + 1.07, z))
	_cyl(_m.steel, 0.12, 1.4, Vector3(w * 0.3, h + 0.7, -d * 0.6))
	# Downspouts at the front corners.
	for side: float in [-1.0, 1.0]:
		_box(_m.steel, Vector3(0.14, h, 0.14), Vector3(side * (w * 0.5 - 0.25), h * 0.5, -d - 0.12))
	# Quake cracks running up the facade, soot from fires.
	for k in 2:
		var x := _rng.randf_range(-w * 0.4, w * 0.4)
		var y := 0.4
		for s in 6:
			var nx := x + _rng.randf_range(-0.6, 0.6)
			var ny := y + _rng.randf_range(0.4, 0.8)
			var a := Vector3(x, y, -d - 0.03)
			var b := Vector3(nx, ny, -d - 0.03)
			_mb.box(_m.soot, Vector3(0.06, a.distance_to(b), 0.02), _F * MeshBuilder.along((a + b) * 0.5, b - a), 0.0)
			x = nx
			y = ny
	# A little rubble at the base.
	for k in 4:
		var s := Vector3(_rng.randf_range(0.3, 0.8), _rng.randf_range(0.15, 0.4), _rng.randf_range(0.3, 0.7))
		_box(wall, s, Vector3(_rng.randf_range(-w * 0.45, w * 0.45), s.y * 0.4, -d - _rng.randf_range(0.3, 1.5)), Vector3(_rng.randf_range(-15, 15), _rng.randf_range(0, 90), 0), 0.04)


## Window on the front at (x, y = sill height): frame, glass, sill; kind: "", "bars", "boarded", "broken".
func _window(x: float, y: float, ww: float, wh: float, kind := "") -> void:
	var z := -_d
	_box(_m.dark, Vector3(ww + 0.24, wh + 0.24, 0.16), Vector3(x, y + wh * 0.5, z - 0.02))
	_box(_m.soot if kind == "broken" else _m.glass, Vector3(ww, wh, 0.05), Vector3(x, y + wh * 0.5, z - 0.08))
	_box(_m.trim, Vector3(ww + 0.4, 0.12, 0.3), Vector3(x, y - 0.06, z - 0.12))
	if kind == "bars":
		var n := int(ww / 0.25)
		for i in n + 1:
			_cyl(_m.steel, 0.025, wh, Vector3(x - ww * 0.5 + i * ww / n, y + wh * 0.5, z - 0.16))
		_box(_m.steel, Vector3(ww + 0.1, 0.06, 0.06), Vector3(x, y + wh * 0.5, z - 0.17))
	elif kind == "boarded":
		for i in 3:
			_box(_m.wood, Vector3(ww * 1.1, 0.22, 0.05), Vector3(x, y + wh * (0.25 + i * 0.25), z - 0.16), Vector3(0, 0, _rng.randf_range(-12, 12)))
	elif kind == "broken":
		_box(_m.soot, Vector3(ww * 0.9, wh * 0.7, 0.02), Vector3(x, y + wh + 0.5, z - 0.03)) # soot above


func _door(x: float, dw := 1.2, dh := 2.3, mat: Material = null) -> void:
	var z := -_d
	_box(_m.dark, Vector3(dw + 0.3, dh + 0.15, 0.18), Vector3(x, dh * 0.5, z - 0.02))
	_box(mat if mat else _m.wood, Vector3(dw, dh, 0.06), Vector3(x, dh * 0.5, z - 0.1))
	_box(_m.steel, Vector3(0.06, 0.06, 0.12), Vector3(x + dw * 0.35, dh * 0.45, z - 0.16))
	_box(_m.gray, Vector3(dw + 0.6, 0.15, 0.6), Vector3(x, 0.075, z - 0.3))


## Sloped awning across the front at height y, with a valance and two brackets.
func _awning(x: float, width: float, y: float, depth: float, mat: Material) -> void:
	var z := -_d
	_box(mat, Vector3(width, 0.08, depth), Vector3(x, y - depth * 0.2, z - depth * 0.5), Vector3(-22, 0, 0))
	_box(mat, Vector3(width, 0.35, 0.05), Vector3(x, y - depth * 0.42 - 0.15, z - depth * 0.95))
	for s: float in [-1.0, 1.0]:
		_box(_m.steel, Vector3(0.05, 0.05, depth), Vector3(x + s * width * 0.45, y - depth * 0.3, z - depth * 0.5), Vector3(-30, 0, 0))


## Sign board on the roof edge with lit lettering.
func _roof_sign(text: String, width: float, h: float, color: Color, px := 280) -> void:
	var z := -_d + 0.6
	for s: float in [-1.0, 1.0]:
		_box(_m.steel, Vector3(0.12, 1.6, 0.12), Vector3(s * width * 0.4, h + 0.8, z + 0.3))
	_box(_m.dark, Vector3(width, 1.9, 0.25), Vector3(0, h + 1.65, z))
	_box(_m.steel, Vector3(width + 0.2, 0.1, 0.35), Vector3(0, h + 2.65, z))
	_text(text, Vector3(0, h + 1.65, z - 0.15), px, color)


# ---------------------------------------------------------------- the buildings

func _motel() -> void:
	var h := 7.0
	_shell(_m.salmon, h)
	var z := -_d
	# Ground floor rooms (door + window), office at the right end.
	for i in 6:
		var x := -_w * 0.5 + 2.5 + i * 3.6
		_door(x - 0.7, 1.0, 2.2, _m.teal)
		_window(x + 0.9, 1.0, 1.4, 1.1, ["", "", "boarded", "", "broken", ""][i])
	_window(_w * 0.5 - 3.0, 0.7, 3.2, 1.9)
	_text("OFFICE", Vector3(_w * 0.5 - 3.0, 2.9, z - 0.2), 70, Color(1.0, 0.8, 0.4), 0.008)
	# Walkway slab, railing, stair.
	_box(_m.gray, Vector3(_w, 0.25, 1.8), Vector3(0, 3.4, z - 0.9))
	_box(_m.trim, Vector3(_w, 0.2, 0.1), Vector3(0, 3.3, z - 1.78))
	for k in int(_w / 1.6) + 1:
		var x := -_w * 0.5 + k * 1.6
		_box(_m.steel, Vector3(0.06, 1.0, 0.06), Vector3(x, 4.0, z - 1.75))
	_box(_m.steel, Vector3(_w, 0.06, 0.08), Vector3(0, 4.5, z - 1.75))
	for k in 5:
		_box(_m.steel, Vector3(0.12, 3.3, 0.12), Vector3(-_w * 0.5 + 1.0 + k * (_w - 2.0) / 4.0, 1.65, z - 1.7))
	var sa := Vector3(-_w * 0.5 - 0.8, 0.0, z - 0.6)
	var sb := Vector3(-_w * 0.5 - 0.8, 3.4, z + 3.2)
	_mb.box(_m.gray, Vector3(1.4, 0.2, sa.distance_to(sb)), _F * Transform3D(Basis.looking_at((sb - sa).normalized(), Vector3.UP), (sa + sb) * 0.5), 0.0)
	# Upper floor rooms.
	for i in 6:
		var x := -_w * 0.5 + 2.5 + i * 3.6
		_door(x - 0.7, 1.0, 2.2, _m.teal)
		_window(x + 0.9, 4.4, 1.4, 1.1, ["", "broken", "", "", "", "boarded"][i])
	# The pole sign out front.
	var px := _w * 0.5 + 2.5
	_cyl(_m.steel, 0.22, 11.0, Vector3(px, 5.5, z - 2.0))
	_solid(Vector3(0.6, 11.0, 0.6), Vector3(px, 5.5, z - 2.0))
	_box(_m.dark, Vector3(5.6, 2.6, 0.7), Vector3(px, 10.0, z - 2.0), Vector3.ZERO, 0.08)
	for k in 12:
		_box(_m.bulb, Vector3(0.14, 0.14, 0.05), Vector3(px - 2.6 + k * 0.47, 11.25, z - 2.38))
	_text("MOTEL", Vector3(px, 10.0, z - 2.4), 240, Color(1.0, 0.35, 0.5))
	_box(_m.dark, Vector3(3.2, 0.8, 0.3), Vector3(px, 8.2, z - 2.0))
	_text("SHELTER FULL", Vector3(px, 8.2, z - 2.2), 80, Color(1.0, 0.25, 0.2), 0.009)


func _liquor() -> void:
	var h := 5.5
	_shell(_m.cream, h)
	var z := -_d
	_window(-_w * 0.5 + 3.5, 0.6, 4.2, 2.3, "bars")
	_window(_w * 0.5 - 3.5, 0.6, 4.2, 2.3, "bars")
	_window(-2.5, 0.6, 2.4, 2.3, "bars")
	_door(1.2, 1.4, 2.4, _m.glass)
	for k in 6: # bars over the door
		_cyl(_m.steel, 0.025, 2.3, Vector3(0.6 + k * 0.24, 1.2, z - 0.22))
	_awning(0, _w - 2.0, 3.6, 1.6, _m.awning_green)
	for k in 3: # posters
		_box(MatKit.flat([Color(0.7, 0.2, 0.15), Color(0.85, 0.75, 0.3), Color(0.2, 0.35, 0.6)][k], 0.8), Vector3(0.7, 1.0, 0.02), Vector3(-_w * 0.5 + 6.6 + k * 0.85, 1.5, z - 0.12))
	_roof_sign("LIQUOR", 10.0, h, Color(0.4, 1.0, 0.75))


func _donuts() -> void:
	var h := 5.0
	_shell(_m.teal, h)
	var z := -_d
	for k in 3:
		_window(-_w * 0.5 + 3.0 + k * 4.6, 0.5, 3.8, 2.6, "broken" if k == 1 else "")
	_door(_w * 0.5 - 2.5, 1.4, 2.4, _m.glass)
	_awning(0, _w - 1.0, 3.7, 1.4, _m.awning_yellow)
	_text("DONUTS", Vector3(0, 4.4, z - 0.2), 160, Color(1.0, 0.6, 0.25), 0.01)
	# Giant donut on the roof: chocolate glaze, sprinkles, held by two steel posts.
	var c := Vector3(0, h + 6.2, -_d * 0.45)
	for s: float in [-1.0, 1.0]:
		_box(_m.steel, Vector3(0.35, 4.2, 0.35), Vector3(s * 2.2, h + 2.1, -_d * 0.45))
	var dough := MatKit.paint(Color(0.62, 0.42, 0.22), 0.3, 0.0, 0.7, 2.0, 0.85, 212)
	var glaze := MatKit.paint(Color(0.22, 0.12, 0.08), 0.3, 0.0, 0.5, 2.0, 0.45, 213)
	_mb.torus(dough, 2.6, 1.3, _xf(c, Vector3(90, 0, 0)), 24, 10)
	_mb.torus(glaze, 2.6, 1.32, _xf(c + Vector3(0, 0, -0.35), Vector3(90, 0, 0), Vector3(1, 1, 0.55)), 24, 8)
	for k in 26:
		var a := TAU * k / 26.0
		var r := 2.6 + _rng.randf_range(-0.8, 0.8)
		_box(MatKit.flat([Color(0.9, 0.85, 0.3), Color(0.3, 0.75, 0.8), Color(0.85, 0.85, 0.82)][k % 3], 0.6), Vector3(0.28, 0.08, 0.08), c + Vector3(cos(a) * r, sin(a) * r, -1.15), Vector3(0, 0, _rng.randf_range(0, 180)))


func _theater() -> void:
	var h := 12.0
	_shell(_m.brick, h)
	var z := -_d
	# Entrance: recessed doors, poster cases, ticket booth.
	for k in 4:
		_door(-3.0 + k * 2.0, 1.6, 2.8, _m.glass)
	for s: float in [-1.0, 1.0]:
		_box(_m.dark, Vector3(1.4, 2.0, 0.2), Vector3(s * 7.0, 1.9, z - 0.1))
		_box(MatKit.flat(Color(0.6, 0.15, 0.12), 0.7), Vector3(1.1, 1.6, 0.05), Vector3(s * 7.0, 1.9, z - 0.22))
	_box(_m.trim, Vector3(2.2, 2.6, 1.6), Vector3(0, 1.3, z - 2.6), Vector3.ZERO, 0.08)
	_box(_m.glass, Vector3(1.6, 1.0, 0.05), Vector3(0, 1.9, z - 3.42))
	_solid(Vector3(2.2, 2.6, 1.6), Vector3(0, 1.3, z - 2.6))
	# Marquee with bulb rows.
	_box(_m.trim, Vector3(16.0, 2.2, 3.2), Vector3(0, 5.2, z - 1.6), Vector3.ZERO, 0.1)
	for row: float in [6.25, 4.15]:
		for k in 30:
			_box(_m.bulb, Vector3(0.14, 0.14, 0.05), Vector3(-7.6 + k * 0.525, row, z - 3.22))
	_box(MatKit.flat(Color(0.88, 0.86, 0.78), 0.7), Vector3(14.5, 1.3, 0.05), Vector3(0, 5.2, z - 3.2))
	_text("LIVE TONIGHT\nTHE CONTEST", Vector3(0, 5.2, z - 3.26), 110, Color(0.1, 0.08, 0.08), 0.009, false)
	# Vertical blade sign.
	_box(_m.dark, Vector3(0.6, 7.0, 2.4), Vector3(0, 9.8, z - 1.2), Vector3.ZERO, 0.08)
	for s: float in [-1.0, 1.0]:
		_text("T\nH\nE\nA\nT\nE\nR", Vector3(s * 0.32, 9.8, z - 1.2), 110, Color(1.0, 0.82, 0.3), 0.0072, true, s * PI * 0.5)
	for k in 3:
		_window(-9.5 + k * 9.5, 8.0, 2.0, 2.2, "boarded" if k == 2 else "")


func _tacos() -> void:
	var h := 4.6
	_shell(_m.cream, h)
	var z := -_d
	for k in 2: # walk-up order windows
		_window(-3.0 + k * 6.0, 1.0, 2.8, 1.5)
		_box(_m.steel, Vector3(3.2, 0.08, 0.6), Vector3(-3.0 + k * 6.0, 1.0, z - 0.35))
	_door(_w * 0.5 - 1.8, 1.0, 2.2)
	_awning(0, _w - 1.0, 3.6, 1.8, _m.awning_red)
	_box(_m.dark, Vector3(2.4, 1.5, 0.1), Vector3(0, 1.75, z - 0.1)) # menu board
	_roof_sign("TACOS", 8.0, h, Color(1.0, 0.65, 0.2))
	# Picnic tables with umbrellas out front.
	for k in 2:
		var p := Vector3(-4.0 + k * 8.0, 0, z - 5.0)
		_box(_m.wood, Vector3(2.2, 0.08, 0.9), p + Vector3(0, 0.75, 0))
		for s: float in [-1.0, 1.0]:
			_box(_m.wood, Vector3(2.2, 0.06, 0.3), p + Vector3(0, 0.45, s * 0.75))
		_cyl(_m.steel, 0.04, 2.4, p + Vector3(0, 1.2, 0))
		_mb.cylinder(_m.awning_yellow if k == 0 else _m.awning_red, 1.4, 0.5, _xf(p + Vector3(0, 2.5, 0)), 10, 0.05, true)


func _auto_parts() -> void:
	var h := 7.0
	_shell(_m.gray, h)
	var z := -_d
	for k in 2: # roll-up garage doors, one half open
		var x := -_w * 0.5 + 5.0 + k * 8.0
		_box(_m.dark, Vector3(5.4, 4.6, 0.2), Vector3(x, 2.3, z - 0.02))
		var down := 4.4 if k == 0 else 2.2
		for i in int(down / 0.2):
			_box(_m.steel, Vector3(5.0, 0.18, 0.08), Vector3(x, 4.4 - i * 0.2 - 0.1, z - 0.12))
	_window(_w * 0.5 - 4.5, 0.9, 3.0, 1.8, "bars")
	_door(_w * 0.5 - 1.8, 1.0, 2.3)
	_roof_sign("AUTO PARTS", 14.0, h, Color(1.0, 0.3, 0.25), 240)
	# Tire stack by the door.
	for k in 5:
		_mb.torus(_m.dark, 0.38, 0.16, _xf(Vector3(_w * 0.5 - 1.0, 0.18 + k * 0.32, z - 1.6)), 12, 6)


func _pawn() -> void:
	var h := 6.0
	_shell(_m.salmon, h)
	var z := -_d
	for k in 2: # shutters pulled down over the windows
		var x := -_w * 0.5 + 4.0 + k * 9.0
		_box(_m.dark, Vector3(3.8, 2.6, 0.2), Vector3(x, 1.9, z - 0.02))
		for i in 12:
			_box(_m.steel, Vector3(3.6, 0.2, 0.08), Vector3(x, 3.1 - i * 0.21, z - 0.12))
	_door(2.0, 1.2, 2.3, _m.steel)
	_awning(0, _w - 2.0, 3.8, 1.2, _m.awning_red)
	_roof_sign("PAWN", 7.0, h, Color(0.45, 0.85, 1.0))
	_text("WE BUY GOLD", Vector3(0, 4.6, z - 0.2), 70, Color(1.0, 0.85, 0.35), 0.009)
	# Three gold balls hanging from a bracket (the old pawnbroker sign).
	var bx := -_w * 0.5 + 1.2
	_box(_m.steel, Vector3(0.08, 0.08, 1.2), Vector3(bx, 4.8, z - 0.6))
	var gold := MatKit.paint(Color(0.7, 0.55, 0.2), 0.3, 0.1, 0.4, 1.0, 0.35, 214)
	gold.metallic = 0.8
	for k in 3:
		var o: Vector3 = [Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0), Vector3(0, -0.4, 0)][k]
		_mb.sphere(gold, 0.22, _xf(Vector3(bx, 4.2, z - 1.1) + o), 10, 6)
