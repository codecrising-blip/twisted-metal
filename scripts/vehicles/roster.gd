class_name Roster
extends RefCounted
## Character / vehicle stats. Add new cars here and a builder in VehicleModels.
## Stats follow docs/design/01-characters.md section 1.1: four stats from 1 to 10 (sum 24) give
##   max_speed = 19 + 1.1 * SPD m/s     accel = (8 + 0.9 * SPD) * class accel m/s^2
##   health    = 200 + 16 * ARM         handling = 1.5 + 0.12 * HND rad/s   grip = 6.0 + 0.35 * HND
## Owner, play-test 1: speeds like TM: Black (slower, not lazy) and no crazy drifts for big cars,
## so heavy classes keep more grip with the handbrake on and turn less sharply.
## mass class: light 1.0, medium 1.4, heavy 2.0, super 2.8 (rams, knockback, wall speed loss).
## size = collision box (width, height, length); camera = chase camera [height, distance].

## One knob for all health (the owner says "longer fights": raise it a little).
const HEALTH_SCALE := 1.0

const MASS := {"light": 1.0, "medium": 1.4, "heavy": 2.0, "super": 2.8}
## How hard a car is pushed by hits, per mass class.
const KNOCKBACK := {"light": 1.3, "medium": 1.0, "heavy": 0.7, "super": 0.5}
## Per class: acceleration factor, grip kept with the handbrake on, turn rate with the handbrake on.
const CLASS_ACCEL := {"light": 1.1, "medium": 1.0, "heavy": 0.9, "super": 0.8}
const DRIFT_GRIP := {"light": 0.3, "medium": 0.38, "heavy": 0.5, "super": 0.6}
const DRIFT_TURN := {"light": 1.55, "medium": 1.4, "heavy": 1.22, "super": 1.12}

const CARS := {
	"sweet_tooth": {
		"name": "Sweet Tooth", "driver": "Needles Kane",
		"spd": 4, "arm": 8, "hnd": 4, "spc": 8, "class": "heavy",
		"special": "napalm_cone", "freeze_cost": 35.0, # perk: Brain Freeze
		"size": Vector3(2.5, 2.8, 6.6), "camera": [6.4, 13.0],
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
	var cls: String = c.get("class", "medium")
	c["max_speed"] = 19.0 + 1.1 * spd
	c["accel"] = (8.0 + 0.9 * spd) * float(CLASS_ACCEL.get(cls, 1.0))
	c["reverse"] = 10.0
	c["max_health"] = (200.0 + 16.0 * arm) * HEALTH_SCALE
	c["handling"] = 1.5 + 0.12 * hnd
	c["grip"] = 6.0 + 0.35 * hnd
	c["drift_grip"] = DRIFT_GRIP.get(cls, 0.38)
	c["drift_turn"] = DRIFT_TURN.get(cls, 1.4)
	c["mass"] = MASS.get(c.get("class", "medium"), 1.4)
	c["knockback"] = KNOCKBACK.get(c.get("class", "medium"), 1.0)
	_cache[id] = c
	return c
