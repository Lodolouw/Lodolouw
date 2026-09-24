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
- **Training Yard** — 6 practice-dummy pads (Straw → Iron → Frost → Ember →
  Void → Celestial), each with its own look, particle effects, and a Power
  multiplier sign; click/tap to train, or toggle Auto Train
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
  table (Ambush, Breach, Coil, Devour, TailLash, Tremor, Undermine). Gloomgut
  still runs on `brain` and `Attacks`, untouched.
- **Arena:** `DunesBuilder` - the fighting floor is Terrain sand (so it can be
  torn up), the ring of standing stones round the seal (the worm's lair), five
  platforms that shatter in phase two (tag `DunePlatform`).
- **Drawing:** `BossClient` - the "MIREWORM: the hunt" section. Its body is
  solid wherever it's out of the sand (`pushOutOfWorm`). Craters, trenches,
  fissures and the phase-two bowl are carved into the Terrain on each player's
  own screen and slide back after `Scars.Last` seconds; hits are always decided
  by the server.
- **The sandstorm:** `ArenaAmbience` - the wall of sand rolling in, the
  thickened air, the dust over your view, the wind.
- **Optional sounds** (SoundService): Worm Rise, Worm Charge, Worm Erupt,
  Worm Slam, Worm Sweep, Worm Wail, Worm Devour, Worm Crack, Worm Death, a
  looping Worm Rumble and a looping Sandstorm. Missing ones borrow Gloomgut's
  (or are simply silent).
