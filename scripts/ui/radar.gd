class_name Radar
extends Control
## Top-right radar. Turns with your car (straight ahead = up), 120 m range.
##   red triangles   enemies (pointing where they drive); at the rim when out of range
##   yellow squares  weapon pickups, small blue dots = turbo, green crosses = health (bigger = mega)
##   grey lines      the arena walls and the ring road (from arena.radar_lines(), if it has one)
##   N               north on the rim

const SIZE := 200.0
const RANGE := 120.0

var player: Vehicle
var lines: Array = [] # Array of PackedVector2Array (world x, z) polylines
var enemies_left := 0
var font: Font

var _sweep := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 30)
	size = Vector2(SIZE, SIZE + 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta * 2.2, TAU)
	queue_redraw()


func _to_radar(world: Vector3) -> Vector2:
	var local := player.global_basis.inverse() * (world - player.global_position)
	return Vector2(local.x, local.z) / RANGE * (SIZE * 0.5 - 6.0)


func _draw() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5 - 4.0
	draw_circle(c, r + 3.0, Color(0.04, 0.04, 0.05, 0.78))
	draw_arc(c, r + 3.0, 0, TAU, 48, Color(0.85, 0.22, 0.12, 0.85), 2.0)
	for k in 2:
		draw_arc(c, r * (k + 1) / 3.0, 0, TAU, 36, Color(0.5, 0.75, 0.5, 0.18), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.5, 0.75, 0.5, 0.12), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.5, 0.75, 0.5, 0.12), 1.0)
	for k in 10:
		var a := _sweep - k * 0.06
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(0.5, 0.9, 0.5, 0.22 - k * 0.02), 2.0)
	if not is_instance_valid(player):
		return
	# Walls and roads, clipped to the circle.
	for line: PackedVector2Array in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var steps := 8
			for s in steps:
				var p0 := c + _to_radar(Vector3(lerpf(a.x, b.x, float(s) / steps), 0, lerpf(a.y, b.y, float(s) / steps)))
				var p1 := c + _to_radar(Vector3(lerpf(a.x, b.x, float(s + 1) / steps), 0, lerpf(a.y, b.y, float(s + 1) / steps)))
				if p0.distance_to(c) < r and p1.distance_to(c) < r:
					draw_line(p0, p1, Color(0.75, 0.75, 0.72, 0.4), 1.5)
	# Pickups.
	for n in player.get_tree().get_nodes_in_group("pickups"):
		var pk := n as Pickup
		if pk == null or not pk.active:
			continue
		var p := _to_radar(pk.global_position)
		if p.length() > r - 4.0:
			continue
		p += c
		if pk.kind == "health" or pk.kind == "mega":
			var s := 4.5 if pk.kind == "mega" else 3.0
			var col := Color(0.45, 1.0, 0.45) if pk.kind == "mega" else Color(0.3, 0.85, 0.35)
			draw_rect(Rect2(p - Vector2(s, s * 0.35), Vector2(s * 2, s * 0.7)), col)
			draw_rect(Rect2(p - Vector2(s * 0.35, s), Vector2(s * 0.7, s * 2)), col)
		elif pk.kind == "turbo":
			draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.35, 0.7, 1.0, 0.75))
		else:
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.82, 0.25, 0.9))
	# Enemies.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for n in player.get_tree().get_nodes_in_group("vehicles"):
		var v := n as Vehicle
		if v == null or v == player or v.is_dead:
			continue
		var p := _to_radar(v.global_position)
		var outside := p.length() > r - 8.0
		if outside:
			p = p.normalized() * (r - 8.0)
		p += c
		var fwd := player.global_basis.inverse() * (-v.global_basis.z)
		var d := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-d.y, d.x)
		var s := 5.0 if outside else 7.0
		var tri := PackedVector2Array([p + d * s * 1.3, p - d * s * 0.8 + side * s * 0.8, p - d * s * 0.8 - side * s * 0.8])
		var col := Color(1.0, 0.22, 0.15)
		if outside:
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), col, 1.5)
		else:
			draw_colored_polygon(tri, col)
		if v == player.target:
			draw_arc(p, 10.0 + pulse * 3.0, 0, TAU, 20, Color(1.0, 0.3, 0.2, 0.8), 1.5)
	# You, and north.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)]), Color(0.95, 0.95, 0.9))
	var north := player.global_basis.inverse() * Vector3(0, 0, -1)
	var nd := Vector2(north.x, north.z).normalized()
	var np := c + nd * (r - 10.0)
	draw_string(font, np + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.75))
	draw_string(font, Vector2(0, SIZE + 22), "ENEMIES LEFT  %d" % enemies_left, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 18, Color(0.94, 0.91, 0.85))
