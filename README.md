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
- **Training Yard** — 12 practice-dummy pads in two rows, entered through a
  stone archway with a pixel sign. The first row (Straw → Iron → Frost →
  Ember → Void → Celestial) is on the ground; the second (Ooze → Dune →
  Crystal → Storm → Dragon → Cosmic, levels 55–105) stands a step up on a
  raised stone terrace behind it, reached by a grand staircase. Each dummy
  has its own look, effects and a Power multiplier sign; click/tap to train,
  or toggle Auto Train. (Rows, spacing and the terrace's height are in
  `Config.Yard`; the castle's south wall sits further out to hold it all.)
- **Tall mossy castle walls** — a much taller stone perimeter wall than a
  typical starter lobby, with crenellated merlons on top, moss patches
  climbing the inner face, and ivy strands hanging down. All Parts, no
  imported meshes.
- **Juicy hit feedback** — hitting a dummy plays a layered thump+ting sound
  (randomized pitch so it never sounds robotic), a squash/stretch/tilt
  "got punched" animation, and a small camera kick. A cosmetic combo counter
  (never affects Power) makes every 10th hit in a row bigger and louder.
  Buying, selling, crafting and prestiging each got their own short chime
  instead of one generic ping.
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

- **Config.lua** is the single source of truth for every number (zone
  multipliers/costs, upgrade costs, talisman recipes, prestige formulas). Both
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

## The Spire's second floor: Mireworm (the Sunken Dunes)

Mireworm doesn't reuse any of Gloomgut's attacks. It sleeps coiled round the
seal in the middle of the arena until someone comes near; then it rears up,
roars, and goes under the sand to hunt by sound: running on sand is loud,
stone is quiet, standing still is silent. Its cycle is hunt (under the sand,
untouchable) -> strike -> exposed (hit it now) -> dive. While it's under the
sand the ground bucks round its ridge (the rumble, which hurts), and the
moment the fight starts a sandstorm rolls in.

- **Where the numbers are:** `Config.Bosses[2]` - `Hunt`, `Rumble`,
  `Whirlpool` (phase two), `Scars` (how long torn-up sand lasts) and `Attacks`.
  The sandstorm is `Config.Spire.Floors[2].ambience.Storm`, and the fight's
  music is `Music = "SANDWORMSONG"`.
- **Server:** `BossService` - `wormBrain`, `stepRumble` and the `WormAttacks`
  table (Ambush, Breach, Coil, Devour, TailLash, Tremor, Undermine). The tail
  lash is a whip (`lashAngle` - the client draws the same curve). Gloomgut
  still runs on `brain` and `Attacks`, untouched.
- **Arena:** `DunesBuilder` - the fighting floor is Terrain sand (so it can be
  torn up), the ring of standing stones round the seal (the worm's lair), five
  platforms that shatter in phase two (tag `DunePlatform`).
- **Drawing:** `BossClient` - the "MIREWORM: the hunt" section. Its body is
  solid wherever it's out of the sand, except to a roll (`pushOutOfWorm`), and
  the whole fight is warmed up the moment you arrive (`rehearse`). Between
  moves its body flows into the next shape head first; it dives in an arc into
  a new hole ahead (`diveArc`); the tail lash is its own tail (`lashPath`).
  Craters, trenches,
  fissures and the phase-two bowl are carved into the Terrain on each player's
  own screen and slide back after `Scars.Last` seconds; hits are always decided
  by the server.
- **The sandstorm:** `ArenaAmbience` - the wall of sand rolling in, the
  thickened air, the dust over your view, the wind.
- **Optional sounds** (SoundService): Worm Rise, Worm Charge, Worm Erupt,
  Worm Slam, Worm Sweep, Worm Wail, Worm Devour, Worm Crack, Worm Death, a
  looping Worm Rumble and a looping Sandstorm. Missing ones borrow Gloomgut's
  (or are simply silent).

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
shrine, the yard or the Spire. It also dresses the lobby with detail: stone
courses and chunky stones on the walls, pixel flames and smoke in place of
the old fire effects, grass and flowers, pylons and sparks round the training
pads, sparks at the shrine, voxel clouds, flocks of birds, and a beacon of
light from the Spire's peak. It only changes how things look, only on your
screen: nothing is moved, nothing solid changes, and the people, the dummies
and the boss arenas are left alone.

Your health is **the heart** (in `Hud`, tuned in `Config.Heart`): red liquid
inside a pixel heart, measured by how much of it is full. A hit makes it
slosh, spill drops over the rim and shake; a flask pours it back in; low on
health it beats and blinks red; at zero it cracks in two and shatters, and
forms again when you respawn.

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
  Oozark, Duneworn and Devourer's for Nahrzul) with bonuses for 2 and 4 pieces.
- **Level:** each item needs a level: the highest you've ever reached, so
  prestiging never locks you out. Gear and chests stay through prestige.
- **The bag:** your loadout and total stats on the left; your items, tabs,
  sorting and chests on the right. Hover for the item's card (stats and
  ranges, how they compare to what you wear, set, lore); click to select,
  double-click to wear; LOCK protects an item; SALVAGE (asks twice) gives coins.
- **Legendary and up** are announced to the whole server.

Everything is decided on the server (`PlayerService`): the client only asks.
Items, rarities, odds, sets and stats all live in `ReplicatedStorage.Items`.

