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

! ---------------------------------------------------------------------------
! Clean-HLE leaf services.  Keep each entry at a fixed address: redirect data
! and the boot trampoline may refer to these symbols before the full runtime
! module is linked.
! ---------------------------------------------------------------------------

    .org 0x100, 0
    .global stv_signed_accumulate
! BIOS 0x0ECC: r0=r4+r5. If a negative r4 crosses to non-negative, return -1.
stv_signed_accumulate:
    mov     r4, r0
    cmp/pz  r4
    bt      signed_add_normal
    add     r5, r0
    cmp/pz  r0
    bf      signed_done
    mov     #-1, r0
signed_done:
    rts
    nop
signed_add_normal:
    rts
    add     r5, r0

    .org 0x120, 0
    .global stv_packed_status_test
! BIOS 0x3E4E: return 1 if any nibble of [0x06000658].word is below 8.
stv_packed_status_test:
    mov.l   status_word_ptr, r1
    mov.w   @r1, r2
    extu.w  r2, r2
    mov     #4, r3
status_nibble_loop:
    mov     r2, r0
    and     #0x0F, r0
    mov     #8, r1
    cmp/hs  r1, r0
    bf      status_found
    shlr2   r2
    shlr2   r2
    dt      r3
    bf      status_nibble_loop
    rts
    mov     #0, r0
status_found:
    rts
    mov     #1, r0
    .align 2
status_word_ptr: .long 0x06000658

    .org 0x160, 0
    .global stv_workspace_byte_set
! BIOS 0x4596: mirror r5.byte to HWRAM and the ST-V system window.
stv_workspace_byte_set:
    mov.l   workspace_h_ptr, r1
    add     r4, r1
    mov.b   r5, @r1
    mov     r4, r0
    shll    r0
    mov.l   workspace_s_ptr, r2
    add     r0, r2
    mov.b   r5, @r2
    rts
    nop
    .align 2
workspace_h_ptr: .long 0x0600065A
workspace_s_ptr: .long 0x20100075

    .org 0x1A0, 0
    .global stv_cart_layout_nibble
! BIOS 0x4680: select a packed layout nibble using channel 1..3, else nibble 0.
stv_cart_layout_nibble:
    mov.l   layout_channel_ptr, r1
    mov.b   @r1, r0
    extu.b  r0, r0
    mov.l   layout_word_ptr, r1
    mov.w   @r1, r2
    extu.w  r2, r2
    cmp/eq  #1, r0
    bt      layout_shift_4
    cmp/eq  #2, r0
    bt      layout_shift_8
    cmp/eq  #3, r0
    bt      layout_shift_12
    bra     layout_mask
    nop
layout_shift_12:
    shlr2   r2
    shlr2   r2
layout_shift_8:
    shlr2   r2
    shlr2   r2
layout_shift_4:
    shlr2   r2
    shlr2   r2
layout_mask:
    mov     r2, r0
    and     #0x0F, r0
    rts
    nop
    .align 2
layout_channel_ptr: .long 0x06000650
layout_word_ptr:    .long 0x0600064C

    .org 0x1E0, 0
    .global stv_channel_address
! BIOS 0x372C: sign-extended low-word(channel * 0x0F00) + 0x20180100.
stv_channel_address:
    mov.l   channel_index_ptr, r1
    mov.b   @r1, r0
    extu.b  r0, r0
    mov.w   channel_stride, r3
    mulu.w  r3, r0
    sts     macl, r0
    exts.w  r0, r0
    mov.l   channel_base, r2
    add     r2, r0
    rts
    nop
    .align 1
channel_stride:    .word 0x0F00
    .align 2
channel_index_ptr: .long 0x06000650
channel_base:      .long 0x20180100

    .org 0x220, 0
    .global stv_memset
! BIOS 0x2CAC: r4=dst, r5=byte, r6=len; return the original destination.
stv_memset:
    mov     r4, r0
    tst     r6, r6
    bt      memset_done
    mov     r4, r2
memset_loop:
    mov.b   r5, @r2
    add     #1, r2
    dt      r6
    bf      memset_loop
memset_done:
    rts
    nop

    .org 0x260, 0
    .global stv_vblank_clock_update
! BIOS 0x0EFC steady-state path: add the NTSC fixed-point increment to
! [0x06000758].  The signed-overflow callback branch is reserved below; the
! steady-state path is the one exercised throughout the 3600-frame oracle.
stv_vblank_clock_update:
    mov.l   vblank_acc_ptr, r1
    mov.l   @r1, r2
    mov.l   vblank_increment, r3
    add     r3, r2
    mov.l   r2, @r1
    mov     r1, r7
    mov     r3, r0
    rts
    nop
    .align 2
vblank_acc_ptr:   .long 0x06000758
vblank_increment: .long 0x55929FAD

! ---------------------------------------------------------------------------
! BIOS 0x3842 channel table dispatch.  The four selectors used by Baku Baku
! update strided 32-bit values and tail-jump through [0x06000648].
! ---------------------------------------------------------------------------
    .org 0x300, 0
    .global stv_read_strided_long
stv_read_strided_long:
    mov     r4, r3
    add     #1, r3
    mov.b   @r3, r0
    extu.b  r0, r0
    shll8   r0
    shll8   r0
    shll8   r0
    add     #2, r3
    mov.b   @r3, r1
    extu.b  r1, r1
    shll8   r1
    shll8   r1
    or      r1, r0
    add     #2, r3
    mov.b   @r3, r1
    extu.b  r1, r1
    shll8   r1
    or      r1, r0
    add     #2, r3
    mov.b   @r3, r1
    extu.b  r1, r1
    or      r1, r0
    rts
    nop

stv_write_strided_long:
    mov     r5, r0
    mov     r4, r3
    add     #7, r3
    mov.b   r0, @r3
    shlr8   r0
    add     #-2, r3
    mov.b   r0, @r3
    shlr8   r0
    add     #-2, r3
    mov.b   r0, @r3
    shlr8   r0
    add     #-2, r3
    mov.b   r0, @r3
    rts
    nop

    .org 0x400, 0
    .global stv_channel_table_dispatch
stv_channel_table_dispatch:
    mov     r4, r0
    tst     r0, r0
    bt      channel_simple_840
    cmp/eq  #0x10, r0
    bt      channel_simple_830
    cmp/eq  #1, r0
    bt      channel_delta
    cmp/eq  #0x20, r0
    bt      channel_range
    rts
    nop

channel_simple_840:
    mov.l   channel_current_ptr, r4
    mov.l   channel_output_840, r5
    bra     channel_simple_common
    nop
channel_simple_830:
    mov.l   channel_current_ptr, r4
    mov.l   channel_output_830, r5
channel_simple_common:
    sts.l   pr, @-r15
    mov     r5, r3
    mov.l   r3, @-r15
    bsr     stv_read_strided_long
    nop
    mov.l   @r15+, r1
    lds.l   @r15+, pr
    mov.l   r0, @r1
    mov.l   channel_tail_ptr, r2
    mov.l   @r2, r2
    mov     r2, r6
    mov     #0x37, r3
    shll8   r3
    add     #0x44, r3
    mov     #1, r4
    mov.l   channel_tail_data, r5
    mov     #0, r6
    jmp     @r2
    nop

channel_delta:
    sts.l   pr, @-r15
    mov.l   channel_current_ptr, r4
    bsr     stv_read_strided_long
    nop
    mov     r0, r7
    mov.l   channel_baseline_840, r1
    mov.l   @r1, r1
    sub     r1, r7
    mov.l   channel_delta_base_a, r4
    bsr     stv_read_strided_long
    nop
    add     r7, r0
    mov     r0, r6
    mov     r6, r5
    mov.l   channel_delta_base_a, r4
    bsr     stv_write_strided_long
    nop
    mov.l   channel_delta_base_b, r4
    bsr     stv_read_strided_long
    nop
    add     r7, r0
    mov     r0, r6
    mov     r6, r5
    mov.l   channel_delta_base_b, r4
    bsr     stv_write_strided_long
    nop
    lds.l   @r15+, pr
    mov.l   channel_tail_ptr, r2
    mov.l   @r2, r2
    mov     r4, r0
    add     #7, r0
    mov.b   @r0, r1
    mov.l   channel_tail_h, r3
    mov.l   @r3, r3
    mov     #3, r4
    mov.l   channel_delta_base_b, r5
    add     #1, r5
    mov     r6, r0
    shlr8   r0
    shlr8   r0
    shlr8   r0
    mov     r0, r6
    mov     #0, r0
    jmp     @r2
    nop

channel_range:
    sts.l   pr, @-r15
    mov.l   channel_current_ptr, r4
    bsr     stv_read_strided_long
    nop
    mov     r0, r7
    mov.l   channel_baseline_830, r1
    mov.l   @r1, r1
    sub     r1, r7
    mov.l   channel_range_accum, r4
    bsr     stv_read_strided_long
    nop
    mov     r0, r6
    add     r7, r0
    tst     r6, r6
    bt      range_accum_ready
    cmp/pz  r0
    bf      range_accum_ready
    mov     #-1, r0
range_accum_ready:
    mov     r0, r6
    mov     r6, r5
    mov.l   channel_range_accum, r4
    bsr     stv_write_strided_long
    nop
    mov.l   channel_range_lower, r4
    bsr     stv_read_strided_long
    nop
    cmp/hs  r7, r0
    bt      range_upper_check
    mov     r7, r5
    mov.l   channel_range_lower, r4
    bsr     stv_write_strided_long
    nop
range_upper_check:
    mov.l   channel_range_upper, r4
    bsr     stv_read_strided_long
    nop
    tst     r0, r0
    bt      range_write_upper
    cmp/hi  r7, r0
    bf      range_tail
range_write_upper:
    mov     r7, r5
    mov.l   channel_range_upper, r4
    bsr     stv_write_strided_long
    nop
range_tail:
    lds.l   @r15+, pr
    mov.l   channel_tail_ptr, r2
    mov.l   @r2, r2
    mov     #0, r0
    mov.l   channel_tail_h, r3
    mov.l   @r3, r3
    mov     #3, r4
    mov.l   channel_range_upper, r5
    add     #1, r5
    mov     r7, r6
    shlr8   r6
    shlr8   r6
    shlr8   r6
    jmp     @r2
    nop

    .align 2
channel_current_ptr:   .long 0x20180000
channel_output_840:    .long 0x06000840
channel_output_830:    .long 0x06000830
channel_tail_ptr:      .long 0x06000648
channel_tail_data:     .long 0x20180007
channel_baseline_840:  .long 0x06000840
channel_baseline_830:  .long 0x06000830
channel_delta_base_a:  .long 0x20183D54
channel_delta_base_b:  .long 0x20183DAC
channel_tail_h:         .long 0x06001412
channel_range_accum:    .long 0x20183DA4
channel_range_lower:    .long 0x20183D94
channel_range_upper:    .long 0x20183D9C

! Machine-readable redirect metadata for the future clean resident dispatcher.
! Each record is {original ST-V BIOS entry, native CS1 entry}; zero terminates.
    .org 0x700, 0
    .global stv_service_redirect_table
    .global stv_service_redirect_table_end
stv_service_redirect_table:
    .long 0x00000EFC, stv_vblank_clock_update
    .long 0x00000ECC, stv_signed_accumulate
    .long 0x00002C64, stv_memmove_reloc
    .long 0x00002CAC, stv_memset
    .long 0x0000372C, stv_channel_address
    .long 0x00003E4E, stv_packed_status_test
    .long 0x00004596, stv_workspace_byte_set
    .long 0x00004680, stv_cart_layout_nibble
    .long 0x00003842, stv_channel_table_dispatch
stv_service_redirect_table_end:
    .long 0x00000000, 0x00000000
