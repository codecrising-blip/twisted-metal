class_name FoamFire
extends Node3D
## Fire as a foam of streaky flame puffs (round 18, from the owner's TMB clips). The puffs live in the
## world: each is born somewhere in `box` (this node's space) carrying `inherit` of the emitter's own
## velocity, rises, and forgets that velocity at `drag` per second. So a car's fire streams back as it
## drives and swings out through its turns by itself, and a fire that stands still is a rounded, rolling
## heap. All puffs are drawn in one ImmediateMesh (one draw call), each a camera-facing upright quad
## textured by foam_fire.gdshader. Switch it with `on`; `level` scales how big and busy it burns.
## Four looks for the owner to pick from (LOOKS); `smoke` adds a dark column (a second FoamFire).

const SHADER := preload("res://scripts/fx/foam_fire.gdshader")
const MAX_PUFFS := 160

const LOOKS := [
	{"name": "1  CROSSED STRANDS", "pattern": 0, "glow": 0.6, "deep": Color(0.55, 0.03, 0.0), "mid": Color(0.95, 0.22, 0.03), "hot": Color(1.0, 0.6, 0.15)},
	{"name": "2  HAIR STRANDS", "pattern": 1, "glow": 0.55, "deep": Color(0.6, 0.02, 0.0), "mid": Color(0.95, 0.15, 0.03), "hot": Color(1.0, 0.45, 0.1)},
	{"name": "3  CROSSED + BLACK SMOKE", "pattern": 0, "glow": 0.6, "deep": Color(0.55, 0.03, 0.0), "mid": Color(0.95, 0.22, 0.03), "hot": Color(1.0, 0.6, 0.15), "smoke": true},
	{"name": "4  HOT FOAM", "pattern": 0, "glow": 0.42, "deep": Color(0.78, 0.12, 0.0), "mid": Color(1.0, 0.45, 0.05), "hot": Color(1.0, 0.86, 0.48)},
]

var look := 0
var on := false
var level := 1.0
var box := Vector3(0.8, 0.1, 0.6) # half extents of where puffs are born
var rate := 70.0 # puffs per second at full strength
var life := 0.75
var size := 1.15 # metres across a puff when born (it grows)
var rise := 2.2 # m/s upwards
var inherit := 0.5 # share of the emitter's velocity a puff keeps when born
var drag := 2.2 # how fast a puff forgets that velocity
var is_smoke := false
var rise_in := 3.0 # strength per second while flaring up
var die_out := 1.0 # ...and while dying down

var _s := 0.0
var _acc := 0.0
var _last := Vector3.INF
var _ev := Vector3.ZERO
var _mesh: MeshInstance3D
var _im: ImmediateMesh
var _mat: ShaderMaterial
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _smoke: FoamFire


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	_mesh.top_level = true # the puffs are in world space
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 16.0
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var l: Dictionary = LOOKS[look]
	if is_smoke:
		_mat.set_shader_parameter("smoke", 1.0)
	else:
		_mat.set_shader_parameter("pattern", int(l.pattern))
		_mat.set_shader_parameter("glow", float(l.glow))
		_mat.set_shader_parameter("deep", l.deep)
		_mat.set_shader_parameter("mid", l.mid)
		_mat.set_shader_parameter("hot", l.hot)
		if l.get("smoke", false):
			_smoke = FoamFire.new()
			_smoke.is_smoke = true
			_smoke.box = box * Vector3(0.7, 1.0, 0.7)
			_smoke.position = Vector3(0.0, size * 1.1, 0.0)
			_smoke.rate = rate * 0.22
			_smoke.life = 2.6
			_smoke.size = size * 1.4
			_smoke.rise = 3.2
			_smoke.inherit = inherit * 0.6
			_smoke.drag = drag * 0.6
			add_child(_smoke)
	add_child(_mesh)
	_mesh.global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var target := level if on else 0.0
	_s = move_toward(_s, target, (rise_in if target > _s else die_out) * delta)
	if _smoke:
		_smoke.on = on
		_smoke.level = level
	var p := global_position
	if _last != Vector3.INF:
		_ev = _ev.lerp((p - _last) / delta, 0.5) # the emitter's own velocity, smoothed a little
	_last = p
	# Born...
	_acc += rate * _s * delta
	var basis := global_basis
	while _acc >= 1.0 and _pos.size() < MAX_PUFFS:
		_acc -= 1.0
		var local := Vector3(randf_range(-box.x, box.x), randf_range(-box.y, box.y), randf_range(-box.z, box.z))
		_pos.append(p + basis * local)
		var jitter := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		_vel.append(_ev * inherit + Vector3(0.0, rise * randf_range(0.75, 1.25), 0.0) + jitter)
		_age.append(0.0)
		_life.append(life * randf_range(0.7, 1.3) * lerpf(0.75, 1.0, _s))
		_size.append(size * randf_range(0.75, 1.25) * lerpf(0.6, 1.0, _s))
		_seed.append(randf())
	_acc = minf(_acc, 1.0)
	# ...rise, lose the speed they were born with, die.
	var k := 1.0 - exp(-drag * delta)
	var i := 0
	while i < _pos.size():
		_age[i] += delta
		if _age[i] >= _life[i]:
			var last := _pos.size() - 1
			_pos[i] = _pos[last]
			_vel[i] = _vel[last]
			_age[i] = _age[last]
			_life[i] = _life[last]
			_size[i] = _size[last]
			_seed[i] = _seed[last]
			_pos.resize(last)
			_vel.resize(last)
			_age.resize(last)
			_life.resize(last)
			_size.resize(last)
			_seed.resize(last)
			continue
		var v := _vel[i]
		var still := Vector3(0.0, v.y, 0.0)
		v = v.lerp(still, k)
		v.y += (0.6 if is_smoke else 1.4) * delta # hot air keeps lifting
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	_draw()


func _draw() -> void:
	_im.clear_surfaces()
	if _pos.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var right := cam.global_basis.x
	right = Vector3(right.x, 0.0, right.z).normalized() if Vector3(right.x, 0.0, right.z).length() > 0.01 else Vector3.RIGHT
	var up := Vector3.UP
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for i in _pos.size():
		var t := _age[i] / _life[i]
		var sz := _size[i] * (0.6 + 0.9 * sqrt(t))
		var fade := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.55, 1.0, t))
		var c := _pos[i] + up * sz * 0.35 # the puff's lower part sits on its point
		var rx := right * sz * 0.5
		var uy := up * sz * 0.6
		var colr := Color(t, _seed[i], 0.0, fade)
		_quad(c - rx - uy, c + rx - uy, c + rx + uy, c - rx + uy, colr)
	_im.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, colr: Color) -> void:
	for v in [[a, Vector2(0, 1)], [b, Vector2(1, 1)], [c, Vector2(1, 0)], [a, Vector2(0, 1)], [c, Vector2(1, 0)], [d, Vector2(0, 0)]]:
		_im.surface_set_color(colr)
		_im.surface_set_uv(v[1])
		_im.surface_add_vertex(v[0])


## A fire on a car's engine cover (Roster "hood": height, z), in look `l`.
static func on_hood(car: Vehicle, l: int) -> FoamFire:
	var f := FoamFire.new()
	f.look = l
	var size3: Vector3 = car.stats.get("size", Vector3(2.2, 1.6, 5.0))
	var hood: Vector2 = car.stats.get("hood", Vector2(size3.y * 0.55, -size3.z * 0.3))
	f.position = Vector3(0.0, hood.x + 0.1, hood.y)
	f.box = Vector3(size3.x * 0.32, 0.08, 0.55)
	car.get_node("Visual").add_child(f)
	return f


## A fire spot on the ground where a car blew apart: a rounded heap the size of the car.
static func spot(parent: Node3D, at: Vector3, car_size: Vector3, l: int) -> FoamFire:
	var f := FoamFire.new()
	f.look = l
	f.box = Vector3(car_size.x * 0.4, 0.15, car_size.z * 0.38)
	f.rate = 130.0
	f.life = 1.0
	f.size = 1.7
	f.rise = 2.3
	parent.add_child(f)
	f.global_position = at
	return f
