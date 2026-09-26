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
for sc in cursed clearleave leave die oldbuilder kite kitejump nextrun locked; do run test_colosseum.luau -a $sc 3; done
for seed in 1 2 3; do run test_colosseum.luau -a hard $seed; run test_colosseum.luau -a nightmare $seed; done
run test_client.luau
run test_builder.luau
run test_boss_template.luau
run test_intro.luau
run test_intro.luau -a skip
run test_intro.luau -a fail
run test_intro.luau -a replay
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
# the bosses' golden traces: they must match exactly (see golden.sh)
if ./golden.sh check > /tmp/golden_check.$$ 2>&1; then
	echo "pass  golden.sh check (24 boss traces)"
else
	echo "FAIL  golden.sh check"
	grep -v "^same" /tmp/golden_check.$$ | head -20
	fails=$((fails + 1))
fi
rm -f /tmp/golden_check.$$
echo "$fails failed"
exit $fails
