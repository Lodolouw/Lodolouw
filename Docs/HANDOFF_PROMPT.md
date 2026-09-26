# Handoff prompt — paste everything below the line into a new Claude session

---

You are continuing work on my Roblox game. Read this whole message before doing anything.

## The game

- It's a Roblox game in the style of **"+1 Defeat the boss to Grow"**: you punch things to gain Power (XP), level up, buy upgrades, and fight bosses.
- **The look is 8-bit / pixel-art**, using the **Endesga-32 palette**: flat materials (SmoothPlastic/Neon), chunky blocky shapes, and the Press Start 2P font. Keep everything new in that style.
- **Everything is built from scripts.** There are no imported meshes or models (apart from optional NPC models loaded by ID with a blocky fallback).

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
