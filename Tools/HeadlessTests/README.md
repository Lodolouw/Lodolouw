# Headless tests (NOT for Roblox Studio)

**Don't copy anything from this folder into Studio.** It isn't part of the
game: it's a small pretend Roblox that lets the game's own scripts run on a
computer with no Roblox at all, so bugs get caught before you paste anything.

- `rbxmock.luau` - the pretend Roblox: Vector3, CFrame, Color3, Enum, parts,
  models, folders, events, services, a virtual clock (`task.wait`,
  `task.spawn`, `task.delay`) and a flat sand floor for raycasts.
- `build_sources.py` - bundles the real game scripts into `sources.luau`
  (the Luau command line can't read files), plus the dummy builder cut out
  of LobbyBuilder.
- `test_colosseum.luau` - ColosseumService: a pretend player goes in, beats
  waves 1-4 and fights the Giant Straw King on wave 5. It checks for errors,
  NaN (broken numbers), dummies leaving the arena or sinking into the sand,
  his moves, his rage, his minions, his reward, the quest (Beat 5 Waves,
  paid when the run is cleared) and RUN AGAIN.
  Scenarios: `full`, `leave` (walks out mid-fight), `die` (dies mid-fight),
  `oldbuilder` (no King template), `kite` / `kitejump` (keeps away from
  him; never jumps / always jumps his shockwaves), `cursed`, `clearleave`,
  `hard` / `nightmare` (a whole run on that difficulty: health, dummies per
  wave, pay, the angry King, what the clear unlocks), `restart` (a new pick
  on wave 1 starts the run over; on wave 2 it waits) and `locked` (picks
  that aren't allowed).
- `test_client.luau` - LobbyActivities and BossIntro: the boss bar, banners,
  camera shakes, sounds, music (and the lobby's stepping aside), the VS
  splash and his talking, the quest tab, the wave box's difficulty, the
  coins and XP flying into you, the DIFFICULTY menu and plaques and the
  CLEARED screen, fed a fake King and fake server messages.
- `test_builder.luau` - every dummy template the real LobbyBuilder code
  builds (the right pieces on the right kind), and the DIFFICULTY board: a
  plaque per difficulty, its prompt, clear of the stands and of the way in,
  facing where you arrive (`-a dump` prints its parts for the picture).
- `dump_dummies.luau` + `render.py`, and `render2.py` - the preview pictures
  in `Docs/`: the models, and snapshots of the fight (`test_colosseum.luau
  -a full 7 snap`) drawn inside a simple model of the arena.
- `render_board.py` - the DIFFICULTY board beside the exit gate, from
  `test_builder.luau -a dump`, with the words on its plaques.

Run them all with `./run_all.sh` (needs the Luau tools from
https://github.com/luau-lang/luau/releases; the pictures also need Python
with numpy and pillow).
