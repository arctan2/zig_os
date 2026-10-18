# Memory

Files: `linker.ld`, `src/mm/*.zig`, `src/arm/ttbr.zig`, `src/arm/arm.zig`.

## Physical map (QEMU virt, `-m 512`)

```
0x0800_0000  GICv2 distributor          (FDT intc reg[0])
0x0801_0000  GICv2 CPU interface        (FDT intc reg[2])
0x0900_0000  PL011 UART
0x4000_0000  ┬ _start / .text.boot      ─┐
             │ .bss.boot (_fdt_base)     │ early kernel (1 MiB)
0x4000_41a8  │ _stack_top_early          │
0x4000_8000  │ boot L1 table (16 KiB)    │
0x4010_0000  ┼ .vectors .text .data ...  ─┤ high kernel LMA (2 MiB)
0x4030_0000  ┼ free_region_start         ─┘
             │ Page metadata (0x4030_0000 – 0x4047_DC00)
0x4050_0000  │ base_addr: buddy-allocated pages
0x5FF0_0000  │ initramfs copy (getInitRamfs)
0x6000_0000  ┴ end of RAM
```

Addresses inside the image (`0x4000_41a8`, `0x4030_0000`, …) are from the current build. Use `llvm-nm zig-out/bin/kernel` to get fresh values.

## Virtual map (after `kernel_main` step 7)

```
0xC000_0000 ─ 0xE000_0000   linear map of all RAM: VA = PA + KERNEL_OFFSET (0x8000_0000)
  0xC000_8000                 boot L1 table
  0xC010_0000                 _vkernel_start: vector_table, .text, .data, .bss, .rodata
  0xC025_39D8                 _irq_stack_top    (4 KiB)
  0xC025_79D8                 _sys_stack_top    (16 KiB, System/User)
  0xC025_B9D8                 _pabort_stack_top (16 KiB, unused)
  0xC025_F9D8                 _vstack_top       (16 KiB, SVC)
  0xC030_0000                 _vkernel_end
  0xC030_0000                 Page metadata (written by initGlobal)
0xF000_0000                 UART  (1 MiB section)
0xF010_0000                 GIC   (1 MiB section)
0xFFF0_0000                 vector table alias → PA 0x4010_0000 (VBAR)
```

All of this is in the TTBR1 range (VA ≥ 1 GiB because TTBCR.N = 2). The kernel uses only 1 MiB sections. User mappings (VA < 1 GiB, through TTBR0) are 4 KiB small pages in L2 tables, created on demand by `pabort_handler` ([interrupts.md](interrupts.md#prefetch-abort-demand-paging)).

## Short-descriptor translation tables

ARM ARM B3.5. One L1 table has 4096 × 4-byte entries, each covering 1 MiB, indexed by VA[31:20]. One L2 table has 256 entries, each covering 4 KiB, indexed by VA[19:12]. `vma.VirtAddress` splits a VA into `l1_idx:12 | l2_idx:8 | offset:12`.

L1 entry types (`page_table.L1EntryType`, bits[1:0]):

| bits | Type | Zig type |
|---|---|---|
| `00` | Fault | — |
| `01` | Pointer to L2 table (base[31:10]) | `L2TableAddr` |
| `10` | Section (base[31:20]) | `SectionEntry` |

`SectionEntry` field order (LSB first) is `type:2, B, C, XN, domain:4, P, AP:2, TEX:3, APX, S, nG, 0, NS, base:12`, which matches ARM ARM B3.5.1, Figure "Short-descriptor first-level descriptor formats".

L2 entries: `SmallPage` (`10`/`11`, 4 KiB) and `LargePage` (`01`, 64 KiB).

### Access permissions

`SectionEntry.setPermissions` encodes APX:AP[1:0] with `SCTLR.AFE = 0` (ARM ARM B3.7.1, table "VMSAv7 MMU access permissions"):

| `Permissions` | APX:AP | PL1 | PL0 |
|---|---|---|---|
| `KernelRW` | `0:01` | RW | none |
| `KernelRO` | `1:01` | RO | none |
| `UserRW` | `0:11` | RW | RW |
| `UserRO` | `1:10` | RO | RO |

These bits are only checked for domains set to **Client** in DACR. Right now every domain is Manager ([boot.md](boot.md#caveats)).

Memory attributes (TEX/C/B) are never set, so every mapping, RAM included, is Strongly-ordered (ARM ARM B3.8.2, "Short-descriptor format memory region attributes, without TEX remap").

### Kernel vs. user half

- Hardware split: TTBCR.N = 2, so VA < `0x4000_0000` goes through TTBR0 and everything else through TTBR1 (ARM ARM B3.5.4). `scheduler.switchTo` writes the next task's `vma.l1_phys` to TTBR0. TTBR1 always holds the boot L1.
- Software split: `L1PageTable.freeEntries` treats entries `0 .. 0xC00` (VA < `0xC000_0000`, `kglobal.getEarlyKernelStartVirt()`) as per-process. A task's L1 is a full copy of the kernel L1 (`L1PageTable.init`).

### TLB maintenance

Helpers in `arm/arm.zig`:

| Helper | Op | Encoding |
|---|---|---|
| `invalidateTLBUnified` | TLBIALL | `c8, c7, 0` |
| `invalidateTLBEntry(va)` | TLBIMVA | `c8, c7, 1` |
| `invalidateICache` | ICIALLU | `c7, c5, 0` |
| `invalidateBranchPredictor` | BPIALL | `c7, c5, 6` |

Each is followed by `dsb; isb`. Architectural rules (ARM ARM B3.10):

- Changing a **Fault** entry to valid needs no TLB invalidate, because faulting entries are never cached in the TLB. A `DSB` (+`ISB`) is enough to make the new entry visible.
- Changing or removing a **valid** entry needs TLBIMVA (or TLBIALL) for that VA, followed by `DSB; ISB`.
- Without ASIDs (`nG = 0` everywhere), switching address spaces needs TLBIALL. `scheduler.switchTo` does this when the next task's `vma.l1` differs from the current one.

## Address-offset helpers (`mm/kglobal.zig`)

| Helper | Formula | Used by |
|---|---|---|
| `physToVirtByKernelOffset` / `virtToPhysByKernelOffset` | `± KERNEL_OFFSET` (`0x8000_0000`, linker constant) | every phys ↔ kernel-pointer conversion: `physToL1Virt`, `physToL2Virt`, `L1PageTable.init`/`free`, `L2PageTable.getPhysAddr`/`free`, `kbacking_alloc`, `getInitRamfs`, `mapFreePagesToKernelL1`, `setKernelTextPermissions` |

There is one kernel linear map, VA = PA + `KERNEL_OFFSET`, so this pair is the only conversion. `page_alloc.initGlobal` takes the offset as a parameter (`KERNEL_OFFSET` in the kernel, 0 in tests).

Physical addresses from `pageToPhys` go to the MMU unchanged (L1/L2 descriptors, TTBR). Convert only when the kernel itself needs to read or write the memory.

In unit tests (`builtin.is_test`) both helpers are identity functions, and `KERNEL_OFFSET` is exported as 0.

## Allocators

### Page allocator (`mm/page_alloc.zig`)

A binary buddy allocator. `PAGE_SIZE = 4 KiB`, `MAX_ORDER = 11` (orders 0–10, max block 1024 pages = 4 MiB).

- `Page { prev, next, flags, order }`: one per page. `flags` holds `Allocated` and `BlockStart`.
- `allocPages(n)` rounds `n` up to a power of two (more than 1024 returns `TooBig`). If the free list for that order is empty, it splits the next larger block. The result is a `*Page`, and `pageToPhys` = `base_addr + idx * 4 KiB`.
- `freeBlock` merges the block with its buddy as far up as it can. `freeAddr(phys)` frees by physical address.
- Buddy blocks are aligned to their own size relative to the 1 MiB-aligned `base_addr`, so a 4-page block meets TTBR's 16 KiB alignment.

### Kernel heap

```
mm.kalloc  = DebugAllocator(.{ .safety = false, .MutexType = SpinLock })
             └─ backing: kbacking_alloc.allocator
                         alloc(len)  → allocPages(ceil(len / 4K)) → phys + KERNEL_OFFSET
                         free(mem)   → freeAddr(virt - KERNEL_OFFSET)
                         resize/remap unsupported
```

`std_options.page_size_{min,max} = 4 KiB` and `os.heap.page_allocator = kbacking_alloc.allocator` in `main.zig`, so `std` sees these as the platform allocators.

### Virtual memory areas (`mm/vma.zig`)

`VirtAddrSpace` holds:

- `l1`: this address space's L1 table (kernel pointer).
- `l1_phys`: its physical address, the value written to TTBR0.
- `vma_list` + `vma_rbtree`: `VirtAllocation { start, size, type, file, file_off }` regions, stored as a sorted list plus an RB-tree keyed by `start`.

Methods:

- `mapAddr(virt, phys, .{.type = .Section | .L2}, perm)`: installs a single mapping and allocates an L2 table when needed. It never allocates backing pages, and it does nothing if the entry is already valid. `perm` is applied only to sections; L2 small pages are created with AP = 0.
- `unmapAddr(virt)`: zeroes the L1 section entry or the L2 entry. It never frees L2 tables.
- `mmap(alloc, start, size, type, file)`: inserts a `VirtAllocation`, merging it with neighbours of the same type and file. It returns `AlreadyMapped` if the range overlaps an existing one. It does not touch page tables.

## Caveats

- **Everything in the image must end before `_vkernel_end`.** `KernelBounds` assumes the kernel ends there, and `initGlobal` writes the `Page` array at `_vkernel_end`'s physical address (`0x4030_0000`). linker.ld therefore collects `.text.*` and `.rodata.*` explicitly. Zig emits string literals and constants into `.rodata.str1.1`, `.rodata.cst*`, `.rodata.__anon_*`, and so on. With only `*(.rodata)` they were placed as orphan sections after `_vkernel_end` and overwritten by the metadata. Check with `objdump -h zig-out/bin/kernel` that nothing non-empty has a VMA ≥ `0xC030_0000`.
- **Allocator range overruns RAM.** `initGlobal` sets `base_addr = 0x4050_0000` (past the metadata) but still manages `floor(free_region_size / 4 MiB)` = 127 blocks counted from `free_region_start`. The last block ends at `0x6010_0000`, 1 MiB past the end of RAM. The initramfs copy at `0x5FF0_0000` is also inside the managed range. Blocks are handed out from low addresses first, so neither problem shows up yet.
- **Boot sections 0xC06–0xC08 keep AP = 0.** `early_kernel` maps `0xC000_0000–0xC08F_FFFF`. `mapFreePagesToKernelL1` skips them because they are already valid, and `setKernelTextPermissions` only covers up to the end of the metadata (0xC05). That is allocator memory (`0x4060_0000–0x408F_FFFF`), which would fault once DACR is set to Client.
- **Missing TLB invalidation** after `setKernelTextPermissions` (valid → valid) and `unmapIdentityKernel` (valid → fault). QEMU's softmmu TLB can keep the old translation until the next TLBIALL.
