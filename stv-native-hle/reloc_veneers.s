! Baku Baku source-address relocation veneers for current SAROO PCBs.
!
! The PCB does not route Saturn AA24 to the FPGA.  The canonical cart image's
! bytes 16 MB+ are therefore exposed through CS1 at 0x04000000 instead of the
! original upper CS0 window at 0x03000000.  Runtime tracing found exactly two
! game copy routines reading that window.  These replacements translate only
! their source argument, leaving data and unrelated pointer-like values alone.

    .section .text, "ax"
    .align 2

    .global stv_long_copy_reloc
    .global stv_memmove_reloc
    .global stv_install_reloc_veneers

! r4=dst, r5=src, r6=count in 32-bit longs.
! Match the original routine's r5/r7/r2 loop behavior after translating src.
stv_long_copy_reloc:
    mov.l   cart_upper_low, r0
    cmp/hs  r0, r5
    bf      long_src_ready
    mov.l   cart_upper_high, r0
    cmp/hs  r0, r5
    bt      long_src_ready
    mov.l   cart_reloc_delta, r0
    add     r0, r5
long_src_ready:
    mov     r5, r7
    bra     long_copy_check
    mov     r4, r5
long_copy_loop:
    mov     r5, r2
    add     #4, r5
    mov.l   @r7+, r1
    mov.l   r1, @r2
    add     #-1, r6
long_copy_check:
    tst     r6, r6
    bf      long_copy_loop
    rts
    nop

    .align 2
cart_upper_low:    .long 0x03000000
cart_upper_high:   .long 0x03400000
cart_reloc_delta:  .long 0x01000000

! r4=dst, r5=src, r6=len in bytes; return r0=original dst.
! Overlap-safe in both directions, matching the clean-HLE contract.
    .align 2
stv_memmove_reloc:
    mov.l   mem_upper_low, r0
    cmp/hs  r0, r5
    bf      mem_src_ready
    mov.l   mem_upper_high, r0
    cmp/hs  r0, r5
    bt      mem_src_ready
    mov.l   mem_reloc_delta, r0
    add     r0, r5
mem_src_ready:
    mov     r4, r0
    cmp/eq  r5, r4
    bt      mem_done
    tst     r6, r6
    bt      mem_done
    cmp/hs  r5, r4
    bt      mem_backward

    mov     r4, r2
    mov     r5, r3
mem_forward_loop:
    mov.b   @r3+, r1
    mov.b   r1, @r2
    add     #1, r2
    dt      r6
    bf      mem_forward_loop
    bra     mem_done
    nop

mem_backward:
    mov     r4, r2
    add     r6, r2
    mov     r5, r3
    add     r6, r3
mem_backward_loop:
    add     #-1, r3
    mov.b   @r3, r1
    add     #-1, r2
    mov.b   r1, @r2
    dt      r6
    bf      mem_backward_loop
mem_done:
    rts
    nop

    .align 2
mem_upper_low:     .long 0x03000000
mem_upper_high:    .long 0x03400000
mem_reloc_delta:   .long 0x01000000

! Install absolute jump stubs into the two traced HWRAM routines.  Call this
! after copying the FPR body to HWRAM and before executing any game code.
! Stub encoding at each target:
!   mov.l @(1,pc),r0 ; jmp @r0 ; nop ; nop ; .long native_target
    .align 2
stv_install_reloc_veneers:
    mov.l   patch_long_addr, r1
    mov.l   patch_opcodes_0, r0
    mov.l   r0, @r1
    mov.l   patch_opcodes_1, r0
    mov.l   r0, @(4, r1)
    mov.l   patch_long_target, r0
    mov.l   r0, @(8, r1)

    mov.l   patch_mem_addr, r1
    mov.l   patch_opcodes_0, r0
    mov.l   r0, @r1
    mov.l   patch_opcodes_1, r0
    mov.l   r0, @(4, r1)
    mov.l   patch_mem_target, r0
    mov.l   r0, @(8, r1)
    rts
    nop

    .align 2
patch_long_addr:   .long 0x0604AFD4
patch_mem_addr:    .long 0x06053C98
patch_opcodes_0:   .long 0xD001402B
patch_opcodes_1:   .long 0x00090009
patch_long_target: .long stv_long_copy_reloc
patch_mem_target:  .long stv_memmove_reloc
