const std = @import("std");
const mmio = @import("mmio");

var UART_BASE: usize = undefined;
var UART_DR: *volatile u32 = undefined;
var UART_FR: *volatile u32 = undefined;

pub fn setBase(base: usize) void {
    UART_BASE = base;
    UART_DR = @ptrFromInt(UART_BASE + 0x00);
    UART_FR = @ptrFromInt(UART_BASE + 0x18);
}

pub fn getUartBase() usize {
    return UART_BASE;
}

pub fn putc(c: u8) void {
    while ((UART_FR.* & (1 << 5)) != 0) {}
    UART_DR.* = c;
}

pub fn puts(s: []const u8) void {
    for (s) |c| {
        putc(c);
    }
}

pub fn putInt(comptime T: type, num: T) void {
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

pub fn putHex(comptime T: type, num: T) void {
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
        puts("00000000");
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

pub fn putBin(comptime T: type, num: T) void {
    var reversed = [_]u8{0} ** 64;
    var n = num;

    puts("0b");

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
        const d: u8 = @intCast(@rem(n, @as(u8, 2)));
        reversed[@intCast(count)] = d + '0';
        count += 1;
        n = @divTrunc(n, 2);
    }

    while (count > 0) {
        count -= 1;
        putc(reversed[count]);
    }
}

const NO_MATCHING_CURLY = "no matching close bracket found for `{`. Please use `{{` to escape the curly.";

fn printInternal(comptime fmt: []const u8, comptime begin: usize, comptime end: usize, comptime arg_idx: usize, args: anytype) void {
    const arg = args[arg_idx];
    const arg_type = @TypeOf(arg);
    const arg_type_info = @typeInfo(arg_type);

    switch(arg_type_info) {
        .int => {
            switch(fmt[begin]) {
                'x' => {
                    putHex(usize, @intCast(arg));
                },
                'c' => {
                    // very hacky way to support bit fields
                    if(arg < 255) {
                        if(arg == 1 or arg == 0) {
                            putInt(usize, arg);
                        } else {
                            putc(@intCast(arg));
                        }
                    } else {
                        putInt(usize, @intCast(arg));
                    } 
                },
                'b' => {
                    putBin(usize, @intCast(arg));
                },
                '}' => {
                    putInt(usize, @intCast(arg));
                },
                else => {
                    @compileError("invalid mode or " ++ NO_MATCHING_CURLY);
                }
            }
        },
        .bool => {
            puts(if(arg) "true" else "false");
        },
        .@"enum" => |_| {
            puts(@typeName(arg_type) ++ "(");
            printInternal(fmt, begin, end, 0, .{@intFromEnum(arg)});
            puts(")");
        },
        .@"struct" => |s| {
            puts(@typeName(arg_type) ++ "{");
            comptime var count = 0;
            inline for(s.fields) |f| {
                puts(f.name);
                puts(": ");
                printInternal(fmt, begin, end, 0, .{@field(arg, f.name)});
                if(count < s.fields.len - 1) puts(", ");
                count += 1;
            }
            puts("}");
        },
        .void => {
        },
        .optional => {
            if(arg) |val| {
                printInternal(fmt, begin, end, 0, .{val});
            } else {
                puts("null");
            }
        },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => {
                puts("{ len: ");
                putInt(usize, arg.len);
                puts(", items: [");
                for(arg, 0..) |a, i| {
                    printInternal(fmt, begin, end, 0, .{a});
                    if(fmt[begin] != 'c' and i < arg.len - 1) puts(", ");
                }
                puts("] }");
            },
            else => {
                printInternal(fmt, begin, end, 0, .{@intFromPtr(arg)});
            }
        },
        .array => {
            putc('[');
            comptime var count = 0;
            inline for(arg) |a| {
                printInternal(fmt, begin, end, 0, .{a});
                if(count < arg.len - 1) puts(", ");
                count += 1;
            }
            putc(']');
        },
        else => {
            @compileError("print not implemented for that type");
        }
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) linksection(".text") void {
    comptime var arg_idx = 0;
    comptime var i = 0;

    inline while(i < fmt.len) : (i += 1) {
        if(fmt[i] == '{') {
            if(i + 1 >= fmt.len) {
                @compileError(NO_MATCHING_CURLY);
            }

            const next_tok = fmt[i + 1];

            if(next_tok == '{') {
                putc('{');
                i += 1;
                continue;
            }

            const begin_curly = i;
            comptime var end_curly = i;

            inline while(end_curly < fmt.len and fmt[end_curly] != '}') : (end_curly += 1){}

            if(end_curly >= fmt.len) {
                @compileError(NO_MATCHING_CURLY);
            }

            printInternal(fmt, begin_curly + 1, end_curly, arg_idx, args);
            arg_idx += 1;

            i = end_curly;
        } else {
            putc(fmt[i]);
        }
    }
}

