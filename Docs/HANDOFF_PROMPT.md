# Handoff prompt — paste everything below the line into a new Claude session

---

You are continuing work on my Roblox game. Read this whole message before doing anything.

## The game

- It's a Roblox game in the style of **"+1 Defeat the boss to Grow"**: you punch things to gain Power (XP), level up, buy upgrades, and fight bosses.
- **The theme is "modern retro"**: Undertale/Deltarune mixed with Pokémon, Stardew Valley, Celeste and a Terraria feel, with a souls-like twist. The inventory is styled after Minecraft Dungeons. There are Undertale touches: dummies and NPCs mock you in typed-out speech boxes with a voice blip, and there's a Smash Bros Ultimate-style intro splash when you approach a boss. The GUI should feel "extremely good and satisfying".
- **The look is 8-bit / pixel-art**, using the **Endesga-32 palette**: flat materials (SmoothPlastic/Neon), chunky blocky shapes, and the Press Start 2P font. Keep everything new in that style.
- **Everything is built from scripts.** There are no imported meshes or models (apart from optional NPC models loaded by ID with a blocky fallback).

## The core vision

**The pitch:** a Roblox grow-and-fight game in the style of **"+1 Defeat the boss to Grow"**, crossed with **souls-like boss fights** and **Blox Fruits-style farming quests**, all in a chunky, colourful **8-bit look**.

**The core loop:**

1. **Farm.** In the **Colosseum** you fight waves of dummies at your level to gain **Power (XP)** and **coins**, and complete looping quests ("Defeat 10 Dummies") and daily quests. This is where players spend most of their time, so it has to be *fun*: varied enemies, telegraphed moves to dodge, and rewards that feel good.
2. **Grow.**
   - Levels come from Power. Total Power for a level = 17.9 × (level − 1)³, up to level 256.
   - Every level gives **stat points** to spend: Strength (damage), Vitality (health), Defense, and Training (+Power gain).
   - **Gear** drops from boss chests: rarities, stats and sets (see `Items.lua`, Inventory GUI).
   - **Upgrades** (backpack, gloves, sell value, Swift Boots) and **talismans** (3 slots, crafted at the Armory/blacksmith) give more ways to get stronger.
   - Levels are **Blox Fruits-style**: max 256, 3 stat points per level.
   - **Prestige was removed completely** (on purpose). Old prestige was converted into Oozark chests once. `Config.MaxPrestige = 0`, and there's no prestige sign. Don't bring it back.
3. **Fight bosses** in **the Spire**. Each floor is a boss with a recommended level:
   - Floor 1: **Oozark, the Gelatinous Tyrant**, the slime, "Gloomgut" in older code. Level 15, in the slime pit.
   - Floor 2: **Nahrzul, Devourer of the Dunes**, the sand worm "Mireworm". Level 30, in the Sunken Dunes.
   - Floor 3: sealed (level 45).

   Boss fights are souls-like: dodge rolls with invincibility frames, stamina, **flasks** to heal (R), lock-on (Tab, Q/E to switch), and clear red telegraphs before attacks. Bosses drop **chests** with gear.
4. **Repeat.** Beating a boss unlocks the next level target, which means more farming with tougher Colosseum enemies and better gear.

**Where it's going:**
- **20+ bosses.** With 20 bosses, a player's full playthrough would be roughly **30–60 hours**. Right now a player finishes both bosses in about **1–3 hours**. A game like this wants 10+ hours of progression.
- **Every boss should be EPIC, but efficient to build:**
  - Share one framework: warnings, health bar, 8-bit block style, attack timing, sounds and music by name.
  - Each new boss is mostly new attacks plus a new body.
  - Mix a few huge showpieces (like the worm) with simpler bosses.
- **The planned boss-code split (not done yet):**
  - Server: `BossService` keeps the shared parts, and each boss gets its own ModuleScript in a `ServerScriptService/Bosses/` folder (`Bosses/Oozark`, `Bosses/Nahrzul`).
  - Client: `BossClient` keeps the shared visuals, and each boss gets its own ModuleScript in a `ReplicatedStorage/BossBodies/` folder with its body and animations.
  - Include a "how to add a boss" template.
  - Players see no difference. Test that both bosses behave identically before and after.
- **The MMO direction** (Hypixel Skyblock / Wynncraft / Blox Fruits) is what keeps the game alive long-term:
  - Every boss drops a **treasure chest**, a "gamble crate", with gear in rarities: Common → Uncommon → Rare → Epic → Legendary → Mythic → Secret. This is **done**.
  - Gear goes in your inventory and drives a player **market**.
  - Gear and pets are permanent.
  - I **declined** unidentified items and sockets.
  - Still to build: **pets**, **fishing**, **trading**, then the **Auction House**. See "The world and its places" above.
- **Other ideas I liked, for later:**
  - A **first-time tutorial**: an arrow to the Colosseum, "Beat 5 dummies", "Spend your stat points", "Open your chest". **I decided the tutorial is built LAST, after everything else.** The King is NOT part of it (he's the early-game boss test); at most one step like "Survive to wave 5!".
  - **Pets** from eggs: the Pet Sanctuary tower is already built and empty.
  - **Gear upgrading** from +1 to +10.
  - **Cosmetics** such as auras and titles.
  - A **settings menu** (music and SFX volume, camera shake).
  - A **level-up celebration**.
- **Order of work:** make the Colosseum great first (see the plan at the bottom). **Bosses come last.**

## The world and its places

### What exists now

The whole lobby is built by LobbyBuilder. Its pieces are, in order: ground and walls, Sell Shop, Upgrade Shop, Armory, Colosseum gate, Colosseum, Quest Board, the Spire, castle gate, castle, island and sea, the slime arena, and decorations.

- **The island:** the castle sits in the middle of an organic, "organised chaos" island in the sea (sea level y = −20). It has:
  - beaches;
  - animated 8-bit waves: foam lines lapping the shore, and "~" crests drifting in, moving in small jumps 12 times a second;
  - voxel trees, palm trees and bushes.
- **The castle:**
  - The **Grand Keep** is in the north. The passage to **the Spire** goes through it.
  - The **Spire** stands on its own islet, reached by a bridge.
  - There's a south **gatehouse** with cozy cream-stone stairs and a rest landing.
  - It has walls, towers, and a moat.
- **The plaza:** a fountain plaza with lamp posts, cobble paths and auto curbs. The Prestige Shrine is gone and the plaza is open paving.
- **Shops:**
  - **Sell Shop** (south-east).
  - **Upgrade Shop**: the **mushroom house** on the **cove**, with an **8-bit frog** shopkeeper. It sits at the end of a natural dirt path with log steps, and there's a **pier**.
  - **Armory / blacksmith**, and the forge in the east **Gear Hall** with a waterwheel.
- **Pet Sanctuary tower:** built, but **empty** (pets aren't made yet).
- **The farm:** a Stardew-style farm with a cottage, crop rows, a windmill with 8-bit stepped spinning sails, a coop, a well and a scarecrow. The entrance is open, with no gate.
- **Quest Board:** daily quests, pick 1 of 3.
- **The mini sand-castle Colosseum:** this is where the old training field / training yard was. **The old training yard dummies are gone.** Power now comes from the Colosseum (plus bosses and quests).
- **Spire floors:**
  - Floor 1: "Oozark's Hollow", the slime pit.
  - Floor 2: the **Sunken Dunes**, the worm's desert (DunesBuilder).
  - Floor 3: sealed (level 45).
- **Music:** there are 3 lobby songs, a slime boss song, and "SANDWORMSONG" for the worm, played by name from SoundService.

### Places we discussed for later (not built yet)

- **Fishing** (a big one, the "chill" second loop for players who don't want to fight):
  - **Where:** the **cove / pier by the mushroom house** was chosen to be repurposed as the fishing spot. Earlier plans also mentioned fishing docks by a lake or waterfall outside the walls.
  - **How it plays:** a timing minigame, not just waiting. The bobber dips, you hit the button in the sweet spot, and a pixel meter shows it.
  - **What you catch:**
    - fish to sell;
    - fishing-only crafting materials;
    - rare treasure (small chests);
    - occasionally a **sea creature** mini-fight.
  - **Progression:** fishing levels, better rods, rare fish, and a **fishing log / collection** to complete.
  - **Feel:** calm music and a fishing hut NPC.
- **Pets** (in the Pet Sanctuary tower), Hypixel Skyblock style:
  - Cute pixel critters that follow you, like a baby slime or a mini sandworm.
  - Each gives a perk: more Power, more coins, fishing luck, or boss damage.
  - They drop from boss chests and fishing, and hatch from eggs bought with coins.
  - They level up, and rarer pets have stronger perks.
- **The market:**
  - First **trading**: a two-player trade window where both confirm and the server swaps the items.
  - Later an **Auction House / Bazaar** in the Grand Keep's great hall, working across servers.
  - It must be exploit-proof, with everything done on the server. The saves are already session-locked, which was a prerequisite.
- **Gear Hall:** an armoury display, and a place where you open chests in public to show off rare pulls.
- **Hall of Champions** in the Grand Keep: live statues of the top players (by Power and fastest boss kill) and a trophy wall of the bosses you've beaten.
- **PvP duels** in an arena courtyard, reusing the combat system and the VS splash.
- **Ramparts parkour** up the walls to the highest tower, with a badge at the top.
- **The Vault** under the keep: a daily chest, and a secret room that opens after beating a certain boss.
- **A codes board** at the gatehouse for promo codes.

**Robux rule we agreed:** never sell gear directly, because that ruins the market. Cosmetics, extra slots and similar are fine.

## The repository

- **Repo:** `https://github.com/Lodolouw/Lodolouw`
- **Branch:** `claude/funny-mccarthy-s0do05` (it carries on from the older `claude/nice-cori-7kss8b`). Keep working on this branch and push to it.
- **Do NOT open pull requests.**
- **Every commit message ends with these two lines:**
  ```
  Co-Authored-By: Claude <noreply@anthropic.com>
  Claude-Session: <your session link>
  ```
  Don't put model names or version numbers in commits.

### File layout (the folder = where it goes in Roblox Studio)

**ReplicatedStorage/**
- `Config.lua`: ALL the tuning numbers (levels, colosseum, bosses, combat, spire, retro look).
- `Items.lua`: gear rarities, stats, sets and loot tables.

**ServerScriptService/**
- `Main.server.lua`: a Script. It builds the world and then starts each service inside `pcall`.
- `LobbyBuilder.lua`: builds the entire lobby, the mini colosseum, the real Colosseum arena and the dummy templates.
  **WARNING:** it is right at Roblox's **200 top-level locals limit (about 193 used)**. Put new code inside the existing `Extras` function block, or inside `do ... end` blocks. Never add new top-level `local`s.
- `PlayerService.lua`: DataStore with session locking, the movement anti-cheat guard, request rate limits, daily quests, stats and upgrades.
- `CombatService.lua`: server-authoritative combat: punches, the owner filter, damage, the shield block, and Disintegrate.
- `ColosseumService.lua`: the Colosseum wave arena (details below).
- `BossService.lua`, `SpireService.lua`, `DunesBuilder.lua`: the bosses and the Spire floors (Gloomgut the slime, Mireworm the sand worm).

**StarterPlayerScripts/** (LocalScripts)
- `CombatClient.client.lua`: combat input, lock-on, roll, camera, damage numbers and health-bar tidying.
  It has about **192 top-level locals** — same rule: use `do ... end` blocks.
- `LobbyActivities.client.lua`: the Colosseum HUD (quest tab, wave banners, confetti), the pipe shrink animation, the quest menu, and the "never sunk in the floor" guard.
- `BossClient.client.lua`: boss visuals (8-bit PIXEL mode).
- `Hud`, `RetroUI`, `RetroWorld`, `Inventory`, `BossIntro`, `ArenaAmbience`, `LobbyFX`, `SpireClient`, `RollDebug`.

**Docs/**: preview images.

**Tools/HeadlessTests/**: NOT for Studio. A pretend Roblox (`rbxmock.luau`) that runs the real scripts headlessly: a full Colosseum run with the King fight, the King's screen side, and the dummy builder. Run `./run_all.sh` (needs the Luau tools). See its README.

### How I install your changes (important — I'm not a programmer)

**Rojo is set up** (`default.project.json`, `StartRojo.bat`, guide in `Docs/ROJO_SETUP.md`): once I've set it up, I pull your push in GitHub Desktop and Studio updates itself. It maps ReplicatedStorage/, ServerScriptService/ and StarterPlayerScripts/ (`.server.lua` = Script, `.client.lua` = LocalScript, `.lua` = ModuleScript) with `$ignoreUnknownInstances` so nothing else in my place is touched. A new script file in those folders appears in Studio automatically. Until I say Rojo works for me, still send the changed files as below.


- I copy each changed file into Studio by hand: open the script, Ctrl+A, delete, paste.
- So after every change:
  1. **commit and push**, and
  2. **send me every changed file** (as file attachments), with a short list of which scripts to replace.
- Every file's **line 1 is `--[[`**. The **last line is `return <ModuleName>`** for ModuleScripts, or `end)` for most LocalScripts.
- Never truncate a file.

### How I like to work

- Explain things simply and briefly, in plain English. I'm young and learning.
- Keep the plain-English comments in the code; they're how I understand it.
- Show me **preview renders/pictures** of anything visual before or after you build it.
- Just go ahead and do things when the direction is clear. Ask only if it's really my decision.
- **Always warm up assets** so nothing stalls or plays silent the first time: preload new sounds, music, animations and textures with `ContentProvider:PreloadAsync` (like BossClient's `warmSounds`, CombatClient's `warmAnimations` and LobbyActivities' Colosseum warm-up).
- Sounds: you can't upload audio. The code plays Sounds **by name from SoundService** (for example "UI Blip", "Punch 1".."Punch 4", "Roll", "Hurt 8-Bit"). I add sounds from the Toolbox and rename them. When you add sound hooks, tell me the exact names.
- **Bosses come last**, after the Colosseum polish.

## Security rules (always keep these)

Assume players can run any LocalScript code, fire any RemoteEvent with any arguments, and teleport or speed-hack. So:

- **The server is authoritative for everything:** damage, rewards, coins, XP, quests, movement.
- **Every remote goes through** `allowRequest` (a budget of 20 tokens refilling at 10/s) and `saneArg`: no NaN/inf, strings ≤ 100, tables of depth < 2 and ≤ 20 keys.
- **The movement guard** (PlayerService) puts players back after:
  - a teleport of more than 60 studs per 0.1s tick;
  - speed above walkSpeed × 1.35 + 12, averaged over 3s;
  - flying for 2.5s.
  When the SERVER moves a player on purpose, it sets the player attributes `MoveTo` (Vector3) and `MoveUntil` (server time) first, so the guard skips them.
- **DataStore:** UpdateAsync with a session lock (`_lockJob`/`_lockTime`, expires after 240s), and `cleanCopy` strips NaN. It kicks the player if the save is still locked after about 50s.
- **Colosseum dummies are per-player:**
  - Each dummy has an `Owner` = UserId attribute.
  - CombatService only lets the owner hit it (`mine()`).
  - Other players' screens hide it (`hideIfNotMine` in LobbyActivities hides any child of `workspace.ColosseumEnemies` whose Owner isn't you).

## The Colosseum (what's built so far)

A wave arena for farming XP and coins.

### Getting in and out
- In the lobby there's a small sand-castle colosseum.
- Press **E** at its little door and you shrink bit by bit, Mario-pipe style, and appear inside the real arena far away (centre `(-2600, 0, 0)`, radius 82, built at 2.6× scale by the same `sandColosseum` function).
- The client does the teleport animation (`PipeIn`/`PipeOut` events). The server sets `MoveTo`/`MoveUntil` first.
- Press **E** at the exit gate to leave (it heals you).
- If you die in there, you respawn in the lobby.

### Quest
- **"Defeat 10 Dummies"** loops forever, shown in a quest tab on the right, like Blox Fruits.
- Daily quests also exist: pick 1 of 3 at the quest board, with a stamp animation on completion.

### Waves
- A wave clears → crowd confetti → the next wave comes after `WaveBreak`.

### Enemy types
Defined in `Config.Colosseum.Types`. Templates are built by LobbyBuilder into ServerStorage as `ColosseumDummy` (Straw) and `ColosseumDummy_<Kind>`.

| Enemy | Unlocks | Health | Reward | Behaviour |
|---|---|---|---|---|
| Straw Dummy | Lv 1 | 1× | 1× | Hops toward you. Slam with a red ring |
| Wooden Brute | Lv 10 | 1.6× | 1.5× | Red strip telegraph, then **charges** (`Config.Colosseum.Charge`). Winded after |
| Hay Slinger | Lv 20 | 0.8× | 1.4× | Keeps 16–32 studs away, **throws hay bales** at a red square (`Throw`) |
| Iron Knight | Lv 35 | 2× | 2.2× | Slow. **Shield blocks from the front** (`ShieldArc` 110°, plus the `FrontDir` attribute): CombatService sends "Blocked" and fires `OnBlock`, which shoves the player back. Go round the back |
| Cursed Dummy | Lv 50 | 1.3× | 2.5× | **Blinks** behind you (purple puff), then slams (`Blink`) |

- Waves are a weighted random mix of the unlocked kinds, with `max` per wave.
- Dummies are always the player's level.

### Technical details (ColosseumService)
- **Model setup:** all parts are anchored and non-colliding. PrimaryPart = Torso. The model is built facing backwards, and its `Foot` attribute = the height of the body above the feet.
- **Moving dummies:** `feet(model)` and `place(model, cf)` are the ONLY way to move a dummy.
- **Sand height:** `sandAt(pos)` raycasts the sand height (the centre ring is 0.52 studs higher). `inArena` clamps to the arena and uses `sandAt`.
- **Warnings:** telegraph markers, puffs and bales go in a per-dummy `DummyFX` folder (with the Owner attribute), NOT inside the model. Moving a model moves everything inside it.
- **Knockback:** `safePush` stops dummy knockback from throwing the player into the stands.
- **Health bars:** `BarHeight` is set per dummy from its bounding box. CombatClient shows the full name and numbers only for the focused target (locked on, or nearest the screen centre); others show a small bar.
- **Spacing:** push-apart spacing scales with dummy size.

### The boss wave: the Giant Straw King ✅
Every 5th wave (`Config.Colosseum.King.Every`) the King drops in alone. All his numbers are in `Config.Colosseum.King`.
- **The look:** LobbyBuilder builds `ColosseumDummy_King` (scale 2.3): a giant straw dummy with a gold crown, a red cape with a white fur collar, a big cream beard and moustache, a gold medal and a golden pitchfork. Preview: `Docs/straw_king.png`.
- **His entrance:** a huge shadow, he crashes down away from you (a harmless show shockwave), then stands roaring for `IntroTime` (Invulnerable, State "Waking") while BossIntro plays the VS splash (first meeting each visit) and he talks. Then State "Fighting".
- **His moves** (`kingBrain` in ColosseumService, each with a red warning): big hops; a royal slam (red ring, `SlamRange`); the **ground pound** (red ring where you stand, he leaps and lands in it, then after `WaveDelay` a **shockwave** of red/gold blocks rolls out at `WaveSpeed`: it's a real wall: touch it with your feet on the sand from either side and it hurts, again after `ReHit` 1s; being higher than 60% of its height above your standing height clears it, and rolling works too; someone squashed by the landing is spared for 1s); the **whirlwind** (red disc, then he spins TOWARDS you like Clash Royale's Valkyrie at `Chase` 11 / `RageChase` 14 studs/s for 2.4s, hitting again every `ReHit` 0.9s you stay in it); **summon** (3 "Straw Minion" straw dummies, max 4, at 75%/40% health and on a cooldown). Preview: `Docs/straw_king_moves.png`.
- **Rage** at 50%: Phase 2, red glowing eyes, faster, 2 shockwaves per pound, a faster whirlwind.
- **Oozark's slime wave** (BossService `stepWaves`) follows the same wall rule now: it can hit you again if you touch it again after 1s.
- **Reward:** 15× a straw dummy's Power and coins; counts as 1 quest kill. His minions crumble when he dies (no reward). A longer break (`WaveBreak` 4.5s) follows.
- **Code:** `spawnDummy(s, kind, spot, level, opts)` now makes EVERY dummy (waves, the King, minions). The King has attributes Kind="King", NoBar, Boss (never out of sight for lock-on), State, Phase, Move. His hit shape (`CombatService.SetTargetShape`) makes him punchable from the sand up to his head; it's cleared when he dies or the session ends.
- **Screen:** LobbyActivities has the King's boss bar (`ColosseumBossBar`, 8-bit, RetroSkip), the BOSS WAVE / THE KING IS FURIOUS! / THE STRAW KING FALLS! banners, camera shakes through CombatClient's `CombatCameraKick` BindableEvent, his sounds and music (the "Music" SoundGroup is faded down while his plays, in its own "KingMusic" group). BossIntro has his portrait and lines. Preview: `Docs/straw_king_screen.png`.
- **Sounds (by name in SoundService, first one found is used):** Horn "Boss Wave Horn"; Land "Straw King Land" or "Boss Slam"; Roar "Straw King Roar" or "Boss Wake"; Spin "Straw King Spin" or "Boss Wave"; Summon "Straw King Summon" or "Boss Wail"; Death "Straw King Death" or "Boss Death"; Victory "Victory Is Ours (a) Sting"; Music "Straw King Song" or "Slime boss song".
- In the headless tests a fight takes about 50-65 seconds for a player at his level with no gear.

### Runs (a mini dungeon) and kill streaks ✅
- **Runs:** a run is 5 waves (`Config.Colosseum.King.Every`, `EndsRun = true`); wave 5 is the King. When he falls the run is **CLEARED**: the server times it (from wave 1 arriving), `PlayerService.RecordColosseumClear` saves `data.Colosseum = { clears, best, bonusDay }` (best = fastest clear in seconds), and the **first clear of each day** pays `ClearBonus` (0.5 of the level gap in Power, 150 + 15/level coins; `Config.colosseumRewards().clearPower/clearCoins`). Then nothing happens until the player chooses on the COLOSSEUM CLEARED screen (LobbyActivities `ClearScreen`, preview `Docs/colosseum_cleared.png`): **RUN AGAIN** (healed, flasks refilled via `CombatService.RefillFlasks`, wave 1 two seconds later) or **LEAVE** (the normal pipe-out, allowed from anywhere only while the run is cleared). The buttons go through PlayerService's `Action` RemoteFunction: ColosseumService registers "ColosseumAgain" and "ColosseumLeave" with `PlayerService.AddAction`. Dying mid-run still sends you to the lobby.
- **Kill streaks** (`Config.Colosseum.Streak`): kills in a row without losing health (ColosseumService watches the Humanoid's HealthChanged). Every 5 kills adds +10% to each kill's pay, up to +50%. It carries on between runs and ends when you're hurt or leave. The screen shows "x12 STREAK +20%" beside the wave box ("WAVE 3/5"), a banner every 5, and "STREAK LOST" if a streak of 5+ breaks.
- "Best wave" was dropped (runs always end at 5): the best clear time replaces it.
- **Spawning:** a new dummy (and the King) is parked out of sight 200 studs up (`PARKED`) until its turn to drop in, and lands at `e.land`. It must never stand on the sand first and then vanish (that was a bug).
- **The pipe sound:** LobbyActivities plays `Config.Colosseum.PipeSound` ("Pipe" / "Mario Pipe" / "Warp Pipe") going in and popping out.
- **Colosseum sounds** (`Config.Colosseum.Sounds`, names + volumes): the server sends `"Sfx", key, position` for dummy moments (Land, Slam, Poof, Charge, Throw, HayLand, Clang, Blink); the client adds WaveHorn, Cheer, Reward and Quest. While inside, `Config.Colosseum.Music` ("Colosseum Song") plays and the looping crowd (`CrowdSound`) murmurs; the King's song takes over in his fight; the lobby's "Music" SoundGroup is ducked under both. All are warmed up and listed in the Output sound report. ("coin2" and "dummy punch" in SoundService are deliberately unused.)

### Recent fixes (please verify in play)
- Players sinking into the floor after reset/death. LobbyActivities `keepFeetUp` watches the lowest foot against the floor, raises the ControllerManager's `GroundController.GroundOffset` (or R15 HipHeight) by the gap, and lifts the body. **The character uses Roblox's ControllerManager**, not classic Humanoid movement.
- The gap behind the stands is filled (`StandFill` parts).

## Everything we've built and decided so far (history)

### Lobby and world
- **The lobby:** a castle plaza with a fountain, lamp posts, paths, a farm, a Sell Shop, and an Upgrade Shop with an 8-bit frog.
- **The mushroom house:** I asked to keep the OLD mushroom house, just sharpened up. A pixel-circle version flickered.
- **The training yard** (12 practice dummies on two tiers) was **replaced** by the mini Colosseum entrance. The Colosseum is now where you farm.
- **The quest board:** pick 1 of 3 daily quests. The others rip off like a bandage, and completing one shows a stamp saying "COMPLETED".
- **Everything is 8-bit.** Flat materials, no flickering.
- **Flicker fixes:**
  - no two faces in the same spot (alternate thicknesses);
  - no overlapping transparent parts;
  - no rope on the bunting ("NO ROPE"). Note: a thin bunting rope does currently exist in the colosseum builder, so check with me if it bothers me.

### The Colosseum
- **The entrance:** a mini sand-castle colosseum in the lobby, placed to use the space well, where the two roads connect. You enter through a Mario-pipe shrink animation.
- **The real arena:** built to match the little model.
  - The spawn/entry animation must not play again inside, since you're already shrunk.
  - The arena floor has extra grip.
  - The crowd in the stands is decorative, and you can be pushed against the stands.
  - There's no invisible barrier stopping dummies from reaching you at the edge.
- **Farming is solo:** your dummies are only yours. Other players can't hit them or see them.
- **Rewards:** XP and coins per kill, plus the quest reward, exactly like Blox Fruits. There's an active quest tab on the right.
- **HP:** you're healed when you leave. HP resets outside the arena.
- **Effects:** a spawn-in animation for dummies (a shadow grows, then they drop in), and confetti from the stands when you clear a wave.
- **Lock-on:**
  - Tab / middle-click / R3 to lock.
  - Q/E to switch left or right on screen.
  - The lock jumps to the nearest enemy when your target dies, and releases when out of range or out of sight.
  - 8-bit corner brackets and Q/E tags show the targets.
  - Shift is the dodge roll in fights, so Shift Lock is off there.
- **Health bars declutter:** only the focused enemy shows its name and numbers.

### Bosses (both made 8-bit)
- **Slime boss:** flicker fixed, and its spawn fixed.
- **Worm boss:** reworked to be more fun and less laggy.
  - A sandstorm rolls in when the fight starts.
  - It has a tail lash, breach, coil and tremor attacks.
  - Its armour cracks off.
  - The music is "SANDWORMSONG".
  - Players can't clip through it.
- **Heart health display:** a liquid heart that spills.

### Security audit
I asked for a full client-exploit audit: remote abuse, economy duplication, teleport and speed hacks, combat spoofing, inventory manipulation and privilege escalation. The fixes are in (see "Security rules" above). Keep everything server-authoritative.

### Other things I asked about
- **Claude plans and effort:** use a high effort setting for careful restructures (like the boss split), and medium for small tweaks. Don't ask for huge multi-feature jobs in one go.
- **Sounds:** you can't make audio. Hook sounds by name in SoundService and tell me the names.

## What to do next (the approved plan, in this order)

The Colosseum polish plan was:
1. enemy types ✅
2. difficulty board
3. boss wave ✅ (the Giant Straw King, see above)
4. streaks
5. juice
6. reward feel

The build order is 1 → 3 + 4 → 2 → 5 + 6.

1. ~~**Boss wave every 5 waves: the Giant Straw King.**~~ ✅ Done (see "The boss wave" above).
2. ~~**Kill streaks and best wave:**~~ ✅ Done, as 5-wave runs with a best clear time, runs cleared, a daily first-clear bonus, and kill streaks (see "Runs" above).
3. **Difficulty board** at the entrance, pick one:
   - **Normal**
   - **Hard:** 1.5× dummy health and damage, better rewards
   - **Nightmare:** 2.5×, much better rewards
4. **Juice:**
   - The crowd cheers when you kill.
   - The crowd throws hearts (heal pickups) and coin bags onto the sand.
   - A horn sounds at the start of each wave.
   - Add sound hooks by name and tell me the names.
5. **Reward feel:**
   - Coins/XP visibly fly from the dummy to you.
   - A chance of a chest drop (use the existing Items / boss chest system).

**Later (bosses last):** more bosses (my goal is 20+), and possibly splitting the big BossService / BossClient into one module per boss.

## Testing tips

- Before pushing, compile-check every changed file with a Luau compiler (`luau-compile`) and run `luau-analyze`.
- Headless tests of the server logic with a mock Roblox are very useful: they caught NaN and positioning bugs before. They're now in `Tools/HeadlessTests/` (`./run_all.sh`); add new tests there.
- Remember `Random:NextNumber(a, b)` takes a range. `Vector3.zero` exists in Roblox.

Start by reading `ReplicatedStorage/Config.lua` (the `Colosseum` section) and `ServerScriptService/ColosseumService.lua`, then continue with step 3 of "What to do next" (the difficulty board: Normal / Hard / Nightmare, picked before each run).
