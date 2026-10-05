# Feed the Thing in the Basement — Design Doc

> "Grow food, feed the thing in your basement, and see what hatches."

A grow/idle tycoon with collecting. Creepy-cute and curious, never truly scary.
This is the single source of truth: paste it into a new chat to continue.

## Status

| # | Section | Status |
|---|---|---|
| 1 | Creature roster | ✅ Locked (3 small fixes from #2, see Decision log) |
| 2 | Crops and diet rules | 📝 Draft, waiting for OK |
| 3 | Economy numbers | ⏳ To do |
| 4 | The toss | ⏳ To do |
| 5 | The Thing | ⏳ To do |
| 6 | Phone UI layout | ⏳ To do |
| 7 | Thumbnail, icon, creature group name | ⏳ To do |
| 8 | Update roadmap, weeks 3–8 | ⏳ To do |

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

- Recommendations use **28 days** of behaviour. Most important: **play-through rate** (thumbnail → play). Also first-play bounce, play days per user (day 1, days 2–7, days 8–28), playtime, qualified sessions, co-play days, spend days, Robux spent.
- New games start 16+. Opening to under-16 needs ID + 2-step verification, a refundable 1,000 Robux fee, and (reportedly) 500 "highly engaged" players (made a purchase in ~2 months), or a refundable 100,000 Robux fee instead.

## Core chain

**GROW 🌱 → FEED 🍖 → HATCH 🥚 → GROW BIG & EARN 💰 → better seeds → rarer creatures → repeat**

1. **Grow** food in the backyard garden (real time, also offline).
2. **Feed** it to the Thing by **swiping to toss** it down the basement hatch. A perfect toss gives a luck bonus.
3. A full **belly** lays an egg. **What you fed it decides what hatches.** *(our twist)*
4. Creatures move into the **yard**, **grow big over real time**, and **earn coins per second**, even offline.
5. Coins buy seeds, plots, yard space and Thing upgrades.

- **The Thing** lives in the basement and is never fully shown (glowing eyes, arms). It grows through 5 sizes.
- **Creatures** live in the public yard, hatch small, grow bigger than your avatar, and show a floating tag: name, rarity, coins/s.

## Loop at every timescale

| When | What | Pull |
|---|---|---|
| ~10 s | Pick, toss, CHOMP, coins. Craving bubble = 3× coins | Instant feedback |
| 1–2 min | Belly full → egg → 3-second hatch reveal | "What did I get?" |
| ~5 min | Seed shop restock | Checking back |
| 10–15 min | Server weather → crop mutations; Thing grows a size | Shared moments |
| Daily | Offline coins, grown creatures, daily craving bonus egg | Return tomorrow |
| Weekly | New seed, creatures, weekend event | Days 8–28 |
| Later | Rebirth (cocoon, reset, permanent multiplier, new basement theme) | Fresh start |

## Social, money, first minute

- **Social:** no player stealing. Launch: public yards, server announcements for rare hatches, 👍 likes + crown (if cheap). Later: NPC egg raids (nobody loses anything), trading with scam protection.
- **Money:** Robux buys **cosmetics only** (Thing hats/skins, yard and basement decor, pedestals, hatch effects). Cheap impulse items at 25–50 Robux.
- **First minute:** 0:00 spawn in the backyard, tomato ripe, hatch rattles, eyes blink → 0:05 "Toss it in!" → 0:20 "PERFECT!" → **0:30 first egg hatches** → 0:45 buy a chili seed, hint "Feed it spicy food…" → 1:00 earned money, hatched a creature, clear next goal.

## Launch scope (2 weeks)

- **In:** 1 garden, 6 crops, swipe toss with perfect zone, the Thing with 5 sizes, 8 creatures × 3 mutations, hatch reveal, growth, restock shop, 2 weather types, offline growth and income (capped), creature-dex, server announcements, yard capacity upgrades, mobile-first UI.
- **Out (later):** rebirth, NPC egg raids, visiting/likes (unless cheap), trading, more weather, weekly events.
- **Performance:** chunky simple creatures, effects via colour and particles, capped creatures per yard.

## Test plan

1. Smallest playable version in ~5 days: garden, toss, Thing, 3–4 creatures, hatch, yard income.
2. Small ad test with 2–3 thumbnail/title variants.
3. Measure: plays per click (last: 17/202), 60-second bounce, session length (goal > 10 min; last 4.5), day-1 retention (goal: clearly beat 7%).
4. Only expand if people stay and come back.

## Thumbnail direction

Bright backyard full of big colourful creatures with name and coins/s tags; basement hatch open with glowing eyes and an arm catching tossed food. Minimal text. No "✅ / ❌" template, no all-dark images. 2–3 variants.

---

# Part B — Design

## 1. Creatures ✅

### Hatch rules

**Diet decides the creature. Luck decides the mutation.**

The belly has **3 slots at Thing size 1** and **5 slots from size 2 on**. Each slot shows the food's icon, plus a ★ if that toss was PERFECT. Checked in this order:

1. **A full belly of Moon Melons, every toss PERFECT** → Lil' Thing (secret)
2. **5 different foods** → Mishmash
3. **Otherwise the food you fed most wins.** On a tie, the rarest food wins.

Mutated food counts as its normal food (Frozen Tomato = Tomato).

### Roster

Coins/s is at full growth. Numbers are drafts; tuned in #3.

| Creature | Rarity | Hatch from | Small → fully grown | Idle | Coins/s | Grow time |
|---|---|---|---|---|---|---|
| **Blorp** | Common | Tomato | Cherry-sized red jelly drop → beanbag blob with one big eye and a leaf hat | Bounces, burps out a seed | 2 | 2 min |
| **Sizzle** | Common | Chili | Tiny red newt → chubby lizard with a flame tuft | Waddles, sneezes a puff of fire | 5 | 3 min |
| **Peeper** | Rare | Eyeberry | Blue fuzzball with 3 eyes → big puffball covered in eyes | Eyes follow the nearest player | 15 | 10 min |
| **Glumcap** | Rare | Glowshroom | Sleepy button mushroom → tall droopy mushroom with a glowing cap | Sways, puffs glowing spores, dozes "Zzz" | 30 | 15 min |
| **Gourdo** | Epic | Pumpkin | Small round pumpkin with stubby legs → boulder-sized pumpkin with a goofy grin | Rolls around, sits down with a THUMP | 100 | 30 min |
| **Mishmash** | Epic | 5 different foods | Lumpy patchwork blob → stitched beast of mismatched parts | Wobbles, hiccups out food icons | 150 | 45 min |
| **Moonmoth** | Legendary | Moon Melon | Fuzzy grub → huge pale moth with melon-striped wings | Hovers, leaves a moon-dust trail | 400 | 2 h |
| **Lil' Thing** | Legendary (secret) | All-PERFECT Moon Melon belly | A shadow puddle with eyes → a shadow blob with glowing eyes and two little arms | Peeks out of its puddle, waves at passing players | 700 | 3 h |

### Growth and size

- Hatches at about knee height, earning **25%** of its income, and grows to full size and **100%** over its grow time (real time, also offline).
- Fully grown height, avatar ≈ 5 studs: Common 6, Rare 8, Epic 11, Legendary 14.

### Mutations

One per creature, no stacking at launch.

| Mutation | Look | Income | Main source | Base odds |
|---|---|---|---|---|
| ❄️ **Frozen** | Pale icy blue, a few icicles, frost-breath puffs | ×2 | Food harvested in snow | 5% |
| ✨ **Glowing** | Neon trim, slow pulse (no real lights) | ×3 | Food harvested at full moon | 3% |
| 👑 **Gold** | Shiny gold metal, sparkles | ×5 | Rare golden harvest, any time | 1% |

- Each mutated food in the belly: **+8%** to the matching mutation.
- Each PERFECT toss: **+1%** to all three.
- The egg shows the **live odds** while you feed. What it shows is what you get.

### Yard full

When an egg hatches into a full yard, a popup gives two choices: **"Sell new one"** or **"Swap with weakest"** (the weakest is highlighted). Epic and rarer creatures need a confirmation. The **dex keeps every creature you've ever hatched**, even after you sell it.

### Dex

8 creatures × 4 looks (normal, Frozen, Glowing, Gold) = **32 slots**. Undiscovered entries show a silhouette ("???") and a hint (see #2).

### Build notes

- Growing = scaling one model. Mutations = material swap + particles. Mishmash reuses other creatures' parts. Lil' Thing reuses the Thing's eyes and arms. ≈ **6 new models**.
- ≤ 10 parts per creature, tween animations (no rigs), Neon instead of PointLights.

## 2. Crops and diet rules 📝 Draft

### Crops

Plants are **permanent**: plant a seed once and it keeps producing fruit. Each plant holds up to **3 ripe fruit**, so offline crop growth caps itself. Numbers are drafts; tuned in #3.

| Crop | Tier | Seed cost | Regrow per fruit | Coins per toss | In the shop |
|---|---|---|---|---|---|
| 🍅 Tomato | Common | 10 | 10 s | 5 | Always |
| 🌶️ Chili | Common | 25 | 15 s | 12 | Always |
| 🫐 Eyeberry | Rare | 400 | 30 s | 40 | 60% of restocks |
| 🍄 Glowshroom | Rare | 2,500 | 45 s | 120 | 40% |
| 🎃 Pumpkin | Epic | 20,000 | 90 s | 600 | 15% |
| 🍈 Moon Melon | Legendary | 150,000 | 3 min | 3,000 | 5%, and **always at the top of each hour** |

- **No sell stand.** Feeding is how food turns into coins: one action, not two.
- **Harvest by walking past:** ripe fruit pops off with a bounce and flies into your basket. No small tap targets.
- **Dig up** a plant to get its seed back in your seed bag. Nothing is lost.
- **Start:** 4 plots, 2 tomato plants already planted with 3 ripe tomatoes between them (first belly = 3 slots → first egg at ~0:30).
- **Shop:** restocks every 5 min on one server-wide timer; each player has their own stock. Odds are shown in the shop. Commons are always in stock so the 0:45 chili purchase never fails.

### Mutated food

When a fruit ripens while you're in a server:

| Condition | Chance | Food becomes | Toss coins |
|---|---|---|---|
| ❄️ Snow (weather) | 20% | Frozen | ×2 |
| 🌕 Full Moon (weather) | 20% | Glowing | ×3 |
| Any time | 1% | Gold | ×5 |

- Weather: one event about every 12 min, lasting ~3 min, Snow or Full Moon at random, server-wide.
- Fruit that ripens offline never mutates. This rewards being online for events.
- Mutated fruit glows on the plant before you pick it.

### Helping kids discover the rules

- **Belly slots** show each food's icon and a ★ for a PERFECT toss.
- **Prediction badge** above the belly: if the egg were laid now, what would it hatch? It shows the creature's icon once discovered, "???" before.
- **Dex hints:**
  - Blorp: "It loves red and juicy…"
  - Sizzle: "Something spicy…"
  - Peeper: "Food that looks back…"
  - Glumcap: "Something from the dark…"
  - Gourdo: "Something big and orange…"
  - Mishmash: "A bit of everything. 5 different!"
  - Moonmoth: "Fruit from the moon…"
  - Lil' Thing: "Only Moon Melons. Only perfect throws."

## 3. Economy numbers ⏳

## 4. The toss ⏳

## 5. The Thing ⏳

## 6. Phone UI layout ⏳

## 7. Thumbnail, icon, creature group name ⏳

## 8. Update roadmap, weeks 3–8 ⏳

---

# Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-10-05 | Diet decides the creature, luck decides the mutation | Random creatures would make the diet twist pointless |
| 2026-10-05 | Full yard → "Sell new one / Swap with weakest" popup; dex keeps everything | Nothing lost forever |
| 2026-10-05 | Keep Lil' Thing as the secret creature | Shows a little of the Thing without revealing it; playground-rumour creature |
| 2026-10-05 | *(draft)* Belly is 3 slots at size 1, 5 slots after | "5 different foods" only works if the belly never has more slots than there are crops |
| 2026-10-05 | *(draft)* Lil' Thing = all-PERFECT Moon Melon belly (was: any food, all PERFECT, size 4+) | Otherwise skilled players farm the best creature with tomatoes and Moon Melon becomes pointless |
| 2026-10-05 | *(draft)* Mishmash 60 → 150 coins/s | It now needs 5 crop types, more effort than Gourdo |
| 2026-10-05 | *(draft)* No sell stand; feeding pays coins | One action instead of two |
