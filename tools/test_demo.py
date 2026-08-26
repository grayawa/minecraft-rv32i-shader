"""Reference execution test for the bundled RV32IM and CSR self-test."""

from __future__ import annotations

import re
import struct
from pathlib import Path


MASK32 = 0xFFFFFFFF
RAM_BYTES = 16_316 * 4
FRAMEBUFFER_ADDRESS = 0x1000
FRAMEBUFFER_WORDS = 32 * 18
CSR_MSCRATCH = 0x340

EXPECTED_PROGRAM = [
    0x01500193, 0x00600213, 0x024182B3, 0x02419333,
    0x0241A3B3, 0x0241B433, 0x0241C4B3, 0x0241D533,
    0x0241E5B3, 0x0241F633, 0x07E00693, 0x04D29C63,
    0x04031A63, 0x04039863, 0x04041663, 0x00300713,
    0x04E49263, 0x04E51063, 0x02E59E63, 0x02E61C63,
    0x340297F3, 0x34002873, 0x02079663, 0x02581463,
    0x000010B7, 0x00100113, 0x00002337, 0x90030313,
    0x0020A023, 0x00408093, 0x00110113, 0xFE60EAE3,
    0x00100073, 0x000010B7, 0xDEADC137, 0xEEF10113,
    0x0020A023, 0x00100073,
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


def run_demo(program: list[int]) -> tuple[list[int], bytearray, dict[int, int], int, int, int]:
    registers = [0] * 32
    memory = bytearray(RAM_BYTES)
    csrs: dict[int, int] = {CSR_MSCRATCH: 0}
    for index, instruction in enumerate(program):
        struct.pack_into("<I", memory, index * 4, instruction)

    pc = 0
    cycle = 0
    status = 0
    while status == 0 and cycle < 10_000:
        instruction = struct.unpack_from("<I", memory, pc)[0]
        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        funct7 = instruction >> 25
        next_pc = (pc + 4) & MASK32

        if opcode == 0x37:
            registers[rd] = instruction & 0xFFFFF000
        elif opcode == 0x13 and funct3 == 0:
            immediate = sign_extend(instruction >> 20, 12)
            registers[rd] = (registers[rs1] + immediate) & MASK32
        elif opcode == 0x33 and funct7 == 1:
            registers[rd] = execute_rv32m(funct3, registers[rs1], registers[rs2])
        elif opcode == 0x23 and funct3 == 2:
            immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
            address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
            struct.pack_into("<I", memory, address, registers[rs2])
        elif opcode == 0x63:
            take = funct3 == 1 and registers[rs1] != registers[rs2]
            take |= funct3 == 6 and registers[rs1] < registers[rs2]
            if take:
                next_pc = (pc + branch_immediate(instruction)) & MASK32
        elif opcode == 0x73 and funct3 in (1, 2):
            address = instruction >> 20
            old_value = csrs[address]
            operand = registers[rs1]
            if funct3 == 1 or operand != 0:
                csrs[address] = operand if funct3 == 1 else old_value | operand
            registers[rd] = old_value
        elif instruction == 0x00100073:
            next_pc = pc
            status = 1
        else:
            raise AssertionError(f"unexpected instruction 0x{instruction:08x} at 0x{pc:08x}")

        registers[0] = 0
        pc = next_pc
        cycle += 1

    return registers, memory, csrs, pc, cycle, status


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

    registers, memory, csrs, pc, cycle, status = run_demo(program)
    values = [
        struct.unpack_from("<I", memory, FRAMEBUFFER_ADDRESS + index * 4)[0]
        for index in range(FRAMEBUFFER_WORDS)
    ]
    assert values == list(range(1, FRAMEBUFFER_WORDS + 1))
    assert registers[3:6] == [21, 6, 126]
    assert registers[9:13] == [3, 3, 3, 3]
    assert registers[15] == 0
    assert registers[16] == 126
    assert csrs[CSR_MSCRATCH] == 126
    assert pc == 0x80
    assert cycle == 2333
    assert status == 1
    print("RV32IM + Zicsr demo OK: self-test passed, 576 framebuffer stores, 2333 instructions")


if __name__ == "__main__":
    main()
