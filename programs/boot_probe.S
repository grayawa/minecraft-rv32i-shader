.section .text
.globl _start

_start:
    bne   x10, x0, fail
    lui   x12, 0x00001
    addi  x12, x12, 32
    bne   x11, x12, fail

    lbu   x13, 0(x11)
    addi  x14, x0, 208
    bne   x13, x14, fail
    lbu   x13, 1(x11)
    addi  x14, x0, 13
    bne   x13, x14, fail
    lbu   x13, 2(x11)
    addi  x14, x0, 254
    bne   x13, x14, fail
    lbu   x13, 3(x11)
    addi  x14, x0, 237
    bne   x13, x14, fail

    lui   x18, 0x10000
    addi  x19, x0, 68
    sb    x19, 0(x18)
    addi  x19, x0, 84
    sb    x19, 0(x18)
    addi  x19, x0, 66
    sb    x19, 0(x18)
    addi  x19, x0, 32
    sb    x19, 0(x18)
    addi  x19, x0, 65
    sb    x19, 0(x18)
    addi  x19, x0, 49
    sb    x19, 0(x18)
    addi  x19, x0, 32
    sb    x19, 0(x18)
    addi  x19, x0, 79
    sb    x19, 0(x18)
    addi  x19, x0, 75
    sb    x19, 0(x18)
    ebreak

fail:
    lui   x18, 0x10000
    addi  x19, x0, 70
    sb    x19, 0(x18)
    addi  x19, x0, 65
    sb    x19, 0(x18)
    addi  x19, x0, 73
    sb    x19, 0(x18)
    addi  x19, x0, 76
    sb    x19, 0(x18)
    ebreak
