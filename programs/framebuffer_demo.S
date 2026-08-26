    .section .text
    .globl _start

_start:
    # Validate RV32M with positive operands that produce exact low/high words.
    addi  x3, x0, 21
    addi  x4, x0, 6
    mul   x5, x3, x4
    mulh  x6, x3, x4
    mulhsu x7, x3, x4
    mulhu x8, x3, x4
    div   x9, x3, x4
    divu  x10, x3, x4
    rem   x11, x3, x4
    remu  x12, x3, x4

    addi  x13, x0, 126
    bne   x5, x13, self_test_failed
    bne   x6, x0, self_test_failed
    bne   x7, x0, self_test_failed
    bne   x8, x0, self_test_failed

    addi  x14, x0, 3
    bne   x9, x14, self_test_failed
    bne   x10, x14, self_test_failed
    bne   x11, x14, self_test_failed
    bne   x12, x14, self_test_failed

    # Validate machine CSR replacement and read operations through mscratch.
    csrrw x15, mscratch, x5
    csrrs x16, mscratch, x0
    bne   x15, x0, self_test_failed
    bne   x16, x5, self_test_failed

    # x1 traverses the framebuffer from 0x1000 to 0x18ff.
    lui   x1, 0x1
    addi  x2, x0, 1
    lui   x6, 0x2
    addi  x6, x6, -1792

fill_framebuffer:
    sw    x2, 0(x1)
    addi  x1, x1, 4
    addi  x2, x2, 1
    bltu  x1, x6, fill_framebuffer
    ebreak

self_test_failed:
    lui   x1, 0x1
    lui   x2, 0xdeadc
    addi  x2, x2, -273
    sw    x2, 0(x1)
    ebreak
