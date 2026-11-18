class_name WheelClamp
## Outlaw's secondary weapon (design 2.3; round 19, the owner's rules): a big heavy police wheel clamp thrown
## forward with light homing. A hit locks the wheels on the side it struck (Vehicle.clamp_for): while the
## car moves it can only turn the other way, no turbo, no reverse; it wears off after 5 s of DRIVING (moving,
## or gas held against a wall) and scrapes SCRAPE_DPS meanwhile (25 in all): sparks, a glowing ribbon and
## bright scratch lines trailing behind the wheel.
## The answer (design): it is slow and easy to see; a hard handbrake turn makes it fly past.

const MIN_TURN := 0.6 # the least it turns toward the free side while moving (of full lock)
const MOVING_SPEED := 2.0 # m/s: slower than this the car counts as standing still...
const GAS_GRINDS := 0.2 # ...unless the gas is held (pushing against a wall still wears the clamp: owner)
const SCRAPE_DPS := 5.0 # 25 over the 5 s of moving
const MARKS_MAX := 70

static var _marks: Array = []
static var _mark_mesh: QuadMesh


const LAMPS := ["lamp_red", "lamp_blue"] # blink in turn
const MODEL_R := 0.5 # the Blender clamps are built round a wheel this big
const SIZE := 1.3 # x the car's wheel (owner, round 19): bigger than the wheel itself, so nobody misses it


## The clamp, its plate facing +X (outward on a right-hand wheel), about a 0.5 m wheel: the owner's pick of
## four (round 19, look C, a police impound lock as heavy as a weight plate; tools/blender/build_wheel_clamp.py),
## lamps as children named "Lamp*" blinking while it holds. The old primitives if the model is missing.
static func build_boot(parent: Node3D) -> void:
	if ModelLib.has("wheel_clamp"):
		parent.add_child(ModelLib.instance("wheel_clamp", "clamp"))
		var k := 0
		for lamp_name: String in LAMPS:
			var l := ModelLib.instance("wheel_clamp", lamp_name)
			l.name = "Lamp%d" % k
			parent.add_child(l)
			k += 1
	else:
		_build_simple(parent)
	for mi in parent.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _build_simple(parent: Node3D) -> void:
	var yellow := MeshKit.emissive(Color(1.0, 0.74, 0.04), 0.35)
	yellow.roughness = 0.5
	var red := MeshKit.emissive(Color(0.85, 0.06, 0.04), 0.4)
	var white := MeshKit.emissive(Color(0.95, 0.95, 0.9), 0.3)
	var iron := MeshKit.mat(Color(0.07, 0.07, 0.075), 0.5, 0.6)
	MeshKit.cylinder(parent, 0.38, 0.08, Vector3(0.25, 0, 0), yellow, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.3, 0.09, Vector3(0.255, 0, 0), red, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.26, 0.1, Vector3(0.26, 0, 0), white, Vector3(0, 0, 90), 16)
	MeshKit.cylinder(parent, 0.09, 0.16, Vector3(0.31, 0, 0), iron, Vector3(0, 0, 90), 8)
	MeshKit.box(parent, Vector3(0.5, 0.12, 0.18), Vector3(0.0, 0.42, 0.0), yellow)
	var lamp := MeshKit.sphere(parent, 0.07, Vector3(0.25, 0.46, 0.0), MeshKit.emissive(Color(1.0, 0.1, 0.05), 4.0), Vector3.ONE, 8)
	lamp.name = "Lamp0"


## Puts a boot on `car`'s front wheel on `side` (+1 right, -1 left), sized to the wheel and mirrored for a
## left one. Returns it (a child of the model). A bright ribbon is dragged from its foot (the trail).
static func attach(car: Vehicle, side: float) -> Node3D:
	var boot := Node3D.new()
	boot.name = "WheelClamp"
	build_boot(boot)
	var size: Vector3 = car.stats.get("size", Vector3(2.2, 1.8, 5.0))
	var radius := float(car.model.get_meta("wheel_radius", 0.5))
	var at := Vector3(side * size.x * 0.5, radius, -size.z * 0.3) # a guess: front wheel on that side
	var half := 0.19 # the tyre's half width
	var best := INF
	for w in car.model.get_meta("wheels", []):
		var lp := car.model.to_local((w as Node3D).global_position)
		if (signf(lp.x) == signf(side) or absf(lp.x) < 0.15) and lp.z < best: # front-most wheel on that side (bikes: the middle)
			best = lp.z
			at = lp
			for mi in (w as Node3D).find_children("*", "MeshInstance3D", true, false):
				half = maxf(half, (mi as MeshInstance3D).get_aabb().size.x * 0.5)
	var k := radius / MODEL_R * SIZE
	boot.position = at + Vector3(side * maxf(0.0, half - 0.19 * k), 0.0, 0.0)
	boot.scale = Vector3(side * k, k, k) # mirrored for a left wheel: the face still looks outward
	boot.set_meta("k", k)
	car.model.add_child(boot)
	var foot := Node3D.new() # where the clamp grinds on the road: the trail is dragged from here
	foot.name = "Foot"
	foot.position = Vector3(0.28, -MODEL_R + 0.04, 0.0)
	boot.add_child(foot)
	var trail := Streak.attach(foot, Color(1.0, 0.62, 0.12), 0.45, 0.22)
	trail.set_meta("clamp_trail", true)
	boot.set_meta("trail", trail)
	return boot


## The lamps blink the whole time it holds (police C: red and blue in turn).
static func blink(boot: Node3D) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var on := fmod(t * 3.2, 1.0) < 0.5
	for c in boot.get_children():
		if String(c.name).begins_with("Lamp"):
			var idx := int(String(c.name).substr(4))
			(c as Node3D).visible = on if idx % 2 == 0 else not on


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
		var rest := boot.scale
		boot.scale = rest * 1.4
		boot.create_tween().tween_property(boot, "scale", rest, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	GameFeel.shockwave(world, at, 2.4, Color(1.0, 0.75, 0.2))


## While the car moves: sparks spray back off the locked wheel and bright scratch lines are left on the
## ground behind it (the trail the owner asked for); the warning lamp blinks.
static func scrape(car: Vehicle, boot: Node3D, moving := true) -> void:
	var world := car.get_parent()
	var at := boot.global_position
	var g := Specials.ground_below(world, at + Vector3.UP * 0.5)
	var back := -car.linear_velocity.normalized() if moving else car.global_basis.z # spinning on the spot: thrown back
	FxKit.spark(world, g + Vector3.UP * 0.1, (back + Vector3.UP * 0.5 + car.global_basis.x * 0.3 * signf(car.global_basis.x.dot(at - car.global_position))).normalized())
	if moving:
		_mark(world, g, car.linear_velocity)


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
