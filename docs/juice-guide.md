# Juice guide (round 8): how every interaction should look and sound

Built for the owner's request: "each interaction can have a few steps to enhance its appearance (missile launch,
glass shattered, mine or SAT exploded or locked, freeze attack...)". Apply it to every new effect too.

## Sources and an honest limit
The owner sent nine Instagram reels (session 7, round 8):
1. Egor (@vasilev.yegor): *Lightning VFX in 7 steps*.
2. Egor: *How to make a spell juicy*.
3. Egor: *The Disney secret to juicy, satisfying animation* (the animation principles).
4. Krit Gupta (@motionbykrit): *How do games make mining feel satisfying* (before / after).
5. Krit: *A campfire that is a flat orange cone, five steps to a fire you'd sit next to*.
6. Krit: *The health bar is lying to you: how games make every hit feel satisfying*.
7. Krit: *11 ways to make a boss kill feel good*.
8. Krit: *5 ways to make a boss entry feel epic*.
9. Krit: *A dash that slides like ice, 5 steps to make it feel fast*.

**The videos themselves could not be watched from the build machine**: Instagram is blocked by the cloud
environment's network and the video-analysis service needs a paid plan. Only each reel's title and description
were read. The rules below are the well-known game-feel techniques those titles name, written for this game.
When the owner can upload the video files, check each rule against the frames and fix this guide.

## 1. Every interaction has five beats
| Beat | Time | What happens |
|---|---|---|
| **Tell** (anticipation) | 0.1-0.6 s before | It announces itself: a charge glow, a wind-up, a lock tone, a rising sound. The player reads it and reacts. |
| **Release** | frame 0 | A short, bright pop bigger than the object (muzzle flash 1-3 frames), the shooter recoils, smoke puff, a punchy attack sound. |
| **Travel** | while it moves | A trail with its own colour that tapers and fades, a travel loop sound, a flyby when it passes the camera. |
| **Impact** | one frame | EVERYTHING lands on the same frame: flash, sound peak, hit-stop, shake, burst, knockback (section 3). |
| **Aftermath** | 0.3-10 s after | Things settle instead of vanishing: debris rests then fades, smoke and embers linger, scorch / cracks stay, the sound tail rings out, the UI catches up. |

Missing beats are what makes an effect feel cheap. Check all five for every weapon, prop and move.

## 2. Never one flat element: layer it (campfire, lightning, spell)
- **Core + glow + edge:** a hot bright core, a wider soft glow around it, a colour ramp from hot to cool
  (white, yellow, orange, red, smoke grey for fire; white, cyan, blue for ice and electricity).
- **Primary, secondary, tertiary particles:** the main burst (fireball, shards), fast small bits with gravity
  (sparks, embers, glints), slow big soft stuff that lingers (smoke, dust, mist).
- **Variation:** no two the same. Size, rotation, speed, timing and pitch each vary ±20-30%. Flicker with noise,
  never a clean sine.
- **Light:** every bright event lights its surroundings. HIGH: a short real light. LOW: an additive flash sprite
  (no dynamic lights on the HD 5500).
- **Lightning:** a jagged path with branches, regenerated 2-3 times in ~0.15 s (it flickers), a white core and a
  wide faint glow, a flash of the whole scene, sparks and a scorch where it lands.

## 3. The impact frame (health bar, mining, boss kill)
- **Flash:** the thing that was hit goes white for 1-2 frames.
- **Hit-stop:** the game freezes 40-120 ms, longer for bigger hits. Only when the player is involved.
- **Shake:** camera shake scaled by power and distance, plus a short kick away from the hit.
- **Squash:** the hit body dips a few percent and springs back (elastic, never goofy: our serious look).
- **Knockback:** the hit thing moves; light things move more.
- **Escalation:** repeated hits build up (cracks grow, pitch rises a little), and the final break is much bigger
  than any hit before it.
- **The health bar lies on purpose:** the damage shows at once as a pale chunk, then drains after a short hold;
  the bar shakes a little on big hits; nearly dead it pulses (built in round 7: `HudTarget`).
- **Big finish (kills):** slow motion, a white-out, a shockwave ring, debris rain, a sound drop to near
  silence then the boom.

## 4. Motion (the animation principles)
Squash and stretch (keep the volume), anticipation before every action, follow-through (antennas, signs, loose
parts keep moving, then settle), ease in and out (nothing starts or stops instantly), arcs (things fly in curves),
secondary action, timing (fast attack, slow release), exaggeration (here only 3-5%: serious look).

## 5. Speed (dash, turbo, jump)
Wind-up squash at the start, then stretch; dust kicked up at the start; speed streaks; a small FOV kick; the
camera lags behind then catches up; afterimages for the fastest moves; landing = a dust ring, a thump and a body
dip.

## 6. Sound rules
- **Three layers:** a sharp attack (the click, crack or snap), a body (the boom, crunch or whoosh), a tail
  (debris, ring-out, echo).
- **Sync:** the loudest moment of every layer lands on the visual impact frame. Build-up sounds (an incoming
  whistle, a charge) are started early so their peak meets the impact, and are cut there. Files with a slow
  lead-in are started past it (`GameFeel.play_synced`, table `audio/sfx/peaks.json`).
- **Variety:** pick among variants and nudge the pitch ±8% every time; repeated hits may climb in pitch.
- **Clarity:** at most about three big sounds at once for one event; far events quieter (the 3D falloff).
  Effects never duck the music (owner, round 5).

## 7. Budget (LOW, Intel HD 5500)
At most ~40 particles per event, no dynamic lights (flash sprites instead), a handful of draw calls per effect,
everything frees itself, materials shared and prewarmed (`GameFeel.prewarm`).

## 8. Checklist per interaction in this game
| Interaction | Tell | Release | Travel | Impact | Aftermath |
|---|---|---|---|---|---|
| Missile launch | charge glow (cone) | flash, recoil kick, smoke puff, launch sound | trail per weapon, flyby | see impact | trail lingers |
| Missile impact | - | - | - | flash, sound peak, shake, sparks, debris, scorch | smoke, scorch stays |
| Glass wall | - | - | - | crack + white glint, shards thrown along the car's path, glitter, dust, glass crash | shards lie on the ground then fade |
| Wood stand / palm / letter | - | - | - | splinters or metal bits, creak / snap / clang | topples, thud on landing, dust |
| Remote mine | drop click, blinking lamp, arm beep | - | - | flash, shockwave, debris, big push | smoke, scorch |
| SAT | lock tone, ring ticks that speed up with the ring | launch whoosh | incoming whistle whose peak meets the beam | white column, flash, shockwave, debris, hit-stop | smoke column, embers, scorch |
| Freeze | charge (blue glow) | icy burst, launch sound | frost trail | ice crystals burst, freeze crackle, the car glazes over | ice shell; on break: ice shards + crash |
| Ram | - | - | - | sparks, metal bits, flash, layered crash, hit-stop, shake | the loser slides away |
| Landing | - | - | - | thump, dust ring, body dip | - |
