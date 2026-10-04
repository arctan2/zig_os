# zig_os docs

A 32-bit ARMv7-A kernel written in Zig. It targets QEMU `virt` with a Cortex-A7 CPU, a GICv2, and 512 MiB of RAM.

These docs follow the code path from reset to the point where `kernel_main` tries to start `/bin/init`.

| Doc | Covers |
|-----|--------|
| [boot.md](boot.md) | `_start` → `early_kernel`: the first L1 table, TTBCR/TTBR1/DACR/SCTLR, turning on the MMU, the jump to the high half |
| [kernel_main.md](kernel_main.md) | Each step of `kernel_main`, ending at `initProcess` and the idle loop |
| [memory.md](memory.md) | Physical/virtual memory map, short-descriptor page tables, address-offset helpers, page allocator, kernel heap |
| [interrupts.md](interrupts.md) | Vector table, VBAR, GICv2, generic timer, IRQ frame layout, context switch |
| [references.md](references.md) | ARM ARM sections, GIC/timer/PL011 specs, devicetree, QEMU, Linux equivalents |

## Build and run

The kernel links `ramdisk/zig-out/initramfs.o`, so build the ramdisk first:

```sh
(cd ramdisk && zig build)   # builds init, packs a newc cpio, objcopies it to initramfs.o
zig build                   # zig-out/bin/kernel
zig build run               # qemu-system-arm -M virt,gic-version=2 -cpu cortex-a7 -m 512 -nographic -kernel zig-out/bin/kernel
```

Debugging: run `zig build drun` (QEMU with `-s -S`) in one terminal, then `zig build gdb` or `zig build lldb` in another. `zig build objdump` writes the disassembly to `zig-out/dump.S`.

Unit tests run on the host: `zig build test -Dtest_filter=<name>`. The `Makefile` also has a Docker target for them.

Host tools: Zig 0.16, `qemu-system-arm`, `cpio`, and `arm-none-eabi-objcopy` (macOS) or `arm-linux-gnueabi-objcopy` (Linux).

## The whole flow at a glance

```
QEMU loads ELF at its LMA (0x4000_0000), r2 = DTB phys
 └─ _start                      src/asm/start.S        mask IRQ/FIQ, sp = _stack_top_early
     └─ early_kernel            src/asm/early_kernel.S MMU off, physical addresses
         ├─ l1_zero_init        zero 16 KiB L1 at _kernel_l1_page_table_phys
         ├─ setup_l1            identity + high-half + FDT 1 MiB sections
         ├─ TTBR1, DACR, TTBCR.N=2, SCTLR (M,C,V,RR)
         └─ jump_to_kernel_main sp = _vstack_top, r2 = FDT virt, pc = kernel_main (0xC01x_xxxx)
             └─ kernel_main     src/kernel/main.zig    SVC mode, high half
                 ├─ mmio.init               UART -> 0xF000_0000, GIC -> 0xF010_0000
                 ├─ KernelBounds            RAM from FDT /memory
                 ├─ mapFreePagesToKernelL1  linear map of all RAM at PA + 0x8000_0000
                 ├─ setKernelTextPermissions
                 ├─ map vectors at 0xFFF0_0000
                 ├─ unmapIdentityKernel     drop VA 0x4000_0000
                 ├─ getInitRamfs            copy cpio to top of RAM
                 ├─ page_alloc.initGlobal   buddy allocator over free RAM
                 ├─ initStacks              IRQ and SYS mode stacks
                 ├─ scheduler.init          idle task
                 ├─ InitRamFs + vfs.dock    cpio -> ramfs at /initramfs
                 ├─ initProcess             open /initramfs/bin/init, parse ELF, allocTask
                 ├─ interrupts.setup        VBAR, GIC dist + CPU iface
                 ├─ timers.enable           PPI 30 (non-secure phys timer)
                 ├─ cpsie i ; cps #0x10     unmask IRQ, drop to User mode
                 └─ scheduler.idle          wfi loop
```
