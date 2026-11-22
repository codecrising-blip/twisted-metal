class_name FlameJet
extends Node3D
## Thumper's Megafire (round 28, design 01 ch 9): while fire is held, a jet of the game's own fire (FoamFire,
## the owner's "hair strands") roars out from under the hood. Every TICK s every car inside the cone (range
## m, +-cone degrees, widened by the car's size, not behind a wall) takes dps x TICK and is set burning;
## palms and props in it burn too, and a running sinner in it is burnt down. Thumper's fuel tank (Vehicle.fuel)
## drains while it burns. backfire() is his rear attack: one short burst out of the back.

const TICK := 0.1

var car: Vehicle
var def: Dictionary
var _fire: FoamFire
var _core: FoamFire
var _snd: AudioStreamPlayer3D
var _light: OmniLight3D
var _t := 0.0
var _on := false


static func attach(v: Vehicle) -> FlameJet:
	var j := FlameJet.new()
	j.car = v
	j.def = WeaponData.get_def(v.special_id)
	var size: Vector3 = v.stats.get("size", Vector3(2.3, 1.5, 5.8))
	j.position = v.model.get_meta("nozzle", Vector3(0, 0.65, -size.z * 0.5 - 0.15))
	v.model.add_child(j)
	return j


func _ready() -> void:
	var reach := float(def.get("range", 14.0))
	_fire = _jet(reach * 2.1, 0.22, 1.0, 1.0)
	_core = _jet(reach * 1.5, 0.1, 0.55, 0.6)
	_snd = GameFeel.loop("fire_loop", self, 2.0, 14.0)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.6, -5.0)
	_light.add_to_group(GraphicsSettings.EXTRA_LIGHT_GROUP)
	_light.visible = GraphicsSettings.high
	add_child(_light)


## One stream of puffs shot forward: speed x drag decides how far it reaches (~speed / drag metres).
func _jet(speed: float, spread: float, size: float, life: float) -> FoamFire:
	var f := FoamFire.new()
	f.box = Vector3(0.12, 0.12, 0.08)
	f.rate = 110.0
	f.life = 0.55 * life
	f.size = 0.75 * size
	f.rise = 0.6
	f.inherit = 1.0
	f.drag = 2.0
	f.jet = speed
	f.jet_spread = spread
	f.rise_in = 12.0
	f.die_out = 6.0
	add_child(f)
	return f


func set_on(on: bool) -> void:
	_on = on
	_fire.on = on
	_core.on = on
	if on:
		_t = 0.0
		GameFeel.play("special_thumper", global_position, car, float(def.get("sound_db", 0.0)) - 2.0, randf_range(0.95, 1.05))
		if _snd and not _snd.playing:
			_snd.play()
	elif _snd:
		_snd.stop()


func _physics_process(delta: float) -> void:
	_light.light_energy = move_toward(_light.light_energy, 3.0 if _on else 0.0, delta * 12.0)
	if not _on or not is_instance_valid(car) or car.is_dead:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	scorch(car, global_position, car.level_forward(), float(def.get("range", 14.0)), float(def.get("cone", 12.0)),
		float(def.get("dps", 12.0)) * TICK, float(def.get("burn", 3.0)))
	if car.is_player and GameFeel.camera:
		GameFeel.camera.add_shake(0.04)


## Everything in a cone of fire: cars (not behind walls), props, running sinners.
static func scorch(by: Vehicle, origin: Vector3, fwd: Vector3, reach: float, cone_deg: float, damage: float, burn: float) -> void:
	var world := by.get_parent()
	var space := by.get_world_3d().direct_space_state
	var cone := deg_to_rad(cone_deg)
	for node in by.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == by or o.is_dead:
			continue
		var to := o.aim_point() - origin
		var d := to.length()
		var size: Vector3 = o.stats.get("size", Vector3(2.2, 1.8, 5.0))
		if d > reach + size.z * 0.4 or d < 0.01:
			continue
		if fwd.angle_to(to / d) > cone + atan2(size.x * 0.6, d):
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, o.aim_point(), 1)
		q.exclude = [by.get_rid(), o.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue # the flame doesn't go through walls
		o.take_damage(damage * WeaponData.DAMAGE_SCALE, by)
		o.ignite(burn, by)
		o.hit_react(to, damage)
	for node in by.get_tree().get_nodes_in_group(&"breakables"):
		var b := node as Breakable
		if b and not b.is_broken and randf() < 0.3:
			var tb := b.global_position + Vector3.UP - origin
			if tb.length() < reach and fwd.angle_to(tb.normalized()) < cone * 1.5:
				b.weapon_hit(damage * 2.0, by, origin, true)
	for node in by.get_tree().get_nodes_in_group(&"sinners"):
		var s := node as Node3D
		var ts := s.global_position + Vector3.UP - origin
		if ts.length() < reach and fwd.angle_to(ts.normalized()) < cone * 1.6:
			s.call("projectile_hit", damage * 2.0, by)


## Backfire (Thumper's rear attack): a short burst of flame out of the back, 8 m, damage + burning, once.
static func backfire(v: Vehicle) -> void:
	var d := WeaponData.get_def("backfire")
	var size: Vector3 = v.stats.get("size", Vector3(2.3, 1.5, 5.8))
	var holder := Node3D.new()
	holder.position = Vector3(0, 0.6, size.z * 0.5 + 0.2)
	holder.rotation.y = PI # the jet shoots along -Z: turned round, out of the back
	v.model.add_child(holder)
	var f := FoamFire.new()
	f.box = Vector3(0.3, 0.15, 0.1)
	f.rate = 140.0
	f.life = 0.45
	f.size = 0.9
	f.rise = 0.6
	f.inherit = 1.0
	f.drag = 2.4
	f.jet = float(d.get("range", 8.0)) * 2.3
	f.jet_spread = 0.35
	f.rise_in = 20.0
	f.die_out = 4.0
	f.on = true
	holder.add_child(f)
	GameFeel.play("special_thumper", holder.global_position, v, 0.0, 1.15)
	GameFeel.play("launch_fire", holder.global_position, v, -4.0, 0.7)
	scorch(v, v.global_position + v.global_basis.z * (size.z * 0.5) + Vector3.UP * 0.8, -v.level_forward(),
		float(d.get("range", 8.0)), float(d.get("cone", 25.0)), float(d.get("damage", 12.0)), float(d.get("burn", 4.0)))
	var tree := v.get_tree()
	tree.create_timer(float(d.get("time", 0.7)), false).timeout.connect(func() -> void:
		if is_instance_valid(f):
			f.on = false)
	tree.create_timer(2.5, false).timeout.connect(func() -> void:
		if is_instance_valid(holder):
			holder.queue_free())
