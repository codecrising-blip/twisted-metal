# Sound effects

The game plays these by name (`GameFeel.play` / `loop` / `ui`); a missing file is simply silent. Every one-shot
nudges the pitch a little so repeats don't sound fake. All files are mono Ogg Vorbis, peak-normalised to -1 dB
(converted from the owner's TM1/TM2/TM4 uploads in session 6). Variants `<name>_1`, `<name>_2` ... are picked at random.

| File | When it plays |
|---|---|
| `explosion` | small and medium explosions (missiles, napalm can) |
| `explosion_big` | big blasts (car wrecks, remote mine, SAT) |
| `launch_fire`, `launch_power`, `launch_napalm` | firing that weapon (TM2) |
| `launch_homing`, `launch_freeze` | homing missile and freeze (TM4 SFX 03 and 33, owner's picks) |
| `launch_zoomy` | Zoomy salvo (TM1 missile launch) |
| `launch_napalm_cone` | Sweet Tooth's Napalm Cone (TM1 Sweet Tooth special) |
| `launch_reaper_skull`, `launch_ghost_missile` | Mr. Grimm's and Spectre's specials |
| `special_outlaw` | Outlaw's taser links |
| `special_crimson_fury`, `special_hammerhead`, `special_axel`, `special_mr_slam`, `special_roadkill`, `special_shadow`, `special_thumper`, `special_twister`, `special_warthog`, `special_spectre_b` | kept for those cars' specials (not built yet) |
| `guns_loop` | machine guns, loops while firing |
| `engine_light`, `engine_medium`, `engine_heavy`, `engine_super` | engine loop by weight class; pitch follows speed and turbo |
| `skid_loop` | tires while sliding sideways or drifting on the handbrake |
| `screech` | a hard slide starts (TM1) |
| `crash_1` ... `crash_4` | wall slams and car rams (one at random) |
| `death_male`, `death_female` | a driver dies (`"female": true` in `Roster`) |
| `ignite` | a car catches fire |
| `fire_loop` | fire pools and the pit of fire |
| `mine_drop` | the Remote mine is planted (TM4 SFX 37, owner's pick) |
| `pickup_weapon`, `pickup_health`, `pickup_turbo` | taking a pickup (health = TM1 health regeneration) |
| `teleport` | the teleport pad, both ends |
| `menu_select` | pause menu open/close, driver pick |
| `not_available` | fire pressed with no weapon, taser with no target |
| `energy_shield`, `lightning`, `splash`, `pedestrian_scream` | kept for the shield, Minion's lightning, water, pedestrians |

Other TM4 clips were dropped (owner: only SFX 03, 33, 37 matter). Exact duplicate uploads are deleted, not kept.
