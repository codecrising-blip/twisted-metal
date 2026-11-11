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
##   kind     bullet | missile | freeze | cone | gas | remote | skull | ghost | sat (look and flight)
##   charges / recharge   specials: charges held and seconds to refill one
##   handler  weapons with their own behaviour (see Specials)
##   icon     HUD icon when it differs from kind
##   trail / trail_len / trail_w   ribbon behind the shot: colour, seconds of history (length), width
##   push     m/s shove on the car it hits (along the shot, scaled by the car's weight class)
##   Friendly fire (owner, play-test 2): blasts, fire pools, mines and the SAT beam hurt their own
##   shooter too. Only a direct hit can't strike the car that fired it.

## One knob for all damage (the owner says "faster fights": raise it a little).
const DAMAGE_SCALE := 1.0

const DEFS := {
	"guns": {
		"label": "Machine Guns", "kind": "bullet", "color": Color(1.0, 0.85, 0.4),
		"speed": 150.0, "damage": 0.55, "homing": 0.0, "life": 0.9, "cooldown": 0.08,
	},
	"homing": {
		"label": "Homing Missile", "kind": "missile", "color": Color(0.62, 0.3, 1.0),
		"speed": 46.0, "damage": 12.0, "homing": 3.2, "life": 5.0, "cooldown": 0.45, "ammo": 3, "push": 2.5,
		"trail": Color(0.6, 0.2, 1.0), "trail_len": 0.3, "trail_w": 0.8,
	},
	"fire": {
		"label": "Fire Missile", "kind": "missile", "color": Color(1.0, 0.42, 0.08),
		"speed": 78.0, "damage": 14.0, "homing": 1.1, "life": 3.0, "cooldown": 0.45, "ammo": 3, "burn": 4.0, "push": 3.0,
		"trail": Color(1.0, 0.45, 0.05), "trail_len": 0.18, "trail_w": 0.9,
	},
	"power": {
		"label": "Power Missile", "kind": "missile", "color": Color(0.95, 0.12, 0.15),
		"speed": 58.0, "damage": 45.0, "homing": 0.0, "life": 3.5, "cooldown": 1.0, "ammo": 1, "push": 9.0,
		"trail": Color(0.95, 0.06, 0.05), "trail_len": 0.4, "trail_w": 1.3, "model_scale": 1.6,
	},
	# TM: Black's gas can. Thrown up and ahead; press fire again to drop it on the spot.
	# It bursts into a pool of fire: everything inside burns.
	"napalm": {
		"label": "Napalm", "kind": "gas", "handler": "napalm", "color": Color(1.0, 0.55, 0.1),
		"throw": 34.0, "lift": 15.0, "drop_speed": 26.0, "life": 4.0, "cooldown": 0.6, "ammo": 1,
		"damage": 30.0, "radius": 6.0, "burn": 5.0, "pool_radius": 4.5, "pool_time": 6.0,
	},
	# Remote (owner, play-test 2): a mine dropped behind the car. Press fire again to blow it, or
	# it goes off when any car (yours too) drives onto it. Big push: cars on top fly high and flip,
	# cars at the side get thrown away. Full damage in the middle, less at the edge.
	"remote": {
		"label": "Remote", "kind": "mine", "handler": "mine", "icon": "remote", "color": Color(0.95, 0.2, 0.15),
		"cooldown": 0.6, "ammo": 1, "arm": 0.8, "trigger": 2.4, "life": 90.0,
		"damage": 50.0, "edge_damage": 20.0, "radius": 8.0, "core": 3.5, "push": 16.0,
		# Height (m) a car right on top is thrown, by weight (owner, session 6): light cars like Grimm
		# and Twister fly highest, super-heavy Darkside the least.
		"launch": {"light": 12.0, "medium": 8.4, "heavy": 5.4, "super": 3.0},
	},
	# Ten light missiles with mid tracking (owner): 6 each, 60 if all hit. Driving straight takes
	# them all; a hard drift shakes off about half.
	"zoomy": {
		"label": "Zoomy", "kind": "missile", "handler": "salvo", "icon": "salvo", "color": Color(0.85, 0.9, 0.2),
		"speed": 62.0, "damage": 6.0, "homing": 1.6, "life": 3.0, "cooldown": 1.0, "ammo": 1, "push": 0.8,
		"salvo": 10, "salvo_gap": 0.06, "small": true, "model_scale": 0.6,
		"trail": Color(0.97, 0.97, 0.95), "trail_len": 0.55, "trail_w": 0.42,
	},
	# Satellite strike (owner, play-test 2): the strike zone is locked in front of YOUR car and moves
	# with you for 4 s; steer to keep the enemy inside it, then the beam hits the zone for 112.
	"sat": {
		"label": "SAT", "kind": "sat", "handler": "sat", "color": Color(0.3, 0.95, 0.8),
		"damage": 112.0, "radius": 7.5, "delay": 4.0, "ahead": 24.0, "cooldown": 1.0, "ammo": 1,
	},
	# Energy move only (front / rear freeze), never a pickup.
	"freeze": {
		"label": "Freeze", "kind": "freeze", "color": Color(0.55, 0.9, 1.0),
		"speed": 70.0, "damage": 3.0, "homing": 2.2, "life": 2.5, "cooldown": 0.5, "freeze": 2.0,
	},
	# ---- Specials: one per driver.
	# Sweet Tooth (owner, play-test 1, Head-On style): tap = a homing flaming cone, 45 (a power
	# missile's damage) + burning. Hold fire 2 s and let go = charged cone, 90 + burning, but it
	# flies straight like a power missile (no tracking).
	"napalm_cone": {
		"label": "Napalm Cone", "kind": "cone", "handler": "cone", "color": Color(1.0, 0.5, 0.15), "special": true,
		"speed": 60.0, "damage": 45.0, "homing": 2.4, "life": 3.0, "burn": 4.0, "push": 6.0,
		"charge_time": 2.0, "charged_damage": 90.0, "charged_speed": 64.0,
		"cooldown": 0.8, "charges": 2, "recharge": 16.0,
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
	# Mr. Grimm: TM2 flaming skull. Owner (session 4): 65, the hardest single special hit but no
	# instant kills (a medium car, 280, takes five).
	"reaper_skull": {
		"label": "Reaper Skull", "kind": "skull", "color": Color(1.0, 0.55, 0.15), "special": true,
		"speed": 85.0, "damage": 65.0, "homing": 0.6, "life": 2.5, "cooldown": 3.0, "charges": 2, "recharge": 20.0, "push": 8.0,
	},
	# Spectre: ghost missile that flies through walls.
	"ghost_missile": {
		"label": "Ghost Missile", "kind": "ghost", "color": Color(0.5, 0.9, 1.0), "special": true,
		"speed": 50.0, "damage": 24.0, "homing": 3.0, "life": 4.0, "cooldown": 0.6, "charges": 3, "recharge": 18.0, "push": 3.5,
		"through_walls": true,
	},
}

## Weapons that can appear in pickups and breakable stands (repeats = more common).
## Turbo pickups have their own, more numerous spots (the most common item on every map).
const PICKUP_WEAPONS := ["homing", "homing", "homing", "fire", "fire", "fire", "power", "power",
	"napalm", "napalm", "remote", "remote", "zoomy", "zoomy", "sat"]

## Owner, session 3: a health pickup restores a share of max health, so armor matters all match.
const HEALTH_PICKUP_RATIO := 0.30
const MEGA_HEALTH_RATIO := 0.60 # confirmed by the owner (session 4)
const HEALTH_RESPAWN := 30.0
const MEGA_RESPAWN := 50.0
const WEAPON_RESPAWN := 14.0
const TURBO_RESPAWN := 10.0

const BURN_DPS := 3.0


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func damage(id: String, key := "damage") -> float:
	return float(get_def(id).get(key, 0.0)) * DAMAGE_SCALE
