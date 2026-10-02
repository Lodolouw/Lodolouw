# Security audit: client-side exploits

**Game:** Defeat a Boss (Roblox, Luau)
**Date:** 2026-10-02
**Scope:** every way a client can reach the server, and every place the server trusts something the client controls.

## Threat model

The attacker controls their own client completely. They can:
- run any LocalScript code;
- fire any RemoteEvent or invoke any RemoteFunction, with any arguments (wrong types, NaN, infinity, huge numbers, Instances), at any rate and in any order;
- move their own character anywhere: teleport, fly, noclip, change speed, fire Touched events;
- read every script the client can see (ReplicatedStorage, StarterPlayerScripts).

They cannot change server scripts or server data. They can use several accounts working together.

**Rule applied throughout:** the server decides everything that matters. Client-side checks and obfuscation are treated as non-existent. Every fix below is server-side.

---

## 1. Trust boundaries

| Entry point | What the client controls | What the server decides (after this audit) |
|---|---|---|
| `Remotes.Action`, a RemoteFunction. About 26 actions: shop, rewards, Arcade, trade, quests, equip, Colosseum, intro, dev tools. | The action name and one argument. | A per-player request budget (10 per second, burst 20) and `saneArg` (no NaN or infinity, short strings, shallow tables). **New:** only one action per player runs at a time. Each handler re-checks ownership, price, cooldown and state against server data. |
| `Remotes.RequestState`, a RemoteEvent. | When it fires. | Rate-limited; it only re-sends the player their own data. |
| `CombatRemotes.CombatAction`, a RemoteEvent: punch, swing, ability, roll, heal, jump, lock-on. | The action name, a lock-on target hint, and a combo number. | **New:**<br>• its own request budget;<br>• the combo swing is picked by the server, and the client's number is ignored;<br>• each swing's lock is enforced;<br>• damage, range, arc, cooldowns, stamina and flasks are all computed on the server;<br>• hits need a believable position history and a line of sight;<br>• targets must belong to the player's own arena copy. |
| `SpireTravel`, a RemoteFunction: enter, leave, Colosseum. | The floor number, the tier name, and when it's called. | The floor and tier are checked against Config. Floor and tier unlocks come from server attributes. There is a door-range check and a cooldown. **New:**<br>• no travel from the intro or the Colosseum, or while already on a floor (except leaving);<br>• party members must have unlocked the floor themselves. |
| `PartyRemote`, a RemoteEvent: invite, accept, kick, leave. | Target players and timing. | Only the leader can invite, kick or start a trip, and a party holds at most 4. **New:**<br>• no invite spam;<br>• busy players can't be invited;<br>• players in the intro can't be pulled into fights;<br>• accepting never breaks up your current party unless the new one can take you. |
| `MarketplaceService.ProcessReceipt`. | Which products are bought. Any client can prompt any product. | The product id is looked up in Config; the receipt id is de-duplicated and saved. **New:**<br>• the receipt is recorded before anything is granted;<br>• gifts save the buyer first;<br>• a once-only pack bought again grants its value in tokens. |
| `PromptGamePassPurchaseFinished`. | Can be faked by exploit executors. | **New:** the server asks `UserOwnsGamePassAsync` before granting anything. |
| **Character physics** (network ownership). | The character's position, speed and height, and Touched events. | The movement guard, at 10 Hz. **New:**<br>• per-tick distance cap tied to walk speed;<br>• fall cap;<br>• speed measured by total path length;<br>• solid-ground fly check, with a 1.3 s hover limit inside arenas;<br>• the server-move window only allows positions along the trip's path;<br>• repeat offenders are kicked;<br>• the sea-return trigger only works in the lobby. |
| **Player attributes** (`SpireFloor`, `Colosseum`, `Intro`, `MoveTo`, `MoveUntil`, `SpireArena`, `Pass_*`, `Weapon`...). | Nothing: attributes a client sets never replicate. | Set only by server code. Verified. |

---

## 2. Findings and fixes

Severity reflects what an exploiter gains and how easily. Every fix below is in the repository; file names are under `ServerScriptService/` unless noted.

### HIGH

#### H1. Community chest paid out many times by racing claims
- **Where:** `RewardService.lua` `claimGroup`, and the `Action` dispatcher in `PlayerService.lua`.
- **Exploit:** each `InvokeServer` runs on its own server thread. `claimGroup` checked `d.Rewards.group`, then yielded on `player:IsInGroup()` (a web call), then set the flag and paid. Firing 15 claims in one frame meant all 15 passed the check before any of them set the flag.
- **Verified:** against the old code, the new test got **45 tokens instead of 3**.
- **Fix, in two layers:**

```lua
-- PlayerService: one action per player at a time (covers every handler that yields)
if busy[player] then
	return false, "One thing at a time!"
end
busy[player] = true
local ok, success, message = pcall(handler, player, profile.data, arg)
busy[player] = nil

-- RewardService: reserve before the yield, re-check after it
if d.Rewards.group or checkingGroup[player] then return false, "Already claimed - thanks for joining!" end
checkingGroup[player] = true
local ok, member = pcall(function() return player:IsInGroup(R.GroupId) end)
checkingGroup[player] = nil
if d.Rewards.group then return false, "Already claimed - thanks for joining!" end
```

- **Why it works:** Luau runs one thread at a time. A claim can only be interleaved with another while it is yielding.
  - The dispatcher lock means a second action from the same player is refused while the first is still running.
  - The reservation plus the re-check after the yield closes the gap even if the handler is ever called another way.
  - The `pcall` around the handler means the lock is always released, even if the handler errors.

#### H2. Out-of-reach hits by teleporting in for the instant a hit lands
- **Where:** `CombatService.lua` range checks, and the movement guard in `PlayerService.lua`.
- **Exploit:**
  1. Stand about 50 studs from the boss and press attack.
  2. A punch lands about 0.19 s later; a swing lands after `Lock × Contact`. Teleport next to the boss just before that moment, then back.
  - The old guard allowed up to 60 studs per 0.1 s tick, and judged speed by net displacement, so an out-and-back move averaged to about zero.
  - Boss hits check where you are when they land, and their timing is published. So the attacker is never there when they land.
- **Fix:**
  - **CombatService:** a short position trail per fighter, plus `movedFairly()` at the moment each punch, swing or spin lands.

    ```lua
    local FAIR_SPEED = (CC.RollSpeed or 62) * 1.3 -- the fastest real move, plus margin
    local FAIR_WINDOW = 0.45
    movedFairly = function(player, st, root)
    	local mu = player:GetAttribute("MoveUntil") -- a move the server itself made
    	if type(mu) == "number" and workspace:GetServerTimeNow() <= mu then return true end
    	local now, pos = os.clock(), root.Position
    	for _, s in ipairs(st.trail or {}) do
    		local dt = now - s.t
    		if dt <= FAIR_WINDOW then
    			local d = Vector3.new(pos.X - s.p.X, 0, pos.Z - s.p.Z).Magnitude
    			if d > FAIR_SPEED * math.max(dt, 0.05) + 4 then return false end
    		end
    	end
    	return true
    end
    -- in every contact callback:
    if not atRoot or not movedFairly(player, st, atRoot) then return end
    ```

  - **Movement guard** (see M5): a per-tick cap tied to walk speed, and speed measured as total path length, so jitter adds up.
- **Why it works:** the server keeps its own record of where the character has been. A position the character couldn't have reached at roll speed in the last 0.45 s is a teleport, and the hit is thrown away. Damage was already computed on the server; now the position it is computed from has to be one the character could reach.

#### H3. Free stamina from the intro carried into real fights, and travel out of the intro
- **Where:**
  - `CombatService.lua` `startFighting` (`free = introFight(player)`)
  - `SpireService.lua` `travel`
  - `ColosseumService.lua` `canEnter`
  - `PartyService.lua` `free`
- **Exploit:**
  1. A fresh account never finishes the intro, so the `Intro` attribute stays set for the whole session.
  2. It walks to the Spire doors, which aren't actually blocked; only the darkness on screen hides them.
  3. It enters the Colosseum or a Spire floor. `startFighting` saw the intro flag and gave free stamina.
  - Endless rolls give about 91% invulnerability, and boss kills still count. A party leader could also pull an intro-stage player into any floor.
- **Fix:**

```lua
-- CombatService.startFighting
free = introFight(player) and not player:GetAttribute("SpireFloor") and not player:GetAttribute("Colosseum"),
-- SpireService.travel (top)
if player:GetAttribute("Intro") then return false, "Finish your first fight first!" end
if player:GetAttribute("Colosseum") then return false, "Not from here!" end
if action ~= "leave" and player:GetAttribute("SpireFloor") then return false, "Not from here!" end
-- ColosseumService.canEnter
if player:GetAttribute("SpireFloor") or player:GetAttribute("Colosseum") or player:GetAttribute("Intro") then
	return false, "Not from here!"
end
-- PartyService.free
return p:GetAttribute("SpireFloor") == nil and not p:GetAttribute("Colosseum") and not p:GetAttribute("Intro")
```

- Also, the Intro-attribute handler in CombatService now restarts a fight only when the intro is the only reason the player is fighting. This removes a free full refill of flasks in the middle of a Colosseum run.
- **Why it works:** each mode (intro, Colosseum, Spire floor) can now only be entered from the lobby, and only one at a time. Free stamina applies only to the intro's own fight. These are server attributes the client can't set.

#### H4. Game passes granted from a faked purchase-finished event
- **Where:** `ShopService.lua`, the `PromptGamePassPurchaseFinished` handler.
- **Exploit:** the handler trusted the event's `purchased == true`. High-privilege executors are reported to be able to fire this event. Doing so would give VIP, 2x XP, 2x Coins and +200% Luck for the session, and VIP's title permanently.
- **Fix:**

```lua
for key, p in pairs(S.Passes) do
	if p.PassId == passId and (p.PassId or 0) > 0 then
		task.spawn(function()
			for _ = 1, 5 do
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
				end)
				if not player.Parent then return end
				if ok and owns then
					givePass(player, key)
					notify(player, "Thanks! " .. p.Name .. " is yours.", "rare")
					return
				end
				task.wait(2) -- (the sale can take a moment to settle)
			end
		end)
	end
end
```

- **Why it works:** the event becomes only a hint. Ownership is confirmed with Roblox's own records, which a client cannot fake. Join-time checks already worked this way.

### MEDIUM

#### M1. Hovering to dodge every attack that is avoided by height
- **Where:** the fly check in the movement guard. Many boss attacks are avoided by height: waves, puddles, Kaze's melee, Revvington's car, Gridlock's tiles, and others.
- **Exploit:** hold the character 6–11 studs above the arena floor. The old check counted anything within 16 studs below as "ground", and any slow descent as falling. That made the player immune to shockwaves and puddles while their own punches still landed.
- **Fix:** in arenas the guard is stricter.

```lua
local fighting = player:GetAttribute("SpireFloor") ~= nil or player:GetAttribute("Colosseum") ~= nil
params.RespectCanCollide = true -- solid ground only
local ground = workspace:Raycast(pos, Vector3.new(0, fighting and -FIGHT_GROUND_RAY or -16, 0), params) -- 7 studs in a fight
if ground or drop >= FALLING then g.air = 0 -- really falling: at least 1.2 studs a tick
else
	g.air += dt
	if g.air > (fighting and FIGHT_FLY_SECONDS or FLY_SECONDS) then why = "flying" end -- 1.3 s in a fight
end
```

- **Why it works:**
  - In an arena, no real jump keeps you more than 7 studs off the floor for more than 1.3 s. The default jump peaks at about 6.4 studs with about 0.55 s airtime.
  - A hovering player is put back on the last solid ground, so they get hit like anyone else.
  - Jump pads are allowed, because `CombatService.Launch` sets a server move (`MoveTo`/`MoveUntil`).
- **Design choice:** this lives in the guard rather than in every boss's height check, so the boss logic and its recorded test traces are untouched.

#### M2. Boss kill rewards for AFK, dead or carried players, and skipping floor unlocks
- **Where:**
  - `BossService.lua` `die()`: it paid everyone in the arena.
  - `PartyService.PartyFor`: only the leader's unlocks were checked.
- **Exploit:**
  1. A strong main forms a party with fresh alts and enters a late floor or a harder tier.
  2. The alts hide or die; the main kills the boss.
  3. Every alt received the Power, the first-clear Arcade Tokens, and that floor's unlock. Unlocks count the highest floor ever cleared, so one carry opened a whole tier.
- **Fix:**

```lua
-- BossService: record real damage per player, and who landed the last blow
E.participants[player] = (E.participants[player] or 0) + d
if killed then E.killer = player end
-- die(): only living players who really fought are paid
local need = math.max(1, (tonumber(E.model:GetAttribute("MaxHealth")) or 0) * 0.01)
local function earned(p)
	local alive = not (CombatService and CombatService.IsFighting) or CombatService.IsFighting(p)
	return alive and (p == E.killer or (E.participants[p] or 0) >= need)
end
-- PartyService.PartyFor: each member must have opened that floor themselves
unlocked = Config.spireTierOpen(cleared, tier.id)
	and (not Config.Spire.RequirePrevious or floorId <= 1 or (cleared[tier.id] or 0) >= floorId - 1)
```

- **Why it works:**
  - Damage dealt is recorded on the server from server-computed hits, so a share of the win can't be faked by standing nearby.
  - Unlocks are checked per player against their own server-side clear record, so nobody is carried past floors they haven't beaten.
  - A player who fought but didn't qualify still gets a "Victory" screen, with 0 reward.

#### M3. Choosing the strongest swing every time
- **Where:** `CombatService.lua` `swingWeapon` and the fist punch. The client sent the combo number.
- **Exploit:** send `CombatAction("Punch", target, 3)` repeatedly. Every swing was then the finisher (1.5x damage, the heaviest hit), throttled only to 85% of the previous swing's lock. That gave about 30–40% more damage per second.
- **Verified:** with the old code, asking for the finisher after a pause got swing 3.
- **Fix:**

```lua
-- the server's own string rule (the same as CombatClient's)
nextSwing = function(st, window, steps, now)
	local c = st.combo or 0
	if c >= 1 and c < steps and now - (st.lastPunch or 0) <= window then return c + 1 end
	return 1
end
local n = nextSwing(st, kind.Window or CC.Combo.Window, #kind.Swings, now)  -- `swing` from the client is ignored
if ... or now - st.lastPunch < (st.lastLock or 0) - SWING_SLACK or ... then return end
st.lastPunch, st.lastLock, st.combo = now, s.Lock, n
```

- Fists work the same way, and also use `PunchLock × Combo.Recovery[n]`, so the finisher's longer recovery is enforced.
- **Why it works:** the string position is now server state, so the client can't ask for any swing. The previous swing's own lock is enforced, with 0.08 s of slack for network jitter instead of 15%.

#### M4. The server-move window allowed teleporting anywhere
- **Where:** `sanctioned()` in the movement guard, and every `MoveTo`/`MoveUntil` setter. The sea wash-back could be triggered at will in the lobby.
- **Exploit:** drop into the void or sea in the lobby. The sea-return trigger then opened a 3-second window in which the guard accepted any position, and that position became the new fair baseline. Arena arrivals (3 s) and Colosseum trips (5.6 s) opened windows too, which let players reach other players' arena copies.
- **Fix:**

```lua
-- excused only ALONG the trip: near the line from where they set off to the destination
if (pos - to).Magnitude <= ARRIVED then return "arrived" end -- the new starting point
local a, ab = g.good, to - g.good
local t = math.clamp((pos - a):Dot(ab) / ab:Dot(ab), 0, 1)
if (pos - (a + ab * t)).Magnitude <= CORRIDOR then return "along" end -- on the way: not judged
return nil -- anywhere else: judged as usual
```

- In `LobbyBuilder.washBack`, players with `SpireFloor` or `Colosseum` set are ignored, so it is never a way out of a fight.
- **Why it works:** a real trip can only be somewhere between where it started and where the server is sending the player. Anything off that path is judged normally, so the window can't be used to go anywhere else.

#### M5. Movement guard gaps: jitter, unlimited drops, glide, no consequence
- **Where:** `PlayerService.lua` `checkMovement`.
- **Fix:**
  - Per-tick distance cap of `max(24, allowed speed × dt × 2.5)` studs, never above 60.
  - A fall cap based on gravity.
  - Speed is total path length over the window, so out-and-back jitter counts.
  - The fly check uses `RespectCanCollide` and requires real falling (at least 1.2 studs per tick).
  - 30 put-backs within 60 s ends the session.
- **Why it works:** every check compares server-observed positions with what the game's physics allows. Each check catches a trick the others miss: jitter is caught by path length, drops by the fall cap, gliding by real-falling, hovering by the arena ground check. A player who keeps getting put back is removed rather than fought forever.

#### M6. A purchase whose payout broke part-way could be paid again
- **Where:** `ShopService.processReceipt`, `RewardService.Pay` and `RefreshLooks`.
- **Exploit:**
  1. Delete your own title's TextLabel; character changes like this can replicate.
  2. Buy something. `Pay` adds the tokens, then `RefreshLooks` errors on the missing label.
  3. The receipt id was never recorded, and the in-memory tokens are autosaved.
  4. Roblox retries the receipt (for example, on rejoin) and it pays again.
- **Fix:**
  - `RefreshLooks` is wrapped in `pcall` inside `Pay`, and the label lookup tolerates a missing label.
  - The receipt is recorded before granting:

```lua
keep() -- table.insert(d.Shop.receipts, id) BEFORE anything is handed out
local okGrant, granted = pcall(grant, buyer, key)
if not okGrant then
	warn("[ShopService] grant failed after the receipt was kept: " .. tostring(granted)) -- never pay twice
elseif not granted then
	forget() -- nothing was paid: let Roblox try again
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
```

- **Why it works:** a receipt id is never processed twice. If the grant fails part-way, the error is logged and the player keeps what was already paid, rather than risking a second payment. PurchaseGranted is still only returned after the save is written.

#### M7. A gift granted twice when the buyer's save failed
- **Where:** `ShopService.processReceipt`, the gift branch.
- **Scenario:** the friend was granted and saved, then the buyer's save failed, so the server returned NotProcessedYet. Roblox re-sends the receipt in another server, where the gift choice is forgotten, so the buyer is granted too. One payment, two grants.
- **Fix:** the receipt is written into the buyer's save first, then the friend is granted.

```lua
keep()
if not PlayerService.SaveNow(buyer) then
	forget()
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
local okGrant, granted = pcall(grant, receiver, key)
if not (okGrant and granted) then grant(buyer, key) end -- (the friend left meanwhile)
```

- **Why it works:** once the friend has the item, the receipt id is already saved where any server would look. A retry finds it and pays nothing.

### LOW

| # | Finding | Fix | Why it works |
|---|---|---|---|
| L1 | **Save lock, same-server rejoin:** if the leave-save failed, a rejoin to the same server loaded the stale DataStore copy straight away, rolling back trades or spending. | The leaving profile stays in a `releasing` map until its save succeeds, with up to 5 retries. A rejoin to the same server reuses that newer in-memory copy. | The newest data is never thrown away in favour of an older stored copy. |
| L2 | **Autosave re-locks after a leave; leaving mid-load leaves the save locked;** shutdown waited only 3 s. | Once a release starts, no ordinary save can write. An ordinary save only writes while `_lockJob == JOB`. Leaving mid-load releases the lock just taken. `BindToClose` waits up to 25 s for every save. | Save locks always end released, and shutdown saves get time to finish. |
| L3 | **NaN, infinity or negative amounts** could reach `Coins`, `Power` or `Tokens` through `AddCoins`, `AddPower`, `AddTokens` or a gain hook. A NaN balance passes every "can you afford it?" check. | `finite()` guards on all three plus `boosted`; results are clamped at 0; `DevSetLevel` rejects `"nan"`. | A balance is always a real, non-negative number, so price checks stay meaningful. (No live path used this yet; it is defence in depth.) |
| L4 | **Once-only Starter Pack re-bought** by prompting it directly from the client. | A repeat grants only its tokens and coins (no title, no revive), and is still a valid sale. | The player paid, so they get value, but "once only" holds. |
| L5 | **Trade dupes through partial saves:** one side saved and the other not after a crash. | Both players are saved immediately after the swap. Sessions that can't save (failed load, or a stolen lock) can't trade. | Shrinks the window to near zero, and removes sessions whose losses would never be written. |
| L6 | **Index and collector rewards farmed across alt accounts** by passing weapons back and forth; the starter Iron Sword was tradeable and came back on every load. | A new `Weapons.found` record: weapons from the Arcade, rewards or starters count, traded weapons don't. Index claims and collector points use it. Starters are untradeable. Old saves count everything they currently own, once. | A weapon pays its Index reward only to an account that earned it. |
| L7 | **Hits that did no damage still gave mastery, lifesteal and stamina:** an invulnerable boss, a shield block, a phase line. | `hitTarget` returns the damage dealt; mastery and on-hit effects only count hits that dealt more than 0. | Progress comes only from real damage. |
| L8 | **Hitting another arena copy's boss** by teleporting in to grief or wake it. | `mine()` requires the boss's `ArenaId` to match the player's `SpireArena`. | Arena copies are isolated on the server. |
| L9 | **No line of sight:** hits went through pillars and walls. | `clearShot()` raycasts against anchored, collidable geometry; characters and targets are ignored. | Walls block hits, as players expect. |
| L10 | **`CombatAction` had no request budget:** spam earned a reply every time. | A per-player token bucket (30 per second, burst 40) and a cap on the name's length. | Flooding costs the server almost nothing. |
| L11 | **Party:**<br>• invite spam;<br>• a failed accept still broke up your current party;<br>• being in two modes at once (Spire + Colosseum). | • One live invite per sender;<br>• at most 5 per player;<br>• busy players can't be invited;<br>• accept checks the new party first;<br>• travel exclusivity (H3). | Removes the harassment paths. |
| L12 | **The intro reward paid again on dev replays.** | It pays only when `IntroDone` was false. | It is once ever, not once per run. |

---

## 3. Checked and found safe

- **Damage is computed only on the server.** The client never sends damage, health or hit positions. The lock-on hint is accepted only if the server validates it.
- **Prices and rewards** always come from Config. Balances are checked before charging, with no yield in between, in ArcadeRoll, ArcadeExchange, DailyBuy and every claim.
- **Dev tools** (DevGive, DevSetLevel, Dev*Weapon, DevMastery, DevReplayIntro, DevIncoming, Spire DevSkip) all check `Config.isDev` on the server. It passes only in Studio, for the owner of a user-owned place, or for listed ids. No live player can reach them.
- **Saves** keep only known fields and clamp every number. Strings and keys the client influences are matched against whitelists, so nobody can bloat a save.
- **Trades:** you can't trade with yourself or swap after accepting; ownership is re-checked before the swap; the swap itself never yields.
- **Arcade:** the pity counter and first-spin rules are server state; machines are whitelisted; spins are rate-limited.
- **Equip:** ownership is required. Weapons come from a server attribute, not from Tool instances.

## 4. Not fixed / residual risk (recommendations)

1. **Jump stamina and the drinking slow-down are enforced on the client.** An exploiter can jump for free and walk at full speed while drinking. A server airtime tracker that charges stamina for jumps would close this.
2. **Auto-dodge bots.** Boss attack timings are sent to clients for the warning effects, so a script can roll perfectly. This is inherent to action games that predict on the client; i-frames are still server-timed and stamina-limited.
3. **Cross-server save locks** rely on `JobId` plus a 240 s expiry. A per-load GUID token would also cover very rare double-load edge cases during DataStore outages.
4. **Studio dev tools** write to the live DataStore when Studio API access is on. Use a separate store name in Studio.
5. **Movement within the allowed limits** (perfect pathing, staying at the speed limit) can't be told apart from good play. The limits are set so normal lag never trips them, so a little headroom remains.
6. **The movement-guard kick** (30 put-backs a minute) is generous to protect laggy players. Watch the logs after launch and tune it.

## 5. Tests

**`Tools/HeadlessTests/test_security_economy.luau`** attacks the economy the way an exploiter would:
- 15 parallel chest claims pay once;
- NaN, infinite and negative amounts are refused;
- a broken payout is never paid twice;
- a re-bought Starter Pack grants its token value only;
- traded weapons don't earn Index rewards;
- starters can't be traded.

**`Tools/HeadlessTests/test_security_combat.luau`** does the same for combat:
- the server picks the combo;
- swing rate is capped;
- blink-in hits land nothing;
- another copy's boss can't be hit;
- no mastery without damage;
- spam is ignored.

Both tests **fail on the code from before the audit** and pass after it. The existing tests were updated where they relied on the old, insecure behaviour:
- `test_sword` now throws real combo strings;
- `test_rewards_shop` checks that a faked pass event gives nothing;
- the shop tests start from a blank shop.

The full suite and the 48 recorded boss traces pass. See the commit message for the run.
