class_name SpiritSkull
extends Node3D
## Mr. Grimm's special, Head-On style (round 23; owner: "a skull spirit face with a reddish look, big damage, zero
## tracking", from `docs/reference/videos/mr grimm video.mp4`). Round 24 (owner: "the design is better now, but
## three heads? make it ONE big head with a good width, like Sweet Tooth's hurtbox, keep the same design; and it
## mustn't set the car it hits burning"): ONE spirit face (a picture of our own sculpted skull that always looks at
## the viewer, `spirit_face.gdshader`) whose skull is as wide as Sweet Tooth (2.5 m; its hits reach that wide too,
## `hit_widen` in WeaponData), a soft red aura and a stream of gold sparkles, a child of its Projectile.
## `launch()`: the rider flashes red and the ground under him glows pink. `burst()` at the hit: the face blows up and
## fades with a pink flash and a ring: no fireball and no embers left on the car (it read as burning).

const TEX := preload("res://assets/fx/spirit_skull.png")
const SHADER := preload("res://scripts/fx/spirit_face.gdshader")
const SKULL_SHARE := 0.6 # of the picture's width is the skull itself (the rest is its aura and margin)
const SIZE := 2.5 / SKULL_SHARE # the picture, metres across: the skull is 2.5 m wide, Sweet Tooth's width
const PINK := Color(1.0, 0.42, 0.48)
const GOLD := Color(1.0, 0.8, 0.35)

static var _quad: QuadMesh
static var _flat: PlaneMesh

var _main: MeshInstance3D
var _t := 0.0


## One spirit face: a camera-facing picture `size` m across.
static func face(parent: Node, size: float, fade := 1.0, seed := 0.0) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("face", TEX)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("seed", seed)
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	parent.add_child(mi)
	return mi


static func _set_fade(mi: MeshInstance3D, f: float) -> void:
	if is_instance_valid(mi):
		(mi.material_override as ShaderMaterial).set_shader_parameter("fade", f)


func _ready() -> void:
	_main = face(self, SIZE * 0.5, 1.0, randf() * 10.0)
	# The red aura round it: a soft additive glow, larger than the face.
	var aura := StandardMaterial3D.new()
	aura.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	aura.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	aura.billboard_keep_scale = true
	aura.albedo_texture = FxKit.soft_texture()
	aura.albedo_color = Color(1.0, 0.12, 0.1, 0.35)
	aura.disable_receive_shadows = true
	var glow := MeshInstance3D.new()
	glow.mesh = _quad_mesh()
	glow.material_override = aura
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.scale = Vector3.ONE * SIZE * 1.5
	glow.position = Vector3(0, 0, 0.3)
	add_child(glow)


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## The gold sparkles it sheds as it flies (the Projectile owns them as its trail, so they linger after the hit).
static func sparkles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = FxKit.particle_mesh(true) # additive: immune to the Compatibility black-quad bug
	p.amount = 24 # scattered sparks, not a solid column (additive sparks pile up to white)
	p.lifetime = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -4.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.13
	p.color_ramp = FxKit._ramp([GOLD, Color(1.0, 0.6, 0.2, 0.8), Color(1.0, 0.35, 0.1, 0)])
	return p


func _process(delta: float) -> void:
	_t += delta
	# It swells out of the bike to full size in the first blink.
	var pop := clampf(_t / 0.12, 0.0, 1.0)
	_main.scale = Vector3.ONE * SIZE * lerpf(0.5, 1.0, 1.0 - pow(1.0 - pop, 3.0))


## The release (juice guide: the tell and the release): the rider glows red, a pink glow on the ground.
static func launch(car: Vehicle, _from: Vector3, _dir: Vector3) -> void:
	if not is_instance_valid(car):
		return
	var world := car.get_parent()
	car.tint_flash(Color(1.0, 0.06, 0.05, 0.55), 0.32) # (no GameFeel.flash: a big flash sphere reads as a white dome)
	var g := Specials.ground_below(world, car.global_position + Vector3.UP * 2.0)
	_ground_glow(world, g + Vector3.UP * 0.12, 7.0, 0.45)


## A soft round glow lying on the ground (additive), fading out.
static func _ground_glow(world: Node, at: Vector3, size: float, seconds: float, c := PINK) -> void:
	if _flat == null:
		_flat = PlaneMesh.new()
		_flat.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = FxKit.soft_texture()
	m.albedo_color = Color(c.r, c.g, c.b, 0.7)
	m.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = _flat
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * size * 0.7
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, seconds)
	tw.tween_property(m, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## The hit: the face blows up to twice its size and fades, gold sparks spray out, a pink flash and glow.
static func burst(world: Node, pos: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var f := face(world, SIZE, 1.0, randf() * 10.0)
	f.global_position = pos + Vector3.UP * 0.6
	var tw := f.create_tween().set_parallel(true)
	tw.tween_property(f, "scale", Vector3.ONE * SIZE * 1.9, 0.38).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void: _set_fade(f, v), 1.0, 0.0, 0.38)
	tw.chain().tween_callback(f.queue_free)
	GameFeel.flash(world, pos, 1.6, PINK, 0.08)
	_ground_glow(world, Specials.ground_below(world, pos + Vector3.UP * 1.5) + Vector3.UP * 0.12, 9.0, 0.55)
	var p := CPUParticles3D.new()
	p.mesh = FxKit.particle_mesh(true)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 60
	p.lifetime = 0.5 # quick: sparks left falling on the car read as it burning (owner, round 24)
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 15.0
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	p.color_ramp = FxKit._ramp([Color(1, 0.92, 0.9, 1), PINK, Color(0.9, 0.08, 0.1, 0)]) # spirit pink, not fire
	p.emitting = false
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t2 := p.create_tween()
	t2.tween_interval(1.2)
	t2.tween_callback(p.queue_free)
