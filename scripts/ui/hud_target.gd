class_name HudTarget
extends Control
## Top-center: the locked enemy (owner, round 7: "not just a red line"). A slanted plate with the
## car's name (round 12: no driver names) and a bar whose colour follows the health like your own (green, yellow,
## orange, red), a pale trail that drains after each hit, and below 30% a heartbeat: the bar and
## frame pulse "lub-dub" and a monitor beep sounds on every beat, faster as the health runs out.

const W := 380.0
const H := 62.0
const LOW := 0.3 # heartbeat starts under this share of health

var target: Vehicle
var font: Font

var _trail := 1.0
var _hold := 0.0
var _shown_for: Vehicle
var _beat_t := 0.0 # time since the last beat
var _pulse := 0.0 # 0..1 glow of the current beat
var _hit_flash := 0.0
var _last_f := 1.0
var _banner := "" # round 12: after a win the plate reads this for a few seconds, then is gone
var _banner_left := 0.0


## Shows `text` on the plate instead of a target for `secs` seconds (fades out over the last one).
func show_banner(text: String, secs: float) -> void:
	_banner = text
	_banner_left = secs


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	pivot_offset = Vector2(W * 0.5, H * 0.5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func health_color(f: float) -> Color:
	if f > 0.6:
		return Color(0.42, 0.82, 0.22).lerp(Color(0.92, 0.78, 0.16), (1.0 - f) / 0.4)
	if f > 0.3:
		return Color(0.92, 0.78, 0.16).lerp(Color(0.95, 0.42, 0.08), (0.6 - f) / 0.3)
	return Color(0.95, 0.42, 0.08).lerp(Color(0.9, 0.08, 0.06), (0.3 - f) / 0.3)


## Seconds between heartbeats: 0.9 s just under 30%, 0.35 s near death.
static func beat_interval(f: float) -> float:
	return lerpf(0.35, 0.9, clampf(f / LOW, 0.0, 1.0))


func _process(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		visible = _banner_left > 0.0
		scale = Vector2.ONE
		modulate.a = clampf(_banner_left, 0.0, 1.0)
		queue_redraw()
		return
	modulate.a = 1.0
	visible = is_instance_valid(target) and not target.is_dead
	if not visible:
		return
	var f := clampf(target.health / target.max_health, 0.0, 1.0)
	if target != _shown_for:
		_shown_for = target
		_trail = f
		_last_f = f
		_beat_t = 0.0
	if f < _last_f - 0.001:
		_hold = 0.45 # just hit: hold the pale part a moment, then let it drain
		_hit_flash = 1.0
	_last_f = f
	_hold -= delta
	if _hold <= 0.0:
		_trail = move_toward(_trail, f, delta * 0.45)
	_trail = maxf(_trail, f)
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
	# Heartbeat: "lub" at the beat, a softer "dub" 0.18 s later.
	if f < LOW:
		_beat_t += delta
		var every := beat_interval(f)
		if _beat_t >= every:
			_beat_t = fmod(_beat_t, every)
			GameFeel.ui("low_health_beep", get_tree(), -12.0)
		_pulse = exp(-_beat_t * 14.0) + 0.6 * exp(-maxf(0.0, _beat_t - 0.18) * 14.0) * float(_beat_t >= 0.18)
	else:
		_beat_t = 0.0
		_pulse = 0.0
	scale = Vector2.ONE * (1.0 + 0.035 * minf(_pulse, 1.0))
	queue_redraw()


func _draw() -> void:
	if _banner_left > 0.0:
		var plate_b := PackedVector2Array([Vector2(16, 0), Vector2(W - 16, 0), Vector2(W, H), Vector2(0, H)])
		draw_colored_polygon(plate_b, Color(0.04, 0.04, 0.05, 0.72))
		draw_polyline(PackedVector2Array([Vector2(16, 0), Vector2(W - 16, 0)]), Color(0.85, 0.22, 0.12, 0.9), 3.0)
		var lines := _banner.split("\n")
		for i in lines.size():
			var fs := 22 if i == 0 else 16
			var ls := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, Vector2((W - ls.x) * 0.5, 27 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.95, 0.92, 0.86) if i == 0 else Color(0.85, 0.22, 0.12))
		return
	if not is_instance_valid(target):
		return
	var f := clampf(target.health / target.max_health, 0.0, 1.0)
	var col := health_color(f)
	var p := minf(_pulse, 1.0)
	# Plate, slanted at both ends.
	var plate := PackedVector2Array([Vector2(16, 0), Vector2(W - 16, 0), Vector2(W, H), Vector2(0, H)])
	draw_colored_polygon(plate, Color(0.04, 0.04, 0.05, 0.72))
	var edge := col.lerp(Color(1, 0.15, 0.1), 0.5) if f < LOW else Color(0.85, 0.22, 0.12)
	draw_polyline(PackedVector2Array([Vector2(16, 0), Vector2(W - 16, 0)]), Color(edge.r, edge.g, edge.b, 0.9), 3.0)
	if p > 0.01:
		draw_polyline(PackedVector2Array([Vector2(16, 0), Vector2(W - 16, 0), Vector2(W, H), Vector2(0, H), Vector2(16, 0)]),
			Color(1.0, 0.2, 0.15, 0.85 * p), 2.0 + 2.0 * p)
	# The car's name only (owner, round 12: no driver names on the HUD).
	var name := target.display_name.to_upper()
	var ns := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(font, Vector2((W - ns.x) * 0.5, 27), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.92, 0.86))
	# Bar: dark track, pale trail, the health in its colour with a lighter top half, tick marks.
	var bar := Rect2(24, 36, W - 48, 14)
	draw_rect(bar, Color(0.12, 0.12, 0.13, 0.9))
	if _trail > f:
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * f, 0), Vector2(bar.size.x * (_trail - f), bar.size.y)), Color(0.95, 0.92, 0.85, 0.8))
	var fill := col.lerp(Color.WHITE, 0.35 * p + 0.5 * _hit_flash)
	var w := bar.size.x * f
	draw_rect(Rect2(bar.position, Vector2(w, bar.size.y)), fill)
	draw_rect(Rect2(bar.position, Vector2(w, bar.size.y * 0.4)), fill.lightened(0.25))
	for k in range(1, 10):
		var tx := bar.position.x + bar.size.x * k / 10.0
		draw_rect(Rect2(tx, bar.position.y, 1.5, bar.size.y), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(bar, Color(1, 1, 1, 0.18 + 0.5 * p), false, 1.0)
