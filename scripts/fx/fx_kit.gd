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


## Round 18: Godot 4.3's Compatibility renderer draws every particle slot that has not been emitted yet
## as an opaque black quad at the emitter while the system runs (godotengine/godot#107978, #124655):
## the "black ball" in smoke, explosions and burning drivers. Called for every node added to the tree
## (main.gd): a running emitter pre-fills its slots (preprocess one lifetime), a one-shot fires them all
## at once (explosiveness 1, the old spread kept as lifetime randomness). Additive ones are left alone:
## black adds nothing.
static func ghost_guard(node: Node) -> void:
	var p := node as CPUParticles3D
	if p == null:
		return
	if p.one_shot and p.amount > 3:
		Callable(FxKit, "_budget").bind(p).call_deferred()
	var mat: Material = (p.mesh as PrimitiveMesh).material if p.mesh is PrimitiveMesh else null
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return
	if p.one_shot:
		if p.explosiveness < 1.0:
			p.lifetime_randomness = clampf(maxf(p.lifetime_randomness, (1.0 - p.explosiveness) * 0.8), 0.0, 1.0)
			p.explosiveness = 1.0
	elif p.preprocess < p.lifetime:
		p.preprocess = p.lifetime
	# One added already emitting would be drawn once before its first update: every slot black, for a
	# frame (the black dot inside explosions). A restart updates it at once.
	if p.emitting:
		p.restart.call_deferred()


## Round 25 (owner: lag when five cars fight at once): bursts (sparks, debris, smoke puffs) keep fewer particles
## far from the camera and when many are alive already; a burst beyond BUDGET_GONE is not drawn at all.
## Deferred: effects are placed after they are added, so the distance is only known on the next idle point.
const BUDGET_FAR := 60.0
const BUDGET_GONE := 170.0
const BUDGET_LIVE := 40


static func _budget(p: CPUParticles3D) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree() or not p.emitting:
		return # not emitting by now = a car's own reusable emitter (muzzle, shells): left alone
	var k := 1.0
	var cam := p.get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(p.global_position)
		if d > BUDGET_GONE:
			p.emitting = false
			p.visible = false
			return
		if d > BUDGET_FAR:
			k *= clampf(BUDGET_FAR / d, 0.35, 1.0)
	if p.get_tree().get_nodes_in_group("fx_bursts").size() > BUDGET_LIVE:
		k *= 0.5
	p.add_to_group("fx_bursts")
	if k < 0.95:
		p.amount = maxi(2, int(p.amount * k))


## A one-shot burst emitter drawn in world space (every particle at once unless explosiveness says less).
static func burst(mesh: Mesh, amount: int, lifetime: float, explosiveness := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = explosiveness
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	return p


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
static func explosion(parent: Node, pos: Vector3, size := 1.0, tint := Color(1.0, 0.5, 0.15), sound := true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	var ball := burst(particle_mesh(true), int(28 * size) + 6, 0.6, 0.95)
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

	var sparks := burst(particle_mesh(true), int(18 * size) + 4, 0.9)
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
	if sound: # synced: the boom's loudest moment lands with the flash (some files swell for half a second)
		GameFeel.play("explosion_big" if size >= 2.0 else "explosion", pos, parent, 0.0, 1.0, true)
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
	var p := burst(particle_mesh(true), 6, 0.35)
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


## Sparks thrown off the green shield coat where it blocks a hit (round 17): a quick white-hot to
## lime to forest-green spray along the surface normal, lighter than a ram's crash burst.
static func shield_sparks(parent: Node, pos: Vector3, normal: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := burst(particle_mesh(true), 14, 0.4)
	p.direction = normal if normal.length() > 0.01 else Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -12, 0)
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	p.color_ramp = _ramp([Color(1, 1, 0.85, 1), Color(0.75, 1.0, 0.4, 0.9), Color(0.13, 0.55, 0.13, 0)])
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
	var sparks := burst(particle_mesh(true), int(14 + 26 * power * GraphicsSettings.particles()), 0.7)
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


## A short puff of grey launch smoke that drifts and fades (a missile leaving its tube).
static func puff(parent: Node, pos: Vector3, size := 0.4) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := smoke(size, 6)
	p.color_ramp = _ramp([Color(0.8, 0.78, 0.74, 0.0), Color(0.78, 0.76, 0.72, 0.4), Color(0.7, 0.68, 0.65, 0.0)]) # pale dust
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 0.9
	p.spread = 60.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(p.queue_free)


## Aftermath of a big blast: a tall column of dark smoke with glowing embers rising in it, for a few
## seconds (it lingers instead of vanishing with the flash).
static func smoke_column(parent: Node, pos: Vector3, size := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sm := smoke(size * 1.6, 12)
	sm.one_shot = true
	sm.explosiveness = 0.5
	sm.lifetime = 3.2
	sm.spread = 12.0
	sm.gravity = Vector3(0.3, 3.0, 0)
	sm.initial_velocity_min = 2.0
	sm.initial_velocity_max = 5.0
	root.add_child(sm)
	sm.emitting = true
	var em := fire(size * 0.4, 10)
	em.one_shot = true
	em.explosiveness = 0.6
	em.lifetime = 1.8
	em.spread = 35.0
	em.gravity = Vector3(0, 4.0, 0)
	em.initial_velocity_min = 3.0
	em.initial_velocity_max = 7.0
	em.scale_amount_min = 0.05
	em.scale_amount_max = 0.12
	root.add_child(em)
	em.emitting = true
	var tw := root.create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(root.queue_free)


static var _shard_mesh: PrismMesh
static var _splinter_mesh: BoxMesh
static var _shard_mats := {}


## See-through glinting material for shards (glass, ice), one per tint.
static func _shard_material(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html()
	if not _shard_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(tint.r, tint.g, tint.b, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.6
		m.roughness = 0.08
		m.emission_enabled = true
		m.emission = tint * 0.45 # they have to read against a bright dusk sky and pale pavers
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true # the particles' colour ramp fades them out
		_shard_mats[key] = m
	return _shard_mats[key]


## Glass (or wood) breaking (juice guide): pieces fly out of the whole panel along the car that went
## through it, spinning and falling, plus a glitter of tiny bright glints for glass. extents = half
## size of the panel in world axes.
static func shatter(parent: Node, center: Vector3, extents: Vector3, dir: Vector3, speed: float, tint: Color, glass: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = center
	var p := CPUParticles3D.new()
	if glass:
		if _shard_mesh == null:
			_shard_mesh = PrismMesh.new() # a thin triangle: a shard
			_shard_mesh.size = Vector3(0.7, 0.95, 0.03)
		p.mesh = _shard_mesh
		p.material_override = _shard_material(tint)
	else:
		if _splinter_mesh == null:
			_splinter_mesh = BoxMesh.new() # a long thin plank splinter
			_splinter_mesh.size = Vector3(0.1, 0.06, 0.7)
		p.mesh = _splinter_mesh
		p.material_override = MeshKit.mat(tint, 0.8)
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int((44 if glass else 26) * GraphicsSettings.particles())
	p.lifetime = 1.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents.abs() + Vector3.ONE * 0.1
	p.direction = (dir + Vector3.UP * 0.35).normalized()
	p.spread = 40.0
	p.gravity = Vector3(0, -26, 0)
	p.initial_velocity_min = 4.0 + speed * 0.25
	p.initial_velocity_max = 9.0 + speed * 0.55
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	# Particles don't collide: fade out about when they reach the ground; the litter takes over.
	p.lifetime = 0.9
	p.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	root.add_child(p)
	p.emitting = true
	if glass: # glints: tiny white sparkles that catch the light for a moment
		var g := burst(particle_mesh(true), int(24 * GraphicsSettings.particles()), 0.6, 0.9)
		g.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		g.emission_box_extents = extents.abs()
		g.direction = p.direction
		g.spread = 60.0
		g.gravity = Vector3(0, -12, 0)
		g.initial_velocity_min = 3.0
		g.initial_velocity_max = 9.0 + speed * 0.3
		g.scale_amount_min = 0.08
		g.scale_amount_max = 0.2
		g.color_ramp = _ramp([Color(1, 1, 1, 1), Color(0.8, 0.95, 1.0, 0.8), Color(0.7, 0.9, 1.0, 0)])
		root.add_child(g)
		g.emitting = true
	var tw := root.create_tween()
	tw.tween_interval(1.8)
	tw.tween_callback(root.queue_free)


## Aftermath of glass: a scatter of flat shards left on the ground past the panel (one mesh), glinting,
## that fade away after a while instead of vanishing.
static func shard_litter(parent: Node, center: Vector3, dir: Vector3, tint: Color, count := 14) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var base := Specials.ground_below(parent, center + Vector3.UP)
	for k in count:
		var c := base + flat * randf_range(0.5, 5.5) + flat.cross(Vector3.UP) * randf_range(-2.5, 2.5)
		c.y = Specials.ground_below(parent, c + Vector3.UP * 2.0).y + 0.03
		var a := randf() * TAU
		var r := randf_range(0.18, 0.42)
		for j: int in [0, 2, 1]: # clockwise seen from above
			var ang := a + j * TAU / 3.0 + randf_range(-0.4, 0.4)
			st.add_vertex(c - base + Vector3(cos(ang), 0, sin(ang)) * r)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.6
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = tint * 0.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = base
	var tw := mi.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(m, "albedo_color:a", 0.0, 2.0)
	tw.tween_callback(mi.queue_free)


## A low ring of dust kicked up along the ground (a landing, something heavy falling over).
static func dust_ring(parent: Node, pos: Vector3, size := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := smoke(size, 10)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2 * size
	p.emission_ring_inner_radius = 0.8 * size
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 4.5 * size
	p.color_ramp = _ramp([Color(0.55, 0.5, 0.42, 0.0), Color(0.5, 0.46, 0.4, 0.45), Color(0.45, 0.42, 0.38, 0.0)])
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.2
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(p.queue_free)


## Round 29 (Paris, the shallow Seine): water thrown up round a wading car's wheels.
static func splash(parent: Node, pos: Vector3, size := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.mesh = particle_mesh(true)
	p.amount = 10
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.75
	p.lifetime_randomness = 0.4
	p.direction = Vector3.UP
	p.spread = 38.0
	p.gravity = Vector3(0, -15.0, 0)
	p.initial_velocity_min = 2.5 * size
	p.initial_velocity_max = 6.0 * size
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * size
	p.color_ramp = _ramp([Color(0.62, 0.68, 0.7, 0.75), Color(0.5, 0.56, 0.58, 0.45), Color(0.4, 0.45, 0.46, 0.0)])
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(p.queue_free)


## Round 32: leaves knocked out of a tree's crown, fluttering down and drifting: small shaded flakes in a few
## greens (a billboard that keeps its scale; the soft blob particles are drawn 1 m wide whatever their scale).
static func leaves(parent: Node, pos: Vector3, size := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not _meshes.has("leaf"):
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 0.7)
		q.material = m
		_meshes["leaf"] = q
	var p := burst(_meshes["leaf"], int(60 * size * GraphicsSettings.particles()) + 8, 3.2, 0.85)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0 * size
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -2.4, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	p.scale_amount_min = 0.14
	p.scale_amount_max = 0.3
	p.color_initial_ramp = _ramp([Color("4C6A2A"), Color("6E8B3D"), Color("3D5622"), Color("7A9446")])
	p.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(3.6)
	tw.tween_callback(p.queue_free)
