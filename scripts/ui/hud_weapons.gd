class_name HudWeapons
extends Control
## Bottom-right panel: the selected weapon big (icon, name, ammo, SPECIAL tag) and every other
## weapon you carry as small chips underneath. Icons are drawn from the weapon's kind and color.

const W := 440.0
const H := 158.0

var player: Vehicle
var font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bg := PackedVector2Array([Vector2(34, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)])
	draw_colored_polygon(bg, Color(0.04, 0.04, 0.05, 0.74))
	if not is_instance_valid(player) or player.weapon_order.is_empty():
		return
	var current := player.selected_weapon()
	var def := WeaponData.get_def(current)
	var color: Color = def.get("color", Color.WHITE)
	draw_colored_polygon(PackedVector2Array([Vector2(34, 0), Vector2(W, 0), Vector2(W, 4), Vector2(33, 4)]), color)
	# Big icon box.
	var box := Rect2(46, 16, 84, 84)
	draw_rect(box, Color(color.r, color.g, color.b, 0.16))
	draw_rect(box, Color(color.r, color.g, color.b, 0.7), false, 2.0)
	_icon(String(def.get("kind", "missile")), box.get_center(), 30.0, color)
	var label := String(def.get("label", current)).to_upper()
	draw_string(font, Vector2(144, 46), label, HORIZONTAL_ALIGNMENT_LEFT, 200, 26, Color(0.94, 0.91, 0.85))
	if def.get("special", false):
		draw_rect(Rect2(144, 56, 76, 20), Color(0.95, 0.75, 0.2, 0.22))
		draw_string(font, Vector2(151, 71), "SPECIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.98, 0.8, 0.3))
	var count: int = player.ammo.get(current, 0)
	draw_string(font, Vector2(W - 140, 98), "x%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, 120, 46, color.lightened(0.15))
	draw_string(font, Vector2(144, 96), "Q / E  CHANGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.48, 0.45))
	# Other weapons as chips.
	var x := 46.0
	for id in player.weapon_order:
		if x > W - 60:
			break
		var d := WeaponData.get_def(id)
		var c: Color = d.get("color", Color.WHITE)
		var sel: bool = id == current
		var chip := Rect2(x, 112, 58, 34)
		draw_rect(chip, Color(c.r, c.g, c.b, 0.3 if sel else 0.1))
		draw_rect(chip, Color(c.r, c.g, c.b, 0.9 if sel else 0.35), false, 1.5)
		_icon(String(d.get("kind", "missile")), chip.position + Vector2(17, 17), 10.0, c if sel else c.darkened(0.35))
		draw_string(font, chip.position + Vector2(30, 24), str(player.ammo.get(id, 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.9, 0.85) if sel else Color(0.6, 0.58, 0.55))
		x += 64.0


## Weapon icons from simple shapes, centered on c, about 2*s wide.
func _icon(kind: String, c: Vector2, s: float, col: Color) -> void:
	match kind:
		"missile", "ghost":
			var body := Rect2(c.x - s * 0.9, c.y - s * 0.16, s * 1.4, s * 0.32)
			draw_rect(body, col)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x + s * 0.5, c.y - s * 0.16), Vector2(c.x + s, c.y), Vector2(c.x + s * 0.5, c.y + s * 0.16)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.9, c.y - s * 0.16), Vector2(c.x - s * 0.55, c.y - s * 0.16), Vector2(c.x - s * 1.0, c.y - s * 0.5)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.9, c.y + s * 0.16), Vector2(c.x - s * 0.55, c.y + s * 0.16), Vector2(c.x - s * 1.0, c.y + s * 0.5)]), col)
			if kind == "ghost":
				for k in 3:
					draw_arc(c + Vector2(-s * 1.2, 0), s * (0.3 + k * 0.2), PI * 0.6, PI * 1.4, 8, Color(col.r, col.g, col.b, 0.6 - k * 0.15), 1.5)
		"lob":
			draw_arc(c + Vector2(0, s * 0.6), s * 0.9, PI * 1.1, PI * 1.9, 12, Color(col.r, col.g, col.b, 0.6), 2.0)
			draw_circle(c + Vector2(s * 0.45, -s * 0.05), s * 0.32, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s * 0.2), c + Vector2(s * 0.45, -s * 0.8), c + Vector2(s * 0.7, -s * 0.2)]), col)
		"beam":
			var pts := PackedVector2Array([c + Vector2(-s, -s * 0.2), c + Vector2(-s * 0.4, -s * 0.5), c + Vector2(-s * 0.1, s * 0.3),
				c + Vector2(s * 0.3, -s * 0.4), c + Vector2(s * 0.6, s * 0.2), c + Vector2(s, -s * 0.1)])
			draw_polyline(pts, col, maxf(2.0, s * 0.12))
		"bomb":
			draw_circle(c, s * 0.5, col)
			for k in 8:
				var a := TAU * k / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.45, c + Vector2(cos(a), sin(a)) * s * 0.8, col, maxf(1.5, s * 0.1))
			draw_line(c + Vector2(0, -s * 0.5), c + Vector2(s * 0.3, -s), Color(col.r, col.g, col.b, 0.7), 1.5)
		"skull":
			draw_circle(c + Vector2(0, -s * 0.1), s * 0.6, col)
			draw_rect(Rect2(c + Vector2(-s * 0.35, s * 0.3), Vector2(s * 0.7, s * 0.35)), col)
			var hole := Color(0.04, 0.04, 0.05)
			draw_circle(c + Vector2(-s * 0.22, -s * 0.1), s * 0.17, hole)
			draw_circle(c + Vector2(s * 0.22, -s * 0.1), s * 0.17, hole)
		"freeze":
			for k in 3:
				var a := PI * k / 3.0
				var d := Vector2(cos(a), sin(a)) * s * 0.9
				draw_line(c - d, c + d, col, maxf(1.5, s * 0.1))
		_:
			draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.12), Vector2(s * 1.6, s * 0.24)), col)
