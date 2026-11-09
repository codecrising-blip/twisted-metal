# Project memory — read this first

Vehicular-combat game in the spirit of Twisted Metal, built in **Godot 4.3**.
The owner designs and play-tests; Claude writes the code, models and levels.

## Working with the owner
- **Always reply in Arabic** (owner's preference). Code, comments and commit messages stay in English.
- Be direct and honest: if an idea is weak say so and explain; rate ideas 1–10 when asked; say when unsure.
- Copyright/licensing: the owner says this is settled on their side. Don't re-raise it.
- The owner picks the music and play-tests; act on their feedback and record decisions below.
- The owner is not a programmer (didn't know what a git branch was). Explain technical steps simply.

## Creative direction (decided)
| Area | Taken from |
|---|---|
| Stages and characters | Twisted Metal 2 and Head-On (Junkyard, Amazonia 3000 B.C., Carnival, Los Angeles, Paris, ...) |
| Music | Twisted Metal 4 style — **owner supplies the tracks** |
| Story telling, tone, gameplay feel | Twisted Metal: Black (dark, grim, character stories) |
| Visual style | **TM2-style bright, readable lighting** (owner, session 3: "forget the Black darkness"). Stages are **big like the main series**, with space and texture. |
| Art technique | All models and levels are built **procedurally in GDScript** from primitives (low-poly PS2-era look). No imported art yet. |

## Run, test, look
Godot 4.3 binary is not in the repo. In a fresh cloud session:
```bash
mkdir -p /tmp/godot && cd /tmp/godot
curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && unzip -q g.zip
G=/tmp/godot/Godot_v4.3-stable_linux.x86_64
cd <repo> && $G --headless --path . --import            # parse all scripts
$G --headless --path . -s tests/smoke_test.gd           # gameplay tests, must print ALL TESTS PASSED
# Screenshots (shots: gameplay | hero | enemies | overview | roof | tunnel | cage | center | pit):
xvfb-run -a -s "-screen 0 1600x900x24" $G --rendering-method gl_compatibility --path . -s tests/screenshot.gd -- hero docs/screenshots/hero.png
```
- Always run the smoke test before committing. Look at screenshots after visual changes.
- The headless run prints `Parameter "m" is null` from the dummy renderer — harmless noise.
- **Renderer: GL Compatibility (OpenGL).** Forward+ (Vulkan) made Godot and the game crash / hang on a
  black screen on the owner's PC, so the project uses Compatibility. Screenshots here match what the
  owner sees. Forward+-only extras (volumetric fog, SSAO, SSR) switch on only if run with Forward+.
- Screenshots render slowly, so physics runs many steps per frame: in `gameplay` shots the cars have
  driven further than in real time.
- The headless smoke test takes about 20 s (it drives, fights and respawns in real time).

## Owner play-test feedback (session 1)
1. ~~Too easy (health too low, damage too high)~~ — done in session 3 (chapter 1 numbers).
2. ~~Getting stuck on walls~~ — done: TM wall rule (deflect/slide, never stop) + stuck helper.
3. ~~Cluttered first stage~~ — replaced by the owner's later choice: TM2 Los Angeles, clean and big.
   (The TM1 ring idea is dropped; breakable props that hide weapons live on in LA.)
4. **Car models:** still to do. Sweet Tooth's model is too crude. Rebuild cars with much more detail, using
   the owner's reference images in `docs/reference/` (see that folder's README).

## Story mode plan (owner's decisions, session 2)
**Playable cast — vehicle version / driver version:**
| Character | Vehicle from | Driver from |
|---|---|---|
| Sweet Tooth — Needles Kane | TM 2012 truck (`TM2012SweetToothRender`) | Head-On (`Screen_shot_2012-02-05...`) |
| Roadkill — Marcus Kane | TM1 | Head-On |
| Outlaw — Jamie Roberts (a woman) | TM2 Outlaw 2 (`TM2Outlaw2Render`) | TM2 (`TM2JamieRobertsPSX`) |
| Axel | TM4 Super Axel | — |
| Mr. Grimm | Black | Black |
| Shadow — Raven | TM2 (exact TM2 design: purple hearse, black roof) | Black (Raven) |
| Mr. Slam — Simon Whittlebone | Head-On | Head-On, but alive (not a ghost) |
| Hammerhead — Mike and Stu | TM2 | TM2 |
| Thumper — Bruce | TM3 | TM2 |
| Brimstone — Jebidiah | Black (reference image) | — |
| Darkside — Mr. Ash | Black (reference image) | — |
| Yellow Jacket — Charlie Kane Jr. | Black (reference image) | — |
| Crimson Fury — Agent Shepherd | TM 2012 (PS3) | Head-On |
| Spectre — Ken | TM2 | TM2 |
| Twister — Amanda Watts | Head-On look (reference image) | TM2 |
| Orbital — Alan Vame (owner's name) | TM4 | TM4 |
| Warthog | TM2 | Colonel Hall, Head-On (confirmed) |
| Junkyard Dog | Black | Billy Ray Stillwell, Black (confirmed) |

**Story facts:** Needles Kane and Marcus Kane believe they are brothers but are the same person (Head-On twist,
revealed in the story; both stay playable). Mr. Slam's story is set before his TM2 wish and fall, so he is alive.
**Junkyard Dog's special (owner's design): Chain Bomb** — a spiked bomb on the crane chain, thrown in a straight line,
manually detonated for area damage (see `docs/design/01b-roster-update.md`).
**Bosses:** Manslaughter (Black), Primeval (TM3), Warhawk (Black), Minion (TM1 design); final boss Calypso:
TM2 look (face: `InfoboxTM2Calypso`; suit from TM2, research it) and TM2-style voice/manner; his vehicle is undecided.
Warhawk must NOT use Black's tanker-shield gimmick; Black's explosive tankers are reserved for the Calypso fight.
**Stage order:** Los Angeles, Paris, Russia–Chernobyl (+Manslaughter), Egypt, Tokyo, London (+Primeval), Antarctica,
Hong Kong, New York (+Warhawk), Athens, Rome, Amazonia (+Minion), final: the blimp vs Calypso.
Sub bosses appear right after the normal fight on that stage, 1-on-1.
The owner deliberately mixes the best of every game (e.g. Manslaughter and Warhawk as sub bosses) — canon roles don't bind us.
**Modeling:** the owner only provides front views; infer side/back to match the front and research references online.
Design chapters (characters, stages, sub bosses, Calypso) live in `docs/design/` once approved.

## Owner decisions (session 3) — full text in `docs/design/05-owner-revisions-1.md` (overrides chapters 1–4)
- **Look:** TM2 lighting, not Black darkness. Big stages. **Test stage = TM2 Los Angeles (Quake Zone)**, also stage 1.
- **Health pickup = 30% of max health** for every car (not a flat +50). Mega health: 60% (confirmed session 4).
- **Lives:** 3 for the whole tournament (spare-life counter 2 → 0). Any loss costs a life; respawn after **6 s** in
  the same fight. Save only after beating a sub boss; loading restores 3 lives — also after Minion, before Calypso
  (owner, session 4: Minion and Calypso are hard enough).
- **Enemies per stage:** 4 in LA rising to 9 in Rome; each sub-boss stage has one fewer than the stage before.
  Proposed: LA 4, Paris 5, Chernobyl 4, Egypt 6, Tokyo 6, London 5, Antarctica 7, Hong Kong 7, New York 6, Athens 8,
  Rome 9, Amazonia 8.
- **No end-of-stage climax events** for now. Easter eggs stay. Contract pages later.
- **Sub-boss arrival:** 3 fast replays of the last kill, 4 s silence, camera to a known spot, the boss breaks in.
  Warhawk: black "loading" screen while the player is moved to his New York zone (the crown), city burns, bridges
  destroyed, blinding searchlight, rights read, 3 s silence, "Time's up", missile.
- **Specials:** Sweet Tooth unchanged from ch1 (Laughing Ghost gets a new look, same job). Outlaw = Crazy 8-style
  taser fired manually, grows with link time and fire-button mashing, breaks when the target drives too far.
  Mr. Grimm = TM2 flaming skull, **65** (session 4; was 94). Shadow = Black's fast wall-climbing ghost, detonate by
  pressing fire again. Mr. Slam bites super-heavy cars (big damage, no throw).
- **Primeval:** pure chase fight in the London arena: turbo-rams constantly, spike projectile (power-missile damage,
  loose homing, wobbles steering), then spike grab 2 s into a wall, heals 15% per spike hit. Never seeks health.
- **Warhawk:** shield broken by destroying 5 cores on 5 bridge-less platforms around the crown, each guarded by
  troops (MG, flashbang, RPG, spike net) and 2 flamethrower machines; each core −20% shield. No tankers.
- **Tokyo:** follow the fan's cable to a high sealed cabinet behind a yellow electric net; only napalm at the peak of
  a jump reaches it. **London:** the train kills (70 per hit) unless you escape to a ledge and turbo back.
  **Antarctica:** no special weapon, no signs at the cracks.
- The `.cht` file the owner sent is GameShark cheat codes, not game data. It confirms TM2 had 9 enemy slots and lives.

## Owner decisions (session 4) — full text in `docs/design/06-owner-revisions-2.md` (wins over 05)
- **Warhawk:** platforms reached by energy jumps (no bridges), a hit at the wrong moment can drop you to your death
  (wanted). Gap must be jumpable by the heaviest/slowest car: **16 m** (Slam ~24 m, Darkside ~27 m at top speed
  without turbo). Spike net = a line on the ground in front of the RPG unit, lasts 12 s, effect **2 s**.
  Each platform: 3 fronts (left, right, front) of 12 MG troops firing together every 2.5 s: one full front = 14,
  all three = 42. Fight may run 6–9 min; the owner picks its music.
- **Primeval:** if he rams a wall and misses, he is stuck 4 s (attack window), then chases again. Invisibility
  (not invincibility) breaks his lock and lets you hit his back.
- **London train:** warning before it comes (red light, horn, on-screen sign, 3 s). **Antarctica:** slippery ice,
  white snow; a cracking area shows pulsing light-blue cracks for 6 s, then the ice block falls.
- **Calypso:** don't raise him for now; the owner is still deciding.
- **Unity/Unreal:** the owner plans to move engines later, on a new laptop (current: i5-5200U, 8 GB, Intel HD 5500,
  no Vulkan on Windows, so Godot must stay on Compatibility). Keep building in Godot until then.

## Owner decisions (session 5) — sub bosses, full text in `docs/design/07-owner-revisions-3.md` (wins over 05/06)
- **Manslaughter:** fight inside a cooling tower; 4 liquid-nitrogen machines (shoot one while he is near: frozen,
  double damage); he reloads by ramming rock piles; after 2 machines are gone, nuclear rain makes the rocks acidic.
  Kill = 4 nitrogen windows + 1 raw-fight share; each wasted machine adds another raw share.
- **Primeval:** freeze lasts only 1 s on him, then he chases at once.
- **Minion:** must be harder than Warhawk. No shield. Patriot missiles with freeze at long range, all-round milling
  saws at close range (~54/s, Grimm dies in 4 s), heals on lava. The fight is holding mid range on the lava.
  Shrine lightning (ch3) explained to the owner; its role in the new design is undecided.
- **TM2 source code:** not public (Sony's, never released); not needed — we write everything in Godot. Useful
  inputs instead: top-down map shots, gameplay video frames, the owner's memories, side/back car images.

## Code map
```
scenes/main.tscn            single scene; everything is spawned from scripts/main.gd
scripts/main.gd             match flow (spawn, lives + 6 s respawn, win/lose, restart, fall-out rescue), music
scripts/core/               InputSetup (all key/pad bindings), ChaseCamera, MeshKit (primitive + material helpers)
scripts/vehicles/           Vehicle (driving, wall rule, rams, states, combat), Roster (stats from SPD/ARM/HND/SPC),
                            VehicleModels (car builders), PlayerController, AIDriver (specials, ramps, max 2 on player)
scripts/weapons/            WeaponData (all balance numbers), Projectile, Pickup, Specials (fires specials),
                            TaserLink, ChainBomb, FirePool
scripts/arena/los_angeles.gd  stage 1 / test stage (TM2 Quake Zone): heightmap ground, roads, tunnels, cage...
scripts/arena/junkyard.gd   the old prototype stage, now free play (`-- junkyard`)
scripts/arena/breakable.gd  props that shatter/topple (stands, glass, palms, letters, tower legs)
scripts/arena/teleporter.gd teleport pad
scripts/fx/                 FxKit (fire/smoke/explosions), FlickerLight, Blinker, ZigLine (bolts, chains, cables)
scripts/ui/hud.gd           HUD (bars, lives, respawn countdown, notices) + light grain/vignette shader
tests/                      smoke_test.gd (headless, ~57 checks), screenshot.gd
audio/music/                drop .ogg/.mp3 here; first file alphabetically plays in a loop
docs/GDD.md                 game design document (living); docs/design/ = design bible (Arabic)
```

## Conventions
- Units are meters. Cars face **-Z**, Y up, wheels touch y = 0.
- Physics layers: 1 world, 2 vehicles, 3 projectiles (unused for bodies), 4 pickups.
- Controllers fill `Vehicle.in_*` fields; one-shot actions use `want_*` flags. No controller = car coasts.
- New car: stats in `Roster.CARS`, builder in `VehicleModels.build()`, special weapon in `WeaponData.DEFS`.
- New stage: a script like `LosAngelesArena` that exposes `build()` (adds its own WorldEnvironment and sun),
  `title`, `subtitle`, `spawn_points` (0 = player), `respawn_points`, `weapon_points`, `health_points`,
  `mega_points`, `ramps` ({foot, top} for the AI), `center`, `wander_half`, and `signal easter_egg(title, text)`.
- Anything a projectile should damage has `projectile_hit(damage, shooter)`; anything a car can smash has
  `vehicle_contact(vehicle, velocity_before) -> bool` (true = the car went through). See `Breakable`.
- Specials with their own behaviour are nodes in the world registered with `Vehicle.set_live_special()`;
  fire presses while one is live go to its `fire_again()` (taser mash, bomb detonation).
- Models store metadata on the model node: `wheels`, `steer`, `wheel_radius`, `guns`, `launcher`, `top`, `lean`.
- Keep balance numbers in `WeaponData` / `Roster`, not scattered in logic.

## Status
**Milestone 1 — playable prototype (done):** Sweet Tooth vs Outlaw + Junkyard Dog (AI) in the Junkyard.

**Milestone 2 — owner's fixes + LA test stage (done, session 3):** TM2 Los Angeles (big, bright, clean) with
4 enemies (Outlaw, Junkyard Dog, Mr. Grimm, Spectre). Chapter 1 balance (health 200 + 16 x ARM, guns 0.55,
homing 12, fire 14 + Burning, power 45, freeze 2 s + ice break + Grit, energy 2.5/s with 1.5 s pause,
weight-based rams), 30% health pickups, wall deflection, 3 lives with 6 s respawn and spawn protection.
Specials: Napalm Cone, Omni Taser (owner's Crazy 8 version), Chain Bomb, Reaper Skull (65), Ghost Missile.
Test aid: pause menu keys 1-5 pick the player's driver (`main.gd` static `player_car`), the rest are AI.
Not built yet from the design: Sweet Bot, the other energy moves (shield, mines, invisibility, rear moves),
sub-boss arrivals, story, character select, detailed car models, sounds.

**Next candidates (agree with owner first):**
1. Owner play-test of the LA stage: driving feel, wall slide, damage/health, AI, the new specials.
2. Detailed car models from `docs/reference/` (Sweet Tooth first), new Laughing Ghost look.
3. Remaining energy moves and Sweet Bot; napalm pickup (needed for the Tokyo puzzle).
4. Sound effects (engine, guns, explosions). Music needs the owner's tracks in `audio/music/`.
5. Story skeleton, sub-boss arrival sequence (replays, silence, break-in), save after sub bosses.
6. Next stage: Paris.

## Session log
- **Session 1:** Created the project from an empty repo on `main`. Built milestone 1, the headless test
  suite and the screenshot tool. Fixed: idle cars kept their last input (an AI car kept driving after its
  brain was removed), particles rendered as squares (switched to a hand-built soft texture), scene too dark
  to read, HUD clipped on the right, Sweet Tooth's head blocking the chase camera (camera height per car).
  Owner's PC: game hung on a black screen and the editor crashed on open with Forward+; switched the
  project to the Compatibility renderer.
- **Session 2:** Design bible chapters 1–3 (characters, stages, sub bosses) written and reviewed in Arabic.
- **Session 3:** Chapter 4 (Calypso) saved. Owner's revisions recorded (`docs/design/05-owner-revisions-1.md`).
  Built milestone 2 (see Status). Bugs met: a big "ground beyond the walls" plane cut through the crater
  (now a frame around the map); decals use `mesh_height()` so they sit on the visible 2 m ground mesh;
  chain bomb flew over car roofs (now thrown 1 m off the ground). Gotcha: GDScript can't infer types from
  untyped `for x in [..]` loop variables (`var y := x * 2` fails) — type the loop variable.
- **Session 4:** Owner answered the open questions (`06-owner-revisions-2.md`). Grimm's skull 94 → 65, mega
  health 60% confirmed.
