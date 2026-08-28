    .section .text
    .globl _start
    .option norelax

_start:
    la      a1, banner
    li      a2, 32
    jal     ra, write_stdout

    li      s0, 0                  # Current Fibonacci value.
    li      s1, 1                  # Following Fibonacci value.
    li      s2, 0                  # Sequence index.

sequence_loop:
    la      t0, line

    li      t1, 10
    divu    t2, s2, t1
    remu    t3, s2, t1
    addi    t2, t2, 48
    addi    t3, t3, 48
    sb      t2, 1(t0)
    sb      t3, 2(t0)

    addi    t4, t0, 15            # Last digit in the ten-column value.
    mv      t5, s0
    li      t6, 10
    li      a3, 10
decimal_loop:
    remu    a4, t5, t6
    divu    t5, t5, t6
    addi    a4, a4, 48
    sb      a4, 0(t4)
    addi    t4, t4, -1
    addi    a3, a3, -1
    bnez    a3, decimal_loop

    mv      a1, t0
    li      a2, 32
    jal     ra, write_stdout

    addi    s2, s2, 1
    li      t0, 48
    beq     s2, t0, sequence_done
    add     t0, s0, s1
    mv      s0, s1
    mv      s1, t0
    j       sequence_loop

sequence_done:
    li      a0, 0
    li      a7, 93                 # exit(0)
    ecall

write_stdout:
    li      a0, 1
    li      a7, 64                 # write(1, buffer, length)
    ecall
    ret

    .section .data
    .balign 4
banner:
    .ascii  "FIBONACCI USER PROGRAM"
    .space  9, 32
    .byte   10
line:
    .ascii  "F00 = 0000000000"
    .space  15, 32
    .byte   10
