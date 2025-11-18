pub export fn vector_table() linksection(".vectors") callconv(.naked) void {
    asm volatile (
        \\ ldr pc, =_reset_handler
        \\ ldr pc, =_undef_handler
        \\ ldr pc, =_svc_handler
        \\ ldr pc, =_pabort_handler
        \\ ldr pc, =_dabort_handler
        \\ nop
        \\ ldr pc, =_irq_handler
        \\ ldr pc, =_fiq_handler
    );
}

pub export fn _irq_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4

        // save the lr(which is the pc actually of interrupted task) along with r0-r12 and spsr
        \\ push {r0-r12, lr} // irq_stack += 56 bytes
        \\ mrs r0, spsr
        \\ push {r0} // irq_stack += 4 bytes

        // now go into the mode from spsr and grab the lr and sp of the task mode
        \\ and r0, r0, #0x1f // r0 already has spsr so just get last 5 bits to get the mode
        \\ mrs r1, cpsr
        \\ bic r1, r1, #0x1f
        \\ orr r0, r0, r1
        \\ msr cpsr, r0 // switch to whatever previously mode was
        \\ mov r0, lr
        \\ mov r1, sp
        \\ cps #0x12 // irq mode
        \\ push {r0, r1} // irq_stack += 8 bytes
        \\ mov r0, sp
        \\ bl irq_handler @ returns r0 = sp of next task
        \\ add sp, sp, #68 // reset the irq_stack
        \\ ldr r1, [r0, #8]
        \\ msr cpsr, r1
        \\ ldr lr, [r0]
        \\ mov sp, r0
        \\ add sp, sp, #12
        \\ ldmia sp!, {r0-r12, pc}
        ::: .{.memory = true}
    );
}

pub export fn _reset_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl reset_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}

pub export fn _undef_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl undef_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}

pub export fn _svc_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl svc_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}

pub export fn _pabort_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl pabort_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}

pub export fn _dabort_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl dabort_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}

pub export fn _fiq_handler() callconv(.naked) void {
    asm volatile (
        \\ sub lr, lr, #4
        \\ push {r0-r12, lr}
        \\ bl fiq_handler
        \\ pop {r0-r12, lr}
        \\ subs pc, lr, #0
    );
}
