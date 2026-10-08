# Game Design Document (living)

## Vision
A new vehicular-combat game in the Twisted Metal tradition that takes the best of four games:

- **Stages and characters** of *Twisted Metal 2* and *Head-On*: a world tour of big, readable arenas
  with secrets, and the classic cast.
- **Music** in the spirit of *Twisted Metal 4*, with tracks chosen by the owner.
- **Story telling, direction and gameplay** of *Twisted Metal: Black*: a grim, adult tone, a personal
  story for every driver, heavy weapons and energy moves.
- **Look:** Black's darkness everywhere: night, fog, fire as the main light, desaturated colour, film grain.

## Core loop
Pick a driver, then enter an arena of 3–6 cars, all against all. Collect weapons, use your special and
energy moves, and be the last car running. In story mode, each won arena moves the driver's story forward,
up to a boss and an ending.

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
| Machine guns | Unlimited, light damage, slight aim assist |
| Homing missile | Low damage, strong tracking |
| Fire missile | Fast, medium damage, mild tracking |
| Power missile | Big damage, flies straight |
| Freeze (energy) | Freezes the target for 2.5 s |
| Jump (energy) | Hop over obstacles and shots |
| Specials | One per driver, recharges over time |

Specials so far: **Sweet Tooth: Laughing Ghost** (slow, flaming clown skull, heavy homing hit).
Outlaw: Riot Slug. Junkyard Dog: Tow Hook.

## Drivers (planned roster)
Built so far: Sweet Tooth (player), Outlaw, Junkyard Dog.
Next: Axel, Mr. Grimm, Thumper, Spectre, Shadow, Roadkill, Hammerhead, Mr. Slam, Minion (boss),
Dark Tooth (boss). The owner decides the order and each driver's story.

## Stages (planned)
| Stage | Inspiration | Status |
|---|---|---|
| Junkyard | Black / TM2 | **Prototype done**: crusher with roof ramp, jump mound, crane, bus wreck, car-stack lanes |
| Amazonia 3000 B.C. | TM2 | — |
| The Carnival | — | — |
| Los Angeles | TM2 | — |
| Paris | TM2 | — |
| Others from TM2 / Head-On | — | owner's choice |

Every stage needs: lanes, at least one vertical route (ramp/roof), a jump, health on risky high ground,
weapons in the open, and fire, neon or street lights as the main light sources.

## Story structure (Black tone)
- **Calypso** runs the tournament and grants the winner one wish, always with a cruel twist.
- Each driver gets a short prologue (why they enter), mid-story beats between arenas, and an ending.
- Delivery: still images or short in-engine scenes, grainy and desaturated, with voice-over or text.

## Milestones
1. ~~Playable prototype: Sweet Tooth in the Junkyard vs 2 AI~~ **done**
2. Feel pass from the owner's play-test, plus sound effects and music hookup
3. Character select and 4–6 drivers
4. Second stage
5. Story mode skeleton (Calypso, one full driver story)
6. Vertical slice: polished, shareable build
