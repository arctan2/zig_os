pub const KERNEL_VIRT_BASE = 0xC0000000;
pub var KERNEL_VIRT_OFFSET: usize = 0;
pub const MMIO_BASE = 0xF0000000;

pub extern var _kernel_end: u8;
pub extern var _kernel_start: u8;

pub fn physToVirt(phys: usize) usize {
    return phys + KERNEL_VIRT_OFFSET;
}

pub fn virtToPhys(virt: usize) usize {
    return virt - KERNEL_VIRT_OFFSET;
}

