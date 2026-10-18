# Agent Instructions

## Source of truth
- Read `README.md` before planning or changing implementation. It contains scope, requirements, architecture, acceptance criteria, and the CPU/build-system trade studies.
- Read `TASKS.md`; resume from the first unblocked incomplete task. Update status and evidence in the same change as completed work.
- Read relevant `docs/decisions/`, `docs/versions.md`, and hardware inventory before changing CPU, memory, clocks, pins, address maps, boot, or tool versions.
- If requirements conflict or a major choice is unresolved, document the conflict and ask rather than silently deciding.

## Engineering priorities
- Correctness and reproducibility first; performance per FPGA resource second; minimal dependencies unless a measured improvement in performance, size, complexity, power, or workflow justifies them.
- Respect the README's resource/performance acceptance rule. Measure before claiming improvement.
- Prefer upstream Linux drivers, bindings, and fixes. Keep local patches small, ordered, documented, and upstreamable.
- Never infer pin assignments, bus wiring, polarity, memory topology, or component identity from marketing copy. Use the schematics and record uncertainty.
- Treat MicroBlaze V Linux/MMU capability as unverified until the exact configuration and supported kernel path are demonstrated.
- Keep 100G optics out of MVP critical path.
- Use Vivado for supported target-device implementation. Open tools may be used for checks/simulation where suitable, not as an assumed replacement for the required vendor flow.

## Workflow
- Make small, cohesive changes. Use Git feature branches/PRs; keep `main` buildable. Do not use numbered commit messages.
- Before implementation, inspect existing files and repository state. Avoid overwriting user changes.
- Pin external sources by release/tag/commit and record versions/hashes. Do not silently track moving branches in release builds.
- Add tests with behavior changes. Distinguish simulation, synthesis, and physical-board evidence.
- Run the narrowest relevant checks, then broader checks when practical. Report commands, outcomes, skipped checks, and blockers accurately.
- Do not claim hardware validation without a physical test and captured evidence.
- Do not commit generated build trees, bitstreams, credentials, license data, private keys, or secrets. Release artifacts belong in CI artifacts/releases, not normal source history.
- Do not make an optimization without baseline measurements and resource/timing comparisons.

## Deliverables and documentation
- Keep RTL, constraints, memory map, device tree, boot configuration, kernel configuration, and rootfs configuration consistent.
- Any change to clocks, resets, DDR, CPU features, address map, boot flow, or driver bindings must update relevant docs/tests.
- For every local kernel patch, record purpose, base version, test, and upstream status.
- CI must protect licensed tools and physical hardware: never run untrusted fork code on a privileged self-hosted runner.
- Keep `TASKS.md` statuses current (`[ ]`, `[-]` in progress, `[x]` complete) and attach evidence/commit IDs for meaningful milestones.
- If blocked, record the blocker, required input, and safe next step rather than marking the task complete.

## Completion standard
A task is complete only when its acceptance criteria pass, relevant checks are run, outputs are reviewed, and documentation/status are updated. If a check cannot run, state why; do not imply success.
