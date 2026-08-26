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

    # Validate LR/SC reservation and an atomic read-modify-write operation.
    addi  x17, x0, 1024
    addi  x18, x0, 7
    sw    x18, 0(x17)
    lr.w  x19, (x17)
    addi  x20, x0, 9
    sc.w  x21, x20, (x17)
    lw    x22, 0(x17)
    addi  x23, x0, 7
    bne   x19, x23, self_test_failed
    bne   x21, x0, self_test_failed
    addi  x23, x0, 9
    bne   x22, x23, self_test_failed
    amoadd.w x24, x18, (x17)
    lw    x25, 0(x17)
    bne   x24, x23, self_test_failed
    addi  x23, x0, 16
    bne   x25, x23, self_test_failed

    # Exercise M-mode ECALL and load-address-misaligned trap entry.
    addi  x26, x0, 628
    csrrw x0, mtvec, x26
    addi  x27, x0, 0
    ecall
    addi  x28, x0, 1
    bne   x27, x28, self_test_failed
    csrrs x29, mcause, x0
    addi  x30, x0, 11
    bne   x29, x30, self_test_failed

    lw    x0, 1(x0)
    addi  x28, x0, 2
    bne   x27, x28, self_test_failed
    csrrs x29, mcause, x0
    addi  x30, x0, 4
    bne   x29, x30, self_test_failed
    csrrs x29, mtval, x0
    addi  x30, x0, 1
    bne   x29, x30, self_test_failed

    # Delegate synchronous exceptions and enter S-mode through MRET.
    addi  x26, x0, 648
    csrrw x0, stvec, x26
    addi  x26, x0, 0x2f7
    csrrw x0, medeleg, x26
    addi  x26, x0, 276
    csrrw x0, mepc, x26
    lui   x26, 0x1
    addi  x26, x26, -2048
    csrrw x0, mstatus, x26
    mret

supervisor_test:
    # Check S-mode ECALL delegation.
    addi  x27, x0, 0
    ecall
    addi  x28, x0, 1
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 9
    bne   x29, x30, self_test_failed

    # Check illegal-instruction trap metadata.
    .word 0xffffffff
    addi  x28, x0, 2
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 2
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, -1
    bne   x29, x30, self_test_failed

    # Check load and store address-alignment traps.
    lw    x0, 1(x0)
    addi  x28, x0, 3
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 4
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 1
    bne   x29, x30, self_test_failed

    sw    x0, 2(x0)
    addi  x28, x0, 4
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 6
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 2
    bne   x29, x30, self_test_failed

    # 0x0000fef0 is the first byte beyond the emulated RAM window.
    lui   x26, 0x10
    addi  x26, x26, -272
    lw    x0, 0(x26)
    addi  x28, x0, 5
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 5
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, self_test_failed

    sw    x0, 0(x26)
    addi  x28, x0, 6
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 7
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, self_test_failed

    # Check an instruction-address-misaligned trap raised by JALR.
    addi  x26, x0, 2
    jalr  x0, 0(x26)
    addi  x28, x0, 7
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 0
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 2
    bne   x29, x30, self_test_failed

    # Check an instruction-access fault and resume through sscratch.
    addi  x26, x0, 544
    csrrw x0, sscratch, x26
    lui   x26, 0x10
    addi  x26, x26, -272
    jalr  x0, 0(x26)

fetch_resume:
    addi  x28, x0, 8
    bne   x27, x28, self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 1
    bne   x29, x30, self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, self_test_failed

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

    .org 628
machine_trap_handler:
    addi  x27, x27, 1
    csrrs x31, mepc, x0
    addi  x31, x31, 4
    csrrw x0, mepc, x31
    mret

    .org 648
supervisor_trap_handler:
    addi  x27, x27, 1
    csrrs x30, scause, x0
    addi  x31, x0, 1
    bne   x30, x31, supervisor_normal_return
    csrrs x31, sscratch, x0
    csrrw x0, sepc, x31
    sret

supervisor_normal_return:
    csrrs x31, sepc, x0
    addi  x31, x31, 4
    csrrw x0, sepc, x31
    sret
