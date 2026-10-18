# 0001 — CPU selection

- Status: proposed (no finalist approved; no measurements yet)
- Date: 2026-10-18

## Context
Main CPU must run an upstream-LTS Linux with MMU on XCKU5P-FFVB676-2-i, leaving fabric for custom AXI datapaths.
See README "CPU trade study" for the rubric and the resource/performance acceptance rule.

## Alternatives
In scope: VexRiscv/VexRiscv-SMP, VexiiRiscv, CVA6.
Removed by project decision 2026-10-18: AMD MicroBlaze V, Rocket Chip.
Excluded by README: MicroBlaze (classic), PicoRV32/Ibex/NEORV32 as main CPU.

## Decision
Pending. Evaluation of the three in-scope candidates is not started; nothing here is a measurement.

## Consequences
Pending.

## Validation
Pending: per-candidate LUT/FF/BRAM/URAM/DSP, Fmax/slack on the real part, Linux boot, DDR bandwidth, benchmarks.
Blocked on the Vivado install (see TASKS.md).

## Revisit triggers
A removed candidate is reintroduced by the user; a finalist cannot boot upstream Linux.
