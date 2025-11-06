.global _start
.section .text.boot
.align 2
.code 32

_start:
	cpsid i
	cpsid f

	ldr sp, =_stack_top_early
	bl early_kernel
hang:
	b hang

