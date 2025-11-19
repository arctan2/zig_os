.section .vectors, "ax", %progbits
.align 2
.code 32

vector_table:
	ldr pc, =_reset_handler
	ldr pc, =_undef_handler
	ldr pc, =_svc_handler
	ldr pc, =_pabort_handler
	ldr pc, =_dabort_handler
	nop
	ldr pc, =_irq_handler
	ldr pc, =_fiq_handler

.section .text
.align 2
.code 32

.extern irq_handler
.extern reset_handler
.extern undef_handler
.extern svc_handler
.extern pabort_handler
.extern dabort_handler
.extern fiq_handler

_irq_handler:
	cpsid i
	sub lr, lr, #4
	// save the lr(which is the pc actually of interrupted task) along with r0-r12 and spsr
	push {r0-r12, lr} // irq_stack += 56 bytes
	mrs r0, spsr
	push {r0} // irq_stack += 4 bytes

	// now go into the mode from spsr and grab the lr and sp of the task mode
	and r0, r0, #0x1f // r0 already has spsr so just get last 5 bits to get the mode
	mrs r1, cpsr // r1 = cpsr
	bic r1, r1, #0x1f // clear last 5 bits
	cmp r0, #0x10
	beq is_user_mode
is_other_than_user_mode:
	orr r0, r0, r1 // new cpsr
	msr cpsr, r0 // switch to whatever previously mode was
	b end_if_else
is_user_mode:
	cps #0x1f // switch to system mode
end_if_else:
	mov r0, lr
	mov r1, sp
	cps #0x12 // irq mode
	push {r0, r1} // irq_stack += 8 bytes
	mov r0, sp
	bl irq_handler // returns r0 = sp of next task
	add sp, sp, #68 // reset the irq_stack
	ldr r1, [r0, #8]
	msr cpsr, r1
	ldr lr, [r0]
	mov sp, r0
	add sp, sp, #12
	ldmia sp!, {r0-r12, pc}

_reset_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl reset_handler
	pop {r0-r12, lr}
	subs pc, lr, #0

_undef_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl undef_handler
	pop {r0-r12, lr}
	subs pc, lr, #0

_svc_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl svc_handler
	pop {r0-r12, lr}
	subs pc, lr, #0

_pabort_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl pabort_handler
	pop {r0-r12, lr}
	subs pc, lr, #0

_dabort_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl dabort_handler
	pop {r0-r12, lr}
	subs pc, lr, #0

_fiq_handler:
	sub lr, lr, #4
	push {r0-r12, lr}
	bl fiq_handler
	pop {r0-r12, lr}
	subs pc, lr, #0
