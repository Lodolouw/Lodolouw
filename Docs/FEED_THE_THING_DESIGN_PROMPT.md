# Design Chat Prompt: "Feed the Thing in the Basement"

Copy everything below the line into a new chat.

---

You are my game design partner for a new Roblox game. Don't write code yet. Help me finish the design so I can build it. Keep answers clear, simple and short. I prefer short explanations over long ones. Be honest: point out weaknesses, and push back if something won't work.

## 1. About me and what I've learned

- I'm a solo Roblox developer. I can build in about **2 weeks**. The game **must work well on phones**.
- My last game was a big, complex boss-fight game. The ad test got 202 clicks but only 17 plays, about 4.5 minutes per play, and about 7% day-1 retention.
- **Lessons:** keep it simple, make the first minute instantly clear, and test early with a small version.
- I want a game that's fun, simple, built on proven formulas, and addictive in a **fair** way: no fake timers, no pay-to-win, nothing that can be lost forever.

## 2. Roblox facts that shape the design (2026; double-check anything you're unsure of)

- **Recommendations** ("Recommended For You") look at **28 days** of player behaviour. The named signals include:
  - **Play-through rate**: thumbnail impression to actual play. This is the most important one.
  - **First-play bounce rate**: players who leave quickly.
  - **Play days per user**: across day 1, days 2–7 and days 8–28.
  - Also playtime, qualified sessions, intentional co-play days, spend days and Robux spent.
- **Thumbnails** are personalised and judged by clicks that turn into real plays.
- **New games start 16+ only.** To open to under-16 players you need ID verification, two-step verification, a refundable 1,000 Robux fee, and (reportedly) **500 "highly engaged" players** (players who made a purchase in the last ~2 months). Alternatively you can pay a **refundable 100,000 Robux** fee to skip that last requirement.
- **Maturity target: Minimal or Mild** (creepy-cute, no gore), so the game can open to younger players later without a redesign.
- Roblox removed "Steal an Egg" and announced restrictions; reports tie them to its AI-generated "brainrot" video content, not the stealing mechanic itself. Avoid leaning on that trend.
- The anomaly or horror "serve and inspect" genre is now flooded with small copies. That's why we moved to a grow/idle tycoon.

## 3. The game in one line

**Title:** *Feed the Thing in the Basement*
**Pitch:** "Grow food, feed the thing in your basement, and see what hatches."
**Genre:** a grow/idle tycoon with collecting. **Tone:** creepy-cute and curious, never truly scary.

The title should make people curious ("what thing?"). The game keeps that curiosity going: you never fully see the Thing (only its glowing eyes and arms), and every egg asks "what will hatch?"

## 4. The core chain (every step copies a proven hit; the twist is ours)

> **GROW 🌱 → FEED 🍖 → HATCH 🥚 → GROW BIG & EARN 💰 → better seeds → rarer creatures → repeat**

1. **Grow** food in your backyard garden. Crops grow over real time, including offline. *(Grow a Garden)*
2. **Feed** the food to the Thing by **swiping to toss** it down the basement hatch. A perfect toss gives a luck bonus. *(an active, skill-based action, like Kick a Lucky Block or Fish It)*
3. When the Thing's **belly bar** fills, it **lays an egg** that hatches a creature. **What you fed it decides which creature hatches.** *(pet-simulator hatching, plus Slime Rancher-style experimenting. This is our twist.)*
4. Creatures **move into your yard**, **grow big over real time**, and **earn coins per second, even offline**. *(Steal a Brainrot display and income, Sell Lemons offline income)*
5. Coins buy better seeds, more garden plots, more yard space and Thing upgrades, which lead to rarer creatures.

**Key rules:**
- **The Thing lives in the basement** and is never fully shown. It's the mystery. It grows through 5 sizes; bigger means bigger eggs and better hatch odds.
- **Creatures live in the yard**, where every player can see them. **They hatch small and grow bigger than your avatar.** Rarer creatures get bigger and gain effects (gold shine, frost sparkle, glowing aura). Each one shows a floating tag: name, rarity, coins per second.
- The yard has a capacity cap (about 8–12 creatures to start), and you upgrade capacity with coins.
- Working name for the creatures: "Thinglets", "Spawn" or "Things". **Still to decide.**

## 5. The loop at every timescale

| When | What happens | The pull |
|---|---|---|
| Every ~10 seconds | Pick, toss, *CHOMP*, coins. A craving bubble shows what it wants for 3× coins | Instant feedback |
| Every 1–2 minutes | Belly full, egg drops, a **3-second hatch reveal** | "What did I get?" |
| Every ~5 minutes | Seed shop **restocks** (random, sometimes rare; you can't pay to skip) | Checking back |
| Every ~10–15 minutes | Server **weather** (rain, snow, full moon) causes crop **mutations**; the Thing grows a size | Shared moments, visible progress |
| Every day | Offline coins and grown creatures wait for you; a new **daily craving** gives a bonus egg | Return tomorrow |
| Every week | A new seed, new creatures, a weekend event | Days 8–28 retention |
| Later | **Rebirth**: the Thing spins a cocoon, the garden resets, you gain a permanent multiplier and a new basement theme | A fresh start that feels powerful |

## 6. Rewards and what each one is for

| Reward | Role |
|---|---|
| **Creatures** (main reward) | Passive income, collection and show-off, all in one |
| **Food** | Fuel for the Thing. Mutated food (gold, frozen, glowing) is a small bonus and hatches rarer creatures |
| **Coins** | Spent on seeds, plots, yard capacity, hatch and Thing upgrades |
| **Creature-dex** | Collection goals: silhouettes ("???") with hints like "Feed it frozen food…" |
| **The Thing's size** | Long-term progress: better eggs and odds |

## 7. Dopamine design (fair, no tricks)

- **Juice on every action:** crops pop out with a bounce, the Thing squashes and stretches as it chomps, coins fountain out with numbers, small screen shakes, satisfying sounds.
- **Combo:** feed several cravings in a row for ×2, ×3, ×5, with the sound pitch rising. It fades gently, with no punishment.
- **Fair surprises:** harvest mutations, perfect tosses, egg rarity (common, rare, epic, legendary) with **odds shown in the game**.
- **The hatch is the biggest moment:** the egg wobbles, cracks, a silhouette appears, then the reveal, with colour and sound by rarity. Rare hatches get a **server-wide announcement**.
- **Always show the next goal:** the belly bar, dex silhouettes, and an upgrade that's always nearly affordable.
- **Big numbers** (K, M, B).
- **Never:** losing creatures, the Thing dying, paid luck, fake timers, paid skips.

## 8. Social (no stealing)

- **No player stealing.** Reasons: it feels unfair to new players, needs full servers, is a big build, is a crowded copy trend, and makes losing creatures feel terrible.
- **At launch:** public yards everyone can see, server announcements, and 👍 likes on yards, with a crown for the most-liked yard on the server.
- **Later updates:** **NPC egg raids** (sneak into a neighbour's basement and grab a rare egg before their Thing wakes up; nobody loses anything), then **trading** with scam protection.

## 9. Money (fair)

- **Robux buys only cosmetics:** hats and skins for the Thing, yard and basement decor, shelf or pedestal styles, egg-hatch effects.
- **Cheap impulse items** (about 25–50 Robux) mean more players make a purchase. That helps reach the 500 "highly engaged" players needed for under-16 access without being pay-to-win.
- No luck boosts or power for Robux.

## 10. The first minute (the most important part)

- **0:00:** Spawn in the backyard. No lobby, no long intro. A tomato is already ripe; the hatch rattles and glowing eyes blink.
- **0:05:** One glowing hint: "Toss it in!" Pick, swipe, *CHOMP*, a coin burst, the belly bar fills a lot.
- **0:20:** A second toss earns "PERFECT!".
- **0:30:** **The first egg drops and hatches.** The creature walks into the yard and starts earning.
- **0:45:** Buy a pepper seed. A silhouette hint appears: "Feed it spicy food…".
- **1:00:** The player has earned money, hatched a creature, and has a clear next goal.

**Rule:** the first hatch must happen within **30 seconds**.

## 11. Two-week launch scope

**In:**
- 1 garden with **6 crops**.
- The swipe toss with a perfect zone (tap and click on PC).
- The Thing with **5 sizes** (one model that scales, plus small additions: eyes, horns).
- **8 creatures × 3 mutations**, the hatch reveal, and growth from small to big.
- Restock shop, **2 weather types**, offline growth and income (decide on a cap).
- Creature-dex, server announcements, yard capacity upgrades.
- Mobile-first UI with big buttons.

**Out (later updates):** rebirth, NPC egg raids, visiting and likes (unless cheap), trading, more weather, weekly events.

**Performance:** big creatures on phones mean simple chunky shapes, effects done with colour and particles, and a capped number per yard.

## 12. Known risks and how we handle them

- **Creature art is the biggest job.** Use simple shapes, and multiply variety with colour, size and mutation effects.
- **Idle games can open slowly.** First crop ready immediately, first hatch within 30 seconds, visible growth on the first feed.
- **Economy balance.** Start simple; tune with test data.
- **Crowded grow genre.** Our difference is the diet-decides-the-hatch twist, the mysterious Thing, and the curious title. Lean on them in the thumbnail.
- **Tone.** Creepy-cute (glowing eyes, funny burps), never gory.
- **Originality check.** I'll search Roblox for "feed the thing", "basement", "feed monster" and "grow a monster" before committing.

## 13. Test plan

1. Build the smallest playable version first (garden, toss, Thing, 3–4 creatures, hatch, yard income) in about 5 days.
2. Run a small ad test with 2–3 thumbnail and title variants.
3. **Measure:**
   - Plays per click (last game: 17/202).
   - 60-second bounce.
   - Average session length (goal: over 10 minutes; last game: 4.5).
   - Day-1 retention (goal: clearly beat 7%).
4. Only expand if people stay and come back.

## 14. Thumbnail direction

- A bright backyard full of **big, colourful creatures with name and coins-per-second tags**.
- The **basement hatch open with glowing eyes and an arm** catching tossed food.
- Minimal text. Avoid the generic "✅ / ❌" anomaly template and all-dark images that vanish on phones.
- Make 2–3 variants to test.

## 15. What I want from you in this chat (in this order)

1. **Creature roster:** 8 launch creatures. For each: name, look when small vs. fully grown, rarity, which food or diet hatches it, coins per second, and what it does when idle. Plus 3 mutation looks (gold, frozen, glowing).
2. **Crops:** 6 launch crops (cost, grow time, sell or feed value) and the **diet rules**, meaning how a mix of food decides the hatch, simple enough for kids to discover.
3. **Economy numbers:** a first-hour progression curve, upgrade prices, the offline income cap, and how fast the Thing grows.
4. **The toss:** exactly how it feels on a phone (swipe, perfect zone, feedback).
5. **The Thing:** its 5 sizes, what players see of it at each size, and its reactions.
6. **UI layout for phones:** which buttons, where, and as few as possible.
7. **Thumbnail and icon concepts**, plus the final creature name ("Thinglets", "Spawn", "Things" or something better).
8. **Update roadmap** for weeks 3–8 (rebirth, NPC egg raids, events) to keep the 28-day retention signal strong.

Start with #1. Before each section, check it against my rules: simple, fair, phone-first, clear in the first minute, buildable in 2 weeks.
