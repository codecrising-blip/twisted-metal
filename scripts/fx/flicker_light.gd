class_name FlickerLight
extends OmniLight3D
## Fire-like flicker for barrels and burning wrecks.

@export var base_energy := 2.5
@export var amount := 0.35
@export var speed := 9.0

var _t := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * speed
	var n := sin(_t + _seed) * 0.5 + sin(_t * 2.7 + _seed * 3.0) * 0.3 + randf_range(-0.2, 0.2)
	light_energy = base_energy * (1.0 + n * amount)
