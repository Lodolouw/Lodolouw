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

1. **Farm.** In the **Colosseum** you fight 5-wave runs of dummies at your level (on Normal, Hard or Nightmare) to gain **Power (XP)** and **coins**, and complete the Colosseum's quest ("Beat 5 Waves") and daily quests. This is where players spend most of their time, so it has to be *fun*: varied enemies, telegraphed moves to dodge, and rewards that feel good.
2. **Grow.**
   - Levels come from Power. Total Power for a level = 17.9 × (level − 1)³, up to level 256.
   - Every level gives **stat points** to spend: Strength (damage), Vitality (health), Defense, and Training (+Power gain).
   - **Gear** drops from boss chests: rarities, stats and sets (see `Items.lua`, Inventory GUI).
   - **Upgrades** (backpack, gloves, sell value, Swift Boots) and **talismans** (3 slots, crafted at the Armory/blacksmith) give more ways to get stronger.
   - Levels are **Blox Fruits-style**: max 256, 3 stat points per level.
   - **Prestige was removed completely** (on purpose). Old prestige was converted into Oozark chests once. `Config.MaxPrestige = 0`, and there's no prestige sign. Don't bring it back.
3. **Fight bosses** in **the Spire**. Each floor is a boss with a recommended level:
   - Floor 1: **Oozark, the Gelatinous Tyrant**, the slime, "Gloomgut" in older code. Level 15, in the slime pit.
   - Floor 2: **Tuber**, a chubby cactus stack (a parody of Mario's Pokey) who powers up into **THE BRUTE, THE CACTUS KING**, a giant ranged cactus golem: two health bars. Level 30, in the Sunken Dunes (a cactus desert). He replaced the old sand worm ("Nahrzul"/"Mireworm"), which didn't work well and lagged.
   - Floor 3: **Knight Burrowmore, the Honourable Digger**, a knight of the shovel (a parody of Shovel Knight). Level 45, in the Glimmer Dig.
   - Floor 4: **Kaze, the Headband Hero**, a wandering martial artist (a parody of Ryu) who fights like a fighting-game character. Level 60, in the Rooftop Dojo.
   - Floor 5: **Speedy Revvington, King of the Speedway**, a cocky cartoon race car (a parody of Lightning McQueen) in a drive-by duel. Level 75, on Piston Speedway.
   - Floor 6: **Gridlock, the Final Beat**, a living level: a demon cube (a parody of Geometry Dash's "Deadlocked") who fights on the beat, in cube, ship, UFO and wave forms. Level 90, in The Final Beat.
   - Floor 7: **Kongo, the Jungle Brawler**, a huge gorilla in a red tie (a parody of Donkey Kong) who fights with the moves from his games. Level 105, in Kongo's Jungle Village. No chest yet (his loot comes with the loot rework).
   - Floor 8: **Petalina, the Blooming Terror**, a giant cartoon flower (a parody of Cuphead's Cagney Carnation) who never moves: seeds, flytraps, petal boomerangs, vines, pollen, a head that stretches out to chomp you. Level 120, in the Glasshouse Garden. No chest yet.

   Boss fights are souls-like: dodge rolls with invincibility frames, stamina, **flasks** to heal (R), lock-on (Tab, Q/E to switch), and clear red telegraphs before attacks. Bosses drop **chests** with gear.
4. **Repeat.** Beating a boss unlocks the next level target, which means more farming with tougher Colosseum enemies and better gear.

**Where it's going:**
- **20+ bosses.** With 20 bosses, a player's full playthrough would be roughly **30–60 hours**. Right now a player finishes both bosses in about **1–3 hours**. A game like this wants 10+ hours of progression.
- **Every boss should be EPIC, but efficient to build:**
  - Share one framework: warnings, health bar, 8-bit block style, attack timing, sounds and music by name.
  - Each new boss is mostly new attacks plus a new body.
  - Mix a few huge showpieces (like Tuber's power-up) with simpler bosses.
- **The boss-code split ✅ (done, players see no difference):**
  - Server: `BossService` keeps what every boss shares; each boss has its own ModuleScript in `ServerScriptService/Bosses/` (`Oozark.lua`, `Tuber.lua`...), found by its `Short` name in `Config.Bosses`.
  - Client: `BossClient` keeps the shared visuals; each boss's body has its own ModuleScript in `ReplicatedStorage/BossBodies/` (`Oozark.lua`, `Tuber.lua`...).
  - "How to add a boss": `Bosses/_Template.lua` + `BossBodies/_Template.lua` (a tiny working boss with one attack, STOMP; `test_boss_template.luau` fights it). See "Adding a boss" below.
  - Proven identical by golden traces: `Tools/HeadlessTests/golden.sh check` (16 recorded fights, server and screen, byte-identical before and after; Burrowmore added 4 more of his own, Kaze 4 more, Revvington 4 more, Gridlock 4 more, Kongo 4 more and Petalina 4 more: 40 now - and floor 2's 7 were re-recorded when Tuber replaced the worm).
- **THE NEW DIRECTION (decided, replaces the old chest/gear/market plan): simple like Blox Fruits.** See "The new direction: weapons, packs, pets and Arcade Tokens" below. (The old boss chests with armour gear were built, and will be removed by it.)
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
- **Walk-up pop-ups (no "press E"):** every station opens by walking up to it. LobbyBuilder's `autoZone(parent, cf, size, attr, value)` makes an invisible box tagged `AutoOpenZone` in front of each one: the shops (attribute `Panel`, watched by Hud), the Spire's doors and fog gates (attribute `Spire`, SpireClient), and the Quest Board and the Colosseum's two doors (attribute `Activity` = `Quests` / `ColosseumEnter` / `ColosseumLeave`, LobbyActivities' "Walk up and it pops up"). The rules are the same everywhere: step in and it opens, step out and it closes (2 studs of slack so it doesn't flicker); close it yourself and it stays closed until you step out and back in. In LobbyActivities, a box you *arrive* in (popping out of the Colosseum's little door, a respawn) also waits until you step out and back. The boxes stop short of the roads, so walking past doesn't open them. The shops' and the Spire's old prompts still exist but are switched off on each screen (`Enabled = false`); the Quest Board and the Colosseum have none. Preview: `Docs/walkup_popups.png`.
- **The intro (Oozlet) ✅:** a brand-new player's first minute - see "The intro: Oozlet" below.
- **The mini sand-castle Colosseum:** this is where the old training field / training yard was. **The old training yard dummies are gone.** Power now comes from the Colosseum (plus bosses and quests).
- **Spire floors:**
  - Floor 1: "Oozark's Hollow", the slime pit.
  - Floor 2: the **Sunken Dunes**, Tuber's cactus desert (DunesBuilder).
  - Floor 3: the **Glimmer Dig**, Knight Burrowmore's dig site on the sunny plains (DigBuilder).
  - Floor 4: the **Rooftop Dojo**, Kaze's dojo on a mountain peak above the clouds at sunset (DojoBuilder).
  - Floor 5: **Piston Speedway**, Revvington's oval racetrack in the desert, packed grandstands and all (SpeedwayBuilder).
  - Floor 6: **The Final Beat**, Gridlock's level: a neon grid floating in a purple void, jump pads, a ceiling grid, spikes and saws all round (GridBuilder).
  - Floor 7: **Kongo's Jungle Village**, Kongo's flat jungle clearing: a village of huts on stilts with rope bridges and treehouses round it, and a waterfall with a rainbow behind it (JungleBuilder).
  - Floor 8: **The Glasshouse Garden**, Petalina's greenhouse: a square glass hall with a round garden inside - paved paths and raised flower beds (GreenhouseBuilder, shape in GardenPlan). The Spire menu scrolls, so more floors fit.
- **Music:** there are 3 lobby songs, a slime boss song, "Tuber Song" for little Tuber (round 1; not added yet) and "SANDWORMSONG" for the Brute (round 2), "Burrowmore Song" for the knight, "Kaze Song" for Kaze, "Revvington Song" for Revvington, "Gridlock Song" for Gridlock and "Kongo Song" for Kongo and "Petalina Song" for Petalina (add them: until then Oozark's plays; Kongo's arena also loops "Jungle Ambience", Petalina's "Greenhouse Ambience"), played by name from SoundService.

### Places we discussed for later (not built yet)

(**Fishing and pets were re-decided:** you fish for pet EGGS - see "Fishing for pets" under the new direction. The two older ideas below are kept only for history.)

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
- **Trading** (only weapons and pets): a two-player trade window where both confirm and the server swaps the items - exploit-proof, everything on the server (the saves are already session-locked). **No Auction House, no market** (decided).
- **Gear Hall:** an armoury display, and a place where you open chests in public to show off rare pulls.
- **Hall of Champions** in the Grand Keep: live statues of the top players (by Power and fastest boss kill) and a trophy wall of the bosses you've beaten.
- **PvP duels** in an arena courtyard, reusing the combat system and the VS splash.
- **Ramparts parkour** up the walls to the highest tower, with a badge at the top.
- **The Vault** under the keep: a daily chest, and a secret room that opens after beating a certain boss.
- **A codes board** at the gatehouse for promo codes.

**Robux rule (updated):** the old rule "never sell gear for Robux" was only there to protect a player market - there's no market now, so Arcade Tokens (which roll weapons) CAN be bought with Robux. See the new direction below.

## The new direction: weapons, packs, pets and Arcade Tokens (DECIDED - not built yet)

I decided to make the game **simple, like Blox Fruits**: few things to understand, and Robux has two clear jobs - **go faster**, or **look cooler / get the fun power**.

- **The loop:** fight in the Colosseum → level up → beat Spire bosses → earn **Arcade Tokens** → roll **weapons** → get stronger → next boss.
- **A player has only 4 things:** their **Level** (Power), a **Weapon** (like a fruit: it changes how you fight), a **Pet** (a helper with a bonus), and two currencies: **Coins** (free, from fighting) and **Arcade Tokens** (for rolls).
- **Weapons come from ARCADE MACHINES, one per boss** - a row of cabinets in the lobby, each painted like its boss. A boss's pack **unlocks when you beat that boss**. Each pack has its own weapons themed on that boss (e.g. Slime: Goo Gloves, Slime Whip, Gelatin Hammer; Jungle: Banana Boomerang, Barrel Bomb, Giant Fist; Garden: Thorn Whip, Petal Blades, Flytrap Gauntlet), one Mythic each, and a tiny shared chance at a Secret. Higher-floor packs cost more but are stronger. It's a real choice: each pack really has different weapons. A "pack of the week" with boosted odds.
- **Every weapon plays differently:** its own model (chunky 8-bit parts), look, combo, reach, timing and special move, animated in code (the character's arms and body moved by script, like the bosses) with trails, bursts, camera shake and sounds. If I later make polished animations in Studio's Animation Editor, I give the IDs and they get swapped in.
- **Rarities:** Common → Uncommon → Rare → Epic → Legendary → Mythic → Secret. **Odds are shown** on every machine (a Roblox rule for paid random items). A **pity counter** per pack (e.g. a guaranteed Legendary every 40 rolls), shown on screen. Duplicates turn into tokens or upgrade that weapon.
- **Arcade Tokens are earned by playing, in small amounts:** 1 from the daily quest (a reason to log in daily), a daily login streak (bonus on day 7), first boss clears (3-5), sometimes from repeat boss kills, a Colosseum run, every 10 levels, codes, badges. About 10-15 a week free. **Or bought with Robux** (packs of tokens). In countries where Roblox doesn't allow paid random items (PolicyService says so), buying tokens with Robux is switched off - free tokens still work.
- **Pets:** hatched from eggs bought with Coins (and rare boss eggs); a bonus like +XP, +coins or +damage; 1 equipped at first, more slots later.
- **Trading:** only weapons and pets. No market / Auction House.
- **What Robux buys:** go faster (2x XP, 2x Coins, token packs, an extra pet slot, lucky hatching) and look cool (weapon skins, auras, victory dances, a VIP tag), plus private servers.
- **What gets CUT:** armour gear (helmet, chest, boots and their sets), boss chests (bosses give Tokens, Power and sometimes a rare egg instead), talismans and the upgrade shop. The screen shrinks to **4 buttons: Roll, Inventory, Shop, Quests**, with Level, Coins and Tokens at the top. Existing players' gear is turned into Arcade Tokens once, so nobody loses out.
- **What stays the same:** the bosses, the Colosseum, the intro, combat and the daily quests.
- **No "evil" tricks:** no fake timers, no fake free-Robux, no misleading thumbnails, no fake near-misses. Fair and exciting, within Roblox's rules.
- **Launch = weapons only, no pets.** Pets (from fishing) are the first big update after launch.
- **Build order:** 1) ONE test weapon (a sword) I playtest first, then weapon ownership + rarity + mastery. 2) Arcade Tokens + the Arcade Machine (the spin screen below) + the first two packs (Slime and Cactus); then the other packs one at a time. 3) The cuts (armour, chests, talismans, upgrade shop) and the NEW GUI (being designed now). 4) Trading. 5) The Robux shop. 6) Event bosses + the Event Arena. 7) Main bosses up to 15, then launch. After launch: fishing and pets, Nightmare Spire, bosses 16-20.
- **Main bosses:** the goal is 20 floors. **At least 15 before launch** (so Nightmare Spire, below, has enough to replay); 16-20 come in updates.
- **EVENT BOSSES (decided, replaces the older "lands in the lobby plaza" plan):** see "Event bosses" below.
- **Growing the game (agreed ideas):** update tags in the title, bosses on the thumbnails (test a few), a daily login streak, codes on update days and like milestones, a group-join reward, leaderboards (fastest boss kill) and a badge per boss, clips for TikTok/Shorts, and Roblox ads only once players stay.

### The arcade spin (how a roll looks - decided)

- A **CS:GO-crate-style strip**, but on the **screen of an arcade cabinet**: pixel weapon tiles fly past and slow down, a coin-slot "clunk" when a token goes in.
- **Rarity colours** on each tile's border: grey (Common), green (Uncommon), blue (Rare), purple (Epic), gold (Legendary), red (Mythic), rainbow (Secret).
- **The landing reacts to rarity:** a small beep for Common; flashing marquee lights for Epic+; a full-screen reveal for Legendary+; a **server-wide banner** for a Secret ("X just rolled a SECRET weapon!").
- **Honest:** the server rolls the result BEFORE the spin, the animation only shows it (also exploit-proof). The strip is filled using the real odds. **No fake near-misses** (never slowing past a Legendary on purpose). The odds button is always on the machine.
- **Mobile and respectful of time:** a spin takes ~3-4 seconds, **tap to skip**, a **Roll x10** button shows a grid of 10 results, and the **pity bar** ("Epic guaranteed in 12 rolls") is on the machine.

### Weapon types and abilities (decided)

- **6 weapon types, all melee** (nothing reaches past sword length, so no boss can be cheesed from safety - that's why spears and staffs were cut):
  1. **Fists / Gauntlets** - fast, short reach (the starter).
  2. **Sword** - balanced, easy.
  3. **Hammer** - slow, heavy, a ground slam.
  4. **Daggers** - fast stabs, a dash.
  5. **Scythe** - wide sweeping arcs, slow swing.
  6. **Katana** - fast light slashes; its thing is the quick-draw (hold to sheathe, release for a lightning dash-slash).
- **Normal attacks come from the TYPE** (every sword swings like a sword - learn a type once, use any weapon of it).
- **One ability per WEAPON** (its own, e.g. the Barrel Hammer rolls a barrel), on a cooldown of about 8-12 s, close range too. **It upgrades with that weapon's mastery**, e.g. Barrel Hammer: mastery 1 one barrel, 25 bigger and faster, 50 two barrels, 75 they explode, 100 (awakened) a new look + a giant golden barrel finale. Rarer weapons get flashier abilities.
- On phones: one attack button, one ability button.
- Each boss pack has about 4 weapons (3 + a Mythic), each a different type in that boss's theme; 15 bosses = about 60 weapons from 6 movesets, plus the event weapons. New types (a 7th, 8th) can be big update headlines later.

### The test sword ✅ (build step 1)

The first weapon is in, to test the feel before anything is built around it: the **Iron Sword** (Common, type Sword). In Studio: dev console, **DEV: Test Sword** (again: back to fists) and **DEV: Mastery +25** (25, 50, 75, 100, then back to 1). Preview `Docs/sword_preview.png` (the stance, the three swings chained as you'd play them, and the Whirlwind, drawn from the real code's poses).

- **Numbers:** all in `Config.Weapons` - `Rarity` (Start/Ceiling multipliers, the mastery table above), `MasteryHits` (8 hits for level 2, +2 per level after), `Types.Sword` (the string: slash 1.0x / backhand 1.0x / chop 1.5x; each swing's `Lock` (commit time), `Contact` (when it lands), `Cost` (stamina), `Range`, `Arc`), `List.IronSword` (colours, and the ability: Whirlwind, 10 s cooldown, 20 stamina, `Tiers` by mastery with the words the card shows). Helpers: `Config.masteryLevel`, `masteryPointsFor`, `weaponMultiplier`, `abilityTier`.
- **Server (CombatService, "Weapons" part):** the player attribute `Weapon` (an id) makes "Punch" swing the weapon instead: it cuts EVERY target in the swing's arc (a punch hits one), damage = your punch x the swing's Damage x the weapon's rarity/mastery multiplier; every enemy hit is a mastery point (attributes `Mastery`, `MasteryProgress`; a "Mastery" event on level up). "Ability" (F) does the Whirlwind: spins hit everything within the tier's Radius, the last spin's `Ring` hits further out (tier 4+). `SwingN` / `AbilityN` attributes change on every swing / ability so every screen animates it. `CombatService.Equip(player, id)`. Mastery is kept per player per weapon for the session only - **saving comes with step 2 (owning weapons)**. Fists are unchanged.
- **Screens (v3: I found v1 "very stiff"; then I asked for Elden Ring's smooth weight, Hades' hits and Deepwoken as the Roblox reference - "not stiff and goofy like a fencing dummy" - and said v2's grip was horrendous and its stance overwrote my dash):** `ReplicatedStorage/WeaponFX` builds a chunky sword with a glowing edge in each fighter's right hand (on each screen, only in a fight) and animates EVERY R6 joint (both shoulders, both hips, neck, `RootJoint` lean + turn + height) plus the sword's angle and roll in the hand. How it moves: every part is pulled by a SPRING (`WeaponFX.SPRINGS`: soft with no bounce when idle, snappy with a little overshoot in a swing); OVERLAP (`OVERLAP`: the body leads, then the arm, and the blade trails like a whip - `LEAD` adds each spring's own lag back so every part still arrives on time); each swing (`swingMoments`, in seconds from its `Lock`/`Contact`) winds up, holds a heartbeat, SNAPS through the cut (the blade is fastest the frame it lands - the moment the server cuts), rips on through and HANGS in the follow-through until it lets you go, then drifts home over `SETTLE` (0.3 s); the next swing winds up from wherever the body is, so a string is one flowing movement; FEET ON THE FLOOR: the body is lowered or raised so a foot stays on the floor (lunges sink down into them) and the hips take back the body's lean and turn. The string: a diagonal slash (high right to low left), a rising backhand (low left to high right), and a leaping overhead finisher that slams down with a shockwave on the floor. The stance (Elden Ring's one-handed idle): relaxed, a little side-on, blade low and forward, breathing, the weight shifting from foot to foot; walking, the legs and free arm walk and the sword arm holds the blade steady (with a touch of the walk's own sway). Rolling, jumping and drinking win: any Action..Action4 animation (the roll) makes it let go of the whole body within a few frames and cancels a swing (tracks warming up at no weight don't count); in the air the legs and body are left to the jump; drinking tucks the sword away and leaves the arm and head to the drink. On a hit (CombatClient `Weapon.landed`): hit-stop that stops the whole body dead and shudders (`HitStop` / `HeavyHitStop` in `Types.Sword`), a slash mark tearing across the target with sparks, a white impact flash with speed lines on heavy hits (`ImpactFrames`), and a "12 HITS" combo counter (`ComboCounter`). The dash in (`Lunge`) goes with the cut: CombatClient starts it at the hold, not on the press (not if you rolled or swung again). The whoosh plays as the cut starts, a touch different in pitch every time. The hint line switches to "Click: swing  F: ability". CombatClient uses the sword's timings and stamina costs in `tryPunch`, predicts your own swing/spin instantly, adds F / gamepad X / a phone button, and a card bottom-right (name, ability, mastery bar, cooldown). Mastery 100: gold blade.
- **Sounds to add (optional):** "Sword Swing", "Sword Hit", "Whirlwind" (missing: silent swings, punch hit sounds).
- Tests: `test_sword.luau` (server rules), `test_weaponfx.luau` (how it looks: the stance, feet on the floor, each swing's path and timing - fastest as it lands, the whip order, the hold, the whoosh - chaining, hit-stop freezing everything, the roll/jump/drink letting go, the Whirlwind, other players, gold, tidying up); pictures `render_sword.py`.
- **Hit reactions ✅ (every hit that lands, fists or sword, anyone's):** I compared us with a YouTube sword-combat tutorial and the one thing it had that we didn't was enemies reacting to being hit, so: the server marks each landed hit on the enemy (`HitFx` = "count:weight:x:z", only when it did damage - not on a shield clang or an untouchable boss) and fires its `OnHit` with the weight and direction too. Every screen flashes the enemy pure white for a blink (CombatClient, a Highlight; not bosses, not enemies drawn by another script). The **Colosseum's dummies** (ColosseumService, "Hit reactions") tip away from the blow and wobble back upright like punching bags, and get knocked back - a little by a normal hit, sent flying by a finisher (weight 3: the last swing of a string, or a crit), even by the killing blow (they crumble to ash as they land). It rides on top of wherever the dummy's brain puts it, and becomes where it really is when its brain next decides a move (`settle`), so the brains never had to change. Heavier kinds budge less (`heft`: scale squared, the Iron Knight x1.8); the Straw King only flinches; nothing is ever knocked past the wall or pulled back towards you. **Bosses** already squashed and blanched when hit; now each blow also jolts their body back a touch (BossClient). Numbers: `Config.Combat.HitReact` (Flash, Tilt, Push, Rise, BossJolt). Preview `Docs/hit_reactions.png` (`render_react.py`). Tests: `test_colosseum.luau -a react` (the reactions, measured), `test_sword.luau` (the marks), `test_hitflash.luau` (the flash).
- **To do: redo the sword.** I called it "that horrible sword" and want it redone later - ask me what exactly (the look of it, the swings, or both) before starting.
- **Next:** I playtest it. Then step 2: weapon data (owning, equipping, saving, mastery saved), then the big switch (new GUI, old loot out), then the Arcade Token machine.

### Weapons: small differences at first, true ceiling with mastery (decided)

Every weapon has **mastery** (levels up by using it, up to 100). At the start the rarities are close; at high mastery the rare ones pull away. Damage vs a basic weapon:

| Rarity | Mastery 1 | Mastery 100 |
|---|---|---|
| Common | 100% | 150% |
| Uncommon | ~102% | 170% |
| Rare | ~104% | 195% |
| Epic | ~106% | 225% |
| Legendary | ~108% | 260% |
| Mythic | ~110% | 300% |
| Secret | 112% | 340% |
| Event (rare drop) | ~110% | 320% |

At mastery 100 a weapon can be **awakened** (a new look + a stronger special). So a new player isn't hopeless with a Common, and a long-time player has a reason to keep going.

### Event bosses (decided)

- **Timer:** a **global** timer, about every **45 minutes**, at the **same clock times** on every server (players can plan for it). 5 minutes before: a warning (sky darkens, siren, "EVENT BOSS IN 4:59", event music).
- **Where:** a new **Event Arena on the side of the island**, which **transforms to fit** each event boss (lava, snow, storm clouds, space...). Everyone runs/teleports there.
- **Who:** at launch, **8 event bosses** that are **turbocharged, themed versions of existing bosses** (same bodies and moves, reused, but bigger, faster and restyled): Magma Kongo, Frostbloom Petalina, Storm Kaze, Galaxy Oozark, Golden Burrowmore, Nitro Revvington, Shadow Tuber, Glitch Gridlock. Picked at random.
- **The fight:** the whole server races to kill it; a live **damage leaderboard**. Health scales with players. Its attacks only hit players who are fighting it.
- **Rewards:** damage milestones at **1% / 5% / 15%** of its health give everyone who reaches them Arcade Tokens. The **top 3** get a gold name + a crown for a while, and the best odds.
- **Two event weapons per event boss:** a **common** one (about **20-30%** drop, so most people leave happy) and a **very rare** one (about **0.5-1%**, the rarest trade in the game). An **event pity counter** so regulars eventually get the rare one.
- **Robux:** a "Double Event Luck" game pass (better odds, shown openly).
- **Late game:** stronger versions later (Calamity / Mythic tier) for high-level players.

### Fishing for pets (decided - first update after launch)

- **You fish for pet EGGS**, not fish: Pond, Coral, Abyss and Golden eggs, and a **Secret pet** (server-wide banner when caught).
- **Rods unlock by level** from the shop: Twig (1), Bamboo (25), Iron (60), Crystal (110), Arcade (180). Better rods = better chances, but **every rod can catch everything**, so a brand-new player can still land the Secret.
- **Beginner's luck:** boosted rare odds for your first 50 catches.
- **Bait** (boosts odds), a **fishing spot per boss** area, and a **pet log** to complete.
- **Ocean events:** the sea changes for a while - **Lava Ocean** (lava-themed pets), **Cosmic Ocean** (cosmic pets), more later.
- **The minigame (mobile friendly, one button):** "keep it in the zone" - hold to raise the marker, let go to drop it, keep it on the moving fish zone until the bar fills. Rarer eggs move more wildly.
- Odds shown for every egg, including the Secret (its picture can be a silhouette, its chance cannot be hidden).

### The late game (decided)

- **Nightmare Spire = New Game+** (like Elden Ring): replay every Spire boss with **more aggression and bigger attacks** and a darker look. **No new attacks** (too much work) - bigger, faster, more of them.
- Speedrun leaderboards per boss, a **Boss Rush** mode, **shiny** pets, an **aquarium** to show off pets, and the stronger event bosses.

### The boss lineup (floors 9-15, decided so far)

9. **Scribble** (as planned before). 10. An **arcade robot tank** (original). 11. A **hammer king** (inspired by King Dedede - own design and name). 12. A **ghost pirate ship captain**. 13. A **cosmic boss** - proposed: "The Stargazer", a giant in the sky with galaxy hands (star cores in the palms are the weak spots) and a telescope eye in round 2, on an asteroid island that shrinks (awaiting my OK). 14. A **skeleton bullet-hell** boss. 15. An **End Dragon** (the finale). 16-20 later.

### Platform safety rules (so the game never gets taken down)

- **Copyright:** borrow a fight's IDEA, never a character's look or name. Every boss gets its own name and a clearly original design. Never show or name real characters in the title, thumbnails, icon, description or ads. Extra care on the dragon, skeleton and ghost bosses.
- **Paid random items** (anything Robux can roll, even through tokens): odds shown before every roll, for every item including the Secret. Check `PolicyService:GetPolicyInfoForPlayerAsync` - if `ArePaidRandomItemsRestricted`, no Robux token purchases for that player (free tokens still work).
- **No real casino games** (slots, roulette, betting items against other players).
- **Trading:** two-sided with a confirm screen and a short cooldown; never promote selling items for real money or Robux off Roblox.
- **No bait:** no rewards for liking/favouriting/following, no fake free Robux, no thumbnails showing things not in the game, no fake player counts or bots.
- **Age rating:** fill in the maturity questionnaire honestly; keep bosses cartoony (no blood, no real jump-scares).

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
- `CarPath.lua`: how Speedy Revvington drives - the segment sums (lines, arcs, skid turns) shared by his server file and his body, so every screen draws him exactly where he is.
- `BeatGrid.lua`: Gridlock's level - the grid, the beat, the tile patterns and his motion (hops, flights, falls, zig-zags), shared by his server file and his body, so every screen lights the same tiles on the same beat and draws him exactly where he is.
- `Vitals.lua`: THE HEART (your health), and in a fight THE POTION (flasks, on its left) and THE LIGHTNING BOLT (stamina, on its right): three pixel-art pictures filled with liquid, drawn at the bottom of the screen. Hud starts it (`Vitals.start`) and CombatClient feeds it (`Vitals.set` for numbers, `Vitals.fire` for moments: "drink", "iframes", "empty", "noFlask"). See "The heart, the potion and the bolt" below.
- `WeaponFX.lua`: how weapons look on every screen - the weapon in each fighter's hand, its swings and its ability, animated in code on the R6 joints (see "The test sword").
- `Items.lua`: gear rarities, stats, sets and loot tables. "Floor" 0 is Oozlet's Chest (the intro's starter gear, level 1: Squishy Gloves, Bouncy Boots, Oozlet Cap, Goo Vest).
- `BossBodies/` (a Folder): one ModuleScript per boss's BODY - everything that boss draws (its body and how it moves, the shape of each action, their sounds, bursts and warnings, its arena reacting): `Oozark.lua`, `Tuber.lua`, `Burrowmore.lua`, `Kaze.lua`, `Revvington.lua`, `Gridlock.lua`, and `_Template.lua` (not a boss: the starting point for a new one). BossClient finds each by the boss's `Short` name and hands it the drawing kit (`Body.init(kit)`).

**ServerScriptService/**
- `Main.server.lua`: a Script. It builds the world and then starts each service inside `pcall`.
- `LobbyBuilder.lua`: builds the entire lobby, the mini colosseum, the real Colosseum arena and the dummy templates.
  **WARNING:** it is right at Roblox's **200 top-level locals limit (about 193 used)**. Put new code inside the existing `Extras` function block, or inside `do ... end` blocks. Never add new top-level `local`s.
- `PlayerService.lua`: DataStore with session locking, the movement anti-cheat guard, request rate limits, daily quests, stats and upgrades.
- `CombatService.lua`: server-authoritative combat: punches, the owner filter, damage, the shield block, and Disintegrate.
- `ColosseumService.lua`: the Colosseum wave arena (details below).
- `BossService.lua`: what every boss shares: an encounter's life (asleep, waking, fighting, the break at half health, resetting, dead + rewards), targets, publishing actions for the screens, timing, hitting players, the surface-boss brain (choose an attack by distance, do it, breathe), moving and turning, shock rings and burning puddles. It loads each boss's own file and hands it the shared helpers (`Boss.init(kit)`; the list is `makeKit`).
- `Bosses/` (a Folder): one ModuleScript per boss, named after its `Short` name in `Config.Bosses`:
  - `Oozark.lua` (floor 1, the slime; "Gloomgut" in older code): its attacks.
  - `Tuber.lua` (floor 2, the cactus): his own brain (two fights: little Tuber, then THE BRUTE), his moves, his every-frame step (everything he throws and plants), the cactus props he leaves round the arena (`Workspace.TuberProps`) and hooks (see "Floor 2: Tuber").
  - `Burrowmore.lua` (floor 3, the knight): his moves (a surface boss: the shared brain picks them by distance), his body shape for punches (high in the air he's out of reach) and a few hooks (see "Floor 3: Knight Burrowmore").
  - `Kaze.lua` (floor 4, the fighter): his own brain (the ki meter, cancels, charging, the Super and the pillars), his moves, his every-frame step and hooks, including the new `onMove` (see "Floor 4: Kaze").
  - `Revvington.lua` (floor 5, the race car): his own brain and every-frame step - everything he does is a driving segment (`ReplicatedStorage/CarPath`) - his moves and his box-shaped hits (see "Floor 5: Speedy Revvington").
  - `Gridlock.lua` (floor 6, the living level): his own brain and every-frame step - the beat, the tile patterns, his forms and motion (`ReplicatedStorage/BeatGrid`), the drop, the gravity flip, the jump pads (see "Floor 6: Gridlock").
  - `_Template.lua`: NOT a boss: the starting point for a new one (see "Adding a boss").
- `SpireService.lua`, `DunesBuilder.lua`, `DigBuilder.lua`, `DojoBuilder.lua`, `SpeedwayBuilder.lua`, `GridBuilder.lua`: the Spire's menu and travel, and the arenas of floors 2, 3, 4, 5 and 6.
- `IntroService.lua`: the intro's fight, all decided on the server (see "The intro: Oozlet").

**StarterPlayerScripts/** (LocalScripts)
- `CombatClient.client.lua`: combat input, lock-on, roll, camera, damage numbers and health-bar tidying. (Stamina and flasks are drawn by `ReplicatedStorage/Vitals`, not here.)
  It has about **194 top-level locals** — same rule: use `do ... end` blocks.
- `LobbyActivities.client.lua`: the Colosseum HUD (quest tab, wave box, banners, confetti), the coins/XP shower, the King's boss bar and music, the CLEARED screen, the difficulty pop-up at the Colosseum's door and the "Leave?" check at its exit, the walk-up pop-ups (no "press E"), the pipe shrink animation, the quest menu, and the "never sunk in the floor" guard.
- `BossClient.client.lua`: what every boss's visuals share: the drawing kit (8-bit parts, rings, bursts, camera kicks, sounds, warnings, one-off moments on the server's clock), tracking each boss and its pose every frame, the arena weather (acid rain, the dunes' sandstorm), the boss bar, the victory banner, and the music. Each boss's body is in `ReplicatedStorage/BossBodies/` (below).
- `IntroClient.client.lua`: everything the intro shows (see "The intro: Oozlet").
- `Hud`, `RetroUI`, `RetroWorld`, `Inventory`, `BossIntro`, `ArenaAmbience`, `LobbyFX`, `SpireClient`. (`RollDebug`, a temporary roll-debugging tool, was removed.)

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
- **Always warm up assets** so nothing stalls or plays silent the first time: preload new sounds, music, animations and textures with `ContentProvider:PreloadAsync` (like BossClient's warm-up of every boss's sounds and songs, CombatClient's `warmAnimations` and LobbyActivities' Colosseum warm-up).
- Sounds: you can't upload audio. The code plays Sounds **by name from SoundService** (for example "UI Blip", "Punch 1".."Punch 4", "Roll", "Hurt 8-Bit"). I add sounds from the Toolbox and rename them. When you add sound hooks, tell me the exact names.
- **Bosses come last**, after the Colosseum polish.
- **No "press E" prompts** (they aren't mobile friendly): things pop up when you walk close to them. See "Walk-up pop-ups" in "What exists now" above.

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

## The heart, the potion and the bolt ✅

Everything about your own health, stamina and flasks sits in the middle of the bottom of the screen, as three pixel pictures in the heart's style (dark outline, glass, white shine, liquid that fills by how many squares are full, not by height). All drawn by `ReplicatedStorage/Vitals.lua`; previews `Docs/vitals_preview.png` (every state) and `Docs/vitals_drink.png` (a drink, moment by moment).

```
   HP 55/100   x3 [potion]   [ HEART ]   [ BOLT ]   Power: 12.4K
```

- **The heart** (always on; `Config.Heart`): moved from Hud into Vitals unchanged - slosh, spill, beat red when low, shatter at 0, mend on respawn.
- **The bolt** (in a fight; right of the heart): yellow electric liquid = your stamina. It follows the stamina closely (`Config.Vitals.Follow`) because you read it mid-fight. Full: sparks crackle off it (`Sparks`), with a burst when it fills up. Too little for what you tried (CombatClient's `noStamina`): the liquid blinks like a dying light and the outline goes red. A roll's invincibility window: it glows pale blue, fading back to yellow as the window ends. The surface crawls white and yellow and a white zap climbs through it now and then.
- **The potion** (in a fight; left of the heart): the heart's own red, with the count beside it (x3). On "Drinking" from the server the cork pops off, the bottle tips `Tip` degrees towards the heart and pours an arc of drops that land in the heart (the heart skips its own pour-in while this happens); it drains over about as long as the heart takes to fill, stands back up, and the next one is full and corked. The count ticks down with the server's number. None left: grey outline, see-through glass, no cork, dim x0; pressing R then makes it shake and the count flash red. A fresh Colosseum run (flasks refilled) bounces it back full.
- **The words move aside:** in the lobby HP and Power sit right beside the heart; in a fight they slide out past the potion and the bolt.
- In the intro CombatClient keeps the bolt and potion hidden (stamina is free there). Nothing about combat changed - it's only how the numbers are shown.
- **The drink animation** (I asked for "something nice and simple"): while you drink, CombatService puts `Drinking` (seconds) on your character, and every screen (CombatClient's "The drink, as everyone sees it") animates any character with it - a little red potion (bottle, glass neck, cork; only on that screen, welded to the right arm) comes up to the chin, tips back with the head back and a couple of gulps, then is put away. Made in code on the R6 `Right Shoulder` and `Neck` joints (their `Transform`, set after Roblox's animations each frame, blended from whatever the arm was doing), no uploaded animation; a non-R6 body just doesn't show it. Preview `Docs/drink_preview.png`; test `test_drink.luau`.
- Tests: `test_vitals.luau` (see Testing tips).

**The new GUI (being discussed, NOT decided):** the old screen was made for the old game (armour gear, selling loot, three shops). Proposed: a top bar (level + XP bar, Coins, Arcade Tokens with a [+] for the token shop), four big buttons on the left (ROLL, BAG, SHOP, QUESTS, with red dots when something's waiting), the heart cluster above, the equipped weapon and its mastery bar beside the heart, an event-boss timer only in its last 15 minutes, and phone-first sizes. Open questions I haven't answered yet: cut stat points (level alone makes you stronger)? Does ROLL open the spin anywhere or walk you to the machines? Keep the chunky outlined look or go fully pixel-arcade?

## The Colosseum (what's built so far)

A wave arena for farming XP and coins.

### Getting in and out
- In the lobby there's a small sand-castle colosseum.
- Walk onto the bridge to its little door and the **difficulty pop-up** opens (see "Difficulty" below). Pick one, press **ENTER**, and you shrink bit by bit, Mario-pipe style, and appear inside the real arena far away (centre `(-2600, 0, 0)`, radius 82, built at 2.6× scale by the same `sandColosseum` function). There's no prompt: the bridge has a walk-up box (`Activity` = "ColosseumEnter"), and the server sends you in only through the ENTER button's Action "ColosseumEnter".
- The client does the teleport animation (`PipeIn`/`PipeOut` events). The server sets `MoveTo`/`MoveUntil` first.
- Walk up to the exit gate and a small **"LEAVE THE COLOSSEUM?"** check pops up (LobbyActivities `LeaveCheck`, ScreenGui `ColosseumLeaveCheck`: "Your run ends here.", STAY / LEAVE; walk-up box `Activity` = "ColosseumLeave", 5 studs deep in front of the gate, so where you arrive, 8 studs in, is outside it). LEAVE calls the Action **"ColosseumLeave"**: the server's `canLeave` only allows it within 32 studs of the gate (the gate part is tagged `ColosseumExit`), unless the run is cleared (then the CLEARED screen's LEAVE works from anywhere). Walking out heals you.
- If you die in there, you respawn in the lobby.

### Quest
- **"Beat 5 Waves"** (`Config.Colosseum.QuestWaves`), shown in a quest tab on the right like Blox Fruits, with one chunky block per wave ("(2/5)", then "(5/5) DONE!"). It's a whole run: it's paid when the King falls, on the CLEARED screen ("QUEST COMPLETE! +XP +coins", with the "Quest Complete" sound), at the run's difficulty: `QuestPower` 0.5 of the level gap and `QuestCoins` 150 + 30/level, x the difficulty's reward. It starts over with the next run (RUN AGAIN, or coming back in). (Without runs, `EndsRun = false`, it pays with a "QuestDone" banner every 5 waves instead.) The old "Defeat 10 Dummies" is gone.
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
- **Reward:** 15× a straw dummy's Power and coins (x the difficulty's reward). His minions crumble when he dies (no reward). A longer break (`WaveBreak` 4.5s) follows (only without runs).
- **Code:** `spawnDummy(s, kind, spot, level, opts)` now makes EVERY dummy (waves, the King, minions). The King has attributes Kind="King", NoBar, Boss (never out of sight for lock-on), State, Phase, Move. His hit shape (`CombatService.SetTargetShape`) makes him punchable from the sand up to his head; it's cleared when he dies or the session ends.
- **Screen:** LobbyActivities has the King's boss bar (`ColosseumBossBar`, 8-bit, RetroSkip), the BOSS WAVE / THE KING IS FURIOUS! / THE STRAW KING FALLS! banners, camera shakes through CombatClient's `CombatCameraKick` BindableEvent, his sounds and music (the "Music" SoundGroup is faded down while his plays, in its own "KingMusic" group). BossIntro has his portrait and lines. Preview: `Docs/straw_king_screen.png`.
- **Sounds (by name in SoundService, first one found is used):** Horn "Boss Wave Horn"; Land "Straw King Land" or "Boss Slam"; Roar "Straw King Roar" or "Boss Wake"; Spin "Straw King Spin" or "Boss Wave"; Summon "Straw King Summon" or "Boss Wail"; Death "Straw King Death" or "Boss Death"; Victory "Victory Is Ours (a) Sting"; Music "Straw King Song" or "Slime boss song".
- In the headless tests a fight takes about 50-65 seconds for a player at his level with no gear.

### Runs (a mini dungeon) and kill streaks ✅
- **Runs:** a run is 5 waves (`Config.Colosseum.King.Every`, `EndsRun = true`); wave 5 is the King. When he falls the run is **CLEARED**: the server times it (from wave 1 arriving), `PlayerService.RecordColosseumClear(player, seconds, diffId)` saves `data.Colosseum = { clears, best, bonusDay, pick, wins, bests }` (clears/best over every difficulty; `wins`/`bests` per difficulty, e.g. `wins.Hard = 3`; old saves had every clear counted as Normal when loaded), and the **first clear of each day** pays `ClearBonus` (0.5 of the level gap in Power, 150 + 15/level coins; `Config.colosseumRewards().clearPower/clearCoins`), x the difficulty's reward. Then nothing happens until the player chooses on the COLOSSEUM CLEARED screen (LobbyActivities `ClearScreen`, preview `Docs/colosseum_cleared.png`): **RUN AGAIN** (healed, flasks refilled via `CombatService.RefillFlasks`, wave 1 two seconds later) or **LEAVE** (the normal pipe-out, allowed from anywhere only while the run is cleared). The buttons go through PlayerService's `Action` RemoteFunction: ColosseumService registers "ColosseumAgain" and "ColosseumLeave" with `PlayerService.AddAction`. Dying mid-run still sends you to the lobby.
- **Kill streaks** (`Config.Colosseum.Streak`): kills in a row without losing health (ColosseumService watches the Humanoid's HealthChanged). Every 5 kills adds +10% to each kill's pay, up to +50%. It carries on between runs and ends when you're hurt or leave. The screen shows "x12 STREAK +20%" beside the wave box ("WAVE 3/5"), a banner every 5, and "STREAK LOST" if a streak of 5+ breaks.
- "Best wave" was dropped (runs always end at 5): the best clear time replaces it.
- **Spawning:** a new dummy (and the King) is parked out of sight 200 studs up (`PARKED`) until its turn to drop in, and lands at `e.land`. It must never stand on the sand first and then vanish (that was a bug).
- **The pipe sound:** LobbyActivities plays `Config.Colosseum.PipeSound` ("Pipe" / "Mario Pipe" / "Warp Pipe") going in and popping out.
- **Colosseum sounds** (`Config.Colosseum.Sounds`, names + volumes): the server sends `"Sfx", key, position` for dummy moments (Land, Slam, Poof, Charge, Throw, HayLand, Clang, Blink); the client adds WaveHorn, Cheer, Reward, Collect (the coins landing: "Coin Collect", borrowing "Reward Pop" until that's added) and Quest. While inside, `Config.Colosseum.Music` ("Colosseum Song") plays and the looping crowd (`CrowdSound`) murmurs; the King's song takes over in his fight; the lobby's "Music" SoundGroup is ducked under both. All are warmed up and listed in the Output sound report. ("coin2" and "dummy punch" in SoundService are deliberately unused.)

### Difficulty: Normal / Hard / Nightmare ✅
- **The numbers** are in `Config.Colosseum.Difficulties` (id, name, health, damage, extra dummies per wave, pace, reward, angry, color):
  - **Normal** (green): everything x1.
  - **Hard** (orange): dummies and the King x1.4 health, hits x1.5 damage, +1 dummy per wave, dummies 15% faster (`pace` 0.85 shortens their rests and hops, NOT their red warnings), pays x2.
  - **Nightmare** (red): x2 health, x2 damage, +2 dummies per wave, 30% faster, **the King is angry from the start**, pays x3.5.
  - "Pays" multiplies everything the run pays: each kill, the quest and the first clear of the day.
- **Unlocks:** Normal is always open; each one opens after clearing a run on the one before (`Config.colosseumUnlocked(data.Colosseum, id)`, used on both server and client). The CLEARED screen says "NIGHTMARE UNLOCKED!" when a clear opens one.
- **Picking, going in:** walk up to the mini colosseum's little door in the lobby (onto its bridge) and a **pop-up** opens (LobbyActivities `DifficultyMenu`, ScreenGui `ColosseumDifficulty`): a card per difficulty with what it does, what it pays, your clears and best time on it, and PICK / PICKED / LOCKED ("Clear a HARD run first"). Clicking a card (or its button) only picks it on your screen; the one you went in on last time starts picked. The big **ENTER** button (in the picked one's colour) calls the Action **"ColosseumEnter"** with the pick: the server checks you can go in (`canEnter`: beside the door, not already in or on the way) and that the pick is open to you (`PlayerService.SetColosseumPick` validates and saves `data.Colosseum.pick`), then sends you down the pipe; if it refuses, the pop-up stays open and says why. It closes with the X, when you step off the bridge, or as you go in. Preview: `Docs/difficulty_menu.png`.
- **Picking the next run:** the difficulty buttons on the CLEARED screen call the Action "ColosseumDifficulty" (saved the same way). A run keeps the difficulty it started on: a pick made mid-run (only a modded client could) waits for the next run. Preview: `Docs/colosseum_cleared_hard.png`.
- **Screen:** the wave box shows the run's difficulty after the wave ("WAVE 3/5  HARD", RichText, in its colour, with a border in its colour), and a new run's banner says "HARD RUN BEGINS!".
- (The DIFFICULTY board that stood beside the arena's exit gate is gone: the pop-up replaced it.)
- **Server:** the session's `s.diff` is set when wave 1 comes in (a run keeps it). `spawnDummy` multiplies health, `dmg(s, share)` wraps every hit on the player, `spawnWave` adds `extra`, `e.slow` includes `pace` (not for the King), `OnKill`/`FinishRun`/`PayQuest` multiply the pay, and `kingBrain` calls `getAngry` right after his entrance when `angry`.

### Reward feel ✅ (no chests: they're being reworked later)
- Every kill sends `"Kill", power, coins, textPos, { from, worth, king }`. Besides the "+XP / +coins" pop-up, LobbyActivities' `Loot` bursts gold coins (flat spinning squares) and green neon XP gems out of the dummy: they pop out, bounce once on the sand, then zip into you (30 steps a second, 8-bit). How many depends on `worth` (the kind's reward x the difficulty's; the King's is a big shower of 40+). Each one that lands ticks (the Collect sound, rising in pitch through a chain, at most ~16 a second) and bumps the HUD's coin counter (Hud's "Coin" frame) or level bar ("GoalBar") with a `CollectPop` UIScale. At most 120 fly at once; leaving the Colosseum clears them. Client-only: the server paid the moment the dummy fell. Preview: `Docs/reward_shower.png`.
- `Config.Audio.Music` is now 0.7 (the music was turned down on request).

### Lobby performance
- Measured with `Tools/HeadlessTests/lobby_count.luau` (parts per lobby piece; `-a client` adds what RetroWorld builds on your screen) and `fx_cost.luau` (how much LobbyFX moves a second, standing at the spawn). The lobby is ~15,400 parts from LobbyBuilder (the island and sea alone ~7,100, of which ~2,000 are foam) plus ~3,800 of RetroWorld detail (cobbles, bricks, grass) on each screen, and 82 lights.
- Done: parts under 4 studs on their longest side cast no shadow (LobbyBuilder, end of `Build`: ~5,000 parts; 9,700 -> 4,800 casting shadows). LobbyFX moves everything with `BulkMoveTo`, skips far-away things, and only moves a wave or a palm when its 8-bit step changes; FX spin/bob steps 20 times a second, pulses 20 a second, far foam (200+ studs) half as often in 1-stud jumps, palms sway in 1-degree steps. Result at the spawn: part moves 45,900 -> 8,500 a second, see-through changes 15,900 -> 2,900 a second.
- The lobby's spawn pad (`LobbySpawn`) is invisible and non-solid now: the glowing cyan pad flickered through the path's cobbles. RetroWorld's save star still marks it.
- Still possible if it's needed: fewer foam pieces, fewer lights, fewer RetroWorld cobbles, or turning on streaming.

### Lobby tidy-up (building inconsistencies)
- Checked with `Tools/HeadlessTests/lobby_dump.luau` (every lobby part as JSON), `check_lobby.py` (things floating, touching nothing, plants poking into walls, bits on the paths, faces that flicker) and `render_lobby.py` (draws the lobby from any camera). Before/after: `Docs/lobby_fixes.png`.
- **Blue paths:** the cobbles were SmoothPlastic, which reflects the blue sky. RetroWorld's `cobble()` / `cobblePlaza()` slabs and cobbles and the curbs (`Curb`, `PlazaCurb`, `CurbPost`) are matte `Plastic` now (`MATTE`).
- **Floating bits:** the banners and torches on the inside of the island's walls hung 0.4 studs off the wall; they sit flat on it now (`buildDecor`'s N/S/W/E). Flowers' blooms sit on the grass, or on a leafy clump when they're over one (they used to hang in the air).
- **Moved so they don't poke into things:** a pine (-48, 160, clear of the south gate's tower), two rocks (48, -104) and (-92, 160), a flower patch (13, 138, off the lamp by the road), and the farm tree (95.5, 75.5, a little smaller: clear of the cottage's roof and the fence).
- **Flicker (two faces in one place):** a tree lump's underside, the banner trims (castle and mini colosseum, a hair wider than the cloth), the castle gate's jambs, the angel's robe, the moss on the stone walls (`mossDepth`: each pixel of moss its own depth), the paving lines, the log steps' edges and the pier's plank lines. The curbs' corner posts (`CurbPost`) were left orange brick; they're dark stone like the curbs now.
- **Left alone on purpose:** the Pet Sanctuary (its bush pokes into the corner tower; it's getting redone later).

### Recent fixes (please verify in play)
- Players sinking into the floor after reset/death. LobbyActivities `keepFeetUp` watches your feet against the floor, raises the ControllerManager's `GroundController.GroundOffset` (or R15 HipHeight) by the gap, and lifts the body. **The character uses Roblox's ControllerManager**, not classic Humanoid movement.
- **Floating in arenas (I reported it in Kongo's arena):** that same `keepFeetUp` measured the lowest CORNER of any body part and only lifted, never lowered - so a sword lunge (the stance lowers you until the tilted legs' ends touch the floor, poking a foot's corner 0.38 in) or a roll looked "sunk" and raised you permanently. Now it only looks at the legs (the middle of their bottoms), only while you stand still with straight legs, lets you back down if you're floating after one of its own lifts (never below where it started), and never lifts more than 3 studs in all. `test_feet.luau` checks it (the old code fails its lunge and roll checks).
- The gap behind the stands is filled (`StandFill` parts).

## The intro: Oozlet ✅

A brand-new player's first minute, from the growth plan we worked out (step 1: "get a boss into the first minute"). Preview: `Docs/intro_preview.png`. All the numbers and words are in `Config.Intro`.

- **The dark (like Undertale's start):** behind the title screen, the player is put by the fountain (`SpawnAt`) and everything but the fountain and the plaza goes dark - a black box round the plaza on their screen only (Neon black walls, ceiling and floor; solid, so the camera never swings outside it), everything outside it hidden with `LocalTransparencyModifier` (and what's stuck on those parts: decals, signs, sparkles), the air turned black, and pale 8-bit mist blocks drifting at the edge (they melt when the camera's close). No HUD or other screens, none of Roblox's buttons, no other players, no music; the camera can't zoom out past `Zoom`; an invisible fence keeps you on the plaza.
- **Oozlet:** Oozark's baby - a blocky green slime with big eyes, rosy cheeks and a tiny gold crown - happily hopping round the fountain. Stand still for `Bump` seconds and it hops over and bumps you (a heart pops up).
- **The words:** HIT THE SLIME! builds up letter by letter (each letter scrambles through symbols, then locks in with a blip), a pause, then the "!" slams down with a BOOM. Then the words throb like a heartbeat and flash, and react: AGAIN! HARDER! YES!! KEEP GOING!! ... ROLL!! ... NICE ROLL! ... IT'S CRACKING! ... FINISH IT!!! A small line underneath says how (click / tap / gamepad). Punch before the words are up and they snap in, BOOM and all.
- **The fight** (IntroService decides everything; Oozlet has your UserId as `Owner`, so it's only yours):
  - Your first punch wakes it: angry face, a "!", its bar drops in at the top, its song starts (`Music`: the first of "Oozlet Song", "Slime boss song", "Colosseum Song" in SoundService).
  - **The lesson:** its first slam leaps up over you and hangs above a red circle (it can't be hit up there) until you ROLL - walk away and it drifts over you again. On phones the ROLL button throbs. Then it drops, dizzy: NOW HIT IT! (After 12s it gives up and drops anyway; after two tries it moves on.)
  - Then it hops after you and slams when you're close (a red circle fills as it rises).
  - At half health it **cracks** (can't be hurt for a moment, pushes you back, cracks glow on its shell) and gets faster, sometimes **bouncing** at you three times (a small red circle each).
  - It never takes you below `Floor` (30%) of your health: **you can't lose**. Stamina is free (there's no stamina bar in the intro).
  - It **pops** into pixels, its crown bounces away, and a **chest** drops out of the sky and bursts open: +1 OOZLET'S CHEST.
- **The reveal:** the mist rolls back over `Reveal.Time` seconds and the lobby builds itself round you - the island's ground unrolls under the mist and every piece pops in (in 8-bit steps) as it passes. Then the screen blinks, and we're past the castle walls looking up at **the Spire building itself out of nothing**, bottom to top: BOOM, **OOZARK AWAITS...** A blink back, and everything returns: your HUD (LEVEL UP!), the music, the other players. (The shot looks at the middle of the tower, under the blue flame in its crown - `FlameOrb` - and RetroWorld's beacon shoots up out of that flame, with its runes turning just above the crown's spikes: it used to start at a spike on the crown's rim, off to one side, and looked odd. `Docs/spire_beacon.png`.)
- **Rewards:** Oozlet's Chest and 100 coins when it pops; enough Power to be at least level 3 once the lobby is back; full health; a toast saying to open the chest in your bag.
- **Who gets it:** brand-new players only (`IntroDone` in their save; an old save with any Power counts as done). **In Studio it never starts by itself** (I asked for this: it played on every Studio Play, which got annoying - Studio often can't save, so every Play looked like a brand-new player) - `Config.Intro.InStudio = true` brings that back. The dev console (see "The dev console" below) has a **"DEV: Replay Intro"** button that plays it again from the start (it pays its rewards again).
- **Never stuck:** if the fight breaks on the server, or anything breaks on the player's screen, everything is put back and they play on normally (no reward; they get the intro next time).
- **How it plugs in:** the player attribute `Intro` = `"Void"` (dark, Oozlet happy) / `"Fight"` / `"Reveal"` / nil (over), and `IntroChecked` once the server has decided. CombatService and CombatClient fight while it's "Void" or "Fight"; BossClient keeps the lobby music off, LobbyActivities keeps its pop-ups shut, RetroWorld keeps its flavour text quiet while `Intro` is set. The screen tells the server only "IntroLook" (I can see: the bump waits for it), "IntroDone" (the reveal's finished) and "IntroFailed" (Actions).
- **Sounds** (by name in SoundService, each with a built-in Roblox fallback): Blip "UI Blip", Boom "Boss Slam", Hop "Dummy Land", Squish "Boss Splat", Wake "Boss Wake", Slam "Boss Slam", Crack "Boss Break", Pop "Boss Death"/"Dummy Poof", Chest "Reward Pop", Win "Quest Complete", Awaits "Boss Wake". Add a Sound named **"Oozlet Song"** for its own music.

## Floor 2: Tuber, then THE BRUTE ✅

A parody of Mario's Pokey with his own name: **two health bars, two fights**. Round 1 is **Tuber**, a chubby potato-shaped stack of three cactus blocks with a pink flower - easy on purpose, so players think he's a joke. When his first bar runs out he POWERS UP into **THE BRUTE, THE CACTUS KING**, a giant cactus golem who fights from a distance. I chose the name because TUBER and BRUTE are the same letters: in the cutscene they swap places, and THE slams down next to it. Previews: `Docs/tuber_preview.png` and `Docs/tuber_poses.png`. All his numbers are in `Config.Bosses[2]` (`PhaseAt` = where the first bar ends; `Attacks` = both rounds' moves, `Phase` 1 or 2; `Moves` = the Brute's hop, cornered, stun, rage).

- **Round 1 (little Tuber):** Wobble Bonk (red wedge), Clumsy Topple (red lane; then he lies there: free hits), Needle Sneeze ("ah... ah... ACHOO!": a jumpable ring), Bounce Stomp (red circle) and every third move **SPLIT!** - three buddies spin-dash at you as spiky balls (each bounces once off a rock or the edge), sit there dizzy (they share his health: punch any of them) and hop back into a stack. The server publishes the buddies' paths as slots; both sides use the same sums (`splitPos`). If his first bar runs out while he's split up (you're punching the buddies, after all), the server puts him back together where they are on average (inside his leash: they can roll right out to the rim) and the body draws them hopping there (`placeRejoin`) before he flops.
- **The power-up** (`BreakTime` 9 s, BossService's break; nobody can be hurt): he flops over, his flower wilts, the music stops; the ground rumbles, the sandstorm whips up (the body's `stormWant` hook), every `DuneCactus` in the arena rips out and flies into him (only on your screen; put back on a reset), the golem slams together piece by piece, the crown drops on, his eyes light up; the TUBER letters shake, swap into BRUTE and THE slams down (`TuberTitle` ScreenGui, driven from the clock); he roars - "THE CACTUS KING", "THE DESERT BOWS" - and the animals at the `DuneLookout` spots bow. The animals turn up from 5 s in (camels walk up onto their ledges - side-on, heads turned to watch, in red saddle blankets so they show against the sandstone - meerkats pop up, vultures glide into the dead trees, lizards scurry onto rocks), and for a second the camera looks out at the nearest camel through a long lens (`watchShot`: `kit.shot` with a narrow field of view) before cutting back to him for BRUTE. His second bar fills as he roars and SANDWORMSONG slams in (the body's `barLook` and `music` hooks). The camera swoops round him the whole time (`kit.shot` asks CombatClient: its `CombatCutscene` event - CombatClient still owns the camera and gives it back exactly as it was). BossIntro switches to the Brute's voice (`becomes = "Brute"` in his lines) and he speaks once it's over.
- **Round 2 (THE BRUTE):** get within 16 studs and he **Root Hops** away (it recharges: `HopAt`; his roots wriggle when it's ready). Catch him while it's recharging and he's **Cornered** (panics: free hits), then Shove Burst + hop. Ranged: Needle Volley, Desert Rain, Spine Lance (rocks stop needles and the lance). Planted (the server makes them in `Workspace.TuberProps`, never inside his model): **Cactus Walls** (invisible solid blocks + a punchable weak spot, 2 punches - `MinHealth` makes the first punch take only half), **Needle Turrets** (2 punches), **Prickly Buddies** (1 punch), **Quicksand** (drags you on your screen, nibbles on the server via BossService's puddles). Breaking the last of his walls and turrets (after at least 2) **STUNS** him (5.5 s: enough to run to him). **Rage** at 30% of his bar: more of everything, his walls creep toward you.
- **The end:** he crumbles into rolling cactus balls; tiny Tuber pops out and stomps off. Banner: THE BRUTE VANQUISHED (`VictoryName`).
- **The arena** (`DunesBuilder`): the worm's seal, lair, platforms, pillars and ribcage are gone; cacti (`DuneCactus`, non-collidable, each part under 14 studs so RetroWorld's decorations don't float when they fly), boulders (`DesertRock`, `Radius`: bounce and cover), animal lookouts (`DuneLookout`, `Kind`), Tuber's garden, a cactus-flower gate sign; the model has `FightRadius`.
- **Loot:** unchanged on purpose (I'm reworking loot): floor 2's chest still drops the Duneworn/Devourer's sets.
- **Sounds:** the worm's own (SandRoar, SandWhip, SandRumble, Worm Erupt/Slam/Crack/Charge/Devour/Death); music "Tuber Song" (round 1, not added yet) and "SANDWORMSONG" (round 2).
- **Checked by** `test_tuber.luau` (full, attacks, reset, duo, timing, powerup, split, props, corner - server and screen) and the 7 `tuber_*` golden traces.

## Floor 3: Knight Burrowmore ✅

A knight of the shovel - a parody of Shovel Knight with his own name ("Knight Burrowmore, the Honourable Digger"), colours and curly horns - in a souls-like fight: every move has ONE clear wind-up, ONE way to dodge it and a moment afterwards when he's open ("you fight him and you learn him"). No parrying, nothing the player has to do but hit, roll and move. Previews: `Docs/burrowmore_preview.png` (the fight) and `Docs/burrowmore_poses.png` (a pose sheet). All his numbers are in `Config.Bosses[3]`.

- **The arena, the Glimmer Dig** (`DigBuilder`, centre `(-2600, 0, 2600)`): a round floor of packed dirt (84 studs out to the invisible wall, a wooden fence just outside) on sunny 8-bit plains; a stone gate south with the fog way out, a glowing checkpoint orb (a Shovel Knight nod) and a sign; his campfire (east) and striped tent (west); coin piles, open chests, gem rocks, dirt mounds with spare shovels; hills, trees, a purple castle on a far hill, floating dirt islands, clouds and blue mountains. `Config.Spire.Floors[3].ambience`: a bright afternoon, a little drifting dust (`ArenaAmbience` now takes `Grains` and `Clouds = false`). No acid rain (`Weather = "Clear"`).
- **The fight** (`Bosses/Burrowmore.lua`; he's a surface boss, so BossService's shared brain chooses his moves by distance): Shovel Drop (the red circle under him follows you, flashes and locks: roll just before he lands; he bounces, then tugs his shovel out), Triple Pogo (three hops, dizzy after), Shovel Swing (a red wedge), Dirt Fling (a fan of clods), Anchor Toss (relic: "item get!", swung, lobbed onto you, stuck: a big opening), Fire Stick (relic: fireballs along red strips; jump or roll them), Charge Dash (a red lane; hitting the edge of the dig dizzies him), Taunt (free hits). **Phase two "No Quarter!"**: shoulder plates fly off, gold cracks, faster; Delayed Drop (hangs at the top after the lock to catch early rollers), Swing into Drop, Gem Rain (treasure into marked circles while he keeps fighting; its own attributes `RainAt`/`RainK`/`Rain1..`), and the **Shovel Meteor** (the first time below `MeteorAt` 30%: out of sight, a huge shadow in the middle - get to the edge - then stuck in the ground for `Stuck` seconds).
- **Can't be punched high in the air**: his file gives CombatService his body shape (`SetTargetShape`), using the same jump sum (`jumpHeight`) the screen draws him with.
- **The end:** down on one knee (BossIntro's last words: "You dig... with honour... the treasure... is yours..."), a pop into pixels, and a treasure chest bursts up out of the dirt. Reward: Burrowmore's Chest (floor 3 in `Items`: sets Spade Knight's and Relicbound, levels 40-60, a Secret "Very First Shovel").
- **The dodge windows are checked** by `test_burrowmore.luau -a timing`: a roll as a drop's circle locks dodges it, a roll a second early doesn't; the delayed drop punishes the roll at the lock and lets the one as he falls through.
- **Sounds** (by name in SoundService, all optional - missing ones borrow Oozark's through `SOUND_FALLBACK` in BossClient): Burrowmore Wake, Burrowmore Jump, Burrowmore Land, Shovel Swing, Shovel Dig, Dirt Land, Relic Get, Anchor Throw, Anchor Land, Fire Stick, Burrowmore Dash, Burrowmore Crash, Burrowmore Laugh, Gem Land, Shovel Meteor, Armour Crack, Burrowmore Death. Music: "Burrowmore Song".

## Floor 4: Kaze, the Headband Hero ✅

A wandering martial artist - a parody of Ryu with his own name, look and moves - who fights like a **fighting-game character**: a KI meter, specials that cost a bar, charging and canceling. Previews: `Docs/kaze_preview.png` (the fight) and `Docs/kaze_poses.png` (a pose sheet). All his numbers are in `Config.Bosses[4]` (including `Ki`, `Cancels`, `Tired`, `Charge`, `Chain`, `SuperAt`, `Movement`).

- **The arena, the Rooftop Dojo** (`DojoBuilder`, centre `(2600, 0, 0)`): a square wooden floor (the invisible walls 62 out: the model's `Half` attribute) with a red border and a wind-swirl emblem, his tatami mat in the middle; **4 stone lantern pillars** at (+-27, +-27), tagged `DojoPillar` (attributes `Floor`, `Radius` 3.5, `Broken`; their parts are marked `Whole` or `Rubble`); a red torii gate south with the fog way out, a stone landing and stairs down into the clouds; the dojo hall north ("KAZE DOJO"), a gong, training posts, tall banners; paper lanterns on ropes, cherry trees shedding petals, stone lanterns; a sea of clouds, far purple peaks (two with pagodas) and a huge setting sun. `Config.Spire.Floors[4].ambience`: sunset, pink petals drifting on the wind.
- **His brain** (`Bosses/Kaze.lua`, `Boss.brain`, pcall-protected like Tuber's): picks a move by distance and by his meter (specials need a bar; he meditates more with an empty meter; blocked by a pillar, he avoids throwing into it). **KI** fills when his hits land (`Hit`), when you punch thin air near him (`Whiff`, through the new `CombatService.OnWhiff`), a trickle (`Passive`), and fast while meditating (`Focus`); round 2 fills it `Phase2` times as fast; a **ki flare** fills it to MAX once a round (`SuperAt` 70% / 25%). **Cancels** (3, then 5 a round): string into special, fake charge into dash, hop back out of a missed special (or out of a string with no ki), chain special into special (round 2). Out of cancels: **Tired** (free hits), then they refill. **Charging** (`Charge.Chance`): a special held for 0.55-1.1s is bigger (every special's numbers are pairs { not charged, fully charged }); two punches while he charges or meditates break it (**Stagger**) and knock ki off.
- **His moves:** PunchString (jab, straight, heavy; small red wedges), DashIn, KazeBlast (a ball of ki along a red lane; stops at a pillar), RisingDragon (a ring, then up; out of reach at the top), TornadoKick (a lane that locks; he spins along it), KiFocus, FakeCharge, and **Super** (full meter, cooldown 22s: leaps to the middle, a red fan follows you and locks, the beam sweeps 160 degrees; a player hidden behind a standing pillar is safe - the test is the ray from the middle to the player; every pillar inside the fan crumbles afterwards). **Round 2** mends the pillars, tears his gi, more cancels, chains.
- **Published for the screens:** `Ki`, `Cancels`, `CancelAt`/`CancelKind`, `WhiffAt`, `KiHitAt`, `KiFlareAt`, plus each move's slots and (specials) how long he charged in `ActN`.
- **His body** (`BossBodies/Kaze.lua`): the rig (gi, belt with flapping tails, bare arms, red gloves, spiky hair, the headband with two long tails simulated as little chains in the wind), every pose, afterimages, the ki ball, the beam (strands cut off by the pillars), the fan, pillar hints, crumbling pillars; **his KI meter** under the boss bar (3 bars, MAX, cancel diamonds, +KI / -KI pops); hints over his head ("TIRED! HIT HIM!", "PUNCH HIM TO BREAK IT!", "CHARGING! BREAK IT!"); `kit.bigText` screens ROUND 1 / FIGHT! / ROUND 2 / SUPER! / K.O.! / PERFECT! (no damage taken); `kit.shout` bubbles for his move names.
- **The end:** K.O.! - he falls on his back, his headband floats away on the wind, he scatters into cherry blossom petals. Reward: Kaze's Chest (floor 4 in `Items`: sets Windwalker and Ki Master's, levels 60-78, a Secret "Endless Headband").
- **Checked by** `test_kaze.luau` (full, attacks, reset, duo, timing, rules, super, and client mode) and 4 golden traces.
- **Sounds** (all optional; missing ones borrow Oozark's through `SOUND_FALLBACK`): Kaze Wake, Kaze Punch, Kaze Heavy, Kaze Blast, Kaze Dragon, Kaze Tornado, Kaze Charge, Kaze Cancel, Kaze Dash, Kaze Land, Kaze Focus, Kaze Stagger, Kaze Pant, Kaze Super, Kaze Beam, Pillar Crumble, Kaze Round Two, Kaze Death; the announcer (silent until added): Round One, Round Two, Fight, KO, Perfect. Music: "Kaze Song".
- **Shared additions he brought:** `Boss.onMove(E, dt)` (a say in where the boss stands each frame), `stepMovement`/`stepWaves`/`stepPuddles` in the kit, `CombatService.OnWhiff` and `CombatService.Launch` (a jump pad, for Gridlock), BossClient's `kit.bigText` and `kit.shout`, a scrolling Spire menu, and `Accent` in a boss's Config (the VS splash and its chest icon, when its own colour is too pale).

## Floor 5: Speedy Revvington ✅

A cocky red race car - a parody of Lightning McQueen with his own name ("Speedy Revvington, King of the Speedway"), number (57) and catchphrase ("Ka-VROOM!") - in a **DRIVE-BY DUEL**: like Elden Ring's Tree Sentinel he charges past you, turns and charges again, but as a cartoon. His face is his windscreen (big eyes that follow you, blink, squint, go dizzy) and his grin is on his front bumper. Previews: `Docs/revvington_preview.png` (the fight) and `Docs/revvington_poses.png` (a pose sheet). All his numbers are in `Config.Bosses[5]` (including `Car`, his box shape, and `Drive`, how he drives between moves).

- **The arena, Piston Speedway** (`SpeedwayBuilder`, centre `(0, 0, -2600)`): an oval racetrack shaped like a capsule - every spot within `Edge` (62) of the line from x = -`Spine` to +`Spine` (70) is track or infield (the model's attributes `Spine`, `Edge`, `Infield`, `Center`; the invisible walls are tagged `SpeedwayWall`). Asphalt with a white middle line, red-and-white curbs, a grassy infield with a big white "57" and a yellow bolt (nothing painted on the track is red, so nothing looks like a warning), a checkered start line under the **starting-light gantry** (parts `StartLight1..5`, lit on each player's screen for the countdown), a tyre wall and catch fence, packed grandstands of blocky fans under a striped roof, a press tower, pit garages either side of the tunnel you arrive through (north), a giant screen, a trophy, a blimp, and desert mesas, cacti and a water tower. `Config.Spire.Floors[5].ambience`: a hot afternoon, a little desert dust.
- **How he moves: `ReplicatedStorage/CarPath`**, shared maths for the server and every screen. He never walks: everything is a SEGMENT (a Line, an Arc round a centre, or a Spin on the spot with a skid slide) starting at a moment on the server's clock, published on his model (`SegK`, `SegT0`, `SegDur`, `SegA`, `SegB`, `SegC`, `SegE`, `SegBack`, then `SegId` last). The screens draw him exactly on it; a segment that arrives late (ping) melts in over a tenth of a second, and a flat-out line slides on until the next segment arrives (unless it ends in the wall). Drives whose start matters (a charge, the drive-by, the ring, the dash) are published a moment BEFORE they start, so every screen already has them when he sets off.
- **His brain** (`Bosses/Revvington.lua`, `Boss.brain` + `Boss.step`, pcall-protected): picks a move that suits where you are (`Range`, and `Facing`: Front / Side / Rear of him), then maybe CRUISES (circling you like a shark, or driving off to get room), then breathes. His hits use his box (`Car`): running people over (`carHits`), cones (honk, backfire), half-circles (whip, bump); CombatService gets his real shape (`SetTargetShape`: the nearest point of the box).
- **His moves:** Charge (the lane follows you until `Lock`, locks, he roars down it, brakes in a skid and turns round slowly - the opening; if the lane meets the tyre wall he CRASHES: dizzy for `CrashStun`), TailWhip (drives by beside you, whips his tail round a half-circle), WheelieSlam (a circle in front, then a jumpable shock ring), Honk (a cone in front), Backfire (a cone behind, and burning puddles), SideBump (hops sideways at you), Donuts (free hits), and in TURBO: BurnoutRing (laps you leaving a ring of fire, then dashes through the middle) and two charges in a row.
- **Published for the screens:** the segment, each move's slots (the lane, the whip spot, the puddles, the flames as they're lit, the dash), and `RaceStart` (the moment of GO!, set once per fight - not again after TURBO).
- **His body** (`BossBodies/Revvington.lua`): the car (tub, cabin, a bonnet that pops up in a crash, a spoiler that grows in TURBO, lightning bolts that glow in TURBO, "57" on his doors and roof, octagon tyres that turn and steer), his face (eyes with lids above and below, dizzy eyes, X eyes; a mouth with teeth and tongue; pink cheeks that puff for a honk), springs (pitch, roll, bounce), tyre smoke, skid marks, speed lines, nitro flames; every warning (the lane with marching arrows and a yellow ring where he'll crash, wedges, circles, fire, the shock ring, honk waves, flying tyres); the countdown (`kit.bigText` 3 / 2 / 1 / GO! with the gantry lights), TURBO!, FINISH! with YOUR TIME; **the race clock** under the boss bar; hints over his roof ("DIZZY! HIT HIM!", "SHOWING OFF! HIT HIM!"); his engine's looping hum; and you can't walk through his box (unless he's flat out: then he runs you over).
- **The end:** FINISH! - he sputters, a front wheel rolls away, his bumper drops off, X eyes, then checkered confetti. Reward: Revvington's Chest (floor 5 in `Items`: sets Speedster and Turbocharged, levels 75-93, a Mythic "The Golden Piston", a Secret "The Ka-VROOM Engine").
- **Checked by** `test_revvington.luau` (full, attacks, reset, duo, timing, crash, and client mode - which fails if any part of him, any warning or any of his screen words never gets drawn) and 4 golden traces.
- **Sounds** (all optional; missing ones borrow Oozark's through `SOUND_FALLBACK`): Revvington Wake, Engine Rev, Revvington Charge, Tire Skid, Revvington Crash, Tire Screech, Suspension Slam, Big Honk, Exhaust Backfire, Car Bump, Donut Screech, Fire Whoosh, Revvington Turbo, Revvington Sputter; silent until added: Crowd Cheer, Start Beep, Start Go, Checkered Flag, and Revvington Engine (LOOPING). Music: "Revvington Song".

## Floor 6: Gridlock, the Final Beat ✅

A living LEVEL - a parody of Geometry Dash's final level "Deadlocked", with his own name ("Gridlock, the Final Beat") and look: a giant black cube with glowing red edges, slanted yellow eyes, a jagged grin and little horns. He fights **ON THE BEAT**, in an arena that fights too. Previews: `Docs/gridlock_preview.png` (the fight) and `Docs/gridlock_poses.png` (a pose sheet). All his numbers are in `Config.Bosses[6]` (every time is in BEATS; `Bpm` is the tempo - set it to the song's, and `BeatOffset` to line it up).

- **The arena, The Final Beat** (`GridBuilder`, centre `(2600, 0, -2600)`): a 15 x 15 grid of 8-stud tiles (a faint dark chessboard) floating in a purple void; neon lines between the tiles (`GridUnder`, pulsed on the beat by the screens); eight yellow **jump pads** (`JumpPad`, on `BeatGrid.PADS`' tiles); the **ceiling grid** 44 studs up on four black pillars; the runway and a green portal where you arrive (south), "THE FINAL BEAT" over it. Far off: giant spikes, spinning saws (`GridSaw`), turning neon frames (`GridSpin`), floating blocks (`GridPulse`), chains, stars, his face in the sky and a red abyss below - one model, `GridBackdrop`, that the screens turn upside down for the gravity flip. The model's attributes: `Center`, `Tiles`, `TileSize`, `Ceiling`, `RunwayA`/`RunwayB`. `Config.Spire.Floors[6].ambience`: dusk and a purple haze.
- **The shared sums: `ReplicatedStorage/BeatGrid`**: the grid (tile <-> spot); the beat (beat k is at `BeatStart + k * 60 / Bpm`); the tile PATTERNS (Tile, Square, Ring, Cross, Checker, Stripes, Rings, Halves, Drop - each from a few numbers, published as short strings in `Tiles1..12` + `TilesK`, so every screen makes exactly the server's tiles); and his MOTION (Hold, Hop, Fly, Fall, Zig), published on his model (`MoveK`, `MoveT0`, `MoveT1`, `MoveA`, `MoveB`, `MoveH`, `MoveN`, `MoveE`, `MoveF`, then `MoveId` last). The screens draw him exactly on his move (a late one melts in over a tenth of a second).
- **The beat** starts with the level (the start of the wake, when the music starts): `BeatStart` and `Bpm` on his model, set once a fight (not again in round 2). BossClient starts a beat boss's song (any boss with `Bpm`) at the level's current moment (`TimePosition` = time since the wake), so the music and the tiles line up even for someone arriving mid-fight. Every move counts from the next beat at least 0.12 s away (`ActN`, except the portal's and the flip's), so every screen hears of it in time.
- **His brain** (`Bosses/Gridlock.lua`, `Boss.brain` + `Boss.step`, pcall-protected): a cycle - THE DROP every `DropEvery` moves, a PORTAL to a new form every `FormEvery` moves, in round 2 a gravity FLIP every `FlipEvery` moves - otherwise an attack that suits his form, gravity and your distance (`Form`, `Gravity`, `Range`), then a breather roaming on the beat (the cube hops, the ship sweeps round you, the UFO bursts after you, the wave zig-zags). Tile attacks hit whoever is on a lit tile as it spikes and not above it (spikes are `Height` tall: jump, roll, or be elsewhere); the swoop and the zig-zag run into people (`E.contact`); the UFO slam hits a circle. CombatService gets his real shape per form (a box, `SetTargetShape`). The jump pads throw people up (`CombatService.Launch`; `PadAt`/`PadIndex` tell the screens).
- **His moves:** CUBE: HopSlam (his 3x3 square lit at once, the hop on the last beat, then a ring of spikes), SpikeRows (a stomp, then rows along the straight lines - round 2 the diagonals too - a row a beat), StompChain (round 2: three hop slams a beat apart). SHIP: BombRun (a lane of tiles through you, a bomb a beat), Swoop (a lane aims, locks, he dives and skims - the opening). UFO: UfoSlam (bursts after you, the circle locks, SLAM, stuck), OrbRain (orbs onto lit tiles, one a beat). WAVE: ZigZag (a dotted zig-zag; he zooms along it leaving a wall of light for `Trail` beats). Any form: TilePattern (a pair that covers the grid between them: checkers, stripes, rings, halves). On the ceiling (round 2): CeilingDrop (a hop a beat after you, the square locks, he drops onto it and is stuck head-first). Not attacks: Drop (he rises to the middle; everything but the pads spikes, the runway too; he crashes: STUNNED for `Drop.Stun` beats), Portal (a new form, through a ring ahead of him), Flip (a gravity portal: up to the ceiling, or back down with a slam).
- **Round 2 (GRAVITY FLIP! at half health):** he becomes a cube and falls UP to the ceiling (`Gravity` = -1); it starts with THE DROP; he flips now and then, changes form faster and rests less.
- **His body** (`BossBodies/Gridlock.lua`): the cube (12 neon edges that flare on the beat, eyes that follow you, brows, horns, a jagged grin with mouth shapes grin/open/o/shut, X eyes, dizzy stars; a full flip on every long hop, squash and stretch, upside down on the ceiling); the SHIP (neon-edged, a flame), the UFO (a saucer with a neon rim, chase lights on the beat, a glass dome, the tractor beam) and the WAVE (a neon dart), him small inside each; **the level's tiles** (red warnings flaring on every beat - white on the last one - then 3-step pixel spikes; bombs and orbs falling onto theirs; the wall of light), reused parts made ahead while the level starts; portals, gravity portals, the swoop lane, the UFO circle, the drop line; the level moving to the music (the neon lines, the pads bobbing, green for the drop, bouncing when they throw someone; saws, frames, glows; the whole backdrop turning upside down); `kit.bigText` ATTEMPT N / DROP IN 3-2-1 / DROP! / GRAVITY FLIP! / LEVEL COMPLETE! (with ATTEMPTS); ATTEMPT N written in the level; **the % bar** under the boss bar; hints ("STUNNED! HIT HIM!", "STUCK! HIT HIM!"); and you can't walk through his box.
- **The end:** LEVEL COMPLETE! - he glitches, X-eyed, and shatters into little neon cubes; the grid lights up green. Reward: Gridlock's Chest (floor 6 in `Items`: sets Beatbound and Demon Geometry, levels 90-108, a Mythic "The Final Beat", a Secret "The Secret Coin").
- **Checked by** `test_gridlock.luau` (full, attacks, reset, duo, timing, drop, pads, and client mode - which fails if any part of him, any warning or any of his screen words never gets drawn) and 4 golden traces.
- **Sounds** (all optional; missing ones borrow Oozark's through `SOUND_FALLBACK`): Gridlock Wake, Cube Hop, Cube Slam, Spikes Up, Portal Whoosh, Ship Thrust, Bomb Drop, Ship Dive, UFO Burst, Orb Land, Wave Zoom, Drop Build, The Drop, Gridlock Stun, Gravity Flip, Jump Pad, Gridlock Break, Gridlock Shatter; silent until added: Attempt Start, Level Complete. Music: "Gridlock Song".

## Floor 7: Kongo, the Jungle Brawler ✅

A huge gorilla in a red tie with a big K on it - a parody of Donkey Kong, with his own name ("Kongo, the Jungle Brawler") and look. I asked for a **flat arena** where he **fights with the moves from his games**, and a **jungle village + waterfall** in the background. Previews: `Docs/kongo_preview.png` (the fight) and `Docs/kongo_poses.png` (a pose sheet). All his numbers are in `Config.Bosses[7]`.

- **The arena, Kongo's Jungle Village** (`JungleBuilder`, centre `(-2600, 0, -2600)` - it was first built at `(-2600, 0, 0)`, right on top of the Colosseum, and moved): a flat round clearing (the fight floor is a Part with its top at exactly y = 0 - the lesson from the Sunken Dunes: never Terrain for a fight floor), 70 studs to the wall, with 18 tiki torches round the edge (their flames tagged `JungleTorch`). Round it: 8 huts on stilts joined by rope bridges, two giant trees with treehouses, a totem, a big drum, banana stalls, barrel piles and crates, and 20 little monkey villagers (`JungleMonkey` models, attribute `Index`). Behind it (north): a cliff with the waterfall, its pool, mist and a rainbow, and a river looping round with a dock and canoes; palms, jungle trees, bushes and vines everywhere else. The gate is south: a "KONGO'S JUNGLE" sign over a vine curtain (the `ArenaExit` prompt, switched off on screens, plus the walk-up `AutoOpenZone`), and `ArenaSpawn`. `Config.Spire.Floors[7].ambience`: a sunny afternoon with a soft green haze, and the "Jungle Ambience" loop.
- **His brain** is the shared one (BossService picks by `Range`, `Weight` and `Phase`; breathers chase you); his moves are in `Bosses/Kongo.lua`. Several leave him open: a GIANT PUNCH that misses leaves him TIRED (slot 3 set; `Tired` seconds), and he's DIZZY after a ROLL or a SPIN (their recovery), shown as "HIT HIM!" / "DIZZY! HIT HIM!" over his head.
- **His moves:** GiantPunch (windmill wind-up of a random length - longer = bigger reach and damage; the lane locks at `Commit`, then he lunges down it hitting everyone in it; round 2 a wind-up over `Big` also sends a shockwave ring), HandSlap (3-4 slaps, `Gap` apart, each a shockwave ring from in front of him: jump or roll it), Roll (curls up, rolls down a lane at you, bounces off the clearing's edge onto a second lane; one set of hits for the whole roll), Spin (a helicopter spin drifting after you, hitting every `Rehit` seconds), Headbutt (a short lunge, close up), Barrel (2-3 barrels rolling down lanes at you: jump them - the hit checks your height), TNT (1-2 lobbed TNT barrels landing on circles; the second aims ahead of where you're running), Pound (a chest pound from far away: no hit, free punches). Round 2 only: CargoThrow (close up: grabs the nearest player in a wedge in front of him and hurls them; a miss leaves him open a bit longer) and Combo (HandSlap, then a Roll, then a GiantPunch).
- **Round 2 (GOING BANANAS! at half health):** he shoves everyone near him back, his face and eyes go red, the torches flare, and he adds CargoThrow, Combo and the ground-shaking punch.
- **How the screens know:** the usual `Action`/`ActionStart`/`ActN` and slots (`ActA`, `ActB`, `ActC`, `Act4`...): GiantPunch (`ActN` = wind-up time; slots 1/2 = the lane, 3 = set if he missed, 4 = the shockwave's spot), HandSlap (`ActN` = slaps; slot 1 = where the waves start), Roll (`ActN` = roll time; slots 1/2/3 = start, bounce point, end), Spin (`ActN` = spin time), Headbutt (slots 1/2), Barrel (`ActN` = barrels; barrel k uses slots 2k-1 and 2k), TNT (`ActN` = count; slot k = where it lands), Pound (`ActN` = time), CargoThrow (slot 1 = aim, slot 2 = where he caught someone). Shockwaves are server rings (`E.waves`) that jumping or rolling dodges.
- **His body** (`BossBodies/Kongo.lua`): blocky gorilla (knuckle-walking legs, long arms with big tan hands, a tan face and muzzle, heavy brow, hair tuft, red tie with a yellow K), the held barrel/TNT swung up round the front and over his head, the rolling ball (four crossed blocks = a pixel ball, with his face, tie, hands and feet showing), dizzy stars; warnings (the punch lane that grows with the wind-up, shockwave rings, roll lanes, the spin ring, rolling barrels, TNT circles with the barrel's arc, the grab wedge); the villagers (bobbing, cheering and waving on his wake, chest pounds and round 2, hands over their eyes when he loses) and the torches flaring in round 2; words: *YAWN*, OOH OOH!, GIANT PUNCH!, SPINNING KONG!, YOINK!, GOING BANANAS! / ROUND 2.
- **The end:** KONGO VANQUISHED - he wobbles, falls flat on his back and pops into pixels in a burst of bananas; the villagers cover their eyes. Reward: **Power only**. `Items.ByFloor[7]` is empty on purpose (I'm reworking loot and asked for no loot yet), so `PlayerService.AddChest` gives nothing for floor 7.
- **Checked by** `test_kongo.luau` (full, attacks, reset, duo, timing, tired, and client mode - which fails if any part of him, any warning or any of his screen words never gets drawn, or if the villagers and torches never move) and 4 golden traces.
- **Sounds** (all optional; missing ones borrow Oozark's through `SOUND_FALLBACK`): Kongo Roar, Kongo Chest Pound, Kongo Wind Up, Kongo Giant Punch, Kongo Slap, Kongo Roll, Kongo Spin, Kongo Headbutt, Barrel Throw, Barrel Break, TNT Boom, Kongo Grab, Kongo Pant, Kongo Hoot, Kongo Rage, Kongo Death. Music: "Kongo Song"; arena loop: "Jungle Ambience".

## Floor 8: Petalina, the Blooming Terror ✅

A giant cartoon flower - a parody of Cuphead's Cagney Carnation, with her own name and look - planted in the middle of a greenhouse garden. She never moves: "a dodge-everything shooter fight: weave through her attacks, then dart in to hit". Previews: `Docs/petalina_preview.png` and `Docs/petalina_poses.png`. All her numbers are in `Config.Bosses[8]`.

- **The arena, the Glasshouse Garden** (`GreenhouseBuilder`, centre `(5200, 0, 0)`): a square glass hall (brick base, glass walls in white frames, a pitched glass roof with stepped gable ends and a lantern on the ridge, sunbeams) around a round garden. The paving is the fight floor (one Part, top at y = 0); the flower beds are raised soil strips (0.4 up) whose edges step like pixels. **`ReplicatedStorage/GardenPlan`** is the shared shape: `Mound` 7, `Inner` 17 (the inner ring path), `Outer` 54 (the outer ring path), `Edge` 66 (the invisible wall), `PathHalf` 6 (four straight paths), `GardenPlan.safe(dx, dz)` (a path or not - exactly the built strips), `nearestSafe`, the petal loop (`petalPoint`, `petalTime`) and the Face Stretch's head path (`headPoint`). Round 2's brambles are built hidden in the beds' soil (models tagged `GardenThorn`: `Delay`, `Up`) and grown on each screen; butterflies are tagged `GardenButterfly`. The door is south, with the `ArenaExit` prompt (switched off on screens) and the walk-up `AutoOpenZone`.
- **Her brain** is the shared one (she's `MoveSpeed = { 0, 0 }`, and her own `Boss.step` keeps `E.chase` off, so breathers only turn her face). Her step also runs her FLYTRAPS (punchable props in `Workspace.PetalinaProps`: `Kind` "Flytrap", `Born`, `Grow`, and per bite `BiteWarn`/`BiteAt`/`BiteDir`/`BiteId`; `EndKind` Broken/Wither/Gone), the pollen clouds, round 2's thorns (`ThornsAt` on her model: standing on a bed - `GardenPlan.safe` false - stings every `Thorns.Tick`), the thorn rings (the shared `E.waves`) and her head. `CombatService.SetTargetShape` makes her stem punchable (radius `StemRadius`) and her head while it's down (`HeadRadius`).
- **Her moves:** SeedSpit (slot k = where seed k lands; the first `Sprout` sprout flytraps), Petals (slot k = the far end of petal k's loop; the loop is tipped so its way out crosses your spot; odd petals bulge left first), VineWhip (slot i = line i's far end; vines race out at `Speed`), Pollen (slot k = cloud k), FaceStretch (`ActN` = reach; slot 1 = the lane's end; the head dives and races down the lane, chomps, then lies there `Droop` seconds - punchable), RootRing (a circle round her, `fromBelow`), Sunbathe (free hits). Round 2: ThornRing (`ActN` rings, waves), SeedRain (slot i = drop i, on paths; the first `Sprout` sprout flytraps).
- **Her body** (`BossBodies/Petalina.lua`): a curved stem in segments, big leaves she uses as arms, a pixel-circle face (two crossed blocks) ringed with petals that fold into a bud, long-lashed eyes, rosy cheeks, a mouth with shapes (smile, o, wide, grin, chomp); round 2 dark petals, angry brows, fangs and stem thorns; the neck that stretches for the Face Stretch; the flytraps, the brambles, the butterflies; "HIT HER!" when her head is down or she's sunbathing; words HELLO, SWEETIE~!, CHOMP!, LA LA LA~, YOU TRAMPLED MY FLOWERS! / ROUND 2.
- **The end:** her petals drop one by one, her head bows to the floor, she pops into pixels, the brambles sink. Reward: **Power only** (`Items.ByFloor[8]` empty on purpose).
- **Checked by** `test_petalina.luau` (full, attacks, reset, duo, timing, droop, traps, thorns, and client mode) and 4 golden traces.
- **Sounds** (all optional; missing ones borrow Oozark's through `SOUND_FALLBACK`): Petalina Hum, Seed Spit, Seed Land, Flytrap Sprout, Flytrap Chomp, Petal Throw, Vine Burst, Pollen Puff, Petalina Stretch, Petalina Chomp, Root Burst, Petalina Giggle, Thorn Ring, Seed Rain, Thorns Spread, Petalina Evil Laugh, Petalina Wilt. Music: "Petalina Song"; arena loop: "Greenhouse Ambience".

**The boss lineup we agreed (parodies with new names, so no lawsuit; each fight unique - no wave spam, no just throwing itself at you):**
1. Floor 3: **Knight Burrowmore** (Shovel Knight) ✅ done (above).
2. Floor 4: **Kaze the Headband Hero** (Ryu) ✅ done (above) - chosen: **Option A, the Special Move Meter**, with **charging and animation canceling**: a KI meter (fills when he lands hits or you whiff near him; hitting him while he charges knocks it down); specials at 1 bar, shouted in pixel text - "KAZE-BLAST!" (floor fireball: jump/roll over), "RISING DRAGON!" (close uppercut: back off, punish the landing), "TORNADO KICK!" (spins across: roll through); he can HOLD a special to charge it (blue glow, rising hum; bigger move; open to hits while charging); he cancels punch strings into specials, fakes a charge into a dash (white flash), a cancel bar (3 a round; empty = guaranteed opening); full meter "SUPER!": a giant beam, hide behind one of 4 breakable pillars; phase two "ROUND 2 - FIGHT!": meter twice as fast, 2 specials chained, 5 cancels, tired longer when they run out.
3. Floor 5: **Speedy Revvington** (Lightning McQueen) ✅ done (above) - "Drive-By Duel", like Elden Ring's Tree Sentinel at the start but a cartoon car: drive-by swipe, skid-turn window, wheelie slam, honk, exhaust backfire, straight charge lane; phase two TURBO.
4. Floor 6: **Gridlock, the Final Beat** (Geometry Dash's "Deadlocked") ✅ done (above) - fights with the arena like a GD level: cube/ship/UFO/wave forms, neon tiles on the beat, jump pads, a drop stun window; phase two faster switches and a gravity flip.
5. Floor 7: **Kongo, the Jungle Brawler** (Donkey Kong) ✅ done (above) - a flat arena; he fights with the moves from his games (giant punch, hand slap shockwaves, rolling attack, spinning Kong, barrels and TNT, headbutt, chest pound); phase two he goes bananas (combos, cargo throw, a ground-shaking punch). Jungle village + waterfall arena.
6. Floor 8: **Petalina, the Blooming Terror** (Cuphead's Cagney Carnation) ✅ done (above) - rooted in a greenhouse garden; round 2 thorns cover the beds so you fight on the paths. Floor 9 (agreed, next): **Scribble**, the stick figure from the Animator vs. Animation cartoons - a "4th-dimensional" being who fights the game itself. Ask me before building it (I'll want to go over the moves and arena first).
7. Saved for the top floors (more hype): **Sans** (Undertale: a dodge-everything bullet-hell of bones and laser skulls) and the **Ender Dragon** (Minecraft).
Rules for picking: contrasting fight styles from one boss to the next (not two of the same kind in a row - e.g. no Tetris right after Geometry Dash), and **no more Mario references**. I want at least **20 bosses**.
Rough levels 45 / 60 / 75 / 90 / 105 / 120 (+15 a floor). Build one boss at a time, with its arena (arenas depend on the moves).

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
- **Worm boss:** reworked to be more fun and less laggy - and then **replaced** by Tuber (floor 2): worms just didn't work and lagged. Its sounds and "SANDWORMSONG" live on in Tuber's fight.
- **Heart health display:** a liquid heart that spills.
- **Stamina and flasks redone to match the heart:** the green stamina bar and the "🧪 3" box were replaced by a pixel **lightning bolt** (stamina, right of the heart) and a pixel **potion** (flasks, left of the heart). I picked this over pixel wings (too complex) and a plain tube under the heart. See "The heart, the potion and the bolt".

### Security audit
I asked for a full client-exploit audit: remote abuse, economy duplication, teleport and speed hacks, combat spoofing, inventory manipulation and privilege escalation. The fixes are in (see "Security rules" above). Keep everything server-authoritative.

### Other things I asked about
- **Claude plans and effort:** use a high effort setting for careful restructures (like the boss split), and medium for small tweaks. Don't ask for huge multi-feature jobs in one go.
- **Sounds:** you can't make audio. Hook sounds by name in SoundService and tell me the names.

## What to do next (the approved plan, in this order)

The Colosseum polish plan was:
1. enemy types ✅
2. difficulty ✅ (a pop-up at the Colosseum's door)
3. boss wave ✅ (the Giant Straw King, see above)
4. streaks ✅
5. juice (skipped for now: I felt the Colosseum is polished enough)
6. reward feel ✅ (without chest drops: chests are being reworked later)

The build order is 1 → 3 + 4 → 2 → 5 + 6.

1. ~~**Boss wave every 5 waves: the Giant Straw King.**~~ ✅ Done (see "The boss wave" above).
2. ~~**Kill streaks and best wave:**~~ ✅ Done, as 5-wave runs with a best clear time, runs cleared, a daily first-clear bonus, and kill streaks (see "Runs" above).
3. ~~**Difficulty board**~~ ✅ Done: Normal / Hard / Nightmare, picked in a pop-up at the Colosseum's door as you go in, and on the CLEARED screen for the next run (see "Difficulty" above). (It started as a board in the arena; I asked for a pop-up instead.) The quest became "Beat 5 Waves" at the same time.
4. **Juice** (skipped for now, maybe later): the crowd cheering kills, throwing hearts (heal pickups) and coin bags onto the sand. (The wave horn already exists.)
5. ~~**Reward feel**~~ ✅ Done: coins and XP fly from the dummy to you (see "Reward feel" above). **No chest drops**: chests are being reworked later.

**Growth plan (we worked it out together, step by step):** the big risk was a new player's first minutes - the name promises a boss, but the first real one (Oozark) is level 15. Step 1, a boss in the first minute, is done: the intro (above). **Step 2 is next: the gap after it** - you finish the intro at level 3 and the Spire says level 15, so you farm dummies for a long time. We haven't decided how to close it yet.

**Also asked for: more bosses** (my goal is 20+). Floors 3 to 8 are done: Knight Burrowmore, Kaze, Speedy Revvington, Gridlock, Kongo and Petalina (see their sections above, and the agreed lineup). Floor 9 (Scribble) comes after the weapon system starts (see the new direction's build order) - ask me before building it.

### The dev console
A small red **DEV** button bottom-right (Hud) opens the dev console: +Loot, +Coins, +Power, Max Upgrades, Replay Intro, and **Set Level** (type a level: your Power becomes that level's, `BestLevel` becomes it, stat points are refunded - so everything feels as it would for a real player at that level; gear and coins untouched); in a fight CombatClient adds "DEV: Incoming hit"; and every Spire floor is open (no need to beat the one below). Who gets it: `Config.isDev(player)` - always in Studio, and in the real game the game's owner (when a person owns it, not a group) plus anyone in `Config.DevUserIds`. The server sets the player attribute `Dev` (only so the screen shows the button) and **every dev action checks `Config.isDev` again on the server**, so nobody else can use them. I playtest in the real Roblox (fullscreen), so keep dev tools working there - owner-only.

### Adding a boss
1. Copy `ServerScriptService/Bosses/_Template.lua` and `ReplicatedStorage/BossBodies/_Template.lua`, naming both copies after the new boss's short name (e.g. `Frostjaw.lua`). Their headers explain everything.
2. Add it to `Config.Bosses` on its floor (copy Oozark's entry and change it: `Short`, name, size, colours, health, and its `Attacks` - one entry per attack function, same names).
3. Give it an arena with a `BossHome` part (attributes `Floor`, `Facing`) and its floor in `Config.Spire.Floors`.
4. A surface boss only needs its attacks (server) and its body, poses and starts (client): BossService and BossClient do the rest. Something unusual uses the hooks - `Bosses/Tuber.lua` and `BossBodies/Tuber.lua` (two bars, a cutscene, per-round music, punchable props) or Gridlock's show most of them.
5. Test: `test_boss_template.luau` shows how to fight a boss headlessly; add golden scenarios for the new boss to `golden.sh` once it's finished.

## Testing tips

- Before pushing, compile-check every changed file with a Luau compiler (`luau-compile`) and run `luau-analyze`.
- Headless tests of the server logic with a mock Roblox are very useful: they caught NaN and positioning bugs before. They're now in `Tools/HeadlessTests/` (`./run_all.sh`); add new tests there.
- **Changing boss code without changing the fights** (a cleanup, a split): run `./golden.sh check` before and after - it replays 40 recorded boss fights (Oozark, Tuber, Burrowmore, Kaze, Revvington, Gridlock, Kongo and Petalina: server decisions and hits, and a fingerprint of everything drawn on screen) and fails on any difference. Only when a change is MEANT to change a boss, re-record it with `./golden.sh record <name prefix>` (e.g. `server_knight`; and say so in the commit). A new boss adds its own scenarios to `test_bosses.luau` and `golden.sh` once it's finished.
- **Burrowmore:** `test_burrowmore.luau -a <full|attacks|reset|duo|timing> [seed] [client]` fights him on the real Glimmer Dig (see its header). `luau burrowmore_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png` draws the fight sheet; `-a poses` and `--cols 3 --title ""` the pose sheet. `render_snaps.py` works for any snapshot file with `SNAP`/`BAR` lines.
- **Revvington:** `test_revvington.luau -a <full|attacks|reset|duo|timing|crash> [seed] [client]` fights him on the real Piston Speedway (see its header). `luau revvington_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png --title "..."` draws the fight sheet; `-a poses` and `--cols 3 --title ""` the pose sheet.
- **Tuber:** `test_tuber.luau -a <full|attacks|reset|duo|timing|powerup|split|props|corner> [seed] [client]` fights him on the real Sunken Dunes (see its header). `luau tuber_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png --cols 3 --title "..."` draws the fight sheet (its power-up pictures are taken from the game's own cutscene camera); `-a poses` and `--cols 3 --title ""` the pose sheet (with the audience close up). `render_snaps.py` now takes a field of view per picture (an 8th number on a SNAP line).
- **Gridlock:** `test_gridlock.luau -a <full|attacks|reset|duo|timing|drop|pads> [seed] [client]` fights him on the real Final Beat (see its header). `luau gridlock_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png --cols 3 --title "..."` draws the fight sheet; `-a poses` and `--cols 3 --title ""` the pose sheet.
- **Kongo:** `test_kongo.luau -a <full|attacks|reset|duo|timing|tired> [seed] [client]` fights him in the real Jungle Village (see its header). `luau kongo_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png --cols 3 --title "..."` draws the fight sheet; `-a poses` and `--cols 3 --title ""` the pose sheet.
- **Petalina:** `test_petalina.luau -a <full|attacks|reset|duo|timing|droop|traps|thorns> [seed] [client]` fights her in the real greenhouse. `luau petalina_snaps.luau > s.txt` then `python3 render_snaps.py s.txt out.png --cols 3 --title "..."` draws the fight sheet; `-a poses` and `--cols 3 --title ""` the pose sheet.
- **The heart, the potion and the bolt:** `test_vitals.luau` starts the real `Vitals` the way Hud does, with a pretend Humanoid and pretend CombatClient messages, and checks every picture square by square (`-a shapes|lobby|arrive|stamina|sparks|empty|iframes|drink|last|race|leave|fuzz`). `luau test_vitals.luau -a snaps > v.txt` then `python3 render_vitals.py v.txt out.png` draws every state; `-a pour` with `--cols 4 --tight --title "DRINKING A FLASK"` the drink, moment by moment.
- **YouTube (not part of the game):** `Docs/youtube/` - `make_icon.py` (the channel icon), `make_end_card.py --day N` (the animated end card) and `oozark_cutscene.mp4`, a 10-second Short of the Oozark fight made from the real game code: in `Tools/HeadlessTests` (after `python3 build_sources.py`), `luau oozark_cutscene.luau > c.txt` (the real BossService and BossClient, his moves forced like a scripted scene, a blocky player), then `python3 render_cutscene.py c.txt out.mp4` (the cameras, the boss bar, his name, hit pops, the freeze frame "CAN YOU BEAT HIM?"). It's silent: music and sounds go on in the editing app. Borrow a fight's idea, never another game's character or name.
- **The intro:** `test_intro.luau` plays it end to end with the real server and screen scripts (`-a skip`: a returning player; `-a fail`: a broken screen). `luau intro_snaps.luau > snaps.txt` then `python3 render_intro.py snaps.txt out.png` draws the four-picture preview from the real lobby.
- **Where every arena is** (2600 studs apart, so none overlap): the lobby round `(0, 0, 0)`; Oozark's hollow `(0, 0, 2600)`; the Colosseum `(-2600, 0, 0)`; the Sunken Dunes `(2600, 0, 2600)`; the Glimmer Dig `(-2600, 0, 2600)`; the Rooftop Dojo `(2600, 0, 0)`; Piston Speedway `(0, 0, -2600)`; The Final Beat `(2600, 0, -2600)`; Kongo's Jungle Village `(-2600, 0, -2600)`; the Glasshouse Garden `(5200, 0, 0)`. A new arena takes a free spot (the next ring out: `(-5200, 0, 0)`, `(0, 0, 5200)` and so on) and goes in `test_arenas_apart.luau`'s list: it builds every arena together and fails if any two overlap.
- `mount.luau` loads the game's scripts into the mock the way Rojo lays them out (folders and all), so scripts that require each other by their place in the game work in tests.
- Remember `Random:NextNumber(a, b)` takes a range. `Vector3.zero` exists in Roblox.

Start by reading `ReplicatedStorage/Config.lua` (the `Intro`, `Bosses` and `Colosseum` sections), `ServerScriptService/BossService.lua` and the two `_Template.lua` boss files (and `Bosses/Burrowmore.lua` + `BossBodies/Burrowmore.lua`: the newest, most complete example of a surface boss). The Colosseum polish plan is done, the boss code is split, the intro (Oozlet) is in, floors 3 to 8 (Knight Burrowmore, Kaze, Speedy Revvington, Gridlock, Kongo, Petalina) are in, and floor 2 is now Tuber (the worm is gone). Next: step 2 of the growth plan (the gap between the intro and Oozark - ask me), and floor 9's boss (Scribble - ask me before building it). **The big next job is the new direction** (see "The new direction: weapons, packs, pets and Arcade Tokens"): it replaces the old chest/gear loot plan - start with its step 1 (the test weapon first). Other ideas for later: a settings menu.
