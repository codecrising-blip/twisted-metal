class_name BloodFx
## Blood (round 17, owner): a pool that spreads under a driver who was run down or shot and stays on
## the ground for a while, and a small splash left on the car that hit them, fading after a few
## seconds. Wet, dark red, no gore. Flat quads with a splatter texture made here (no decals: the
## Compatibility renderer has none).

const POOL_STAYS := 22.0 # seconds on the ground, then it fades
const CAR_STAYS := 10.0 # seconds on the car
const MAX_POOLS := 8

static var _tex: ImageTexture
static var _pools: Array = []


## The splatter: one irregular blob with drops thrown round it, soft edged, white (tinted by the material).
static func texture() -> ImageTexture:
	if _tex:
		return _tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var blobs: Array = [[Vector2(64, 64), 26.0]]
	for k in 7: # lobes round the middle
		var a := rng.randf() * TAU
		blobs.append([Vector2(64, 64) + Vector2(cos(a), sin(a)) * rng.randf_range(12, 26), rng.randf_range(9, 16)])
	for k in 16: # thrown drops
		var a := rng.randf() * TAU
		blobs.append([Vector2(64, 64) + Vector2(cos(a), sin(a)) * rng.randf_range(34, 58), rng.randf_range(1.5, 4.5)])
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var best := 0.0
			for b: Array in blobs:
				var r: float = b[1]
				best = maxf(best, clampf((r - p.distance_to(b[0])) / 3.0 + 0.5, 0.0, 1.0))
			if best > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, best))
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func _material(alpha := 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture()
	m.albedo_color = Color(0.32, 0.015, 0.012, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.22 # wet
	m.metallic_specular = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A pool spreading on the ground at `pos` to `radius` over `grow` seconds.
static func pool(world: Node, pos: Vector3, radius := 1.0, grow := 1.6) -> void:
	if world == null or not world.is_inside_tree():
		return
	var ground := Specials.ground_below(world, pos + Vector3.UP * 0.5)
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	mi.mesh = quad
	var mat := _material()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = ground + Vector3.UP * 0.1
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * 0.15
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, grow).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(POOL_STAYS)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	tw.tween_callback(mi.queue_free)
	_pools.assign(_pools.filter(func(p: Variant) -> bool: return is_instance_valid(p)))
	_pools.append(mi)
	while _pools.size() > MAX_POOLS:
		(_pools.pop_front() as Node).queue_free()


## A small splash on the car itself: `local_pos` / `local_normal` in the car's own space. It rides
## with the car and fades.
static func on_car(car: Vehicle, local_pos: Vector3, local_normal: Vector3, size := 0.7) -> void:
	if car == null or not is_instance_valid(car) or car.model == null:
		return
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * size
	mi.mesh = quad
	var mat := _material(0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	car.model.add_child(mi)
	var n := local_normal.normalized()
	var side := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, n, side.cross(n)).rotated(n, randf() * TAU), local_pos + n * 0.03)
	var tw := mi.create_tween()
	tw.tween_interval(CAR_STAYS)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.5)
	tw.tween_callback(mi.queue_free)
