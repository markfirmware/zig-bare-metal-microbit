MEMORY {
    flash (rx) : ORIGIN = 0x0, LENGTH = 256K
    ram (rw) : ORIGIN = 0x20000000, LENGTH = 16K
}

SECTIONS {
    /DISCARD/ : {
        *(.ARM.exidx)
    }

    .flash : {
        KEEP(*(.vector_table.primary))
        KEEP(*(.vector_table))
        KEEP(*(.text))
        KEEP(*(.text.*))
        *(.rodata*)
    } > flash

    .ram : {
        __bss_start = .;
         *(.bss)
        __bss_end = .;
    } > ram
}
