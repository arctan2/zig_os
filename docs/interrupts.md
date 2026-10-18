# Interrupts, timer, scheduling

Files: `src/asm/vector_table.S`, `src/kernel/interrupts.zig`, `src/kernel/interrupt_handlers.zig`, `src/kernel/scheduler.zig`, `src/mmio/gicv2.zig`, `src/arm/generic_timer.zig`, `src/devices/timers.zig`.

## Vector table

`.vectors` is the first output section of the high kernel (VA `0xC010_0000`, PA `0x4010_0000`). Each slot is `ldr pc, =_xxx_handler`, which loads from a literal pool in the same section, so the table works from any alias.

| Offset | Exception | Stub → Zig handler |
|---|---|---|
| `0x00` | Reset | `_reset_handler` → `reset_handler` (print, hang) |
| `0x04` | Undefined | `_undef_handler` → `undef_handler` (print, hang) |
| `0x08` | SVC | `_svc_handler` → `svc_handler` (print, hang) |
| `0x0C` | Prefetch abort | `_pabort_handler` → `pabort_handler` (demand-map a page, return; see below) |
| `0x10` | Data abort | `_dabort_handler` → `dabort_handler` (print, hang) |
| `0x14` | — | `nop` |
| `0x18` | IRQ | `_irq_handler` → `irq_handler` (see below) |
| `0x1C` | FIQ | `_fiq_handler` → `fiq_handler` (print, hang) |

`interrupts.setup` clears `SCTLR.V` and writes `VBAR = 0xFFF0_0000`, the alias mapped in [kernel_main step 6](kernel_main.md#6-vector-alias). VBAR requires the Security Extensions, which Cortex-A7 has. The address must be 32-byte aligned. See ARM ARM B1.8.1 and B4.1.156.

Only IRQ and System modes get stacks (`initStacks`). An undefined-instruction, abort, or FIQ exception runs its stub on an uninitialised banked SP.

## GICv2 (`mmio/gicv2.zig`)

Interrupt IDs: SGI 0–15, PPI 16–31, SPI 32–1019 (GICv2 spec §2.2.1). `fdt.InterruptProp.toIntrId` converts a devicetree `<type num flags>` triple to an ID with type 0 = SPI (+32), 1 = PPI (+16).

`gicv2.D.init` (distributor, GICv2 §4.3):
1. Writes 0 to `GICD_ISENABLERn[0..31]`.
2. Sets every `GICD_IPRIORITYRn` byte to `0xFF` (lowest priority).
3. Sets every `GICD_ITARGETSRn` byte to `0x01` (CPU 0).
4. Sets `GICD_ICFGRn[2..63]` to 0 (level-sensitive).
5. Clears all pending bits through `GICD_ICPENDRn`.
6. Writes `GICD_CTLR = 1`.

`gicv2.C.init` (CPU interface, GICv2 §4.4): `GICC_CTLR = 1`, `GICC_PMR = 0xF0`. Only interrupts with a priority value below `0xF0` are signalled. Everything stays at `0xFF` except the timer.

At runtime, `irq_handler` reads `GICC_IAR` to acknowledge and writes the same ID to `GICC_EOIR` when done (GICv2 §3.2).

## Generic timer (`devices/timers.zig`, `arm/generic_timer.zig`)

The FDT `timer` node (`arm,armv7-timer`) lists four interrupts in the order secure physical, non-secure physical, virtual, hypervisor. Index 1 is `<1 14 ...>` = PPI 14 = **ID 30**, the non-secure physical timer (EL1 physical timer).

`timers.enable`:

```
D.setPriority(30, 0); D.configure(30, .Level); D.enableIrq(30)
CNTP_TVAL = freq                        // c14, c2, 0
freq = CNTFRQ; CNTP_CTL.enable = 1, imask = 0   // c14, c0, 0 / c14, c2, 1
```

Each IRQ reloads `CNTP_TVAL = 10000` counter ticks. Generic Timer reference: ARM ARM chapter B8.

## IRQ entry and exit (`_irq_handler`)

On entry, the CPU is in IRQ mode, `LR_irq` = interrupted PC + 4, and `SPSR_irq` = interrupted CPSR (ARM ARM B1.8.3).

```asm
sub lr, lr, #4
push {r0-r12, lr}          @ interrupted r0-r12 and return PC
mrs r0, spsr ; push {r0}   @ interrupted CPSR
@ switch to the interrupted mode (User → System, since they share SP/LR) to read its banked sp/lr
mov r0, lr ; mov r1, sp
cps #0x12 ; push {r0, r1}
mov r0, sp ; bl irq_handler
```

The resulting frame on the IRQ stack is exactly `scheduler.CpuState` (68 bytes, field order must not change):

```
sp+0   lr        (banked LR of interrupted mode)
sp+4   sp        (banked SP of interrupted mode)
sp+8   cpsr      (SPSR_irq)
sp+12  r0 … r12
sp+64  pc        (return address)
```

`irq_handler(irq_sp)`:

1. `ack = GICC_IAR`.
2. If `ack.intr_id == 30`, call `scheduler.tick(frame)`, which may overwrite `*frame` with another task's state.
3. Copy `*frame` to `frame.sp - 68`, i.e. onto the **target task's own stack**, and return that pointer.
4. The `defer` block reloads `CNTP_TVAL` and writes `GICC_EOIR`.

Back in assembly:

```asm
add sp, sp, #68            @ IRQ stack is empty again
ldr r1, [r0, #8] ; msr cpsr, r1   @ switch straight into the target mode/CPSR
ldr lr, [r0]               @ restore banked LR
mov sp, r0 ; add sp, sp, #12
ldmia sp!, {r0-r12, pc}    @ pops the frame; SP ends at the task's original SP
```

The exit path does not use `SUBS pc, lr` or `RFE`. If the target CPSR has I = 0, IRQs are unmasked before the `ldmia` completes.

## Prefetch abort: demand paging

`_pabort_handler` does `sub lr, lr, #4`, saves `r0-r12, lr`, calls `pabort_handler`, restores, and returns with `subs pc, lr, #0`. That retries the faulting instruction. For a prefetch abort, `LR_abt - 4` is the faulting instruction (ARM ARM B1.8.3).

`pabort_handler`:

1. `addr = IFAR` (`arm/ifar.zig`). The fault type is in IFSR (`arm/ifsr.zig`): `0b00101` = translation fault, section (no L1 entry), `0b00111` = translation fault, page (L2 table exists, no entry).
2. `page = allocPages(1)` (panics `"memory full"` on failure).
3. `current_task.vma.mapAddr(addr, pageToPhys(page), .L2, .UserRO)`, which creates the L2 table if needed.

Current limitations:

- The handler never looks up the task's VMAs. Any address gets a page, and nothing is reported as a segfault.
- The page is not filled from the ELF file. Fresh QEMU RAM is zero, and `0x0000_0000` decodes as `andeq r0, r0, r0` (a no-op). So the init task executes 1024 no-ops per page, faults on the next page, and walks up through user space until memory runs out.
- `var task_vma = cur_task.vma` copies the `VirtAddrSpace`. Page-table writes still land because `l1` is a pointer, but any change to the VMA list or tree would be lost.
- `mapAddr` ignores `perm` for L2 pages, so the page gets AP = 0. This only works because DACR is Manager.

`dabort_handler` prints DFAR/DFSR (`arm/dfar.zig`, `arm/dfsr.zig`) and hangs.

## Scheduler tick and context switch

`scheduler.Scheduler`:
- `runnable[32]`: one FIFO queue per priority. 0 is the highest priority.
- `bitmask`: bit *p* is set when queue *p* is non-empty. `next()` picks the queue at `@ctz(bitmask)`.
- `current_task`: starts as `&idle_task` (priority 31).

`tick(frame)`:
1. If `current.time_remaining == 0`:
   - save `*frame` into the current task and reset its slice to 10 ticks,
   - `schedule()` requeues the current task and rotates the highest-priority queue,
   - `tryContextSwitch`: `next()` → `remove` → `switchTo` (re-enqueue the old task; if `vma.l1` differs, TLBIALL and write `next.vma.l1_phys` to TTBR0) → `*frame = next.cpu_state`.
2. `current.time_remaining -= 1`.

TTBR1 always holds the boot L1, so the kernel half is shared. TTBR0 is per task. The TLBIALL runs before the TTBR0 write; there is no barrier between the write and the return to the task.

## Caveats

- `timers.enable` calls `setTval(GenericTimer.freq)` **before** `GenericTimer.enable()` reads `CNTFRQ` into `freq`. The first interval uses whatever `freq` held (it is declared `undefined`).
- Writing 0 to `GICD_ISENABLERn` has no effect. Interrupts are disabled by writing 1 to `GICD_ICENABLERn` (GICv2 §4.3.5–4.3.6). `GICD_ITARGETSR0–7` (IDs 0–31) are read-only.
- The abort stubs use `lr - 4` for every exception. That is correct for prefetch aborts, but the data-abort return address is `lr - 8` (ARM ARM B1.8.3, table "Offsets applied to Link value for exceptions taken to PL1 modes"). This doesn't matter yet because `dabort_handler` never returns.
- Abort mode has no stack, yet `pabort_handler` now returns and runs on every user page fault. `_pabort_handler` pushes 56 bytes onto whatever SP_abt held at reset. A `_pabort_stack_top` gap already exists in linker.ld but `initStacks` never loads it.
