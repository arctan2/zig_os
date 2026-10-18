# Boot: `_start` → `kernel_main`

Files: `src/asm/start.S`, `src/asm/early_kernel.S`, `linker.ld`.

## Image layout (linker.ld)

The ELF has two halves with different link addresses:

| Region | VMA (link address) | LMA (load address) | Contents |
|---|---|---|---|
| Early kernel | `PHYS_BASE` = `0x4000_0000` | same | `.text.boot`, `.bss.boot`, 16 KiB early stack, 16 KiB L1 table |
| High kernel | `VIRT_BASE` = `0xC010_0000` | `0x4010_0000` | `.vectors`, `.text` (+ `.text.*`), `.data`, `.bss`, `.rodata` (+ `.rodata.*`), mode stacks |

Symbols defined in linker.ld:

- `_early_kernel_start` = `0x4000_0000`, `_early_kernel_end` = `0x4010_0000`. The early region is padded to 1 MiB so the high kernel's LMA is section-aligned.
- `_stack_top_early`: top of a 16 KiB stack right after `.bss.boot`.
- `_kernel_l1_page_table_phys`: a 16 KiB-aligned, 16 KiB L1 table. The alignment is required because TTBR holds bits [31:14] of the table address.
- `KERNEL_OFFSET = _vkernel_start - _early_kernel_end` = `0xC010_0000 - 0x4010_0000` = `0x8000_0000`. Every high-kernel VMA equals its LMA + `KERNEL_OFFSET`.
- `_irq_stack_top` (4 KiB), `_sys_stack_top`, `_pabort_stack_top`, `_vstack_top` (16 KiB each). These are gaps after `.rodata`, not output sections.
- `_vkernel_end`: rounded up to 1 MiB (currently `0xC030_0000`). Every non-empty section must end before it, because the page allocator's metadata is written there ([memory.md caveats](memory.md#caveats)).

QEMU's ELF loader places each segment at its LMA and zero-fills the `.bss` part of each segment (memsz > filesz). The kernel never clears `.bss` itself.

## `_start` (start.S)

```asm
cpsid i ; cpsid f          @ mask IRQ and FIQ
ldr sp, =_stack_top_early
bl early_kernel
```

QEMU starts the CPU in SVC mode with the MMU and caches off. `early_kernel` expects the DTB's physical address in `r2`, which is the ARM Linux boot register convention (`r0 = 0`, `r1 = machine type`, `r2 = DTB`; see [references](references.md#boot-protocol)).

## `early_kernel` (early_kernel.S)

Everything here runs at physical addresses. `ldr rX, =sym` gives link addresses, which equal physical addresses for `.text.boot` symbols. For high-kernel symbols such as `kernel_main` and `_vstack_top`, it gives the virtual address.

### 1. Save the DTB pointer

`r2` is stored to `_fdt_base`, a word in `.bss.boot`.

### 2. `l1_zero_init`

Writes 4096 zero words to `_kernel_l1_page_table_phys`. A zero entry is a Fault descriptor (bits[1:0] = `00`).

### 3. `setup_l1`: build 1 MiB section mappings

`kernel_map_section(r0 = l1, r1 = virt, r2 = phys)` writes

```
l1[virt >> 20] = (phys & 0xFFF0_0000) | 0b10
```

This is a short-descriptor **Section** entry: bits[1:0] = `10`, base address in [31:20], and every other field 0. That means domain 0, AP = `00`, TEX/C/B = 0 (Strongly-ordered), XN = 0. Field layout: ARM ARM B3.5.1. The Zig version of this layout is `page_table.SectionEntry`.

Mappings created:

| VA | PA | Why |
|---|---|---|
| `0x4000_0000` | `0x4000_0000` | Identity map of the early kernel, so the instruction stream keeps working after `SCTLR.M` is set |
| `0xC000_0000` | `0x4000_0000` | High alias of the early kernel. This makes the L1 table reachable at `0xC000_8000` later (`physToL1Virt`) |
| `0xC010_0000` … `0xC080_0000` (8 entries) | `0x4010_0000` … | The high kernel (8 MiB window, current image is 2 MiB) |
| `fdt_phys + 0x8000_0000` | `fdt_phys & ~0xFFFFF` | The DTB, so `kernel_main` can parse it |

### 4. `clean_state`

```asm
mcr p15,0,r1,c8,c7,0    @ TLBIALL   invalidate unified TLB
mcr p15,0,r1,c7,c5,6    @ BPIALL    invalidate branch predictor
mcr p15,0,r1,c7,c14,0   @ ARMv6 "clean+invalidate entire D-cache" (see caveats)
mcr p15,0,r1,c7,c5,0    @ ICIALLU   invalidate I-cache to PoU
dsb ; isb
```

This runs once before the MMU is turned on and once after. For TLB and cache maintenance requirements, see ARM ARM B3.10 and B4.2.

### 5. Program the translation registers

| Instruction | Register | Value | Effect |
|---|---|---|---|
| `mcr p15,0,r0,c2,c0,1` | TTBR1 | `_kernel_l1_page_table_phys` | Base of the L1 table. Walk attribute bits (IRGN/RGN/S) are 0, so walks are non-cacheable |
| `mcr p15,0,r1,c3,c0,0` | DACR | `0xFFFF_FFFF` | All 16 domains = `0b11` **Manager**: AP bits are **not checked** |
| `mcr p15,0,r1,c2,c0,2` | TTBCR | `N \|= 2` | VA < `0x4000_0000` (1 GiB) walks TTBR0, VA ≥ 1 GiB walks TTBR1 |

With N = 2, TTBR1 still points to a full 16 KiB table indexed by VA[31:20]. TTBR0 is never written, and every mapping the kernel makes is at or above 1 GiB. See ARM ARM B3.5.4 (TTBR0 vs. TTBR1) and B4.1.153 (TTBCR).

### 6. Enable the MMU

`SCTLR |= 0x6045`:

| Bit | Name | Meaning |
|---|---|---|
| 0 | M | MMU enable |
| 2 | C | Data/unified cache enable |
| 6 | — | RAO/SBOP on ARMv7 |
| 13 | V | High vectors (`0xFFFF_0000`). `interrupts.setup` clears this later and uses VBAR |
| 14 | RR | Round-robin cache replacement |

The I-cache (bit 12), branch prediction (bit 11), and alignment checking (bit 1) stay off. The `mov r2, #0x2000` after the write is dead code. Register reference: ARM ARM B4.1.130. The Zig view is `arm/sctlr.zig`.

The next instruction fetch goes through the MMU. It lands in the identity-mapped section, so execution continues at physical addresses.

### 7. Jump to the high half

```
r0 = fdt_phys + KERNEL_OFFSET    @ FDT virtual address
r1 = _vstack_top                 @ SVC stack (virtual)
r2 = kernel_main                 @ 0xC012_9BC8 in the current build
jump_to_kernel_main:
    sp = r1 ; r0 = 0 ; r1 = 0 ; r2 = fdt_virt
    dsb ; isb
    mov pc, r3
```

`kernel_main(u32, u32, fdt_base)` uses the same r0/r1/r2 order as the Linux convention, with r2 now a virtual address.

## Register state on entry to `kernel_main`

- Mode: SVC, IRQ/FIQ masked.
- MMU on, D-cache on, I-cache off.
- TTBR1 = the boot L1, TTBCR.N = 2, DACR = all Manager.
- SP = `_vstack_top`. No other mode has a stack yet.
- `SCTLR.V = 1`, so any exception vectors to unmapped `0xFFFF_0000`.

## Caveats

- **DACR = Manager everywhere.** Every AP/APX value written later (`KernelRO`, `UserRO`, …) is ignored by hardware. Permissions take effect only after the relevant domain is set to Client (`0b01`). See ARM ARM B3.7.3.
- **`c7, c14, 0`** (and `cleanDCache`/`invalidateDCache` in `arm/arm.zig`: `c7,c10,0` / `c7,c6,0`) are ARMv6 whole-cache operations that ARMv7-A does not define. On ARMv7 the whole D-cache is cleaned with a set/way loop (`DCCISW`, `c7,c14,2`). QEMU doesn't model caches, so this only matters on hardware.
- **Non-cacheable table walks with the D-cache on.** TTBR1 walk attributes are 0, but `kernel_main` edits the table through cacheable mappings. On hardware each edited descriptor needs a `DCCMVAU`/`DCCMVAC` clean before the walker sees it (ARM ARM B3.10.1, "General TLB maintenance requirements"; Linux does this in `cpu_v7_set_pte_ext`/`flush_pmd_entry`).
- The early mappings are Strongly-ordered (TEX/C/B = 0) even for RAM, so `SCTLR.C` has no effect on kernel memory yet.
