ENTRY(_start)

VIRT_BASE = 0xC0100000;
PHYS_BASE = 0x40000000;

SECTIONS
{
	/DISCARD/ : {
		*(.ARM.exidx*)
		*(.ARM.extab*)
	}

	. = PHYS_BASE;

	_early_kernel_start = .;

	.text.boot : {
        *(.text.boot)
	}

	.bss.boot : { *(.bss.boot) }

	. = . + 0x4000;
	. = ALIGN(8);
	_stack_top_early = .;

	. = ALIGN(16384);

	_kernel_l1_page_table_phys = .;

	. = . + 0x4000;

	_kernel_l1_page_table_end = .;

	. = ALIGN(0x00100000);

	_early_kernel_end = .;

	. = VIRT_BASE;

	_vkernel_start = .;

	KERNEL_OFFSET = _vkernel_start - _early_kernel_end;

    .vectors : AT(ADDR(.vectors) - KERNEL_OFFSET) {
        KEEP(*(.vectors))
    }

    .text : AT(ADDR(.text) - KERNEL_OFFSET) {
        *(.text)
    }

    . = ALIGN(8);

    .data : AT(ADDR(.data) - KERNEL_OFFSET) { *(.data*) }
    .bss  : AT(ADDR(.bss) - KERNEL_OFFSET) { *(.bss*) *(COMMON) }
	.rodata : AT(ADDR(.rodata) - KERNEL_OFFSET) { *(.rodata) }

	. = ALIGN(8);
	. += 0x1000;
	. = ALIGN(8);
	_irq_stack_top = .;

	. = ALIGN(8);
	. += 0x4000;
	. = ALIGN(8);
	_sys_stack_top = .;

	. = ALIGN(8);
	. += 0x4000;
	. = ALIGN(8);
	_pabort_stack_top = .;

	. = ALIGN(8);
	. += 0x4000;
	. = ALIGN(8);
	_vstack_top = .;
	
	. = ALIGN(0x00100000);

	_vkernel_end = .;

	.initramfs_img : AT(ADDR(.initramfs_img) - KERNEL_OFFSET) { KEEP(*(.initramfs_img)) }
}

