# Feed the Thing in the Basement — prototype v0.1

> "Grow food, feed the thing in your basement, and see what hatches."

This is the **5-day test build** from the design doc (`Docs/FeedTheThing/DESIGN.md`).
It contains the whole core loop, so you can run the ad test on it:

**grow 🌱 → toss 🍖 → hatch 🥚 → Thinglets grow and earn 💰 → better seeds → repeat**

Like your last game, everything is built from scripts: there are no imported meshes or models, and every number lives in `Config.lua`.

## What's in

- 8 plots in a ring around a plaza (8-player servers). Each plot has a house, a hatch pit and 10 garden beds.
- **Garden:** 6 crops. Plants are permanent and hold 3 ripe fruit. Walk past a plant and its fruit jumps into your basket. Weather makes fruit Frozen or Glowing, and 1% of fruit comes out Gold.
- **The toss:** a throw pad with a timing ring. A PERFECT toss gets an arm catch. Every toss lands. Cravings pay ×3, and combos go ×2, ×3, ×5.
- **The Thing:** 5 sizes that it grows into by eating. You only ever see eyes, arms, teeth, horns and cracks. It blinks, looks at you, chomps and burps.
- **Hatching:** the diet rules (most food wins, 5 different foods → Mishmash, all-PERFECT Moon Melons → Lil' Thing). Mutation odds are shown live, and the hatch reveal plays on screen.
- **Thinglets:** all 8, in Normal, Frozen, Glowing and Gold looks. They grow over real time (also offline), earn coins per second, wander, and look at nearby players. Each has a name tag. Tap one to see its card and sell it.
- **Shop** (restocks every 5 min, odds shown), **Upgrades** (plots, yard space), **Dex** (32 looks with hints).
- Offline income (up to 1 hour), a Daily Craving bonus egg, a friend bonus, server announcements, the size-up banner, and the first-minute hints.
- Saving with DataStores.

## Not in yet (on purpose)

Rebirth, the Style (Robux cosmetics) shop, NPC egg raids, likes, trading and events. See the roadmap in the design doc.

## Setting it up in Studio

1. Make a new **Baseplate** place and **delete the Baseplate** part (the game makes its own ground).
2. Create these scripts with exactly these names and parents, and paste each file in:

```
ReplicatedStorage/
  Config.lua               → ModuleScript "Config"
  Rules.lua                → ModuleScript "Rules"
  Looks.lua                → ModuleScript "Looks"
  UI.lua                   → ModuleScript "UI"

ServerScriptService/
  Main.server.lua          → Script "Main"
  DataService.lua          → ModuleScript "DataService"
  WorldBuilder.lua         → ModuleScript "WorldBuilder"
  GameService.lua          → ModuleScript "GameService"

StarterPlayer/StarterPlayerScripts/
  World.client.lua         → LocalScript "World"
  Toss.client.lua          → LocalScript "Toss"
  Hud.client.lua           → LocalScript "Hud"
```

   If you use **Rojo**, `default.project.json` does all of this for you.

3. **Game Settings:**
   - Places → Max Players: **8** (one plot per player).
   - To test saving in Studio: publish the place, then turn on Security → **Enable Studio Access to API Services**. Without it the game still runs, it just starts fresh each time, and the Output says so once.
4. Press **Play**. The Output should say `Feed the Thing in the Basement is running.`

If something is misnamed, `Main` names the exact script and line that broke instead of failing silently.

### Sounds (optional)

Sounds are played by name. Add a Sound to **SoundService** with any of these names and it plays (the Creator Store has free ones):

`Chomp`, `Perfect`, `Coin`, `Pop`, `Throw`, `Combo`, `Crack`, `Hatch`, `HatchRare`, `SizeUp`, `Buy`, `Click`, `Burp`, `Error`, `Announce`

Chomp, Perfect, Coin, Pop and Hatch matter most for the feel.

## Test it like a new player

Use a phone-sized emulator (Test → Device → a phone, landscape) and check each step:

| When | What should happen |
|---|---|
| 0:00 | You spawn facing your hatch; glowing eyes look at you; tomatoes hop into your basket |
| 0:05 | Throw pad appears with "Tap to toss it in!"; the ring pulses gold |
| ~0:20 | Third toss → BURP, egg pops out → reveal → a Blorp walks into your yard |
| ~0:45 | "Buy a Chili seed!" points at Shop; buying plants it straight away |
| ~2 min | YOUR THING GREW! Size 2; the belly now holds 5 |

Then check the rest: you're asked to choose when the yard is full, tapping a Thinglet opens its card, the weather comes every 12 min (Snow / Full Moon), and the Shop timer counts down.

**Quick-test tip:** to see later content fast, give yourself coins or grow your Thing from the Command Bar while playing. This only works in Studio:

```lua
game.Players:GetPlayers()[1]:SetAttribute("GiveCoins", 1e6)
game.Players:GetPlayers()[1]:SetAttribute("GiveGrowth", 50000) -- feeds the Thing (size 4 at 50K)
```

## Tuning

- All numbers live in `ReplicatedStorage/Config.lua`.
- To check an economy change before trying it in game, edit the numbers in `Docs/FeedTheThing/economy_sim.py` and run `python3 Docs/FeedTheThing/economy_sim.py`. It prints when an always-active player hits each milestone.
- The game rules have tests you can run outside Studio (needs the `luau` command line): `python3 FeedTheThing/Tests/run_tests.py`.

## How it's built

- **The server decides everything** (`GameService`): it checks every toss and decides PERFECT from the moment you let go, on the same clock the ring uses. It also handles the hatch rules, odds, coins, shop stock and weather.
- **Clients only draw** (`World`, `Toss`, `Hud`). Plants, the Thing and Thinglets are drawn locally from plot attributes in `ReplicatedStorage.Plots`. That keeps the server light and the animations smooth on phones.
- `Rules.lua` holds the rules as plain functions shared by the server and the HUD, so what the HUD shows (the hatch prediction, the odds) always matches what the server does.
- Weather and the shop's stock come from the clock and your UserId, so every server agrees and nothing can be re-rolled by rejoining.

## Known limits of the prototype

- There is no session lock on saves: joining a second server within seconds of leaving could load slightly old data. This is fine for the test; add session locking (or ProfileStore) before launch.
- A PERFECT toss is judged from the release time the client sends, so exploiters could fake it. That's acceptable while nothing can be traded; check it again before trading ships.
