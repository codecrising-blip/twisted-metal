class_name ReaperSweep
extends Node3D
## Mr. Grimm's secondary (round 23, owner's design), "Soul Harvest": a giant spectral scythe swings round Grimm
## twice in "time" s at "radius" m (round 24, owner: one Roadkill car length, 5.4 m). Every pass of the blade over an opponent inside the
## circle tears out "steal" / "spins" of that car's full health, and Grimm heals "heal" / "spins" of his own for
## each: an opponent caught by both passes loses 25%, and Grimm gains 25% per opponent (360 degrees, any number).
## The look (owner: "flashy and intimidating, a grim reaper"; round 24: whitish with a tiny tone of red, the slash
## filling the arc, a smaller blade head): a white-hot blade on a black shaft, the slash filling the arc it swept
## from near Grimm out to the blade, a faint ring on the ground marking its reach, red sparks and a red
## flash where it cuts, souls (red wisps) torn out of the victims flying into Grimm, Grimm flaring green as they
## arrive. The scythe follows Grimm while he drives.

const EDGE := Color(1.0, 0.96, 0.94) # the white-hot cutting edge (round 24: white with a hint of red)
const SLASH := Color(1.0, 0.78, 0.76) # the slash filling the arc it sweeps: whitish, a tiny tone of red
const SOUL := Color(0.45, 1.0, 0.62) # pale soul green
const BLOOD := Color(1.0, 0.12, 0.08)
const BLADE_LEN := 1.9 # m of curved blade at the end of the shaft (round 24: 4.6 was "ridiculously big")
const TRAIL_ARC := 2.4 # rad of swoosh drawn behind the blade
const TRAIL_STEPS := 28

var owner_car: Vehicle
var def := {}

var _t := 0.0
var _theta0 := 0.0
var _theta := 0.0
var _rel := {} # victim -> blade angle relative to it last frame (wraps when the blade passes)
var _hits := {} # victim -> passes taken
var _arm: Node3D
var _trail: MeshInstance3D
var _im: ImmediateMesh
var _ring_mat: StandardMaterial3D
var _ring: MeshInstance3D
var stolen := 0.0 # health taken in all (tests read it)
var healed := 0.0

static var _blade_mesh: ArrayMesh
static var _blade_shader: Shader
static var _trail_mat: StandardMaterial3D


static func start(v: Vehicle, d: Dictionary) -> ReaperSweep:
	var s := ReaperSweep.new()
	s.owner_car = v
	s.def = d
	v.get_parent().add_child(s)
	s._begin()
	return s


func _radius() -> float:
	return float(def.get("radius", 5.4))


func _centre() -> Vector3:
	return owner_car.global_position + Vector3.UP * 1.1


func _begin() -> void:
	top_level = true
	global_position = _centre()
	var fwd := owner_car.flat_forward()
	# Blade angle: theta 0 = along +X; it starts beside Grimm (his right) and comes round the front first.
	_theta0 = atan2(-fwd.z, fwd.x) - PI * 0.5
	_theta = _theta0
	var r := _radius()
	# The scythe: a black shaft from Grimm out to the blade, the blade curving forward at its end.
	_arm = Node3D.new()
	add_child(_arm)
	var shaft := MeshKit.box(_arm, Vector3(r - 1.4, 0.16, 0.16), Vector3((r + 1.4) * 0.5, 0.0, 0.0), MeshKit.mat(Color(0.03, 0.035, 0.035), 0.6, 0.3))
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glowline := MeshKit.box(_arm, Vector3(r - 1.6, 0.05, 0.05), Vector3((r + 1.4) * 0.5, 0.11, 0.0), MeshKit.emissive(SLASH, 1.2))
	glowline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blade := MeshInstance3D.new()
	blade.mesh = _blade(r)
	var bm := ShaderMaterial.new()
	bm.shader = _shader()
	blade.material_override = bm
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.rotation.x = deg_to_rad(55.0) # raised: a flat blade is a thin line from the chase camera
	_arm.add_child(blade)
	_arm.rotation.y = _theta
	# The swoosh behind it, drawn fresh every frame in world space.
	_im = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _im
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _trail_mat == null:
		_trail_mat = StandardMaterial3D.new()
		_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_mat.vertex_color_use_as_albedo = true
		_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_mat.disable_receive_shadows = true
	_trail.material_override = _trail_mat
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	# Its reach, marked on the ground.
	var world := owner_car.get_parent()
	var ground := Specials.ground_below(world, global_position + Vector3.UP)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(0.9, 0.6, 0.58, 0.4)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = ground + Vector3.UP * 0.2
	_ring.scale = Vector3(r, 1.0, r)
	# The release: a cold flash on Grimm, the scream of the blade, a shake.
	owner_car.tint_flash(Color(SLASH.r, SLASH.g, SLASH.b, 0.5), 0.2)
	var db := float(def.get("sound_db", 0.0))
	# Round 23: its own sound (generated: two heavy whooshes, a blade's ring, a wail), sped up 1.3x so the two
	# whooshes land on the two laps; played from its start (not synced to its peak, the second whoosh).
	GameFeel.play("scythe_sweep", global_position, world, db, 1.3)
	GameFeel.play("launch_ghost_missile", global_position, world, -8.0 + db, 0.7, true)
	GameFeel.shake(global_position, 0.35)
	if owner_car.is_player:
		GameFeel.hitstop(get_tree(), 0.04)
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o and o != owner_car and not o.is_dead:
			_rel[o] = _wrap(_theta - _bearing(o))


## The blade: a crescent at the end of the shaft, its tip curving forward (local -Z leads as the arm turns)
## and in toward Grimm, wide at the root, needle at the tip. UV.y 0 = the cutting edge (inside), 1 = the spine.
static func _blade(r: float) -> ArrayMesh:
	if _blade_mesh != null:
		return _blade_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var spine: Array[Vector3] = []
	var edge: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		var c := Vector3(r + 0.15 - 0.62 * t * t, 0.08 * t, -BLADE_LEN * t) # the curve of the blade
		var tan := Vector3(-1.24 * t, 0.08, -BLADE_LEN).normalized()
		var out := tan.cross(Vector3.UP).normalized() # away from the edge side
		if out.x < 0.0:
			out = -out
		var w := 0.5 * pow(1.0 - t, 0.75) + 0.02
		spine.append(c + out * w * 0.55)
		edge.append(c - out * w * 0.45)
	for i in n:
		var a := float(i) / n
		var b := float(i + 1) / n
		for tri in [[edge[i], spine[i], spine[i + 1]], [edge[i], spine[i + 1], edge[i + 1]]]:
			for p: Vector3 in tri:
				var uvy := 0.0 if (p == edge[i] or p == edge[i + 1]) else 1.0
				st.set_uv(Vector2(a if p in [edge[i], spine[i]] else b, uvy))
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	_blade_mesh = st.commit()
	return _blade_mesh


static func _shader() -> Shader:
	if _blade_shader == null:
		_blade_shader = Shader.new()
		_blade_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;
void fragment() {
	// White-hot edge (a hint of red), a pale red glow behind it, a near-black steel spine; wisps run along it.
	float e = UV.y;
	vec3 edge = vec3(1.0, 0.95, 0.93) * 1.5;
	vec3 soul = vec3(1.0, 0.62, 0.6) * 1.1;
	vec3 spine = vec3(0.06, 0.04, 0.04);
	vec3 c = mix(edge, soul, smoothstep(0.0, 0.25, e));
	c = mix(c, spine, smoothstep(0.35, 0.9, e));
	float wisp = 0.5 + 0.5 * sin(UV.x * 40.0 - TIME * 30.0 + e * 6.0);
	c += soul * 0.35 * wisp * (1.0 - e);
	ALBEDO = c;
	ALPHA = mix(1.0, 0.82, e) * (0.85 + 0.15 * sin(TIME * 41.0));
}
"""
	return _blade_shader


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_car) or owner_car.is_dead:
		queue_free()
		return
	_t += delta
	var total := float(def.get("time", 0.8))
	var spins := float(def.get("spins", 2.0))
	var u := clampf(_t / total, 0.0, 1.0)
	# Fast out of the gate, a hair slower at the very end (it hangs a moment before it vanishes).
	_theta = _theta0 + spins * TAU * (1.0 - pow(1.0 - u, 1.35))
	global_position = _centre()
	_arm.rotation.y = _theta
	_cut()
	_draw_trail(u)
	var fade := 1.0 - clampf((u - 0.85) / 0.15, 0.0, 1.0)
	_ring_mat.albedo_color.a = 0.4 * fade * (0.7 + 0.3 * sin(_t * 40.0))
	_ring.global_position = Specials.ground_below(get_parent(), global_position + Vector3.UP) + Vector3.UP * 0.2
	if u >= 1.0:
		_end()


## Bearing of a car round Grimm in the arm's angle: theta 0 = +X, growing toward -Z.
func _bearing(o: Vehicle) -> float:
	var d := o.global_position - global_position
	return atan2(-d.z, d.x)


static func _wrap(a: float) -> float:
	return fposmod(a, TAU)


## Every car the blade passed over since last frame (inside the circle) loses its share, Grimm takes it.
func _cut() -> void:
	var r := _radius()
	var spins := float(def.get("spins", 2.0))
	for node in get_tree().get_nodes_in_group("vehicles"):
		var o := node as Vehicle
		if o == null or o == owner_car or o.is_dead:
			continue
		var rel := _wrap(_theta - _bearing(o))
		var last := float(_rel.get(o, rel))
		_rel[o] = rel
		if rel >= last: # the blade has not come round to it yet this lap
			continue
		var d := o.global_position - global_position
		var size: Vector3 = o.stats.get("size", Vector3(2, 2, 5))
		if Vector2(d.x, d.z).length() > r + size.z * 0.3 or absf(d.y) > 4.0:
			continue
		if int(_hits.get(o, 0)) >= int(spins):
			continue
		_hits[o] = int(_hits.get(o, 0)) + 1
		var before := o.health
		o.take_damage(o.max_health * float(def.get("steal", 0.25)) / spins, owner_car)
		var took := before - o.health
		var tangent := Vector3(-sin(_theta), 0.0, -cos(_theta))
		o.hit_react(tangent, 30.0)
		o.push(tangent * 4.0 * o.knockback + Vector3.UP * 1.5)
		_slash_fx(o, tangent)
		if took > 0.0:
			stolen += took
			var gain := owner_car.max_health * float(def.get("heal", 0.25)) / spins
			healed += gain
			_soul(o.aim_point(), gain)


func _slash_fx(o: Vehicle, dir: Vector3) -> void:
	var world := get_parent()
	var at := o.aim_point()
	GameFeel.flash(world, at, 1.5, BLOOD, 0.08)
	GameFeel.play("ram_impact", at, world, -3.0, 1.4, true)
	for k in 4:
		FxKit.spark(world, at, (dir + Vector3(randf_range(-0.7, 0.7), 0.8, randf_range(-0.7, 0.7))).normalized())
	if o.is_player or owner_car.is_player:
		GameFeel.hitstop(get_tree(), 0.05)
		GameFeel.shake(at, 0.4)


## A soul torn out of the victim: a red wisp that flies into Grimm; he flares green and heals as it lands.
func _soul(from: Vector3, gain: float) -> void:
	var world := get_parent()
	var car := owner_car
	for k in 3:
		var w := MeshInstance3D.new()
		var m := MeshKit.emissive(BLOOD, 1.3) # (more emission bleaches it to white through the tonemapper)
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		sphere.radial_segments = 8
		sphere.rings = 4
		w.mesh = sphere
		w.material_override = m
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(w)
		w.global_position = from + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6))
		Streak.attach(w, BLOOD, 0.25, 0.3)
		var start := w.global_position
		var bend := Vector3(randf_range(-3, 3), randf_range(2.5, 4.5), randf_range(-3, 3))
		var dur := 0.32 + k * 0.06
		var last := k == 2
		var tw := w.create_tween()
		tw.tween_method(func(s: float) -> void:
			if not is_instance_valid(car) or not is_instance_valid(w):
				return
			var end := car.global_position + Vector3.UP * 1.2
			var mid := start.lerp(end, 0.5) + bend
			w.global_position = start.lerp(mid, s).lerp(mid.lerp(end, s), s), 0.0, 1.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func() -> void:
			if last and is_instance_valid(car) and not car.is_dead:
				car.heal(gain)
				car.tint_flash(Color(SOUL.r, SOUL.g, SOUL.b, 0.45), 0.18)
				GameFeel.flash(car.get_parent(), car.global_position + Vector3.UP, 1.2, SOUL, 0.08)
				GameFeel.play("pickup_health", car.global_position, car.get_parent(), -6.0, 0.8)
			if is_instance_valid(w):
				w.queue_free())
	if is_instance_valid(car) and car.is_player:
		car.notice.emit(car, "SOUL HARVEST +%d" % int(round(gain)))


## The swoosh: a crescent of light over the band the blade swept in the last moment: a bright rim along the
## blade's tip, a soft green body inside it, both fading toward the tail. Narrow on purpose: a wide sheet at
## car height covered the ground like fog.
func _draw_trail(u: float) -> void:
	_im.clear_surfaces()
	var r := _radius()
	var swept := _theta - _theta0
	var arc := minf(TRAIL_ARC, swept)
	if arc <= 0.05:
		return
	var fade := 1.0 - clampf((u - 0.8) / 0.2, 0.0, 1.0)
	var c := global_position + Vector3.UP * 0.25
	# [inner radius, outer radius, colour at the inner edge, colour at the outer edge]
	# Round 24 (owner: "not too hollow in between"): the slash fills the swept arc from near Grimm out to the
	# blade, faint inside and brighter toward the rim, then the white-hot rim itself.
	var bands := [[r * 0.2, r - 0.25, Color(SLASH.r, SLASH.g, SLASH.b, 0.14), Color(SLASH.r, SLASH.g, SLASH.b, 0.55)],
		[r - 0.25, r + 0.25, Color(EDGE.r, EDGE.g, EDGE.b, 0.95), Color(EDGE.r, EDGE.g, EDGE.b, 0.0)]]
	for band in bands:
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in TRAIL_STEPS + 1:
			var s := float(i) / TRAIL_STEPS # 0 = at the blade, 1 = the tail
			var a := _theta - arc * s
			var dir := Vector3(cos(a), 0.0, -sin(a))
			var fresh := pow(1.0 - s, 1.6) * fade
			var ci: Color = band[2]
			var co: Color = band[3]
			_im.surface_set_color(Color(co.r, co.g, co.b, co.a * fresh))
			_im.surface_add_vertex(c + dir * float(band[1]))
			_im.surface_set_color(Color(ci.r, ci.g, ci.b, ci.a * fresh))
			_im.surface_add_vertex(c + dir * float(band[0]))
		_im.surface_end()


func _end() -> void:
	var world := get_parent()
	FxKit.puff(world, global_position, 0.6)
	queue_free()
