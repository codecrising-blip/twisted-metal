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
| Backdrops | What lies **outside** a stage is a pre-rendered **panorama image** on the sky (owner, session 5: "the background should be minimal, even a photo"), never 3D. All modeling effort goes into the playable stage. |

## Run, test, look
Godot 4.3 binary is not in the repo. In a fresh cloud session:
```bash
mkdir -p /tmp/godot && cd /tmp/godot
curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && unzip -q g.zip
G=/tmp/godot/Godot_v4.3-stable_linux.x86_64
cd <repo> && $G --headless --path . --import            # parse all scripts
$G --headless --path . -s tests/smoke_test.gd           # gameplay tests, must print ALL TESTS PASSED
# Screenshots (shots: gameplay | hero | duel | enemies | overview | roof | tunnel | cage | center | pit,
#   or car:<id>:<front34|rear34|side|front|top|low> for one car alone). Add `-- full` for all five cars:
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
- After adding a new `class_name` script, run `--import` once or other scripts can't find the class.
- **Rebake the LA backdrop** after changing `scripts/arena/la_city.gd` (needs xvfb, about a minute):
  `xvfb-run -a -s "-screen 0 1600x900x24" $G --rendering-method gl_compatibility --path . -s tests/bake_backdrop.gd -- /tmp/faces 2048`
  then `python3 tests/cube_to_panorama.py /tmp/faces assets/backdrops/los_angeles_city.jpg 6144`. Keep the `.import`
  next to the jpg on VRAM compression with mipmaps (uncompressed it would cost ~100 MB of video memory).
- **Performance budget (owner's HD 5500 lagged, worst near the power tower):** keep draw calls low. Merge static
  pieces with MeshBuilder (`_solid()` / `_solid_box_mb()` in LA add colliders to one shared body), share one mesh
  between repeated props (palms, stands, lamps), no dynamic lights on pickups/missiles on LOW, decorative lights in
  `GraphicsSettings.EXTRA_LIGHT_GROUP` (HIGH only). Measure with a quick script using
  `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` at a few camera spots.
  After the pass: 1706 -> 597 mesh nodes, 45 -> 16 lights, worst view ~2500 -> ~1070 draw calls. F3 = FPS counter.
- The game starts in the **preview match** (Sweet Tooth vs Outlaw only). `-- full` = all five cars (tests use it).
  `-- high` / `-- low` force a graphics level for one run.

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
- **Calypso (session 5):** the owner's plan replaces ch4: see `docs/design/08-calypso-owner-plan.md` (TM2 face/voice,
  blimp, tankers, 4-5 phases: contract seal reads inputs, timed loss, ghosts of contestants and sub bosses, energy-attack
  and turbo curses, nuke in your car (2 s to shield), time rewind that breaks his ring, then a raw brawl).
  Final structure: 4 phases (ghost floor with hidden respawn panels; engine floor with tankers, 4 engines, turbo curse;
  Calypso cheating; raw fight after the ring breaks). Vehicle: a metal devil beast styled after the TM4 carnival wagon,
  train-like scream when it accelerates. Ring-break line (final): "HAHAHAHAHAHAHAHAHA... DID YOU THINK THE RING MADE
  ME WHO I AM? I AM CALYPSO... AND I'LL TAKE YOUR SOUL WITH MY OWN HANDS." Engine floor: treadmills, burning fuel
  spills, permanent electric floors (jump them; shock like Outlaw's taser). "Soul pull" trick archived.
- **Design summary:** `docs/design/00-master-summary.md` is the one-page overview of everything agreed (Arabic).
- **Unity/Unreal:** the owner plans to move engines later, on a new laptop (current: i5-5200U, 8 GB, Intel HD 5500,
  no Vulkan on Windows, so Godot must stay on Compatibility). Keep building in Godot until then.

## Owner decisions (session 5) — sub bosses, full text in `docs/design/07-owner-revisions-3.md` (wins over 05/06)
- **Manslaughter:** fight inside a cooling tower; 4 liquid-nitrogen machines (shoot one while he is near: frozen,
  double damage); he reloads by ramming rock piles; after 2 machines are gone, nuclear rain makes the rocks acidic.
  Kill = 4 nitrogen windows + 1 raw-fight share; each wasted machine adds another raw share.
- **Primeval:** freeze lasts only 1 s on him, then he chases at once.
- **Minion:** must be harder than Warhawk. No shield. Patriot missiles with freeze at long range, all-round milling
  saws at close range (~54/s, Grimm dies in 4 s), heals on lava. The fight is holding mid range on the lava.
  Lava heal is **1%/s** (final). Lightning drops him ~5 s for a combo worth ~20% of his health. Four wooden bridges
  link the pillars to the top center; 3 Patriots break one (never rebuilt). The top platform (lightning + full health)
  breaks after 6 Patriots: no more lightning. If he hasn't seen you for 20 s, a hellfire siren opens the gates of
  hell and lava floods every stone road for at least 2 minutes while he hunts you anywhere, even on top.
  Once the siren starts there is no stopping it. He shells bridges/top only while you are on them or firing from them.
  Patriot freeze 1.5 s then 2 s freeze immunity; the ice breaks on the 2nd Patriot. After freezing you he rushes in
  with the saws if close, else fires 2-3 more Patriots. Lava heal 2%/s. Hidden counter: the top gate's lightning hits
  the HIGHEST car; get down into the lava with him so it hits him, and rain turns that lava to obsidian.
- **All attacks:** warnings are very short (~0.3 s lock tone; the missile itself is the real warning; homing tuned so
  sharp turns can dodge). **Weapon cooldowns are per weapon** (code): switching and firing another weapon is instant,
  so combos work; only the same weapon waits for its reload.
- **Manslaughter** stays immune to normal freeze; frost circle marks each nitrogen machine's reach.
- **TM2 source code:** not public (Sony's, never released); not needed — we write everything in Godot. Useful
  inputs instead: top-down map shots, gameplay video frames, the owner's memories, side/back car images.

## Owner play-test 1 (session 5, end) — full text in `docs/design/09-owner-playtest-1.md`. APPROVED, NOT BUILT YET
Build these with the owner next session (he asked to keep them for then):
- **AI:** chase but not like a magnet; attack with missiles/specials; when the player turns to face them they keep
  attacking from the same direction (head-on), no sliding back behind; only at low health do they slide away and
  look for health. **No limit on AI special use** (owner rejected that idea).
- **Napalm Cone (Sweet Tooth, rated 1/10 now):** Head-On style. Tap = homing napalm shot, burns on contact,
  30 + burning. Hold to charge (up to 2 s) = 50 + normal burning, **no tracking**, power-missile path.
  Other cars' weapons need the same kind of review later, car by car.
- **Movement:** slower, like TM Black (not lazy); big cars no crazy drifts; weaker turbo. **Turbo never regenerates**:
  full at start and after respawn, each turbo pickup refills it **completely**, turbo pickups are the **most common**
  item on every map.
- **Pickups:** less bright; each shows its weapon's shape and color (fire vs homing must be obvious), health clear.
- **Energy combos** (quick, ~0.5 s, on the D-pad AND the left stick): jump U U L, shield U U R, front freeze L R U,
  secondary weapon R L U, rear freeze L R D, invisibility R L D, mines D D R, rear attack D D L.
- **Pad layout (PS):** Square drive, **double-tap Square and hold the second press = turbo** (stops on release), X handbrake, Circle headlights, Triangle rear view,
  R1/L1 switch weapon, R2 fire weapon, L2 machine guns, R3 camera mode, L3/left stick = D-pad (steer + combos),
  D-pad left/right steer, down reverse, up drive.
- **Camera modes (R3):** near chase, far chase, **in-car view showing the driver's hands** (TM2 had it; our own driver design, later).
- **Headlights:** reveal invisible cars from the start; the key tool against Calypso's clones later.
- **Later (after the above):** serious daytime stage look; real buildings with depth (motel, taco place, hot dog stand
  read as thin as a finger), believable palms (now "chopsticks"); act as a model designer with taste.
- Also noted: the game lags a lot on the owner's laptop (FPS counter + lighter graphics still to do); PS5 pad wanted;
  Shield, Sweet Bot and the other energy moves are not built yet.

## Code map
```
scenes/main.tscn            single scene; everything is spawned from scripts/main.gd
scripts/main.gd             match flow (spawn, lives + 6 s respawn, win/lose, restart, fall-out rescue), music
scripts/core/               InputSetup (all key/pad bindings), ChaseCamera, MeshKit (simple primitives),
                            MeshBuilder (detailed models merged per material: chamfered boxes, lofts, lathes),
                            MatKit (generated paint/rust/chrome/rubber textures), GraphicsSettings (LOW/HIGH)
scripts/vehicles/           Vehicle (driving, wall rule, rams, states, combat), Roster (stats from SPD/ARM/HND/SPC),
                            VehicleModels (dispatch + simple prototype cars), HeroModels (detailed Sweet Tooth
                            and Outlaw), VehicleFx (gatling spin, muzzle flash, turbo flames, mascot spring,
                            tire smoke), PlayerController, AIDriver (specials, ramps, max 2 on player)
scripts/weapons/            WeaponData (all balance numbers), Projectile, Pickup, Specials (fires specials),
                            TaserLink, ChainBomb, FirePool
scripts/arena/los_angeles.gd  stage 1 / test stage (TM2 Quake Zone): heightmap (raised battleground, ramps, crater,
                            road hills), spline road, tunnels, cage, tower, sign; spot() = named places for tests
scripts/arena/la_city.gd    BAKE ONLY: the 3D city rendered into the LA backdrop panorama (not built in the game)
scripts/arena/la_props.gd   LA street furniture: toppling street lights, burnt wrecks, billboards, power lines,
                            traffic lights, barriers, dumpsters, containers, rubble, manholes, stains
scripts/arena/junkyard.gd   the old prototype stage, now free play (`-- junkyard`)
scripts/arena/breakable.gd  props that shatter/topple (stands, glass, palms, letters, tower legs)
scripts/arena/teleporter.gd teleport pad
scripts/fx/                 FxKit (fire/smoke/explosions), FlickerLight, Blinker, ZigLine (bolts, chains, cables)
scripts/ui/hud.gd           HUD layout (target, feed, messages, help, countdown, pause) + grain/vignette shader
scripts/ui/hud_status.gd    bottom-left panel: name, lives, segmented health (trail), turbo, energy, state chips
scripts/ui/hud_weapons.gd   bottom-right panel: selected weapon (drawn icon, ammo), other weapons as chips
scripts/ui/radar.gd         top-right radar: turns with the car; enemies, pickups, walls/road from radar_lines()
tests/                      smoke_test.gd (headless, ~65 checks), screenshot.gd, bake_backdrop.gd + cube_to_panorama.py
assets/backdrops/           stage backdrops (equirectangular panoramas shown as the sky)
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
- Models store metadata on the model node: `wheels`, `steer`, `wheel_radius`, `guns`, `launcher`, `top`, `lean`,
  and optionally `gun_spinners`, `exhaust` + `exhaust_dir`, `bobble` (read by `VehicleFx`).
- Detailed models: build with `MeshBuilder` (one mesh per material = few draw calls on the HD 5500) and
  `MatKit` materials (triplanar, no UVs needed). MeshBuilder decides triangle winding itself; hand-built
  SurfaceTool meshes must be clockwise seen from the visible side, or two-sided materials light them from behind
  (that made LA's roads pitch black until session 5).
- Car models are **our own designs** carrying each character's idea and colors, never copies of the originals.
- **Serious look (owner, session 5):** no toy look. Real proportions, wheels under fender arches, dark worn metal
  (no shiny chrome), heavy dirt/rust, armor, welded mesh over glass, muted colors, no cartoon faces.
- MatKit materials read vertex colors (MeshBuilder writes them). On plain primitives (MeshKit boxes, BoxMesh in
  a MultiMesh) use `MatKit.plain(mat)`, or the missing vertex color can turn the surface black.
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

**Quality preview (session 5, second pass after the owner's review):** Sweet Tooth vs Outlaw, 1-on-1 in LA.
Owner's verdict on pass 1: cars looked goofy/toy-like, LA looked like a school backyard, sand hills made no sense,
blimp too close, HUD weak, radar missing. Pass 2 (current):
- **Sweet Tooth** = armored ice-cream step van: welded wedge plow with spikes, gatlings in the nose, steel mesh
  over the windshield, slit armor on the cab windows, roll-up steel shutter on the serving hatch, napalm mortar
  with fuel cans, blackened stacks, spare wheel, faded "ICE CREAM" lettering. Roof: a scorched, cracked fiberglass
  cone sign that burns from inside (replaces the cartoon "Scoop" face, which read as goofy; no clown, no face).
- **Outlaw** = armored police interceptor: real wheel openings, black steel wheels, louvered steel over the
  windshield, mesh on side windows, bullet strikes, twin hood guns in an armored box, low light bar, caged taser
  coil on the trunk.
- **LA layout (owner, session 5, third pass; this is the current stage):** walls at +-155 (bigger map).
  A raised **battleground** in the middle, `PLAT_H` = 5 m (about three Outlaws stacked), 200 x 184 m rounded square,
  retaining walls with hazard-painted edges; open edges are drops. **Four ramps** up from the road. A **wavy road
  loop** (Catmull-Rom through `ROAD_CTRL`) around it with **three jump hills** (3 m). Twin tunnels on the north
  straight with ramps from the battleground onto their roof (teleporter to the cage). On the battleground: pit of
  fire (crater), burnt building, power tower, the cage deck + overpass, barrier rows and wrecks as cover.
  Outer wall = rusted steel barrier + chain-link fence (collider 8 m). Beyond it: the city as one baked panorama
  on the sky (`assets/backdrops/los_angeles_city.jpg`); HOLLYWOOD on a scaffold past the north wall; blimp far
  away. Owner's verdict on the previous pass: the 3D city was wasted effort and the stage itself was a plain
  square; background must be minimal (an image is enough).
- **HUD**: status panel, weapons panel, radar (see code map).
- Effects: spinning gatlings + muzzle flash, turbo flames, tire smoke. Graphics: LOW (default) / HIGH, G in pause.
Owner also wants, later: main menu, car select, stage select, world map, opponent preview.

**Next candidates (agree with owner first):**
0. **The play-test 1 fixes above** (AI, Napalm Cone, movement/turbo, pickups, combos, pad layout, cameras,
   headlights), plus performance for the owner's laptop. Then the stage look rework.
1. Owner play-test of the LA stage: driving feel, wall slide, damage/health, AI, the new specials.
2. Owner's verdict on the preview cars; then the same detail for the other cars, new Laughing Ghost look.
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
- **Session 5:** Sub-boss and Calypso designs finished (`07`, `08`, master summary). Built the quality preview
  (see Status). Bugs met: SurfaceTool `append_from()` silently drops non-indexed parts once the merged mesh is
  indexed (MeshBuilder now indexes every part); LA road strips were wound the wrong way, so the two-sided asphalt
  was lit from below and looked black; `get_meta(key, null)` prints an error when the key is missing.
  Second pass (owner: "goofy, toy-like, school backyard"): serious rebuild of both cars, LA city + props, new HUD
  and radar. Gotchas: a procedural window grid shimmers far away (fade it with `fwidth`); distant mountains turn
  white in fog (their material uses `disable_fog`); MatKit materials need vertex colors (see Conventions).
  Third pass (owner: "a full 3D city for a background, and the stage left a plain square"): city baked into a
  panorama, LA rebuilt (raised battleground, ramps, wavy road, hills). Gotchas: `const X := SomeClassName` is not
  a constant expression in 4.3 (write the class name out); Godot's panorama reads u = 0 at north (-Z) growing
  east, v = 0 straight up (tests/cube_to_panorama.py follows that); AI wandering now aims at `arena.ground()` and
  climbs ramps in two steps when a ramp starts up on a plateau (`AIDriver._lower_ramp`).
