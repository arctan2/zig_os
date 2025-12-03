export fn _start() callconv(.naked) void {
    asm volatile(
        \\ mov r0, #1
        \\ mov r1, #2
        \\ mov r7, #7
        \\ swi #0
        \\ b .
    );
}
