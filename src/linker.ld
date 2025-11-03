ENTRY(_start)

VIRT_BASE = 0xC0010000;
PHYS_BASE = 0x40000000;
KERNEL_OFFSET = VIRT_BASE - PHYS_BASE;

SECTIONS
{
	/DISCARD/ : {
		*(.ARM.exidx*)
		*(.ARM.extab*)
	}

	. = PHYS_BASE;

	.text.boot : {
        *(.text.boot*)
        *(.rodata*)
	}

	. = . + 0x4000;
	. = ALIGN(8);
	_stack_top_early = .;

	. = ALIGN(16384);

	kernel_l1_page_table = .;

	. = . + 0x4000;

	kernel_l1_page_table_end = .;

	. = ALIGN(8);
	boot_end_phys = .;

	. = VIRT_BASE;

	_kernel_start = .;

	KERNEL_OFFSET_FROM_BOOT_END = _kernel_start - boot_end_phys;

    /* .vectors : AT(ADDR(.vectors) - KERNEL_OFFSET_FROM_BOOT_END) {
        KEEP(*(.vectors))
    }
	*/

    .text : AT(ADDR(.text) - KERNEL_OFFSET_FROM_BOOT_END) {
        *(.text*)
        *(.rodata*)
    }

    . = ALIGN(8);

    .data : AT(ADDR(.data) - KERNEL_OFFSET_FROM_BOOT_END) { *(.data) }
    .bss  : AT(ADDR(.bss) - KERNEL_OFFSET_FROM_BOOT_END) { *(.bss) *(COMMON) }

	.stack : AT(ADDR(.stack) - KERNEL_OFFSET_FROM_BOOT_END) {
		. = ALIGN(8);
		. += 0x8000;
		. = ALIGN(8);
		_stack_top = .;
	}

	. = . + 8;
    . = ALIGN(8);
	_kernel_end = .;
}

