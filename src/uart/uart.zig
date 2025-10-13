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

const NO_MATCHING_CURLY = "no matching close bracket found for `{`. Please use `{{` to escape the curly.";

fn printInternal(comptime fmt: []const u8, comptime begin: usize, comptime end: usize, comptime arg_idx: usize, args: anytype) void {
    const arg = args[arg_idx];
    const arg_type = @TypeOf(arg);
    const arg_type_info = @typeInfo(arg_type);

    switch(arg_type_info) {
        .int => {
            switch(fmt[begin]) {
                'x' => {
                    putHex(arg_type, arg);
                },
                'c' => {
                    putc(arg);
                },
                '}' => {
                    putInt(arg_type, arg);
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
        .void => {
        },
        .optional => {
            if(arg) |val| {
                printInternal(fmt, begin, end, 0, .{val});
            } else {
                puts("null");
            }
        },
        .pointer => {
            printInternal(fmt, begin, end, 0, .{@intFromPtr(arg)});
        },
        else => {
            @compileError("print not implemented for that type");
        }
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
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

