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
  `hard` / `nightmare` (a whole run on that difficulty, picked in the
  pop-up at the door: health, dummies per wave, pay, the angry King, what
  the clear unlocks), `nextrun` (a new pick mid-run waits for the next run)
  and `locked` (going in on a locked difficulty or from too far away, and
  picks that aren't allowed). Every scenario goes in through the pop-up's
  ENTER (standing at the door sends nobody in), and `leave` checks LEAVE is
  refused away from the exit gate mid-fight, then works at the gate.
- `test_client.luau` - LobbyActivities and BossIntro: the boss bar, banners,
  camera shakes, sounds, music (and the lobby's stepping aside), the VS
  splash and his talking, the quest tab, the wave box's difficulty, the
  coins and XP flying into you, walking up to the Quest Board and the
  Colosseum's doors (the pop-ups open and close, stay shut after the X or
  STAY until you step out and back, and wait when you pop out of the
  door), the difficulty pop-up (picking, ENTER, refusals), the "Leave?"
  check and the CLEARED screen, fed a fake King and fake server messages.
- `test_builder.luau` - every dummy template the real LobbyBuilder code
  builds (the right pieces on the right kind).
- `dump_dummies.luau` + `render.py`, and `render2.py` - the preview pictures
  in `Docs/`: the models, and snapshots of the fight (`test_colosseum.luau
  -a full 7 snap`) drawn inside a simple model of the arena.
- `lobby_count.luau` - builds the whole lobby with the real LobbyBuilder and
  counts parts, shadow-casting parts, lights and Neon per piece (`-a client`
  also runs RetroWorld and counts its detail; `-a names` lists the island's
  biggest part names and the animated tags).
- `fx_cost.luau` - runs LobbyFX for 10 pretend seconds at the spawn and
  counts parts moved and see-through changes per second (and by name).
- `lobby_dump.luau` - builds the whole lobby (LobbyBuilder, then RetroWorld's
  detail) and prints every part as one line of JSON.
- `check_lobby.py` - reads that dump and lists what looks wrong: things
  floating in the air, objects touching nothing, plants poking into walls,
  bits sticking up on the paths, and faces in the same spot (flicker).
- `render_lobby.py` - draws the lobby from that dump from any camera
  (`--eye=x,y,z --look=x,y,z`, `--mark` circles spots in red).

Run them all with `./run_all.sh` (needs the Luau tools from
https://github.com/luau-lang/luau/releases; the pictures also need Python
with numpy and pillow).
