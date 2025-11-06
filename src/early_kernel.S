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
.extern kernel_main

early_kernel: @ r2 = fdt_base
	ldr r1, =_fdt_base
	str r2, [r1]

	ldr r0, =_kernel_l1_page_table_phys
	bl l1_zero_init
	bl setup_l1

	bl clean_state

	mcr p15, 0, r0, c2, c0, 1 // write ttbr1

	ldr r1, =0xffffffff
	mcr p15, 0, r1, c3, c0, 0 // write domain

	mrc p15, 0, r1, c2, c0, 2 // read ttbcr
	orr r1, r1, #0x2
	mcr p15, 0, r1, c2, c0, 2 // write ttbcr

	mrc p15, 0, r1, c1, c0, 0 // read sctlr
	ldr r2, =0x6045
	orr r1, r1, r2
	mcr p15, 0, r1, c1, c0, 0 // write sctlr

	bl clean_state

	ldr r1, =_fdt_base
	ldr r1, [r1]
	ldr r0, =KERNEL_OFFSET
	add r0, r0, r1 // fdt_virt

	ldr r1, =_vstack_top
	ldr r2, =kernel_main

    bl jump_to_kernel_main

	// not reachable
hang:
	b hang

clean_state:
	push {r0-r1, lr}
	mov r1, #0

	mcr p15, 0, r1, c8, c7, 0 // invalidate tlb unified
	mcr p15, 0, r1, c7, c5, 6 // invalidate branch predictor
	mcr p15, 0, r1, c7, c14, 0 // clean invalidate d cache
	mcr p15, 0, r1, c7, c5, 0 // clean invalidate i cache
	dsb
	isb

	pop{r0-r1, pc}
	bx lr

jump_to_kernel_main: @ r0 = fdt_virt, r1 = _stack_top, r2 = entry
	mov sp, r1
	mov r3, r2
	mov r2, r0
	mov r0, #0
	mov r1, #0
	dsb
	isb
	mov pc, r3

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

setup_l1:
	push {r0-r3, lr}

	ldr r1, =_early_kernel_start
	ldr r2, =_early_kernel_start
	bl kernel_map_section

	ldr r1, =_vkernel_start
	subs r1, r1, #0x100000
	bl kernel_map_section

	mov r3, #0
	ldr r1, =_vkernel_start
	ldr r2, =_early_kernel_end

	setup_l1_loop:
		cmp r3, #3
		beq setup_l1_loop_end

		bl kernel_map_section

		add r1, #0x100000
		add r2, #0x100000
		add r3, r3, #1
		b setup_l1_loop
	setup_l1_loop_end:

	ldr r2, =_fdt_base
	ldr r2, [r2]
	ldr r1, =KERNEL_OFFSET
	add r1, r1, r2
	bl kernel_map_section

	pop {r0-r3, pc}
	bx lr


kernel_map_section: @ r0 = l1, r1 = virt, r2 = phys
	push {r0-r4, lr}

	mov r1, r1, LSR #20 @ l1_idx
	ldr r3, =0xfff00000
	and r2, r2, r3
	add r2, r2, #2
	str r2, [r0, r1, LSL #2] @ l1[l1_idx] = r2

	pop {r0-r4, pc}
	bx lr


.section .bss.boot, "aw", %nobits
.align 4

_fdt_base: .word 0
