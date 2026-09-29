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

- [ ] **Gridlock Song**: you're making it. Put it in SoundService as "Gridlock Song" and set `Bpm` in his Config to its tempo.
- [ ] **Thunder Crack** sound for the walrus king's lightning (8-bit, I can make it).
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
  1. The camera flies to that machine, and the token goes in with a clunk.
  2. Weapon tiles scroll across the machine's screen and slow down. Epic and above flash and get rays; Legendary and above a big fanfare.
  3. Tap to skip. Spin x10 shows a grid of 10 (a Legendary gets its own reveal first).
  4. The reveal: EQUIP / SPIN AGAIN / DONE, and the camera flies back.
- [x] Other players see the machine light up and the result float over it, and a Secret sends a banner to the whole server.
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
- [ ] **Knight (Burrowmore):** Shovel Hammer · Relic Daggers · Spade Scythe · Honour Blade · Anchor Fists · *No Quarter*
- [ ] **Speedway (Revvington):** Tyre Scythe · Nitro Katana · Piston Punchers · Pit Stop Sabre · Wheelie Wrecker · *Victory Lap*
- [ ] **Jungle (Kongo):** Chest Pound Fists · Jungle Fang · Vine Scythe · Barrel Daggers · Barrel Hammer · *Kong's Crown*
- [ ] **Canvas (Scribble):** Eraser Hammer · Pencil Sword · Ink Fists · Doodle Katana · Copy-Paste Scythe · *Delete Key*

(Each pack is Common → Rare → Epic → Legendary → Mythic → Secret, in that
order. One test weapon goes first so you can play-test a roll.) The Slime pack
goes first; the other four packs' abilities already work (with blocky
stand-in models), and their 3D models are drafted but not finished - they
come one pack at a time after you've play-tested Slime.

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

- [ ] **The new GUI** (sketch: `Previews/gui_sketch.html`):
  - a top bar with level + XP, coins and **Arcade Tokens [+]**
  - four buttons: **ROLL, BAG, SHOP, QUESTS**, with red dots
  - the weapon card
  - in a fight, the lobby things slide away
- [ ] **Cut the old loot**: armour gear, boss chests, talismans, the upgrade shop and the sell shop / backpack counter. Old players' gear turns into Arcade Tokens once, so nobody loses out.
- [ ] Decide: keep stat points, or let your level alone make you stronger?

## 6. The Robux shop

- [ ] **Token packs.** Switched off automatically where Roblox doesn't allow paid random items (the PolicyService check).
- [ ] **A cheap starter pack**, offered once after your first boss.
- [ ] **Game passes**: 2x XP, 2x Coins, VIP (a tag plus a small bonus).
- [ ] **Cosmetics**: weapon skins, auras, victory dances.
- [ ] **Safe purchase handling**: the server gives each purchase exactly once, even if you leave mid-purchase.

## 7. Reasons to come back

- [ ] Daily login streak (in step 2), codes on update days, a badge per boss, leaderboards (fastest boss kill), and a group-join reward.

## 8. Trading

- [ ] Weapons only (pets later): a two-sided screen, a confirm step and a short cooldown.

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
