class_name WheelClamp
## Outlaw's secondary weapon (round 18, design 2.3): an iron wheel clamp, a yellow "Denver boot", thrown
## forward with light homing. On a hit it locks onto the target's front wheel on the side it struck:
## for WeaponData "clamp" seconds the car can't use turbo and its steering is dragged to that side, so
## the driver has to keep steering against it (Vehicle.clamp_for / _clamp_step). Sparks fly off the
## locked wheel while it drives; when it lets go the boot drops off with a clank.
## The answer (design): it is slow and easy to see; a hard handbrake turn makes it fly past.

const PULL := 0.55 # how hard the steering is dragged (of full lock): steer against it to drive straight


## The boot: a yellow plate over the wheel face, a jaw arm round the tyre, a heavy padlock. Its plate
## faces +X (outward when put on a right-hand wheel). About 0.7 m across.
static func build_boot(parent: Node3D) -> void:
	var yellow := MeshKit.mat(Color(0.62, 0.45, 0.04), 0.55, 0.35)
	var iron := MeshKit.mat(Color(0.07, 0.07, 0.075), 0.5, 0.6)
	var plate := MeshKit.cylinder(parent, 0.34, 0.07, Vector3.ZERO, yellow, Vector3(0, 0, 90), 12)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MeshKit.cylinder(parent, 0.12, 0.12, Vector3(0.05, 0, 0), iron, Vector3(0, 0, 90), 8)
	MeshKit.box(parent, Vector3(0.1, 0.62, 0.12), Vector3(-0.08, -0.22, 0.0), yellow) # the arm down round the tyre
	MeshKit.box(parent, Vector3(0.42, 0.1, 0.14), Vector3(-0.24, -0.5, 0.0), yellow) # the jaw under it
	MeshKit.box(parent, Vector3(0.14, 0.16, 0.1), Vector3(0.1, -0.3, 0.12), iron) # padlock
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
	boot.position = at + Vector3(side * 0.2, 0.0, 0.0)
	boot.rotation = Vector3(0, 0 if side > 0.0 else PI, 0)
	car.model.add_child(boot)
	return boot
