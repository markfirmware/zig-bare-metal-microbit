ENTRY(_start)

SECTIONS {

    /DISCARD/ : {
        *(.ARM.exidx)
    }

    . = 0x0;

    .text : {
        KEEP(*(.text.start.mission00))
        KEEP(*(.text.start.*))
        *(.text)
        *(.rodata)
    }

    . = 0x20000000;

    .data : {
        *(.data)
    }

    .bss : {
        __bss_start = .;
        *(COMMON)
        *(.bss)
        __bss_end = .;
    }
}
