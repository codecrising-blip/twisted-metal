class_name Roster
extends RefCounted
## Character / vehicle stats. Add new cars here and a builder in VehicleModels.
## Stats follow docs/design/01-characters.md section 1.1: four stats from 1 to 10 (sum 24) give
##   max_speed = 25 + 1.3 * SPD m/s     accel = 12 + SPD m/s^2
##   health    = 200 + 16 * ARM         handling = 1.5 + 0.12 * HND rad/s   grip = 4.0 + 0.3 * HND
## mass class: light 1.0, medium 1.4, heavy 2.0, super 2.8 (rams, knockback, wall speed loss).
## size = collision box (width, height, length); camera = chase camera [height, distance].

## One knob for all health (the owner says "longer fights": raise it a little).
const HEALTH_SCALE := 1.0

const MASS := {"light": 1.0, "medium": 1.4, "heavy": 2.0, "super": 2.8}
## How hard a car is pushed by hits, per mass class.
const KNOCKBACK := {"light": 1.3, "medium": 1.0, "heavy": 0.7, "super": 0.5}

const CARS := {
	"sweet_tooth": {
		"name": "Sweet Tooth", "driver": "Needles Kane",
		"spd": 4, "arm": 8, "hnd": 4, "spc": 8, "class": "heavy",
		"special": "napalm_cone", "freeze_cost": 35.0, # perk: Brain Freeze
		"size": Vector3(2.5, 2.6, 6.3), "camera": [6.4, 13.0],
		"tagline": "He laughs louder than the engine.",
	},
	"outlaw": {
		"name": "Outlaw", "driver": "Jamie Roberts",
		"spd": 7, "arm": 6, "hnd": 6, "spc": 5, "class": "medium",
		"special": "omni_taser", "brake_mult": 1.3, # perk: Interceptor
		"size": Vector3(2.2, 1.6, 5.0),
		"tagline": "She stopped telling them it was about justice.",
	},
	"junkyard_dog": {
		"name": "Junkyard Dog", "driver": "Billy Ray Stillwell",
		"spd": 5, "arm": 8, "hnd": 4, "spc": 7, "class": "heavy",
		"special": "chain_bomb",
		"size": Vector3(2.4, 2.0, 5.8),
		"tagline": "Everything ends up in his yard.",
	},
	"mr_grimm": {
		"name": "Mr. Grimm", "driver": "Mr. Grimm",
		"spd": 8, "arm": 1, "hnd": 6, "spc": 9, "class": "light",
		"special": "reaper_skull",
		"size": Vector3(2.0, 1.9, 3.2), "camera": [3.8, 9.0],
		"tagline": "Death rides a motorcycle.",
	},
	"spectre": {
		"name": "Spectre", "driver": "Ken",
		"spd": 8, "arm": 2, "hnd": 8, "spc": 6, "class": "light",
		"special": "ghost_missile",
		"size": Vector3(2.1, 1.4, 4.6), "camera": [3.8, 9.5],
		"tagline": "Through walls, through you.",
	},
}

static var _cache := {}


static func get_car(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var base: Dictionary = CARS.get(id, {})
	if base.is_empty():
		return {}
	var c := base.duplicate()
	var spd: int = c.get("spd", 5)
	var arm: int = c.get("arm", 5)
	var hnd: int = c.get("hnd", 5)
	c["max_speed"] = 25.0 + 1.3 * spd
	c["accel"] = 12.0 + spd
	c["reverse"] = 12.0
	c["max_health"] = (200.0 + 16.0 * arm) * HEALTH_SCALE
	c["handling"] = 1.5 + 0.12 * hnd
	c["grip"] = 4.0 + 0.3 * hnd
	c["mass"] = MASS.get(c.get("class", "medium"), 1.4)
	c["knockback"] = KNOCKBACK.get(c.get("class", "medium"), 1.0)
	_cache[id] = c
	return c
