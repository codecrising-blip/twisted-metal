class_name WeaponData
extends RefCounted
## Every weapon in the game. Balance numbers live here only (design: docs/design/01-characters.md
## and the owner's overrides in 05-owner-revisions-1.md).
##   speed    m/s            damage   hit points
##   homing   turn rate rad/s (0 = flies straight)
##   life     seconds before it fizzles
##   cooldown seconds before the same car can fire again
##   ammo     ammo granted by a pickup
##   burn     seconds of Burning on hit
##   kind     bullet | missile | freeze | lob | skull | ghost
##   charges / recharge   specials: charges held and seconds to refill one
##   handler  specials with their own behaviour (see Specials)

## One knob for all damage (the owner says "faster fights": raise it a little).
const DAMAGE_SCALE := 1.0

const DEFS := {
	"guns": {
		"label": "Machine Guns", "kind": "bullet", "color": Color(1.0, 0.85, 0.4),
		"speed": 150.0, "damage": 0.55, "homing": 0.0, "life": 0.9, "cooldown": 0.08,
	},
	"homing": {
		"label": "Homing Missile", "kind": "missile", "color": Color(0.45, 0.8, 1.0),
		"speed": 46.0, "damage": 12.0, "homing": 3.2, "life": 5.0, "cooldown": 0.45, "ammo": 3,
	},
	"fire": {
		"label": "Fire Missile", "kind": "missile", "color": Color(1.0, 0.45, 0.1),
		"speed": 78.0, "damage": 14.0, "homing": 1.1, "life": 3.0, "cooldown": 0.45, "ammo": 3, "burn": 4.0,
	},
	"power": {
		"label": "Power Missile", "kind": "missile", "color": Color(1.0, 0.15, 0.2),
		"speed": 58.0, "damage": 45.0, "homing": 0.0, "life": 3.5, "cooldown": 1.0, "ammo": 1,
	},
	"freeze": {
		"label": "Freeze", "kind": "freeze", "color": Color(0.55, 0.9, 1.0),
		"speed": 70.0, "damage": 3.0, "homing": 2.2, "life": 2.5, "cooldown": 0.5, "freeze": 2.0,
	},
	# ---- Specials: one per driver.
	# Sweet Tooth: flaming ice cream cone lobbed to where the target will be. Leaves a fire pool.
	"napalm_cone": {
		"label": "Napalm Cone", "kind": "lob", "color": Color(1.0, 0.5, 0.15), "special": true,
		"damage": 30.0, "splash": 15.0, "splash_radius": 4.0, "burn": 4.0, "pool_radius": 2.0, "pool_time": 5.0,
		"min_range": 12.0, "max_range": 70.0, "life": 3.0, "cooldown": 1.0, "charges": 2, "recharge": 18.0,
	},
	# Outlaw (Jamie Roberts): Crazy 8-style taser. Fired by the player; grows with link time and
	# fire-button mashing; breaks when the target gets too far away.
	"omni_taser": {
		"label": "Omni Taser", "kind": "beam", "color": Color(0.55, 0.75, 1.0), "special": true, "handler": "taser",
		"range": 25.0, "break_range": 32.0, "dps": 8.0, "dps_per_mash": 1.5, "max_dps": 20.0, "duration": 3.0,
		"cooldown": 1.0, "charges": 2, "recharge": 19.0,
	},
	# Junkyard Dog (Billy Ray Stillwell): spiked bomb on the crane chain. Straight throw, press fire
	# again to detonate; at the end of the chain it drops and blows after 3 s.
	"chain_bomb": {
		"label": "Chain Bomb", "kind": "bomb", "color": Color(1.0, 0.25, 0.1), "special": true, "handler": "chain_bomb",
		"speed": 45.0, "chain": 25.0, "radius": 7.0, "damage": 30.0, "edge_damage": 15.0, "stuck_bonus": 10.0,
		"fuse": 3.0, "cooldown": 1.0, "charges": 2, "recharge": 15.0,
	},
	# Mr. Grimm: TM2 flaming skull. Owner: three hits kill a medium car (280).
	"reaper_skull": {
		"label": "Reaper Skull", "kind": "skull", "color": Color(1.0, 0.55, 0.15), "special": true,
		"speed": 85.0, "damage": 94.0, "homing": 0.6, "life": 2.5, "cooldown": 3.0, "charges": 2, "recharge": 20.0,
	},
	# Spectre: ghost missile that flies through walls.
	"ghost_missile": {
		"label": "Ghost Missile", "kind": "ghost", "color": Color(0.5, 0.9, 1.0), "special": true,
		"speed": 50.0, "damage": 24.0, "homing": 3.0, "life": 4.0, "cooldown": 0.6, "charges": 3, "recharge": 18.0,
		"through_walls": true,
	},
}

## Weapons that can appear in pickups and breakable stands.
const PICKUP_WEAPONS := ["homing", "homing", "fire", "fire", "power"]

## Owner, session 3: a health pickup restores a share of max health, so armor matters all match.
const HEALTH_PICKUP_RATIO := 0.30
const MEGA_HEALTH_RATIO := 0.60 # proposal, waiting for the owner
const HEALTH_RESPAWN := 30.0
const MEGA_RESPAWN := 50.0
const WEAPON_RESPAWN := 14.0

const BURN_DPS := 3.0


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func damage(id: String, key := "damage") -> float:
	return float(get_def(id).get(key, 0.0)) * DAMAGE_SCALE
