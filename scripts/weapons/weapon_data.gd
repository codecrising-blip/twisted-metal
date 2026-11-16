class_name WeaponData
extends RefCounted
## Every weapon in the game. Balance numbers live here only (design: docs/design/01-characters.md
## and the owner's overrides in 05-owner-revisions-1.md).
##   speed    m/s            damage   hit points
##   homing   turn rate rad/s (0 = flies straight)
##   seek     round 12: half-angle (deg) of the seeker. Once the target is further off the nose than
##            this, the lock is lost for good and the missile flies straight on. Within NEAR_RANGE m
##            the turn rate falls (down to NEAR_TURN of it at contact), so a late hard turn dodges.
##   life     seconds before it fizzles
##   cooldown seconds before the same car can fire again
##   ammo     ammo granted by a pickup
##   max_ammo round 12: the most a car can carry of it
##   burn     seconds of Burning on hit
##   kind     bullet | missile | freeze | cone | gas | remote | skull | ghost | sat (look and flight)
##   charges / recharge   specials: charges held and seconds to refill one
##   handler  weapons with their own behaviour (see Specials)
##   icon     HUD icon when it differs from kind
##   trail / trail_len / trail_w   ribbon behind the shot: colour, seconds of history (length), width
##   push     m/s shove on the car it hits (along the shot, scaled by the car's weight class)
##   squish   radians of elastic body dip on the car it hits (squish_classes: which weight classes feel it)
##   wobble   seconds the steering twitches after a hit (homing)
##   flip     the hit throws the car up and rolls it over (power missile; up speed by class: FLIP_UP)
##   shake    camera shake when it hits the player;  flashbang  seconds of white-out on a direct hit
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
		"speed": 46.0, "damage": 12.0, "homing": 3.2, "seek": 45.0, "life": 2.5, "cooldown": 0.45, "ammo": 3, "max_ammo": 10, "push": 2.5,
		"trail": Color(0.6, 0.2, 1.0), "trail_len": 0.3, "trail_w": 0.8,
		"squish": 0.035, "wobble": 0.35, "shake": 0.25,
	},
	"fire": {
		"label": "Fire Missile", "kind": "missile", "color": Color(1.0, 0.42, 0.08),
		"speed": 78.0, "damage": 14.0, "homing": 1.1, "seek": 25.0, "life": 2.5, "cooldown": 0.45, "ammo": 3, "max_ammo": 10, "burn": 4.0, "push": 3.0,
		"trail": Color(1.0, 0.45, 0.05), "trail_len": 0.18, "trail_w": 0.9,
		"squish": 0.06, "squish_classes": ["light", "medium"], "shake": 0.3,
	},
	"power": {
		"label": "Power Missile", "kind": "missile", "color": Color(0.95, 0.12, 0.15),
		"speed": 58.0, "damage": 45.0, "homing": 0.0, "life": 2.5, "cooldown": 1.0, "ammo": 1, "max_ammo": 8, "push": 9.0,
		"trail": Color(0.95, 0.06, 0.05), "trail_len": 0.4, "trail_w": 1.3, "model_scale": 1.6,
		"flip": true, "shake": 0.7,
	},
	# TM: Black's gas can. Thrown up and ahead; press fire again to drop it on the spot.
	# It bursts into a pool of fire: everything inside burns.
	"napalm": {
		"label": "Napalm", "kind": "gas", "handler": "napalm", "color": Color(1.0, 0.55, 0.1),
		"throw": 47.6, "lift": 13.9, # round 12: x1.4 speed, x1.3 reach (flatter arc)
		"drop_speed": 26.0, "life": 4.0, "cooldown": 0.6, "ammo": 1, "max_ammo": 6,
		"damage": 30.0, "radius": 6.0, "burn": 5.0, "pool_radius": 4.5, "pool_time": 6.0,
		"flashbang": 0.3, "shake": 0.5,
	},
	# Remote (owner, play-test 2): a mine dropped behind the car. Press fire again to blow it, or
	# it goes off when any car (yours too) drives onto it. Big push: cars on top fly high and flip,
	# cars at the side get thrown away. Full damage in the middle, less at the edge.
	"remote": {
		"label": "Remote", "kind": "mine", "handler": "mine", "icon": "remote", "color": Color(0.95, 0.2, 0.15),
		"cooldown": 0.6, "ammo": 1, "max_ammo": 6, "arm": 0.8, "trigger": 2.4, "life": 90.0,
		"damage": 50.0, "edge_damage": 20.0, "radius": 8.0, "core": 3.5, "push": 24.0, "blast_size": 4.0,
		# Round 9 (owner): an electronic mine; a clean hit (inside the core) sets the car burning.
		"electronic": true, "burn": 4.0,
		# Height (m) a car right on top is thrown, by weight (owner, session 6): light cars like Grimm
		# and Twister fly highest, super-heavy Darkside the least.
		# Session 6 round 4: x1.5 again on the owner's word ("send them flying more").
		"launch": {"light": 18.0, "medium": 12.6, "heavy": 8.1, "super": 4.5},
	},
	# Ten light missiles with mid tracking (owner): 6 each, 60 if all hit. Driving straight takes
	# them all; a hard drift shakes off about half.
	"zoomy": {
		"label": "Zoomy", "kind": "missile", "handler": "salvo", "icon": "salvo", "color": Color(0.85, 0.9, 0.2),
		"speed": 62.0, "damage": 6.0, "homing": 1.6, "seek": 30.0, "life": 2.5, "cooldown": 1.0, "ammo": 1, "max_ammo": 3, "push": 0.8,
		"salvo": 10, "salvo_gap": 0.06, "small": true, "model_scale": 0.6,
		"trail": Color(0.97, 0.97, 0.95), "trail_len": 0.55, "trail_w": 0.42,
		"squish": 0.025, "squish_classes": ["light", "medium", "heavy"], "shake": 0.1,
	},
	# Satellite strike (owner, play-test 2): the strike zone is locked in front of YOUR car and moves
	# with you for 4 s; steer to keep the enemy inside it, then the beam hits the zone for 112.
	"sat": {
		"label": "SAT", "kind": "sat", "handler": "sat", "color": Color(0.3, 0.95, 0.8),
		"damage": 112.0, "radius": 7.5, "delay": 4.0, "ahead": 24.0, "cooldown": 1.0, "ammo": 1, "max_ammo": 3,
		"flashbang": 1.0, "shake": 1.0,
	},
	# Energy move only (front / rear freeze), never a pickup.
	"freeze": {
		"label": "Freeze", "kind": "freeze", "color": Color(0.55, 0.9, 1.0),
		"speed": 70.0, "damage": 3.0, "homing": 2.2, "seek": 40.0, "life": 2.5, "cooldown": 0.5, "freeze": 2.0,
	},
	# Energy moves (design 5.2): the rear freeze is the same ball thrown backwards, a bit slower.
	"rear_freeze": {
		"label": "Rear Freeze", "kind": "freeze", "color": Color(0.55, 0.9, 1.0),
		"speed": 60.0, "damage": 3.0, "homing": 1.8, "seek": 40.0, "life": 2.5, "cooldown": 0.5, "freeze": 2.0,
	},
	# Rear attack: two missiles out of the back, 12 each, steering 2.0.
	"rear_missile": {
		"label": "Rear Missile", "kind": "missile", "color": Color(1.0, 0.55, 0.2),
		"speed": 50.0, "damage": 12.0, "homing": 2.0, "seek": 40.0, "life": 2.5, "cooldown": 0.3, "push": 2.5,
		"trail": Color(1.0, 0.55, 0.2), "trail_len": 0.25, "trail_w": 0.7, "squish": 0.03, "shake": 0.2,
	},
	# Energy mine: one small mine behind you, arms in 0.6 s, lasts 20 s, 20 and a light toss. Up to 3.
	"energy_mine": {
		"label": "Mine", "kind": "mine", "color": Color(1.0, 0.3, 0.2),
		"arm": 0.6, "trigger": 2.2, "life": 20.0, "damage": 20.0, "edge_damage": 8.0, "radius": 5.0, "core": 2.0,
		"push": 10.0, "blast_size": 2.0, "launch": {"light": 4.0, "medium": 3.0, "heavy": 2.0, "super": 1.2},
	},
	# ---- Specials: one per driver.
	# Sweet Tooth (owner, play-test 1, Head-On style): tap = a homing flaming cone, 45 (a power
	# missile's damage) + burning. Hold fire 2 s and let go = charged cone, 90 + burning, but it
	# flies straight like a power missile (no tracking).
	"napalm_cone": {
		"label": "Napalm Cone", "kind": "cone", "handler": "cone", "color": Color(1.0, 0.5, 0.15), "special": true,
		"speed": 60.0, "damage": 45.0, "homing": 2.4, "seek": 35.0, "life": 3.0, "burn": 4.0, "push": 6.0,
		"squish": 0.06, "shake": 0.45, "trail": Color(1.0, 0.32, 0.05), "trail_len": 0.3, "trail_w": 1.1,
		"charge_time": 2.0, "charged_damage": 90.0, "charged_speed": 64.0,
		# Held this long PAST the full charge it melts down: no shot, locked 3 s (owner: round 10
		# 1 s, round 17 2 s).
		"meltdown_after": 2.0, "meltdown_lock": 3.0,
		"cooldown": 0.8, "recharge": 16.0,
	},
	# Outlaw (Jamie Roberts): Crazy 8-style taser. Fired by the player; grows with link time and
	# fire-button mashing; breaks when the target gets too far away.
	"omni_taser": {
		"label": "Omni Taser", "kind": "beam", "color": Color(0.55, 0.75, 1.0), "special": true, "handler": "taser",
		"range": 25.0, "break_range": 32.0, "dps": 8.0, "dps_per_mash": 1.5, "max_dps": 20.0, "duration": 3.0,
		"cooldown": 1.0, "recharge": 19.0,
	},
	# Junkyard Dog (Billy Ray Stillwell): spiked bomb on the crane chain. Straight throw, press fire
	# again to detonate; at the end of the chain it drops and blows after 3 s.
	"chain_bomb": {
		"label": "Chain Bomb", "kind": "bomb", "color": Color(1.0, 0.25, 0.1), "special": true, "handler": "chain_bomb",
		"speed": 45.0, "chain": 25.0, "radius": 7.0, "damage": 30.0, "edge_damage": 15.0, "stuck_bonus": 10.0,
		"fuse": 3.0, "cooldown": 1.0,
		"burn": 4.0, "pool_radius": 5.0, "pool_time": 5.0, # round 16: the blast burns and leaves a fire pool "recharge": 15.0,
	},
	# Mr. Grimm: TM2 flaming skull. Owner (session 4): 65, the hardest single special hit but no
	# instant kills (a medium car, 280, takes five).
	"reaper_skull": {
		"label": "Reaper Skull", "kind": "skull", "color": Color(1.0, 0.55, 0.15), "special": true,
		"speed": 85.0, "damage": 65.0, "homing": 0.6, "life": 2.5, "cooldown": 3.0, "recharge": 20.0, "push": 8.0,
		"squish": 0.08, "shake": 0.6,
	},
	# Spectre: ghost missile that flies through walls.
	"ghost_missile": {
		"label": "Ghost Missile", "kind": "ghost", "color": Color(0.5, 0.9, 1.0), "special": true,
		"speed": 50.0, "damage": 24.0, "homing": 3.0, "seek": 55.0, "life": 4.0, "cooldown": 0.6, "recharge": 18.0, "push": 3.5,
		"squish": 0.05, "shake": 0.3,
		"through_walls": true,
	},
}

## Weapons that can appear in pickups and breakable stands (repeats = more common).
## Turbo pickups have their own, more numerous spots (the most common item on every map).
const PICKUP_WEAPONS := ["homing", "homing", "homing", "fire", "fire", "fire", "power", "power",
	"napalm", "napalm", "remote", "remote", "zoomy", "zoomy", "sat"]

## Owner, session 3: a health pickup restores a share of max health, so armor matters all match.
## Round 14 (owner): specials recharge slower the fewer a car can hold (they pile up to 3/4/5):
## x2 for the 3-slot cars (easy to land), x1.75 for 4 slots, x1.5 for 5 (hard to land), of the
## original "recharge" times. Roster.special_recharge(id) applies it.
const SPECIAL_RECHARGE_BY_SLOTS := {3: 2.0, 4: 1.75, 5: 1.5}

const HEALTH_PICKUP_RATIO := 0.30
const MEGA_HEALTH_RATIO := 0.60 # confirmed by the owner (session 4)
const HEALTH_ENERGY_S := 5.0 # round 11: seconds of energy regen a health pickup gives
const MEGA_HEALTH_ENERGY_S := 8.0 # (full health gives all of it)
const HEALTH_RESPAWN := 30.0
const MEGA_RESPAWN := 50.0
const WEAPON_RESPAWN := 14.0
const TURBO_RESPAWN := 10.0

const BURN_DPS := 3.0

## Round 12 (owner): homing gets weaker as it closes in (see "seek" above).
const NEAR_RANGE := 15.0
const NEAR_TURN := 0.4

## Power missile flip: up speed (m/s) and how far it rolls (1 = once round) by weight class.
const FLIP_UP := {"light": 9.0, "medium": 8.0, "heavy": 6.5, "super": 4.0}
const FLIP_ROLL := {"light": 1.0, "medium": 1.0, "heavy": 1.0, "super": 0.2}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func damage(id: String, key := "damage") -> float:
	return float(get_def(id).get(key, 0.0)) * DAMAGE_SCALE
