class_name EarthquakeSlam
extends Node3D
## Thumper's secondary (round 29, owner; replaces the Drive-By): Earthquake Slam. The lowrider drops on its
## springs and a sonic boom blasts out from under it: a blue wave rolls along the ground to "radius" m (a stereo
## 808 boom for the player, positional for the rest). Every car it reaches takes damage and is thrown away from
## Thumper, the push falling off with distance; cars inside lift_r are lifted on the side facing him and roll over
## (Vehicle.blast_knock with a flip). Super heavy cars only slide. Pushes enemies off health and weapons, or into a
## wall where the Megafire or a freeze can finish them.

const GROW := 0.45 # seconds for the wave to reach its full radius

var car: Vehicle
var def: Dictionary
var _disc: MeshInstance3D
var _wall: MeshInstance3D
var _dmat: ShaderMaterial
var _wmat: ShaderMaterial
var _t := 0.0
var _hit: Array = []


static func start(v: Vehicle, d: Dictionary) -> EarthquakeSlam:
	var q := EarthquakeSlam.new()
	q.car = v
	q.def = d
	v.get_parent().add_child(q)
	q.global_position = v.global_position - Vector3.UP * 0.3
	return q


func _ready() -> void:
	var radius := float(def.get("radius", 16.0))
	var shader: Shader = load("res://scripts/fx/quake_wave.gdshader")
	_disc = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0) * radius
	_disc.mesh = pm
	_dmat = ShaderMaterial.new()
	_dmat.shader = shader
	_disc.material_override = _dmat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.position = Vector3.UP * 0.45
	add_child(_disc)
	_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 40
	cyl.rings = 1
	_wall.mesh = cyl
	_wmat = ShaderMaterial.new()
	_wmat.shader = shader
	_wmat.set_shader_parameter("wall", 1.0)
	_wall.material_override = _wmat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	var world := get_parent()
	var at := global_position + Vector3.UP * 0.4
	# the boom: full stereo for the driver himself, out in the world for everyone else
	if car.is_player:
		GameFeel.ui("earthquake_slam", get_tree(), float(def.get("sound_db", 0.0)))
	else:
		GameFeel.play("earthquake_slam", at, world, float(def.get("sound_db", 0.0)) + 2.0)
	GameFeel.flash(world, at, 2.2, Color(0.55, 0.8, 1.0), 0.14)
	FxKit.dust_ring(world, global_position, 3.2)
	FxKit.dust_ring(world, global_position, 6.0)
	GameFeel.shake(at, 1.1, 70.0)
	if car.is_player:
		GameFeel.hitstop(get_tree(), 0.07)
	car.linear_velocity += Vector3.DOWN * 3.0 # the lowrider slams down on its springs as it fires
	_blast()


## Everyone in reach: damage, a throw away from him, a roll for the ones close by.
func _blast() -> void:
	var radius := float(def.get("radius", 16.0))
	var lift_r := float(def.get("lift_r", 8.0))
	for node in car.get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == car or o.is_dead:
			continue
		var to := o.global_position - car.global_position
		if absf(to.y) > 4.0:
			continue # another level (a roof, the river below)
		var flat := Vector3(to.x, 0.0, to.z)
		var d := flat.length()
		if d > radius:
			continue
		var dir := flat / d if d > 0.1 else -car.flat_forward()
		var k := 1.0 - d / radius
		o.take_damage(float(def.get("damage", 14.0)) * (0.4 + 0.6 * k) * WeaponData.DAMAGE_SCALE, car)
		o.hit_react(-dir, 6.0)
		var heavy := String(o.stats.get("class", "medium")) == "super"
		var push := float(def.get("push", 26.0)) * (0.35 + 0.65 * k)
		if heavy:
			o.blast_knock(dir * push * 0.35, 0.0, false)
			continue
		if d < lift_r:
			var close := 1.0 - d / lift_r
			o.blast_knock(dir * push + Vector3.UP * float(def.get("lift", 9.0)) * (0.55 + 0.45 * close), 0.35 + 0.4 * close)
		else:
			o.blast_knock(dir * push + Vector3.UP * 2.5, 0.0)
		o.squish(-dir, 1.5)
		_hit.append(o)
	Specials.blast_props(car.get_parent(), car.global_position, radius * 0.6, float(def.get("damage", 14.0)), car)


func _process(delta: float) -> void:
	_t += delta
	var radius := float(def.get("radius", 16.0))
	var g := clampf(_t / GROW, 0.0, 1.0)
	var front := 1.0 - pow(1.0 - g, 2.2) # fast out, easing at the edge
	var fade := 1.0 - smoothstep(GROW * 0.7, GROW + 0.55, _t)
	_dmat.set_shader_parameter("front", front)
	_dmat.set_shader_parameter("fade", fade)
	_wall.scale = Vector3(front * radius, 2.4 * (1.0 - g * 0.5), front * radius)
	_wall.position = Vector3.UP * (1.2 * (1.0 - g * 0.5) + 0.3)
	_wmat.set_shader_parameter("fade", fade * (1.0 - g * 0.4))
	if _t > GROW + 0.7:
		queue_free()
