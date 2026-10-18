# CPU out-of-context synthesis (2026-10-18)

Evidence class: **Vivado synthesis only** (no place/route, no simulation, no board). Vivado 2026.1, part xcku5p-ffvb676-2-i,
`synth_design -mode out_of_context -flatten_hierarchy rebuilt`, clock constraint 8.0 ns on the core clock. Results in docs/decisions/0001.

Commands (work dir `build/`, third-party checkouts pinned as in 0001):
- VexiiRiscv: `fpga/scripts/cpu/gen_vexii.sh vexii_linux32 --xlen=32 $COMMON`, RV64 with `--xlen=64`, where
  `COMMON="--with-mul --with-div --allow-bypass-from=0 --fetch-l1 --fetch-l1-ways=4 --fetch-l1-mem-data-width-min=64 --lsu-l1 --lsu-l1-ways=4 --lsu-l1-mem-data-width-min=64 --with-lsu-bypass --relaxed-branch --with-btb --with-ras --with-gshare --with-rva --with-supervisor --performance-counters=0"`
  (mirrors LiteX `vexiiriscv` "linux" variant arguments); then `vivado -mode batch -source fpga/scripts/cpu/ooc_verilog.tcl -tclargs <name> VexiiRiscv clk 8.0 <outdir> <VexiiRiscv.v>`.
- VexRiscv SMP: pre-generated `VexRiscvLitexSmpCluster_Cc1_Iw64Is8192Iy2_Dw64Ds8192Dy2_ITs4DTs4_Ldw128_Cdma_Ood.v` + `Ram_1w_1rs_Generic.v`, clock port `debugCd_external_clk`.
- CVA6: copy `core/include/<cfg>_config_pkg.sv` to `<cfg>_fpgaen_config_pkg.sv` with `FpgaEn: bit'(1)`;
  `vivado -mode batch -source fpga/scripts/cpu/ooc_cva6.tcl -tclargs <cva6 dir> <cfg>_fpgaen 8.0 <outdir>` (reads `core/Flist.cva6` recursively).
- Without FpgaEn the CVA6 numbers were 22175/10550 LUT/FF (RV32) and 46650/23250 (RV64): the FPGA RAM mapping reduces logic only slightly.

Known limitations: cache configurations differ by core; CVA6 RV64 shows 0 BRAM (caches not mapped or pruned) and needs a wrapper re-run; no peripherals,
debug module or interrupt controller are included in any row.
