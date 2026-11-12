class_name HudStatus
extends Control
## Bottom-left panel: car and driver, spare lives, segmented health bar (green -> amber -> red,
## with a pale trail showing the damage you just took), turbo and energy bars with the energy cost
## marks, and state chips (BURNING, FROZEN, PROTECTED). Drawn in code, no textures.

const W := 470.0
const H := 158.0
const ACCENT := Color(0.85, 0.22, 0.12)

var player: Vehicle
var spare_lives := 2
var font: Font

var _trail := 1.0 # health fraction the pale trail is at
var _flash := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var f := player.health / player.max_health
	_trail = f if f > _trail else move_toward(_trail, f, delta * 0.35)
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var bg := PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W - 34, H), Vector2(0, H)])
	draw_colored_polygon(bg, Color(0.04, 0.04, 0.05, 0.74))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W - 1.3, 4), Vector2(0, 4)]), ACCENT)
	draw_polyline(PackedVector2Array([Vector2(W, 0), Vector2(W - 34, H), Vector2(0, H)]), Color(1, 1, 1, 0.08), 1.0)
	if not is_instance_valid(player):
		return
	# Name, driver, lives.
	var name_text := player.display_name.to_upper()
	draw_string(font, Vector2(18, 40), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.94, 0.91, 0.85))
	var nw := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(font, Vector2(26 + nw, 40), String(player.stats.get("driver", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.57, 0.52))
	draw_string(font, Vector2(W - 150, 24), "LIVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.57, 0.52))
	for i in 2:
		_car_icon(Vector2(W - 100 + i * 34, 16), i < spare_lives)
	# Health.
	var f := clampf(player.health / player.max_health, 0.0, 1.0)
	draw_string(font, Vector2(18, 72), "HEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.67, 0.62))
	var hc := _health_color(f)
	if _flash > 0.0:
		hc = hc.lerp(Color(1, 1, 1), _flash * 0.6)
	_segments(Rect2(92, 56, 300, 22), 25, f, hc, _trail)
	draw_string(font, Vector2(402, 76), str(ceili(player.health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, hc.lightened(0.2))
	# Turbo and energy.
	draw_string(font, Vector2(18, 103), "TURBO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.67, 0.62))
	_segments(Rect2(92, 92, 240, 11), 30, player.turbo / 100.0, Color(1.0, 0.56, 0.1), -1.0)
	draw_string(font, Vector2(18, 125), "ENERGY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.67, 0.62))
	_segments(Rect2(92, 114, 240, 11), 30, player.energy / 100.0, Color(0.3, 0.62, 1.0), -1.0)
	for cost: float in [Vehicle.JUMP_COST, Vehicle.FREEZE_COST]:
		var x := 92.0 + 240.0 * cost / 100.0
		draw_line(Vector2(x, 111), Vector2(x - 3, 128), Color(1, 1, 1, 0.55), 1.5)
	# State chips.
	var chips: Array = []
	if player.burn_time > 0.0:
		chips.append(["BURNING", Color(1.0, 0.45, 0.1)])
	if player.frozen_time > 0.0:
		chips.append(["FROZEN", Color(0.55, 0.85, 1.0)])
	if player.invulnerable_time > 0.0:
		chips.append(["PROTECTED", Color(0.95, 0.9, 0.5)])
	if player.shield_time > 0.0:
		chips.append(["SHIELD", Color(0.4, 0.8, 1.0)])
	if player.invisible_time > 0.0:
		chips.append(["INVISIBLE" if player.revealed_time <= 0.0 else "SEEN", Color(0.75, 0.6, 1.0)])
	if player.headlights_on:
		chips.append(["LIGHTS", Color(1.0, 0.95, 0.75)])
	var cx := 350.0
	for c in chips:
		var tw := font.get_string_size(c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(cx, 93, tw + 14, 20), Color(c[1].r, c[1].g, c[1].b, 0.25))
		draw_string(font, Vector2(cx + 7, 108), c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c[1])
		cx += tw + 20
		if cx > W - 60:
			break


func _health_color(f: float) -> Color:
	if f > 0.6:
		return Color(0.42, 0.82, 0.22).lerp(Color(0.92, 0.78, 0.16), (1.0 - f) / 0.4)
	if f > 0.3:
		return Color(0.92, 0.78, 0.16).lerp(Color(0.95, 0.42, 0.08), (0.6 - f) / 0.3)
	return Color(0.95, 0.42, 0.08).lerp(Color(0.9, 0.08, 0.06), (0.3 - f) / 0.3)


## Slanted segments; filled up to `value` (0..1). trail >= value draws the recent damage pale.
func _segments(r: Rect2, count: int, value: float, color: Color, trail: float) -> void:
	var gap := 3.0
	var sw := (r.size.x - gap * (count - 1)) / count
	var skew := r.size.y * 0.35
	for i in count:
		var x := r.position.x + i * (sw + gap)
		var t0 := float(i) / count
		var t1 := float(i + 1) / count
		var poly := PackedVector2Array([Vector2(x + skew, r.position.y), Vector2(x + sw + skew, r.position.y),
			Vector2(x + sw, r.end.y), Vector2(x, r.end.y)])
		var c := Color(0.16, 0.16, 0.17, 0.85)
		if value >= t1 - 0.001:
			c = color
		elif value > t0:
			c = color.darkened(0.45)
		elif trail > t0:
			c = Color(0.85, 0.82, 0.75, 0.75)
		draw_colored_polygon(poly, c)


func _car_icon(p: Vector2, filled: bool) -> void:
	var c := Color(0.94, 0.78, 0.3) if filled else Color(0.3, 0.29, 0.27)
	draw_rect(Rect2(p + Vector2(0, 4), Vector2(26, 9)), c)
	draw_rect(Rect2(p + Vector2(6, 0), Vector2(13, 5)), c)
	draw_circle(p + Vector2(6, 14), 3.2, c.darkened(0.3))
	draw_circle(p + Vector2(20, 14), 3.2, c.darkened(0.3))
