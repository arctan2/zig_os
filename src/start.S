.global _start
.global jump_to_kernel_main
.section .text.boot
.align 2
.code 32

_start:
	cpsid i
	cpsid f

	ldr sp, =_stack_top_early
	bl early_kernel_main
hang:
	b hang

jump_to_kernel_main:
	// r0: fdt_virt, r1: _stack_top, r2: entry
	mov sp, r1
	mov r3, r2
	mov r2, r0
	mov r0, #0
	mov r1, #0
	mov pc, r3
