# Game Design Document (living)

## Vision
A new vehicular-combat game in the Twisted Metal tradition that takes the best of four games:

- **Stages and characters** of *Twisted Metal 2* and *Head-On*: a world tour of big, readable arenas
  with secrets, and the classic cast.
- **Music** in the spirit of *Twisted Metal 4*, with tracks chosen by the owner.
- **Story telling, direction and gameplay** of *Twisted Metal: Black*: a grim, adult tone, a personal
  story for every driver, heavy weapons and energy moves.
- **Look (owner, session 3):** bright, readable TM2-style lighting (the Black darkness idea is dropped).
  Stages are big like the main series. Full design bible: `docs/design/` (revisions in `05-owner-revisions-1.md`).

## Core loop
Pick a driver, then enter an arena, all against all (4 enemies in stage 1, up to 9 in Rome). Collect weapons,
use your special and energy moves, and be the last car running. In story mode, each won arena moves the
driver's story forward, up to a sub boss every third stage and Calypso at the end.
**Lives:** 3 for the whole tournament. A wreck costs one; you respawn after 6 s in the same fight.
Saving only after a sub boss.

## Controls (prototype)
| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Gas / brake-reverse | W / S | RT / LT |
| Steer | A / D | Left stick |
| Handbrake (power slide) | Space | B |
| Turbo | Shift | Y |
| Machine guns | J, Ctrl, left mouse | A |
| Fire selected weapon | K, Alt, right mouse | X |
| Change weapon | Q / E | LB / RB |
| Jump (energy) | C | D-pad up |
| Freeze (energy) | F | D-pad down |
| Look back | B | R3 |
| Pause / restart / help | Esc / Enter / F1 | Start / Start / Back |

## Weapons (balance lives in `scripts/weapons/weapon_data.gd`)
| Weapon | Role |
|---|---|
| Machine guns | Unlimited, 0.55 a bullet (6.9 a second), slight aim assist |
| Homing missile | 12, strong tracking, 3 per pickup |
| Fire missile | 14 + Burning (3/s for 4 s), mild tracking, 3 per pickup |
| Power missile | 45, flies straight, 1 per pickup |
| Health pickup | 30% of max health (Mega health in the LA cage: 60%, proposed) |
| Freeze (energy 50) | Frozen 2 s; a single hit of 15+ shatters the ice; 3 s of Grit after |
| Jump (energy 25) | Hop over obstacles and shots |
| Specials | One per driver, charges recharge over time |

Specials built: **Sweet Tooth: Napalm Cone** (lobbed where the target will be, fire pool),
**Outlaw: Omni Taser** (Crazy 8-style: fired by hand, mash to strengthen, breaks at range),
**Junkyard Dog: Chain Bomb** (straight throw on the chain, press again to detonate, hooks cars),
**Mr. Grimm: Reaper Skull** (TM2 flaming skull, 94: three kill a medium car),
**Spectre: Ghost Missile** (through walls). Health = 200 + 16 x Armor (216-360).

## Drivers (roster of 18, see CLAUDE.md)
Built so far: Sweet Tooth (player), Outlaw, Junkyard Dog, Mr. Grimm, Spectre (low-poly placeholders; the
detailed rebuild from the reference images is still to do). Bosses: Manslaughter, Primeval, Warhawk, Minion,
Calypso.

## Stages (planned)
| Stage | Inspiration | Status |
|---|---|---|
| Los Angeles: Quake Zone Rumble | TM2 | **Test stage built**: ring road, twin glass tunnels with roof + teleporter, caged super health on an overpass deck, fire pit crater, burnt building, 3 road humps, hot dog stands, power tower, HOLLYWOOD sign easter egg |
| Junkyard | Black | Prototype, now free play |
| Paris, Chernobyl, Egypt, Tokyo, London, Antarctica, Hong Kong, New York, Athens, Rome, Amazonia, the blimp | TM2 / Head-On / new | Designed in `docs/design/02-stages.md`, not built |

Every stage needs: wide lanes, at least one vertical route (ramp/roof), a jump, health on risky high ground,
weapons in the open, breakable props that hide weapons, and walls that deflect cars instead of stopping them.

## Story structure (Black tone)
- **Calypso** runs the tournament and grants the winner one wish, always with a cruel twist.
- Each driver gets a short prologue (why they enter), mid-story beats between arenas, and an ending.
- Delivery: still images or short in-engine scenes, grainy and desaturated, with voice-over or text.

## Milestones
1. ~~Playable prototype: Sweet Tooth in the Junkyard vs 2 AI~~ **done**
2. ~~Owner's play-test fixes: balance, wall slide, lives, TM2 Los Angeles test stage, 4 enemies~~ **done**
3. Detailed car models from the reference images; sound effects and music hookup
4. Character select and more drivers
5. Second stage (Paris)
6. Story mode skeleton (Calypso, one full driver story), sub-boss arrivals
7. Vertical slice: polished, shareable build
