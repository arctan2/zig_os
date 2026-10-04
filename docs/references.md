# References

Section numbers refer to the editions listed. If a number has moved in another edition, search for the section title.

## ARM architecture

**ARM Architecture Reference Manual, ARMv7-A and ARMv7-R edition** (ARM DDI 0406C.d)
<https://developer.arm.com/documentation/ddi0406/latest/>

| Topic | Section | Used in |
|---|---|---|
| Processor modes, banked registers | B1.3 | `initStacks`, IRQ entry |
| Exception vectors, VBAR, high vectors | B1.8.1 | `interrupts.setup`, `SCTLR.V` |
| Link values / return offsets per exception | B1.8.3 | `vector_table.S` stubs |
| VMSA overview | B3.1–B3.3 | — |
| Short-descriptor translation table format | B3.5 | `page_table.zig`, `early_kernel.S` |
| Short-descriptor descriptor formats (Section, L2 pointer, Small/Large page) | B3.5.1 | `SectionEntry`, `L2TableAddr`, `SmallPage`, `LargePage` |
| Selecting TTBR0 vs. TTBR1 (TTBCR.N) | B3.5.4 | `TTBCR.N = 2` |
| Access permissions (AP/APX) | B3.7.1 | `SectionEntry.setPermissions` |
| Domains (DACR) | B3.7.3 | DACR = `0xFFFF_FFFF` |
| Memory region attributes (TEX/C/B) | B3.8.2 | (all mappings Strongly-ordered) |
| TLB maintenance requirements | B3.10 | `invalidateTLB*`, `switchTo` |
| Cache and branch predictor maintenance ops | B4.2.1 | `clean_state`, `arm.zig` |
| TLB maintenance ops | B4.2.2 | `TLBIALL`, `TLBIMVA` |
| DACR | B4.1.43 | |
| SCTLR | B4.1.130 | `arm/sctlr.zig` |
| TTBCR | B4.1.153 | `arm/ttbr.zig` |
| TTBR0 / TTBR1 | B4.1.154 / B4.1.155 | `arm/ttbr.zig` |
| VBAR | B4.1.156 | `arm/vbar.zig` |
| Generic Timer (CNTFRQ, CNTP_CTL, CNTP_TVAL) | Chapter B8 | `arm/generic_timer.zig` |
| PSR / CPSR format | B1.3.3 | `arm/cpsr.zig` |

**Cortex-A7 MPCore Technical Reference Manual** (ARM DDI 0464F): implementation details of the MMU, caches, and the generic timer on the CPU QEMU emulates.
<https://developer.arm.com/documentation/ddi0464/latest/>

**ARM Cortex-A Series Programmer's Guide for ARMv7-A** (ARM DEN0013D): readable explanations to go with the ARM ARM. Relevant chapters are *Caches*, *The Memory Management Unit*, *Exception Handling*, *Interrupt Handling*, and *Boot Code*.
<https://developer.arm.com/documentation/den0013/latest/>

## Peripherals

**ARM Generic Interrupt Controller Architecture Specification v2** (ARM IHI 0048B.b)
<https://developer.arm.com/documentation/ihi0048/latest/>

| Topic | Section |
|---|---|
| Interrupt ID ranges (SGI/PPI/SPI) | 2.2.1 |
| Interrupt handling, IAR/EOIR flow | 3.2 |
| Priority and PMR | 3.3 |
| Distributor registers (GICD_*) | 4.3 (ISENABLER 4.3.5, ICENABLER 4.3.6) |
| CPU interface registers (GICC_*) | 4.4 |

**PrimeCell UART (PL011) Technical Reference Manual** (ARM DDI 0183G): `UARTDR` at 0x000, `UARTFR` at 0x018, `TXFF` = FR bit 5 (`mmio/uart.zig`).
<https://developer.arm.com/documentation/ddi0183/latest/>

## Devicetree

- **Devicetree Specification v0.4**, chapter 5 "Flattened Devicetree (DTB) Format" (header, structure block tokens, strings block). Used by `src/fdt/`. <https://www.devicetree.org/specifications/>
- GIC binding (3-cell `interrupts`, PPI +16 / SPI +32): Linux `Documentation/devicetree/bindings/interrupt-controller/arm,gic.yaml`
- Arch timer binding (interrupt order: secure phys, non-secure phys, virt, hyp): Linux `Documentation/devicetree/bindings/timer/arm,arch_timer.yaml`
- The board's tree: `device_trees/qemu.dts` (dump with `dtc -I dtb -O dts`).

## Boot protocol

- Linux `Documentation/arch/arm/booting.rst`: the `r0 = 0, r1 = machine type, r2 = DTB` convention and the CPU state expected at entry (MMU off, SVC, IRQs masked).
- QEMU `virt` board: <https://www.qemu.org/docs/master/system/arm/virt.html>. Memory map: `base_memmap[]` in QEMU `hw/arm/virt.c`. Direct kernel boot and DTB placement: `hw/arm/boot.c`.

## Formats

- **cpio newc**: Linux `Documentation/driver-api/early-userspace/buffer-format.rst`, `man 5 cpio`. Used by `fs/cpio.zig`.
- **ELF**: System V gABI <https://refspecs.linuxfoundation.org/elf/gabi4+/contents.html>; *ELF for the Arm Architecture* (ARM IHI 0044) <https://github.com/ARM-software/abi-aa/releases>. Used by `binfmt/elf.zig`.
- **ARM EABI syscall convention** (number in r7, `svc #0`): `man 2 syscall`, "Architecture calling conventions".

## Comparable code in Linux (arch/arm)

| This project | Linux |
|---|---|
| `early_kernel` page-table setup | `arch/arm/kernel/head.S`: `__create_page_tables` |
| MMU enable + jump to high half | `head.S`: `__enable_mmu`, `__turn_mmu_on` |
| TTBCR/TTBR split | `arch/arm/mm/proc-v7-2level.S`, `proc-v7.S` (`__v7_setup`) |
| Page-table write + clean | `proc-v7-2level.S`: `cpu_v7_set_pte_ext` |
| TLB ops | `arch/arm/include/asm/tlbflush.h` |
| Vector table / exception entry | `arch/arm/kernel/entry-armv.S` |
| GICv2 driver | `drivers/irqchip/irq-gic.c` |
| Arch timer | `drivers/clocksource/arm_arch_timer.c` |
