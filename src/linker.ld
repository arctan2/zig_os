ENTRY(_start)

SECTIONS
{
    . = 0x40000000;
	_kernel_start = .;

    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    }

    . = ALIGN(8);

    .data : { *(.data*) }
    .bss  : { *(.bss*) *(COMMON) }

    . = ALIGN(8);
    _stack_top = . + 0x4000;

    . = ALIGN(8);
	_kernel_end = .;
}

