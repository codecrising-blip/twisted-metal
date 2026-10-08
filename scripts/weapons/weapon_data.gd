class_name WeaponData
extends RefCounted
## Every weapon in the game. Balance numbers live here only.
##   speed    m/s            damage   hit points
##   homing   turn rate rad/s (0 = flies straight)
##   life     seconds before it fizzles
##   cooldown seconds between shots
##   ammo     ammo granted by a pickup
##   kind     visual style: bullet | missile | ghost | freeze

const DEFS := {
	"guns": {
		"label": "Machine Guns", "kind": "bullet", "color": Color(1.0, 0.85, 0.4),
		"speed": 150.0, "damage": 1.6, "homing": 0.0, "life": 0.9, "cooldown": 0.08,
	},
	"homing": {
		"label": "Homing Missile", "kind": "missile", "color": Color(0.45, 0.8, 1.0),
		"speed": 46.0, "damage": 14.0, "homing": 3.2, "life": 5.0, "cooldown": 0.45, "ammo": 3,
	},
	"fire": {
		"label": "Fire Missile", "kind": "missile", "color": Color(1.0, 0.45, 0.1),
		"speed": 78.0, "damage": 20.0, "homing": 1.1, "life": 3.0, "cooldown": 0.45, "ammo": 3,
	},
	"power": {
		"label": "Power Missile", "kind": "missile", "color": Color(1.0, 0.15, 0.2),
		"speed": 58.0, "damage": 42.0, "homing": 0.0, "life": 3.5, "cooldown": 1.0, "ammo": 1,
	},
	"freeze": {
		"label": "Freeze", "kind": "freeze", "color": Color(0.55, 0.9, 1.0),
		"speed": 70.0, "damage": 2.0, "homing": 2.8, "life": 2.5, "cooldown": 0.5, "freeze": 2.5,
	},
	# Specials: one per character, recharge over time.
	"laughing_ghost": {
		"label": "Laughing Ghost", "kind": "ghost", "color": Color(1.0, 0.5, 0.1),
		"speed": 36.0, "damage": 48.0, "homing": 4.2, "life": 7.0, "cooldown": 1.2, "special": true,
	},
	"riot_slug": {
		"label": "Riot Slug", "kind": "missile", "color": Color(0.3, 0.5, 1.0),
		"speed": 95.0, "damage": 30.0, "homing": 0.6, "life": 2.5, "cooldown": 1.2, "special": true,
	},
	"tow_hook": {
		"label": "Tow Hook", "kind": "missile", "color": Color(1.0, 0.8, 0.2),
		"speed": 62.0, "damage": 28.0, "homing": 1.6, "life": 2.5, "cooldown": 1.2, "special": true,
	},
}

## Weapons that can appear in pickup crates.
const PICKUP_WEAPONS := ["homing", "fire", "power"]

const SPECIAL_START_AMMO := 2
const SPECIAL_RECHARGE_SECONDS := 22.0


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})
