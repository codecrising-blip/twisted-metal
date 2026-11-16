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
## Round 7 (owner: "still slow, even Outlaw"): every car 1.4x the round-5 speed (top speed, pick-up,
## reverse) and handbrake drifts 1.2x stronger (sharper drift turn, looser drift grip), same for every class.
const SPEED_SCALE := 1.26 # round 7: 1.4; round 11 (owner): 10% slower
const DRIFT_SCALE := 1.2
const REVERSE_SCALE := 1.84 # owner: x1.6 (round 9), then x1.15 on top (round 10)
const REVERSE_ACCEL := 1.12 # share of forward acceleration in reverse: 0.7 x 1.6 (round 10: quick out of a wall slam)

const MASS := {"light": 1.0, "medium": 1.4, "heavy": 2.0, "super": 2.8}
## How hard a car is pushed by hits, per mass class.
const KNOCKBACK := {"light": 1.3, "medium": 1.0, "heavy": 0.7, "super": 0.5}
## Per class: acceleration factor, grip kept with the handbrake on, turn rate with the handbrake on.
const CLASS_ACCEL := {"light": 1.1, "medium": 1.0, "heavy": 0.9, "super": 0.8}
## U-turn slides (owner, round 11, "tafheet"): at speed, hold the handbrake and a direction and the
## car swings round in one slide, as far as its class allows, then the tyres bite.
##   max       degrees one hold can turn
##   turbo_to  boosting during the slide lets it carry on this far (0 = turbo doesn't help)
##   turbo_rate how fast it still turns while boosting (super heavy: slower, a wider arc)
##   taps      re-pressing the handbrake (within SLIDE_TAP_WINDOW) buys more turn, at a cost in speed
## Light cars (and Outlaw, "uturn": "light") turn a full 180 in one hold; mid cars 160 and need turbo
## for the rest; heavy 140, turbo doesn't help, taps do (a curved, slower U); super heavy 120, turbo
## finishes it in a wide arc.
const UTURN := {
	"light": {"max": 180.0, "turbo_to": 0.0, "turbo_rate": 1.0, "taps": false},
	"medium": {"max": 160.0, "turbo_to": 180.0, "turbo_rate": 1.0, "taps": false},
	"heavy": {"max": 140.0, "turbo_to": 0.0, "turbo_rate": 1.0, "taps": true},
	"super": {"max": 120.0, "turbo_to": 180.0, "turbo_rate": 0.55, "taps": false},
}


## The U-turn profile of a car (its own "uturn" class if it has one, else its weight class).
static func uturn(stats: Dictionary) -> Dictionary:
	return UTURN.get(String(stats.get("uturn", stats.get("class", "medium"))), UTURN["medium"])
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
		# Round 11 (owner): she U-turns like a light car, and her turbo tank holds 1.4x (7 s instead of 5).
		"uturn": "light", "turbo_tank": 1.4,
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

## Round 12 (owner): specials per car. Every life starts with SPECIAL_START; one recharges at a time
## (the weapon's "recharge" seconds) up to the car's max, which follows how hard the special is to land:
## easy ones 3, hard ones 5, the rest 4. (Thumper's Megafire is a fuel tank instead: 10 s, design.)
const SPECIAL_START := 2
const SPECIAL_MAX := {
	"spectre": 3, "warthog": 3, "crimson_fury": 3, "shadow": 3,
	"mr_slam": 5, "hammerhead": 5, "yellow_jacket": 5, "darkside": 5,
}

static func special_max(id: String) -> int:
	return int(SPECIAL_MAX.get(id, 4))


## Round 13 (owner): steering in the air, by class (Outlaw flies like the light cars). rate = turn
## rad/s (a 6 m jump lasts ~1.3 s: light ~140 deg, medium ~105, heavy ~70, super ~40 if held);
## carry = the share of that turn the flight path follows (the rest comes from turbo along the nose).
const AIR_TURN := {
	"light": {"rate": 2.0, "carry": 0.35},
	"medium": {"rate": 1.5, "carry": 0.28},
	"heavy": {"rate": 1.0, "carry": 0.2},
	"super": {"rate": 0.6, "carry": 0.14},
}

static func air_turn(stats: Dictionary) -> Dictionary:
	return AIR_TURN.get(String(stats.get("uturn", stats.get("class", "medium"))), AIR_TURN["medium"])


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
	c["reverse"] = 10.0 * SPEED_SCALE * REVERSE_SCALE
	c["max_health"] = (200.0 + 16.0 * arm) * HEALTH_SCALE
	c["handling"] = 1.5 + 0.12 * hnd
	c["grip"] = 5.0 + 0.325 * hnd
	c["drift_grip"] = float(DRIFT_GRIP.get(cls, 0.38)) / DRIFT_SCALE
	c["drift_turn"] = float(DRIFT_TURN.get(cls, 1.4)) * DRIFT_SCALE
	c["mass"] = MASS.get(c.get("class", "medium"), 1.4)
	c["knockback"] = KNOCKBACK.get(c.get("class", "medium"), 1.0)
	_cache[id] = c
	return c
