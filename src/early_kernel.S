.section .text.boot
.global early_kernel
.align 2
.code 32

.extern _kernel_l1_page_table_phys
.extern KERNEL_OFFSET
.extern PHYS_BASE
.extern VIRT_BASE
.extern _early_kernel_start
.extern _early_kernel_end
.extern _vkernel_start
.extern _vkernel_end
.extern _vstack_top
.extern _kernel_l1_page_table_phys

early_kernel:
	ldr r0, =_kernel_l1_page_table_phys
	bl l1_zero_init
	bl setup_l1

hang:
	b hang

l1_zero_init:
	push {lr}

	mov r1, #0
	mov r2, #0

	l1_zero_init_loop:
		cmp r1, #4096
		beq l1_zero_init_loop_end
		str r2, [r0, r1, LSL #2]
		add r1, r1, #1
		b l1_zero_init_loop
	l1_zero_init_loop_end:

	pop {pc}
	bx lr

@ fn kernelMapSection(kmem: *VirtMemHandlerEarly, virt: usize, phys: usize) linksection(".text.boot") void {
@     const virt_addr: VirtAddressEarly = @bitCast(virt);
@     const l1_idx = virt_addr.l1_idx;
@     const entry: *SectionEntryEarly = @ptrCast(&kmem.l1.entries[l1_idx]);
@     entry.section_addr = @intCast(phys >> 20);
@     entry.type = .Section;
@ }
@
@ for(0..3) |i| {
@ 	const virt = @intFromPtr(&kglobal.VIRT_BASE) + (mm.page_alloc.SECTION_SIZE * i);
@ 	const phys = @intFromPtr(&kglobal._early_kernel_end) + (mm.page_alloc.SECTION_SIZE * i);
@ 	const ident = @intFromPtr(&kglobal.PHYS_BASE) + (mm.page_alloc.SECTION_SIZE * i);
@ 	kernelMapSection(&kmem, ident, ident);
@ 	kernelMapSection(&kmem, virt, phys);
@ }
@
@ const VirtAddressEarly = packed struct(u32) {
@     offset: u12,
@     l2_idx: u8,
@     l1_idx: u12,
@ };

setup_l1:
	push {lr}

	ldr r1, =_vkernel_start
	ldr r2, =_early_kernel_end

	bl kernel_map_section

	ldr r1, =_early_kernel_start
	ldr r2, =_early_kernel_start

	bl kernel_map_section

	pop {pc}
	bx lr


kernel_map_section: @ r0 = l1, r1 = virt, r2 = phys
	push {lr}
	mov r1, r1, LSR #20 @ l1_idx
	ldr r3, =0xfff00000
	and r2, r2, r3
	add r2, r2, #2
	str r2, [r0, r1, LSL #2] @ l1[l1_idx] = r2

	pop {pc}
	bx lr


.section .bss.boot, "aw", %nobits
.align 4

kernel_size: .word 0
