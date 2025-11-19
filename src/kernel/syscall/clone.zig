const uart = @import("uart");

pub fn clone() void {
    uart.print("cloning", void);
}
