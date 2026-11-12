#!/bin/bash
# SPDX-License-Identifier: MIT
# Device-tree checks without hardware: every .dts builds warning-free, the memory node and the peripheral
# addresses/interrupts match tests/dts/expected_map.txt, and a mutated DTS (moved UART) is rejected.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
b=$here/build/dts_tests
rm -rf "$b"; mkdir -p "$b"
fail=0

build() { # dts out
	cpp -nostdinc -undef -x assembler-with-cpp -I"$here/linux/dts" "$1" |
		dtc -I dts -O dtb -W no-unit_address_vs_reg -W no-simple_bus_reg -o "$2" - 2>"$2.err"
}

check_map() { # dtb
	local dts comp base irq node
	dts=$b/$(basename "$1").dts
	dtc -I dtb -O dts -o "$dts" "$1" 2>/dev/null
	grep -E 'reg = <0x40000000 0x40000000>' "$dts" >/dev/null || { echo "  memory is not 1 GiB at 0x40000000"; return 1; }
	local rc=0
	while read -r comp base irq; do
		case $comp in '#'*|'') continue ;; esac
		node=$(awk -v c="\"$comp" 'index($0, c) {f=1} f && /reg = </ {print; exit}' "$dts")
		echo "$node" | grep -qi "0x$base " || { echo "  $comp: base $base not found ($node)"; rc=1; }
		if [ "$irq" != "-" ]; then
			awk -v c="\"$comp" 'index($0, c) {f=1} f && /interrupts = </ {print; exit}' "$dts" |
				grep -Eq "<0x0*$(printf %x "$irq")>" || { echo "  $comp: interrupt $irq not found"; rc=1; }
		fi
	done <"$here/tests/dts/expected_map.txt"
	return $rc
}

for dts in "$here"/linux/dts/hg-xcku5p*.dts; do
	n=$(basename "$dts" .dts)
	if ! build "$dts" "$b/$n.dtb"; then echo "FAIL $n (dtc)"; cat "$b/$n.dtb.err"; fail=1; continue; fi
	if [ -s "$b/$n.dtb.err" ]; then echo "FAIL $n (warnings)"; cat "$b/$n.dtb.err"; fail=1; continue; fi
	if check_map "$b/$n.dtb"; then echo "PASS $n"; else echo "FAIL $n (map)"; fail=1; fi
done

# Mutant: the checker must reject a UART at the wrong address.
sed 's/0xf8000000 0x1000/0xf8007000 0x1000/' "$here/linux/dts/hg-xcku5p.dtsi" >"$b/hg-xcku5p.dtsi"
cp "$here/linux/dts/hg-xcku5p-sdroot.dts" "$b/mut.dts"
if build "$b/mut.dts" "$b/mut.dtb" && check_map "$b/mut.dtb" >/dev/null; then
	echo "FAIL mutant uart address was not caught"; fail=1
else
	echo "PASS mutant uart address caught"
fi
[ $fail -eq 0 ] && echo "DTS CHECKS PASS"
exit $fail
