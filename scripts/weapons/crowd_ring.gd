class_name CrowdRing
extends Node3D
## Axel's Crowd Controller (design 01, Axel): "windup" seconds of sparks off both tyres while Axel rises a
## little (the warning: jump it or get out of range), then a ring of electric fire races out along the
## ground to "radius" m in "spread" s. Each car it meets takes "damage" near Axel down to "edge_damage"
## at the rim, is thrown hard away from him (a super heavy only takes the damage) and burns. Mines inside
## the ring die harmlessly, and any grab on Axel breaks (a taser link, a wheel clamp, a chain bomb on him).
## A car more than 1.6 m off the ground (jumping) when the ring passes is missed.

const LIFT := 3.0 # m/s Axel is lifted during the windup

var owner_car: Vehicle
var def := {}

var _t := 0.0
var _fired := false
var _hit := {}
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _bolt: Bolt
var _spark_t := 0.0


static func start(v: Vehicle, d: Dictionary) -> CrowdRing:
	var r := CrowdRing.new()
	r.owner_car = v
	r.def = d
	v.add_child(r) # rides with Axel during the windup, then stays where it went off
	GameFeel.play("special_axel", v.global_position + Vector3.UP, v, 0.0, 1.0, true)
	if v.is_on_floor():
		v.push(Vector3.UP * LIFT)
	return r


func _ready() -> void:
	_bolt = Bolt.new()
	add_child(_bolt)


func _physics_process(delta: float) -> void:
	_t += delta
	var windup := float(def.get("windup", 0.4))
	if not is_instance_valid(owner_car) or (owner_car.is_dead and not _fired):
		queue_free()
		return
	if not _fired:
		_windup_fx(delta)
		if _t >= windup:
			_fire()
		return
	var spread := float(def.get("spread", 0.35))
	var k := clampf((_t - windup) / spread, 0.0, 1.0)
	var radius := float(def.get("radius", 12.0)) * k
	_reach(radius)
	_ring.scale = Vector3(maxf(radius, 0.5), 1.0, maxf(radius, 0.5))
	_ring_mat.albedo_color.a = 0.85 * (1.0 - k * k)
	_bolt.begin()
	if k < 1.0:
		for i in 10: # lightning crawling along the front of the ring
			var a := TAU * (i + randf()) / 10.0
			var p := _ring.global_position + Vector3(cos(a), 0.0, sin(a)) * radius
			var q := _ring.global_position + Vector3(cos(a + 0.35), 0.0, sin(a + 0.35)) * radius
			_bolt.strand(Bolt.jagged(p + Vector3.UP * 0.2, q + Vector3.UP * randf_range(0.2, 1.4), 3, 0.45), 0.09, 0.03, 0.9)
	_bolt.finish()
	if _t >= windup + spread + 0.25:
		queue_free()


## The warning: sparks off both tyres where they meet the ground, a crackle running up the spokes.
func _windup_fx(delta: float) -> void:
	_spark_t -= delta
	_bolt.begin()
	var size: Vector3 = owner_car.stats.get("size", Vector3(3.8, 2.8, 2.8))
	for sx in [-1.0, 1.0]:
		var foot := owner_car.global_transform * Vector3(sx * size.x * 0.4, 0.15, 0.0)
		var hub := owner_car.global_transform * Vector3(sx * size.x * 0.4, size.y * 0.5, 0.0)
		_bolt.strand(Bolt.jagged(foot, hub, 3, 0.5), 0.07, 0.02, 0.8)
		if _spark_t <= 0.0:
			FxKit.spark(owner_car.get_parent(), foot, (Vector3.UP + owner_car.global_basis.x * sx).normalized())
	if _spark_t <= 0.0:
		_spark_t = 0.06
	_bolt.finish()


func _fire() -> void:
	_fired = true
	var world := owner_car.get_parent()
	var at := Specials.ground_below(world, owner_car.global_position + Vector3.UP)
	# The ring stays where it went off, it doesn't follow Axel.
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, at)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(1.0, 0.55, 0.25, 0.85)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 4
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.global_position = at + Vector3.UP * 0.25
	GameFeel.flash(world, at + Vector3.UP, 3.0, Color(0.7, 0.85, 1.0), 0.12)
	GameFeel.shockwave(world, at, float(def.get("radius", 12.0)) * 1.15, Color(0.45, 0.7, 1.0))
	GameFeel.shake(at, 0.5)
	GameFeel.play("lightning", at, world, -4.0, 1.2, true)
	FxKit.dust_ring(world, at, 2.0)
	_break_grabs()
	_clear_mines(at)


func _reach(radius: float) -> void:
	var centre := _ring.global_position
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == null or o == owner_car or o.is_dead or _hit.has(o):
			continue
		var rel := o.global_position - centre
		var flat := Vector2(rel.x, rel.z).length()
		if flat > radius + o.stats.get("size", Vector3(2, 2, 5)).z * 0.3:
			continue
		_hit[o] = true
		if rel.y > 1.6 and not o.is_on_floor():
			continue # jumped it (the counter)
		var t := clampf(flat / float(def.get("radius", 12.0)), 0.0, 1.0)
		var dmg := lerpf(float(def.get("damage", 16.0)), float(def.get("edge_damage", 8.0)), t) * WeaponData.DAMAGE_SCALE
		o.take_damage(dmg, owner_car)
		var away := Vector3(rel.x, 0.0, rel.z)
		away = away.normalized() if away.length() > 0.3 else o.flat_forward()
		o.hit_react(away, dmg)
		if o.stats.get("class", "medium") != "super":
			var push := float(def.get("push", 20.0)) * (1.0 - 0.5 * t) * o.knockback
			o.blast_knock(away * push + Vector3.UP * push * 0.3, 0.0, false)
		o.ignite(float(def.get("burn", 3.0)), owner_car)
		FxKit.spark(get_parent(), o.aim_point(), -away)
		if o.is_player or owner_car.is_player:
			GameFeel.hitstop(get_tree(), 0.04)


## Anything holding Axel lets go: a taser link on him, a wheel clamp, a chain bomb hooked to him.
func _break_grabs() -> void:
	for node in owner_car.get_parent().get_children():
		if node is TaserLink and (node as TaserLink).target == owner_car:
			(node as TaserLink).break_link()
		elif node is ChainBomb and (node as ChainBomb).stuck_to == owner_car:
			(node as ChainBomb).stuck_to = null
	if owner_car.clamped_time > 0.0:
		owner_car.release_clamp()


func _clear_mines(at: Vector3) -> void:
	var r := float(def.get("radius", 12.0))
	for node in get_tree().get_nodes_in_group(&"mines"):
		if node is Mine and (node as Node3D).global_position.distance_to(at) <= r:
			(node as Mine).fizzle()
