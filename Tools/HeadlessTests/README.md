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
  `test_bosses.luau -a <scenario> <seed> [server|client]` fights Oozark,
  Tuber (and the others) with pretend players, the real BossService and (client mode) the
  real BossClient, and prints every boss attribute, hit, shove and reward
  (server) or a fingerprint of everything drawn on screen five times a
  second (client). `./golden.sh record` saves the scenarios in `golden/`
  (gzipped: 16 for Oozark and Tuber - `tuber_full`, `tuber_reset` and
  `tuber_attacks`, which replaced the old worm's - 4 for Knight Burrowmore -
  `knight_full` and `knight_attacks`, server and client - 4 for Kaze,
  `kaze_full` and `kaze_attacks`, 4 for Revvington, `car_full` and
  `car_attacks`, 4 for Gridlock, `grid_full` and `grid_attacks`, and 4
  for Kongo, `kongo_full` and `kongo_attacks`: 36 in all);
  `./golden.sh check`
  replays them and fails on any difference - the proof that a change to the
  boss code (like splitting it into one file per boss) changed nothing
  players can see. `./golden.sh check client_` runs only the client ones, and
  `./golden.sh record server_knight` re-records only those.
- `test_arenas_apart.luau` - EVERY ARENA IN ITS OWN SPOT: builds the lobby
  (with Oozark's hollow and the Colosseum) and every Spire arena together
  and fails if any two overlap, seen from above (`-a list` prints the ground
  each one covers). A new floor's builder goes in its list. (Kongo's jungle
  was first built right on top of the Colosseum: each arena's own test only
  builds that one arena, so nothing noticed.)
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
- `test_tuber.luau` - TUBER / THE BRUTE (floor 2) on the real Sunken Dunes
  (DunesBuilder) with the real BossService and his own brain (and, with
  `client` at the end, the real BossClient drawing him). Its pretend players
  circle little Tuber, chase the Brute down and punch whatever's nearest in
  reach (him through his shape - a split-up buddy, his toppled body, the
  golem's trunk - or a wall's weak spot, a turret, a buddy). `-a full` fights
  him to the death (both bars, the reward), `attacks` forces every move in its
  round on a player standing still (each must land) and on one rolling (each
  must be dodged), `reset` leaves in round 2 and comes back (little Tuber
  again, everything he planted gone), `duo` is two players, `timing` checks
  the dodge windows, `powerup` checks the power-up (nothing hurts anyone, he
  can't be hurt, round 1's mess is cleared, the Brute is golem-sized, round 2
  opens with a hop; it hits him while he's split up, and in client mode checks
  the buddies hop back together), `split` checks SPLIT! (the buddies share his health,
  their balls land, they stack back up), `props` checks his walls (burst up,
  prick, two punches), turrets (shoot, two punches), buddies (pop), quicksand
  (nibbles) and the stun (breaking the last of them), and `corner` checks
  catching him with his hop recharging (free hits, then he escapes). In client
  mode it checks every part of him, every warning, the flying cacti, the
  camera shots (and the long look at the animals), the audience and his screen
  words (THE, THE CACTUS KING, THE DESERT BOWS, SPLIT!, ACHOO!...) get drawn.
  Every scenario also fails if he ever jumps across the arena (faster than 120
  studs a second) - except when his buddies hop back together.
- `tuber_snaps.luau` + `render_snaps.py` - Tuber's preview pictures (a hot
  afternoon sky): `luau tuber_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/tuber_preview.png --cols 3 --title "TUBER|FLOOR 2  -  THE SUNKEN DUNES|RECOMMENDED LV 30"`
  (the fight: fourteen moments and a title card - the power-up's are taken
  from the game's own cutscene camera, the camel through its long lens); `-a
  poses` with `--cols 3 --title ""` the pose sheet (`Docs/tuber_poses.png`:
  him move by move, then a camel, a meerkat, a vulture and a lizard close up).
  (`render_snaps.py` reads a picture's own field of view from an 8th number on
  its SNAP line, if there is one.)
- `test_gridlock.luau` - GRIDLOCK (floor 6) on the real Final Beat
  (GridBuilder) with the real BossService, his own brain and the shared
  sums in ReplicatedStorage/BeatGrid (and, with `client` at the end, the
  real BossClient drawing him, the level's tiles and his screens). Its
  pretend players circle him, roll and jump now and then, and the jump pads
  really throw them up (a pretend CombatService.Launch). `-a full` fights him
  to the death (both rounds, every form, the drop, the gravity flip, the
  reward), `attacks` forces every move (each in its own form) in both rounds
  on a player standing still (each must land) and on one rolling (each must
  be dodged), `reset` leaves mid-fight and comes back (a cube again, the
  right way up), `duo` is two players, `timing` checks the dodge windows (a
  roll as a slam or a spike lands dodges it, one far too early doesn't),
  `drop` checks THE DROP (a player on a jump pad is safe, one on a plain
  tile is hit, one rolling on the beat is safe, one hiding on the runway is
  hit) and `pads` checks a pad throws you up (and not again straight away).
  It also checks every hit from the level lands on the beat, his moves join
  up (no jumps), he never leaves the grid, and (client) that every part of
  him, every warning and every one of his screen words (ATTEMPT 1, DROP!,
  GRAVITY FLIP!, LEVEL COMPLETE!...) gets drawn.
- `gridlock_snaps.luau` + `render_snaps.py` - Gridlock's preview pictures (a
  purple void): `luau gridlock_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/gridlock_preview.png --cols 3 --title "GRIDLOCK, THE FINAL BEAT|FLOOR 6  -  THE FINAL BEAT|RECOMMENDED LV 90"`
  (the fight: eleven moments and a title card); `-a poses` with
  `--cols 3 --title ""` the pose sheet (`Docs/gridlock_poses.png`).
- `test_kongo.luau` - KONGO (floor 7) in the real Jungle Village
  (JungleBuilder) with the real BossService and his own moves (and, with
  `client` at the end, the real BossClient drawing him, his warnings, the
  monkey villagers and the torches). Its pretend players circle him, roll
  and jump now and then, and punch him when he's in reach. `-a full` fights
  him to the death (both rounds, the reward), `attacks` forces every move in
  both rounds on a player standing where it reaches (each must land) and on
  one rolling (each must be dodged), `reset` leaves mid-fight and comes back,
  `duo` is two players, `timing` checks the dodge windows (a roll just before
  a hit dodges it, one far too early doesn't) and `tired` checks a Giant
  Punch that misses leaves him wide open (punches land) and one that hits
  doesn't. It also checks he never leaves the clearing, round 2 comes at half
  health, floor 7 still has no loot (it's waiting for the loot rework), and
  (client) that every part of him, every warning and every one of his screen
  words (GIANT PUNCH!, SPINNING KONG!, YOINK!, GOING BANANAS!, DIZZY! HIT
  HIM!...) gets drawn, and that the villagers and the torches move.
- `kongo_snaps.luau` + `render_snaps.py` - Kongo's preview pictures (the
  jungle village): `luau kongo_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/kongo_preview.png --cols 3 --title "KONGO|FLOOR 7  -  KONGO'S JUNGLE VILLAGE|RECOMMENDED LV 105"`
  (the fight: eleven moments and a title card); `-a poses` with
  `--cols 3 --title ""` the pose sheet (`Docs/kongo_poses.png`).
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
