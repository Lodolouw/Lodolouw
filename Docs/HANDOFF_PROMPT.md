# Handoff prompt — paste everything below the line into a new Claude session

---

You are continuing work on my Roblox game. Read this whole message before doing anything.

## The game

- It's a Roblox game in the style of **"+1 Defeat the boss to Grow"**: you punch things to gain Power (XP), level up, buy upgrades, and fight bosses.
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
   - **Upgrades** (backpack, gloves, sell value, Swift Boots), **talismans** (3 slots) and **prestige** give more ways to get stronger.
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
- **Other ideas I liked, for later:**
  - A **first-time tutorial**: an arrow to the Colosseum, "Beat 5 dummies", "Spend your stat points", "Open your chest".
  - **Pets** from eggs: the Pet Sanctuary tower is already built and empty.
  - **Gear upgrading** from +1 to +10.
  - **Cosmetics** such as auras and titles.
  - A **settings menu** (music and SFX volume, camera shake).
  - A **level-up celebration**.
- **Order of work:** make the Colosseum great first (see the plan at the bottom). **Bosses come last.**

## The repository

- **Repo:** `https://github.com/Lodolouw/Lodolouw`
- **Branch:** `claude/nice-cori-7kss8b`. Keep working on this branch and push to it.
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

### How I install your changes (important — I'm not a programmer)

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

### Recent fixes (please verify in play)
- Players sinking into the floor after reset/death. LobbyActivities `keepFeetUp` watches the lowest foot against the floor, raises the ControllerManager's `GroundController.GroundOffset` (or R15 HipHeight) by the gap, and lifts the body. **The character uses Roblox's ControllerManager**, not classic Humanoid movement.
- The gap behind the stands is filled (`StandFill` parts).

## Everything we've built and decided so far (history)

### Lobby and world
- **The lobby:** a castle plaza with a fountain, lamp posts, paths, a farm, a Sell Shop, and an Upgrade Shop with an 8-bit frog.
- **The mushroom house:** I asked to keep the OLD mushroom house, just sharpened up. A pixel-circle version flickered.
- **The training yard:** 12 practice dummies on two tiers, with Straw → Cosmic dummies.
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
3. boss wave
4. streaks
5. juice
6. reward feel

The build order is 1 → 3 + 4 → 2 → 5 + 6.

1. **Boss wave every 5 waves: the Giant Straw King.** A big straw dummy with a crown, a boss HP bar, and a few telegraphed attacks (for example a ground-pound shockwave ring, summoning straw minions, a spinning sweep). It gives a big reward.
2. **Kill streaks and best wave:**
   - A streak counter for kills without getting hit ("x5 STREAK!") with a reward multiplier.
   - Save each player's best wave in their data, and show it in the HUD.
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
- Headless tests of the server logic with a mock Roblox are very useful: they caught NaN and positioning bugs before.
- Remember `Random:NextNumber(a, b)` takes a range. `Vector3.zero` exists in Roblox.

Start by reading `ReplicatedStorage/Config.lua` (the `Colosseum` section) and `ServerScriptService/ColosseumService.lua`, then continue with step 1 of "What to do next".
