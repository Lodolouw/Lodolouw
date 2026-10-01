# What we still need to add (the plan to launch)

Written 29 Sep 2026. Tick things off as they're done. The order matters: each
step needs the ones before it. "You" = the owner (play-testing in Studio);
everything else is code I write.

**Already done:** the intro (Oozlet), the Colosseum (waves, runs, difficulty,
the Straw King), all 10 Spire bosses (Tuber to King Gavelgrunt), the heart /
flask / stamina, the test sword (Iron Sword with mastery), and Gridlock's 8-bit
sound effects.

---

## 0. Loose ends (small, any time)

- [x] **Boss songs**: Gridlock, Kongo, Petalina, Scribble and Gavelgrunt Song are all in SoundService (Gridlock's tiles follow `Bpm` in his Config - set it to the song's tempo).
- [x] **Thunder Crack** and the rest of floors 7-10's boss sounds (boss_sfx.py, uploaded; softened in Config.BossSoundLoudness).
- [x] **Sword sounds**: "Sword Swing", "Sword Hit", "Whirlwind" (made with the weapon sounds, uploaded).
- [ ] **The level gap after the intro**: you finish at level 3, and Oozark wants level 15. We still need to decide how to close it.

## 1. Owning weapons

- [x] Weapons you own are **saved** (the list, which one is equipped, and each one's mastery), with a Weapons panel (press B) to equip them.
- [x] The weapon list in Config: all 30 launch weapons (name, type, rarity, colours and ability for each).
- [x] The other **weapon types' movesets**: gauntlets, Hammer, Daggers, Scythe and Katana (drawn in code, with blocky stand-in models; preview `Docs/weapon_types.png`).
- [x] The **ability building blocks** (damage up, lifesteal, shield, guard, stacks, marks, speed, reach, bursts...) with their glow on screen.

## 2. Arcade Tokens

- [x] The currency itself: saved, shown bottom-left (click it for the Arcade) and on the ROLL button, with a dev button that adds tokens.
- [ ] **Free ways to earn them** (about 10-15 a week):
  - [x] quests: 1 token each, a new set every 6 hours (a new player's first is a small dummy quest)
  - [x] first boss clears: 5 (floor 1) up to 10 (floor 10)
  - [ ] a login streak (a big day 7), Colosseum runs, every 10 levels, codes, badges

## 3. The arcade machines

- [x] **The Arcade** where the forge and waterwheel were: 5 machines at launch (floors 1, 3, 5, 7, 9), painted like their packs (the other 5 are listed as coming soon; their machines come with their packs); the token machine, the prize pedestal and the BIG WINS board (`Docs/arcade.png`).
- [x] **The ROLL button opens the Arcade menu from anywhere**: one card per machine, showing every drop with its rarity and **odds in %**, the pity bar, the price, and Spin x1 / Spin x10.
  - [x] Locked machines still show their drops, with "Beat X to open".
  - [ ] A "pack of the week" card at the top with boosted odds.
- [x] **The server rolls first**: it takes the tokens and picks the result, including pity (a Legendary or better within 30 spins) and duplicates (mastery, or a token back once mastered). Your first spin is Rare or better.
- [x] **The show** (`Docs/arcade_screens.png`):
  1. The camera flies to that machine, your token flicks from your hand into the slot and the lever comes down; then the camera flies up to the machine's own screen (it rumbles while it spins and jolts on the landing).
  2. Weapon tiles scroll across the machine's screen and slow down. Epic and above flash and get rays; Legendary and above a big fanfare.
  3. Tap to skip. Spin x10 shows a grid of 10 (a Legendary gets its own reveal first).
  4. The reveal: EQUIP / SPIN AGAIN / DONE, and the camera flies back.
- [x] Other players see the machine light up and the result float over it, and a Secret sends a banner to the whole server.
- [x] **The Arcade's own music** (`Tools/Sounds/arcade_sfx.py`): an 8-bit song that speeds up while the strip spins, silence (or a heartbeat, for a Legendary or better) just before it lands, a sound for each rarity and heart-racing jackpots (glass smashing, alarm bells, a siren, showers of coins). Uploaded (ids in `AssetIds.lua`).
- [x] Walking into the Arcade opens the menu. Outside the lobby you can view it but not spin. If you can't afford another spin, the button says "Get tokens".
- [x] **Honest rules:** odds always shown, no fake near-misses, and the scroll strip is filled using the real odds.

## 4. The weapons (the big one: 78 in all - full details in `Docs/weapons_plan.md`)

**What every weapon needs:** a 3D model (Blender, like the swords in
`Tools/Weapons`), its moveset (shared by its type), its ability, sounds, and
its card picture for the Arcade menu.

- [x] **The type movesets:** gauntlets, Hammer, Daggers, Scythe, Katana, animated the same way as the sword's and uploaded (their IDs are in Config). The gauntlets punch exactly like your bare fists. Still to come: the katana's quick-draw.
- [x] ~~The 5 shared Epic moves~~ Better: **every weapon has its own real ability** (all 30): what it hits, when, and how it looks on every screen (`ReplicatedStorage/Moves` and `MoveFX`).
- [x] **The Open Cloud uploader:** `Tools/Upload/upload_assets.bat` uploads every model and ability animation and copies all the IDs for you to paste to me - no copying IDs one by one. (You make an API key; see `Tools/Upload/README.md`.)
- [ ] **Starters:** Training Wraps (Fists) ✅ · Iron Sword ✅ (make it the free early-quest weapon)

**Launch: a machine on every second floor (1, 3, 5, 7, 9) = 5 packs, 30 weapons.** Your first roll comes right after your first boss.

- [x] **Slime (Oozark):** Goo Gloves · Jellyblade · Gelatin Hammer · Ooze Daggers · Acid Scythe · *Gelatinous Edge* (Secret)
  - [x] 3D models (`Docs/weapons/slime.png`), abilities with their effects and animations (`Docs/animations/slime_abilities_fx.mp4`)
  - [x] You: run the uploader and paste me the IDs, then play-test the pack
  - [x] Sounds (and the Arcade shows each weapon's 3D model in its reveal)
- [x] **Knight (Burrowmore):** Shovel Hammer · Relic Daggers · Spade Scythe · Honour Blade · Anchor Fists · *No Quarter*
  - [x] 3D models (`Docs/weapons/knight.png`), abilities with their effects and animations (`Docs/animations/knight_abilities_fx.mp4`), swing effects (dirt and gold; No Quarter's coins, gold crack and Burrowmore's visor), sounds (`Docs/sounds/knight_speedway_sounds.mp4`)
  - [x] You: run the uploader and paste me the IDs (done) - then play-test the pack
- [x] **Speedway (Revvington):** Tyre Scythe · Nitro Katana · Piston Punchers · Pit Stop Sabre · Wheelie Wrecker · *Victory Lap*
  - [x] 3D models (`Docs/weapons/speedway.png`), abilities with their effects and animations (`Docs/animations/speedway_abilities_fx.mp4`), swing effects (sparks and tyre smoke; fire on the Mythic; Victory Lap's confetti, chequered flag and Revvington's eyes), sounds
  - [x] You: run the uploader and paste me the IDs (done) - then play-test the pack
- [x] **Jungle (Kongo):** Chest Pound Fists · Jungle Fang · Vine Scythe · Barrel Daggers · Barrel Hammer · *Kong's Crown*
  - [x] 3D models (`Docs/weapons/jungle.png`), abilities with their effects and animations (`Docs/animations/jungle_abilities_fx.mp4`), swing effects (leaves and bananas; splinters on the Mythic; Kong's Crown's gold bananas, lashing vine and Kongo's glare), sounds (`Docs/sounds/jungle_canvas_sounds.mp4`)
  - [ ] You: run the uploader and paste me the IDs - then play-test the pack
- [x] **Canvas (Scribble):** Eraser Hammer · Pencil Sword · Ink Fists · Doodle Katana · Copy-Paste Scythe · *Delete Key*
  - [x] 3D models (`Docs/weapons/canvas.png`), abilities with their effects and animations (`Docs/animations/canvas_abilities_fx.mp4`), swing effects (ink and paper; pixels on the Mythic; Delete Key's glitch and Scribble's face - `Docs/weapons/swing_effects_jungle_canvas.png`), sounds
  - [ ] You: run the uploader and paste me the IDs - then play-test the pack

(Each pack is Common → Rare → Epic → Legendary → Mythic → Secret, in that
order. One test weapon goes first so you can play-test a roll.) All five
launch packs are made.

**Updates after launch (the even floors, one "NEW WEAPON PACK!" update each; the Throne pack is the big one):**

- [ ] **Cactus (Tuber):** Prickle Blade · Barrel Cactus Maul · Spine Darts · Desert Reaper · Sandstorm Katana · *Brute Gauntlets*
- [ ] **Dojo (Kaze):** Headband Daggers · Wind Sickle · Rooftop Katana · Ki Knuckles · Rising Dragon · *Super Hammer*
- [ ] **Neon (Gridlock):** Beat Katana · Cube Fists · Neon Blade · Drop Hammer · Wave Daggers · *Deadline*
- [ ] **Garden (Petalina):** Petal Blade · Flytrap Gauntlet · Thorn Katana · Harvest Scythe · Pollen Daggers · *Carnation Crusher*
- [ ] **Throne (Gavelgrunt):** Tax Daggers · Royal Scythe · Decree Sword · Belly Bump Fists · Crown Katana · *The Final Gavel*

**Event weapons (come with step 9, 2 per event boss = 16):** Ember Cleaver,
Tidefang and Voidstar are already modelled; the other 13 are listed in the
weapons plan.

**Mastery 100 awakening** for every weapon: a new look and a stronger ability.

## 5. The new screen and the cuts

- [ ] **The window look everywhere** (you asked for old-computer windows, made loud): `ReplicatedStorage/WindowKit` - the Arcade has it (`Docs/arcade_screens.png`); next the HUD, the Weapons panel, the Quest Board, the Spire menu and the pop-ups.
- [ ] **The new GUI** (sketch: `Previews/gui_windows_sketch.html`), in steps:
  - [x] the server side: rewards, the shop's safe receipts, passes, boosts, luck (`RewardService`, `ShopService`)
  - [x] **1. The lobby screen**: picture buttons with badges, coins and tokens, the next goal with a trail on the ground and a beam, the gift clock, today's quest, boost tags, corner bonuses; the see-through menus (`Docs/new_gui_lobby.png`)
  - [x] **2. Rewards** (login calendar, free gift, codes, updates) + **the Index** (weapons, bosses, collector) + **the community chest** (`Docs/new_gui_rewards.png`; put your community's number in `Config.Rewards.GroupId`)
  - [x] **3. The shop**: featured, tickets, tokens, daily items, passes, looks, gifts; revives and Boss Rush in fights; luck in the Arcade's odds; Instant x10 (`Docs/new_gui_shop.png`). **To do (you):** make the Developer Products and Game Passes and paste their ids into `Config.Shop`
  - [x] **4. The Bag** (weapon, its one [F] ability, mastery, next tier, equip, filter; Looks; no Stats or Gear buttons), **the fight screen's weapon card** (a title bar in the weapon's rarity colour), **Settings** (sound, graphics, others' effects, camera shake, tickets) (`Docs/new_gui_bag_settings.png`)
- [x] **Armour gear and boss chests cut**: bosses pay Power (and tokens the first time); the intro's chest holds your first Arcade Token; the chest quest became "Clear a Colosseum run"; old players' gear and chests turned into Arcade Tokens once (up to 100), so nobody loses out. The G key and the gear window are gone.
- [x] **Talismans and the Upgrade Shop cut**: old saves get the coins they spent back, once (up to 50,000). The mushroom house stays as the toad's house.
- [x] **The Sell Shop, loot and the backpack cut**: old saves' unsold loot is sold at its old price, once (in the same 50,000-coin refund).
- [x] **Stat points removed** (decided): your level alone makes you stronger - every level adds damage, health, defence and Power gain (`Config.LevelBonus`).

## 6. The Robux shop

- [x] **Token packs.** Switched off automatically where Roblox doesn't allow paid random items (the PolicyService check).
- [x] **A cheap starter pack**, once per player (the SHOP button's badge shows it after your first boss).
- [x] **Game passes**: 2x XP, 2x Coins, VIP (a title plus a small bonus), luck, Instant x10.
- [ ] **Cosmetics**: titles and auras are in (Daily Items, rewards); weapon skins and victory dances still to come.
- [x] **Safe purchase handling**: the server gives each purchase exactly once, even if you leave mid-purchase.
- [ ] **You:** create the products and passes in the Creator Dashboard and paste their ids into `Config.Shop`.

## 7. Reasons to come back

- [ ] Daily login streak (in step 2), codes on update days, a badge per boss, leaderboards (fastest boss kill), and a group-join reward.

## 8. Trading

- [x] Weapons only (pets later): sit down across a picnic bench from someone to trade - a two-sided screen, both accept, a 3-second countdown, and the swap happens all at once on the server (`Docs/trade_window.png`). You: try it in Studio with two players.

## 9. Event bosses

- [ ] **The Event Arena** on the side of the island. It changes to fit each boss.
- [ ] A global timer about every 45 minutes, with a 5-minute warning.
- [ ] 8 turbocharged versions of existing bosses (Magma Kongo, Storm Kaze...), a damage leaderboard, token rewards at 1% / 5% / 15%, and 2 event weapons each, with a pity counter.

## 10. The harder Spire

- [ ] After King Gavelgrunt: **Nightmare**, then **Eclipse**, then **Doom** versions of all 10 bosses. Same moves, but faster, bigger and more of them.

## 11. Launch checklist

- [ ] Play-test every floor on a phone.
- [ ] Check performance in a full server.
- [ ] Check saving (leaving mid-fight, rejoining).
- [ ] Fill in the maturity questionnaire honestly.
- [ ] Make the icon and thumbnails (our own bosses only, nothing from other games).
- [ ] Write the description and the first codes.

## After launch

- The 5 even-floor weapon packs (above).
- Fishing for pet eggs, and pets.
- Stronger event bosses.
- Boss Rush and speedrun boards.
- More Spire floors.
