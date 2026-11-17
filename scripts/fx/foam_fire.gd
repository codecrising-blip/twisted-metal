class_name FoamFire
extends Node3D
## The game's fire (round 18, the owner's pick of four looks from his TMB clips: "hair strands"): a foamy
## heap of flame puffs, each a soft blob full of fine strands racing up (foam_fire.gdshader). The puffs
## live in the world: each is born somewhere in `box` (this node's space, so a falling palm or a lying
## body carries its emitter with it) with `inherit` of the emitter's own velocity, rises and loses that
## velocity at `drag` per second. So a burning car's fire streams back as it drives and swings out through
## its turns by itself, a running driver trails flames, and a fire standing still is a rounded rolling heap.
## A puff is drawn from its first moment with its root at its birth point, so the fire grows out of the
## surface it burns on (round 18: it floated above the hood). All puffs are one ArrayMesh, one draw call.
## Switch it with `on`; `level` (0..1) scales how big and busy it burns.

const SHADER := preload("res://scripts/fx/foam_fire.gdshader")
const MAX_PUFFS := 140

var on := false
var level := 1.0
var box := Vector3(0.8, 0.05, 0.6) # half extents of where puffs are born
var rate := 70.0 # puffs per second at full strength
var life := 0.75
var size := 1.15 # metres across a puff when born (it grows)
var rise := 2.2 # m/s upwards
var inherit := 0.5 # share of the emitter's velocity a puff keeps when born
var drag := 2.2 # how fast a puff forgets that velocity
var rise_in := 3.0 # strength per second while flaring up
var die_out := 1.0 # ...and while dying down
var glow := -1.0 # >= 0: this fire's own blend (1 = plain see-through, no light added); small fires seen
# against the bright sky (Sweet Bot's cone) need more body or they wash out

var _s := 0.0
var _acc := 0.0
var _last := Vector3.INF
var _ev := Vector3.ZERO
var _mesh: MeshInstance3D
var _am: ArrayMesh
var _mat: ShaderMaterial
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
static var _uvs := PackedVector2Array()
static var _idx := PackedInt32Array()
static var _shared_mat: ShaderMaterial


func _ready() -> void:
	if _uvs.is_empty(): # the corner UVs and triangles of every possible puff, built once
		for i in MAX_PUFFS:
			_uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			var b := i * 4
			_idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = SHADER
	_mat = _shared_mat
	if glow >= 0.0:
		_mat = _shared_mat.duplicate() as ShaderMaterial
		_mat.set_shader_parameter("glow", glow)
	_am = ArrayMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _am
	_mesh.top_level = true # the puffs are in world space
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mesh.global_transform = Transform3D.IDENTITY


## True while flames (or their last puffs) are showing.
func burning() -> bool:
	return _s > 0.01 or not _pos.is_empty()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var target := level if on else 0.0
	_s = move_toward(_s, target, (rise_in if target > _s else die_out) * delta)
	var p := global_position
	if _last != Vector3.INF:
		_ev = _ev.lerp((p - _last) / delta, 0.5) # the emitter's own velocity, smoothed a little
	_last = p
	if _s <= 0.0 and _pos.is_empty():
		if _am.get_surface_count() > 0:
			_am.clear_surfaces()
		return
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
		_size.append(size * randf_range(0.75, 1.25) * lerpf(0.55, 1.0, _s))
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
		v = v.lerp(Vector3(0.0, v.y, 0.0), k)
		v.y += 1.4 * delta # hot air keeps lifting
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	_build()


func _build() -> void:
	_am.clear_surfaces()
	var n := _pos.size()
	var cam := get_viewport().get_camera_3d()
	if n == 0 or cam == null:
		return
	var right := cam.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	_verts.resize(n * 4)
	_cols.resize(n * 4)
	for i in n:
		var t := _age[i] / _life[i]
		var sz := _size[i] * (0.6 + 0.9 * sqrt(t))
		var fade := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.55, 1.0, t))
		# The quad's lower edge sits a little under the birth point, so a young puff's root is ON the
		# surface it was born on (the blob's soft bottom starts about a quarter of the way up).
		var base := _pos[i] - Vector3(0.0, sz * 0.22, 0.0)
		var rx := right * (sz * 0.5)
		var top := Vector3(0.0, sz * 1.2, 0.0)
		var j := i * 4
		_verts[j] = base - rx
		_verts[j + 1] = base + rx
		_verts[j + 2] = base + rx + top
		_verts[j + 3] = base - rx + top
		var c := Color(t, _seed[i], 0.0, fade)
		_cols[j] = c
		_cols[j + 1] = c
		_cols[j + 2] = c
		_cols[j + 3] = c
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_TEX_UV] = _uvs.slice(0, n * 4)
	arrays[Mesh.ARRAY_INDEX] = _idx.slice(0, n * 6)
	_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_am.surface_set_material(0, _mat)


## A car's engine fire: on the engine cover at the front (Roster "hood": height, z), never over the whole
## car and never inside it (owner, round 18). A child of the car's visual, so it hides with it.
static func on_hood(car: Node3D, stats: Dictionary) -> FoamFire:
	var f := FoamFire.new()
	var size3: Vector3 = stats.get("size", Vector3(2.2, 1.6, 5.0))
	var hood: Vector2 = stats.get("hood", Vector2(size3.y * 0.55, -size3.z * 0.3))
	f.position = Vector3(0.0, hood.x - 0.14, hood.y)
	f.box = Vector3(size3.x * 0.32, 0.03, 0.55)
	# Puffs keep most of the car's speed, so at speed the fire trails about a car length behind (the TMB
	# clips), not a long red wall; the rest still swings out through the turns.
	f.inherit = 0.8
	f.drag = 1.2
	f.life = 0.6
	car.add_child(f)
	return f


## The fire where a car blew apart: a rounded heap the size of the car, on the ground.
static func pyre(parent: Node3D, car_size: Vector3) -> FoamFire:
	var f := FoamFire.new()
	f.box = Vector3(car_size.x * 0.4, 0.05, car_size.z * 0.38)
	f.position = Vector3(0.0, 0.05, 0.0)
	f.rate = 120.0
	f.life = 1.0
	f.size = 1.7
	f.rise = 2.3
	f.rise_in = 6.0
	f.die_out = 0.35 # burns down over about three seconds
	parent.add_child(f)
	return f
