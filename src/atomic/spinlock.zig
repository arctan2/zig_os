const std = @import("std");

const Self = @This();
const State = enum(u8) { Unlocked = 0, Locked = 1 };
const AtomicValue = std.atomic.Value(State);

value: AtomicValue = .init(.Unlocked),

pub fn lock(self: *Self) void {
    while(true) {
        switch(self.value.swap(.Locked, .acquire)) {
            .Locked => {},
            .Unlocked => break
        }
    }
}

pub fn tryLock(self: *Self) bool {
    return switch(self.value.swap(.Locked, .acquire)) {
        .Locked => false,
        .Unlocked => true
    };
}

pub fn unlock(self: *Self) void {
    self.value.store(.Unlocked, .release);
}
