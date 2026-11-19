class_name TaserLink
extends Node3D
## Outlaw's special (owner's design, like Crazy 8): the player fires it whenever they like. It arcs to
## the nearest enemy in range in any direction and keeps hurting it while the link holds.
## Every press of the fire button during the link makes it stronger. The target can still drive:
## once it gets farther than break_range (or behind a wall) the connection is lost.
## Firing with nobody in range spins the arc round the car (3 turns over the duration) and locks on to
## the first enemy that comes into range (owner, round 9).

var owner_car: Vehicle
var target: Vehicle
var def := {}
var dps := 8.0
var mashes := 0

var _time := 0.0
var _pending := 0.0
var _searching := false # fired with nobody in range: the arc spins round the car looking (round 9)
var _scan_t := 0.0
var _blocked := 0.0 # how long the view has been fully blocked (a short grace before the link breaks)
var _hum: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _spark := 0.0
var _bolt: Bolt
var _main: Array[Vector3] = [] # this flash's path, kept for the afterimage
var _ghost: Array[Vector3] = [] # the previous flash, drawn faint
var _refresh := 0.0
var _dark := false # a flicker: the core drops out for an instant
var _light: OmniLight3D

const SEARCH_RADIUS := 9.0 # the spinning arc's reach while it looks for a target
const SEARCH_TURNS := 3.0 # turns round the car over the whole duration (owner, round 9)
const LOCK_MIN := 1.2 # a target caught late in the spin still gets at least this long
const LOS_GRACE := 0.4 # seconds fully out of sight before the connection is lost
const JOLT_HEIGHT := 1.3 # m the victim is thrown up when the arc first bites


## Owner, round 10: the moment the arc connects, the shock throws the victim into a hop that upsets
## it (wheels off the ground, a twist, the steering twitching as it lands), so it cannot just turbo
## away, and Outlaw gets her chance to mash. Once per connection, never while the link holds.
func _connect_jolt() -> void:
	if not is_instance_valid(target) or target.is_dead:
		return
	var up := sqrt(2.0 * Vehicle.GRAVITY * JOLT_HEIGHT)
	target.blast_knock(Vector3.UP * up - target.linear_velocity * Vector3(0.35, 0.0, 0.35), 0.0, false)
	var b := target.global_basis
	target.angular_velocity += b.z * randf_range(1.6, 2.4) * (1.0 if randf() < 0.5 else -1.0) + b.x * randf_range(-1.0, 1.0) + Vector3.UP * randf_range(-1.4, 1.4)
	target.wobble(1.0)
	target.hit_react(target.global_position - owner_car.global_position, 12.0)
	FxKit.spark(get_parent(), target.aim_point(), Vector3.UP)
	GameFeel.flash(get_parent(), target.aim_point(), 2.2, Color(0.6, 0.8, 1.0), 0.08)
	if target.is_player or owner_car.is_player:
		GameFeel.hitstop(get_tree(), 0.04, 0.05)
		GameFeel.shake(target.global_position, 0.25)


static func start(v: Vehicle, d: Dictionary) -> TaserLink:
	var link := TaserLink.new()
	link.owner_car = v
	link.def = d
	link.dps = d.get("dps", 8.0)
	link.target = find_victim(v, d.get("range", 25.0))
	v.get_parent().add_child(link)
	v.set_live_special(link)
	# Owner, round 10: the siren wails for as long as the attack is on (it used to play once, 1.8 s,
	# and die before the 3 s were up). The crackle runs under it.
	link._siren = GameFeel.loop("special_outlaw", v, 0.0, 18.0)
	if link._siren:
		link._siren.play()
	link._hum = GameFeel.loop("taser_loop", v, -8.0, 14.0) # the arc crackles while it lives
	if link._hum:
		link._hum.play()
	if link.target:
		link._connect_jolt()
	if link.target == null:
		link._searching = true # owner, round 9: no target? the arc spins round the car, hunting
		if v.is_player:
			v.notice.emit(v, "SEARCHING...")
	return link


## Nearest live enemy within range that the taser can see.
static func find_victim(v: Vehicle, reach: float) -> Vehicle:
	var best: Vehicle = null
	var best_d := reach
	for node in v.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == v or o.is_dead or o.is_hidden():
			continue
		var d := v.global_position.distance_to(o.global_position)
		if d <= best_d and _can_see(v, o):
			best_d = d
			best = o
	return best


## Owner, round 9: only something that hides the whole car breaks the link (a real wall, a container,
## a second floor), never a kerb-high kicker, a ramp's side, glass or a fence. Three sight lines at
## different heights; any one getting through is enough. Glass, props, palms and fences don't count.
static func _can_see(a: Vehicle, b: Vehicle) -> bool:
	var space := a.get_world_3d().direct_space_state
	for h: float in [0.5, 2.5, 4.5]:
		if _clear(space, a.aim_point() + Vector3.UP * h, b.aim_point() + Vector3.UP * h, [a.get_rid(), b.get_rid()]):
			return true
	return false


static func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, skip: Array) -> bool:
	var exclude: Array[RID] = []
	for r: RID in skip:
		exclude.append(r)
	for tries in 5:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c: Object = hit.collider
		if c is Breakable or (c is Node and (c as Node).is_in_group(&"see_through")):
			exclude.append((c as CollisionObject3D).get_rid())
			continue
		return false
	return true


func _ready() -> void:
	_bolt = Bolt.new()
	_bolt.tint = Color(0.35, 0.62, 1.0)
	add_child(_bolt)
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
	if not is_instance_valid(owner_car) or owner_car.is_dead or owner_car.frozen_time > 0.0:
		_end(false)
		return
	var from := owner_car.launch_point()
	_time += delta
	var duration := float(def.get("duration", 3.0))
	var strength := dps / float(def.get("max_dps", 20.0))
	_refresh -= delta
	var reroll := _refresh <= 0.0
	if reroll:
		_refresh = 0.05
		_dark = randf() < 0.1
	if _searching:
		# The arc sweeps round the car, its end skipping along the ground, until someone is in range.
		var a := _time / duration * SEARCH_TURNS * TAU
		var fwd := owner_car.flat_forward()
		var dir := fwd.rotated(Vector3.UP, a)
		var tip := from + dir * SEARCH_RADIUS + Vector3.UP * 3.0
		var g := Specials.ground_below(get_parent(), tip)
		_draw(from, g + Vector3.UP * 0.1, 0.35, reroll, false)
		_light.global_position = g + Vector3.UP
		_spark -= delta
		if _spark <= 0.0:
			_spark = 0.12 if GraphicsSettings.high else 0.25
			FxKit.spark(get_parent(), g, Vector3.UP)
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.1
			target = find_victim(owner_car, float(def.get("range", 25.0)))
			if target:
				_searching = false
				_time = minf(_time, duration - LOCK_MIN)
				_connect_jolt()
				if owner_car.is_player:
					owner_car.notice.emit(owner_car, "LOCKED ON")
		if _time >= duration:
			_end(false)
		return
	if not is_instance_valid(target) or target.is_dead:
		_end(false)
		return
	var d := owner_car.global_position.distance_to(target.global_position)
	if d > float(def.get("break_range", 32.0)):
		_end(true)
		return
	if _can_see(owner_car, target):
		_blocked = 0.0
	else:
		_blocked += delta
		if _blocked > LOS_GRACE:
			_end(true)
			return
	_pending += dps * delta
	if _pending >= 2.0:
		target.take_damage(_pending * WeaponData.DAMAGE_SCALE, owner_car)
		_pending = 0.0
	var to := target.aim_point()
	_draw(from, to, strength, reroll, true)
	_light.global_position = to
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.08 if GraphicsSettings.high else 0.2 # each spark burst is a new node: fewer on LOW
		FxKit.spark(get_parent(), to + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)), Vector3.UP)
		if GraphicsSettings.high:
			FxKit.spark(get_parent(), from, Vector3.UP)
	if _time >= duration:
		_end(false)


## The arc this frame: a new jagged path every 50 ms (the old one lingers faintly), branches, a hot
## star where it lands and, on a car, small arcs crawling over its body.
func _draw(from: Vector3, to: Vector3, strength: float, reroll: bool, on_car: bool) -> void:
	_bolt.begin()
	if not _ghost.is_empty():
		_bolt.strand(_ghost, 0.05, 0.02, 0.3)
	if reroll or _main.is_empty():
		_ghost = _main
		_main = Bolt.jagged(from, to, 4, 0.2 + 0.08 * strength)
	else: # keep the shape but follow the ends as both cars move
		_main[0] = from
		_main[_main.size() - 1] = to
	if not _dark:
		var w0 := 0.07 + 0.08 * strength
		_bolt.strand(_main, w0, w0 * 0.4)
		for k in 2 + int(strength * 2.0):
			var i := randi_range(2, _main.size() - 4)
			var off := ((_main[i + 1] - _main[i]).normalized() + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.9), randf_range(-1, 1))).normalized()
			_bolt.strand(Bolt.jagged(_main[i], _main[i] + off * randf_range(0.8, 2.2), 2, 0.3), w0 * 0.5, 0.004, 0.8)
	# The hot star where it bites.
	for k in 4:
		var ray := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized() * randf_range(0.4, 0.9)
		_bolt.strand(Bolt.jagged(to, to + ray, 1, 0.3), 0.06, 0.004, 0.9)
	if on_car and is_instance_valid(target):
		var size: Vector3 = target.stats.get("size", Vector3(2.2, 1.8, 5.0))
		var xf := target.global_transform
		for k in 3: # electricity crawling over the hit car
			var p := xf * Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.4, 1.0) * size.y, randf_range(-0.5, 0.5) * size.z)
			var q := xf * Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.4, 1.0) * size.y, randf_range(-0.5, 0.5) * size.z)
			_bolt.strand(Bolt.jagged(p, q, 2, 0.35), 0.035, 0.01, 0.75)
	_bolt.finish()
	_light.light_energy = 0.5 if _dark else randf_range(2.0, 4.0) + strength * 4.0


## Torn off from outside (Axel's Crowd Controller breaks every grab on him).
func break_link() -> void:
	_end(true)


func _end(lost: bool) -> void:
	if _pending > 0.0 and is_instance_valid(target) and not target.is_dead:
		target.take_damage(_pending * WeaponData.DAMAGE_SCALE, owner_car)
	_pending = 0.0
	if is_instance_valid(_hum):
		_hum.queue_free()
	if is_instance_valid(_siren): # the wail winds down instead of cutting off
		var siren := _siren
		var tw := siren.create_tween().set_parallel(true)
		tw.tween_property(siren, "volume_db", -40.0, 0.35)
		tw.tween_property(siren, "pitch_scale", 0.6, 0.35)
		tw.chain().tween_callback(siren.queue_free)
	if is_instance_valid(owner_car):
		GameFeel.play("taser_fizzle", owner_car.launch_point(), owner_car.get_parent(), -6.0)
		if owner_car.live_special() == self:
			owner_car.set_live_special(null)
		if lost:
			owner_car.notice.emit(owner_car, "CONNECTION LOST")
	queue_free()
