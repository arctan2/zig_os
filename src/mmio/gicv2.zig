const std = @import("std");
const mm = @import("mm");
const uart = @import("uart");
const utils = @import("utils");
const fdt = @import("fdt");

fn writeRegBit(base: u32, intr_id: u32) void {
    const reg_index = intr_id / 32;
    const bit_index = intr_id % 32;
    const reg_addr = base + (reg_index * 4);
    utils.write32(reg_addr, @as(u32, 1) << @intCast(bit_index));
}

pub const IntrAck = packed struct(u32) {
    intr_id: u10,
    cpu_id: u2,
    _: u20
};

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

    pub fn setPriorityMask(self: *@This(), mask: u32) void {
        utils.write32(self.PMR, mask);
    }

    pub fn enable(self: *@This()) void {
        utils.write32(self.CTLR, 1);
    }

    pub fn disable(self: *@This()) void {
        utils.write32(self.CTLR, 0);
    }

    pub fn ack(self: *@This()) IntrAck {
        const intr_ack: IntrAck = @bitCast(utils.read32(self.IAR));
        return intr_ack;
    }
    
    pub fn endOfIntr(self: *@This(), intr_id: u32) void {
        utils.write32(self.EOIR, intr_id);
    }

    pub fn init(self: *@This()) void {
        self.enable();
        self.setPriorityMask(0xf0);
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
    ITARGETSRn: u32 = 0x800,//R/W 0x00000000 Interrupt Processor Targets Registers (which CPU handles IRQ).
    ICFGRn: u32 = 0xC00, // R/W Impl. defined Interrupt Configuration Registers (edge/level).
    // 0xD00-0xDFC Implementation defined - - Optional vendor registers.
    NSACRn: u32 = 0xE00, // R/W 0x00000000 Non-secure Access Control Registers (optional).
    WO: u32 = 0xF00,  // - Software Generated Interrupt Register.
    // 0xF04-0xF0C Reserved - - -
    CPENDSGIRn: u32 = 0xF10, // R/W 0x00000000 SGI Clear-Pending Registers.
    SPENDSGIRn: u32 = 0xF20, // R/W 0x00000000 SGI Set-Pending Registers.
    // 0xF30-0xFCC Reserved - - -
    PIDR: u32 = 0xFD0, // / CIDR RO Impl. defined Peripheral/Component Identification Registers.

    const Config = enum(u2) {
        Level = 0,
        Edge = 1,
    };

    pub fn setBase(self: *@This(), distr_start: usize) void {
        inline for(std.meta.fields(@This())) |field| {
            @field(self, field.name) = @field(self, field.name) + distr_start;
        }
    }

    pub fn init(self: *@This()) void {
        for(0..32) |i| {
            utils.write32(self.ISENABLERn + (i * 4), 1);
        }

        for(0..1020) |i| {
            const reg_addr = self.IPRIORITYRn + i;
            utils.write8(reg_addr, 0x1);
        }

        for(0..1024) |i| {
            const reg_addr = self.ITARGETSRn + i;
            utils.write8(reg_addr, 0x1);
        }

        for(0..256) |i| {
            const reg_addr = self.ICFGRn + i;
            utils.write8(reg_addr, @intFromEnum(Config.Level));
        }

        utils.write32(self.CTLR, 1);
    }

    pub fn enableIrq(self: *@This(), intr_id: u32) void {
        writeRegBit(self.ISENABLERn, intr_id);
    }

    pub fn disableIrq(self: *@This(), intr_id: u32) void {
        writeRegBit(self.ICENABLERn, intr_id);
    }

    pub fn printPendingIntr(self: *@This()) void {
        var b: usize = 0;
        uart.print("pendingIntr: ", void);
        for(0..32) |i| {
            const reg_val = utils.read32(self.ISPENDRn + (i * 4));
            for(0..32) |j| {
                const bit = (reg_val >> @intCast(j)) & 1;

                if(bit == 1) {
                    uart.print("{}, ", .{b});
                }

                b += 1;
            }
        }

        uart.print("\n", void);
    }

    pub fn setPriority(self: *@This(), intr_id: u32, priority: u8) void {
        const addr = self.IPRIORITYRn + intr_id;
        utils.write8(addr, priority);
    }

    pub fn setTarget(self: *@This(), intr_id: u32, cpu_target: u8) void {
        const addr = self.ITARGETSRn + intr_id;
        utils.write8(addr, cpu_target);
    }

    pub fn configure(self: *@This(), intr_id: u32, config: Config) void {
        _ = self;
        _ = intr_id;
        _ = config;
    }
} {};

