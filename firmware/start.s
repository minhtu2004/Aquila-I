# =============================================================================
# start.s — Startup code cho picorv32
# -----------------------------------------------------------------------------
# Memory Map:
#   0x00000000 : j _start          (reset vector)
#   0x00000004 : nop               (padding)
#   0x00000008 : nop               (padding)
#   0x0000000C : nop               (padding)
#   0x00000010 : j _irq_handler    (PROGADDR_IRQ)
#   0x00000014 : nop               (padding)
#   0x00000018 : _start            (code bắt đầu)
# -----------------------------------------------------------------------------
# Stack   : top of 4KB RAM (_stack_top từ sections.lds)
# RAM     : 0x0001_0000 - 0x0001_0FFF
# ROM     : 0x0000_0000 - 0x0000_1FFF
# =============================================================================
.section .vectors, "ax"
.global _vectors
_vectors:
    j       _start
    nop
    nop
    nop
    j       _irq_handler
    nop

# =============================================================================
# _start
# =============================================================================
.section .text
.global _start
_start:
    la      sp, _stack_top

    la      a0, _bss_start
    la      a1, _bss_end
    beq     a0, a1, _bss_done
_bss_loop:
    sw      zero, 0(a0)
    addi    a0, a0, 4
    blt     a0, a1, _bss_loop
_bss_done:

    la      a0, _data_lma
    la      a1, _data_start
    la      a2, _data_end
    beq     a1, a2, _data_done
_data_loop:
    lw      t0, 0(a0)
    sw      t0, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    blt     a1, a2, _data_loop
_data_done:

    call    main

_hang:
    j       _hang

# =============================================================================
# _irq_handler — save regs → call irq_dispatch → restore → retirq
# =============================================================================
.global _irq_handler
.balign 4
_irq_handler:
    addi    sp, sp, -128

    sw      ra,   0(sp)

    sw      s0,   4(sp)
    sw      s1,   8(sp)
    sw      s2,  12(sp)
    sw      s3,  16(sp)
    sw      s4,  20(sp)
    sw      s5,  24(sp)
    sw      s6,  28(sp)
    sw      s7,  32(sp)
    sw      s8,  36(sp)
    sw      s9,  40(sp)
    sw      s10, 44(sp)
    sw      s11, 48(sp)

    sw      a0,  52(sp)
    sw      a1,  56(sp)
    sw      a2,  60(sp)
    sw      a3,  64(sp)
    sw      a4,  68(sp)
    sw      a5,  72(sp)
    sw      a6,  76(sp)
    sw      a7,  80(sp)

    sw      t0,  84(sp)
    sw      t1,  88(sp)
    sw      t2,  92(sp)
    sw      t3,  96(sp)
    sw      t4, 100(sp)
    sw      t5, 104(sp)
    sw      t6, 108(sp)
    
    
    
    
    # ---- DEBUG PicoRV32 IRQ qregs ----
    # q0 = return PC của IRQ
    # q1 = IRQ reason / pending bit

    .word   0x0000028B      # getq t0, q0
    lui     t1, 0x10
    addi    t1, t1, 0x300   # t1 = 0x00010300
    sw      t0, 0(t1)       # dbg[0] = q0

    .word   0x0000828B      # getq t0, q1
    sw      t0, 4(t1)       # dbg[1] = q1

    sw      sp, 8(t1)       # dbg[2] = sp
    sw      ra, 12(t1)      # dbg[3] = ra
    sw      s0, 16(t1)      # dbg[4] = s0
    
    
    
    

    call    irq_dispatch

    lw      ra,   0(sp)

    lw      s0,   4(sp)
    lw      s1,   8(sp)
    lw      s2,  12(sp)
    lw      s3,  16(sp)
    lw      s4,  20(sp)
    lw      s5,  24(sp)
    lw      s6,  28(sp)
    lw      s7,  32(sp)
    lw      s8,  36(sp)
    lw      s9,  40(sp)
    lw      s10, 44(sp)
    lw      s11, 48(sp)

    lw      a0,  52(sp)
    lw      a1,  56(sp)
    lw      a2,  60(sp)
    lw      a3,  64(sp)
    lw      a4,  68(sp)
    lw      a5,  72(sp)
    lw      a6,  76(sp)
    lw      a7,  80(sp)

    lw      t0,  84(sp)
    lw      t1,  88(sp)
    lw      t2,  92(sp)
    lw      t3,  96(sp)
    lw      t4, 100(sp)
    lw      t5, 104(sp)
    lw      t6, 108(sp)

    addi    sp, sp, 128

    .word   0x0400000B      # retirq
