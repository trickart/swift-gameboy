/* swift-gameboy: linker script for the Game Boy (DMG)
 *
 *   ROM  0x0000-0x7FFF  32KB (no MBC, ROM ONLY cartridge)
 *   WRAM 0xC000-0xC09F  shadow OAM (OAM DMA source, used by GameBoy.Sprites)
 *   WRAM 0xC0A0-0xDFFF  .data / .bss / heap / stack
 *   HRAM 0xFF80-0xFFFE  OAM DMA routine etc.
 */
MEMORY {
  ROM  (rx)  : ORIGIN = 0x0000, LENGTH = 0x8000
  WRAM (rwx) : ORIGIN = 0xC0A0, LENGTH = 0x1F60
  HRAM (rwx) : ORIGIN = 0xFF80, LENGTH = 0x007F
}

ENTRY(_start)

__oam_shadow = 0xC000;   /* 160 bytes, must be placed on a 0x100 boundary */
__stack_top  = 0xE000;   /* the stack grows downward from the end of WRAM */
__stack_size = 0x0400;   /* 1KB */

SECTIONS {
  /* RST / interrupt vectors (0x0000-0x00FF) */
  .vectors 0x0000 : { KEEP(*(.vectors)) } > ROM

  /* Cartridge header (0x0100-0x014F). Checksums etc. are filled in by gbfix.py */
  .header 0x0100 : { KEEP(*(.header)) } > ROM

  /* Starts right after the header (0x0150). The linker errors out if it overflows the ROM region */
  .text : {
    *(.text .text.*)
  } > ROM

  .rodata : {
    *(.rodata .rodata.*)
  } > ROM

  /* Initialized data: stored in ROM, copied to WRAM by crt0 */
  .data : {
    __data_start = .;
    *(.data .data.*)
    . = ALIGN(2);
    __data_end = .;
  } > WRAM AT> ROM
  __data_load = LOADADDR(.data);
  __data_size = SIZEOF(.data);

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(2);
    __bss_end = .;
  } > WRAM
  __bss_size = SIZEOF(.bss);

  /* The heap runs from just after .bss up to the start of the stack region */
  __heap_start = ALIGN(__bss_end, 2);
  __heap_end   = __stack_top - __stack_size;

  .hram (NOLOAD) : { *(.hram) } > HRAM

  __rom_used = LOADADDR(.data) + SIZEOF(.data);

  /DISCARD/ : { *(.comment) *(.eh_frame*) *(.llvm_addrsig) *(.note*) }
}
