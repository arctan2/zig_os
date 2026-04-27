pub const Bitmask = packed struct(usize) {
    bits: usize,

    pub fn default() Bitmask {
        return .{
            .bits = 0
        };
    }

    pub inline fn countZeros(self: *Bitmask) usize {
        return @ctz(self.bits);
    }

    pub inline fn set(self: *Bitmask, number: usize) void {
        self.bits |= (@as(usize, 1) << @intCast(number));
    }

    pub inline fn clear(self: *Bitmask, number: usize) void {
        self.bits &= ~(@as(usize, 1) << @intCast(number));
    }
};
