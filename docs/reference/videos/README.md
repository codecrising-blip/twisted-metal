# Reference videos (owner, round 16)

Study material from the Twisted Metal series, sent by the owner. Not game files. To study one, pull frames:
`ffmpeg -i <file> -vf "fps=4,scale=480:-2,tile=4x3" -frames:v 1 sheet.jpg` (Claude can't play video or hear audio).
All clips named by the owner's answers (round 16).

| File | What it shows | Use |
|---|---|---|
| `shield_tmb_pick.mp4` | TMB, Crazy 8. The lightning is his special (not wanted). The **shield** is the pale blue field over the car with thin lines flowing from tail to nose (around 6 s) | Built in round 16 (`shield_field.gdshader`); the owner found it bad in round 17 and picked the Head-On shield instead |
| `shield_headon_pick.mp4` | Head-On, round 17: **the shield the owner wants now** (about 11.5-14 s): the car's body turns solid glossy green, details faintly through, wheels and some parts keep their colours, fades out at the end. The icy shell that bursts into purple crystals (16-18 s) is the freeze, not the shield | Round 17: a green coat built from it was rejected ("not green paint"); the shield is a living forest-green magnetic field over the whole car, wheels included (`shield_field.gdshader`) |
| `death_tmb_driver_burning.mp4` | TMB, round 17: a car is destroyed (flash, sparks, fireball), the wreck burns under a tall black smoke column and the driver gets out on fire and runs; Roadkill's driver (about 4-11 s) and later Sweet Tooth's (about 26-28 s) | Driver deaths: the idea, made our own (owner); death screams now `audio/sfx/death_male.ogg` / `death_female.ogg` |
| `death_tmb_brimstone_kills_roadkill.mp4`, `death_tmb_crazy8.mp4` | TMB, round 17: a car destroyed, the wreck turns into a car-sized pyre that shrinks over about 4 s under black smoke; the driver gets out burning | **The owner's standard fire for the whole game** (round 17): streaky red-orange licks stuck to a black silhouette, trailing behind (`tmb_fire.gdshader`, `TmbFireGroup`) |
| `death_tmb_ram_driver.mp4` | TMB: Roadkill kills Brimstone, then runs his burning driver down | Burning driver's run (hunched, flailing, beating at the flames) and being run down |
| `fire_tmb_spectre_burning.mp4` | TMB: Spectre burning while it drives: red streaks streaming back off the car | Burning cars (`Vehicle._burn_fx`) |
| `evolution_invisibility_pick_tm2.mp4` | Invisibility in TM1, TM2, TM3, TM4, Black, Small Brawl, Head-On | **TM2 picked, built in round 16** (`CloakFx`): blue sparks, pixel break-up, gone for everyone |
| `evolution_freeze.mp4` | The freeze attack through the series | Later freeze look |
| `special_darkside_ram_tslide.mp4`, `special_darkside_ram_2.mp4` | Darkside's ram charge; "T-SLIDE BONUS" | Darkside: ramming while sliding sideways = extra damage, very hard |
| `special_brimstone_sinner.mp4` | Brimstone throws a sinner ahead | Brimstone: the sinner lands, then runs (or crawls on walls) at the target |
| `special_sweet_bot_missiles.mp4` | Sweet Tooth's robot form firing a long barrage ("MISSILE HIT 20") | Sweet Bot's attack in the same style, smaller than TMB's |
| `special_roadkill_charged_missiles.mp4` | Roadkill: "MAX MISSILE CHARGE", then "ALL MISSILES HIT" | Roadkill's charged missiles (see design 21 for where it goes) |
| `special_junkyard_dog_spike_ball.mp4` | Junkyard Dog's spike ball, a ring on the ground, the blast | Chain Bomb: the blast now sets cars burning and leaves a fire pool |
| `story_tmb_sweet_tooth.mp4`, `story_tmb_mr_grimm.mp4` | TMB story openings (Blackfield Asylum, 3D, dark) | How story openings are told |
| `story_tmb_shadow_raven.mp4` | TMB: Raven, Shadow's driver | The owner's pick for Shadow's driver (not Mortimer) |
| `story_tmb_junkyard_dog_billy_ray.mp4` | TMB: Billy Ray; the biplane is the man who destroyed his life, he wants revenge | Junkyard Dog's story |
| `story_tmb_brimstone_jedediah.mp4` | TMB: Jedediah, Brimstone's driver | Brimstone's story |
| `story_tm2_outlaw.mp4`, `story_tm2_minion.mp4` | TM2: Calypso grants wishes; the world as his battleground | Calypso's manner, wish scenes |
| `story_headon_sweet_tooth_ending.mp4` | Head-On: Sweet Tooth's ending; the white-haired man is Calypso | Our Calypso has his young TM2 look, not this old one |
| `story_headon_needles_marcus_and_crimson_fury_ending.mp4` | Head-On: Needles Kane sees Marcus Kane in the mirror; then Crimson Fury's ending, Agent Shepherd Smith surrounds the area and arrests Calypso | The Kane twist; Crimson Fury's story |
| `story_headon_axel.mp4` | Head-On: Axel; the old man in goggles is the doctor who forced Axel onto the machine to win Twisted Metal for him | Axel's story |
| `story_headon_minion.mp4` | Head-On: Minion, the demon of hell whose powers Calypso stole | Minion's story |
| `story_headon_mr_grimm.mp4`, `story_headon_roadkill.mp4` | Head-On comic-panel wish stories | Our Mr. Grimm is the Head-On reaper, not TMB's soldier |
| `tmb_intro_and_menu.mp4`, `tmb_menu.mp4` | TMB intro and main menu | Menu mood later |
| `WhatsApp Video 2026-11-19 at 7.50.47 AM.mp4`, `WhatsApp Video 2026-11-19 at 7.59.06 AM.mp4` | TM2 and Head-On car select screens, the whole roster (round 21) | The select screens later (driver art, car on a stand) |
