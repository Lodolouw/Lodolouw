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
  his moves, his rage, his minions, his reward and that waves carry on.
  Scenarios: `full`, `leave` (walks out mid-fight), `die` (dies mid-fight),
  `oldbuilder` (no King template), `kite` / `kitejump` (keeps away from
  him; never jumps / always jumps his shockwaves).
- `test_client.luau` - LobbyActivities and BossIntro: the boss bar, banners,
  camera shakes, sounds, music (and the lobby's stepping aside), the VS
  splash and his talking, fed a fake King.
- `test_builder.luau` - every dummy template the real LobbyBuilder code
  builds (the right pieces on the right kind).
- `dump_dummies.luau` + `render.py`, and `render2.py` - the preview pictures
  in `Docs/`: the models, and snapshots of the fight (`test_colosseum.luau
  -a full 7 snap`) drawn inside a simple model of the arena.

Run them all with `./run_all.sh` (needs the Luau tools from
https://github.com/luau-lang/luau/releases; the pictures also need Python
with numpy and pillow).
