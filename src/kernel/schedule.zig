const mm = @import("mm");
const utils = @import("utils");
const ListNode = utils.types.ListNode;
const Queue = utils.types.ListNode;
const BitMask = utils.types.ListNode;

pub const CpuState = extern struct {
    lr: usize,
    sp: usize,
    cpsr: usize,
    pc: usize,
    registers: [13]usize,

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
        prev_cpu_time: usize,
        children: ?*ListNode(T, "children"),
        parent: ?*T,
    };
}

const SchedulerState = struct {
    pub fn default() SchedulerState {
        return .{
        };
    }
};
pub const Task = TaskInfo(SchedulerState);

pub var Scheduler = struct {
    runnable: [32]Queue(Task),
    bitmask: BitMask,
};

const global = Scheduler{};

pub fn next() ?*Task {
    return null;
}

pub fn add(task: *Task) void {
    global.runnable[task.priority].enqueue(task);
    global.bitmask.set(task.priority);
}

pub fn remove(task: *Task) void {
    _ = global.runnable[task.priority].remove(task);
    if(global.runnable[task.priority].isEmpty()) {
        global.bitmask.clear(task.priority);
    }
}
