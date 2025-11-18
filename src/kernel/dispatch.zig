const Task = @import("schedule.zig").Task;

pub var kernel_task = Task {
    .cpu_state = .default(),
    .sch_state = .default(),
    .id = 0,
    .state = .Running,
    .priority = 31,
    .vm_handler = undefined,
    .prev_cpu_time = 0,
    .children = null,
    .parent = null,
};

const Dispatcher = struct {
    current_task: *Task,
};

pub const IrqCpuState = extern struct {
    lr_of_intr_task: usize,
    sp_of_intr_task: usize,
    cpsr_of_intr_task: usize,
    registers: [13]usize,
    pc_of_intr_task: usize,
};

var global = Dispatcher{
    .current_task = &kernel_task
};

pub fn currentTask() *Task {
    return global.current_task;
}

pub fn switchTo(task: *Task, _: *IrqCpuState) void {
    global.current_task = task;
}
