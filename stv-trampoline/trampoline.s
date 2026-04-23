! SAROO-STV Phase 1 trampoline
!
! Minimal Saturn-format cart-boot image:
!   - 256-byte "SEGA SEGASATURN " header at offset 0x00
!   - _start at offset 0x100, visible as the "First Master" pointer
!   - Sets VDP2 to display-on with a bright magenta back screen,
!     then halts master SH-2 in an NOP loop.
!
! Assembled with sh-elf-as -little=no (big-endian, SH-2). The binary
! drops straight onto SAROO SDRAM at the CS0 base; Saturn IPL parses
! the header, validates the magic, and jumps via the First Master PC.
!
! For Phase 1 validation this is enough to prove the end-to-end path:
! FPGA CS0 ROM mapping -> Saturn IPL header check -> our code runs.
! A richer trampoline (VDP2 text, hex dump) is a later pass.

    .section .header, "ax"
    .global _boot_header

! ------------------------------------------------------------------
! Saturn cart-boot header (256 bytes total).
! Layout reference: Yabause docs + Charles MacDonald's Saturn notes.
! ------------------------------------------------------------------
_boot_header:
    ! 0x00: hardware ID (16 bytes, ASCII, space-padded)
    .ascii  "SEGA SEGASATURN "
    ! 0x10: maker ID     (16 bytes)
    .ascii  "SEGA ENTERPRISES"
    ! 0x20: product number (10 bytes)  + version (6 bytes)
    .ascii  "T-000HBSTV"
    .ascii  "V1.000"
    ! 0x30: release date YYYYMMDD (8 bytes) + dev/region info (8 bytes)
    .ascii  "20260424"
    .ascii  "CD-1/1  "
    ! 0x40: region flags (10 bytes) "JTUE      " = multi-region
    .ascii  "JTUE      "
    ! 0x4A: (6 bytes) padding to reach peripherals field at 0x50
    .ascii  "      "
    ! 0x50: peripheral list (16 bytes) "J" = standard control pad
    .ascii  "J               "
    ! 0x60: game name (112 bytes, space-padded)
    .ascii  "SAROO-STV Phase 1 Trampoline                                                                                    "
    ! 0xD0: reserved (16 bytes of 0)
    .space  16, 0
    ! 0xE0: IP size (unused here) / first-master-SH2 PC
    .long   _start          ! 0xE0 — master SH-2 initial PC
    .long   _start          ! 0xE4 — (docs: master initial SP — fill later)
    .long   _start          ! 0xE8 — slave SH-2 initial PC (ignored: we leave slave idle)
    .long   _start          ! 0xEC — slave initial SP
    ! 0xF0..0xFF: reserved
    .space  16, 0

    ! Pad to 256 bytes header size so _start lands at a known offset.
    .space  0x100 - (. - _boot_header), 0

! ------------------------------------------------------------------
! Master SH-2 entry point.
!
! Goals for Phase 1:
!   1) Initialize SR (block interrupts, SH-2 normal mode).
!   2) Point stack at top of High Work RAM (0x06100000).
!   3) Drop a magic pattern at WRAM+0 so the first post-boot byte at
!      0x06000000 is observable in Mednafen's save-state dump.
!   4) Blast VDP2 to display-on with a magenta back screen.
!   5) Halt in a NOP loop.
! ------------------------------------------------------------------
    .section .text, "ax"
    .align 2
    .global _start
_start:
    ! SR = 0xF0 : block all interrupts (IMASK = 0xF)
    mov     #0xF0, r0
    ldc     r0, sr

    ! Stack: top of HWRAM (0x06100000). Load via a pointer because
    ! full 32-bit immediates aren't a single-instruction op on SH-2.
    mov.l   stack_top_ptr, r15

    ! WRAM heartbeat: write 0x5AA5A55A at 0x06000000 so save-state
    ! inspection proves "we got here".
    mov.l   wram_base_ptr,     r1
    mov.l   heartbeat_val_ptr, r2
    mov.l   r2, @r1

    ! ---- VDP2: display on, back screen = magenta ----
    !
    ! Minimal sequence:
    !   TVMD  (0x25F80000) = 0x8000        (DISP=1, LSMD=NBG0 off, default res)
    !   BKTAU (0x25F80020) = 0x0000
    !   BKTAL (0x25F80022) = 0x0000        (back screen table at VRAM offset 0)
    !   @0x25E00000       = 0xFC1F         (RGB555 magenta) — VRAM word 0
    !   BDCLMD bit in BKTAU = 0 so back-screen color reads the word above.
    mov.l   vdp2_tvmd_ptr,  r3
    mov.w   tvmd_val,       r0
    mov.w   r0, @r3                        ! TVMD = 0x8000

    mov.l   vdp2_bktau_ptr, r3
    mov.w   zero_w,         r0
    mov.w   r0, @r3                        ! BKTAU = 0
    mov.l   vdp2_bktal_ptr, r3
    mov.w   r0, @r3                        ! BKTAL = 0

    mov.l   vdp2_vram_ptr,  r3
    mov.w   magenta_val,    r0
    mov.w   r0, @r3                        ! *(VRAM+0) = 0xFC1F

    ! ---- Halt: infinite NOP loop ----
halt:
    nop
    bra     halt
    nop

    .align 2
stack_top_ptr:      .long 0x06100000
wram_base_ptr:      .long 0x06000000
heartbeat_val_ptr:  .long 0x5AA5A55A
vdp2_tvmd_ptr:      .long 0x25F80000
vdp2_bktau_ptr:     .long 0x25F80020
vdp2_bktal_ptr:     .long 0x25F80022
vdp2_vram_ptr:      .long 0x25E00000

    .align 1
tvmd_val:           .word 0x8000
zero_w:             .word 0x0000
magenta_val:        .word 0xFC1F
