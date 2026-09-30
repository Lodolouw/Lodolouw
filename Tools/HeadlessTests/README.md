# Headless tests (NOT for Roblox Studio)

**Don't copy anything from this folder into Studio.** It isn't part of the
game: it's a small pretend Roblox that lets the game's own scripts run on a
computer with no Roblox at all, so bugs get caught before you paste anything.

- `rbxmock.luau` - the pretend Roblox: Vector3, CFrame, Color3, Enum, parts,
  models, folders, events, services, a virtual clock (`task.wait`,
  `task.spawn`, `task.delay`), a flat sand floor for raycasts and a camera's
  `WorldToViewportPoint`.
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
  for Kongo, `kongo_full` and `kongo_attacks`, 4 for Petalina,
  `petal_full` and `petal_attacks`, 4 for Scribble, `scrib_full` and
  `scrib_attacks`, and 4 for King Gavelgrunt, `king_full` and
  `king_attacks`: 48 in all);
  `./golden.sh check`
  replays them and fails on any difference - the proof that a change to the
  boss code (like splitting it into one file per boss) changed nothing
  players can see. `./golden.sh check client_` runs only the client ones, and
  `./golden.sh record server_knight` re-records only those.
  `test_bosses.luau -a <scenario> <seed> client aim` checks instead where
  BossClient says the boss is - the middle and head it measures from what's
  drawn (`AimAt`, `HeadAt`, `AimSize`, `AimTime`: your lock-on and its speech
  bubbles use them) - against its own drawn parts every sample while it's
  awake, and prints the lowest and highest head and middle per move (PASS if
  they always matched; `run_all.sh` does every boss's `_attacks`).
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
- `test_petalina.luau` - PETALINA (floor 8) in the real Glasshouse Garden
  (GreenhouseBuilder, GardenPlan) with the real BossService and her own moves
  (and, with `client` at the end, the real BossClient drawing her, her
  flytraps, the brambles and the butterflies). Its pretend players circle her
  (keeping to the paths in round 2), roll, jump and punch her stem - or her
  head when it's down. `-a full`, `attacks`, `reset`, `duo` and `timing` as
  for the others; `droop` checks punches on her drooping head land (and don't
  once it's back up), `traps` that flytraps sprout, bite, pop in one punch
  and wilt, and `thorns` that in round 2 a bed stings and a path doesn't. It
  also checks she never moves, floor 8 has no loot, and (client) that every
  part of her, every warning and her words get drawn, the butterflies fly,
  every bramble grows in round 2 and sinks again after.
- `petalina_snaps.luau` + `render_snaps.py` - Petalina's preview pictures:
  `luau petalina_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/petalina_preview.png --cols 3 --title "PETALINA|FLOOR 8  -  THE GLASSHOUSE GARDEN|RECOMMENDED LV 120"`;
  `-a poses` with `--cols 3 --title ""` the pose sheet (`Docs/petalina_poses.png`).
- `test_scribble.luau` - SCRIBBLE (floor 9) on the real Canvas (CanvasBuilder,
  CanvasPlan) with the real BossService and his own three-round brain (and,
  with `client` at the end, the real BossClient drawing him, his warnings,
  clones, the Z key, the DELETE box and the erased edge). Its pretend players
  circle him, roll, jump, punch him, pop his clones and the Z key, and in
  round 3 run to punch the DELETE box's NO button. `-a full`, `attacks`,
  `reset`, `duo` and `timing` as for the others; `undo` checks the Z key
  (broken: he's stunned and punches land; left alone: CTRL+Z gives back
  exactly your last hits), `delete` the DELETE box (NO crashes him, costs him
  health and brings the paper back; left alone it hits hard but never kills
  and shrinks the paper; erased paper stings), `whip` that jumping clears the
  Boss Bar Whip, and `clones` that the ink clones chase, slash, pop and
  smudge away. It also checks he stays on the paper and floor 9 has no loot.
- `test_gavelgrunt.luau` - KING GAVELGRUNT (floor 10, the final boss) on the
  real Throne Summit (ThroneBuilder, ThronePlan) with the real BossService
  and his own three-round brain (and, with `client` at the end, the real
  BossClient drawing him - the walrus king - his warnings, guards, coins,
  feast, crown, spotlight, crumbling pillars and the storm's lightning).
  `-a full`, `attacks`, `reset`, `duo` and `timing` as for the others; `toe`
  checks the glowing flipper tip (punched: he hops and punches land), `coins`
  the Tax Collector (grabbed coins heal you; left ones make his next move hit
  harder), `feast` the Royal Feast (smashing the platter or choking him stops
  the heal), `crown` the Crown Grab (punched in time he trips), `guilty`
  GUILTY! (a podium softens it; friends share it), `pillars` that his big
  moves break pillars and round 3 crumbles the rest, `final` THE FINAL GAVEL
  (once, at 10%; a jump or roll clears it; then he's worn out), and
  `entrance` his entrance (with `client`: drawn asleep up on his throne, then
  standing on it, then landing where he fights from - your lock-on following
  him - and back up onto it after a reset). It also checks he stays in the
  courtyard.
- `gavelgrunt_snaps.luau` + `render_snaps.py` - King Gavelgrunt's preview
  pictures: `luau gavelgrunt_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/gavelgrunt_preview.png --cols 3 --title "KING GAVELGRUNT|FLOOR 10  -  THE THRONE SUMMIT|RECOMMENDED LV 150"`;
  `-a poses` with `--cols 3 --title ""` the pose sheet
  (`Docs/gavelgrunt_poses.png`); `-a turn` with `--cols 2 --size 900,900`
  a big turnaround of him (front, three-quarter, side, back).
- `scribble_snaps.luau` + `render_snaps.py` - Scribble's preview pictures:
  `luau scribble_snaps.luau > s.txt` then
  `python3 render_snaps.py s.txt ../../Docs/scribble_preview.png --cols 3 --title "SCRIBBLE|FLOOR 9  -  THE CANVAS|RECOMMENDED LV 135"`;
  `-a poses` with `--cols 3 --title ""` the pose sheet (`Docs/scribble_poses.png`).
- `test_lockaim.luau` - WHERE YOUR LOCK-ON AIMS: CombatClient's own
  `targetPoint` and `lockView`, cut out of it: a boss is aimed at the middle
  BossClient measured while it's fresh (and as if still standing when it's
  up in the air), anything else at the middle of its parts as before; the
  camera's sums are unchanged except that a tall boss is looked at a little
  higher.
- `test_talk.luau` - THE BOSSES TALKING: the real BossIntro, a pretend boss
  whose head BossClient has measured, and a camera. The speech bubble hangs
  over the head with its tail pointing down at it; beside the head, pointing
  sideways, when there's no room up there; at the nearest edge (tail tucked
  away) with the head off the top, off a side or behind you; never over the
  boss bar; last words stay where they were said; the old box's "* " is
  gone; the tag carries the boss's name in its colour.
- `talk_snaps.luau` + `render_talk.py` - the speech bubbles' preview
  (`Docs/talk_preview.png`): each boss woken by a pretend player and seen
  through the lock-on camera (CombatClient's own sums), its wake line in the
  bubble exactly where BossIntro put it and the lock-on's brackets where
  they'd be. `luau talk_snaps.luau -a <floor> [before] [distance]` prints
  one floor (`before` adds how it looked before: the brackets on the Root,
  the old black box); put several in one file and
  `python3 render_talk.py talk_snaps.txt ../../Docs/talk_preview.png`.
- `test_vitals.luau` - THE HEART, THE POTION AND THE BOLT
  (ReplicatedStorage/Vitals): the three pixel pictures at the bottom of the
  screen. It starts the real module the way Hud does, with a pretend
  Humanoid and what CombatClient would tell it, and checks what's drawn
  square by square: the pictures are closed (no liquid can leak) and fill by
  how many squares are full (`shapes`); the heart alone in the lobby, filling
  with your health, spilling, shattering and mending (`lobby`); in a fight
  the potion and the bolt pop in beside it, standing on the same line, with
  the HP and Power words stepping aside so nothing overlaps (`arrive`); the
  bolt following your stamina closely (`stamina`), crackling when full
  (`sparks`), flickering with a red outline when you're out (`empty`) and
  glowing blue while a roll makes you untouchable (`iframes`); a drink - the
  cork pops, the bottle tips, its drops land in the heart, the heart fills
  without pouring its own drops too, the count ticks down and the next one's
  full (`drink`); the last flask, then grey glass, x0 and a shake (`last`);
  the count reaching 0 just before "Drinking" arrives (`race`); leaving
  mid-pour (`leave`); and two minutes of random everything (`fuzz`).
- `render_vitals.py` - its preview pictures: `luau test_vitals.luau -a snaps
  > v.txt` then `python3 render_vitals.py v.txt ../../Docs/vitals_preview.png`
  (every state); `-a pour` and `--cols 4 --tight --title "DRINKING A FLASK"`
  (`Docs/vitals_drink.png`: a drink, moment by moment). It lays out the real
  frames (anchor points, UIScale, rotation) the way Roblox does.
- `test_drink.luau` - THE DRINK (CombatClient's "The drink, as everyone
  sees it"): the real code cut out of CombatClient, run on a pretend R6
  character with Roblox's own shoulder and neck joints. With "Drinking" on
  the character, a potion (bottle, neck, cork, welded to the right arm, and
  unable to bump into anything) appears, the hand comes up to the chin and
  lifts to tip it back, the head tips back; afterwards the potion's gone and
  both joints are exactly where they were. Also: nothing piles up when no
  animation moves the joints, the drink starts from a walking arm without a
  snap, a character that disappears mid-drink is tidied up, another player's
  drink shows too, and a non-R6 body is left alone. `-a poses` prints the
  joints over a drink for `render_drink.py` (`python3 render_drink.py d.txt
  ../../Docs/drink_preview.png`).
- `test_sword.luau` - THE TEST SWORD on the server: the real CombatService
  (its "Weapons" part) with a pretend player among punchable targets. Fists
  still hit one enemy per punch; "DEV: Test Sword" puts the Iron Sword in
  your hand; a slash cuts every enemy in its arc but not the one behind or
  out of reach, as hard as a punch at mastery 1; the chop reaches further,
  hits 1.5x and is narrow; a swing thrown too soon is ignored; twelve quick
  slashes only get ten through (stamina); hitting raises mastery (and tells
  the screen); "DEV: Mastery +25" goes 25, 50, 75, 100, then back to 1; at
  100 a slash hits 1.5x; the Whirlwind cuts all round (not far away), cools
  down, spins twice at 50, sends a shockwave at 75 and spins three times at
  100; no swinging mid-spin; leaving mid-swing lands nothing; bad swing
  numbers and weapon ids can't break it.
- `test_weaponfx.luau` - WEAPONFX, how weapons look: the real module on
  pretend R6 characters. The sword is in the hand only in a fight (6 pieces,
  welded to the right arm, bumping into nothing); the slash sweeps the blade
  right to left and the backhand left to right (with the trail on), the body
  winds up and follows through, the chop comes down from above your head, the
  Whirlwind turns the body 360 / 720 / 1080 degrees by tier; everything's
  back exactly where it was afterwards; another player's swing and Whirlwind
  play when their counters change (an old counter doesn't); mastery 100 turns
  the blade gold; leaving the fight, dying mid-swing or letting go puts it
  away; a non-R6 body gets nothing. `-a poses` prints the joints for
  `render_sword.py` (`python3 render_sword.py s.txt ../../Docs/sword_preview.png`).
  (Nothing plays animations there, so it's the swings made in code - what
  every screen falls back to.)
- `test_swordanims.luau` - the sword's UPLOADED ANIMATIONS and 3D MODEL
  (WeaponFX with the ids in Config and the IronSword's Model), with a
  pretend Animator playing pretend tracks: the 3D sword (a model in
  ReplicatedStorage, as Studio's 3D Importer leaves it - here twice too big)
  is held at its grip, tip along the Handle's -Z, scaled to 5 studs, its
  glow Neon; the Grip is a Motor6D; standing, the idle plays and the body
  and blade are left to it; walking, the idle stops and the code holds the
  sword arm; a swing plays from the start, nothing drawn over it, the smear
  between its animation's Cut and Through markers, one whoosh; chained
  swings hand over at once; hit-stop freezes the track for a blink; a swing
  that hasn't loaded is drawn in code (the last one stopped); the Whirlwind
  stops a swing and isn't cut short; someone else's swing arrives by itself
  (their idle and swing left alone), one that doesn't arrive in 0.15 s is
  drawn in code, and code steps aside if it turns up late; leaving the fight
  stops and throws the tracks away; no 3D model: the blocky sword.
- `test_weapon_save.luau` - OWNING WEAPONS on the server: you can only
  equip what you own, and the weapon in your hand and every weapon's mastery
  are kept in the save (`data.Weapons`); the held weapon goes back in your
  hand when you join.
- `test_weapontypes.luau` - the WEAPON TYPES in WeaponFX (gauntlets, hammer,
  daggers, scythe, katana): each one in hand (two for gauntlets and daggers),
  its own stance, and every swing of its string - an arm really swings, the
  smear shows through the cut, the feet stay down, and it settles back.
  `-a trace` prints which way the weapon points every frame; `-a poses` the
  blocks and poses for `render_weapontypes.py`.
- `test_blocks.luau` - ABILITY BUILDING BLOCKS on the server: the aura and
  PowerN, DamageUp and Lifesteal (and wearing off), the cooldown, Shield,
  Guard, a Burst, NextHit's Mark, Stacks, and leaving the fight clearing it
  all.
- `test_voxelhold.luau` - holding the VOXEL WEAPONS' 3D models
  (`Tools/Weapons`): a pretend imported model, turned, moved and scaled any
  old way, is held exactly where its markers say at its true size, the
  markers gone, each mesh coloured from `WeaponModelInfo`, one in each hand
  for gauntlets and daggers, gold metal when awakened, and the blocky one
  until the model arrives (then the real one swaps in).
- `test_moves.luau` - every weapon ABILITY MOVE on the server (all 30,
  `ReplicatedStorage/Moves`): each one used among dummies hurts only what it
  should (close in front, never the far dummy, nothing before its first hit
  is due); the patches it leaves keep hurting and slow; things thrown fly
  and hit; a spot it picks is the dummy you're locked on to, and every screen
  is told (AbilityFx); the aura and its style; the specials (No Quarter's
  gold wave, Copy-Paste's copies, Victory Lap's rolls); cooldowns and
  stamina.
- `test_movefx.luau` - how every ability LOOKS (`ReplicatedStorage/MoveFX`):
  each weapon's move played on your own screen and on someone else's, the
  spots the server picks, every building block's moment and every style's
  aura - each really draws something, nothing errors or warns, and it all
  tidies itself up.
- `test_arcade.luau` - THE ARCADE on the server (ArcadeService, and the
  Arcade Tokens in PlayerService) with a pretend DataStore: 200,000 spins
  come out at the odds the machines show; the first spin ever is never a
  Common; a Legendary or better never takes more than `Pity` spins and each
  machine counts its own; the "ArcadeRoll" action through the real Action
  remote refuses bad requests, a machine you haven't opened, spinning outside
  the lobby, too fast and not enough tokens, takes the right price (x1 / x10),
  gives new weapons, mastery for ones you own (shown at once if held), a
  token back once mastered, tells every screen and fills the BIG WINS board;
  a new player's first dummy quest is the small one and a handed-in quest
  pays a token; a new set of quests every 6 hours, and a finished quest not
  yet handed in is handed in for you when the set changes (online, or from
  an old save when you join) - once; a boss's first win pays
  tokens and opens its machine; tokens and the counters are saved, and a
  nonsense save is cleaned up.
- `test_arcade_client.luau` - THE ARCADE on your screen (ArcadeClient),
  talking to the real server, in the real building (ArcadeBuilder), with
  pretend imported Slime models: the ROLL button and badge, the machines'
  screens, the prize pedestal, walking in opening the menu (once) and out
  closing it, the menu (odds, pity, locked and covered machines), a spin
  (the camera flies to the machine, the strip lands on the server's pick, the
  reveal card with the weapon turning round its middle, EQUIP, SPIN AGAIN,
  DONE, tap to skip), ten at once (a Legendary's reveal, then the grid),
  someone else's Secret (the machine lights up, their result floats over it,
  the banner, BIG WINS), two spins on one machine taking turns, the HUD's
  ArcadeOpen, the token machine, and no spinning outside the lobby or in the
  intro. `-a snaps` also prints snapshots of the screen for `render_gui.py`.
- `test_weaponbag.luau` - the WEAPONS panel (WeaponBag.client.lua): a card
  per weapon you own, rarest first, its icon when it's uploaded
  (`AssetIds.Icons`) and none when it isn't, IN HAND / EQUIP.
- `test_hud.luau` - the HUD's ARCADE TOKENS (Hud.client.lua): the counter
  bottom-left and its token picture, clicking it opens the Arcade
  (`ArcadeOpen`), the hint line nudging you to spin, and DEV: +10 Tokens.
- `test_moneyicons.luau` - the living coin and token (MoneyIcons): made
  once all 8 pictures are uploaded (flipping through them, the token
  bobbing), nothing while any is missing.
- `test_rewards_shop.luau` - THE NEW GUI's SERVER SIDE (RewardService and
  ShopService) with a pretend DataStore, Marketplace and PolicyService and
  three players: the new save fields start empty and a nonsense save is
  cleaned up; the login streak (once a day, a missed day starts again, day 7's
  title once); the free gift (only after its minutes of play, its daily limit,
  a new day); codes (capitals and spaces ignored, once each, dates), update
  gifts; the Index (only weapons you own, once each, by rarity), the
  collector bar and its levels, the community chest; wearing titles and auras
  (shown over your head / round you); settings; the corner bonuses (time in
  the server, friends, a VIP friend) and the 2x passes, VIP and boosts on XP
  and coins (and the intro's exact amounts untouched); ROBUX: SOON while a
  product has no id, the prompt, a receipt pays once however often Roblox
  sends it, "granted" only after the save is written (a failed save says
  "not yet" and the retry pays nothing more), the starter pack once, gifts to
  someone in the server (and to the buyer if they've left), no paid random
  items where PolicyService says no (or can't say); game passes at join and
  when bought; Daily Items; luck (the passes, the boost, the odds, a real spin).
  It moves the calendar with `M.dayShift` (os.time only) instead of playing
  through whole days.
- `gui_snap.luau` + `render_gui.py` - PICTURES OF A SCREEN (any ScreenGui):
  `gui_snap` prints what a ScreenGui draws right now (boxes, borders,
  gradients, words, clipping, with UIScale / UIListLayout / UIGridLayout /
  UIPadding worked out), and `render_gui.py` paints the snapshots in a grid
  with captions (`--bg` a picture of the world behind, `--font` the game's
  FredokaOne if you have it, `--pixel` Press Start 2P for words in Roblox's
  "Arcade" pixel font - the window look's titles and buttons). The Arcade's:
  `luau test_arcade_client.luau -a snaps > s.txt`, then `python3 render_gui.py
  s.txt ../../Docs/arcade_screens.png --bg inside.png --font FredokaOne.ttf
  --pixel PressStart2P.ttf`.
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
- `oozark_cutscene.luau` + `render_cutscene.py` - the 10-second Oozark
  cutscene for YouTube (`Docs/youtube/oozark_cutscene.mp4`): the scene
  script runs the real BossService and BossClient with his moves forced one
  after another (rise, lunge, slam, wave) and a blocky player who walks in,
  rolls, punches and jumps the wave, and prints every frame; the renderer
  films it with moving cameras and puts the boss bar, his name, hit pops and
  the freeze-frame ending on top (`--strip --at 5.2,6.5` draws just those
  moments, to check a shot).
- `brute_cutscene.luau` + `render_brute_cutscene.py` - the same for THE BRUTE
  (`Docs/youtube/brute_cutscene.mp4`): little Tuber punched, the power-up,
  the root hop, the fight back, frozen as his spines blast the player away.
- `burrowmore_cutscene.luau` + `render_burrowmore_cutscene.py` - the same
  for KNIGHT BURROWMORE (`Docs/youtube/burrowmore_cutscene.mp4`, 11 seconds):
  his wake-up and pose (his name slams on), a Shovel Drop (the red circle
  chasing the player), punches while his shovel's stuck, a Charge Dash into
  the edge of the dig, NO QUARTER!, and his Shovel Meteor in slow motion,
  frozen as he plunges. The film's clock runs faster or slower than the
  game's in places (the scene's header says where); `--sheet` draws a 3 x 3
  contact sheet (`Docs/youtube/burrowmore_cutscene_frames.png`).
- `gavelgrunt_cutscene.luau` + `render_gavelgrunt_cutscene.py` - a 5.6-second
  LOOP of KING GAVELGRUNT's Big Gulp (`Docs/youtube/gavelgrunt_gulp.mp4`):
  the player runs at us, the wind drags them back and lifts them into his
  mouth (GULP!), he chews, spits them out (PTOO!) and burps them face first
  along the floor in slow motion (BUUURP!); they get up dizzy - and he's
  opening his mouth again (NOT AGAIN!). His Big Gulp is forced twice, 5 s
  apart, and the film runs from 1 s into the first to 1 s into the second,
  so the last frame runs straight into the first (every pose of the player
  is worked out from the seconds since the move began, never stepped along).
  The hook THE FINAL BOSS ATE ME stays on top. It has quiet sound effects
  mixed in (the game's own Big Inhale, Gulp, Munching, Spit Out and Royal
  Burp, plus a few soft ones made in the renderer), peaking at -8 dB so they
  sit under music, and they wrap round the loop too. `--seam` draws the last
  frames and the first in a row (to check the loop), `--sound` writes just
  the sound (a WAV), `--poster` the thumbnail
  (`Docs/youtube/gavelgrunt_gulp_thumbnail.png`/`.jpg`), `--sheet` the frames
  (`Docs/youtube/gavelgrunt_gulp_frames.png`).
- `abilities_film.luau` + `render_abilities.py` - the weapon abilities'
  EFFECTS filmed from the real MoveFX (`Docs/animations/slime_abilities_fx.mp4`):
  each Slime ability used in turn among dummies, with tweens really playing
  out; the renderer draws the player posed by the ability's own animation
  (`Tools/Animations/abilities.py`) holding the blocky stand-in, with the
  pops and flashes on top: `luau abilities_film.luau > film.txt`, then
  `python3 render_abilities.py film.txt out.mp4` (`--sheet` for a PNG of key
  moments). `film_draw.py` is the drawing both use (from
  `render_burrowmore_cutscene.py`).

Run them all with `./run_all.sh` (it ends with `./golden.sh check`) (needs the Luau tools from
https://github.com/luau-lang/luau/releases; the pictures also need Python
with numpy and pillow).
