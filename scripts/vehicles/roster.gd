class_name Roster
extends RefCounted
## Character / vehicle stats. Add new cars here and a builder in VehicleModels.
## Stats follow docs/design/01-characters.md section 1.1: four stats from 1 to 10 (sum 24) give
##   max_speed = 21.3 + 1.1 * SPD m/s   accel = (10.2 + 0.85 * SPD) * class accel m/s^2
##   health    = 200 + 16 * ARM         handling = 1.5 + 0.12 * HND rad/s   grip = 5.0 + 0.325 * HND
## Owner, play-test 1: speeds like TM: Black (slower, not lazy); play-test 2: 25% slower was too much,
## so it is 15% under the first numbers (25 + 1.3 x SPD). Drifts: session 6 put grip and the
## handbrake numbers halfway back between the first (very loose) and play-test 1 (too stiff) values,
## the same step for every class so the cast stays balanced. No crazy drifts for big cars,
## so heavy classes keep more grip with the handbrake on and turn less sharply.
## ram = ram power 1-10 (round 6): who wins a collision (Vehicle._ram). Weight first, then armour
## and what the car rams with (plows, push bars, spikes). Full cast table: docs/design/11-owner-round-6.md.
## mass class: light 1.0, medium 1.4, heavy 2.0, super 2.8 (rams, knockback, wall speed loss).
## size = collision box (width, height, length); camera = chase camera [height, distance].

## One knob for all health (the owner says "longer fights": raise it a little).
const HEALTH_SCALE := 1.0
## Round 6 (owner, after the physical car): every car 1.2x faster (top speed, pick-up, reverse) and
## handbrake drifts 1.15x stronger (sharper drift turn, looser drift grip), same step for every class.
const SPEED_SCALE := 1.2
const DRIFT_SCALE := 1.15

const MASS := {"light": 1.0, "medium": 1.4, "heavy": 2.0, "super": 2.8}
## How hard a car is pushed by hits, per mass class.
const KNOCKBACK := {"light": 1.3, "medium": 1.0, "heavy": 0.7, "super": 0.5}
## Per class: acceleration factor, grip kept with the handbrake on, turn rate with the handbrake on.
const CLASS_ACCEL := {"light": 1.1, "medium": 1.0, "heavy": 0.9, "super": 0.8}
const DRIFT_GRIP := {"light": 0.26, "medium": 0.3, "heavy": 0.36, "super": 0.41}
const DRIFT_TURN := {"light": 1.62, "medium": 1.55, "heavy": 1.46, "super": 1.41}

const CARS := {
	"sweet_tooth": {
		"name": "Sweet Tooth", "ram": 7.5, "engine": "ic_truck", "driver": "Needles Kane",
		"spd": 4, "arm": 8, "hnd": 4, "spc": 8, "class": "heavy",
		"special": "napalm_cone", "freeze_cost": 35.0, # perk: Brain Freeze
		"size": Vector3(2.5, 2.8, 6.6), "camera": [6.4, 13.0],
		"tagline": "He laughs louder than the engine.",
	},
	"outlaw": {
		"name": "Outlaw", "ram": 5.0, "engine": "taxi", "driver": "Jamie Roberts", "female": true,
		"spd": 7, "arm": 6, "hnd": 6, "spc": 5, "class": "medium",
		"special": "omni_taser", "brake_mult": 1.3, # perk: Interceptor
		"size": Vector3(2.2, 1.6, 5.0),
		"tagline": "She stopped telling them it was about justice.",
	},
	"junkyard_dog": {
		"name": "Junkyard Dog", "ram": 7.0, "engine": "tow", "driver": "Billy Ray Stillwell",
		"spd": 5, "arm": 8, "hnd": 4, "spc": 7, "class": "heavy",
		"special": "chain_bomb",
		"size": Vector3(2.4, 2.0, 5.8),
		"tagline": "Everything ends up in his yard.",
	},
	"mr_grimm": {
		"name": "Mr. Grimm", "ram": 2.5, "engine": "moto", "driver": "Mr. Grimm",
		"spd": 8, "arm": 1, "hnd": 6, "spc": 9, "class": "light",
		"special": "reaper_skull",
		"size": Vector3(2.0, 1.9, 3.2), "camera": [3.8, 9.0],
		"tagline": "Death rides a motorcycle.",
	},
	"spectre": {
		"name": "Spectre", "ram": 3.5, "engine": "suv", "driver": "Ken",
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
	c["max_speed"] = (21.3 + 1.1 * spd) * SPEED_SCALE
	c["accel"] = (10.2 + 0.85 * spd) * float(CLASS_ACCEL.get(cls, 1.0)) * SPEED_SCALE
	c["reverse"] = 10.0 * SPEED_SCALE
	c["max_health"] = (200.0 + 16.0 * arm) * HEALTH_SCALE
	c["handling"] = 1.5 + 0.12 * hnd
	c["grip"] = 5.0 + 0.325 * hnd
	c["drift_grip"] = float(DRIFT_GRIP.get(cls, 0.38)) / DRIFT_SCALE
	c["drift_turn"] = float(DRIFT_TURN.get(cls, 1.4)) * DRIFT_SCALE
	c["mass"] = MASS.get(c.get("class", "medium"), 1.4)
	c["knockback"] = KNOCKBACK.get(c.get("class", "medium"), 1.0)
	_cache[id] = c
	return c
