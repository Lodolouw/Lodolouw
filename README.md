# Boss Grow — Starter Lobby

A "+1 to grow" style Roblox lobby, built entirely from scripts (no imported
models/assets). This is **lobby only** — no arena, no bosses yet, as requested.
There's an inert "BOSS ARENA - Coming soon" gate so you can see where the
arena will plug in later.

## What's included

- **Procedurally-built lobby** (toy-brick island, paths, tall mossy castle
  walls, trees, lamps)
- **Sell Shop** — sell loot materials for coins
- (The Upgrade Shop, the talismans and prestige are gone: your level alone
  makes you stronger, and weapons come from the Arcade. The Upgrade Shop's
  mushroom house stays as the toad's house.)
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
  Colosseum, the bosses, the Arcade, the shop). Both
  the server and the client require it, so they always agree.
- **LobbyBuilder.lua** runs once on the server at startup and builds every
  Part/Model/GUI-anchor in Workspace. Nothing here is a real asset — it's all
  `Instance.new("Part")` calls. Decorative pieces are tagged `"FX"` so the
  client can animate them without the server doing any per-frame work.
- **PlayerService.lua** owns all player data (Power, Coins, Arcade Tokens,
  weapons, quests, rewards), validates every action server-side (never trust the
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
  actions require standing near the station (on by default).
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
a chest with your first Arcade Token in it (a spin at the Arcade). Then the mist
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
  huff (HMPH!). The banner says THE BRUTE VANQUISHED. Everyone gets Power (and
  Arcade Tokens the first time).
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
  gets Power (and Arcade Tokens the first time).
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
  Everyone gets Power (and Arcade Tokens the first time).
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

A cocky orange muscle car with white racing stripes and big green eyes (his
own name, look, number - 57 - and catchphrase: "Ka-VROOM!") waits on the start line of a
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
  boss bar counts from GO!). Everyone gets Power (and Arcade Tokens the first
  time).
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
  you are. Everyone gets Power (and Arcade Tokens the first time).
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

A huge silverback gorilla - charcoal fur, a pale grey face and a gold chain
with a big banana medallion (his own name and look) naps in the middle of a flat
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
  into pixels in a burst of bananas. He pays Power (and Arcade Tokens the
  first time).
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
  pays Power (and Arcade Tokens the first time).
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

## The Spire's ninth floor: Scribble, the 4th-Dimensional Doodle (The Canvas)

A stick figure drawn in blue pen who knows he's inside a video game (his own
name and look - no famous stick figure's), so he fights with the game
itself. He's a DRAWING: flat as paper, his lines wobbling like hand-drawn
animation, and he always turns to face your camera, like a paper cut-out.
His arena is a giant sheet of graph paper inside a paint program's window
("SCRIBBLE.EXE" on the title bar, giant tools down one side, colour swatches
down the other), floating over a computer desktop with giant folders, the
recycle bin and the taskbar. The way out is a giant red [X] close button.
He sleeps as a faint pencil sketch; walk up and he inks himself in. Three
rounds, 3-4 minutes: the longest fight yet. Recommended level 135.

- **ROUND 1, "DOODLE" (the drawing tools):** PENCIL DASH (a dotted line draws
  itself through you, then he rockets along it - get off the line; he skids
  at the end: "HIT HIM!"), ERASER SWEEP (a pink strip across the paper, then
  a giant eraser rubs it out - get off it), PAINT BUCKET (the grid square
  you're in floods with paint - leave it), COPY-PASTE ("CTRL+C... CTRL+V!":
  two ink clones chase you - a punch or two pops one) and UNDO (a giant Z key
  pops up: punch it in time and he's stunned; miss it and "CTRL+Z!" - he
  undoes your last few hits).
- **ROUND 2, "BREAKING THE 4TH WALL"** at 55% health: he tears himself out of
  the paper (red marker now) and a crack runs across your screen. THE CURSOR
  (a giant mouse pointer hunts you, freezes and clicks - roll), BOSS BAR WHIP
  (he rips his health bar off your screen and swings it round low - jump
  it), ERROR POP-UPS (ERROR / 404 / LAG windows drop out of the sky and stand
  as walls, then shatter) and LAG SPIKE (ghosts of him in a line to you, then
  he skips from ghost to ghost - get off them).
- **ROUND 3, "DELETE"** at 20%: he glitches into rainbow colours and keeps
  trying to delete the floor. A giant "Delete FLOOR 9? YES / NO" box pops up
  at the edge of the paper with a countdown while the paper is erased from
  the edges in (a grey checkerboard - standing on it stings). Punch NO and he
  crashes ("SCRIBBLE.EXE IS NOT RESPONDING": the big damage window, and the
  paper comes back); miss it and the delete hits everyone hard (it never
  kills - you're left on 1) and the paper stays smaller.
- **The end:** he's crumpled into a paper ball and thrown into the recycle
  bin. He pays Power (and Arcade Tokens the first time).
- **Where things are:** every number in `Config.Bosses[9]`; the floor in
  `Config.Spire.Floors[9]`; his moves and his three-round brain in
  `ServerScriptService/Bosses/Scribble.lua`; his body, warnings, clones, the
  Z key, the DELETE box and the erased edge in
  `ReplicatedStorage/BossBodies/Scribble.lua`; the paper's shape (its size,
  the Paint Bucket's squares, where the DELETE box stands, how far it's been
  erased) in `ReplicatedStorage/CanvasPlan.lua`; the arena in
  `ServerScriptService/CanvasBuilder.lua`; his portrait and lines (with a
  round-3 line) in `BossIntro`.
- **Music:** a Sound named `Scribble Song` in SoundService (Oozark's plays until
  you add it), and `Desktop Hum` for the arena's background loop. **Sounds**
  (all optional; missing ones borrow Oozark's): Scribble Laugh, Pencil
  Scratch, Ink Dash, Ink Skid, Eraser Rub, Paint Splash, Copy Paste, Clone
  Swipe, Key Pop, Undo Rewind, Scribble Dizzy, Mouse Click, Bar Whip, Error
  Pop, Lag Glitch, Delete Warning, Scribble Crash, Scribble Rip, Scribble
  Glitch, Paper Crumple.
- Previews: `Docs/scribble_preview.png` (the fight) and `Docs/scribble_poses.png`
  (him, pose by pose).

## The Spire's tenth floor: King Gavelgrunt, Lord of the Spire (The Throne Summit)

THE FINAL BOSS. The king at the top of the Spire - every boss below works for
him. A colossal WALRUS KING nine times your height (his own name and look):
a great layered belly with a gold belt, huge shoulders under spiked gold
pauldrons, a deep crimson cape with an ermine band, a tall spiked crown,
ivory tusks (one snapped off short) and a giant stitched scar across his left
eye - which still glows. He swings an iron war-gavel with gold bands whose
runes light up as he winds up. His arena is a round stone courtyard above the
clouds in a thunderstorm that never ends (rain, lightning, thunder): a purple
carpet up to his golden throne, four stone pillars to hide behind, three low
podiums round the edge and torches. It gets darker in round 2 and turns to a
red eclipse in round 3. Three rounds, 4-5 minutes: the longest fight in the
game. Recommended level 150.

- **HIS ENTRANCE:** he sleeps on his throne. Walk up the carpet and lightning
  cracks, his eyes light up ("WHO DARES..."), he stands up on the throne,
  raises the gavel into the storm - lightning strikes it - and leaps down in
  front of you with a slam that shakes the courtyard. The VS splash slams in
  as he lands, then "HAR HAR HAR!" and "KNEEL!". Your camera watches it from
  the foot of the throne. When everyone's gone he leaps back up onto his
  throne and goes back to sleep.

- **ROUND 1, "THE KING IS AMUSED":** ROYAL SMASH (a red circle, then the gavel
  slams and a shockwave ring rolls out - jump or roll it; the gavel sticks in
  the floor: "STUCK! HIT HIM!"), GAVEL SWEEP (a wide swing in front of him -
  get behind him), BELLY BOUNCE (he hops up and belly-flops on you - his
  shadow grows under you), ROYAL DECREE ("GUARDS!": little guards drop in),
  TOE STOMP (after a stomp the tip of his flipper glows: "PUNCH HIS TOE!"
  and he hops round on one foot) and TAX COLLECTOR ("TAXES ARE DUE!": gold coins rain down -
  grab them to heal; every coin you leave he sucks up and his next move hits
  harder).
- **ROUND 2, "THE MECHANICAL GAVEL"** at 65%: steam, and the gavel becomes a
  piston hammer. TRIPLE SLAM (three slams walking at you, each with its own
  ring), HAMMER TORNADO ("SPIN TO WIN!": he spins after you, then he's dizzy),
  BIG GULP (he breathes in, pulling you in; caught, you're swallowed and spat
  out across the courtyard, then a burp shoves everyone back), ROCKET HAMMER
  (the hammer head fires out on a chain and yanks back), THE ROYAL FEAST
  ("DINNER TIME!": he sits and eats a giant roast, healing - smash the
  platter or punch his belly till he chokes) and THE ROYAL ROLL ("BOWLING!":
  he rolls into a ball and bowls across the courtyard, breaking pillars).
- **ROUND 3, "NO ONE TAKES MY CROWN"** at 30%: his crown flies off and he goes
  berserk (faster; his eyes, scar and runes burn red), and the pillars that
  are left crumble. EARTHQUAKE
  (he leaps sky-high; some flagstones light up gold - "STAND ON THE GOLD!"),
  CROWN GRAB ("MY CROWN!!": he runs for his crown - punch him in time and he
  trips: "TRIP HIM!"), "GUILTY!" (one player gets a spotlight; a giant gavel
  falls on them - run to a podium to take far less, and friends can stand
  with you to share it) and THRONE TOSS (he throws his throne: "MY THRONE!
  CATCH!"). At 10%, THE FINAL GAVEL: one gigantic slam and a shockwave over
  everything - jump or roll it at the last moment - then he's worn out and
  wide open.
- **The end:** he falls flat on his back: "SPIRE CONQUERED!". He pays Power
  (and Arcade Tokens the first time). The Nightmare, Eclipse and Doom versions
  of the Spire come next.
- **Where things are:** every number in `Config.Bosses[10]`; the floor in
  `Config.Spire.Floors[10]`; his moves and his three-round brain in
  `ServerScriptService/Bosses/Gavelgrunt.lua`; his body, his entrance,
  warnings, guards, coins, the feast, the crown, the spotlight, the crumbling
  pillars and the storm (rain, lightning, the sky) in
  `ReplicatedStorage/BossBodies/Gavelgrunt.lua`; the courtyard's shape (the
  pillars, podiums, flagstones, the throne and where he sits on it) in
  `ReplicatedStorage/ThronePlan.lua`;
  the arena in `ServerScriptService/ThroneBuilder.lua`; his portrait and lines
  (with a round-3 line) in `BossIntro`; his design in
  `Docs/bosses/hammer_king_design.md`.
- **Music:** a Sound named `Gavelgrunt Song` in SoundService (Oozark's plays
  until you add it), and `Summit Wind` for the arena's background loop (a
  howling storm wind). **Thunder Crack** is the lightning's thunder (silent
  until you add it). **Sounds** (all optional; missing ones borrow Oozark's): Gavelgrunt Laugh,
  Gavel Smash, Gavel Swing, Belly Bounce, Giant Land, Royal Trumpet, Guard
  Jab, Giant Stomp, Toe Ouch, Coin Rain, Coin Pickup, Coin Vacuum, Piston
  Hiss, Hammer Spin, Big Inhale, Gulp, Spit Out, Royal Burp, Rocket Hammer,
  Chain Rattle, Royal Feast, Munching, Choke Cough, Royal Roll, Earthquake,
  Crown Clang, Giant Trip, Gavel Guilty, Giant Gavel, Throne Crash, Final
  Gavel, Pillar Crumble, Gavel Transform, King Roar, King Fall.
- Previews: `Docs/gavelgrunt_preview.png` (the entrance and the fight) and
  `Docs/gavelgrunt_poses.png` (him, pose by pose).

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

## Bosses talking, and your lock-on on a boss

- **Speech bubbles:** a boss's lines (its hello, taunts, gloating, its new
  round, its last words) come up in a speech bubble by its head - white,
  inked round the edge, its name on a tag in its colour, the words typed out
  with a blip - instead of the black box that covered the top of your screen.
  The bubble hangs over its head with its tail pointing down at it; with no
  room up there (a tall boss's head up by the boss bar) it sits beside the
  head, pointing sideways; with the head off your screen it waits at the
  edge nearest it. It never covers the boss bar, and last words stay where
  they were said (the boss may be melting or flying off). `BossIntro` (its
  `LINES` are the words).
- **Your lock-on on the boss's real body:** a boss is drawn on your screen far
  bigger than the small invisible Root the server moves (Scribble stands 16
  studs tall on a 4-stud Root), and the lock-on used to aim at that Root: the
  brackets sat at your own feet and the camera cut the boss's head off. Now
  `BossClient` measures what's drawn every frame and says where its middle
  and head are (the boss model's `AimAt`, `HeadAt`, `AimSize` and `AimTime`,
  on your screen only). `CombatClient` puts the brackets on its middle,
  frames all of it (looking a little higher at a tall one), and when it leaps
  aims at it as if it still stood under itself, so the camera keeps the
  ground it'll land on in view. A body file can say for itself (`Body.aim`).
- Preview: `Docs/talk_preview.png` (Scribble before and after, then every boss).

## Hit reactions (every hit that lands)

Enemies react when a hit lands on them - fists or sword, yours or another
player's. Preview: `Docs/hit_reactions.png`.

- **A white flash:** the enemy goes pure white for a blink.
- **The Colosseum's dummies** tip away from the blow and wobble back upright
  like punching bags, and get knocked back: a little by a normal hit, sent
  flying by a finisher (the last swing of a string, or a crit) - even the
  killing blow, which turns them to ash as they land. Heavier kinds budge
  less, the Straw King only flinches, and nothing is ever knocked past the wall.
- **Bosses** squash and blanch when hit, and each blow jolts them back a touch.
- The numbers are in `Config.Combat.HitReact` (how long the flash lasts, how
  far dummies tip and get pushed, how high a finisher throws them, how far a
  boss jolts).

## Weapons (being built: the test sword)

The game is moving from gear to **weapons** (see the new direction in
`Docs/HANDOFF_PROMPT.md`). The first one is in, to test the feel: the
**Iron Sword** (`Config.Weapons`). In Studio, open the dev console and press
**DEV: Test Sword** (again: back to fists). **DEV: Next Sword** goes through
all four 3D swords (Iron Sword, Ember Cleaver, Tidefang, Voidstar - for now
the other three are Iron Swords in everything but their looks), then fists.

- In a fight the punch button swings it instead: a **flat forehand** (right
  to left at chest height), a **rising backhand**, and a **leaping spin
  finisher** (1.5x, narrow, a little more reach). Each swing cuts **every
  enemy in its arc**. No down slashes.
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
- **The sword and the swings:** the sword is the **Iron Warden**, a 3D model
  made in Blender from a pixel sprite (`Tools/Weapons`) and imported into
  **ReplicatedStorage** with Studio's 3D Importer (it must be there, named
  `IronWarden`: the IronSword's `Model` in `Config.Weapons`). The idle and
  the three swings are **uploaded animations** made in Blender for R6
  (`Tools/Animations`, key poses in `Docs/animations/sword_key_poses.png`); their ids are in
  `Config.Weapons.Types.Sword.Animations`. Swings follow through like a
  tennis swing. Your screen plays them and Roblox shows them to everyone.
  Walking with the sword and the Whirlwind are still made in code
  (`ReplicatedStorage/WeaponFX`). Missing model: the old blocky sword. An
  animation that can't load: that swing is drawn in code instead.
- The animations only play in a game owned by whoever published them (you,
  or your group if you publish them to the group).
- Sounds (optional, in SoundService): **Sword Swing**, **Sword Hit**,
  **Whirlwind**. Until you add them the swings are silent and hits use the
  punch sounds.

## Gear, the Upgrade Shop and talismans (removed)

Armour gear (helmets, chestplates, boots, gauntlets and their sets) and the
bosses' treasure chests are gone: **weapons from the Arcade are the loot now**,
and your level makes you stronger (`Config.LevelBonus`). What that changed:

- **Bosses** pay Power (and Arcade Tokens the first time you beat each one). A
  Boss Rush ticket doubles the Power.
- **The intro:** Oozlet's chest now holds your **first Arcade Token**
  ("+1 ARCADE TOKEN" rises out of it) - a spin at the Arcade straight away.
- **The Quest Board:** the "open treasure chests" quest is now **"Clear a
  Colosseum run"** (or 3 runs), so every set still has three kinds.
- **Critical hits** only come from a weapon's Crit effect now (x1.75,
  `Config.CritMultiplier`); defence only from your level (at most
  `Config.MaxDefense`, 60%).
- **Old saves:** a player who still has old gear or unopened chests gets
  **Arcade Tokens for them, once**, when they next join (a message tells them
  how many): every unopened chest (and every old prestige) and every Common to
  Rare piece = 1 token, Epic = 2, Legendary = 5, Mythic = 10, Secret = 25 - up
  to **100** in all. The numbers are `OLD_GEAR` in
  `ServerScriptService/PlayerService.lua`. The next save leaves the old gear
  out, so it can't be swapped twice.
- The G key, the gear window (`Inventory`) and `ReplicatedStorage/Items` are
  gone.
- **The Upgrade Shop and the talismans are gone too.** Walk speed outside
  fights is `Config.BaseWalkSpeed` for everyone, Power from training and max
  health come from your level. The mushroom house on the cove stays (the
  toad's house) without its sign, arrow or walk-up. An old save gets back the
  coins it spent on upgrades and talismans, once, up to **50,000** (`OLD_SHOP`
  in `PlayerService.lua`), with a message. (DEV: Max Upgrades is gone.)

## The new GUI (the lobby screen, rewards, the Index, the shop, the Bag and Settings)

The whole interface from `Previews/gui_windows_sketch.html`, built in steps.
`Config.NewHud = true` turns it on (false brings the old HUD's buttons back).

**Step 1 - the lobby screen** (`StarterPlayerScripts/LobbyHud`, preview
`Docs/new_gui_lobby.png`):
- **Left:** four big picture buttons - SHOP, BAG, ARCADE, INDEX - with red
  badges for what's waiting (tokens to spin, weapons to add to the Index, the
  starter pack after your first boss). (No STATS or GEAR buttons.)
- **Bottom left:** your coins and tokens (the token's **+** opens the shop).
- **Top middle: the NEXT GOAL** - pick a quest, spin your tokens, hand in a
  finished quest, train in the Colosseum until you're close to the next
  floor's level, or climb the Spire - with how far it is. A **glowing trail**
  runs along the ground from your feet towards it and a **beam of light**
  stands on it. There's no FIGHT button: you walk there and choose yourself.
- **Right:** the **free gift's clock** (tap it when it says READY!),
  **REWARDS** and **SETTINGS**, then **today's quest** (fold it with _). They
  sit a little lower than the top corner so Roblox's player list can't
  cover them.
- **By the level bar:** "2X XP 12:30", "2X COINS", "LUCK +50%" while a boost
  or pass is on. **Bottom right:** the corner bonuses (more XP for time in
  this server and for friends in it with you - hover for what they are).
- It hides in fights, in the intro and while a menu is open. The old left
  buttons, stats strip, hint line and the WEAPONS / ROLL squares are
  hidden (and stay hidden through fights and the intro); the level bar, the
  heart and the dev tools stay. At level 256 the level bar says MAX LEVEL.

**Step 2 - Rewards, the Index and the community chest** (preview
`Docs/new_gui_rewards.png`):
- **REWARDS** (`StarterPlayerScripts/RewardsMenu`, green): **Login** - the
  seven-day calendar (claimed days, today's CLAIM, day 7's big one; miss a
  day and it starts again); **Gift** - the free gift's clock, today's count
  and what the next gifts are; **Codes** - type one, REDEEM; **Updates** -
  what's new and its gift. The newest update opens by itself the first time
  a returning player joins after it comes out.
- **THE INDEX** (`StarterPlayerScripts/IndexMenu`, purple): **Weapons** -
  every weapon pack by pack; ones you haven't found are dark "???" shapes
  (with their rarity), a new find has CLAIM; **Bosses** - the ten floors,
  beaten or not; **Collector** - the collector bar and its rewards.
- **THE COMMUNITY CHEST** in the lobby (on the grass west of the plaza, by
  the path; built by `RewardService.BuildChest`, at `Config.Rewards.ChestAt`):
  walk up and its window opens - join the community, claim once. **Put your
  community's number in `Config.Rewards.GroupId`** (until then it says the
  community isn't linked yet).

**Step 3 - the shop** (`StarterPlayerScripts/ShopMenu`, gold; preview
`Docs/new_gui_shop.png`):
- **Featured** (the Arcade, the Starter Pack once per player, VIP, quick
  tickets), **Tickets** (Revive x3, Spin x3, Boss Rush x3, 30 min 2x XP),
  **Tokens** (the packs - with how much more each bigger one *really* gives,
  worked out from the prices - and every free way to earn tokens), **Daily**
  (five looks for coins, new every day), **Passes** (VIP, 2x XP, 2x Coins,
  +50/100/200% luck, Instant x10), **Looks** (wear your titles and auras;
  where to get the rest).
- **GIFT** buys a product for someone else in the server.
- **Where Roblox doesn't allow paid random items** (PolicyService), the token
  packs, Spin x3 and the luck passes don't show - the free ways do.
- **To switch the Robux things on:** make each Developer Product and Game
  Pass in the Creator Dashboard (your experience > Monetization) at the
  prices in `Config.Shop`, and paste their ids into `Config.Shop` (ProductId /
  PassId). Until then each says **SOON** and can't be bought. Every purchase
  is handed out exactly once (ShopService saves it before telling Roblox).
- **Tickets in fights:** a **Revive** stands you back up at half health when a
  hit would finish you in a boss fight (one per fight); a **Boss Rush** makes
  a win against a boss you've beaten before pay double Power. Both
  are used by themselves; Settings can switch each off.
- **Luck** (a luck pass or the Luck boost) makes Epic and rarer more likely at
  the Arcade - and the Arcade's odds show the lucky numbers, the same the
  server rolls with. **Instant x10** skips the ten-spin show straight to the
  results.

**Step 4 - the Bag, the fight screen and Settings** (preview
`Docs/new_gui_bag_settings.png`):
- **THE BAG** (`StarterPlayerScripts/BagMenu`, teal; the BAG button or **B**):
  the weapon in your hand, big - rarity, type, mastery and how far to the next
  level, its **one ability on [F]** with what it does now and what the next
  mastery tier adds, IN HAND / FISTS - and every weapon you own, rarest first,
  with a rarity filter; tap one to look at it and EQUIP it. The **Looks** tab
  wears titles and auras.
- **THE FIGHT SCREEN** stays as it is (heart in the middle, flask left, bolt
  right, the gold level bar); the weapon card gets a title bar in the weapon's
  rarity colour with its name, and the ability reads "[F] WHIRLWIND".
- **SETTINGS** (`StarterPlayerScripts/SettingsMenu`): music, sound effects,
  shadows, low graphics, hide others' effects (their abilities and auras
  aren't drawn on your screen), camera shake, and whether revive / Boss Rush
  tickets are used by themselves. Saved with your data.

**No more stat points:** your level alone makes you stronger. Every level
adds a little damage, max health, defence and Power from training
(`Config.LevelBonus` - tune the numbers there); your max health goes up the
moment you level. The STATS button, its panel and the plaza shrine's walk-up
are gone (the Shrine of Growth stays as decoration). Armour gear is gone too
(see "Gear, the Upgrade Shop and talismans (removed)" above).

**The Arcade's menu** (`StarterPlayerScripts/ArcadeClient`, preview
`Docs/arcade_menu.png`): a bright arcade cabinet - ARCADE in lights with
chasing bulbs, every machine as a big button, the picked machine's six prizes
as big glowing tiles with their real odds, the JACKPOT METER, and two huge
SPIN buttons ("PRESS ME!" bounces on it before your first spin).

**Pictures load fast:** every uploaded picture is a decal, which Roblox can
only show as a slow thumbnail - so `ServerScriptService/PictureLoader` looks up
the real image inside each one when the game starts, and
`ReplicatedStorage/Pictures` swaps them in and starts downloading them all as
you join.

**The menus** (`ReplicatedStorage/Menus`): see-through - the world blurs and
dims behind, and the menu floats over it: a big title top left, tabs down the
left side, your money top right and a red X. One at a time; Esc closes it and
so does going into a fight; the server's messages show on top. Each menu's
script defines it with `Menus.define`; older windows (the Arcade, Weapons)
open through `Menus.external`.

**The pieces** (`ReplicatedStorage/WindowKit`): picture buttons, cards with
hard shadows, tabs, badges, chips, bars, the coin and token, and the menus'
**pixel icons** (`Tools/Icons/make_ui_icons.py`, 31 of them). Until the icons
are uploaded (`Tools/Upload/upload_assets.bat`, as `UI_<name>`) a simple
stand-in picture shows instead.

**On the server** (`RewardService`, `ShopService`, tested by
`test_rewards_shop.luau`): the login streak, the free gift, codes, update
gifts, the Index and collector bar, the community chest, looks (titles and
auras everyone sees), settings, the corner bonuses, timed boosts; the Robux
shop (every purchase handed out exactly once, gifts, passes, Daily Items, no
paid random items where Roblox doesn't allow them) and the Arcade's luck.
