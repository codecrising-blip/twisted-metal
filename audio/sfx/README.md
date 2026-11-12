# Sound effects

The game plays these by name (`GameFeel.play` / `loop` / `ui`) on the **SFX bus** (`AudioSettings`, a few dB of
headroom; music has its own bus and is never lowered by effects). A missing file is silent. One-shots nudge the
pitch so repeats don't sound fake. Variants `<name>_1`, `<name>_2` ... are picked at random (with `<name>` itself).
All files: mono Ogg Vorbis, peak -1 dB, converted from the owner's TM1 / TM2 / TM4 / TM 2012 uploads.

| File | When it plays |
|---|---|
| `explosion` + `explosion_1..6` | small and medium explosions (TM2 + TM 2012) |
| `explosion_big` + `explosion_big_1..5` | big blasts: wrecks, remote mine, SAT (TM4 "Blast sound" + TM 2012) |
| `launch_fire`, `launch_power`, `launch_napalm` | firing that weapon (TM2) |
| `launch_homing`, `launch_freeze` | homing missile and freeze (TM4 SFX 03 and 33, owner's picks) |
| `launch_zoomy` | Zoomy salvo (TM 2012 zoomy_launch) |
| `launch_napalm_cone` | Sweet Tooth's Napalm Cone (TM1 Sweet Tooth special) |
| `launch_reaper_skull`, `launch_ghost_missile` | Mr. Grimm's and Spectre's specials (TM2) |
| `charge_up` | Napalm Cone charging: five rising beeps (then `taser_loop` hums until you let go) |
| `missile_flyby` | a missile passing close to the camera (TM 2012) |
| `special_outlaw`, `taser_loop`, `taser_fizzle` | Outlaw's taser: link (TM2), crackle while held and fizzle at the end (TM 2012 field surge) |
| `guns_loop`, `guns_stop`, `shell_1..2`, `ricochet_1..3` | machine guns: loop while firing, barrels spinning down, casings, ricochets off the world |
| `engine_<set>_idle/slow/fast/rev` | engine layers crossfaded by speed, rev on the gas from low speed. Sets (TM 2012): `ic_truck` Sweet Tooth, `taxi` Outlaw, `tow` Junkyard Dog, `moto` Mr. Grimm, `suv` Spectre, `tank` for super heavies later (`Roster` "engine") |
| `skid_loop`, `screech` | tyres sliding (TM2), a hard slide starting (TM1) |
| `crash_1..4` | wall slams and rams (TM2) |
| `death_male`, `death_female` | a driver dies (`"female": true` in `Roster`) |
| `ignite`, `fire_loop` | a car catches fire; fire pools and the pit of fire |
| `mine_drop` | the Remote mine is planted (TM4 SFX 37, owner's pick) |
| `sat_launch`, `sat_scan_loop`, `sat_incoming`, `sat_strike` | SAT: launch at the shooter, scan hum while locked, warning 1.4 s before, the beam (+ big blast layers) (TM 2012) |
| `shield_activate`, `shield_loop`, `shield_impact`, `shield_off` | energy shield (TM 2012) |
| `pickup_weapon`, `pickup_health`, `pickup_turbo` | pickups (TM2 / TM1 health regeneration) |
| `weapon_switch` | changing weapons (TM 2012) |
| `teleport`, `menu_select`, `not_available` | teleport pad, pause menu, nothing to fire (TM2) |
| `special_*`, `energy_shield`, `lightning`, `splash`, `pedestrian_scream` | kept for cars and moves not built yet |

Not here on purpose: `audio/later/` (TM 2012 sounds for features not built yet: shield, Sweet Bot, Primeval,
Warhawk, Minion, Calypso, other stages; Godot skips it) and `audio/reference/sfx_candidates/` (alternatives to sounds
in use: TM 2012 freeze ray, missiles, ghost missile, scythe; TM2 class engines; TM1 missile launch).
Exact duplicate uploads are deleted. Damaged in the owner's Downloads.rar (could not be extracted, ask again):
taxi_rev, power_wire_sparks, helicopter_rotors, cable_spark, traffic_horn2/5/6/7, warhawk_ram2, warhawk_rotors1/2,
bridge_move, crusher1/2, generator3, general_engine3/8, machinery_jam, rain_indoor, wave, wood_door_open.
Dropped: preacher_bomber_* (a TM 2012 enemy we don't have). Missing from the set: ic_truck_fast (slow, pitched up).
