const std = @import("std");
const mm = @import("mm");
const arm = @import("arm");
const utils = @import("utils");
const ListNode = utils.types.ListNode;
const Queue = utils.types.Queue;
const Bitmask = utils.types.Bitmask;
const uart = @import("uart");

// do not ever change the positions of the fields in this because the entire
// irq handler will break
pub const CpuState = extern struct {
    lr: usize = 0,
    sp: usize = 0,
    cpsr: arm.cpsr.CPSR = @bitCast(@as(u32, 0)),
    registers: [13]usize = .{0} ** 13,
    pc: usize = 0,
};

const TimeSlice = struct {
    const DEFAULT: usize = 10;
};

pub fn TaskInfo(comptime SchedState: type) type {
    return struct {
        const T = TaskInfo(SchedState);

        cpu_state: CpuState,
        sch_state: SchedState,
        id: usize,
        state: enum {
            Running,
            Interruptable,
            Blocked,
        },
        priority: usize,
        vma: mm.vma.Vma,
        time_remaining: usize,
        children: ?*ListNode(T, "children"),
        parent: ?*T,

        pub fn default() T {
            return .{
                .cpu_state = .{},
                .sch_state = .{},
                .id = 0,
                .state = .Running,
                .priority = 31,
                .vma = undefined,
                .time_remaining = TimeSlice.DEFAULT,
                .children = null,
                .parent = null,
            };
        }

        pub fn allocTask(gpa: std.mem.Allocator) !*T {
            const task = try gpa.create(T);
            task.* = T.default();
            return task;
        }

        fn saveStateResetTimeSlice(self: *T, irq_cpu_state: *CpuState) void {
            self.time_remaining = TimeSlice.DEFAULT;
            self.cpu_state = irq_cpu_state.*;
        }
    };
}

const SchedulerState = struct {
    const ListNodeType = ListNode(SchedulerState, "list_node");
    list_node: ListNodeType = .{.next = null},

    pub fn toTask(self: *SchedulerState) *Task {
        return @fieldParentPtr("sch_state", self);
    }
};
pub const Task = TaskInfo(SchedulerState);

pub var idle_task = Task.default();

pub const Scheduler = struct {
    runnable: [32]Queue(SchedulerState.ListNodeType) = .{Queue(SchedulerState.ListNodeType).default()}**32,
    bitmask: Bitmask = .default(),
    current_task: *Task,
};

pub var global = Scheduler{
    .current_task = &idle_task
};

pub fn init(kvmem: mm.vma.Vma) void {
    idle_task.vma = kvmem;
    idle_task.cpu_state = .{
        .lr = 0,
        .sp = @intFromPtr(&mm.kglobal._vstack_top),
        .cpsr = @bitCast(arm.cpsr.read()),
        .registers = .{0}**13,
        .pc = @intFromPtr(&idle),
    };
    idle_task.cpu_state.cpsr.Mode = .User;
    idle_task.cpu_state.cpsr.I = .Unmaksed;
    global.bitmask.set(idle_task.priority);
}

pub fn idle() void {
    uart.print("idle\n", .{});
    while (true) {
        asm volatile("wfi");
    }
}

pub inline fn currentTask() *Task {
    return global.current_task;
}

pub fn next() *Task {
    const idx = global.bitmask.countZeros();
    return global.runnable[idx].head.?.container().toTask();
}

pub fn add(task: *Task) void {
    global.runnable[task.priority].enqueue(&task.sch_state.list_node);
    global.bitmask.set(task.priority);
}

fn schedule() void {
    const idx = global.bitmask.countZeros();
    if(idx == 32) return;
    global.runnable[global.current_task.priority].insertFront(&global.current_task.sch_state.list_node);
    if(global.runnable[idx].dequeue()) |node| {
        global.runnable[idx].enqueue(node);
    }
}

fn remove(task: *Task) void {
    _ = global.runnable[task.priority].remove(&task.sch_state.list_node);
    if(global.runnable[task.priority].isEmpty()) {
        global.bitmask.clear(task.priority);
    }
}

fn switchTo(task: *Task, prev_task_cpu_state: *CpuState) void {
    global.current_task.cpu_state = prev_task_cpu_state.*;
    add(global.current_task);
    // uart.print("{x} != {x}\n", .{@intFromPtr(global.current_task.vma.l1), @intFromPtr(task.vma.l1)});
    if(@intFromPtr(global.current_task.vma.l1) != @intFromPtr(task.vma.l1)) {
        arm.invalidateTLBUnified();
    }
    global.current_task = task;
}

fn tryContextSwitch(irq_cpu_state: *CpuState) void {
    const next_task = next();
    remove(next_task);
    switchTo(next_task, irq_cpu_state);
    irq_cpu_state.* = next_task.cpu_state;
}

pub fn tick(irq_cpu_state: *CpuState) void {
    if(global.current_task.time_remaining == 0) {
        global.current_task.saveStateResetTimeSlice(irq_cpu_state);
        schedule();
        tryContextSwitch(irq_cpu_state);
    }

    global.current_task.time_remaining -= 1;
}

