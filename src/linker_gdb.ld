ENTRY(_start)

VIRT_BASE = 0xC0000000;

SECTIONS
{
    . = VIRT_BASE;
	_kernel_start = .;

    /*. = 0x8000;*/

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

