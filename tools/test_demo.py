"""Reference execution test for the bundled RV32IMA synchronous-trap self-test."""

from __future__ import annotations

import re
import struct
from pathlib import Path


MASK32 = 0xFFFFFFFF
RAM_BYTES = 16_316 * 4
FRAMEBUFFER_ADDRESS = 0x1000
FRAMEBUFFER_WORDS = 32 * 18
CSR_MSCRATCH = 0x340
CSR_MSTATUS = 0x300
CSR_MEDELEG = 0x302
CSR_MTVEC = 0x305
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342
CSR_MTVAL = 0x343
CSR_STVEC = 0x105
CSR_SSCRATCH = 0x140
CSR_SEPC = 0x141
CSR_SCAUSE = 0x142
CSR_STVAL = 0x143

EXPECTED_PROGRAM = [
    0x01500193, 0x00600213, 0x024182B3, 0x02419333,
    0x0241A3B3, 0x0241B433, 0x0241C4B3, 0x0241D533,
    0x0241E5B3, 0x0241F633, 0x07E00693, 0x22D29A63,
    0x22031863, 0x22039663, 0x22041463, 0x00300713,
    0x22E49063, 0x20E51E63, 0x20E59C63, 0x20E61A63,
    0x340297F3, 0x34002873, 0x20079463, 0x20581263,
    0x40000893, 0x00700913, 0x0128A023, 0x1008A9AF,
    0x00900A13, 0x1948AAAF, 0x0008AB03, 0x00700B93,
    0x1F799063, 0x1C0A9E63, 0x00900B93, 0x1D7B1A63,
    0x0128AC2F, 0x0008AC83, 0x1D7C1463, 0x01000B93,
    0x1D7C9063, 0x27400D13, 0x305D1073, 0x00000D93,
    0x00000073, 0x00100E13, 0x1BCD9463, 0x34202EF3,
    0x00B00F13, 0x19EE9E63, 0x00102003, 0x00200E13,
    0x19CD9863, 0x34202EF3, 0x00400F13, 0x19EE9263,
    0x34302EF3, 0x00100F13, 0x17EE9C63, 0x28800D13,
    0x105D1073, 0x2F700D13, 0x302D1073, 0x11400D13,
    0x341D1073, 0x00001D37, 0x800D0D13, 0x300D1073,
    0x30200073, 0x00000D93, 0x00000073, 0x00100E13,
    0x15CD9063, 0x14202EF3, 0x00900F13, 0x13EE9A63,
    0xFFFFFFFF, 0x00200E13, 0x13CD9463, 0x14202EF3,
    0x00200F13, 0x11EE9E63, 0x14302EF3, 0xFFF00F13,
    0x11EE9863, 0x00102003, 0x00300E13, 0x11CD9263,
    0x14202EF3, 0x00400F13, 0x0FEE9C63, 0x14302EF3,
    0x00100F13, 0x0FEE9663, 0x00002123, 0x00400E13,
    0x0FCD9063, 0x14202EF3, 0x00600F13, 0x0DEE9A63,
    0x14302EF3, 0x00200F13, 0x0DEE9463, 0x00010D37,
    0xEF0D0D13, 0x000D2003, 0x00500E13, 0x0BCD9A63,
    0x14202EF3, 0x00500F13, 0x0BEE9463, 0x14302EF3,
    0x0BAE9063, 0x000D2023, 0x00600E13, 0x09CD9A63,
    0x14202EF3, 0x00700F13, 0x09EE9463, 0x14302EF3,
    0x09AE9063, 0x00200D13, 0x000D0067, 0x00700E13,
    0x07CD9863, 0x14202EF3, 0x00000F13, 0x07EE9263,
    0x14302EF3, 0x00200F13, 0x05EE9C63, 0x22000D13,
    0x140D1073, 0x00010D37, 0xEF0D0D13, 0x000D0067,
    0x00800E13, 0x03CD9E63, 0x14202EF3, 0x00100F13,
    0x03EE9863, 0x14302EF3, 0x03AE9463, 0x000010B7,
    0x00100113, 0x00002337, 0x90030313, 0x0020A023,
    0x00408093, 0x00110113, 0xFE60EAE3, 0x00100073,
    0x000010B7, 0xDEADC137, 0xEEF10113, 0x0020A023,
    0x00100073, 0x001D8D93, 0x34102FF3, 0x004F8F93,
    0x341F9073, 0x30200073, 0x001D8D93, 0x14202F73,
    0x00100F93, 0x01FF1863, 0x14002FF3, 0x141F9073,
    0x10200073, 0x14102FF3, 0x004F8F93, 0x141F9073,
    0x10200073,
]


def signed(value: int) -> int:
    value &= MASK32
    return value - (1 << 32) if value & (1 << 31) else value


def sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def trunc_div(left: int, right: int) -> int:
    magnitude = abs(left) // abs(right)
    return -magnitude if (left < 0) != (right < 0) else magnitude


def execute_rv32m(funct3: int, left: int, right: int) -> int:
    left &= MASK32
    right &= MASK32
    signed_left = signed(left)
    signed_right = signed(right)
    if funct3 == 0:
        return left * right & MASK32
    if funct3 == 1:
        return (signed_left * signed_right >> 32) & MASK32
    if funct3 == 2:
        return (signed_left * right >> 32) & MASK32
    if funct3 == 3:
        return (left * right >> 32) & MASK32
    if funct3 == 4:
        if right == 0:
            return MASK32
        if left == 0x80000000 and right == MASK32:
            return left
        return trunc_div(signed_left, signed_right) & MASK32
    if funct3 == 5:
        return MASK32 if right == 0 else left // right
    if funct3 == 6:
        if right == 0:
            return left
        if left == 0x80000000 and right == MASK32:
            return 0
        quotient = trunc_div(signed_left, signed_right)
        return (signed_left - quotient * signed_right) & MASK32
    if funct3 == 7:
        return left if right == 0 else left % right
    raise AssertionError(f"unknown RV32M funct3 {funct3}")


def shader_multiply_high_unsigned(left: int, right: int) -> int:
    left_low = left & 0xFFFF
    left_high = left >> 16
    right_low = right & 0xFFFF
    right_high = right >> 16
    low_product = left_low * right_low
    middle = left_high * right_low + (low_product >> 16)
    carry_product = left_low * right_high + (middle & 0xFFFF)
    return (left_high * right_high + (middle >> 16) + (carry_product >> 16)) & MASK32


def shader_multiply_high_signed_unsigned(left: int, right: int) -> int:
    high_word = shader_multiply_high_unsigned(left, right)
    return (high_word - right if left & 0x80000000 else high_word) & MASK32


def shader_multiply_high_signed(left: int, right: int) -> int:
    high_word = shader_multiply_high_unsigned(left, right)
    if left & 0x80000000:
        high_word -= right
    if right & 0x80000000:
        high_word -= left
    return high_word & MASK32


def verify_high_multiply() -> None:
    values = [0, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, MASK32, 0x12345678]
    for left in values:
        for right in values:
            actual = shader_multiply_high_unsigned(left, right)
            expected = (left * right >> 32) & MASK32
            assert actual == expected, (hex(left), hex(right), hex(actual), hex(expected))
            signed_unsigned = shader_multiply_high_signed_unsigned(left, right)
            expected_signed_unsigned = (signed(left) * right >> 32) & MASK32
            assert signed_unsigned == expected_signed_unsigned
            signed_signed = shader_multiply_high_signed(left, right)
            expected_signed_signed = (signed(left) * signed(right) >> 32) & MASK32
            assert signed_signed == expected_signed_signed

    assert execute_rv32m(4, 0x80000000, MASK32) == 0x80000000
    assert execute_rv32m(4, 123, 0) == MASK32
    assert execute_rv32m(6, 0x80000000, MASK32) == 0
    assert execute_rv32m(6, 123, 0) == 123


def branch_immediate(instruction: int) -> int:
    value = (
        (((instruction >> 31) & 1) << 12)
        | (((instruction >> 7) & 1) << 11)
        | (((instruction >> 25) & 0x3F) << 5)
        | (((instruction >> 8) & 0xF) << 1)
    )
    return sign_extend(value, 13)


def run_demo(program: list[int]) -> tuple[list[int], bytearray, dict[int, int], int, int, int, int]:
    registers = [0] * 32
    memory = bytearray(RAM_BYTES)
    csrs: dict[int, int] = {
        CSR_MSTATUS: 0,
        CSR_MEDELEG: 0,
        CSR_MTVEC: 0,
        CSR_MSCRATCH: 0,
        CSR_MEPC: 0,
        CSR_MCAUSE: 0,
        CSR_MTVAL: 0,
        CSR_STVEC: 0,
        CSR_SSCRATCH: 0,
        CSR_SEPC: 0,
        CSR_SCAUSE: 0,
        CSR_STVAL: 0,
    }
    privilege = 3
    reservation: int | None = None
    for index, instruction in enumerate(program):
        struct.pack_into("<I", memory, index * 4, instruction)

    pc = 0
    cycle = 0
    status = 0
    while status == 0 and cycle < 10_000:
        next_pc = (pc + 4) & MASK32
        trap: tuple[int, int] | None = None
        instruction = 0

        if pc & 3:
            trap = (0, pc)
        elif pc > RAM_BYTES - 4:
            trap = (1, pc)
        else:
            instruction = struct.unpack_from("<I", memory, pc)[0]
            opcode = instruction & 0x7F
            rd = (instruction >> 7) & 0x1F
            funct3 = (instruction >> 12) & 7
            rs1 = (instruction >> 15) & 0x1F
            rs2 = (instruction >> 20) & 0x1F
            funct7 = instruction >> 25

            if opcode == 0x37:
                registers[rd] = instruction & 0xFFFFF000
            elif opcode == 0x13 and funct3 == 0:
                immediate = sign_extend(instruction >> 20, 12)
                registers[rd] = (registers[rs1] + immediate) & MASK32
            elif opcode == 0x33 and funct7 == 1:
                registers[rd] = execute_rv32m(funct3, registers[rs1], registers[rs2])
            elif opcode == 0x67 and funct3 == 0:
                immediate = sign_extend(instruction >> 20, 12)
                target = (registers[rs1] + immediate) & 0xFFFFFFFE
                if target & 3:
                    trap = (0, target)
                else:
                    registers[rd] = next_pc
                    next_pc = target
            elif opcode == 0x23 and funct3 == 2:
                immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
                address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
                if address & 3:
                    trap = (6, address)
                elif address > RAM_BYTES - 4:
                    trap = (7, address)
                else:
                    struct.pack_into("<I", memory, address, registers[rs2])
                    reservation = None
            elif opcode == 0x03 and funct3 == 2:
                immediate = sign_extend(instruction >> 20, 12)
                address = (registers[rs1] + immediate) & MASK32
                if address & 3:
                    trap = (4, address)
                elif address > RAM_BYTES - 4:
                    trap = (5, address)
                else:
                    registers[rd] = struct.unpack_from("<I", memory, address)[0]
            elif opcode == 0x2F and funct3 == 2:
                address = registers[rs1]
                atomic_function = instruction >> 27
                load_reservation = atomic_function == 2 and rs2 == 0
                if address & 3:
                    trap = (4 if load_reservation else 6, address)
                elif address > RAM_BYTES - 4:
                    trap = (5 if load_reservation else 7, address)
                else:
                    old_value = struct.unpack_from("<I", memory, address)[0]
                    if load_reservation:
                        registers[rd] = old_value
                        reservation = address
                    elif atomic_function == 3:
                        success = reservation == address
                        registers[rd] = 0 if success else 1
                        if success:
                            struct.pack_into("<I", memory, address, registers[rs2])
                        reservation = None
                    elif atomic_function == 0:
                        registers[rd] = old_value
                        struct.pack_into(
                            "<I", memory, address, (old_value + registers[rs2]) & MASK32
                        )
                        reservation = None
                    else:
                        trap = (2, instruction)
            elif opcode == 0x63:
                take = funct3 == 1 and registers[rs1] != registers[rs2]
                take |= funct3 == 6 and registers[rs1] < registers[rs2]
                if take:
                    target = (pc + branch_immediate(instruction)) & MASK32
                    if target & 3:
                        trap = (0, target)
                    else:
                        next_pc = target
            elif opcode == 0x73 and funct3 in (1, 2):
                address = instruction >> 20
                if address not in csrs:
                    trap = (2, instruction)
                else:
                    old_value = csrs[address]
                    operand = registers[rs1]
                    if funct3 == 1 or operand != 0:
                        csrs[address] = operand if funct3 == 1 else old_value | operand
                    registers[rd] = old_value
            elif instruction == 0x00000073:
                trap = (8 if privilege == 0 else 9 if privilege == 1 else 11, 0)
            elif instruction == 0x30200073 and privilege == 3:
                previous_interrupt_enable = (csrs[CSR_MSTATUS] >> 7) & 1
                previous_privilege = (csrs[CSR_MSTATUS] >> 11) & 3
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x1888)
                    | (previous_interrupt_enable << 3)
                    | (1 << 7)
                )
                privilege = previous_privilege
                next_pc = csrs[CSR_MEPC]
            elif instruction == 0x10200073 and privilege >= 1:
                previous_interrupt_enable = (csrs[CSR_MSTATUS] >> 5) & 1
                previous_privilege = (csrs[CSR_MSTATUS] >> 8) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x122)
                    | (previous_interrupt_enable << 1)
                    | (1 << 5)
                )
                privilege = previous_privilege
                next_pc = csrs[CSR_SEPC]
            elif instruction == 0x00100073:
                next_pc = pc
                status = 1
            else:
                trap = (2, instruction)

        if trap is not None:
            cause, trap_value = trap
            delegated = privilege != 3 and (csrs[CSR_MEDELEG] >> cause) & 1
            if delegated:
                supervisor_interrupt_enable = (csrs[CSR_MSTATUS] >> 1) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x122)
                    | (supervisor_interrupt_enable << 5)
                    | ((privilege & 1) << 8)
                )
                csrs[CSR_SEPC] = pc
                csrs[CSR_SCAUSE] = cause
                csrs[CSR_STVAL] = trap_value
                privilege = 1
                next_pc = csrs[CSR_STVEC] & ~3
            else:
                machine_interrupt_enable = (csrs[CSR_MSTATUS] >> 3) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x1888)
                    | (machine_interrupt_enable << 7)
                    | (privilege << 11)
                )
                csrs[CSR_MEPC] = pc
                csrs[CSR_MCAUSE] = cause
                csrs[CSR_MTVAL] = trap_value
                privilege = 3
                next_pc = csrs[CSR_MTVEC] & ~3

        registers[0] = 0
        pc = next_pc
        cycle += 1
    return registers, memory, csrs, pc, cycle, status, privilege


def main() -> None:
    shader_path = (
        Path(__file__).resolve().parents[1]
        / "assets" / "mcrv" / "shaders" / "post" / "rv32_step.fsh"
    )
    shader_source = shader_path.read_text(encoding="utf-8")
    shader_words = {
        int(index): int(word, 16)
        for index, word in re.findall(
            r"if \(index == (\d+)u\) return 0x([0-9a-fA-F]+)u;", shader_source
        )
    }
    program = [shader_words[index] for index in range(len(EXPECTED_PROGRAM))]
    assert program == EXPECTED_PROGRAM
    verify_high_multiply()

    registers, memory, csrs, pc, cycle, status, privilege = run_demo(program)
    values = [
        struct.unpack_from("<I", memory, FRAMEBUFFER_ADDRESS + index * 4)[0]
        for index in range(FRAMEBUFFER_WORDS)
    ]
    assert values == list(range(1, FRAMEBUFFER_WORDS + 1))
    assert registers[3:6] == [21, 6, 126]
    assert registers[9:13] == [3, 3, 3, 3]
    assert registers[15] == 0
    assert registers[16] == 126
    assert registers[19] == 7
    assert registers[21] == 0
    assert registers[22] == 9
    assert registers[24] == 9
    assert registers[25] == 16
    assert registers[27] == 8
    assert registers[29] == 0xFEF0
    assert struct.unpack_from("<I", memory, 1024)[0] == 16
    assert csrs[CSR_MSCRATCH] == 126
    assert csrs[CSR_MTVEC] == 0x274
    assert csrs[CSR_MEPC] == 0x114
    assert csrs[CSR_MCAUSE] == 4
    assert csrs[CSR_MTVAL] == 1
    assert csrs[CSR_MEDELEG] == 0x2F7
    assert csrs[CSR_STVEC] == 0x288
    assert csrs[CSR_SSCRATCH] == 0x220
    assert csrs[CSR_SEPC] == 0x220
    assert csrs[CSR_SCAUSE] == 1
    assert csrs[CSR_STVAL] == 0xFEF0
    assert csrs[CSR_MSTATUS] == 0xA0
    assert privilege == 1
    assert pc == 0x25C
    assert cycle == 2526
    assert status == 1
    print("RV32IMA synchronous traps OK: 8 exception paths, 576 framebuffer stores, 2526 instructions")


if __name__ == "__main__":
    main()
