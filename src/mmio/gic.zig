const std = @import("std");
const mm = @import("mm");

pub fn read32(reg: u32) u32 {
    return @as(*volatile u32, @ptrFromInt(reg)).*;
}

pub fn write32(reg: u32, val: u32) void {
    @as(*volatile u32, @ptrFromInt(reg)).* = val;
}

pub var C = struct {
    CTLR: u32 = 0x0000, // CPU Interface Control Register - enables/disables signaling interrupts to CPU
    PMR: u32 = 0x0004, // Priority Mask Register - only interrupts <= this priority are signaled
    BPR: u32 = 0x0008, // Binary Point Register - sets how priority levels are split for preemption
    IAR: u32 = 0x000C, // Interrupt Acknowledge Register - read to obtain interrupt ID and CPU source
    EOIR: u32 = 0x0010, // End of Interrupt Register - write the same value read from IAR to signal done
    RPR: u32 = 0x0014, // Running Priority Register - current priority level being serviced
    HPPI: u32 = 0x0018, // R Highest Priority Pending Interrupt Register
    ABPR: u32 = 0x001C, // Aliased Binary Point Register - used in Secure state
    AIAR: u32 = 0x0020, // Aliased Interrupt Acknowledge Register - Secure variant of IAR
    AEOI: u32 = 0x0024, // R Aliased End of Interrupt Register - Secure variant of EOIR
    AHPP: u32 = 0x0028, // IR Aliased Highest Priority Pending Interrupt Register - Secure variant
    // 0x002C-0x003C Reserved
    // 0x0040-0x00CF IMPLEMENTATION DEFINED region
    // 0x00D0-0x00DC GICC_APRn Active Priorities Registers (one per priority level bit group)
    // 0x00E0-0x00EC GICC_NSAPRn Non-Secure Active Priorities Registers
    // 0x00ED-0x00F8 Reserved
    IIDR: u32 = 0x00FC, // IMPLEMENTATION DEFINED CPU Interface Identification Register
    DIR: u32 = 0x1000, // Deactivate Interrupt Register - used to deactivate level-sensitive interrupts without EOI

    pub fn setBase(self: *@This(), cpu_iface_start: usize) void {
        inline for(std.meta.fields(@This())) |field| {
            @field(self, field.name) = @field(self, field.name) + cpu_iface_start;
        }
    }

    pub fn init(self: *@This()) void {
        write32(self.CTLR, 1);
        write32(self.PMR, 0xF0);
    }
} {};

pub var D = struct {
    CTLR: u32 = 0x000, // R/W 0x00000000 Distributor Control Register - enables the distributor.
    TYPE: u32 = 0x004, //R RO Impl. defined Interrupt Controller Type Register - tells number of IRQs, CPUs.
    IIDR: u32 = 0x008, // RO Impl. defined Implementer Identification Register.
    // 0x00C-0x01C Reserved - - -
    // 0x020-0x03C Implementation defined - - Optional vendor-specific.
    // 0x040-0x07C Reserved - - -
    IGROUPRn: u32 = 0x080, // R/W Impl. defined Interrupt Group Registers (secure vs non-secure).
    ISENABLERn: u32 = 0x100, // R/W Impl. defined Interrupt Set-Enable Registers.
    ICENABLERn: u32 = 0x180, // R/W Impl. defined Interrupt Clear-Enable Registers.
    ISPENDRn: u32 = 0x200, // R/W 0x00000000 Interrupt Set-Pending Registers.
    ICPENDRn: u32 = 0x280, // R/W 0x00000000 Interrupt Clear-Pending Registers.
    ISACTIVERn: u32 = 0x300, // R/W 0x00000000 Interrupt Set-Active Registers.
    ICACTIVERn: u32 = 0x380, // R/W 0x00000000 Interrupt Clear-Active Registers.
    IPRIORITYRn: u32 = 0x400, // R/W 0x00000000 Interrupt Priority Registers (1 byte per IRQ).
    // 0x7FC Reserved - - -
    ITARGETSRn: u32 = 0x80,//0-  R/W 0x00000000 Interrupt Processor Targets Registers (which CPU handles IRQ).
    ICFGRn: u32 = 0xC00, // R/W Impl. defined Interrupt Configuration Registers (edge/level).
    // 0xD00-0xDFC Implementation defined - - Optional vendor registers.
    NSACRn: u32 = 0xE00, // R/W 0x00000000 Non-secure Access Control Registers (optional).
    WO: u32 = 0xF00,  // - Software Generated Interrupt Register.
    // 0xF04-0xF0C Reserved - - -
    CPENDSGIRn: u32 = 0xF10, // R/W 0x00000000 SGI Clear-Pending Registers.
    SPENDSGIRn: u32 = 0xF20, // R/W 0x00000000 SGI Set-Pending Registers.
    // 0xF30-0xFCC Reserved - - -
    PIDR: u32 = 0xFD0, // / CIDR RO Impl. defined Peripheral/Component Identification Registers.

    pub fn setBase(self: *@This(), distr_start: usize) void {
        inline for(std.meta.fields(@This())) |field| {
            @field(self, field.name) = @field(self, field.name) + distr_start;
        }
    }

    pub fn init(self: *@This()) void {
        write32(self.CTLR, 1);
    }
} {};

