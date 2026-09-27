# Headless tests (NOT for Roblox Studio)

**Don't copy anything from this folder into Studio.** It isn't part of the
game: it's a small pretend Roblox that lets the game's own scripts run on a
computer with no Roblox at all, so bugs get caught before you paste anything.

- `rbxmock.luau` - the pretend Roblox: Vector3, CFrame, Color3, Enum, parts,
  models, folders, events, services, a virtual clock (`task.wait`,
  `task.spawn`, `task.delay`) and a flat sand floor for raycasts.
- `build_sources.py` - bundles the real game scripts into `sources.luau`
  (the Luau command line can't read files), plus the dummy builder cut out
  of LobbyBuilder. Every script is also bundled by its path in the project.
- `mount.luau` - puts those scripts into the pretend Roblox where Rojo puts
  them (ModuleScripts in their folders, each with its own `script`), so a
  script that requires another by its place in the game works: the bosses'
  files in `ServerScriptService/Bosses` and `ReplicatedStorage/BossBodies`.
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
- `test_bosses.luau` + `golden.sh` - GOLDEN TRACES of the Spire's bosses.
  `test_bosses.luau -a <scenario> <seed> [server|client]` fights Oozark or
  Nahrzul with pretend players, the real BossService and (client mode) the
  real BossClient, and prints every boss attribute, hit, shove and reward
  (server) or a fingerprint of everything drawn on screen five times a
  second (client). `./golden.sh record` saves the scenarios in `golden/`
  (gzipped: 16 for Oozark and Nahrzul, 4 for Knight Burrowmore -
  `knight_full` and `knight_attacks`, server and client - 4 for Kaze,
  `kaze_full` and `kaze_attacks`, and 4 for Revvington, `car_full` and
  `car_attacks`); `./golden.sh check`
  replays them and fails on any difference - the proof that a change to the
  boss code (like splitting it into one file per boss) changed nothing
  players can see. `./golden.sh check client_` runs only the client ones, and
  `./golden.sh record server_knight` re-records only those.
- `test_boss_template.luau` - the "how to add a boss" templates really
  work: `Bosses/_Template.lua` and `BossBodies/_Template.lua` plugged in as
  a pretend extra boss (on a made-up floor 99), fought to the death with the
  real BossService and BossClient.
- `test_burrowmore.luau` - KNIGHT BURROWMORE (floor 3) on the real Glimmer
  Dig (DigBuilder) with the real BossService (and, with `client` at the end,
  the real BossClient drawing him). `-a full` fights him to the death (both
  phases, the meteor, the reward), `attacks` forces every move on a player
  standing still (each must land) and on one rolling (each must be dodged),
  `reset` leaves mid-fight and comes back, `duo` is two players, and `timing`
  checks the dodge windows (a roll as a drop's circle locks dodges it; a roll
  a second early doesn't; the delayed drop punishes a roll at the lock). It
  also checks he never leaves the dirt, never takes a punch high in the air,
  and (client) that every part of him and every warning gets drawn.
- `burrowmore_snaps.luau` + `render_snaps.py` - Burrowmore's preview
  pictures: `luau burrowmore_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/burrowmore_preview.png` (the
  fight: seven moments and a title card); `-a poses` and
  `render_snaps.py ... --cols 3 --title ""` the pose sheet
  (`Docs/burrowmore_poses.png`). `render_snaps.py` draws any snapshot file
  (SNAP / part lines / BAR for the boss bar; a file can bring its own
  CAPTION lines and a SKY colour).
- `test_kaze.luau` - KAZE (floor 4) on the real Rooftop Dojo (DojoBuilder)
  with the real BossService and his own brain (and, with `client` at the end,
  the real BossClient drawing him, his ki meter and his screens). Its pretend
  players also swing at thin air now and then (his ki feeds on it). `-a full`
  fights him to the death (both rounds, a Super in each, tired spells,
  cancels, the reward), `attacks` forces every move in both rounds on a
  player standing still (each must land) and on one rolling (each must be
  dodged), `reset` leaves after a pillar has crumbled and comes back (meter
  empty, cancels back, every pillar whole), `duo` is two players, `timing`
  checks the dodge windows (the jab's wedge, the dragon's ring, the tornado
  arriving, the ball of ki), `rules` checks the ki rules (a miss near him
  feeds his meter and one far away doesn't; two punches break his focus or
  a charge; out of cancels he's tired, then they refill; a full meter means a
  Super) and `super` checks the beam (a player behind a pillar is safe, one in
  the open is hit, the pillar crumbles, round 2 mends it). It also checks he
  never leaves his ground or stands inside a pillar, and is never hit high in
  a Rising Dragon.
- `kaze_snaps.luau` + `render_snaps.py` - Kaze's preview pictures (a sunset
  sky): `luau kaze_snaps.luau > s.txt` then `python3 render_snaps.py s.txt
  ../../Docs/kaze_preview.png --title "KAZE|FLOOR 4  -  THE ROOFTOP DOJO|RECOMMENDED LV 60"`
  (the fight, eight moments); `-a poses` with `--cols 3 --title ""` the pose
  sheet (`Docs/kaze_poses.png`).
- `test_revvington.luau` - SPEEDY REVVINGTON (floor 5) on the real Piston
  Speedway (SpeedwayBuilder) with the real BossService and his own brain
  (and, with `client` at the end, the real BossClient drawing him). `-a full`
  fights him to the death (TURBO, the reward), `attacks` forces every move
  in both rounds on a player standing still (each must land) and on one
  rolling (each must be dodged), `reset` leaves mid-fight and comes back,
  `duo` is two players, `timing` checks the dodge windows (a roll as the
  charge arrives dodges it, a roll well before doesn't; the same for the
  wheelie, the honk and the backfire) and `crash` checks the tyre wall (a
  charge whose lane meets the wall crashes - dizzy - and one in the open
  doesn't). It also checks every drive joins up with the last (no jumps),
  he's never faster than he should be and never leaves the track, and
  (client) that every part of him, every warning and every one of his
  screen words (GO!, HONK!!, CRASH!, FINISH!...) gets drawn.
- `revvington_snaps.luau` + `render_snaps.py` - Revvington's preview
  pictures (a desert sky): `luau revvington_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/revvington_preview.png --title "SPEEDY REVVINGTON|FLOOR 5  -  PISTON SPEEDWAY|RECOMMENDED LV 75"`
  (the fight: nine moments and a title card); `-a poses` with
  `--cols 3 --title ""` the pose sheet (`Docs/revvington_poses.png`).
- `test_intro.luau` - THE INTRO end to end: a brand-new player joins, the
  real PlayerService, CombatService and IntroService run Oozlet's fight and
  the real IntroClient draws it, on a little lobby (the plaza, the fountain,
  the island, a tree, a shop with a sign, the Spire). It checks the dark
  (what stays lit, what hides, the black box, the mist, the screens and
  Roblox buttons hidden, other players hidden, the camera held in), the
  words building up letter by letter, Oozlet hopping and bumping you, the
  first punch waking it (through CombatService's own remote), the lesson
  slam following you until you roll, the crack, the pop, the rewards, that
  you never drop below 30% health, and the reveal putting everything back.
  `-a full detail` prints every change of words and move; `-a skip` is a
  returning player (no intro); `-a fail` is a screen that breaks mid-intro
  (everything back, no reward).
- `intro_snaps.luau` + `render_intro.py` - the intro's preview picture
  (`Docs/intro_preview.png`): the real lobby and the real intro, four
  moments (the dark, the lesson, the reveal, the Spire) drawn with what's
  on the screen: `luau intro_snaps.luau > snaps.txt`, then
  `python3 render_intro.py snaps.txt out.png`. (Its pretend camera has a
  screen size now, so RetroWorld's whole look - cobbles, the Spire's beacon -
  is in the pictures too.)
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

Run them all with `./run_all.sh` (it ends with `./golden.sh check`) (needs the Luau tools from
https://github.com/luau-lang/luau/releases; the pictures also need Python
with numpy and pillow).
