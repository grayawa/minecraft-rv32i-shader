"""Reference execution test for the RV32I framebuffer demo."""

from __future__ import annotations

import re
import struct
from pathlib import Path


RAM_BYTES = 16_348 * 4
FRAMEBUFFER_ADDRESS = 0x1000
FRAMEBUFFER_WORDS = 32 * 18


def encode_lui(rd: int, upper: int) -> int:
    return (upper << 12) | (rd << 7) | 0x37


def encode_addi(rd: int, rs1: int, immediate: int) -> int:
    return ((immediate & 0xFFF) << 20) | (rs1 << 15) | (rd << 7) | 0x13


def encode_sw(rs2: int, rs1: int, immediate: int) -> int:
    value = immediate & 0xFFF
    return (
        ((value >> 5) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (2 << 12)
        | ((value & 0x1F) << 7)
        | 0x23
    )


def encode_bltu(rs1: int, rs2: int, immediate: int) -> int:
    value = immediate & 0x1FFF
    return (
        (((value >> 12) & 1) << 31)
        | (((value >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (6 << 12)
        | (((value >> 1) & 0xF) << 8)
        | (((value >> 11) & 1) << 7)
        | 0x63
    )


PROGRAM = [
    encode_lui(1, 0x1),
    encode_addi(2, 0, 1),
    encode_lui(6, 0x2),
    encode_addi(6, 6, -1792),
    encode_sw(2, 1, 0),
    encode_addi(1, 1, 4),
    encode_addi(2, 2, 1),
    encode_bltu(1, 6, -12),
    0x00100073,
]

EXPECTED_PROGRAM = [
    0x000010B7,
    0x00100113,
    0x00002337,
    0x90030313,
    0x0020A023,
    0x00408093,
    0x00110113,
    0xFE60EAE3,
    0x00100073,
]


def sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def run_demo() -> tuple[list[int], bytearray, int, int, int]:
    registers = [0] * 32
    memory = bytearray(RAM_BYTES)
    for index, instruction in enumerate(PROGRAM):
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
        next_pc = (pc + 4) & 0xFFFFFFFF

        if opcode == 0x37:
            registers[rd] = instruction & 0xFFFFF000
        elif opcode == 0x13 and funct3 == 0:
            immediate = sign_extend(instruction >> 20, 12)
            registers[rd] = (registers[rs1] + immediate) & 0xFFFFFFFF
        elif opcode == 0x23 and funct3 == 2:
            immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
            immediate = sign_extend(immediate, 12)
            address = (registers[rs1] + immediate) & 0xFFFFFFFF
            struct.pack_into("<I", memory, address, registers[rs2])
        elif opcode == 0x63 and funct3 == 6:
            immediate = (
                (((instruction >> 31) & 1) << 12)
                | (((instruction >> 7) & 1) << 11)
                | (((instruction >> 25) & 0x3F) << 5)
                | (((instruction >> 8) & 0xF) << 1)
            )
            if registers[rs1] < registers[rs2]:
                next_pc = (pc + sign_extend(immediate, 13)) & 0xFFFFFFFF
        elif instruction == 0x00100073:
            next_pc = pc
            status = 1
        else:
            raise AssertionError(f"unexpected instruction 0x{instruction:08x} at 0x{pc:08x}")

        registers[0] = 0
        pc = next_pc
        cycle += 1

    return registers, memory, pc, cycle, status


def main() -> None:
    assert PROGRAM == EXPECTED_PROGRAM
    shader_path = (
        Path(__file__).resolve().parents[1]
        / "assets"
        / "mcrv"
        / "shaders"
        / "post"
        / "rv32_step.fsh"
    )
    shader_source = shader_path.read_text(encoding="utf-8")
    shader_words = {
        int(index): int(word, 16)
        for index, word in re.findall(
            r"if \(index == (\d+)u\) return 0x([0-9a-fA-F]+)u;", shader_source
        )
    }
    assert [shader_words[index] for index in range(len(PROGRAM))] == PROGRAM

    registers, memory, pc, cycle, status = run_demo()
    values = [
        struct.unpack_from("<I", memory, FRAMEBUFFER_ADDRESS + index * 4)[0]
        for index in range(FRAMEBUFFER_WORDS)
    ]
    assert values == list(range(1, FRAMEBUFFER_WORDS + 1))
    assert registers[1] == 0x1900
    assert registers[2] == FRAMEBUFFER_WORDS + 1
    assert registers[6] == 0x1900
    assert pc == 0x20
    assert cycle == 2309
    assert status == 1
    print("RV32I demo OK: 576 framebuffer stores, 2309 instructions, EBREAK")


if __name__ == "__main__":
    main()
