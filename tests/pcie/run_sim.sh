#!/bin/bash
# SPDX-License-Identifier: MIT
# Root-port simulations of the PCIe endpoint in Vivado's xsim (slow: minutes to tens of minutes per test; not part of scripts/ci.sh).
# usage: tests/pcie/run_sim.sh [testname...]   default: pcie_ep_regs pcie_ep_dma; pcie_ep_nocpu runs the CPU-less build's endpoint (separate default-off test)
# Needs Vivado (settings64.sh sourced or at /opt/Xilinx/2026.1/Vivado). Logs: build/pcie_sim/<test>.log, one PASS/FAIL line per test.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
out=$here/build/pcie_sim
[ -n "${XILINX_VIVADO:-}" ] || source /opt/Xilinx/2026.1/Vivado/settings64.sh
mkdir -p "$out"
if [ ! -d "$out/bfm/exd/xdma_0_ex/imports" ]; then
	vivado -mode batch -nojournal -log "$out/bfm.log" -source "$here/tests/pcie/gen_bfm.tcl" -tclargs "$out/bfm" >/dev/null 2>&1
	grep -q BFM_DONE "$out/bfm.log" || { echo "FAIL bfm generation (see $out/bfm.log)"; exit 1; }
fi
tests=("$@")
[ ${#tests[@]} -gt 0 ] || tests=(pcie_ep_regs pcie_ep_dma)
rc=0
for t in "${tests[@]}"; do
	unset PCIE_NOCPU
	[ "$t" = pcie_ep_nocpu ] && export PCIE_NOCPU=1
	vivado -mode batch -nojournal -log "$out/$t.log" -source "$here/tests/pcie/sim.tcl" -tclargs "$out/$t" "$out/bfm" "$t" >/dev/null 2>&1
	if grep -q "$t: Test Completed Successfully" "$out/$t.log" && ! grep -q -E "ERROR:|TEST FAIL" "$out/$t.log"; then
		echo "PASS $t"
	else
		echo "FAIL $t (see $out/$t.log)"; grep -E "ERROR|TEST FAIL" "$out/$t.log" | head -5; rc=1
	fi
done
exit $rc
