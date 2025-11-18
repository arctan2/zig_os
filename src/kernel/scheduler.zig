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
    lr: usize,
    sp: usize,
    cpsr: usize,
    registers: [13]usize,
    pc: usize,

    pub fn default() CpuState {
        return .{
            .registers = .{0}**13,
            .lr = 0,
            .pc = 0,
            .sp = 0,
            .cpsr = 0
        };
    }
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
        vm_handler: mm.vm_handler.VMHandler,
        time_remaining: usize,
        children: ?*ListNode(T, "children"),
        parent: ?*T,

        pub fn default() T {
            return .{
                .cpu_state = .default(),
                .sch_state = .default(),
                .id = 0,
                .state = .Running,
                .priority = 31,
                .vm_handler = undefined,
                .time_remaining = TimeSlice.DEFAULT,
                .children = null,
                .parent = null,
            };
        }

        fn saveStateResetTimeSlice(self: *T, irq_cpu_state: *CpuState) void {
            self.time_remaining = TimeSlice.DEFAULT;
            self.cpu_state = irq_cpu_state.*;
        }
    };
}

const SchedulerState = struct {
    const ListNodeType = ListNode(SchedulerState, "list_node");
    list_node: ListNodeType,

    pub fn default() SchedulerState {
        return .{
            .list_node = .{.next = null}
        };
    }

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

pub fn init(kvmem: mm.vm_handler.VMHandler) void {
    idle_task.vm_handler = kvmem;
    idle_task.cpu_state = .{
        .lr = 0,
        .sp = @intFromPtr(&mm.kglobal._vstack_top),
        .cpsr = @bitCast(arm.cpsr.read()),
        .registers = .{0}**13,
        .pc = @intFromPtr(&idle),
    };
    add(&idle_task);
}

pub fn idle() void {
    while (true) {
        uart.print("task 1 waiting\n", .{});
        asm volatile("wfi");
    }
}

pub inline fn currentTask() *Task {
    return global.current_task;
}

pub fn next() *Task {
    const idx = global.bitmask.countZeros();
    const t = global.runnable[idx].head.?.container().toTask();
    return t;
}

pub fn add(task: *Task) void {
    global.runnable[task.priority].enqueue(&task.sch_state.list_node);
    global.bitmask.set(task.priority);
}

fn schedule() void {
    const idx = global.bitmask.countZeros();
    const t = global.runnable[idx].dequeue() orelse return;
    global.runnable[idx].enqueue(t);
}

fn remove(task: *Task) void {
    _ = global.runnable[task.priority].remove(task);
    if(global.runnable[task.priority].isEmpty()) {
        global.bitmask.clear(task.priority);
    }
}

fn switchTo(task: *Task, prev_task_cpu_state: *CpuState) void {
    global.current_task.cpu_state = prev_task_cpu_state.*;
    global.current_task = task;
}

fn tryContextSwitch(irq_cpu_state: *CpuState) void {
    const next_task = next();
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

