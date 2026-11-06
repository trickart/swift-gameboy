; swift-gameboy: startup code for the Game Boy (SM83)
;
; - RST / interrupt vectors
; - Cartridge header (0x0100-0x014F)
; - _start: set up the stack, copy .data, zero .bss, copy the OAM DMA routine to HRAM, call main
; - Interrupts save all registers and call the weak C symbols gb_*_handler
;   (Swift can override them with @_cdecl("gb_vblank_handler") etc.)

	.section .vectors,"ax",@progbits
	.globl _start
	.org 0x00
	jp _start
	.org 0x08
L_rst08: jr L_rst08
	.org 0x10
L_rst10: jr L_rst10
	.org 0x18
L_rst18: jr L_rst18
	.org 0x20
L_rst20: jr L_rst20
	.org 0x28
L_rst28: jr L_rst28
	.org 0x30
L_rst30: jr L_rst30
	.org 0x38
L_rst38: jr L_rst38
	.org 0x40
	jp L_isr_vblank
	.org 0x48
	jp L_isr_stat
	.org 0x50
	jp L_isr_timer
	.org 0x58
	jp L_isr_serial
	.org 0x60
	jp L_isr_joypad
	.org 0x68
	jr L_isr_joypad    ; 0x68-0xFF unused
	.org 0x100

; ---- Cartridge header ------------------------------------------------------
	.section .header,"a",@progbits
	nop
	jp _start
	; Nintendo logo (0x0104-0x0133)
	.byte 0xCE,0xED,0x66,0x66,0xCC,0x0D,0x00,0x0B,0x03,0x73,0x00,0x83,0x00,0x0C,0x00,0x0D
	.byte 0x00,0x08,0x11,0x1F,0x88,0x89,0x00,0x0E,0xDC,0xCC,0x6E,0xE6,0xDD,0xDD,0xD9,0x99
	.byte 0xBB,0xBB,0x67,0x63,0x6E,0x0E,0xEC,0xCC,0xDD,0xDC,0x99,0x9F,0xBB,0xB9,0x33,0x3E
	; Title (0x0134-0x0143), filled in by gbfix.py
	.space 16, 0x00
	.byte 0x00, 0x00     ; 0x0144 new licensee code
	.byte 0x00           ; 0x0146 SGB flag
	.byte 0x00           ; 0x0147 cartridge type: ROM ONLY
	.byte 0x00           ; 0x0148 ROM size: 32KB
	.byte 0x00           ; 0x0149 RAM size: none
	.byte 0x01           ; 0x014A destination code
	.byte 0x33           ; 0x014B old licensee code
	.byte 0x00           ; 0x014C version
	.byte 0x00           ; 0x014D header checksum (gbfix.py)
	.byte 0x00, 0x00     ; 0x014E global checksum (gbfix.py)

; ---- Startup ---------------------------------------------------------------
	.section .text,"ax",@progbits
_start:
	di
	ld sp, __stack_top

	; Copy .data from ROM to WRAM
	ld hl, __data_load
	ld de, __data_start
	ld bc, __data_size
	ld a, b
	or a, c
	jr z, L_data_done
L_data_loop:
	ld a, (hl+)
	ld (de), a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, L_data_loop
L_data_done:

	; Zero-fill .bss
	ld hl, __bss_start
	ld bc, __bss_size
	ld a, b
	or a, c
	jr z, L_bss_done
	xor a, a
L_bss_loop:
	ld (hl+), a
	dec bc
	ld a, b
	or a, c
	ld a, 0
	jr nz, L_bss_loop
L_bss_done:

	; Copy the OAM DMA routine to HRAM (0xFF80)
	ld hl, L_oam_dma_rom
	ld de, _gb_oam_dma_hram
	ld b, L_oam_dma_rom_end - L_oam_dma_rom
L_dma_copy:
	ld a, (hl+)
	ld (de), a
	inc de
	dec b
	jr nz, L_dma_copy

	call _main
_halt:
	halt
	nop                ; HALT bug workaround
	jr _halt

; ---- OAM DMA -----------------------------------------------------------------
; void gb_oam_dma(uint8_t source_page)  : A = high byte of the source address (e.g. 0xC1)
	.globl _gb_oam_dma
_gb_oam_dma:
	jp _gb_oam_dma_hram
L_oam_dma_rom:
	ldh (0x46), a
	ld a, 40
L_oam_dma_wait:
	dec a
	jr nz, L_oam_dma_wait
	ret
L_oam_dma_rom_end:

; ---- Small helpers called from Swift (substitute for inline assembly) ---------
	.globl _gb_ei
	.globl _gb_di
	.globl _gb_halt
_gb_ei:
	ei
	ret
_gb_di:
	di
	ret
_gb_halt:
	halt
	nop
	ret

; ---- Interrupt handlers --------------------------------------------------------
	.weak _gb_vblank_handler
	.weak _gb_stat_handler
	.weak _gb_timer_handler
	.weak _gb_serial_handler
	.weak _gb_joypad_handler
_gb_vblank_handler:
_gb_stat_handler:
_gb_timer_handler:
_gb_serial_handler:
_gb_joypad_handler:
	ret

L_isr_vblank:
	push af
	push bc
	push de
	push hl
	call _gb_vblank_handler
	jr L_isr_ret
L_isr_stat:
	push af
	push bc
	push de
	push hl
	call _gb_stat_handler
	jr L_isr_ret
L_isr_timer:
	push af
	push bc
	push de
	push hl
	call _gb_timer_handler
	jr L_isr_ret
L_isr_serial:
	push af
	push bc
	push de
	push hl
	call _gb_serial_handler
	jr L_isr_ret
L_isr_joypad:
	push af
	push bc
	push de
	push hl
	call _gb_joypad_handler
L_isr_ret:
	pop hl
	pop de
	pop bc
	pop af
	reti

; ---- HRAM ---------------------------------------------------------------------
	.section .hram,"aw",@nobits
_gb_oam_dma_hram:
	.space L_oam_dma_rom_end - L_oam_dma_rom
