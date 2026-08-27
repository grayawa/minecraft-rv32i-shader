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
    addi  x17, x0, 2047
    addi  x17, x17, 1
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
    addi  x26, x0, machine_trap_handler
    csrrw x0, mtvec, x26
    addi  x27, x0, 0
    ecall
    addi  x28, x0, 1
    bne   x27, x28, machine_self_test_failed
    csrrs x29, mcause, x0
    addi  x30, x0, 11
    bne   x29, x30, machine_self_test_failed

    lw    x0, 1(x0)
    addi  x28, x0, 2
    bne   x27, x28, machine_self_test_failed
    csrrs x29, mcause, x0
    addi  x30, x0, 4
    bne   x29, x30, machine_self_test_failed
    csrrs x29, mtval, x0
    addi  x30, x0, 1
    bne   x29, x30, machine_self_test_failed

    # Route a 16550A transmit event through PLIC source 10 and MEIP.
    addi  x27, x0, 0
    lui   x17, 0xc000
    addi  x17, x17, 40
    addi  x19, x0, 1
    sw    x19, 0(x17)
    lui   x17, 0xc002
    addi  x19, x0, 1024
    sw    x19, 0(x17)
    lui   x17, 0xc200
    sw    x0, 0(x17)

    lui   x18, 0x10000
    addi  x19, x0, 2
    sb    x19, 1(x18)
    lbu   x20, 5(x18)
    addi  x21, x0, 0x60
    bne   x20, x21, machine_self_test_failed
    lui   x20, 0x1
    addi  x20, x20, -2048
    csrrs x0, mie, x20
    addi  x20, x0, 8
    csrrs x0, mstatus, x20
    addi  x19, x0, 85
    sb    x19, 0(x18)
    nop
    nop
    nop
    nop

    addi  x28, x0, 1
    bne   x27, x28, machine_self_test_failed
    csrrs x29, mcause, x0
    lui   x30, 0x80000
    addi  x30, x30, 11
    bne   x29, x30, machine_self_test_failed
    sb    x0, 1(x18)

    # Send the remaining UART IRQ OK line with polling-style writes.
    addi  x19, x0, 65
    sb    x19, 0(x18)
    addi  x19, x0, 82
    sb    x19, 0(x18)
    addi  x19, x0, 84
    sb    x19, 0(x18)
    addi  x19, x0, 32
    sb    x19, 0(x18)
    addi  x19, x0, 73
    sb    x19, 0(x18)
    addi  x19, x0, 82
    sb    x19, 0(x18)
    addi  x19, x0, 81
    sb    x19, 0(x18)
    addi  x19, x0, 32
    sb    x19, 0(x18)
    addi  x19, x0, 79
    sb    x19, 0(x18)
    addi  x19, x0, 75
    sb    x19, 0(x18)
    addi  x19, x0, 32
    sb    x19, 0(x18)

    # Validate CLINT software state and deliver a machine timer interrupt.
    addi  x27, x0, 0
    lui   x17, 0x2000
    addi  x19, x0, 1
    sw    x19, 0(x17)
    lw    x20, 0(x17)
    bne   x20, x19, machine_self_test_failed
    sw    x0, 0(x17)

    lui   x17, 0x2004
    lui   x18, 0x200c
    addi  x18, x18, -8
    sw    x0, 0(x18)
    sw    x0, 4(x18)
    sw    x0, 4(x17)
    addi  x19, x0, 12
    sw    x19, 0(x17)
    addi  x20, x0, 128
    csrrs x0, mie, x20
    addi  x20, x0, 8
    csrrs x0, mstatus, x20
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    addi  x28, x0, 1
    bne   x27, x28, machine_self_test_failed
    csrrs x29, mcause, x0
    lui   x30, 0x80000
    addi  x30, x30, 7
    bne   x29, x30, machine_self_test_failed

    # Build an Sv32 root table at 0xa000 and a level-zero table at 0xb000.
    # Supervisor and user aliases map code page zero and framebuffer page one.
    lui   x17, 0xa
    lui   x18, 0xb
    lui   x19, 0x3
    addi  x19, x19, -1023
    sw    x19, 1024(x17)
    addi  x19, x0, 0x4b
    sw    x19, 0(x18)
    addi  x19, x0, 0x4c7
    sw    x19, 4(x18)
    addi  x19, x0, 0x59
    sw    x19, 8(x18)
    addi  x19, x0, 0x4d7
    sw    x19, 12(x18)

    # Identity-map the PLIC and UART 4 MiB regions for S-mode firmware.
    lui   x19, 0x3000
    addi  x19, x19, 0xc7
    sw    x19, 192(x17)
    lui   x19, 0x4000
    addi  x19, x19, 0xc7
    sw    x19, 256(x17)

    lui   x26, 0x80000
    addi  x26, x26, 10
    csrrw x0, satp, x26
    sfence.vma x0, x0

    # MPRV uses the supervisor mapping for translated data access.
    lui   x17, 0x1
    addi  x20, x0, 42
    sw    x20, 0(x17)
    lui   x21, 0x40001
    lui   x26, 0x21
    addi  x26, x26, -2048
    csrrw x0, mstatus, x26
    lw    x22, 0(x21)
    bne   x22, x20, machine_self_test_failed
    addi  x23, x0, 43
    sw    x23, 0(x21)
    csrrw x0, mstatus, x0
    lw    x24, 0(x17)
    bne   x24, x23, machine_self_test_failed

    # Configure supervisor exception and timer-interrupt delegation.
    lui   x26, 0x40000
    addi  x26, x26, supervisor_trap_handler
    csrrw x0, stvec, x26
    lui   x26, 0xb
    addi  x26, x26, 0x3f7
    csrrw x0, medeleg, x26
    # Arm a delegated supervisor external interrupt alongside STIP.
    lui   x17, 0xc002
    addi  x17, x17, 128
    addi  x19, x0, 1024
    sw    x0, -128(x17)
    sw    x19, 0(x17)
    lui   x17, 0xc201
    sw    x0, 0(x17)
    lui   x18, 0x10000
    addi  x19, x0, 2
    sb    x19, 1(x18)
    addi  x19, x0, 83
    sb    x19, 0(x18)

    addi  x20, x0, 0x220
    csrrw x0, mideleg, x20
    csrrs x0, mie, x20
    lui   x26, 0x40000
    addi  x26, x26, supervisor_test
    csrrw x0, mepc, x26
    lui   x26, 0x1
    addi  x26, x26, -2046
    csrrw x0, mstatus, x26
    mret

supervisor_test:
    # Firmware has received delegated SEIP and the converted timer STIP.
    addi  x28, x0, 3
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    lui   x30, 0x80000
    addi  x30, x30, 5
    bne   x29, x30, supervisor_self_test_failed

    addi  x27, x0, 0
    ecall
    addi  x28, x0, 1
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 9
    bne   x29, x30, supervisor_self_test_failed

    .word 0xffffffff
    addi  x28, x0, 2
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 2
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, -1
    bne   x29, x30, supervisor_self_test_failed

    lw    x0, 1(x0)
    addi  x28, x0, 3
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 4
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 1
    bne   x29, x30, supervisor_self_test_failed

    sw    x0, 2(x0)
    addi  x28, x0, 4
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 6
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 2
    bne   x29, x30, supervisor_self_test_failed

    lui   x26, 0x50000
    lw    x0, 0(x26)
    addi  x28, x0, 5
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 13
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, supervisor_self_test_failed

    sw    x0, 0(x26)
    addi  x28, x0, 6
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 15
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, supervisor_self_test_failed

    addi  x26, x0, 2
    jalr  x0, 0(x26)
    addi  x28, x0, 7
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 0
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    addi  x30, x0, 2
    bne   x29, x30, supervisor_self_test_failed

    lui   x26, 0x40000
    addi  x26, x26, fetch_resume
    csrrw x0, sscratch, x26
    lui   x26, 0x50000
    jalr  x0, 0(x26)

fetch_resume:
    addi  x28, x0, 8
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 12
    bne   x29, x30, supervisor_self_test_failed
    csrrs x29, stval, x0
    bne   x29, x26, supervisor_self_test_failed
    sfence.vma x0, x0

    # SUM grants S-mode data access to the user data page.
    lui   x26, 0x40003
    lw    x20, 0(x26)
    addi  x28, x0, 9
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 13
    bne   x29, x30, supervisor_self_test_failed
    lui   x25, 0x40
    csrrs x0, sstatus, x25
    lw    x20, 0(x26)
    bne   x20, x23, supervisor_self_test_failed

    # MXR grants load access to the execute-only user code alias.
    lui   x26, 0x40002
    addi  x26, x26, user_test+4
    lw    x20, 0(x26)
    addi  x28, x0, 10
    bne   x27, x28, supervisor_self_test_failed
    csrrs x29, scause, x0
    addi  x30, x0, 13
    bne   x29, x30, supervisor_self_test_failed
    lui   x25, 0x80
    csrrs x0, sstatus, x25
    lw    x20, 0(x26)
    addi  x23, x0, 0x73
    bne   x20, x23, supervisor_self_test_failed

    # SRET enters the execute-only user alias at 0x400023dc.
    lui   x26, 0x40002
    addi  x26, x26, user_test
    csrrw x0, sepc, x26
    sret

user_test:
    addi  x27, x0, 0
    ecall
    addi  x28, x0, 1
    bne   x27, x28, user_self_test_failed
    addi  x28, x0, 8
    bne   x30, x28, user_self_test_failed

    # User access to a supervisor page raises a delegated load page fault.
    lui   x26, 0x40000
    lw    x0, 0(x26)
    addi  x28, x0, 2
    bne   x27, x28, user_self_test_failed
    addi  x28, x0, 13
    bne   x30, x28, user_self_test_failed

    # U-mode fills the physical framebuffer through its user data alias.
    lui   x1, 0x40003
    addi  x2, x0, 1
    lui   x6, 0x40004
    addi  x6, x6, -1792

fill_framebuffer:
    sw    x2, 0(x1)
    addi  x1, x1, 4
    addi  x2, x2, 1
    bltu  x1, x6, fill_framebuffer
    ebreak

self_test_failed:
machine_self_test_failed:
    lui   x1, 0x1
    lui   x2, 0xdeadc
    addi  x2, x2, -273
    sw    x2, 0(x1)
    ebreak

supervisor_self_test_failed:
    lui   x1, 0x40001
    lui   x2, 0xdeadc
    addi  x2, x2, -273
    sw    x2, 0(x1)
    ebreak

user_self_test_failed:
    lui   x1, 0x40003
    lui   x2, 0xdeadc
    addi  x2, x2, -273
    sw    x2, 0(x1)
    ebreak

    .org 1536
machine_trap_handler:
    csrrs x30, mcause, x0
    blt   x30, x0, machine_interrupt
    addi  x27, x27, 1
    csrrs x31, mepc, x0
    addi  x31, x31, 4
    csrrw x0, mepc, x31
    mret

machine_interrupt:
    lui   x31, 0x80000
    addi  x31, x31, 11
    bne   x30, x31, machine_timer_interrupt
    addi  x27, x27, 1
    lui   x31, 0xc200
    lw    x29, 4(x31)
    addi  x28, x0, 10
    bne   x29, x28, machine_self_test_failed
    sw    x29, 4(x31)
    mret

machine_timer_interrupt:
    addi  x27, x27, 1
    addi  x31, x0, 128
    csrrc x0, mie, x31
    addi  x31, x0, 32
    csrrs x0, mip, x31
    mret

    .org 1640
supervisor_trap_handler:
    csrrs x30, scause, x0
    blt   x30, x0, supervisor_interrupt
    addi  x27, x27, 1
    addi  x31, x0, 12
    bne   x30, x31, supervisor_normal_return
    csrrs x31, sscratch, x0
    csrrw x0, sepc, x31
    sret

supervisor_normal_return:
    csrrs x31, sepc, x0
    addi  x31, x31, 4
    csrrw x0, sepc, x31
    sret

supervisor_interrupt:
    lui   x31, 0x80000
    addi  x31, x31, 9
    bne   x30, x31, supervisor_timer_interrupt
    addi  x27, x27, 1
    lui   x31, 0xc201
    lw    x29, 4(x31)
    addi  x28, x0, 10
    bne   x29, x28, supervisor_self_test_failed
    sw    x29, 4(x31)
    lui   x31, 0x10000
    sb    x0, 1(x31)
    sret

supervisor_timer_interrupt:
    addi  x27, x27, 1
    addi  x31, x0, 32
    csrrc x0, sip, x31
    sret
