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

## Setting it up in Studio (with Rojo)

You need this branch's files on your PC first (fetch the branch in GitHub Desktop, or download the ZIP).

1. **Start Rojo:** double-click **`FeedTheThing/serve.bat`**. The first time, it downloads Rojo 7.4.4 (the same version as your Studio plugin) into `FeedTheThing/.tools`. Leave the black window open while you work.
2. **In Studio:** open a new **Baseplate** place. In the Rojo panel, press **Connect** (it's already set to `localhost` and port `34872`), then **Accept**. All 11 scripts appear in the right places:

```
ReplicatedStorage        Config, Rules, Looks, UI          (ModuleScripts)
ServerScriptService      Main (Script); DataService, WorldBuilder, GameService (ModuleScripts)
StarterPlayerScripts     World, Toss, Hud                  (LocalScripts)
```

3. **Game Settings:**
   - Places → Max Players: **8** (one plot per player).
   - To test saving: publish the place, then turn on Security → **Enable Studio Access to API Services**. Without it the game still runs, it just starts fresh each time, and the Output says so once.
4. **Import the map (made in Blender):** choose Import 3D, then `FeedTheThing/Blender/Export/FeedTheThing_Map.fbx`, then Import. Rename the new model to **`Map`** and drag it into **ServerStorage**. Its size and position don't matter, because the game lines it up. Details are in `FeedTheThing/Blender/README.md`.
5. Press **Play**. The Output should say `Feed the Thing in the Basement is running.`
   - The Baseplate and SpawnLocation are removed automatically while playing, and your saved place keeps them.
   - If something is misnamed, `Main` names the exact script that broke instead of failing silently.

While Rojo is connected, any change to a file in `FeedTheThing/` shows up in Studio straight away. Save the place in Studio (File → Save) as usual. Rojo only manages the scripts, not the rest of your place.

**Not using Rojo?** Create the scripts above by hand with exactly those names and paste each file in (`*.server.lua` = Script, `*.client.lua` = LocalScript, other `.lua` = ModuleScript).

**Already use Rokit?** Run `rokit install` in `FeedTheThing/`, then `rojo serve`.

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
