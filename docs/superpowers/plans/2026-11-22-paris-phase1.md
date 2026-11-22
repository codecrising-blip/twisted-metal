# Paris Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A drivable Paris stage (layout v2) with the Haussmann buildings in their final look and colours, selectable from the front end, so the owner can judge the city's taste early.

**Architecture:** `ParisArena` (GDScript, same duck-typed interface as `LosAngelesArena`) builds the ground, the Seine trench, bridges, plazas and collision from one height function, and places Blender-made Haussmann kit modules along block footprints with one MultiMesh per module (few draw calls). Landmarks are tasteful placeholder massing in phase 1; their Blender models come in phases 2-3.

**Tech Stack:** Godot 4.3 (GL Compatibility), GDScript, Blender 5.3 via `bpy` (`tools/blender/tmlib.py`), skills blender-environment-kits / blender-asset-qa / blender-game-optimization.

## Global Constraints
- Map 550 x 450 m: x -275..275 (east +), z -225..225 (south +), y up. Roads 18 m, Champs-Elysees 24 m, alleys 11-12 m.
- Seine water 30 m wide, lower quays 8 m at y -5, walled (no falling in). Roof decks of the drivable Haussmann quarter at y 13 (deck), ramps up to them.
- Palette (spec 32 section 5): stone #D8C9AC / shade #A3967F, zinc #6F7C86 seams #A7B0B5, slate #50575D, iron #1E2420, chimney pots #B0643E, shop fronts #6E1F1F #1F4A35 #1E2A44 black with gold #C9A24A, asphalt #3A3B3E, cobbles #6B6458, sidewalks #B9AE98, gravel #CDBA8E, lawn #6F8F48, trees #6E8B3D, gold #C9A54A, Seine #4E6B6A, tower #6B4E3A. Sun 4 pm (~35 deg elevation, from the south-west), light #FFF1DC.
- Performance: draw calls never above LA's worst view (~400); static pieces batched; repeated modules as MultiMesh; nothing hidden under the ground, inside walls or past the boundary; small props fade at 80-170 m.
- Never break LA: `tests/smoke_test.gd` (LA) must still print ALL TESTS PASSED.
- Commits end with the session's attribution lines; push to `main`.

## File Structure
- Create `scripts/arena/paris.gd` (`class_name ParisArena`): layout constants, height function, ground + collision, roads/plazas paint, Seine trench, bridges, level_of, ramps, spawn / weapon / health points, radar lines, spot(), environment (sky, sun).
- Create `scripts/arena/paris_blocks.gd` (`class_name ParisBlocks`): footprint polygons -> Haussmann modules (MultiMesh per module), roof decks + collision, roof ramps, rooftop crossings.
- Create `scripts/arena/paris_landmarks.gd` (`class_name ParisLandmarks`): phase-1 massing for the tower, Arc, Grand Palais, Concorde, Louvre + pyramid, Notre-Dame, Opera, Invalides, Montmartre + Sacre-Coeur, Moulin Rouge, Chaillot.
- Create `tools/blender/build_haussmann.py`: the kit -> `assets/models/haussmann.glb` + `haussmann_albedo/_normal/_orm.webp`.
- Modify `scripts/main.gd:74` (arena choice), `scripts/ui/front_end.gd` (Paris pin open, stage handed to main).
- Create `tests/paris_check.gd` (headless: Paris builds, cars spawn on the ground, every ramp top is reachable, no spawn inside a building).
- Modify `tests/screenshot.gd` only if it needs a `-- paris` switch (shots go through `main.tscn`).

### Task 1: Stage choice (main + front end)
**Files:** Modify `scripts/main.gd` (static `stage := "los_angeles"`, `-- paris` on the command line, `ParisArena.new()`), `scripts/ui/front_end.gd` (`STAGES` Paris `"open": true`, `_show_loading` sets `main_script.stage`).
**Interfaces:** Produces `main.stage: String` ("los_angeles" | "paris").
- [ ] Add the static and the switch; LA stays the default.
- [ ] Run LA smoke test: ALL TESTS PASSED.
- [ ] Commit.

### Task 2: ParisArena ground, Seine, bridges, plazas
**Files:** Create `scripts/arena/paris.gd`; Test `tests/paris_check.gd`.
**Interfaces:** Consumes the arena interface listed by the code survey (spawn_points, respawn_points, weapon_points, weapon_kinds, health_points, mega_points, ramps, center, wander_half, music, next_line, title, subtitle, easter_egg, build(), radar_lines(), spot(), level_of(), ground()). Produces `ParisArena.height(x, z) -> float`, `ParisArena.river_z(x) -> float`, `ParisArena.ROOF_Y := 13.0`.
- [ ] Write `tests/paris_check.gd`: builds ParisArena, asserts ground under every spawn point is within 0.5 m of `height()`, asserts the bridge decks are solid (ray down at each bridge centre hits y ~0), prints PASS/FAIL lines and `PARIS CHECK OK`.
- [ ] Run it: fails (class missing).
- [ ] Implement ground (quadtree trimesh like LA's `_ground_faces`), zone paint (asphalt, cobbles, sidewalks, lawn, gravel), Seine trench (water plane, lower quays, stone walls, ramps down at the ends), 4 bridges with parapets, Etoile ring + avenues, Champs-Elysees, Concorde, Tuileries, Invalides esplanade, Trocadero terraces with ramps, Montmartre hill with a switchback road, 4 pm sky and sun.
- [ ] Run paris_check: `PARIS CHECK OK`. Run LA smoke test: ALL TESTS PASSED.
- [ ] Commit.

### Task 3: Haussmann kit in Blender
**Files:** Create `tools/blender/build_haussmann.py`; output `assets/models/haussmann.glb` + atlas webp.
**Interfaces:** Produces glb nodes, all 3.0 m wide bays (pivot bottom-centre on the facade plane, facade facing +Y in Blender = -Z in Godot... checked with a preview): `shop_red`, `shop_green`, `shop_navy`, `shop_black`, `door`, `upper` (floors 2-3, continuous balcony on floor 2), `corner` (pan coupe, 45 deg), `mansard` (zinc slope + dormer), `chimney`, `party_wall` (blank side wall bay). Heights: ground 4.2 m, entresol band 0.4, floors 3.1 m, cornice at 10.8 m, mansard to 13.0 m.
- [ ] `--shape` preview of one corner of a block (all modules) for the owner.
- [ ] Bake + export; run blender-asset-qa checks (normals, floating parts, z-fighting).
- [ ] `godot --headless --import`; commit.

### Task 4: Blocks from footprints
**Files:** Create `scripts/arena/paris_blocks.gd`; modify `scripts/arena/paris.gd` (call it).
**Interfaces:** Consumes `ModelLib.mesh("haussmann", node, "haussmann")`. Produces `ParisBlocks.build(arena: Node3D, blocks: Array) -> void` where each block is `{poly: PackedVector2Array, roof: bool (drivable deck), seed: int}`; adds ramps to `arena.ramps`.
- [ ] Extend paris_check: a ray down onto each drivable roof hits y 13 +- 0.2; no spawn / weapon point inside a block polygon.
- [ ] Implement: walk each edge, fit whole bays (stretch the last bay up to 15%), corners at angles > 30 deg get `corner`; ground floor alternates shops/doors by seed; one MultiMeshInstance3D per module type for the whole city; flat roof deck + collider on drivable blocks; roof ramps and rooftop crossings (steel decks) from the layout.
- [ ] paris_check OK, LA smoke OK; commit.

### Task 5: Landmark massing (phase 1)
**Files:** Create `scripts/arena/paris_landmarks.gd`.
**Interfaces:** Produces `ParisLandmarks.build(arena: Node3D) -> void` (collision on everything solid; the Arc and the Grand Palais open for driving through).
- [ ] Massing in the palette with proper proportions; the tower as four legs + taper in bronze brown at 140 m.
- [ ] Screenshots: overview, Seine at the bridges, a Haussmann street, rooftops, Concorde, Montmartre.
- [ ] Commit.

### Task 6: Playability, perf, docs
**Files:** Modify `scripts/arena/paris.gd` (spawn / weapon / health points, ramps for the AI), `tests/_perf.gd` (Paris spots), `CLAUDE.md`, `docs/design/32-paris-design.md`.
- [ ] Spawn 5 enemies + player; AI drives (ramps list), smoke-level sanity in paris_check (cars still on the map after 20 s).
- [ ] Draw calls at 6 spots <= LA worst; record numbers.
- [ ] Docs + commit + push; send the owner the screenshots.
