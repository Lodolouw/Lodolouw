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
for sc in clearleave leave die oldbuilder kite kitejump; do run test_colosseum.luau -a $sc 3; done
run test_client.luau
run test_builder.luau
echo "$fails failed"
exit $fails
