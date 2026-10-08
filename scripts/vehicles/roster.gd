class_name Roster
extends RefCounted
## Character / vehicle stats. Add new cars here and a builder in VehicleModels.
##   max_speed m/s, accel m/s^2, handling turn rate rad/s, grip = how fast sideways slide dies
##   size = collision box (width, height, length)
##   camera = chase camera [height, distance] (tall cars need a higher camera)

const CARS := {
	"sweet_tooth": {
		"name": "Sweet Tooth", "driver": "Needles Kane",
		"max_health": 150.0, "max_speed": 30.0, "accel": 17.0, "reverse": 12.0,
		"handling": 2.0, "grip": 5.5, "special": "laughing_ghost",
		"size": Vector3(2.4, 2.0, 5.6),
		"camera": [6.2, 12.5],
		"tagline": "He laughs louder than the engine.",
	},
	"outlaw": {
		"name": "Outlaw", "driver": "",
		"max_health": 105.0, "max_speed": 34.0, "accel": 21.0, "reverse": 13.0,
		"handling": 2.4, "grip": 6.5, "special": "riot_slug",
		"size": Vector3(2.2, 1.8, 4.8),
		"tagline": "",
	},
	"junkyard_dog": {
		"name": "Junkyard Dog", "driver": "",
		"max_health": 130.0, "max_speed": 28.0, "accel": 16.0, "reverse": 11.0,
		"handling": 1.9, "grip": 5.0, "special": "tow_hook",
		"size": Vector3(2.4, 2.0, 5.8),
		"tagline": "",
	},
}


static func get_car(id: String) -> Dictionary:
	return CARS.get(id, {})
