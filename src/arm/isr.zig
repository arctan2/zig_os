const uart = @import("uart");

pub const ISR = packed struct(u32) {
    _: u5,
    F: u1,
    I: u1,
    A: u1,
    __: u24,

    pub fn print(self: *const ISR) void {
        uart.print("isr {{ a = {}, i = {}, f = {} }\n", .{
            @as(u32, @intCast(self.A)),
            @as(u32, @intCast(self.I)),
            @as(u32, @intCast(self.F))
        });
    }
};

pub fn read() ISR {
    return asm volatile(
        "mrc p15, 0, %[val], c12, c1 ,0"
        : [val] "=r" (->ISR)
    );
}
