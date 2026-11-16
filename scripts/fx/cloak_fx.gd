class_name CloakFx
extends Node3D
## Invisibility the TM2 way (round 16, the owner's pick from the series' evolution clip): blue sparks
## crackle over the body for 0.8 s while it breaks up and fades, then the car is simply gone, for
## everyone, its own driver too. Coming back is the same, quicker. The car (Vehicle._energy_tick)
## drives the fade; this node draws the sparks: a spray of blue star points over the body and a few
## tiny arcs crawling on it (one Bolt mesh).

const SPARK_COLOR := Color(0.45, 0.65, 1.0)

var car: Vehicle
var size := Vector3(2.2, 1.8, 5.0)
var _sparks: CPUParticles3D
var _bolt: Bolt
var _left := 0.0
var _redraw := 0.0


func _ready() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.mesh = FxKit.particle_mesh(true)
	_sparks.amount = 30
	_sparks.lifetime = 0.22
	_sparks.local_coords = true
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparks.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.45, size.z * 0.5)
	_sparks.position = Vector3(0, size.y * 0.5, 0)
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 0.5
	_sparks.initial_velocity_max = 2.5
	_sparks.gravity = Vector3.ZERO
	_sparks.scale_amount_min = 0.05
	_sparks.scale_amount_max = 0.15
	_sparks.color = SPARK_COLOR
	_sparks.color_ramp = FxKit._ramp([Color(0.85, 0.92, 1.0, 1.0), Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b, 0.9), Color(0.1, 0.2, 0.6, 0.0)])
	_sparks.emitting = false
	add_child(_sparks)
	_bolt = Bolt.new()
	_bolt.tint = SPARK_COLOR
	add_child(_bolt)


## Sparks for `seconds` (going invisible: 0.8 s; coming back: shorter).
func play(seconds: float) -> void:
	_left = seconds
	_sparks.emitting = true


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_sparks.emitting = false
		_bolt.begin()
		_bolt.finish()
		return
	_redraw -= delta
	if _redraw > 0.0 or car == null:
		return
	_redraw = 1.0 / 30.0
	_bolt.begin()
	var xf := car.global_transform
	for k in 3: # tiny arcs crawling over the panels
		var a := Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.2, 0.95) * size.y, randf_range(-0.5, 0.5) * size.z)
		var b := a + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.9, 0.9))
		_bolt.strand(Bolt.jagged(xf * a, xf * b, 2, 0.4), 0.03, 0.01, randf_range(0.5, 1.0))
	_bolt.finish()
