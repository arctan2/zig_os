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
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'I'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _reset_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'J'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _undef_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'K'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _svc_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'L'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _pabort_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'M'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _dabort_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'N'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

pub export fn _fiq_handler() callconv(.naked) void {
    asm volatile (
        \\ ldr r0, =0xF0000000
        \\ mov r1, #'O'
        \\ str r1, [r0]
        \\ b .
        // \\ sub lr, lr, #4
        // \\ push {r0-r12, lr}
        // \\ bl irq_handler
        // \\ pop {r0-r12, lr}
        // \\ subs pc, lr, #0
    );
}

