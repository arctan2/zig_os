// .global _start
// .section .text
// .align 2
// .code 32
// 
// _start:
//     ldr sp, =_stack_top
// 	mov r0, #0
//     bl kernel_main
// hang:
//     b hang

.global _start
.section .text
.align 2
.code 32

_start:
	cpsid i
	cpsid f

	ldr sp, =_stack_top
	bl kernel_main

hang:
    b hang

