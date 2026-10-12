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
var _bolt: ZigLine
var _bolt2: ZigLine
var _light: OmniLight3D


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
	var mat := MeshKit.emissive(Color(0.6, 0.8, 1.0), 6.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt = ZigLine.new()
	_bolt.material = mat
	_bolt.segments = 12
	add_child(_bolt)
	_bolt2 = ZigLine.new()
	_bolt2.material = mat
	_bolt2.segments = 8
	add_child(_bolt2)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.7, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 9.0
	add_child(_light)


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
		_bolt.draw(from, ahead, 0.8)
		_bolt2.visible = false
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
	_bolt.draw(from, to, 0.35 + strength * 0.4, 0.0, 0.06 + strength * 0.1)
	_bolt2.visible = true
	_bolt2.draw(from, to, 0.6, 0.0, 0.04)
	_light.global_position = to
	_light.light_energy = 2.0 + strength * 4.0
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.12
		FxKit.spark(get_parent(), to + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)), Vector3.UP)
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
