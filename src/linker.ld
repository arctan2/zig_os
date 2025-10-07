ENTRY(_start)

SECTIONS
{
    . = 0x40000000;

    /*. = 0x8000;*/

    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    }

    . = ALIGN(8);
    _stack_top = . + 0x4000;

    .data : { *(.data*) }
    .bss  : { *(.bss*) *(COMMON) }

    . = ALIGN(8);

	_kernel_end = .;
}

