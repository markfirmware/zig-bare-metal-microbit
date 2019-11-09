ENTRY(_start)

SECTIONS {

    /DISCARD/ : {
        *(.ARM.exidx)
        *(.rodata)
    }

    .text 0x0 : {
        KEEP(*(.text.boot))
        *(.text)
    }

    .data 0x20004000 : {
        *(ARM.exidx)
        *(.data)
    }

    .bss : {
        __bss_start = .;
        *(COMMON)
        *(.bss)
        __bss_end = .;
    }
}
