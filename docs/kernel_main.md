# `kernel_main` → init process

File: `src/kernel/main.zig`. Entry state is described in [boot.md](boot.md#register-state-on-entry-to-kernel_main).

## 1. The kernel address space

```zig
const kernel_l1_phys = arm.ttbr.read(1);
var kvma = VirtAddrSpace{ .l1 = physToL1Virt(kernel_l1_phys), .l1_phys = kernel_l1_phys };
```

`kvma.l1` points to the boot L1 through its high alias: `0x4000_8000 + KERNEL_OFFSET` = `0xC000_8000`. From here on, every page-table edit goes through `VirtAddrSpace.mapAddr` / `unmapAddr` (`mm/vma.zig`). All phys ↔ virt conversions use `KERNEL_OFFSET` ([memory.md](memory.md#address-offset-helpers-mmkglobalzig)).

## 2. MMIO: `mmio.init(&kvma, fdt_base)`

`mmio_mapper` hands out consecutive 1 MiB virtual slots starting at `kglobal.MMIO_BASE = 0xF000_0000`:

| VA | PA | Device |
|---|---|---|
| `0xF000_0000` | `0x0900_0000` | PL011 UART. `uart.setBase(0x0900_0000)` first records the physical base, then switches to the VA |
| `0xF010_0000` | `0x0800_0000` | GICv2. Distributor at `+0x0`, CPU interface at `+distr_size` (`0x1_0000`) |

The GIC addresses come from the FDT: the node with an `interrupt-controller` property, its `reg` entries 0 (distributor base), 1 (distributor size), and 2 (CPU interface base). `gicv2.D` / `gicv2.C` store absolute register addresses (`setBase` adds the base to every offset field).

## 3. RAM bounds: `fdt.getMemStartSize`, `KernelBounds.init`

`/memory@40000000` `reg` gives start = `0x4000_0000` and size = `0x2000_0000` (512 MiB).

```
kernel_size_phys  = (early end - early start) + (vkernel end - vkernel start)  = 1 MiB + 2 MiB
free_region_start = mem_start + kernel_size_phys                               = 0x4030_0000
free_region_size  = mem_end - free_region_start
```

## 4. Linear map: `mm.mapFreePagesToKernelL1`

For every 1 MiB of RAM from `0x4000_0000` up to `mem_end`:

```
kvma.mapAddr(pa + KERNEL_OFFSET, pa, .Section, .KernelRW)
```

This makes VA `0xC000_0000–0xE000_0000` a linear map of all RAM. `mapAddr` only fills **Fault** entries, so the sections `early_kernel` already created (`0xC00`–`0xC08`, the FDT) keep their boot descriptors (AP = 0).

## 5. `mm.setKernelTextPermissions`

Sets **KernelRW** (APX:AP = `0:01`) on:

- the FDT's section, and
- L1 entries `0xC00` … `(pages_meta_end >> 20)`, where `pages_meta_end` = `align_1MiB(KERNEL_OFFSET + free_region_start + page_metadata_size)` = `0xC050_0000`. This covers the kernel image and the page-allocator metadata that `initGlobal` writes later. Boot entries 0xC06–0xC08 are not covered and keep AP = 0 ([memory.md caveats](memory.md#caveats)).

These are the boot entries that step 4 skipped. Nothing is made read-only or execute-never yet. Because DACR is Manager, AP bits are not enforced anyway ([boot.md caveats](boot.md#caveats)).

## 6. Vector alias

```zig
kvma.mapAddr(0xFFF0_0000, &_early_kernel_end /* 0x4010_0000 */, .Section, .KernelRO)
```

`0x4010_0000` is the LMA of `.vectors`, the first thing in the high kernel. VBAR is pointed at this alias in step 14.

## 7. `mm.unmapIdentityKernel`

Clears the L1 entry for VA `0x4000_0000`. The `0xC000_0000` alias of the early kernel (and the L1 table) stays mapped. No TLB invalidate is issued (see [memory.md caveats](memory.md#caveats)).

## 8. `kglobal.getInitRamfs`

The ramdisk is linked into the kernel's `.data` section (`_binary_initramfs_img_cpio_{start,end,size}`, produced by `objcopy -I binary` in `ramdisk/build.zig`). The `.initramfs_img` output section in linker.ld stays empty.

The page allocator in step 9 hands out every page from `free_region_start` up, so before that runs, the cpio is copied to `alignBackward(mem_end - size, 1 MiB)` (currently PA `0x5FF0_0000`) through the linear map. That range is not removed from the allocator ([memory.md caveats](memory.md#caveats)).

## 9. `mm.page_alloc.initGlobal(free_region_start, free_region_size, KERNEL_OFFSET)`

This sets up a binary buddy allocator (`MAX_ORDER = 11`, so the largest block is 1024 pages = 4 MiB):

- A `Page` metadata array (12 bytes per 4 KiB page of the free region) is placed at `free_region_start + KERNEL_OFFSET` = `0xC030_0000` (PA `0x4030_0000 – 0x4047_DC00`), directly after the kernel image.
- Allocatable memory starts at `base_addr = align_1MiB(free_region_start + metadata_size)` = `0x4050_0000`.
- All whole 4 MiB blocks are linked into `free_list[10]`.

After this call, `mm.kalloc` works. It is a `std.heap.DebugAllocator` backed by `kbacking_alloc`, which allocates whole pages and returns `phys + KERNEL_OFFSET`. Details: [memory.md](memory.md#allocators).

## 10. `initStacks`

```asm
cps #0x12 ; mov sp, _irq_stack_top   @ IRQ mode
cps #0x1f ; mov sp, _sys_stack_top   @ System mode (shares SP with User)
cps #0x13                            @ back to SVC
```

Abort, Undefined, and FIQ modes still have no stack.

## 11. `scheduler.init(kvma)`

Fills `idle_task`: `vma = kvma`, `pc = idle`, `sp = _vstack_top`, CPSR = current CPSR with Mode = User and I = unmasked, priority 31. It sets bit 31 in the runnable bitmask. See [interrupts.md](interrupts.md#scheduler-tick-and-context-switch).

## 12. Filesystems

```zig
const ctx = fs.InitRamFs.init(mm.kalloc, initramfs_img);   // fs/initramfs.zig
vfs.dock(mm.kalloc, "initramfs", fs.InitRamFs.fs_ops, ctx, .Ram);
```

- `InitRamFs.init` walks the newc cpio (`fs/cpio.zig`) until the `TRAILER!!!` entry. For each entry it creates the path's directories and the file in a `Ramfs` (`fs/ramfs.zig`), then applies the owner r/w/x bits from the cpio mode.
- `vfs.dock` registers the filesystem under the name `initramfs`, so its root is reachable at `/initramfs/...`.

## 13. `initProcess` → `process.createElf`

```zig
f    = vfs.open(alloc, "/initramfs/bin/init", .{ .read = 1 });
elf  = binfmt.elf.init(alloc, f);                     // reads + validates ElfHeader
task = scheduler.Task.allocTask(mm.kalloc, kernel_l1);
elf.loadPTLoads(alloc, &task.vma);                    // one .segment VMA per PT_LOAD
task.vma.mmap(alloc, 0xbfffffff, 64 KiB, .stack, null, 0);
task.cpu_state = idle_task.cpu_state; task.cpu_state.pc = e_entry; task.priority = 30;
scheduler.add(task);
```

- `allocTask` → `VirtAddrSpace.init` → `L1PageTable.init`. This allocates a 4-page (16 KiB) buddy block, which is naturally 16 KiB aligned as TTBR requires, and copies all 4096 kernel L1 entries into it. `l1_phys` is its physical address.
- `loadPTLoads` only records VMAs (`p_vaddr`, `p_memsz`, file, `p_offset`). No page tables are touched and nothing is read from the file.
- The task's L1 is installed in TTBR0 by `scheduler.switchTo` the first time the task is scheduled.

When the task first runs, `pc = e_entry` (`0x200ec`) is unmapped and every instruction page is demand-mapped by `pabort_handler` ([interrupts.md](interrupts.md#prefetch-abort-demand-paging)). The handler does not yet copy the ELF contents into the page, so the task runs zero-filled memory.

The init binary (`ramdisk/init.zig`) is a naked `_start` that does `mov r0,#1; mov r1,#2; mov r7,#7; swi #0`, which is the EABI syscall convention (number in r7). `svc_handler` currently prints and hangs.

## 14. Interrupts and timer

```zig
interrupts.setup(&fdt_accessor);   // SCTLR.V = 0, VBAR = 0xFFF0_0000, GIC D.init + C.init
devices.timers.enable(&fdt_accessor);
interrupts.enable();               // cpsie i
```

Details in [interrupts.md](interrupts.md).

## 15. Drop to User mode and idle

```zig
asm volatile("cps #0x10");   // User mode, SP = _sys_stack_top
scheduler.idle();            // print "idle", then wfi forever
```

From here, `kernel_main`'s own thread *is* the idle task. It runs in User mode and still prints to the UART, which works only because DACR = Manager. Timer IRQs now drive `scheduler.tick`.
