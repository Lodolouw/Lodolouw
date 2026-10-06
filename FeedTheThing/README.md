# Feed the Thing in the Basement — prototype v0.2

> "Feed the thing in your basement, and see what hatches."

This is the test build from the design doc (`Docs/FeedTheThing/DESIGN.md`).
v0.2 is the **simple loop**: one thing to do, one thing to get, then do it again for cooler things.

**buy food 🍅 → feed the Thing 🍖 → it burps out an egg 🥚 → the egg hatches by itself → the Thinglet earns 💰 → better food → repeat**

Every number lives in `Config.lua`.

## What's in

- 8 plots along a street (8-player servers). Each plot has a house, a hatch pit and planter boxes; your nests sit in the planters beside the hatch.
- **Feeding:** a food bar with 6 foods and their prices (Tomato is free, so you can always play) and a big FEED button (tap or hold). The food flies down the hatch, CHOMP, then the Thing **burps an egg onto a nest**. Above the bar you see the chance of each rarity with the food you picked.
- **Eggs:** 3 nests to start (up to 6). Each egg shows a countdown (6 s for a Tomato egg, up to 35 s for a Moon Melon), wobbles more and more, then hatches by itself. Your very first egg hatches in 3 s.
- **What hatches:** any food can hatch any rarity, but better food has much better odds. Each food leans towards its own Thinglet. Luck (a bigger Thing, the Lucky Thing upgrade) raises the rare chances, and the rarest the most. Frozen, Glowing and Gold mutations; Snow and Full Moon weather make Frozen and Glowing 3× as likely. And a secret Thinglet.
- **Reveals:** something special (a new kind, a mutation, Epic or better) gets the big reveal; everything else pops up small on the right so you can keep feeding.
- **The yard:** no choices to make. When it's full, a better Thinglet takes the weakest one's place (the weaker one is sold); a weaker one is sold straight away.
- **The Thing:** 5 sizes that it grows into by eating; every size adds luck. You only ever see eyes, arms, teeth, horns and cracks. It blinks, looks at you, chomps and burps.
- **Thinglets:** all 8, in Normal, Frozen, Glowing and Gold looks. They grow over real time (also offline), earn coins per second, wander, and look at nearby players. Tap one to see its card and sell it.
- **Upgrades** (yard space, nests, luck, income, quick eggs; buy x1/x10/MAX) and the **Index** (32 looks; the ones you haven't found say which food gives them most often).
- **The coin truck:** every 2 minutes it comes out of the west tunnel, stops at someone's house and throws them a package of coins.
- Offline income (up to 2 hours), a friend bonus, server announcements for Legendary and Gold hatches, the size-up banner.
- Saving with DataStores.

## Not in yet (on purpose)

Rebirth, the Style (Robux cosmetics) shop, leaderboards, likes, trading, events and music. See the roadmap in the design doc.

## Setting it up in Studio (with Rojo)

You need this branch's files on your PC first (fetch the branch in GitHub Desktop, or download the ZIP).

1. **Start Rojo:** double-click **`FeedTheThing/serve.bat`**. The first time, it downloads Rojo 7.4.4 (the same version as your Studio plugin) into `FeedTheThing/.tools`. Leave the black window open while you work.
2. **In Studio:** open a new **Baseplate** place. In the Rojo panel, press **Connect** (it's already set to `localhost` and port `34872`), then **Accept**. All the scripts appear in the right places:

```
ReplicatedStorage        Config, Rules, Looks, UI, Assets, SoundSheet   (ModuleScripts)
ServerScriptService      Main (Script); DataService, WorldBuilder, GameService (ModuleScripts)
StarterPlayerScripts     World, Feed, Hud                  (LocalScripts)
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

### Sounds and Blender models: uploading them (upload.bat)

All the sound effects are original. `Sounds/make_sounds.py` makes them, and also packs all of them into one file, `Sounds/SoundSheet.ogg`, so they cost a single audio upload instead of 18 (Roblox allows 10 audio uploads a month without ID verification). The Blender models are the `.fbx` files in `Blender/Export`. The stud pattern on the menus and buttons is `GUI/studs.png`.

**Double-click `upload.bat`** (next to `serve.bat`):
1. **Copy your API key (Ctrl+C) and press Enter.** It reads the key straight from the clipboard, so nothing shows on screen.
2. **Type your Roblox user id.** It's the number in your profile's web address.
3. **It uploads whatever is new or changed and writes the ids into the game's files.** Rojo puts them in Studio, and the game loads the sounds, map and props by itself, so there's nothing to import.
4. **Commit and push in GitHub Desktop** so the ids are kept.

The first time, it downloads a small Python (about 11 MB, only used by the uploader) into `.tools`. It also offers to remember the key. If you say yes, the key is saved on this computer only (in your AppData folder, never in the project, so it can't end up on GitHub or OneDrive); after that it's just a double-click. `upload.bat forget` forgets it.

The API key (create.roblox.com/dashboard/credentials) needs the **Assets** API with **Read** and **Write**.

Good to know:
- **Run it whenever I've changed sounds or models.** Anything already uploaded is skipped.
- **The game must be owned by the same account as the uploads.** Otherwise Roblox won't let it load the map and props.
- **New uploads go through Roblox's moderation.** They can take a few minutes to show up.
- **A changed model keeps its id** (it gets a new version). A changed sound sheet gets a new id, written in for you.
- **A Sound you place in SoundService with the same name (`Chomp`, `Coin`...) overrides the uploaded one.** So does putting a sound's id in `Config.Sounds`.
- **No key?** Import by hand instead:
  - Map: **Import 3D**, name it `Map`, put it in **ServerStorage**.
  - Props: **Import 3D**, name them `Props`, put them in **ReplicatedStorage**.
  - Sounds: import `SoundSheet.ogg` and paste its id into `ReplicatedStorage/SoundSheet.lua`.

## Test it like a new player

Use a phone-sized emulator (Test → Device → a phone, landscape) and check each step:

| When | What should happen |
|---|---|
| 0:00 | You spawn facing your hatch; glowing eyes look at you; the food bar shows at the bottom with "Tap to feed it!" |
| 0:05 | Tap FEED: the Tomato flies in, CHOMP, then BURP and an egg lands on a nest with a countdown |
| 0:08 | Your first egg hatches (3 s): the big reveal, then a Blorp hops out of the nest into your yard |
| ~0:30 | You can afford a Chili; the odds above the bar change when you pick it |
| ~1–2 min | YOUR THING GREW! Size 2, +10% luck |
| ~2 min | Eyeberry (1K); the Upgrades button gets a red dot: "Get more nests!" |

Then check the rest: once the yard is full, better Thinglets take the weakest one's spot and the rest are sold (the small pop on the right says so); tapping a Thinglet opens its card; the coin truck comes every 2 minutes; the weather comes every 12 minutes (Snow / Full Moon).

**Quick-test tip:** to see later content fast, give yourself coins or grow your Thing from the Command Bar while playing. This only works in Studio:

```lua
game.Players:GetPlayers()[1]:SetAttribute("GiveCoins", 1e6)
game.Players:GetPlayers()[1]:SetAttribute("GiveGrowth", 25000) -- feeds the Thing (size 4 at 25K)
game.Players:GetPlayers()[1]:SetAttribute("HatchNow", true) -- every egg on your nests hatches now
```

## Tuning

- All numbers live in `ReplicatedStorage/Config.lua`.
- To check an economy change before trying it in game, edit the numbers in `Docs/FeedTheThing/economy_sim.py` and run `python3 Docs/FeedTheThing/economy_sim.py`. It prints when an always-active player (one who spends everything, and one who saves up) hits each milestone.
- Tests you can run outside Studio (needs the `luau` command line): `python3 FeedTheThing/Tests/run_tests.py`. It runs the rules tests, then the real server scripts on a pretend Roblox (a player joins, feeds, hatches, upgrades, leaves and comes back).

## How it's built

- **The server decides everything** (`GameService`): it checks every feed (price, a free nest, close to your hatch), rolls what each egg will hatch into the moment it's laid (the food's odds, your luck, the weather), hatches eggs when their countdown ends, and runs the yard, upgrades, coins, the coin truck and the weather. What's inside an egg stays on the server until it hatches.
- **Clients only draw** (`World`, `Feed`, `Hud`). The Thing, the nests, the eggs and the Thinglets are drawn locally from plot attributes in `ReplicatedStorage.Plots`. That keeps the server light and the animations smooth on phones.
- `Rules.lua` holds the rules as plain functions shared by the server and the HUD, so what the HUD shows (the odds, upgrade prices) always matches what the server does.
- Weather comes from the clock, so every server agrees.

## Known limits of the prototype

- There is no session lock on saves: joining a second server within seconds of leaving could load slightly old data. This is fine for the test; add session locking (or ProfileStore) before launch.
- Saves from v0.1 aren't loaded (the DataStore name changed to `FeedTheThing_v2`), so everyone starts fresh with the new loop.
