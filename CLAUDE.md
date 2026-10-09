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
| Visual style | **Black-style darkness** for cars and stages: night, fire light, fog, film grain |
| Art technique | All models and levels are built **procedurally in GDScript** from primitives (low-poly PS2-era look). No imported art yet. |

## Run, test, look
Godot 4.3 binary is not in the repo. In a fresh cloud session:
```bash
mkdir -p /tmp/godot && cd /tmp/godot
curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && unzip -q g.zip
G=/tmp/godot/Godot_v4.3-stable_linux.x86_64
cd <repo> && $G --headless --path . --import            # parse all scripts
$G --headless --path . -s tests/smoke_test.gd           # gameplay tests, must print ALL TESTS PASSED
# Screenshots (shots: gameplay | hero | enemies | overview):
xvfb-run -a -s "-screen 0 1600x900x24" $G --rendering-method gl_compatibility --path . -s tests/screenshot.gd -- hero docs/screenshots/hero.png
```
- Always run the smoke test before committing. Look at screenshots after visual changes.
- The headless run prints `Parameter "m" is null` from the dummy renderer — harmless noise.
- **Renderer: GL Compatibility (OpenGL).** Forward+ (Vulkan) made Godot and the game crash / hang on a
  black screen on the owner's PC, so the project uses Compatibility. Screenshots here match what the
  owner sees. Forward+-only extras (volumetric fog, SSAO, SSR) switch on only if run with Forward+.
- Screenshots render slowly, so physics runs many steps per frame: in `gameplay` shots the cars have
  driven further than in real time.

## Owner play-test feedback (session 1) — to do next
1. **Too easy:** health is too low and damage too high, so fights end too fast. Raise health, lower damage.
2. **Getting stuck:** too many obstacles; hitting a wall stops the car and only reversing helps.
   Wanted: Twisted Metal-style wall hits that deflect/slide the car left or right so it keeps moving.
3. **Stage:** replace the cluttered Junkyard as the first stage with an arena like Twisted Metal 1's first
   stage as the owner describes it: a **circular ring**, **breakable crates that hide weapons**, a
   **ramp/jump in the middle** to reach health or a superior weapon, and **no annoying obstacles**.
4. **Car models:** Sweet Tooth's model is too crude. Rebuild cars with much more detail, using the
   owner's reference images in `docs/reference/` (see that folder's README).

## Story mode plan (owner's decisions, session 2)
**Playable cast — vehicle version / driver version:**
| Character | Vehicle from | Driver from |
|---|---|---|
| Sweet Tooth — Needles Kane | TM 2012 truck (`TM2012SweetToothRender`) | Head-On (`Screen_shot_2012-02-05...`) |
| Roadkill — Marcus Kane | TM1 | Head-On |
| Outlaw — Jamie Roberts | TM2 Outlaw 2 (`TM2Outlaw2Render`) | TM2 |
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

## Code map
```
scenes/main.tscn            single scene; everything is spawned from scripts/main.gd
scripts/main.gd             match flow (spawn, win/lose, restart), lighting/environment, music loader
scripts/core/               InputSetup (all key/pad bindings), ChaseCamera, MeshKit (primitive + material helpers)
scripts/vehicles/           Vehicle (driving/combat/damage), Roster (stats), VehicleModels (car builders),
                            PlayerController, AIDriver
scripts/weapons/            WeaponData (all balance numbers), Projectile, Pickup
scripts/arena/junkyard.gd   the Junkyard stage + spawn/pickup points
scripts/fx/                 FxKit (fire/smoke/explosions), FlickerLight, Blinker
scripts/ui/hud.gd           HUD + full-screen grain/vignette shader
tests/                      smoke_test.gd (headless), screenshot.gd
audio/music/                drop .ogg/.mp3 here; first file alphabetically plays in a loop
docs/GDD.md                 game design document (living)
```

## Conventions
- Units are meters. Cars face **-Z**, Y up, wheels touch y = 0.
- Physics layers: 1 world, 2 vehicles, 3 projectiles (unused for bodies), 4 pickups.
- Controllers fill `Vehicle.in_*` fields; one-shot actions use `want_*` flags. No controller = car coasts.
- New car: stats in `Roster.CARS`, builder in `VehicleModels.build()`, special weapon in `WeaponData.DEFS`.
- New stage: a script like `JunkyardArena` that exposes `build()`, `spawn_points`, `weapon_points`, `health_points`.
- Models store metadata on the model node: `wheels`, `steer`, `wheel_radius`, `guns`, `launcher`, `top`.
- Keep balance numbers in `WeaponData` / `Roster`, not scattered in logic.

## Status
**Milestone 1 — playable prototype (done):** Sweet Tooth vs Outlaw + Junkyard Dog (AI) in the Junkyard.
Driving with handbrake slides and turbo, machine guns, homing/fire/power missiles, Laughing Ghost special,
energy jump + freeze, health and weapon pickups, ramming, wrecks, win/lose/restart, pause, HUD, grain filter.

**Next candidates (agree with owner first):**
1. Owner play-test pass: driving feel, camera, difficulty, darkness level.
2. Sound effects (engine, guns, explosions) — none yet. Music needs owner's tracks in `audio/music/`.
3. More Black-style energy moves (shield, mines, napalm) and per-character second specials.
4. Character select + more cars (Axel, Mr. Grimm, Thumper, Spectre, ...).
5. Story mode skeleton: Calypso intro, per-character prologue/ending in Black's tone.
6. Next stage (owner's pick from the list above).

## Session log
- **Session 1:** Created the project from an empty repo on `main`. Built milestone 1, the headless test
  suite and the screenshot tool. Fixed: idle cars kept their last input (an AI car kept driving after its
  brain was removed), particles rendered as squares (switched to a hand-built soft texture), scene too dark
  to read, HUD clipped on the right, Sweet Tooth's head blocking the chase camera (camera height per car).
  Owner's PC: game hung on a black screen and the editor crashed on open with Forward+; switched the
  project to the Compatibility renderer.
