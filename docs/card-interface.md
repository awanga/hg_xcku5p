# CPU-less PCIe card: interface reference (proposed for freeze at v1.0)

What a host driver, the UART test rig, or another project built on `-card` can rely on. The module headers are the authority for each register; this page lists them in one place and states the change policy. Version words let software check what it talks to.

## BAR0 (host) = rig address 0xF8000000 + offset, 64 KiB, 32-bit accesses
| Offset | Block | Layout word | Source of truth |
|---|---|---|---|
| 0x1000 | `card_regs` (identity, build, status, scratch, LED) | LAYOUT = 1 at +0x04, ID "CARD" 0x43415244 | `fpga/rtl/card_regs.v` |
| 0x2000 | `user_regs` (16 control, 16 status, kick, event/enable, `irq`) | 0x00010000 at +0x8C | `fpga/rtl/user_regs.v` |
| 0x4000..0x7FFF | `user_ip` (reference block: ID "UIP1" 0x55495031, CAPS {layout 1, UIRQ, UMEM} at +0x04, IRQ_SET/PEND/SEEN, START, one `mem_probe` per DDR4 port at 0x100 + 0x40 * i) | layout in CAPS[31:16] = 1 | `fpga/rtl/user_ip.v`, `fpga/rtl/mem_probe.v` |
| 0xA000 | `pcie_regs` (doorbells, mailbox, DMA window) | ID 0x50434901 | `fpga/rtl/pcie_regs.v` |
| other | unmapped: DECERR from the register crossbar (a read returns an error, the bus keeps working) | | `fpga/rtl/card_top.v` |
`user_ip` is replaced by a user's IP, so its map is the reference one, not a fixed one: a new IP keeps the window and changes the ID and layout word. The identity of the card (vendor, device, subsystem IDs, class, revision) is in `card_regs` and in `fpga/pcie_identity.cfg`.

## Host data path
XDMA H2C/C2H (BAR1/DMA engine of the Xilinx XDMA core, driver `xdma`) to DDR4 (0x40000000, 1 GiB) through the window of `pcie_regs`: closed at reset, opened by writing WIN_BASE (+0xA070) and WIN_SIZE (+0xA074).

## Interrupts to the host
XDMA user interrupts (MSI, or INTx when MSI is off): vector 0 CPU/host doorbell of `pcie_regs`, vector 1 `user_regs` `irq`, vectors 2..7 the `user_ip` lines (`UIRQ` of them). One message per assertion; a handler clears the cause and re-reads until none is pending (`fpga/rtl/irq_req.v`).

## UART rig (UART2, 230400 baud, 8N1, LF-terminated lines)
`W aaaaaaaa dddddddd` -> `OK`; `R aaaaaaaa` -> `dddddddd`; `B aaaaaaaa nnnn` -> n lines; `I` interrupt vector; `V` -> `HGRIG1`; `ERR` on a bus error or a malformed line. Addresses 0x40000000..0x7FFFFFFF go to DDR4, the rest to the peripheral crossbar. `fpga/rtl/uart_rig.v`, host side `tools/rig.py`.

## Build interface (`fpga/scripts/build_soc.tcl`)
`-card` (implies `-nocpu -pcie`), `-umem N` (1..15 user DDR4 ports, default 2, 14 verified), `-uirq N` (1..6, default 6), `-strategy`. Generics of `card_top`: `UMEM`, `UIRQ`, `CARD_VERSION`, `CARD_BUILD`, `PCI_ID`, `PCI_CLASS`, `PCI_SUBSYS` (the last three from the manifest).

## Change policy from v1.0
- A change that alters the meaning of an existing register, offset or command needs a new layout version word and a major release; adding registers in unused space or a new window in a free BAR0 range is a minor release.
- Free BAR0 space for new windows: 0x0000..0x0FFF, 0x3000..0x3FFF, 0x8000..0x9FFF and 0xB000..0xFFFF (`user_ip` owns 0x4000..0x7FFF and may be replaced). A new window needs a crossbar slave in `build_soc.tcl` and `card_top.v`.
- The rig protocol is additive (new command letters only).

## Not part of the interface
Board peripherals (none in `-card`), the `mem_probe` timing, the crossbar arbitration order, and anything marked "reference" above.
