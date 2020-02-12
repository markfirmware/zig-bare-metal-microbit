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
    }

    .rodata : {
        *(.rodata)
#       __debug_info_start = .;
#       KEEP(*(.debug_info))
#       __debug_info_end = .;
#       __debug_abbrev_start = .;
#       KEEP(*(.debug_abbrev))
#       __debug_abbrev_end = .;
#       __debug_str_start = .;
#       KEEP(*(.debug_str))
#       __debug_str_end = .;
#       __debug_line_start = .;
#       KEEP(*(.debug_line))
#       __debug_line_end = .;
#       __debug_ranges_start = .;
#       KEEP(*(.debug_ranges))
#       __debug_ranges_end = .;
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
