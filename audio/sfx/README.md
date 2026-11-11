# Sound effects

The game plays these by name (`GameFeel.play` / `loop` / `ui`); a missing file is simply silent. Every one-shot
nudges the pitch a little so repeats don't sound fake. All files are mono Ogg Vorbis, peak-normalised to -1 dB
(converted from the owner's TM2/TM4 uploads in session 6). Variants `<name>_1`, `<name>_2` ... are picked at random.

| File | When it plays |
|---|---|
| `explosion` | small and medium explosions (missiles, napalm can) |
| `explosion_big` | big blasts (car wrecks, remote mine, SAT) |
| `launch_fire`, `launch_homing`, `launch_power`, `launch_napalm`, `launch_freeze` | firing that weapon (zoomy borrows `launch_fire`, higher and quieter; Napalm Cone borrows `launch_napalm`, lower) |
| `launch_reaper_skull`, `launch_ghost_missile` | Mr. Grimm's and Spectre's specials |
| `special_outlaw` | Outlaw's taser links |
| `special_axel`, `special_mr_slam`, `special_roadkill`, `special_shadow`, `special_thumper`, `special_twister`, `special_warthog`, `special_spectre_b` | kept for those cars' specials (not built yet) |
| `guns_loop` | machine guns, loops while firing |
| `engine_light`, `engine_medium`, `engine_heavy`, `engine_super` | engine loop by weight class; pitch follows speed and turbo |
| `skid_loop` | tires while sliding sideways or drifting on the handbrake |
| `crash_1` ... `crash_4` | wall slams and car rams (one at random) |
| `death_male`, `death_female` | a driver dies (`"female": true` in `Roster`) |
| `ignite` | a car catches fire |
| `fire_loop` | fire pools and the pit of fire |
| `mine_drop` | the Remote mine is dropped |
| `pickup_weapon`, `pickup_health` | taking a pickup (turbo borrows `pickup_health`, higher) |
| `teleport` | the teleport pad, both ends |
| `menu_select` | pause menu open/close, driver pick |
| `not_available` | fire pressed with no weapon, taser with no target |
| `energy_shield`, `lightning`, `splash` | kept for the shield energy move, Minion's lightning, water stages |
| `unsorted/tm4_sfx_*` | owner's TM4 clips not yet identified: not played until the owner says what each one is |
