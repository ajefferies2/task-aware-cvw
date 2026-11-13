OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K }
SECTIONS {
  . = ORIGIN(RAM);
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.*) } > RAM
  .data : ALIGN(4) { *(.data .data.*) } > RAM
  .sdata : ALIGN(4) {
    PROVIDE(__global_pointer$ = . + 0x800);
    *(.sdata .sdata.*)
  } > RAM
  .bss (NOLOAD) : ALIGN(16) {
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > RAM
  __stack_top = 0x8000ff00;
  ASSERT(__bss_end < 0x8000ef00, "Program overlaps scheduler stack/mailbox")
  /DISCARD/ : { *(.comment .note .eh_frame .eh_frame_hdr) }
}
