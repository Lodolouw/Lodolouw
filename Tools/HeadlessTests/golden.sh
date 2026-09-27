#!/bin/bash
# GOLDEN TRACES: proof that a change to the boss code changed nothing players
# can see. Each scenario prints a detailed trace of a boss fight (the server's
# decisions and hits, or everything drawn on screen); the saved copies in
# golden/ are what the code did before the change.
#   ./golden.sh record   save fresh traces as the golden copies (only when a
#                        change is MEANT to change the bosses)
#   ./golden.sh check    run them again and compare: any difference fails,
#                        showing the first lines that differ
#   ./golden.sh check client_    (only the scenarios whose names start so)
#   ./golden.sh record server_knight   (records only those: a new boss's own)
# Needs the Luau command-line tools on your PATH (or LUAU=/path/to/luau).
cd "$(dirname "$0")"
LUAU=${LUAU:-luau}
python3 build_sources.py >/dev/null || exit 1
mkdir -p golden
# name|luau arguments
SCENARIOS=(
	"server_slime_full|test_bosses.luau -a slime_full 1"
	"server_slime_full2|test_bosses.luau -a slime_full 2"
	"server_slime_duo|test_bosses.luau -a slime_duo 1"
	"server_slime_die|test_bosses.luau -a slime_die 1"
	"server_slime_attacks|test_bosses.luau -a slime_attacks 1"
	"server_tuber_full|test_bosses.luau -a tuber_full 1"
	"server_tuber_full2|test_bosses.luau -a tuber_full 2"
	"server_tuber_reset|test_bosses.luau -a tuber_reset 1"
	"server_tuber_attacks|test_bosses.luau -a tuber_attacks 1"
	"client_slime_full|test_bosses.luau -a slime_full 1 client"
	"client_slime_duo|test_bosses.luau -a slime_duo 1 client"
	"client_slime_die|test_bosses.luau -a slime_die 1 client"
	"client_slime_attacks|test_bosses.luau -a slime_attacks 1 client"
	"client_tuber_full|test_bosses.luau -a tuber_full 1 client"
	"client_tuber_reset|test_bosses.luau -a tuber_reset 1 client"
	"client_tuber_attacks|test_bosses.luau -a tuber_attacks 1 client"
	"server_knight_full|test_bosses.luau -a knight_full 1"
	"server_knight_attacks|test_bosses.luau -a knight_attacks 1"
	"client_knight_full|test_bosses.luau -a knight_full 1 client"
	"client_knight_attacks|test_bosses.luau -a knight_attacks 1 client"
	"server_kaze_full|test_bosses.luau -a kaze_full 1"
	"server_kaze_attacks|test_bosses.luau -a kaze_attacks 1"
	"client_kaze_full|test_bosses.luau -a kaze_full 1 client"
	"client_kaze_attacks|test_bosses.luau -a kaze_attacks 1 client"
	"server_car_full|test_bosses.luau -a car_full 1"
	"server_car_attacks|test_bosses.luau -a car_attacks 1"
	"client_car_full|test_bosses.luau -a car_full 1 client"
	"client_car_attacks|test_bosses.luau -a car_attacks 1 client"
	"server_grid_full|test_bosses.luau -a grid_full 1"
	"server_grid_attacks|test_bosses.luau -a grid_attacks 1"
	"client_grid_full|test_bosses.luau -a grid_full 1 client"
	"client_grid_attacks|test_bosses.luau -a grid_attacks 1 client"
)
mode=${1:-check}
only=${2:-}
fails=0
for entry in "${SCENARIOS[@]}"; do
	name=${entry%%|*}
	cmd=${entry#*|}
	case "$name" in "$only"*) ;; *) continue ;; esac
	out=$("$LUAU" $cmd 2>&1)
	if ! echo "$out" | grep -q "^PASS"; then
		echo "FAIL  $name (didn't finish: no PASS)"
		echo "$out" | tail -6
		fails=$((fails + 1))
		continue
	fi
	# (saved squashed with gzip: the traces are long)
	if [ "$mode" = "record" ]; then
		echo "$out" | gzip -9n > "golden/$name.txt.gz"
		echo "saved $name ($(echo "$out" | wc -l) lines)"
	else
		if [ ! -f "golden/$name.txt.gz" ]; then
			echo "FAIL  $name (no golden copy: run ./golden.sh record first)"
			fails=$((fails + 1))
		elif diff -q <(echo "$out") <(gzip -dc "golden/$name.txt.gz") >/dev/null; then
			echo "same  $name"
		else
			echo "DIFF  $name  (new < > golden)"
			diff <(echo "$out") <(gzip -dc "golden/$name.txt.gz") | head -12
			fails=$((fails + 1))
		fi
	fi
done
echo "$fails failed"
exit $fails
