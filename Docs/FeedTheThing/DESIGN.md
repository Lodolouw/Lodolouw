# Feed the Thing in the Basement — Design Doc

> "Grow food, feed the thing in your basement, and see what hatches."

A grow/idle tycoon with collecting. Creepy-cute and curious, never truly scary.
This is the single source of truth: paste it into a new chat to continue.

## Status

All 8 sections are decided. **Prototype v0.1 (the 5-day test build) is in `FeedTheThing/`; see its README to set it up.** Numbers come from an economy simulation (`economy_sim.py`, see #3) and live in `FeedTheThing/ReplicatedStorage/Config.lua`, so tuning after the ad test is a one-file job.

| # | Section | Status |
|---|---|---|
| 1 | Creature roster | ✅ |
| 2 | Crops and diet rules | ✅ |
| 3 | Economy numbers | ✅ (simulated) |
| 4 | The toss | ✅ |
| 5 | The Thing | ✅ |
| 6 | Phone UI layout + world layout | ✅ |
| 7 | Thumbnail, icon, creature group name | ✅ |
| 8 | Update roadmap, weeks 3–8 | ✅ |

---

# Part A — The brief (fixed)

## Constraints

- Solo developer, about **2 weeks** to build. **Must work well on phones.**
- **Fair:** no fake timers, no pay-to-win, no paid luck, no paid skips, nothing lost forever.
- **Maturity: Minimal or Mild** (creepy-cute, no gore), so it can open to under-16 later without a redesign.
- Avoid the "brainrot" trend and the flooded anomaly/horror "serve and inspect" genre.

## Lessons from the last game

Big boss-fight game: 202 ad clicks → 17 plays, ~4.5 min per play, ~7% day-1 retention.
→ Keep it simple, make the first minute instantly clear, test early with a small version.

## Roblox facts that shape the design

- Recommendations use **28 days** of behaviour. Most important: **play-through rate** (thumbnail → play). Also first-play bounce, play days per user (day 1, days 2–7, days 8–28), playtime, qualified sessions, intentional co-play days, spend days, Robux spent.
- New games start 16+. Opening to under-16 needs ID + 2-step verification, a refundable 1,000 Robux fee, and (reportedly) 500 "highly engaged" players (made a purchase in ~2 months), or a refundable 100,000 Robux fee instead.

## Core chain

**GROW 🌱 → FEED 🍖 → HATCH 🥚 → GROW BIG & EARN 💰 → better seeds → rarer creatures → repeat**

1. **Grow** food in the garden (real time, also offline).
2. **Feed** it to the Thing by **swiping to toss** it down the basement hatch. A perfect toss gives a luck bonus.
3. A full **belly** lays an egg. **What you fed it decides what hatches.** *(our twist)*
4. Thinglets move into the **yard**, **grow big over real time**, and **earn coins per second**, even offline.
5. Coins buy seeds, plots and yard space.

## Loop at every timescale

| When | What | Pull |
|---|---|---|
| ~10 s | Pick, toss, CHOMP, coins. Craving bubble = ×3 coins | Instant feedback |
| 1–2 min | Belly full → egg → hatch reveal | "What did I get?" |
| 5 min | Seed shop restock | Checking back |
| ~12 min | Server weather → mutated crops | Shared moments |
| 2 min → 4 h | The Thing grows a size (fast at first, slower later) | Visible long-term progress |
| Daily | 1 hour of offline coins, grown Thinglets, Daily Craving bonus egg | Return tomorrow |
| Weekly | Update every Saturday | Days 8–28 |
| Week 3+ | Rebirth | Fresh start that feels powerful |

## Social and money

- **Social:** no player stealing. Launch: public yards, server announcements for rare hatches, **friend bonus** (+10% coins per friend in the server, max +30%). Later: likes + crown, NPC egg raids (nobody loses anything), trading with scam protection.
- **Money:** Robux buys **cosmetics only**. Cheap impulse items at 25–50 Robux. No luck, power or skips for Robux, ever.

## Test plan

1. Smallest playable version in ~5 days: garden, toss, Thing, hatch, yard income.
2. Small ad test with 2–3 thumbnail variants.
3. Measure: plays per click (last: 17/202), 60-second bounce, session length (goal > 10 min; last 4.5), day-1 retention (goal: clearly beat 7%).
4. Only expand if people stay and come back.

---

# Part B — Design

## 1. Thinglets (creatures)

### Hatch rules

**Diet decides the Thinglet. Luck decides the mutation.**

The belly has **3 slots at Thing size 1** and **5 slots from size 2 on**. Each slot shows the food's icon, plus a ★ if that toss was PERFECT. Checked in this order:

1. **A full belly of Moon Melons, every toss PERFECT** → Lil' Thing (secret)
2. **5 different foods** → Mishmash
3. **Otherwise the food you fed most wins.** On a tie, the rarest food wins.

Mutated food counts as its normal food (Frozen Tomato = Tomato).

### Roster

| Thinglet | Rarity | Hatch from | Small → fully grown | Idle | Coins/s | Grow time |
|---|---|---|---|---|---|---|
| **Blorp** | Common | Tomato | Cherry-sized red jelly drop → beanbag blob with one big eye and a leaf hat | Bounces, burps out a seed | 1 | 2 min |
| **Sizzle** | Common | Chili | Tiny red newt → chubby lizard with a flame tuft | Waddles, sneezes a puff of fire | 3 | 3 min |
| **Peeper** | Rare | Eyeberry | Blue fuzzball with 3 eyes → big puffball covered in eyes | Eyes follow the nearest player | 10 | 10 min |
| **Glumcap** | Rare | Glowshroom | Sleepy button mushroom → tall droopy mushroom with a glowing cap | Sways, puffs glowing spores, dozes "Zzz" | 30 | 15 min |
| **Gourdo** | Epic | Pumpkin | Small round pumpkin with stubby legs → boulder-sized pumpkin with a goofy grin | Rolls around, sits down with a THUMP | 100 | 30 min |
| **Mishmash** | Epic | 5 different foods | Lumpy patchwork blob → stitched beast of mismatched parts | Wobbles, hiccups out food icons | 175 | 45 min |
| **Moonmoth** | Legendary | Moon Melon | Fuzzy grub → huge pale moth with melon-striped wings | Hovers, leaves a moon-dust trail | 500 | 2 h |
| **Lil' Thing** | Legendary (secret) | All-PERFECT Moon Melon belly | A shadow puddle with eyes → a shadow blob with glowing eyes and two little arms | Peeks out of its puddle, waves at passing players | 1,000 | 3 h |

### Growth and size

- Hatches small, earning a share of its income set by the Thing's size (25% at size 1 → 60% at size 5), and grows to full size and **100%** over its grow time (real time, also offline).
- Fully grown height, avatar ≈ 5 studs: Common 6, Rare 8, Epic 11, Legendary 14.

### Mutations

One per Thinglet, no stacking.

| Mutation | Look | Income | Main source | Base odds |
|---|---|---|---|---|
| ❄️ **Frozen** | Pale icy blue, a few icicles, frost-breath puffs | ×2 | Food harvested in snow | 5% |
| ✨ **Glowing** | Neon trim, slow pulse (no real lights) | ×3 | Food harvested at full moon | 3% |
| 👑 **Gold** | Shiny gold metal, sparkles | ×5 | Rare golden harvest, any time | 1% |

Odds on each egg = base + **8%** per matching mutated food in the belly + **1%** per PERFECT toss + **1%** per Thing size above 1. The egg shows these **live odds** while you feed. What it shows is what you get. If the total passes 100%, the shares are scaled down to fit.

### Yard full, selling, dex

- **Yard full:** the hatch popup offers **"Sell new one"** or **"Swap with weakest"** (highlighted). Epic and rarer need a confirmation.
- **Sell price:** 30 seconds of the Thinglet's full income.
- **Dex:** 8 Thinglets × 4 looks = **32 slots**. Keeps everything you've ever hatched, even after you sell it. Undiscovered = silhouette + hint.

### Build notes

Growing = scaling one model. Mutations = material swap + particles. Mishmash reuses other Thinglets' parts. Lil' Thing reuses the Thing's eyes and arms. ≈ **6 new models**, ≤ 10 parts each, tween animations (no rigs), Neon instead of lights.

## 2. Crops and diet rules

Plants are **permanent**: buy a seed once and the plant keeps producing. Each plant holds up to **3 ripe fruit**, so offline crop growth caps itself.

| Crop | Tier | Seed cost | Regrow per fruit | Coins per toss | In the shop |
|---|---|---|---|---|---|
| 🍅 Tomato | Common | 10 | 15 s | 3 | Always |
| 🌶️ Chili | Common | 50 | 20 s | 8 | Always |
| 🫐 Eyeberry | Rare | 750 | 45 s | 30 | 80% of restocks |
| 🍄 Glowshroom | Rare | 7,500 | 75 s | 100 | 60% |
| 🎃 Pumpkin | Epic | 100K | 100 s | 400 | 40% |
| 🍈 Moon Melon | Legendary | 1M | 3 min | 2,000 | 20%, and **always at the top of each hour** |

- **No sell stand.** Feeding is how food turns into coins.
- **Harvest by walking past:** ripe fruit pops off with a bounce and flies into your basket.
- **Buying a seed plants it** in the first empty plot. No empty plot → "Replace your weakest plant?" and the old seed's price is **refunded in full**. Nothing is lost, and there's no seed inventory to manage.
- **Start:** 4 plots, 2 tomato plants already planted with 3 ripe tomatoes between them (first belly = 3 slots → first egg at ~0:30).
- **Shop:** restocks every 5 min on one server-wide timer. Each player has their own stock. Odds are shown in the shop. Commons are always in stock.

### Mutated food and weather

| Condition | Chance per ripening fruit | Food becomes | Toss coins |
|---|---|---|---|
| ❄️ Snow | 20% | Frozen | ×2 |
| 🌕 Full Moon | 20% | Glowing | ×3 |
| Any time | 1% | Gold | ×5 |

- Weather: an event about every 12 min, lasting 3 min, Snow or Full Moon at random, server-wide.
- Fruit that ripens offline never mutates. This rewards being online for events.
- Mutated fruit glows on the plant before you pick it.

### Helping kids discover the rules

- **Belly slots** show each food's icon and a ★ for each PERFECT toss.
- **Prediction badge** above the belly: what the egg would hatch right now (icon if discovered, "???" if not).
- **Dex hints:** Blorp "It loves red and juicy…", Sizzle "Something spicy…", Peeper "Food that looks back…", Glumcap "Something from the dark…", Gourdo "Something big and orange…", Mishmash "A bit of everything. 5 different!", Moonmoth "Fruit from the moon…", Lil' Thing "Only Moon Melons. Only perfect throws."

## 3. Economy numbers

### Coins

- **Toss coins** = food value × mutation × Thing size bonus × craving (×3) × combo.
- **Combo:** every craving hit in a row steps it up: ×1 → ×2 → ×3 → ×5 (max). A non-craving toss or 6 s without tossing drops it back to ×1 with a soft fizz, and nothing else is lost.
- **Craving:** one food at a time, shown in a bubble over the hatch. After each hit it switches to another food in your basket (it stays the same if you only have one kind).
- **Thinglet income** is the main earner after the first ~10 minutes. The simulation shows the curve barely changes whether cravings average ×2 or ×4, so the toss can be juicy without breaking the economy.

### Upgrades

| Upgrade | Start | Prices for each next step |
|---|---|---|
| Garden plots | 4 | 150 · 1K · 5K · 25K · 150K · 750K (max 10) |
| Yard space | 8 | 2K · 8K · 30K · 100K · 300K · 1M · 3M · 10M (max 16) |

The Thing is **not** bought: it grows by eating (#5). That keeps coins for seeds, plots and yard.

### Thing growth

Every toss adds the food's base value to the Thing's growth bar.

| Size | Growth needed (total) | Active player reaches it at |
|---|---|---|
| 2 | 100 | ~2 min |
| 3 | 3,000 | ~15 min |
| 4 | 50,000 | ~1 h 15 |
| 5 | 800,000 | ~4.5 h |

### First hours (simulated, active player, 20 runs, median)

| Time | Milestone |
|---|---|
| 0:30 | First Blorp |
| ~1 min | Chili planted → first Sizzle |
| ~2 min | Thing size 2 (belly becomes 5 slots) |
| ~3 min | First Eyeberry |
| 6–8 min | First Peeper |
| 10–13 min | First Glowshroom |
| ~15 min | Thing size 3 |
| ~20 min | First Glumcap |
| ~40 min | First Pumpkin |
| ~1 h 15 | First Gourdo and Thing size 4 |
| ~2 h | First Moon Melon |
| ~3 h | First Moonmoth |
| ~4.5 h | Thing size 5 |

Real players are slower and spread this over **days 1–3**. After that, the chase is Gold Thinglets, Lil' Thing and the 32-slot dex until rebirth arrives in week 3.

### Offline

- **Thinglets earn up to 1 hour of coins while you're away**, shown on a "Welcome back" screen with one big Collect button. It's easy to explain, and it pays out in full after just one hour away.
- Thinglets keep **growing** offline with no cap. Plants fill up to 3 fruit each.
- Why not more: 8 hours at full rate would give day-2 players several sessions' worth of coins at once and burn through the content too fast. A longer offline cap is a good rebirth perk later.

### Daily Craving

Once a day (resets at midnight UTC, countdown shown), the Thing craves one food you grow. **Feed it 10 of that food → a bonus egg that is always mutated** (Frozen 60% / Glowing 30% / Gold 10%). It's a daily reason to come back that can't be bought.

## 4. The toss

**A timing toss, not an aiming toss.** Aiming by swipe strength feels different on every phone; timing feels the same everywhere.

- **Where:** when you're within ~30 studs of your hatch, the **throw pad** appears at the bottom centre: your selected food, big, with the basket bar of all your foods beside it.
- **The perfect ring:** a glowing ring around the hatch slowly shrinks and grows (1.2 s cycle). It turns **gold** when it's small. That's the PERFECT window (30% of the cycle, generous on purpose).
- **Swipe up** from the throw pad (or anywhere on the lower half of the screen). PC: click, or press Space. Number keys 1–6 pick a food.
- The ring's state **at release** decides PERFECT or GOOD. **Every toss lands.** There is no miss and nothing is wasted.
- **Feedback:**
  - Release: whoosh, the food spins through the air in an arc (0.35 s).
  - GOOD: it drops in. CHOMP, the lid squashes, crumbs fly, "+24" coins pop up and fly to the counter.
  - PERFECT: an arm shoots out and catches it mid-air. "PERFECT!" in gold, sparkles, a tiny screen shake, and a gold ring around that belly slot.
  - Craving hit: the bubble pops, "×3", and the combo counter rises with a higher pitch each step.
- **Tapping the craving bubble** selects that food, so you don't have to hunt through the basket.

## 5. The Thing

You **never see its body**: only eyes, arms, teeth and horns in the dark under the hatch. It's one model that scales, with parts added at each size.

| Size | Name | What you see | Belly | Toss coins | Hatchlings start at |
|---|---|---|---|---|---|
| 1 | Lurker | Small wooden trapdoor, two small glowing eyes, one little arm | 3 | ×1 | 25% |
| 2 | Muncher | Bigger eyes, two arms, the lid rattles | 5 | ×1.25 | 30% |
| 3 | Gobbler | Cellar door, a big grin of rounded glowing teeth, a tongue that licks the rim | 5 | ×1.5 | 35% |
| 4 | Glutton | Double doors, four arms, horn tips peeking out, the ground thumps when it chomps | 5 | ×2 | 45% |
| 5 | Colossus | Glowing cracks in the lawn around the hatch, huge eyes, a crown of horns | 5 | ×3 | 60% |

Each size also adds +1% to every mutation chance.

**Reactions (all cheap tweens and sounds):**

- **Idle:** blinks; its eyes follow the nearest player; sometimes rumbles and rattles the lid. It growls a hungry growl when the belly is empty and you're near.
- **Craving:** a thought bubble with the food.
- **Chomp:** squash and stretch, CHOMP, happy squinting eyes. A PERFECT toss gets star eyes.
- **Belly full:** the hatch shakes, a big BURP, and the egg pops out onto the lawn.
- **Size up:** the lid bursts open, light pours out, and a banner reads "YOUR THING GREW! Size 3: Gobbler. It grew teeth!" Reaching size 5 gets a server announcement.
- **Weather:** in snow it sneezes; at full moon its eyes glow purple and it does a little howl.
- **Never:** dies, gets angry at you, or takes anything away.

## 6. Phone UI layout

**Few things on screen.** Roblox's own buttons (top bar, thumbstick bottom-left, jump bottom-right) stay clear.

| Where | What | When |
|---|---|---|
| Top centre | Title banner "Feed the Thing!"; announcements and weather show in it | Always |
| Left, middle | 2 wide buttons: **Shop** (green, cart), **Index** (cyan, book), with a red "!" badge when something's new | Always |
| Right, middle | 2 square buttons: **Daily** (red, egg) and **Upgrades** (orange, chevrons) | Always |
| Bottom left | 💰 coins in big italic numbers + coins/s above | Always |
| Bottom right | Weather timer: "Snow in 2m 31s" / "Full Moon! 1m 05s left" | Always (above the jump button on phones) |
| Bottom centre | **Throw pad + basket hotbar** (numbered slots) | Near your hatch |
| Over the hatch (3D) | Belly slots, prediction badge, craving bubble, mutation odds chips, combo | Near your hatch |
| Over each Thinglet (3D) | Name, rarity colour, coins/s, growth bar while growing | Always |
| Over each plot gate (3D) | Owner's avatar, name, Thing size | Always |

The style follows the genre's hits (Steal an Egg): saturated colours, thick black outlines, lit-from-the-top buttons, white text with black outlines, big italic numbers. Icons are drawn with UI frames (crisp at any size, no uploads needed).

**Popups (one big button each where possible):**

- **Hatch reveal:** the egg wobbles, cracks, shows a silhouette, then the reveal with rarity colour and sound. 3 s for a new Thinglet; 1.5 s for one you already have; tap to skip after 1 s.
- **Welcome back:** offline coins + Collect.
- **Yard full:** Sell new one / Swap with weakest.
- **Thinglet card** (tap a Thinglet): name, rarity, mutation, coins/s, growth, Sell.
- **Shop:** all 6 seeds with stock, price, odds and "New stock in 2:31". (The mystery lives in the dex, not the shop: players need to see their next goal.) The ✨ **Style** tab for Robux cosmetics arrives with week 3.
- **Upgrades:** More plots, More yard space, the Thing's growth bar.
- **Index** (the dex): 8 × 4 grid, silhouettes + hints.
- **Daily:** today's craving, progress, the bonus egg, the offline and friend perks.

Minimum tap target 64 px; text never under 18 px.

### World layout

- **Stud-style neighbourhood, made in Blender** (`FeedTheThing/Blender`). One street runs down the middle with **4 plots on each side**, all facing the road. Checkered stud walls surround the map. The road runs into a tunnel in the wall at each end: SEED EXPRESS in the west (the seed stand sits beside it) and FEED THE THING in the east.
- **8 players per server.** The first players get the middle of the street, across from each other.
- **Each plot:** the house at the back; the **hatch** pit in the lawn in front of it; **planter boxes** on both sides of the hatch (harvest → toss is a few steps); the **yard** lawn in front where Thinglets roam, behind an X-fence with a wide gate onto the sidewalk; a mailbox; and a floating sign with the owner's avatar and name.
- **Spawn** right next to your own hatch.
- Collisions are invisible blocks made by the game, so mesh collisions never get in the way. StreamingEnabled on; ≤ 10 parts per Thinglet; particles only on mutated ones.

## 7. Thumbnail, icon and name

**Creature group name: Thinglets.** It ties straight to the title, sounds cute, is easy to say and search, and doesn't clash with "the Thing". "Spawn" sounds dark and generic; "Things" gets confused with the Thing itself.

**Thumbnail variants for the ad test (bright, high contrast, at most 2 words):**

1. **"The Catch":** sunny yard; the open hatch in front with huge glowing eyes and a purple arm catching a flying tomato; the avatar mid-throw; 4–5 big Thinglets behind with tags (Moonmoth "LEGENDARY 500/s").
2. **"What will hatch?":** a giant golden egg cracking on the lawn with a silhouette inside, glowing eyes in the hatch behind it, the avatar amazed. Text: "???".
3. **"Yard flex":** a wide yard of huge Thinglets including a Gold one, big "+1.2K/s" numbers, the hatch eyes peeking from a corner.

**Icon:** a top-down view of the hatch, slightly open, two big glowing eyes and an arm holding a tomato, on bright green grass. It reads clearly even at the smallest size.

## 8. Update roadmap (weeks 3–8)

The calendar assumes building Oct 5–18, an ad test mid-build, and **launch ~Oct 19, 2026**. **Updates ship every Saturday.** Weekend events are config toggles: Double Mutation, Golden Hour (Gold ×2 odds) and Fast Growth.

| Week | Dates | Update | Why |
|---|---|---|---|
| 3 | Oct 19–25 | **Launch polish + Rebirth ("Cocoon")**: needs Thing size 5. Resets coins, plots, plants and the yard. Keeps the dex, cosmetics and **one favourite Thinglet**. Gives a permanent **+50% coins** per rebirth and a new basement theme. Rebirth 1 also unlocks the 7th crop. **Style shop** (5 cosmetics: eye colours, hatch skins). | Late game has nothing left to buy; rebirth gives it a reason. The Style shop starts counting spend days. |
| 4 | Oct 26–Nov 1 | **Halloween event**: Candy Corn crop, Spooky Moon weather, event Thinglet "Jack-o'-Blorp". **Event Thinglets return every year**, so there's no pressure to grind. | Perfect timing for a creepy-cute game. |
| 5 | Nov 2–8 | **NPC Egg Raids**: sneak into a sleeping neighbour Thing's basement (simple timing stealth) and grab an egg with better odds. 3 raid tickets a day. | A new active mode and a daily reason to return. |
| 6 | Nov 9–15 | **New tier**: 1 crop, 2 Thinglets, Rain weather (crops grow ×2 during rain). **Likes + crown** on yards. | Content for days 8–28; shows off yards. |
| 7 | Nov 16–22 | **Trading** with scam protection: both players see values, a two-step confirm, and new accounts can't trade. | Social pull and co-play. |
| 8 | Nov 23–29 | **Feast event**: a server-wide feeding meter. When the server fills it together, everyone gets a bonus egg. | Intentional co-play days signal. |

---

# Polish plan (from the first Studio playtest)

The prototype works, but it still looks and feels generic. The plan below is in order of impact on the two numbers that matter: plays per click (the art) and whether people stay and come back (feel, clarity, goals).

## Phase 1: fix what the screenshot shows (½ day)
- Weather must not make the game dark. Full Moon becomes a purple tint with glowing particles instead of night. Snow stays bright.
- Income under 1/s shows "+0/s". Show "+0.3/s".
- When the basket is empty, the throw pad is a blank white circle. It should say "Pick fruit!" and point to the plants.
- The red close button reads as "%", and the cart icon doesn't read as a cart. Redraw both, or use uploaded icons once the API key works.
- The belly display over the hatch is small and hard to read. Make it bigger, with a clearer "Will hatch" label.
- The fences and planters look heavy and dark. Use lighter wood and lower fences, so plots feel open, like Steal an Egg's.

## Phase 2: real art for everything that's alive (3 to 4 days)
- **Thinglets in Blender:** 8 creatures with big readable faces (eyes, mouth, blush), one clear silhouette each, and a simple idle animation (bounce, blink, wiggle). Keeping the 4 looks.
- **The Thing:** proper eyes with lids, arms with hands, a grin. It should be the mascot people remember.
- **Crops and plants:** 6 plants that visibly grow (sprout, then bush, then fruit), so the garden feels alive.
- **Eggs:** one egg per rarity, plus a crack animation.

## Phase 3: game feel (2 days)
- **Sounds and music:** chomp, pop, coin, PERFECT, combo, crack, hatch and size-up, a cosy background loop, and a night version for events. This is the biggest "it feels finished" upgrade, and currently there is no sound at all.
- **Toss:** the food is always on the pad, a fatter arc, a trail, and the Thing reacting every time (lick, squish, happy eyes). Coins fly from the hatch into the coin counter.
- **Hatch reveal:** the biggest moment. Light rays, a rarity colour burst, confetti for Epic and up, and the creature hops into the yard.
- **Thing size-up:** a 3-second event (the house shakes, the lid bursts open), with a server message for the big sizes.

## Phase 4: always a next goal (2 days)
- **Goal tracker** under the coins: one goal at a time ("Buy a Chili seed 48/50", "Hatch a Sizzle", "Grow your Thing to size 2"), each with a small reward. It covers the first 30 minutes, then hands over to the Index.
- **Index rewards:** completing a creature's 4 looks gives a permanent +5% coins. This makes collecting matter.
- **More upgrade tracks:** a bigger harvest radius, faster plant growth and a bigger PERFECT window. All bought with coins, never Robux.
- **Free gift every 10 minutes of play** (a mutated fruit or coins). Fair, and it lengthens sessions.
- **Daily login streak:** day 1 to day 7 rewards. Nothing is lost if you miss a day; the streak just restarts.

## Phase 5: ad test (2 days)
- Thumbnails and icon rendered in Blender (the 3 concepts from #7), then the ad test.
- Measure plays per click, 60-second bounce, session length and day-1 retention, then decide what to fix next.

## After launch
Rebirth, Halloween event, NPC egg raids, trading, Robux cosmetics (see #8).

# Decision log

| Date | Decision | Why |
|---|---|---|
| 10-05 | Diet decides the Thinglet, luck decides the mutation | Random creatures would make the diet twist pointless |
| 10-05 | Full yard → "Sell new one / Swap with weakest"; dex keeps everything | Nothing lost forever |
| 10-05 | Keep Lil' Thing; rule = all-PERFECT Moon Melon belly | A skill reward that doesn't make Moon Melon pointless |
| 10-05 | Belly 3 slots at size 1, then 5 | Fast first hatch; "5 different foods" needs belly ≤ number of crops |
| 10-05 | No sell stand; feeding pays coins | One action instead of two |
| 10-05 | Creature name: **Thinglets** | Ties to the title, cute, searchable |
| 10-05 | Prices ×~10 per crop tier; stock odds raised (Pumpkin 40%, Moon Melon 20%) | Sim: low odds made progress depend on luck, not coins |
| 10-05 | Buying a seed auto-plants; replacing refunds in full | No seed inventory UI; nothing lost |
| 10-05 | Thing grows by eating, not by buying | Every toss feels like progress; fewer upgrade buttons |
| 10-05 | Offline = 1 hour of income | Generous feeling without skipping a day's content |
| 10-05 | Timing toss (ring), every toss lands | Feels the same on every phone; never punishing |
| 10-05 | Friend bonus +10% per friend (max +30%) at launch | Cheap; feeds the co-play signal |
| 10-05 | Style shop (cosmetics) moved into launch week 3 | Spend days count toward recommendations and the 500 engaged players |
| 10-05 | 8-player servers, plots in a ring | Phone performance with up to 16 Thinglets per yard |
| 10-05 | Map rebuilt as a stud-style street neighbourhood, made in Blender (was a ring of plots built from parts) | The look players expect from the genre (Steal an Egg); easier to make pretty in Blender |
| 10-05 | Buying seeds sends a delivery truck (made in Blender) that lobs the package onto your lawn; the plant appears when it lands | Turns a menu click into a fun, visible moment everyone on the street sees |
| 10-05 | The truck comes out of a tunnel at the west end and fades into one at the east end (the old arch became the east tunnel) | No trucks popping in and out of thin air; it has somewhere to come from and go to |
| 10-05 | Sounds and Blender models upload with one double-click (upload.bat asks for the key and user id); all sounds ship as one sound sheet | No manual importing; one audio upload instead of 18 fits Roblox's 10-a-month limit |
| 10-05 | Thinglets and the egg are made in Blender: smooth, flat-coloured pieces named by role (Body, Eye, Accent, Glow) instead of textures | Big readable faces; the Frozen, Glowing and Gold looks can still recolour them; the block-built versions stay as the fallback |
| 10-06 | Upgrades became an incremental menu: 10 upgrades with levels, rising costs, buy x1/x10/MAX, unlocking as the Thing grows (Config.Upgrades) | Something to buy at every stage; the menu shows exactly what you get; everything stays coins-only |
| 10-05 | Sound effects are made in code (`Sounds/make_sounds.py`) and uploaded with an Open Cloud key | 100% original (no licence or copyright risk), easy to tweak and re-upload |
| 10-05 | Uploaded models load by asset id (InsertService) | No manual Studio import after every change |
| 10-05 | Prototype: the server decides, clients draw (plants, Thing, Thinglets drawn locally from plot attributes) | Smooth animation on phones, light server |
| 10-05 | Weather and shop stock come from the clock + UserId | Every server agrees; rejoining can't re-roll stock |
| 10-05 | Server allows a toss every 0.12 s (client waits 0.22 s) | Network jitter never eats a toss the player saw land |
