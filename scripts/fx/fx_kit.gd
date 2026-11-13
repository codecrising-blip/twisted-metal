class_name FxKit
extends RefCounted
## Particle effects built in code: fire, smoke, sparks, explosions.

static var _soft_tex: ImageTexture
static var _meshes := {}


## Round soft dot used by every particle so quads don't look square.
## Built pixel by pixel so it exists immediately (no deferred generation).
static func soft_texture() -> ImageTexture:
	if _soft_tex == null:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c := (size - 1) * 0.5
		for y in size:
			for x in size:
				var d := Vector2(x - c, y - c).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
		_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex


## Billboard quad for particles. additive = glowing (fire), otherwise alpha (smoke).
static func particle_mesh(additive: bool) -> QuadMesh:
	if _meshes.has(additive):
		return _meshes[additive]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.no_depth_test = false
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.material = m
	_meshes[additive] = q
	return q


static func _ramp(colors: Array) -> Gradient:
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	var n := colors.size()
	for i in n:
		offsets.append(float(i) / float(n - 1))
		cols.append(colors[i])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = cols
	return g


static func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1, 0.0))
	return c


static func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 1.0))
	return c


## Continuous fire (barrels, Sweet Tooth's hair, burning wrecks).
static func fire(scale := 1.0, amount := 32) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = particle_mesh(true)
	p.amount = maxi(4, int(amount * GraphicsSettings.particles()))
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25 * scale
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 3.0 * scale, 0)
	p.initial_velocity_min = 1.0 * scale
	p.initial_velocity_max = 2.2 * scale
	p.scale_amount_min = 0.35 * scale
	p.scale_amount_max = 0.75 * scale
	p.scale_amount_curve = _shrink_curve()
	p.color_ramp = _ramp([Color(1.0, 0.75, 0.35, 0.9), Color(1.0, 0.4, 0.06, 0.7), Color(0.6, 0.1, 0.02, 0.35), Color(0.1, 0.05, 0.05, 0.0)])
	return p


static func smoke(scale := 1.0, amount := 20) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = particle_mesh(false)
	p.amount = maxi(4, int(amount * GraphicsSettings.particles()))
	p.lifetime = 2.2
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3 * scale
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0.4, 1.4, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 1.0 * scale
	p.scale_amount_max = 2.0 * scale
	p.scale_amount_curve = _grow_curve()
	p.color_ramp = _ramp([Color(0.24, 0.23, 0.22, 0.0), Color(0.2, 0.19, 0.18, 0.45), Color(0.14, 0.14, 0.14, 0.0)])
	return p


## One-shot explosion: fireball, smoke, sparks and a light flash. Frees itself.
static func explosion(parent: Node, pos: Vector3, size := 1.0, tint := Color(1.0, 0.5, 0.15)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	var ball := CPUParticles3D.new()
	ball.mesh = particle_mesh(true)
	ball.one_shot = true
	ball.explosiveness = 0.95
	ball.amount = int(28 * size) + 6
	ball.lifetime = 0.6
	ball.local_coords = false
	ball.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ball.emission_sphere_radius = 0.6 * size
	ball.spread = 180.0
	ball.initial_velocity_min = 2.0 * size
	ball.initial_velocity_max = 7.0 * size
	ball.damping_min = 6.0
	ball.damping_max = 10.0
	ball.scale_amount_min = 1.2 * size
	ball.scale_amount_max = 2.6 * size
	ball.scale_amount_curve = _shrink_curve()
	ball.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), tint, Color(0.5, 0.08, 0.02, 0.6), Color(0.05, 0.05, 0.05, 0)])
	root.add_child(ball)
	ball.emitting = true

	var sm := smoke(size * 1.2, int(14 * size) + 4)
	sm.one_shot = true
	sm.explosiveness = 0.8
	sm.lifetime = 2.5
	sm.spread = 180.0
	sm.initial_velocity_max = 3.0 * size
	root.add_child(sm)
	sm.emitting = true

	var sparks := CPUParticles3D.new()
	sparks.mesh = particle_mesh(true)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = int(18 * size) + 4
	sparks.lifetime = 0.9
	sparks.local_coords = false
	sparks.spread = 180.0
	sparks.gravity = Vector3(0, -18, 0)
	sparks.initial_velocity_min = 8.0 * size
	sparks.initial_velocity_max = 16.0 * size
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.18
	sparks.color_ramp = _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0)])
	root.add_child(sparks)
	sparks.emitting = true

	# Debris: dark metal chunks thrown out and falling back (one draw call).
	if size >= 0.9:
		var chunks := CPUParticles3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 0.12, 0.3)
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.12, 0.11, 0.1)
		metal.roughness = 0.7
		box.material = metal
		chunks.mesh = box
		chunks.one_shot = true
		chunks.explosiveness = 1.0
		chunks.amount = int(6 * size) + 2
		chunks.lifetime = 1.4
		chunks.local_coords = false
		chunks.direction = Vector3.UP
		chunks.spread = 70.0
		chunks.gravity = Vector3(0, -24, 0)
		chunks.initial_velocity_min = 6.0 * size
		chunks.initial_velocity_max = 12.0 * size
		chunks.angular_velocity_min = -720.0
		chunks.angular_velocity_max = 720.0
		chunks.scale_amount_min = 0.6 * size
		chunks.scale_amount_max = 1.4 * size
		root.add_child(chunks)
		chunks.emitting = true
	# The first instant: a white-hot flash, a ring racing along the ground on big ones, a burn mark.
	GameFeel.flash(parent, pos, 1.8 * size, tint.lerp(Color(1, 0.95, 0.8), 0.5), 0.14)
	if size >= 1.6:
		GameFeel.shockwave(parent, pos, 4.5 * size, tint)
	if size >= 1.0:
		GameFeel.scorch(parent, pos, 1.2 * size)
	GameFeel.shake(pos, 0.25 * size)
	GameFeel.play("explosion_big" if size >= 2.0 else "explosion", pos, parent)
	var tw := root.create_tween()
	if GraphicsSettings.high: # a moving light per explosion is too costly on LOW: the flash does it
		var light := OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 6.0 * size
		light.omni_range = 9.0 * size
		root.add_child(light)
		tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_interval(2.4)
	tw.tween_callback(root.queue_free)


## Small hit spark (bullets). No light: guns fire many of these per second.
static func spark(parent: Node, pos: Vector3, normal := Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.mesh = particle_mesh(true)
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 6
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = normal
	p.spread = 60.0
	p.gravity = Vector3(0, -15, 0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	p.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.5, 0.1, 0)])
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(p.queue_free)


## Car-on-car impact (rams, round 7: "show it strong"): a fan of sparks sprayed along the hit, bent
## metal bits thrown off and a white-hot flash at the contact. power 0..1 (a light tap .. a full ram).
static func crash_burst(parent: Node, pos: Vector3, normal: Vector3, power: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sparks := CPUParticles3D.new()
	sparks.mesh = particle_mesh(true)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = int(14 + 26 * power * GraphicsSettings.particles())
	sparks.lifetime = 0.7
	sparks.local_coords = false
	sparks.direction = (normal + Vector3.UP * 0.6).normalized()
	sparks.spread = 75.0
	sparks.gravity = Vector3(0, -20, 0)
	sparks.initial_velocity_min = 7.0 + 6.0 * power
	sparks.initial_velocity_max = 14.0 + 12.0 * power
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.2
	sparks.color_ramp = _ramp([Color(1, 0.97, 0.8, 1), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0)])
	root.add_child(sparks)
	sparks.emitting = true
	var bits := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.05, 0.26)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.15, 0.14)
	metal.metallic = 0.6
	metal.roughness = 0.5
	box.material = metal
	bits.mesh = box
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.amount = int(3 + 7 * power)
	bits.lifetime = 1.2
	bits.local_coords = false
	bits.direction = (normal + Vector3.UP).normalized()
	bits.spread = 60.0
	bits.gravity = Vector3(0, -26, 0)
	bits.initial_velocity_min = 5.0
	bits.initial_velocity_max = 9.0 + 6.0 * power
	bits.angular_velocity_min = -900.0
	bits.angular_velocity_max = 900.0
	bits.scale_amount_min = 0.7
	bits.scale_amount_max = 1.5
	root.add_child(bits)
	bits.emitting = true
	var smoke := smoke(0.6 + 0.6 * power, 6)
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.lifetime = 1.2
	root.add_child(smoke)
	smoke.emitting = true
	GameFeel.flash(parent, pos, 1.0 + 1.6 * power, Color(1.0, 0.85, 0.6), 0.1)
	if power > 0.45:
		GameFeel.shockwave(parent, pos - Vector3.UP * 0.6, 4.0 + 5.0 * power, Color(1.0, 0.75, 0.45))
	var tw := root.create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(root.queue_free)
