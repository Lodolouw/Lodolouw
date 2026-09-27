# Boss Grow — Starter Lobby

A "+1 to grow" style Roblox lobby, built entirely from scripts (no imported
models/assets). This is **lobby only** — no arena, no bosses yet, as requested.
There's an inert "BOSS ARENA - Coming soon" gate so you can see where the
arena will plug in later.

## What's included

- **Procedurally-built lobby** (toy-brick island, paths, tall mossy castle
  walls, trees, lamps)
- **Sell Shop** — sell loot materials for coins
- **Upgrade Shop** — spend coins on 4 permanent-per-run upgrades (backpack
  size, power gain, sell value, walk speed)
- **Talisman Workbench** — craft 6 talismans from coins + materials, equip up
  to 3 at once for stat bonuses
- **Prestige Shrine** — reset Power/Coins/Upgrades for permanent multipliers
- **The Colosseum** — walk through the mini colosseum's door (south-west of
  the plaza) into your own wave arena: dummies hop in wave after wave, the
  King last. This is where you level up. (The old training pads are gone.)
- **Tall mossy castle walls** — a much taller stone perimeter wall than a
  typical starter lobby, with crenellated merlons on top, moss patches
  climbing the inner face, and ivy strands hanging down. All Parts, no
  imported meshes.
- **Chimes** — buying, selling, crafting and prestiging each got their own
  short chime instead of one generic ping.
- Full GUI built from code: left-side buttons, backpack/coins/power readout,
  hint banner, goal progress bar, floating "+N" numbers, toast notifications,
  and 4 popup panels

## File layout → where each file goes in Studio

```
ReplicatedStorage/
  Config.lua                  → ModuleScript named "Config"

ServerScriptService/
  LobbyBuilder.lua             → ModuleScript named "LobbyBuilder"
  PlayerService.lua            → ModuleScript named "PlayerService"
  Main.server.lua               → Script named "Main"

StarterPlayer/StarterPlayerScripts/
  LobbyFX.client.lua           → LocalScript named "LobbyFX"
  Hud.client.lua                → LocalScript named "Hud"
```

### Setup steps

1. In Studio, create the folders/instances above with those exact names and
   parents (rename after inserting — Studio adds ".lua" only on disk, not in
   the instance name).
2. Paste each file's contents into the matching instance.
3. Enable **Enable Studio Access to API Services** if you want DataStore
   saving to work while testing in Studio (Game Settings → Security). Without
   it, the game still runs fine, just without persistence.
4. Hit Play. `Main` builds the lobby and starts the game loop automatically.

## How it fits together

- **Config.lua** is the single source of truth for every number (the
  Colosseum, upgrade costs, talisman recipes, prestige formulas). Both
  the server and the client require it, so they always agree.
- **LobbyBuilder.lua** runs once on the server at startup and builds every
  Part/Model/GUI-anchor in Workspace. Nothing here is a real asset — it's all
  `Instance.new("Part")` calls. Decorative pieces are tagged `"FX"` so the
  client can animate them without the server doing any per-frame work.
- **PlayerService.lua** owns all player data (Power, Coins, Loot, Upgrades,
  Talismans, Prestige), validates every action server-side (never trust the
  client), and pushes state snapshots to each player's HUD. It also exposes
  `PlayerService.AddLoot/AddCoins/AddPower/GetData` for your future arena
  scripts to call when a boss dies.
- **Hud.client.lua** builds 100% of the GUI from code and only ever *displays*
  the last snapshot from the server — it never assumes anything client-side is
  authoritative.
- **LobbyFX.client.lua** is a tiny, generic animator: anything tagged `"FX"`
  with `SpinSpeed`/`BobAmp`/`BobSpeed`/orbit attributes gets animated. Add more
  tagged parts later and they'll animate for free.

## Hooking up the arena later

When you build the boss arena, call into the existing systems instead of
writing new ones:

```lua
local PlayerService = require(game.ServerScriptService.PlayerService)

-- when a boss dies:
PlayerService.AddLoot(player, "Ember", 3)   -- returns how many actually fit
PlayerService.AddCoins(player, 500)
PlayerService.AddPower(player, 1000)
```

The `ArenaGate` model (tagged nowhere, just sitting north of the plaza) has a
`Portal` part with a `Destination` attribute reading "TODO: teleport to the
boss arena" — that's your teleport hook once the arena place/area exists.

## Notes / things you'll likely want to change

- `PING_SOUND` / `HIT_SOUND` in Hud.client.lua use built-in `rbxasset://`
  placeholder sounds — swap in your own asset IDs.
- Buying and selling instead use a `Sound` instance named `coin2` under
  `SoundService` (see `COIN_SOUND` / `playNamedSound` in Hud.client.lua) - if
  that Sound gets renamed or removed it falls back to `PING_SOUND`.
- `Config.RequireProximity` / `Config.StationRange` control whether shop
  actions require standing near the station (on by default). The left-side
  Upgrades/Backpack/Talismans/Prestige buttons teleport the player to that
  station's spot when clicked, so a purchase from the panel never fails
  with "walk up to the X first."
- All 6 files were checked for structural syntax correctness (balanced
  brackets/parens/braces and every `function`/`if`/`for`/`while`/`do`/`repeat`
  block correctly matched with `end`), and every RemoteEvent/RemoteFunction
  name, CollectionService tag, instance attribute, and part name referenced
  across files was cross-checked to match exactly.

## The intro: Oozlet (a brand-new player's first minute)

A new player wakes up in the dark, like the start of Undertale: only the
fountain and the plaza are there, with 8-bit mist at the edge, no buttons and
no other players. Oozlet - Oozark's baby, a blocky slime with a tiny crown -
is happily hopping round the fountain, and HIT THE SLIME! builds up letter
by letter until the "!" lands with a BOOM. Punch it and it gets angry: a
short fight you can't lose that teaches punching and rolling (its first slam
hangs over you until you roll), it cracks at half health and pops, and drops
your first chest (Oozlet's Chest: starter gear anyone can wear). Then the mist
rolls back, the lobby builds itself around you piece by piece, and the Spire
rises out of nothing: OOZARK AWAITS...

- `ServerScriptService/IntroService.lua` runs the fight (all on the server);
  `StarterPlayerScripts/IntroClient.client.lua` draws everything, on that
  player's screen only. Every number and word is in `Config.Intro`.
- Only brand-new players get it (it's saved). **In Studio it never starts by
  itself** (Studio often can't save, so every Play would look brand new) -
  watch it with the dev console's "DEV: Replay Intro", or set
  `Config.Intro.InStudio = true` to get it on every Play.
  `Config.Intro.On = false` switches it off for everyone.
- Preview: `Docs/intro_preview.png`.

## The Spire's second floor: Tuber, then THE BRUTE (the Sunken Dunes)

A boss with **two health bars and two completely different fights** (a
parody of a certain famous stack of cactus from a certain plumber's games -
with his own name and look). He sleeps in a little garden in the middle of a
sunny cactus desert. Recommended level 30.

- **Round 1: TUBER** - a chubby, potato-shaped stack of three lumpy cactus
  blocks with a pink flower, dot eyes and rosy cheeks. Easy on purpose (long
  warnings, long breaks), so you think he's a joke. WOBBLE BONK (leans back,
  flops his head forward: step out of the red wedge), CLUMSY TOPPLE (falls flat
  along a red lane like a tree, then lies there flailing: free hits), NEEDLE
  SNEEZE ("ah... ah... ACHOO!": a ring of needles, jump or roll it), BOUNCE
  STOMP (lands on the red circle) and, every third move, **SPLIT!**: he pops
  into three buddies that curl into spiky balls and SPIN-DASH at you one after
  another (each bounces once off a rock or the edge), then sit there dizzy -
  punch any of them, they share his health - and hop back into a stack.
- **THE POWER-UP** (his first bar runs out, 9 seconds, nobody can be hurt):
  he flops over (split up? his buddies hop back together first), his flower
  wilts, the music stops... the ground rumbles, a
  sandstorm rolls in, and **every cactus in the arena rips out of the ground
  and flies to him**. The pieces slam together into a giant cactus golem; a
  crown drops onto his head; his eyes light up red. Across your screen the
  letters of TUBER shake, slide into new places and turn red: **BRUTE** - and
  **THE** slams down next to it. He roars: THE CACTUS KING... THE DESERT BOWS.
  Camels (in bright saddle blankets), meerkats, vultures and lizards have come
  to watch - the camera looks out at a camel walking up onto its ledge - and
  they bow. His second health bar - "The Brute, the Cactus King" - fills up
  and the music slams in. Your camera swoops round him for the whole show.
- **Round 2: THE BRUTE** fights from a distance: his goal is to keep you away,
  yours is to break through his cactus and catch him. Get close and he rips
  his roots up and **hops away** across the arena (his roots wriggle when his
  hop is ready again). Catch him while it's recharging and he's **CORNERED**:
  he panics (free hits!), blasts you back with a shove burst and escapes.
  Meanwhile: NEEDLE VOLLEY (a red cone, three fans of needles), DESERT RAIN
  (cactus balls fall on red circles), SPINE LANCE (a line locks on, a giant
  spike flies across the arena - dodge late, rocks stop it), CACTUS WALLS
  (burst up between you and him; go round, or punch the glowing weak spot
  twice), NEEDLE TURRETS (little towers that shoot you; two punches), BALL
  HERD (spiky balls roll in from the edge, bouncing off rocks and walls),
  PRICKLY BUDDIES (minions that waddle after you and pop; one punch) and
  QUICKSAND (drags you in and nibbles). **Break the last of his walls and
  turrets and he's STUNNED** - out of cactus, free hits. Low on health he
  goes into a **RAGE**: more of everything, and his walls creep toward you.
- **The end:** he freezes, cracks and crumbles into a heap of cactus balls
  that roll away - and out pops tiny Tuber, flower wilted, who stomps off in a
  huff (HMPH!). The banner says THE BRUTE VANQUISHED. Everyone gets the
  floor-2 chest (its loot hasn't changed).
- **The arena** (`DunesBuilder`): the Sunken Dunes as a cactus desert - cacti
  everywhere (tagged `DuneCactus`: the ones that fly into the golem, put back
  when the fight resets), boulders (`DesertRock`: rolling balls bounce off
  them, needles and the lance stop at them - cover!), lookouts on the dunes
  for the audience (`DuneLookout`), Tuber's garden in the middle, a cactus
  flower over the gate. The worm's seal, lair, platforms, pillars and ribcage
  are gone.
- **Where things are:** every number in `Config.Bosses[2]` (`PhaseAt` is where
  his first bar ends; `Attacks` has both rounds' moves, `Moves` the Brute's
  hop, cornered, stun and rage); the floor in `Config.Spire.Floors[2]`; his
  brain and moves in `ServerScriptService/Bosses/Tuber.lua`; his body, both
  health bars, the power-up show (the letters, the camera, the flying cacti,
  the audience) and everything he plants in `ReplicatedStorage/BossBodies/Tuber.lua`;
  his portraits and lines (Tuber's, then the Brute's) in `BossIntro`.
- **Music:** round 1 plays a Sound named `Tuber Song` (add a cute, bouncy one
  - Oozark's plays until you do); the power-up is silent; round 2 plays
  `SANDWORMSONG`. **Sounds** - the ones you already have from the old worm
  (missing ones borrow Oozark's): Worm Erupt (popping up, cacti ripping out of
  the ground, walls bursting up), SandWhip (the bonk, the sneeze, needles),
  Worm Slam (toppling, stomping, landing), Worm Crack (splitting, the
  power-up's burst, things breaking), Worm Charge (rolling balls, his hop, the
  lance), Worm Devour (stacking back up, the golem forming), SandRumble (the
  power-up's rumble), SandRoar (THE BRUTE roars), Worm Death.
- Previews: `Docs/tuber_preview.png` (the fight) and `Docs/tuber_poses.png`
  (him pose by pose, and the audience close up).

## The Spire's third floor: Knight Burrowmore (the Glimmer Dig)

A knight of the shovel (a parody of a certain blue shovel knight, with his
own name, colours and curly horns) kneels in the middle of an old dig site on
the sunny plains. Walk near and he gets up, pulls his shovel out of the dirt,
twirls it and strikes a pose. It's a **souls-like** fight: every move has one
clear wind-up, one way to dodge it, and a moment afterwards when he's open -
you learn him by losing to him. Recommended level 45.

- **His moves:** Shovel Drop (jumps high; the red circle under him FOLLOWS you,
  flashes and locks - roll just before he lands), Triple Pogo (three hops at
  you, dizzy after), Shovel Swing (a red wedge in front of him), Dirt Fling (a
  fan of clods), Anchor Toss (a relic: "item get!", swung round overhead, lobbed
  onto you, then he has to tug it out of the floor), Fire Stick (a relic:
  fireballs along red strips on the floor), Charge Dash (a red lane that locks
  on; running into the edge of the dig dizzies him) and a Taunt (free hits).
- **Phase two, "No Quarter!":** at half health his shoulder plates fly off,
  cracks glow gold in his armour and he gets faster: the Delayed Drop (he hangs
  at the top to catch early rollers), Swing into Drop, Gem Rain (treasure falls
  into marked circles while he keeps fighting) and his final move, the Shovel
  Meteor (below 30% health: he jumps out of sight, a huge shadow grows in the
  middle - get to the edge - then he's stuck in the ground).
- **The end:** he drops to one knee ("You dig... with honour..."), pops into
  pixels, and a treasure chest bursts up out of the dirt. Everyone in the dig
  gets Burrowmore's Chest (Spade Knight's and Relicbound gear).
- **Where things are:** every number in `Config.Bosses[3]`; the floor in
  `Config.Spire.Floors[3]`; his moves in `ServerScriptService/Bosses/Burrowmore.lua`;
  his body in `ReplicatedStorage/BossBodies/Burrowmore.lua`; the arena in
  `ServerScriptService/DigBuilder.lua`; his portrait and lines in `BossIntro`.
- **Music:** a Sound named `Burrowmore Song` in SoundService (Oozark's plays
  until you add it). **Sounds** (all optional, missing ones borrow Oozark's):
  Burrowmore Wake, Burrowmore Jump, Burrowmore Land, Shovel Swing, Shovel Dig,
  Dirt Land, Relic Get, Anchor Throw, Anchor Land, Fire Stick, Burrowmore Dash,
  Burrowmore Crash, Burrowmore Laugh, Gem Land, Shovel Meteor, Armour Crack,
  Burrowmore Death.
- Previews: `Docs/burrowmore_preview.png` (the fight) and
  `Docs/burrowmore_poses.png` (him, pose by pose).

## The Spire's fourth floor: Kaze, the Headband Hero (the Rooftop Dojo)

A wandering martial artist (a parody of a certain headband-wearing world
warrior, with his own name, look and moves) meditates in a dojo on a
mountain peak above the clouds, at sunset. Walk near and he opens his eyes,
stands, bows, drops into his stance: **ROUND 1... FIGHT!** He fights like a
**fighting-game character**. Recommended level 60.

- **The KI METER** (three bars, under his boss bar): it fills when his hits
  land on you, when you punch thin air near him (don't swing wildly - "+KI"),
  a little all the time, and fast while he meditates. Every special costs a
  bar. A full meter flashes **MAX** - his Super is coming. Once a round (at
  70% health, then 25%) his ki flares straight to MAX.
- **His moves:** a Punch String (jab, straight, heavy "HYAH!" - each with a
  small red wedge), Dash In (a dash with afterimages into a string), and his
  three SPECIALS, shouted in pixel letters: **KAZE-BLAST!** (a ball of ki
  rolling along a red lane - jump it or roll; it bursts on a pillar),
  **RISING DRAGON!** (a spinning uppercut straight up inside a red ring - back
  off, then punish his landing; up high he's out of reach) and **TORNADO
  KICK!** (he spins across the dojo along a red lane - roll through him).
- **Charging and cancelling:** now and then he holds a special (a blue glow
  and a rising hum) - the longer, the bigger. Punch him twice while he glows
  (or while he meditates, "HAAAA...") and it breaks: he staggers. He can
  CANCEL (a white flash): a string into a special, a fake charge into a dash,
  a hop back out of a missed special. The diamonds under his meter are his
  cancels for the round - when they run out he's **TIRED** (hands on knees,
  panting, "TIRED! HIT HIM!" over his head): free hits.
- **SUPER!:** at a full meter the screen flashes, he leaps to the middle of
  the dojo, a red fan shows where his giant beam will sweep, and the four
  stone pillars glow: **hide behind one** (the beam can't go through), get out
  of the fan, or roll through the beam. Every pillar the beam hits crumbles.
- **ROUND 2** (half health): down on one knee, a burst of ki throws everyone
  back, his gi tears, he re-ties his headband. The pillars are back, his meter
  fills twice as fast, he chains specials together and has more cancels.
- **The end: K.O.!** He falls, his headband drifts away on the wind, and he
  scatters into cherry blossom petals (**PERFECT!** if you never got hit).
  Everyone gets Kaze's Chest (Windwalker and Ki Master's gear).
- **Where things are:** every number in `Config.Bosses[4]`; the floor in
  `Config.Spire.Floors[4]`; his brain and moves in `ServerScriptService/Bosses/Kaze.lua`;
  his body, meter and screens in `ReplicatedStorage/BossBodies/Kaze.lua`; the
  arena in `ServerScriptService/DojoBuilder.lua`; his portrait and lines in `BossIntro`.
- **Music:** a Sound named `Kaze Song` in SoundService (Oozark's plays until
  you add it). **Sounds** (all optional; missing ones borrow Oozark's): Kaze
  Wake, Kaze Punch, Kaze Heavy, Kaze Blast, Kaze Dragon, Kaze Tornado, Kaze
  Charge, Kaze Cancel, Kaze Dash, Kaze Land, Kaze Focus, Kaze Stagger, Kaze
  Pant, Kaze Super, Kaze Beam, Pillar Crumble, Kaze Round Two, Kaze Death - and
  the announcer (silent until you add them): Round One, Round Two, Fight, KO,
  Perfect.
- Previews: `Docs/kaze_preview.png` (the fight) and `Docs/kaze_poses.png` (him,
  pose by pose).

## The Spire's fifth floor: Speedy Revvington (Piston Speedway)

A cocky red race car (a parody of a certain famous red race car, with his own
name, number - 57 - and catchphrase: "Ka-VROOM!") waits on the start line of a
roaring desert racetrack, the grandstands packed with blocky fans. His face is
his windscreen and his grin is on his bumper. Walk up and the start lights on
the gantry count down: **3... 2... 1... GO!** It's a **drive-by duel**: like a
knight on horseback he charges at you, drives past swinging his tail, rears
up, skids round and charges again. Recommended level 75.

- **How he moves:** he never walks - he drives, along straight lines, curves
  and skid turns that every screen follows exactly (`ReplicatedStorage/CarPath`),
  even at 100 studs a second. Between moves he circles you like a shark. You
  can't walk through him, and when he's flat out he runs you over.
- **His moves:** CHARGE (he revs, tyres smoking, a red lane follows you, his
  headlights flash as it locks - get out of the lane; then he brakes and turns
  round slowly: your chance. If the lane ends at the tyre wall a yellow ring
  marks it: he CRASHES and is dizzy - "DIZZY! HIT HIM!"), TAIL WHIP (a red
  strip shows where he'll drive past you, then his tail whips round across a
  red half-circle on your side), WHEELIE SLAM (you're close in front: he rears
  up on his back wheels over a red circle, slams down, and a shock ring rolls
  out - jump it), HONK (close in front: his cheeks puff up... "HONK!!" throws
  you back), BACKFIRE (behind him: his pipes glow... BANG - fire and burning
  puddles), SIDE BUMP (right beside him: he leans away, then hops sideways at
  you - "BONK!") and DONUTS (showing off for the crowd: free hits).
- **TURBO!** (half health): a blast of blue nitro throws everyone back, his
  stripes glow, his spoiler grows and he gets faster - he charges twice in a
  row and adds the BURNOUT RING (he laps you once, leaving a ring of fire,
  then dashes through the middle at you: jump the flames, or roll the dash).
- **The end: FINISH!** He sputters and coughs black smoke, a front wheel pops
  off and rolls away, his bumper drops off, X eyes... and he bursts into
  checkered confetti. The screen shows YOUR TIME (the race clock under his
  boss bar counts from GO!). Everyone gets Revvington's Chest (Speedster and
  Turbocharged gear).
- **Where things are:** every number in `Config.Bosses[5]`; the floor in
  `Config.Spire.Floors[5]`; his brain and moves in `ServerScriptService/Bosses/Revvington.lua`;
  how he drives in `ReplicatedStorage/CarPath.lua`; his body, the race clock and
  the start lights in `ReplicatedStorage/BossBodies/Revvington.lua`; the arena
  in `ServerScriptService/SpeedwayBuilder.lua`; his portrait and lines in `BossIntro`.
- **Music:** a Sound named `Revvington Song` in SoundService (Oozark's plays
  until you add it). **Sounds** (all optional; missing ones borrow Oozark's):
  Revvington Wake, Engine Rev, Revvington Charge, Tire Skid, Revvington Crash,
  Tire Screech, Suspension Slam, Big Honk, Exhaust Backfire, Car Bump, Donut
  Screech, Fire Whoosh, Revvington Turbo, Revvington Sputter - and (silent
  until you add them) Crowd Cheer, Start Beep, Start Go, Checkered Flag and
  Revvington Engine (a LOOPING hum: its pitch follows his speed).
- Previews: `Docs/revvington_preview.png` (the fight) and
  `Docs/revvington_poses.png` (him, pose by pose).

## The Spire's sixth floor: Gridlock, the Final Beat (The Final Beat)

A living LEVEL (a parody of a certain famous final level of a certain rhythm
game full of cubes and spikes - with his own name and look): a giant black
cube with glowing red edges, slanted yellow eyes, a jagged grin and little
horns, asleep in the middle of a neon grid floating in a purple void, with
giant spikes, spinning saws and his own grinning face in the sky all round.
Walk up and the level starts: **ATTEMPT 1** (then 2, then 3...), written
across your screen and in the level itself. Everything happens **on the beat**
of the music. Recommended level 90.

- **The level fights too:** tiles light up red, flare on every beat (white on
  the last one: get off!) and then spike - rows marching out from him, rings,
  checkers, stripes, halves. Jump the spikes, roll through them, or stand on a
  dark tile. The lines between the tiles pulse with the music, and eight
  yellow **jump pads** throw you high into the air.
- **His forms** (he changes through a portal every few moves: green, pink,
  orange or cyan): **CUBE** (HOP SLAM: his square lights up, he flips through
  the air onto it and a ring of spikes pops up round it; SPIKE ROWS: a stomp,
  and rows of spikes march out a tile a beat), **SHIP** (BOMB RUN: a lane of
  tiles through you, a bomb a beat down it; SWOOP: a red lane locks on and he
  dives down it), **UFO** (UFO SLAM: the circle under him follows you, locks,
  the tractor beam comes down... SLAM - then he's stuck: "STUCK! HIT HIM!";
  ORB RAIN) and **WAVE** (ZIG-ZAG: he zooms along a dotted zig-zag, leaving a
  wall of light behind him). Any form: TILE PATTERN (the level itself).
- **THE DROP:** every few moves the music builds - DROP IN 3... 2... 1... -
  he rises to the middle, the jump pads glow green, and EVERY tile spikes
  (the runway too) except the pads. Stand on a pad (it throws you up), jump,
  or roll. Then he crashes down: **STUNNED! HIT HIM!**
- **GRAVITY FLIP!** (half health): the whole world turns upside down and he
  falls UP to the ceiling grid. From there he drops onto a square that follows
  you (a red line shows where - and then he's stuck head-first in the tiles),
  flips back down now and then, changes form faster, and adds STOMP CHAIN
  (three hop slams, one a beat). Round 2 starts with THE DROP.
- **The end: LEVEL COMPLETE!** He glitches, X-eyed, and shatters into little
  neon cubes while the grid lights up green, and your attempts are on the
  screen. The level's **%** bar under his boss bar shows how far through him
  you are. Everyone gets Gridlock's Chest (Beatbound and Demon Geometry gear).
- **The beat:** `Bpm` in `Config.Bosses[6]` is the level's tempo (128). Set it
  to your song's tempo and everything (his hops, the tiles, the drop) lands on
  your music; `BeatOffset` (seconds) lines it up with the song's first beat.
  The song starts from wherever the level is (it began when he woke), so the
  music and the tiles stay in step even if you arrive mid-fight.
- **Where things are:** every number in `Config.Bosses[6]`; the floor in
  `Config.Spire.Floors[6]`; his brain and moves in `ServerScriptService/Bosses/Gridlock.lua`;
  the grid, the beat, the tile patterns and his motion (the same sums on the
  server and every screen) in `ReplicatedStorage/BeatGrid.lua`; his body, the
  level's tiles, the % bar and the screens in `ReplicatedStorage/BossBodies/Gridlock.lua`;
  the level in `ServerScriptService/GridBuilder.lua`; his portrait and lines in `BossIntro`.
- **Music:** a Sound named `Gridlock Song` in SoundService (Oozark's plays
  until you add it). **Sounds** (all optional; missing ones borrow Oozark's):
  Gridlock Wake, Cube Hop, Cube Slam, Spikes Up, Portal Whoosh, Ship Thrust,
  Bomb Drop, Ship Dive, UFO Burst, Orb Land, Wave Zoom, Drop Build, The Drop,
  Gridlock Stun, Gravity Flip, Jump Pad, Gridlock Break, Gridlock Shatter -
  and (silent until you add them) Attempt Start and Level Complete.
- Previews: `Docs/gridlock_preview.png` (the fight) and
  `Docs/gridlock_poses.png` (him, pose by pose).

## The Spire's seventh floor: Kongo, the Jungle Brawler (Kongo's Jungle Village)

A huge gorilla in a red tie with a big K on it (a parody of a certain famous
barrel-throwing ape, with his own name and look) naps in the middle of a flat
jungle clearing. Round it: a village of huts on stilts joined by rope bridges,
two giant trees with treehouses, tiki torches, banana stalls and barrel piles,
and behind it all a waterfall thundering down a cliff into a river, with a
rainbow in the spray. Little monkey villagers watch from the huts. Walk up and
he wakes: *YAWN*... then a chest pound and "OOH OOH!". He fights with the moves
from his games. Recommended level 105.

- **His moves:** GIANT PUNCH (he windmills his arm: the longer he winds up,
  the bigger the punch, and a red lane grows toward you and blinks when it
  locks - step out of the lane. If he misses he's **TIRED**, hands on his
  knees, panting: "HIT HIM!"), HAND SLAP (he slaps the ground 3 or 4 times, a
  shockwave rolling out from each slap - jump them or roll through), ROLLING
  ATTACK (he curls into a ball and rolls down a red lane at you; if it reaches
  the edge of the clearing he bounces off and rolls back down a second lane -
  and he's **DIZZY** afterwards: "DIZZY! HIT HIM!"), SPINNING KONG (arms out,
  he spins like a helicopter inside a red ring, drifting after you - back off;
  dizzy afterwards too), HEADBUTT (close up: a quick lunge, head first),
  BARREL THROW (he heaves barrels over his head and rolls them down red lanes
  at you - jump them), TNT (he lobs TNT barrels with fizzing fuses; a red
  circle shows where each one lands - the second one lands where you're
  running to) and CHEST POUND ("OOH OOH!" - showing off when you're far away:
  free hits).
- **GOING BANANAS!** (half health): he shoves everyone near him back, his face
  goes red, his eyes turn red and the torches flare up. Now he chains moves
  together (COMBO: hand slaps, then a roll, then a giant punch), adds CARGO
  THROW (close up: a red wedge fills in front of him - get out of it, or he
  grabs you, "YOINK!", and hurls you across the clearing), and a long wind-up
  on his giant punch shakes the ground with a shockwave you have to jump.
- **The villagers:** they bob along to the fight, cheer and wave their arms
  when he wakes, pounds his chest or goes bananas, and cover their eyes when
  he loses.
- **The end: KONGO VANQUISHED!** He wobbles, falls flat on his back and pops
  into pixels in a burst of bananas. He pays Power only for now: his chest and
  gear are coming with the loot rework (`Items.ByFloor[7]` is empty on purpose,
  so no chest is given).
- **Where things are:** every number in `Config.Bosses[7]`; the floor in
  `Config.Spire.Floors[7]`; his brain and moves in `ServerScriptService/Bosses/Kongo.lua`;
  his body, warnings, the villagers and the torches in `ReplicatedStorage/BossBodies/Kongo.lua`;
  the arena in `ServerScriptService/JungleBuilder.lua`; his portrait and lines in `BossIntro`.
- **Music:** a Sound named `Kongo Song` in SoundService (Oozark's plays until
  you add it), and `Jungle Ambience` for the arena's background loop.
  **Sounds** (all optional; missing ones borrow Oozark's): Kongo Roar, Kongo
  Chest Pound, Kongo Wind Up, Kongo Giant Punch, Kongo Slap, Kongo Roll, Kongo
  Spin, Kongo Headbutt, Barrel Throw, Barrel Break, TNT Boom, Kongo Grab,
  Kongo Pant, Kongo Hoot, Kongo Rage, Kongo Death.
- Previews: `Docs/kongo_preview.png` (the fight) and `Docs/kongo_poses.png`
  (him, pose by pose).

## The Spire's eighth floor: Petalina, the Blooming Terror (The Glasshouse Garden)

A giant cartoon flower (a parody of a certain famous flower boss from a
certain old-cartoon-style run-and-gun game, with her own name and look),
taller than a house, planted in the middle of a huge old glass greenhouse:
a round garden of paved paths - a ring round her, four straight paths and a
ring round the outside - with raised flower beds full of tulips and daisies
between them, potted palms in the corners, baskets of flowers hanging from
the glass roof, butterflies and sunbeams. She sleeps as a closed bud; walk up
and she blooms: "HELLO, SWEETIE~!". She NEVER MOVES from her spot - she fills
the garden with things to dodge and you weave in to hit her stem.
Recommended level 120.

- **Her moves:** SEED SPIT (seeds fly onto red circles near you, and some
  sprout into FLYTRAPS: they gape at anyone who comes close, then snap - one
  punch pops one, and left alone they wilt), PETAL BOOMERANG (petals fly out
  in a loop through where you're standing and come back - a dotted line shows
  each loop; they fly low: jump them, roll, or stay inside the loop), VINE
  WHIP (red lines run out from her, then vines burst up along them racing
  outward - step off the lines, you can't jump them), POLLEN CLOUD (clouds
  drift onto circles near you and sting anyone standing in them), FACE
  STRETCH (a red lane follows you and locks, then her neck stretches and her
  head shoots down it to CHOMP at the end - get out of the lane; then her head
  lies on the floor, dizzy: "HIT HER!" - you can punch her head), ROOT RING
  (right up close: roots burst up in a circle round her - get out, or roll)
  and SUNBATHE (she hums in the sun: free hits).
- **ROUND 2 ("YOU TRAMPLED MY FLOWERS!")** at half health: her petals go dark
  red, her smile turns into a fanged grin, thorns sprout on her stem - and
  thorny brambles grow over every flower bed. From then on standing on a bed
  stings, so fight on the paths. She adds THORN RING (rings of thorns spread
  across the garden - jump them) and SEED RAIN (seeds rain from the glass roof
  onto the paths near you, sprouting more flytraps).
- **The end: she wilts.** Her petals drop off one by one, her head bows to the
  floor, and she pops into pixels; the brambles sink back into the soil. She
  pays Power only for now: her chest and gear are coming with the loot rework
  (`Items.ByFloor[8]` is empty on purpose, so no chest is given).
- **Where things are:** every number in `Config.Bosses[8]`; the floor in
  `Config.Spire.Floors[8]`; her moves in `ServerScriptService/Bosses/Petalina.lua`;
  her body, warnings, flytraps, the brambles and butterflies in
  `ReplicatedStorage/BossBodies/Petalina.lua`; the garden's shape (where the
  paths and beds are, the petals' loop, her head's path) in
  `ReplicatedStorage/GardenPlan.lua`; the arena in
  `ServerScriptService/GreenhouseBuilder.lua`; her portrait and lines in `BossIntro`.
- **Music:** a Sound named `Petalina Song` in SoundService (Oozark's plays until
  you add it), and `Greenhouse Ambience` for the arena's background loop.
  **Sounds** (all optional; missing ones borrow Oozark's): Petalina Hum, Seed
  Spit, Seed Land, Flytrap Sprout, Flytrap Chomp, Petal Throw, Vine Burst,
  Pollen Puff, Petalina Stretch, Petalina Chomp, Root Burst, Petalina Giggle,
  Thorn Ring, Seed Rain, Thorns Spread, Petalina Evil Laugh, Petalina Wilt.
- Previews: `Docs/petalina_preview.png` (the fight) and `Docs/petalina_poses.png`
  (her, pose by pose).

## The look: modern retro

`RetroUI` (StarterPlayerScripts) restyles every screen in the game without
changing the scripts that build them, mixing the pixel games that did it best:

- **Undertale / Deltarune**: dark panels become black boxes with a thick
  white border; the red heart SOUL sits beside the button you point at and
  that button's text turns yellow; new messages type themselves out with a
  voice blip (counters and timers don't).
- **Pokémon**: a thin second line inside each box (the double border), the
  bouncing title with a hard shadow, and the striped battle wipe.
- **Stardew Valley**: chunky pixel icons in place of emoji, a pixel coin, and
  soft pixel corners.
- **Celeste**: buttons squash when pressed, menus pop open, and pixel sparks
  burst on clicks.

It also uses pixel fonts (nothing below `MinText`), a 32-colour palette with
banded gradients, a clean screen (no scanlines) and a title screen on joining,
with the Undertale encounter flash into the game. Every piece is switched in
`Config.Retro` (`On = false` puts the old look back).

The lobby wears the same look (`RetroWorld`, `Config.Retro.World`): its
colours snapped to the menus' palette, realistic textures turned to flat
colour, pixel motes drifting around you, a spinning pixel save star over the
spawn, and Undertale-style lines typed out when you walk up to a shop, the
shrine or the Spire. It also dresses the lobby with detail: stone
courses and chunky stones on the walls, pixel flames and smoke in place of
the old fire effects, grass and flowers, sparks at the shrine, voxel clouds, flocks of birds, and a beacon of
light shooting up out of the blue flame in the Spire's crown (`Docs/spire_beacon.png`). It only changes how things look, only on your
screen: nothing is moved, nothing solid changes, and the people and the
boss arenas are left alone.

Your health is **the heart** (drawn by `ReplicatedStorage/Vitals` for `Hud`,
tuned in `Config.Heart`): red liquid inside a pixel heart, measured by how
much of it is full. A hit makes it slosh, spill drops over the rim and
shake; low on health it beats and blinks red; at zero it cracks in two and
shatters, and forms again when you respawn.

In a fight two more pixel pictures stand either side of it (`Config.Vitals`,
previews `Docs/vitals_preview.png` and `Docs/vitals_drink.png`):

- **The potion** on its left is your healing flasks, with how many are left
  beside it (x3). Drink one (R) and the cork pops off, the bottle tips over
  and pours into the heart in an arc of red drops, and the heart fills as
  they land. None left: empty grey glass, x0, and it shakes if you try.
  Your character drinks too, and everyone sees it: a little red potion comes
  up to the chin, gets tipped back with the head back and a gulp, then is
  put away (`Docs/drink_preview.png`; CombatService puts "Drinking" on the
  character, and every screen animates it on the R6 arm and neck).
- **The lightning bolt** on its right is your stamina: yellow electric liquid
  that drains as you punch, roll and jump and refills from the bottom when
  you stop. Full, it crackles with sparks; try something with too little
  left and it flickers like a dying light with a red outline; while a roll
  makes you untouchable it glows pale blue.

`CombatClient` tells `Vitals` your stamina and flasks (`Vitals.set`) and what
just happened (`Vitals.fire`: a drink, a roll's invincibility, running out).

## Weapons (being built: the test sword)

The game is moving from gear to **weapons** (see the new direction in
`Docs/HANDOFF_PROMPT.md`). The first one is in, to test the feel: the
**Iron Sword** (`Config.Weapons`). In Studio, open the dev console and press
**DEV: Test Sword** (again: back to fists).

- In a fight the punch button swings it instead: a **diagonal slash**, a
  **rising backhand**, and a **leaping overhead finisher** that slams the
  ground (1.5x, narrow, a little more reach). Each swing cuts **every enemy
  in its arc**.
- **F** (gamepad X, or the phone's crossed-swords button) is its ability,
  the **Whirlwind**: spin round cutting everything close to you (10 s
  cooldown, 20 stamina).
- **Mastery** goes up with every enemy you hit. The sword hits harder as it
  grows (1x to 1.5x for a Common), and the Whirlwind gets better at 25
  (wider, harder), 50 (two spins), 75 (a shockwave) and 100 (awakened: three
  golden spins, and the blade turns gold). **DEV: Mastery +25** jumps a
  quarter at a time. (Mastery isn't saved yet.)
- A card bottom-right shows the weapon, its mastery and the Whirlwind's
  cooldown.
- **How it feels** (Elden Ring's weight, Hades' hits, Deepwoken as the Roblox
  reference): you stand relaxed with the blade low and forward, breathing.
  Every swing puts the whole body in: it winds up, holds for a heartbeat,
  SNAPS through the cut as you dash in, rips on through and hangs there a
  moment - and the next swing flows straight out of that follow-through.
  The body moves first and the blade last, like a whip, and your feet stay
  on the floor (lunges sink down into them). Rolling, jumping and drinking
  always take your body back. A glowing smear follows the blade; hits stop
  everything dead for a blink (hit-stop), rip a slash mark across the enemy,
  and heavy ones flash the screen with speed lines. A combo counter climbs
  while you keep hitting.
- Everyone sees it: drawn on every screen by `ReplicatedStorage/WeaponFX`,
  in code on all the R6 joints. Preview: `Docs/sword_preview.png`.
- Sounds (optional, in SoundService): **Sword Swing**, **Sword Hit**,
  **Whirlwind**. Until you add them the swings are silent and hits use the
  punch sounds.

## Gear: boss chests, items and your bag

Every boss drops its **treasure chest** for everyone in the arena when it
dies. Open it from your bag (the **GEAR** button under the left buttons, or
**G**) and it rolls a rarity, then an item of that rarity from that boss's loot:

**Common → Uncommon → Rare → Epic → Legendary → Mythic → Secret** (about 1 in 5000).

- **Rolled stats:** every stat rolls inside its range when it drops, so no two
  are equal. The better the rolls, the more stars (up to 3); all stats at their
  best = **PERFECT**.
- **Slots:** Weapon, Helmet, Chest, Boots. Stats: Damage, Crit Chance (x1.75),
  Health, Defense (both capped at 60%) and Training Power.
- **Sets:** each boss has two sets (Gelatinous and Tyrant's Regalia for
  Oozark, Duneworn and Devourer's on floor 2 (the old worm's - floor 2's loot
  is going to be reworked for Tuber), Spade Knight's and Relicbound
  for Burrowmore, Windwalker and Ki Master's for Kaze, Speedster and
  Turbocharged for Revvington, Beatbound and Demon Geometry for Gridlock)
  with bonuses for 2 and 4 pieces. Kongo (floor 7) and Petalina (floor 8)
  have no chests yet: their loot comes with the rework.
- **Level:** each item needs a level: the highest you've ever reached, so
  prestiging never locks you out. Gear and chests stay through prestige.
- **The bag:** your loadout and total stats on the left; your items, tabs,
  sorting and chests on the right. Hover for the item's card (stats and
  ranges, how they compare to what you wear, set, lore); click to select,
  double-click to wear; LOCK protects an item; SALVAGE (asks twice) gives coins.
- **Legendary and up** are announced to the whole server.

Everything is decided on the server (`PlayerService`): the client only asks.
Items, rarities, odds, sets and stats all live in `ReplicatedStorage.Items`.

