"""Economy simulation for Feed the Thing in the Basement (the simple loop).

A bot plays for hours, feeding whenever a nest is free, and we print when it
first reaches each milestone (median of 20 runs). Change the numbers at the
top (they copy FeedTheThing/ReplicatedStorage/Config.lua), rerun, compare.
    python3 economy_sim.py
Two players are simulated:
  greedy - always feeds the best food it can afford
  saver  - feeds free Tomatoes while the next food costs under 10 minutes of
           income, so it saves up for it
Real players are slower; read the times as "the fastest a keen player gets there".
"""
import math, random, statistics

# id, price, egg seconds, growth, secret chance, odds (Common, Rare, Epic, Legendary), favourite
FOODS = [
    ("Tomato", 0, 6, 1, 0.00001, (0.927, 0.07, 0.0028, 0.0002), "Blorp"),
    ("Chili", 50, 8, 3, 0.00003, (0.81, 0.177, 0.0124, 0.0006), "Sizzle"),
    ("Eyeberry", 1000, 12, 10, 0.0001, (0.63, 0.328, 0.04, 0.002), "Peeper"),
    ("Glowshroom", 15000, 18, 30, 0.0003, (0.42, 0.45, 0.12, 0.01), "Glumcap"),
    ("Pumpkin", 200000, 25, 100, 0.0008, (0.22, 0.49, 0.25, 0.04), "Gourdo"),
    ("MoonMelon", 2500000, 35, 300, 0.002, (0.08, 0.37, 0.40, 0.15), "Moonmoth"),
]
# kind: (rarity rank 0-3, coins per second grown, seconds to grow)
THINGLETS = {
    "Blorp": (0, 1, 120), "Sizzle": (0, 2, 180), "Peeper": (1, 5, 600), "Glumcap": (1, 8, 900),
    "Gourdo": (2, 25, 1800), "Mishmash": (2, 40, 2700), "Moonmoth": (3, 150, 7200), "LilThing": (3, 600, 10800),
}
BY_RARITY = {0: ["Blorp", "Sizzle"], 1: ["Peeper", "Glumcap"], 2: ["Gourdo", "Mishmash"], 3: ["Moonmoth"]}
FAVOURITE = 0.6
MUTATIONS = [("Gold", 5, 0.005), ("Glowing", 3, 0.02), ("Frozen", 2, 0.04)]  # rarest first
SIZES = [(0, 0, 0.25), (100, 0.1, 0.30), (2000, 0.2, 0.35), (25000, 0.35, 0.45), (250000, 0.5, 0.60)]  # growth, luck, hatchStart
SELL_SECONDS = 10
START_NESTS, START_YARD = 3, 8
UPGRADES = {"nests": (3, 500, 10, 1), "luck": (20, 200, 1.8, 0.05), "income": (25, 300, 1.6, 0.1), "speed": (10, 250, 2.0, 0.1)}
YARD_PRICES = {9: 500, 10: 2500, 11: 10000, 12: 40000, 13: 150000, 14: 600000, 15: 2500000, 16: 10000000}
UPGRADE_SHARE = 0.25  # buys an upgrade when it costs under this share of its coins
HOURS = 8
RUNS = 20


def tidy(x):
    if x < 100:
        return math.floor(x + 0.5)
    step = 10 ** (math.floor(math.log10(x)) - 1)
    return math.floor(x / step + 0.5) * step


def size_of(growth):
    return max(i for i, s in enumerate(SIZES) if growth >= s[0])


def roll(food, luck, rng):
    if rng.random() < food[4] * (1 + luck):
        kind = "LilThing"
    else:
        weights = [food[5][r] * (1 + luck * r) for r in range(4)]
        u, acc, rarity = rng.random() * sum(weights), 0, 3
        for r, w in enumerate(weights):
            acc += w
            if u < acc:
                rarity = r
                break
        favourite = food[6]
        if THINGLETS[favourite][0] == rarity and rng.random() < FAVOURITE:
            kind = favourite
        else:
            kind = rng.choice(BY_RARITY[rarity])
    mult, u, acc = 1, rng.random(), 0
    for _, m, base in MUTATIONS:
        acc += base * (1 + luck)
        if u < acc:
            mult = m
            break
    return kind, mult


def play(seed, saver):
    rng = random.Random(seed)
    coins, growth, cap = 0.0, 0, START_YARD
    levels = {k: 0 for k in UPGRADES}
    yard, eggs, first = [], [], {}

    def full(t):
        return THINGLETS[t[0]][1] * t[1]

    def income(now):
        total = 0
        for kind, mult, born, start in yard:
            grow = THINGLETS[kind][2]
            total += THINGLETS[kind][1] * mult * (start + (1 - start) * min(1, (now - born) / grow))
        return total * (1 + UPGRADES["income"][3] * levels["income"])

    for now in range(1, HOURS * 3600 + 1):
        coins += income(now)
        waiting = []
        for ready, kind, mult in eggs:
            if ready > now:
                waiting.append((ready, kind, mult))
                continue
            record = (kind, mult, now, SIZES[size_of(growth)][2])
            if len(yard) < cap:
                yard.append(record)
            else:
                weakest = min(range(len(yard)), key=lambda i: full(yard[i]))
                if full(record) > full(yard[weakest]):
                    coins += full(yard[weakest]) * SELL_SECONDS
                    yard[weakest] = record
                else:
                    coins += full(record) * SELL_SECONDS
            first.setdefault(kind, now)
        eggs = waiting
        for k, (top, base, rise, _) in UPGRADES.items():
            while levels[k] < top and tidy(base * rise ** levels[k]) <= coins * UPGRADE_SHARE:
                coins -= tidy(base * rise ** levels[k])
                levels[k] += 1
        while cap < 16 and YARD_PRICES[cap + 1] <= coins * UPGRADE_SHARE:
            coins -= YARD_PRICES[cap + 1]
            cap += 1
        while len(eggs) < START_NESTS + levels["nests"]:
            index = max(i for i, f in enumerate(FOODS) if f[1] <= coins)
            if saver and index + 1 < len(FOODS) and FOODS[index + 1][1] <= income(now) * 600:
                index = 0  # save up for the next one
            food = FOODS[index]
            coins -= food[1]
            growth += food[3]
            luck = SIZES[size_of(growth)][1] + UPGRADES["luck"][3] * levels["luck"]
            kind, mult = roll(food, luck, rng)
            eggs.append((now + food[2] / (1 + UPGRADES["speed"][3] * levels["speed"]), kind, mult))
            first.setdefault("food: " + food[0], now)
        for i in range(1, len(SIZES)):
            if growth >= SIZES[i][0]:
                first.setdefault("Thing size %d" % (i + 1), now)
    return first


def clock(seconds):
    return "%dh%02dm" % (seconds // 3600, seconds % 3600 // 60) if seconds >= 3600 else "%dm%02ds" % (seconds // 60, seconds % 60)


for saver in (False, True):
    runs = [play(seed, saver) for seed in range(RUNS)]
    keys = sorted({k for r in runs for k in r}, key=lambda k: statistics.median(r.get(k, 10 ** 9) for r in runs))
    print("== %s player (median of %d runs, %d hours) ==" % ("saver" if saver else "greedy", RUNS, HOURS))
    for k in keys:
        times = [r[k] for r in runs if k in r]
        reached = len(times)
        median = statistics.median(r.get(k, 10 ** 9) for r in runs)
        when = clock(median) if reached * 2 > RUNS else "not in most runs"
        print("  %-18s %s%s" % (k, when, "" if reached == RUNS else "   (reached in %d of %d runs)" % (reached, RUNS)))
    print()
