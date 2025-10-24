const uart = @import("uart");

pub fn enableInterrupts() void {
    uart.print("enabling intruupt\n", void);
}
