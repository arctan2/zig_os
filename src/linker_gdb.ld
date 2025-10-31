ENTRY(_start)

VIRT_BASE = 0xC0000000;

SECTIONS
{
    . = VIRT_BASE;
    .vectors : {
        KEEP(*(.vectors))
    }

    .text : {
        *(.text*)
        *(.rodata*)
    }

	/DISCARD/ : {
		*(.ARM.exidx*)
		*(.ARM.extab*)
	}

    . = ALIGN(8);

    .data : { *(.data*) }
    .bss  : { *(.bss*) *(COMMON) }

    . = ALIGN(8);
    _stack_top = . + 0x4000;

    . = ALIGN(8);
	_kernel_end = .;
}

