const std = @import("std");

const UART_BASE: usize = 0x09000000;
const UART_DR: *volatile u32 = @ptrFromInt(UART_BASE + 0x00);
const UART_FR: *volatile u32 = @ptrFromInt(UART_BASE + 0x18);

pub fn putc(c: u8) void {
    while ((UART_FR.* & (1 << 5)) != 0) {}
    UART_DR.* = c;
}

pub fn puts(s: []const u8) void {
    for (s) |c| {
        putc(c);
    }
}

pub fn put_number(comptime T: type, num: T) void {
    var reversed: [64]u8 = [_]u8{0} ** 64;
    var n = num;

    if (n == 0) {
        putc('0');
        return;
    }

    if (n < 0) {
        putc('-');
        n = -n;
    }

    if (n == 0) {
        putc('0');
        return;
    }

    var count: usize = 0;

    while (n != 0) {
        const d: u8 = @intCast(@rem(n, @as(u8, 10)));
        reversed[@intCast(count)] = d + '0';
        count += 1;
        n = @divTrunc(n, 10);
    }

    while (count > 0) {
        count -= 1;
        putc(reversed[count]);
    }
}

pub fn put_hex(comptime T: type, num: T) void {
    var reversed = [_]u8{0} ** 64;
    var n = num;

    puts("0x");

    if (n == 0) {
        putc('0');
        return;
    }

    if (n < 0) {
        putc('-');
        n = -n;
    }

    if (n == 0) {
        putc('0');
        return;
    }

    var count: usize = 0;

    const num_map = [_]u8{'a', 'b', 'c', 'd', 'e', 'f'};

    while (n != 0) {
        const d: u8 = @intCast(@rem(n, @as(u8, 16)));
        if(d < 10) {
            reversed[@intCast(count)] = d + '0';
        } else {
            reversed[@intCast(count)] = num_map[d - 10];
        }
        count += 1;
        n = @divTrunc(n, 16);
    }

    while (count > 0) {
        count -= 1;
        putc(reversed[count]);
    }
}
