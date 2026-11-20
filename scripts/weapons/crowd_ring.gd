class_name CrowdRing
extends Node3D
## Axel's Crowd Controller. Round 21 (owner: "sooo weak, a huge delay, the tip of it does nothing"): it
## goes off THE MOMENT it is fired. A 360 degree sphere of electric fire races out from Axel to "radius"
## m in "spread" s: a hollow shell, bright at its rim from every side (not a ball), with a ring racing
## along the ground under it and lightning crawling over it. Every car it reaches, on the ground or in
## the air, takes the same "damage" (no weaker edge), is thrown hard away from Axel (a super heavy only
## takes the damage) and burns. Mines inside it die harmlessly, and any grab on Axel breaks (a taser
## link, a wheel clamp, a chain bomb on him).

const COLOR := Color(1.0, 0.55, 0.25) # the ring's electric orange (round 20), now the whole sphere
const BOLT_TINT := Color(0.35, 0.6, 1.0)

var owner_car: Vehicle
var def := {}

var _t := 0.0
var _hit := {}
var _centre := Vector3.ZERO
var _shell: MeshInstance3D
var _shell_mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _bolt: Bolt

static var _shader: Shader


static func start(v: Vehicle, d: Dictionary) -> CrowdRing:
	var r := CrowdRing.new()
	r.owner_car = v
	r.def = d
	v.get_parent().add_child(r)
	r._fire()
	return r


func _ready() -> void:
	_bolt = Bolt.new()
	_bolt.tint = BOLT_TINT
	add_child(_bolt)


## A sphere drawn only near its outline: wherever you look from, it reads as a glowing ring round a
## clear middle, with fine lightning bands sliding over it.
static func shell_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float fade = 1.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 3.0);
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bands = smoothstep(0.82, 1.0, sin(w.y * 3.0 + TIME * 14.0 + sin(w.x * 0.7 + TIME * 5.0) * 2.0));
	float a = (rim * 1.4 + 0.06 + bands * 0.18 * (1.0 - facing)) * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 0.85), rim * rim * 0.6) * a;
}
"""
	return _shader


func _fire() -> void:
	var world := owner_car.get_parent()
	_centre = owner_car.global_position + Vector3.UP * 1.2
	global_position = _centre
	var ground := Specials.ground_below(world, _centre)
	# The sphere shell.
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = shell_shader()
	_shell_mat.set_shader_parameter("tint", COLOR)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 40
	sphere.rings = 20
	_shell = MeshInstance3D.new()
	_shell.mesh = sphere
	_shell.material_override = _shell_mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	_shell.scale = Vector3.ONE * 0.5
	# The ring racing along the ground under it.
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.85)
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
	_ring.global_position = ground + Vector3.UP * 0.25
	# The release beat (juice guide): a white-hot flash, the shockwave, the crack of it, a shake.
	var sound_db := float(def.get("sound_db", 0.0))
	GameFeel.play("special_axel", _centre, world, sound_db, 1.0, true)
	GameFeel.play("lightning", _centre, world, -4.0 + sound_db, 1.2, true)
	GameFeel.flash(world, _centre, 3.0, Color(1.0, 0.85, 0.6), 0.12)
	GameFeel.shockwave(world, ground, float(def.get("radius", 12.0)) * 1.15, COLOR)
	GameFeel.shake(_centre, 0.55)
	FxKit.dust_ring(world, ground, 2.0)
	for sx in [-1.0, 1.0]: # sparks off both tyres
		FxKit.spark(world, owner_car.global_transform * Vector3(sx * 1.6, 0.2, 0.0), Vector3.UP)
	if owner_car.is_player:
		GameFeel.hitstop(get_tree(), 0.05)
	_break_grabs()
	_clear_mines()


func _physics_process(delta: float) -> void:
	if _shell == null:
		return
	_t += delta
	var spread := float(def.get("spread", 0.35))
	var full := float(def.get("radius", 12.0))
	var k := clampf(_t / spread, 0.0, 1.0)
	var radius := full * (1.0 - pow(1.0 - k, 2.0)) # fast out, easing at the edge
	_reach(radius)
	var r := maxf(radius, 0.5)
	_shell.scale = Vector3.ONE * r
	_ring.scale = Vector3(r, 1.0, r)
	var fade := 1.0 - clampf((_t - spread * 0.6) / (spread * 0.9), 0.0, 1.0)
	_shell_mat.set_shader_parameter("fade", fade)
	_ring_mat.albedo_color.a = 0.85 * fade
	_bolt.begin()
	if fade > 0.05:
		for i in 9: # lightning crawling over the shell
			var a := TAU * (i + randf()) / 9.0
			var e := randf_range(-0.6, 0.9)
			var p := _centre + Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * r
			var q := _centre + Vector3(cos(a + 0.3) * cos(e + 0.25), sin(e + 0.25), sin(a + 0.3) * cos(e + 0.25)) * r
			_bolt.strand(Bolt.jagged(p, q, 3, 0.4), 0.1 * fade, 0.03, 0.9 * fade)
	_bolt.finish()
	if _t >= spread * 1.6:
		queue_free()


## Everything the sphere has reached: the same damage everywhere inside it, a throw, burning.
func _reach(radius: float) -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == null or o == owner_car or o.is_dead or _hit.has(o):
			continue
		var rel := o.aim_point() - _centre
		var size: Vector3 = o.stats.get("size", Vector3(2, 2, 5))
		if rel.length() > radius + size.z * 0.3:
			continue
		_hit[o] = true
		var dmg := float(def.get("damage", 50.0)) * WeaponData.DAMAGE_SCALE
		o.take_damage(dmg, owner_car)
		var away := Vector3(rel.x, 0.0, rel.z)
		away = away.normalized() if away.length() > 0.3 else o.flat_forward()
		o.hit_react(away, dmg)
		if o.stats.get("class", "medium") != "super":
			var push := float(def.get("push", 20.0)) * o.knockback
			o.blast_knock(away * push + Vector3.UP * push * 0.3, 0.0, false)
		o.ignite(float(def.get("burn", 4.0)), owner_car)
		FxKit.spark(get_parent(), o.aim_point(), -away)
		GameFeel.flash(get_parent(), o.aim_point(), 1.6, Color(1.0, 0.75, 0.4), 0.08)
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


func _clear_mines() -> void:
	var r := float(def.get("radius", 12.0))
	for node in get_tree().get_nodes_in_group(&"mines"):
		if node is Mine and (node as Node3D).global_position.distance_to(_centre) <= r + 1.5:
			(node as Mine).fizzle()
