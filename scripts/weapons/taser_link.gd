class_name TaserLink
extends Node3D
## Outlaw's special (owner's design, like Crazy 8): the player fires it whenever they like. It arcs to
## the nearest enemy in range in any direction and keeps hurting it while the link holds.
## Every press of the fire button during the link makes it stronger. The target can still drive:
## once it gets farther than break_range (or behind a wall) the connection is lost.
## Firing with nobody in range zaps the air and still spends the charge.

var owner_car: Vehicle
var target: Vehicle
var def := {}
var dps := 8.0
var mashes := 0

var _time := 0.0
var _pending := 0.0
var _fizzle := 0.0
var _spark := 0.0
var _core: ZigLine # white-hot centre of the bolt
var _glow: ZigLine # wide blue glow around it, same zigzag
var _forks: Array[ZigLine] = [] # short side branches
var _offsets: Array[Vector2] = [] # zigzag, re-rolled in short bursts so the bolt crackles
var _fork_at: Array[int] = []
var _fork_dirs: Array[Vector3] = []
var _refresh := 0.0
var _dark := false # a flicker: the arc drops out for an instant
var _light: OmniLight3D

const BOLT_SEGMENTS := 16


static func start(v: Vehicle, d: Dictionary) -> TaserLink:
	var link := TaserLink.new()
	link.owner_car = v
	link.def = d
	link.dps = d.get("dps", 8.0)
	link.target = find_victim(v, d.get("range", 25.0))
	v.get_parent().add_child(link)
	if link.target == null:
		link._fizzle = 0.35
		v.notice.emit(v, "NO TARGET IN RANGE")
	else:
		v.set_live_special(link)
	return link


## Nearest live enemy within range that the taser can see.
static func find_victim(v: Vehicle, reach: float) -> Vehicle:
	var best: Vehicle = null
	var best_d := reach
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == v or o.is_dead:
			continue
		var d := v.global_position.distance_to(o.global_position)
		if d <= best_d and _can_see(v, o):
			best_d = d
			best = o
	return best


static func _can_see(a: Vehicle, b: Vehicle) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a.aim_point() + Vector3.UP * 0.5, b.aim_point(), 1)
	return a.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ready() -> void:
	var core := MeshKit.emissive(Color(0.85, 0.95, 1.0), 9.0)
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(0.3, 0.55, 1.0, 0.45)
	_core = ZigLine.new()
	_core.material = core
	_core.segments = BOLT_SEGMENTS
	add_child(_core)
	_glow = ZigLine.new()
	_glow.material = glow
	_glow.segments = BOLT_SEGMENTS
	add_child(_glow)
	for k in 3:
		var f := ZigLine.new()
		f.material = core
		f.segments = 4
		add_child(f)
		_forks.append(f)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.7, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 9.0
	add_child(_light)
	_reroll()


## New zigzag: sharp alternating kinks across the line, plus where the side forks split off.
func _reroll() -> void:
	_offsets.clear()
	for i in BOLT_SEGMENTS + 1:
		var side := 1.0 if i % 2 == 0 else -1.0
		_offsets.append(Vector2(side * randf_range(0.35, 1.0), randf_range(-0.7, 0.7)))
	_fork_at.clear()
	_fork_dirs.clear()
	for k in _forks.size():
		_fork_at.append(randi_range(3, BOLT_SEGMENTS - 3))
		_fork_dirs.append(Vector3(randf_range(-1, 1), randf_range(-0.4, 1.0), randf_range(-1, 1)).normalized())
	_dark = randf() < 0.12


## Draws the arc from `from` to `to`; strength 0..1 makes it thicker and wilder.
func _draw_bolt(from: Vector3, to: Vector3, strength: float, delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.045
		_reroll()
	for z: ZigLine in [_core, _glow] + _forks:
		z.visible = not _dark
	if _dark:
		_light.light_energy = 0.5
		return
	var axis := to - from
	var length := axis.length()
	if length < 0.05:
		return
	var dir := axis / length
	var u := dir.cross(Vector3.UP)
	if u.length() < 0.1:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := dir.cross(u).normalized()
	var amp := clampf(length * 0.06, 0.25, 1.4) * (0.8 + strength * 0.6)
	var pts: Array[Vector3] = []
	for i in BOLT_SEGMENTS + 1:
		var t := float(i) / BOLT_SEGMENTS
		var p := from.lerp(to, t)
		if i > 0 and i < BOLT_SEGMENTS:
			var o := _offsets[i]
			p += (u * o.x + w * o.y) * amp * sqrt(sin(t * PI))
		pts.append(p)
	_core.draw_points(pts, 0.05 + strength * 0.05)
	_glow.draw_points(pts, 0.3 + strength * 0.25)
	for k in _forks.size():
		var start := pts[_fork_at[k]]
		var end := start + (_fork_dirs[k] + dir * 0.3).normalized() * randf_range(1.0, 2.6)
		var fork_pts: Array[Vector3] = []
		for j in 5:
			var p := start.lerp(end, j / 4.0)
			if j > 0 and j < 4:
				p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.25
			fork_pts.append(p)
		_forks[k].draw_points(fork_pts, 0.035)
	_light.light_energy = randf_range(2.0, 4.0) + strength * 4.0


## Called for each fire press while the link holds: mashing builds damage.
func fire_again() -> void:
	mashes += 1
	dps = minf(float(def.get("max_dps", 20.0)), dps + float(def.get("dps_per_mash", 1.5)))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_car):
		queue_free()
		return
	var from := owner_car.launch_point()
	if _fizzle > 0.0:
		_fizzle -= delta
		var ahead := from + owner_car.flat_forward() * 8.0 + Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
		_draw_bolt(from, ahead, 0.3, delta)
		_light.global_position = ahead
		if _fizzle <= 0.0:
			queue_free()
		return
	if owner_car.is_dead or owner_car.frozen_time > 0.0 or not is_instance_valid(target) or target.is_dead:
		_end(false)
		return
	var d := owner_car.global_position.distance_to(target.global_position)
	if d > float(def.get("break_range", 32.0)) or not _can_see(owner_car, target):
		_end(true)
		return
	_time += delta
	_pending += dps * delta
	if _pending >= 2.0:
		target.take_damage(_pending * WeaponData.DAMAGE_SCALE, owner_car)
		_pending = 0.0
	var to := target.aim_point()
	var strength := dps / float(def.get("max_dps", 20.0))
	_draw_bolt(from, to, strength, delta)
	_light.global_position = to
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.08
		FxKit.spark(get_parent(), to + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)), Vector3.UP)
		FxKit.spark(get_parent(), from, Vector3.UP)
	if _time >= float(def.get("duration", 3.0)):
		_end(false)


func _end(lost: bool) -> void:
	if _pending > 0.0 and is_instance_valid(target) and not target.is_dead:
		target.take_damage(_pending * WeaponData.DAMAGE_SCALE, owner_car)
	_pending = 0.0
	if is_instance_valid(owner_car):
		owner_car.set_live_special(null)
		if lost:
			owner_car.notice.emit(owner_car, "CONNECTION LOST")
	queue_free()
