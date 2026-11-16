class_name ShieldCage
extends Node3D
## The energy shield (round 16, the owner's Twisted Metal: Black reference, "I WANT THAT SHIELD"):
## not a bubble but live electricity. White-hot strands with a blue glow run round the car's body at
## the waist and the roofline, jump between them at the corners, and every moment a bolt or two
## arcs out from the body to the ground or the air around it. It crackles on and off; in its last
## half second it sputters (gaps, weaker strands) so you know it is about to drop. A hit on it
## throws an arc to the side it came from. All of it is ONE Bolt mesh (one draw call).

const REDRAW := 1.0 / 30.0 # redraw the strands this often (lightning that holds still looks fake)
const OUT_EVERY := 0.11 # a new outward arc this often
const OUT_LIFE := 0.13
const HUG := 0.22 # metres outside the body

var car: Vehicle
var size := Vector3(2.2, 1.8, 5.0)
var _bolt: Bolt
var _light: OmniLight3D
var _t := 0.0
var _redraw := 0.0
var _out_t := 0.0
var _outs: Array = [] # [from_local, to_world, life]
var _hits: Array = [] # [to_world, life]


func _ready() -> void:
	_bolt = Bolt.new()
	_bolt.tint = Color(0.35, 0.62, 1.0)
	add_child(_bolt)
	# HIGH only: a cold blue light on the car and the ground under it (LOW never draws effect lights).
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.7, 1.0)
	_light.omni_range = 7.0
	_light.light_energy = 1.4
	_light.position = Vector3(0, size.y * 0.6, 0)
	_light.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	_light.visible = GraphicsSettings.high
	add_child(_light)
	# Switched on: every outward arc fires at once.
	for k in 5:
		_spawn_out()


## Something hit the shield from `from` (world): an arc jumps out toward it.
func hit_from(from: Vector3) -> void:
	if car == null:
		return
	var dir := from - car.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var to := car.global_position + Vector3.UP * size.y * 0.6 + dir.normalized() * randf_range(3.0, 4.5) + Vector3.UP * randf_range(-0.5, 1.2)
	_hits.append([to, 0.18])


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_t += delta
	var left := car.shield_time
	var dying := left < 0.5
	for o in _outs:
		o[2] -= delta
	_outs = _outs.filter(func(o): return o[2] > 0.0)
	for h in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h): return h[1] > 0.0)
	_out_t -= delta
	if _out_t <= 0.0:
		_out_t = OUT_EVERY * randf_range(0.6, 1.4) * (1.8 if dying else 1.0)
		_spawn_out()
	if _light.visible:
		_light.light_energy = randf_range(0.8, 1.8) * (0.5 if dying else 1.0)
	_redraw -= delta
	if _redraw > 0.0:
		return
	_redraw = REDRAW
	_bolt.begin()
	# Sputtering at the end: whole frames go dark, the rest are weaker.
	if dying and randf() < 0.35:
		_bolt.finish()
		return
	var a := (0.55 if dying else 1.0) * randf_range(0.75, 1.0)
	var xf := car.global_transform
	var hw := size.x * 0.5 + HUG
	var hl := size.z * 0.5 + HUG
	# Waist loop (full body), roof loop (narrower, shorter: the cabin).
	_loop(xf, hw, hl, size.y * 0.42, 0.034, a)
	_loop(xf, hw * 0.8, hl * 0.62, size.y + 0.12, 0.026, a * 0.85)
	# Corner jumps between the two loops, two of the four each redraw.
	for k in 2:
		var sx := 1.0 if randf() < 0.5 else -1.0
		var sz := 1.0 if randf() < 0.5 else -1.0
		var p0 := xf * Vector3(sx * hw, size.y * 0.42, sz * hl)
		var p1 := xf * Vector3(sx * hw * 0.8, size.y + 0.12, sz * hl * 0.62)
		_bolt.strand(Bolt.jagged(p0, p1, 3, 0.3), 0.024, 0.016, a * 0.9)
	# Outward arcs to the ground and the air around the car.
	for o in _outs:
		var from: Vector3 = xf * (o[0] as Vector3)
		_bolt.zap(from, o[1], 0.0, 1, a * clampf(o[2] / OUT_LIFE * 1.5, 0.2, 1.0))
	for h in _hits:
		var from2 := xf * Vector3(0, size.y * 0.6, 0)
		_bolt.zap(from2, h[0], 0.4, 2, clampf(h[1] / 0.18, 0.0, 1.0))
	_bolt.finish()


## A jagged ring round the body at height y (rounded rectangle, a little wobble every redraw).
func _loop(xf: Transform3D, hw: float, hl: float, y: float, width: float, alpha: float) -> void:
	var corner := minf(hw, hl) * 0.55
	var ring: Array[Vector3] = []
	var centres := [Vector2(hw - corner, -(hl - corner)), Vector2(hw - corner, hl - corner),
		Vector2(-(hw - corner), hl - corner), Vector2(-(hw - corner), -(hl - corner))]
	var start_angle := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in 4:
		for k in 3:
			var ang: float = start_angle[c] + k * (PI * 0.25)
			var cc: Vector2 = centres[c]
			ring.append(Vector3(cc.x + cos(ang) * corner, y, cc.y + sin(ang) * corner))
	var pts: Array[Vector3] = []
	for i in ring.size():
		var seg := Bolt.jagged(xf * ring[i], xf * ring[(i + 1) % ring.size()], 2, 0.22)
		if i > 0:
			seg.remove_at(0)
		pts.append_array(seg)
	# Break the ring in one or two places now and then: electricity, not a neon tube.
	if randf() < 0.5:
		var cut := randi_range(4, pts.size() - 5)
		_bolt.strand(pts.slice(0, cut), width, width, alpha)
		_bolt.strand(pts.slice(cut + 2), width, width, alpha)
	else:
		_bolt.strand(pts, width, width, alpha)


func _spawn_out() -> void:
	var sx := randf_range(-1, 1)
	var sz := randf_range(-1, 1)
	var from := Vector3(sx * size.x * 0.5, size.y * randf_range(0.3, 0.9), sz * size.z * 0.5)
	if car == null:
		return
	var out := car.global_basis * Vector3(sx, 0, sz)
	out.y = 0.0
	if out.length() < 0.1:
		out = car.global_basis.x
	var to := car.global_position + out.normalized() * randf_range(2.5, 5.0) + Vector3.UP * randf_range(-0.3, 2.2)
	_outs.append([from, to, OUT_LIFE * randf_range(0.7, 1.3)])
