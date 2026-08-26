    .section .text
    .globl _start

_start:
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
