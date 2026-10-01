#!/bin/bash
# Runs every headless test. Needs the Luau command-line tools on your PATH
# (https://github.com/luau-lang/luau/releases) - or set LUAU=/path/to/luau.
cd "$(dirname "$0")"
LUAU=${LUAU:-luau}
python3 build_sources.py >/dev/null || exit 1
fails=0
run() {
	out=$("$LUAU" "$@" 2>&1)
	if echo "$out" | grep -q "^PASS"; then
		echo "pass  $*"
	else
		echo "FAIL  $*"
		echo "$out" | tail -8
		fails=$((fails + 1))
	fi
}
for seed in 1 2 3 4 5 6; do run test_colosseum.luau -a full $seed; done
for sc in cursed clearleave leave die oldbuilder kite kitejump nextrun locked react train; do run test_colosseum.luau -a $sc 3; done
for seed in 1 2 3; do run test_colosseum.luau -a hard $seed; run test_colosseum.luau -a nightmare $seed; done
run test_client.luau
run test_builder.luau
run test_arenas_apart.luau
# arena copies: two players on one floor get an arena and a boss each (the
# fights, the wins, a party's health, moved runways and pillars, reuse and
# take-down, and only your own copy's boss drawn on your screen)
run test_arena_copies.luau
# parties: invites, a full party, leader-only invites and kicks, leaving and
# handing over, and the leader taking the whole party into one arena
run test_party.luau
run test_boss_template.luau
# the heart, the potion and the bolt at the bottom of the screen, and the drink
run test_vitals.luau
run test_drink.luau
# the test sword: its rules on the server, and how it looks on every screen
run test_sword.luau
run test_weaponfx.luau
# the weapons: owning them, the types' swings, the voxel models held, the
# abilities' building blocks, every ability move (the server's hits) and how
# they all look (MoveFX)
run test_weapon_save.luau
run test_weapontypes.luau
run test_swordanims.luau
run test_voxelhold.luau
run test_blocks.luau
run test_moves.luau
run test_movefx.luau
run test_swordanims.luau
# the Arcade: the spins' odds, pity and prices, tokens from quests and bosses
# (the server), the menu, the spin and the reveal on your screen, and your
# tokens on the HUD
run test_arcade.luau
run test_arcade_client.luau
# trading at the picnic benches: the seats, offers, refusals, ACCEPT and the
# countdown, the swap (exactly once), stopping a trade, and the window
run test_trade.luau
run test_hud.luau
run test_weaponbag.luau
run test_moneyicons.luau
# the new GUI's server side: rewards, the shop's Robux receipts (each paid
# exactly once), gifts, passes, Daily Items, luck
run test_rewards_shop.luau
# the new lobby screen (next goal and its trail, gift clock, quest, boosts)
# and the menus' host (see-through, tabs, one at a time)
run test_lobbyhud.luau
# the Rewards menu, the Index and the community chest's window
run test_rewards_menus.luau
# the Shop (buying, gifts, SOON, no paid random items where not allowed)
run test_shop_menu.luau
# the Bag (weapons, the [F] ability, equip) and the Settings (sound, shadows,
# low graphics, others' effects, camera shake)
run test_bag_settings.luau
# RetroWorld's detail: with low graphics the moving detail holds still where it
# belongs (nothing piled up on the fountain) and the flyers are put away; an
# arena that unloads and comes back isn't dressed a second time on top
run test_retroworld_detail.luau
# enemies reacting to hits: the white flash (the dummies' tip and knock-back: test_colosseum react)
run test_hitflash.luau
# feet on the floor: never sunk after a reset, never floating after lunges and rolls
run test_feet.luau
run test_intro.luau
run test_intro.luau -a skip
run test_intro.luau -a fail
run test_intro.luau -a replay
# Tuber / THE BRUTE (floor 2): whole fights, every move in its round, resets,
# two players, the dodge windows, the power-up, SPLIT!, his cactus walls,
# turrets, buddies and quicksand (and the stun), cornering him - and his body,
# the power-up show and everything he plants on screen
for seed in 1 2 3; do run test_tuber.luau -a full $seed; done
for sc in attacks reset duo timing powerup split props corner; do run test_tuber.luau -a $sc 1; done
run test_tuber.luau -a full 2 client
run test_tuber.luau -a attacks 1 client
run test_tuber.luau -a powerup 1 client
# Knight Burrowmore (floor 3): whole fights, every move, resets, two players,
# the dodge windows, and the same with his body drawn on screen
for seed in 1 2 3; do run test_burrowmore.luau -a full $seed; done
for sc in attacks reset duo timing; do run test_burrowmore.luau -a $sc 1; done
run test_burrowmore.luau -a full 2 client
run test_burrowmore.luau -a attacks 1 client
# Kaze (floor 4): whole fights, every move, resets, two players, the dodge
# windows, the ki rules, the beam and the pillars, and his body on screen
for seed in 1 2 3; do run test_kaze.luau -a full $seed; done
for sc in attacks reset duo timing rules super; do run test_kaze.luau -a $sc 1; done
run test_kaze.luau -a full 2 client
run test_kaze.luau -a attacks 1 client
# Speedy Revvington (floor 5): whole fights, every move, resets, two players,
# the dodge windows, crashing into the tyre wall, and his body on screen
for seed in 1 2 3; do run test_revvington.luau -a full $seed; done
for sc in attacks reset duo timing crash; do run test_revvington.luau -a $sc 1; done
run test_revvington.luau -a full 2 client
run test_revvington.luau -a attacks 1 client
# Gridlock (floor 6): whole fights, every move in its form, resets, two
# players, the dodge windows, THE DROP and the jump pads, and his body and
# the level's tiles on screen
for seed in 1 2 3; do run test_gridlock.luau -a full $seed; done
for sc in attacks reset duo timing drop pads; do run test_gridlock.luau -a $sc 1; done
run test_gridlock.luau -a full 2 client
run test_gridlock.luau -a attacks 1 client
# Kongo (floor 7): whole fights, every move, resets, two players, the dodge
# windows, the tired opening, and his body, the villagers and torches on screen
for seed in 1 2 3; do run test_kongo.luau -a full $seed; done
for sc in attacks reset duo timing tired; do run test_kongo.luau -a $sc 1; done
run test_kongo.luau -a full 2 client
run test_kongo.luau -a attacks 1 client
# Petalina (floor 8): whole fights, every move, resets, two players, the dodge
# windows, her drooping head, the flytraps, round 2's thorns, and her on screen
for seed in 1 2 3; do run test_petalina.luau -a full $seed; done
for sc in attacks reset duo timing droop traps thorns; do run test_petalina.luau -a $sc 1; done
run test_petalina.luau -a full 2 client
run test_petalina.luau -a attacks 1 client
run test_petalina.luau -a thorns 1 client
# Scribble (floor 9): whole fights (all three rounds), every move, resets, two
# players, the dodge windows, the Z key, the DELETE box, the whip, the clones,
# and him on screen
for seed in 1 2 3; do run test_scribble.luau -a full $seed; done
for sc in attacks reset duo timing undo delete whip clones; do run test_scribble.luau -a $sc 1; done
run test_scribble.luau -a full 2 client
run test_scribble.luau -a attacks 1 client
run test_scribble.luau -a delete 1 client
# King Gavelgrunt (floor 10, the last boss): whole fights (all three rounds and
# THE FINAL GAVEL), every move, resets, two players, the dodge windows, his toe,
# the tax coins, the feast, the crown, GUILTY! and the podiums, the pillars,
# and him on screen
for seed in 1 2 3; do run test_gavelgrunt.luau -a full $seed; done
for sc in attacks reset duo timing toe coins feast crown guilty pillars final entrance; do run test_gavelgrunt.luau -a $sc 1; done
run test_gavelgrunt.luau -a full 2 client
run test_gavelgrunt.luau -a attacks 1 client
run test_gavelgrunt.luau -a entrance 1 client
# where your lock-on aims and where the bosses' words hang: every boss's
# measured middle and head (AimAt / HeadAt) checked against what's drawn
# through every move; the lock-on's own sums; the speech bubbles
for boss in slime tuber knight kaze car grid kongo petal scrib king; do run test_bosses.luau -a ${boss}_attacks 1 client aim; done
run test_lockaim.luau
run test_talk.luau
# the bosses' golden traces: they must match exactly (see golden.sh)
if ./golden.sh check > /tmp/golden_check.$$ 2>&1; then
	echo "pass  golden.sh check (48 boss traces)"
else
	echo "FAIL  golden.sh check"
	grep -v "^same" /tmp/golden_check.$$ | head -20
	fails=$((fails + 1))
fi
rm -f /tmp/golden_check.$$
echo "$fails failed"
exit $fails
