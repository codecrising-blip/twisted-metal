class_name WheelClamp
## Outlaw's secondary weapon (design 2.3; round 19, the owner's rules): a big bright wheel clamp thrown
## forward with light homing. A hit locks the wheels on the side it struck (Vehicle.clamp_for): while the
## car moves it can only turn the other way, no turbo, no reverse; it wears off after 5 s of MOVING and
## scrapes SCRAPE_DPS while it moves (25 in all), sparks and bright scratch lines trailing behind the wheel.
## The answer (design): it is slow and easy to see; a hard handbrake turn makes it fly past.

const MIN_TURN := 0.6 # the least it turns toward the free side while moving (of full lock)
const MOVING_SPEED := 2.0 # m/s: slower than this the car counts as standing still (the clamp doesn't wear)
const SCRAPE_DPS := 5.0 # 25 over the 5 s of moving
const BOOT_SCALE := 1.35 # on the wheel: bigger than the wheel itself, so nobody misses it
const MARKS_MAX := 70

static var _marks: Array = []
static var _mark_mesh: QuadMesh


## The boot: a safety-yellow plate over the whole wheel face with a red and white reflective ring, a jaw
## arm round the tyre, a heavy padlock and a red warning lamp on top. Its plate faces +X (outward on a
## right-hand wheel). About 0.75 m across before BOOT_SCALE.
static func build_boot(parent: Node3D) -> void:
	var yellow := MeshKit.emissive(Color(1.0, 0.74, 0.04), 0.35)
	yellow.roughness = 0.5
	var red := MeshKit.emissive(Color(0.85, 0.06, 0.04), 0.4)
	var white := MeshKit.emissive(Color(0.95, 0.95, 0.9), 0.3)
	var iron := MeshKit.mat(Color(0.07, 0.07, 0.075), 0.5, 0.6)
	MeshKit.cylinder(parent, 0.38, 0.08, Vector3.ZERO, yellow, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.3, 0.09, Vector3(0.005, 0, 0), red, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.26, 0.1, Vector3(0.01, 0, 0), white, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.2, 0.11, Vector3(0.015, 0, 0), yellow, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.09, 0.16, Vector3(0.06, 0, 0), iron, Vector3(0, 0, 90), 8)
	MeshKit.box(parent, Vector3(0.12, 0.7, 0.16), Vector3(-0.09, -0.26, 0.0), yellow) # arm down round the tyre
	MeshKit.box(parent, Vector3(0.5, 0.12, 0.18), Vector3(-0.28, -0.58, 0.0), yellow) # jaw under it
	MeshKit.box(parent, Vector3(0.18, 0.2, 0.14), Vector3(0.12, -0.34, 0.14), iron) # padlock
	var lamp := MeshKit.sphere(parent, 0.07, Vector3(0.0, 0.44, 0.0), MeshKit.emissive(Color(1.0, 0.1, 0.05), 4.0), Vector3.ONE, 8)
	lamp.name = "Lamp"
	for mi in parent.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Puts a boot on `car`'s front wheel on `side` (+1 right, -1 left). Returns it (a child of the model).
static func attach(car: Vehicle, side: float) -> Node3D:
	var boot := Node3D.new()
	boot.name = "WheelClamp"
	build_boot(boot)
	var size: Vector3 = car.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var at := Vector3(side * size.x * 0.5, 0.5, -size.z * 0.3) # a guess: front wheel on that side
	var best := INF
	for w in car.model.get_meta("wheels", []):
		var lp := car.model.to_local((w as Node3D).global_position)
		if signf(lp.x) == signf(side) and lp.z < best: # the front-most wheel on that side (cars face -Z)
			best = lp.z
			at = lp
	boot.position = at + Vector3(side * 0.24, 0.0, 0.0)
	boot.rotation = Vector3(0, 0 if side > 0.0 else PI, 0)
	boot.scale = Vector3.ONE * BOOT_SCALE
	car.model.add_child(boot)
	return boot


## The hit (juice guide: tell, impact, aftermath): a yellow flash, a burst of sparks, the clang, the
## boot slams on with a scale pop, a hit-stop and a shake when the player is in it.
static func hit_feel(car: Vehicle, boot: Node3D) -> void:
	var world := car.get_parent()
	var at := boot.global_position if is_instance_valid(boot) else car.global_position
	GameFeel.flash(world, at, 1.6, Color(1.0, 0.8, 0.2), 0.08)
	for k in 4:
		FxKit.spark(world, at, (Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))).normalized())
	GameFeel.play("ram_impact", at, world, -3.0, 1.45, true)
	GameFeel.play("metal_fall", at, world, -5.0, 1.3)
	GameFeel.shake(at, 0.35)
	if car.is_player:
		GameFeel.hitstop(car.get_tree(), 0.06)
	if is_instance_valid(boot):
		boot.scale = Vector3.ONE * BOOT_SCALE * 1.35
		boot.create_tween().tween_property(boot, "scale", Vector3.ONE * BOOT_SCALE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## While the car moves: sparks spray back off the locked wheel and bright scratch lines are left on the
## ground behind it (the trail the owner asked for); the warning lamp blinks.
static func scrape(car: Vehicle, boot: Node3D) -> void:
	var world := car.get_parent()
	var at := boot.global_position
	var g := Specials.ground_below(world, at + Vector3.UP * 0.5)
	var back := -car.linear_velocity.normalized()
	FxKit.spark(world, g + Vector3.UP * 0.1, (back + Vector3.UP * 0.5 + car.global_basis.x * 0.3 * signf(car.global_basis.x.dot(at - car.global_position))).normalized())
	_mark(world, g, car.linear_velocity)
	var lamp := boot.get_node_or_null("Lamp") as Node3D
	if lamp:
		lamp.visible = fmod(Time.get_ticks_msec() * 0.006, 1.0) < 0.55


static func _mark(world: Node, at: Vector3, vel: Vector3) -> void:
	if _mark_mesh == null:
		_mark_mesh = QuadMesh.new()
		_mark_mesh.size = Vector2(0.09, 0.8)
		_mark_mesh.orientation = PlaneMesh.FACE_Y
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.88, 0.86, 0.8, 0.7) # bright scraped tarmac
		_mark_mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = _mark_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var dir := Vector3(vel.x, 0.0, vel.z)
	mi.global_position = at + Vector3.UP * 0.04
	if dir.length() > 0.1:
		mi.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	var tw := mi.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(mi, "scale", Vector3(0.05, 1.0, 1.0), 2.0) # thins away (transparency does nothing on Compatibility)
	tw.tween_callback(mi.queue_free)
	_marks.append(mi)
	_marks.assign(_marks.filter(func(n: Variant) -> bool: return is_instance_valid(n)))
	while _marks.size() > MARKS_MAX:
		(_marks.pop_front() as Node).queue_free()


## Worn through after its 5 s of moving: it snaps and flies off the wheel with a clank.
static func break_off(car: Vehicle, boot: Node3D) -> void:
	var world := car.get_parent()
	var at := boot.global_transform
	boot.get_parent().remove_child(boot)
	world.add_child(boot)
	boot.global_transform = at
	GameFeel.play("metal_fall", at.origin, world, -3.0, 1.1)
	FxKit.puff(world, at.origin, 0.4)
	FxKit.spark(world, at.origin, Vector3.UP)
	var out := car.global_basis.x * signf(car.global_basis.x.dot(at.origin - car.global_position))
	var tw := boot.create_tween().set_parallel(true)
	tw.tween_property(boot, "global_position", at.origin + out * 2.2 + Vector3.UP * 1.2, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(boot, "rotation", boot.rotation + Vector3(3.0, 1.0, 2.0), 0.7)
	tw.chain().tween_property(boot, "global_position", Specials.ground_below(world, at.origin + out * 3.0) + Vector3.UP * 0.2, 0.35).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(2.5)
	tw.chain().tween_callback(boot.queue_free)
