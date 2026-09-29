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
- [ ] **Sword sounds**: "Sword Swing", "Sword Hit", "Whirlwind".
- [ ] **The level gap after the intro**: you finish at level 3, and Oozark wants level 15. We still need to decide how to close it.

## 1. Owning weapons

- [ ] Weapons you own are **saved** (the list, which one is equipped, and each one's mastery).
- [ ] The weapon list in Config: name, type, rarity, colours and ability for each.
- [ ] The other **weapon types' movesets**: Hammer, Daggers, Scythe and Katana (Fists and Sword already work).
- [ ] The **ability building blocks** (damage up, lifesteal, shield, dash-strike, spin, slam...) so abilities from Common to Epic are quick to make.

## 2. Arcade Tokens

- [ ] The currency itself: saved, shown in the top bar, with a dev button that adds tokens.
- [ ] **Free ways to earn them** (about 10-15 a week): the daily quest, a login streak (a big day 7), first boss clears (3-5), Colosseum runs, every 10 levels, codes, badges.

## 3. The arcade machines

- [ ] **A row of cabinets in the lobby**, one per boss, painted like its boss.
- [ ] **The ROLL button opens the Arcade menu from anywhere**: one card per machine, showing every drop with its rarity and **odds in %**, the pity bar, the price, and Roll x1 / Roll x10.
  - Locked machines still show their drops, greyed out with "Beat X to unlock".
  - A "pack of the week" card at the top with boosted odds.
- [ ] **The server rolls first**: it takes the tokens and picks the result, including pity (a guaranteed Legendary every N rolls) and duplicates (they become tokens or mastery).
- [ ] **The show**:
  1. The camera flies to that machine, and the token goes in with a clunk ("Token Clunk" is already uploaded).
  2. Weapon tiles scroll across the cabinet's screen and slow down. Epic and above flash the lights; Legendary and above get a full-screen reveal.
  3. Tap to skip. Roll x10 shows a grid of 10.
  4. The camera flies back, and you get "Equip now?".
- [ ] Other players see the cabinet light up, and a Secret sends a banner to the whole server.
- [ ] Walking up to a machine opens its card. Outside the lobby you can view the Arcade menu but not buy. If you can't afford a roll, the button says "Get tokens".
- [ ] **Honest rules:** odds always shown, no fake near-misses, and the scroll strip is filled using the real odds.

## 4. The weapons (the big one: 78 in all - full details in `Docs/weapons_plan.md`)

**What every weapon needs:** a 3D model (Blender, like the swords in
`Tools/Weapons`), its moveset (shared by its type), its ability, sounds, and
its card picture for the Arcade menu.

- [ ] **The 4 type movesets still missing:** Hammer, Daggers, Scythe, Katana (idle + 3-hit combo each; the katana's quick-draw). Fists and Sword are in.
- [ ] **The 5 shared Epic moves:** dash-strike, spin, ground slam, leap strike, uppercut (re-coloured per pack).
- [ ] **The Open Cloud uploader:** one command uploads every model and animation and writes all the IDs into the game - no copying 68 IDs by hand. (You'll need to make an API key once.)
- [ ] **Starters:** Training Wraps (Fists) ✅ · Iron Sword ✅ (make it the free early-quest weapon)

**Launch: a machine on every second floor (1, 3, 5, 7, 9) = 5 packs, 30 weapons.** Your first roll comes right after your first boss.

- [ ] **Slime (Oozark):** Goo Gloves · Jellyblade · Gelatin Hammer · Ooze Daggers · Acid Scythe · *Gelatinous Edge* (Secret)
- [ ] **Knight (Burrowmore):** Shovel Hammer · Relic Daggers · Spade Scythe · Honour Blade · Anchor Fists · *No Quarter*
- [ ] **Speedway (Revvington):** Tyre Scythe · Nitro Katana · Piston Punchers · Pit Stop Sabre · Wheelie Wrecker · *Victory Lap*
- [ ] **Jungle (Kongo):** Chest Pound Fists · Jungle Fang · Vine Scythe · Barrel Daggers · Barrel Hammer · *Kong's Crown*
- [ ] **Canvas (Scribble):** Eraser Hammer · Pencil Sword · Ink Fists · Doodle Katana · Copy-Paste Scythe · *Delete Key*

(Each pack is Common → Rare → Epic → Legendary → Mythic → Secret, in that
order. One test weapon goes first so you can play-test a roll.)

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
