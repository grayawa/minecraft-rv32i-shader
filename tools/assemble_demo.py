"""Assemble the RV32IMA instructions used by the bundled demonstration program."""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


CSR_ADDRESSES = {
    "sstatus": 0x100,
    "sie": 0x104,
    "stvec": 0x105,
    "sscratch": 0x140,
    "sepc": 0x141,
    "scause": 0x142,
    "stval": 0x143,
    "sip": 0x144,
    "satp": 0x180,
    "mstatus": 0x300,
    "medeleg": 0x302,
    "mideleg": 0x303,
    "mie": 0x304,
    "mtvec": 0x305,
    "mscratch": 0x340,
    "mepc": 0x341,
    "mcause": 0x342,
    "mtval": 0x343,
    "mip": 0x344,
}

R_FUNCT = {
    "mul": (0, 1),
    "mulh": (1, 1),
    "mulhsu": (2, 1),
    "mulhu": (3, 1),
    "div": (4, 1),
    "divu": (5, 1),
    "rem": (6, 1),
    "remu": (7, 1),
}

BRANCH_FUNCT3 = {"bne": 1, "blt": 4, "bltu": 6}
CSR_FUNCT3 = {"csrrw": 1, "csrrs": 2, "csrrc": 3}


def register(token: str) -> int:
    match = re.fullmatch(r"x([0-9]|[12][0-9]|3[01])", token)
    if match is None:
        raise ValueError(f"unknown register {token}")
    return int(match.group(1))


def integer(token: str) -> int:
    return int(token, 0)


def resolve_immediate(token: str, labels: dict[str, int]) -> int:
    if token in labels:
        return labels[token]
    match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)([+-][0-9]+)", token)
    if match is not None and match.group(1) in labels:
        return labels[match.group(1)] + int(match.group(2))
    return integer(token)


def signed_bits(value: int, bits: int) -> int:
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    if value < minimum or value > maximum:
        raise ValueError(f"immediate {value} exceeds signed {bits}-bit range")
    return value & ((1 << bits) - 1)


def encode_branch(offset: int, rs1: int, rs2: int, funct3: int) -> int:
    immediate = signed_bits(offset, 13)
    return (
        ((immediate >> 12) & 1) << 31
        | ((immediate >> 5) & 0x3F) << 25
        | rs2 << 20
        | rs1 << 15
        | funct3 << 12
        | ((immediate >> 1) & 0xF) << 8
        | ((immediate >> 11) & 1) << 7
        | 0x63
    )


def parse_memory_operand(token: str, labels: dict[str, int]) -> tuple[int, int]:
    match = re.fullmatch(r"(.+)\((x(?:[0-9]|[12][0-9]|3[01]))\)", token)
    if match is None:
        raise ValueError(f"invalid memory operand {token}")
    return resolve_immediate(match.group(1), labels), register(match.group(2))


def encode_instruction(
    operation: str, operands: list[str], pc: int, labels: dict[str, int]
) -> int:
    if operation == "nop":
        return 0x00000013
    if operation == "ecall":
        return 0x00000073
    if operation == "ebreak":
        return 0x00100073
    if operation == "mret":
        return 0x30200073
    if operation == "sret":
        return 0x10200073
    if operation == "sfence.vma":
        return 0x12000073
    if operation == "lui":
        rd, immediate = register(operands[0]), integer(operands[1])
        return ((immediate & 0xFFFFF) << 12) | (rd << 7) | 0x37
    if operation == "addi":
        rd, rs1 = register(operands[0]), register(operands[1])
        immediate_value = signed_bits(resolve_immediate(operands[2], labels), 12)
        return (immediate_value << 20) | (rs1 << 15) | (rd << 7) | 0x13
    if operation in R_FUNCT:
        rd, rs1, rs2 = map(register, operands)
        funct3, funct7 = R_FUNCT[operation]
        return (
            funct7 << 25
            | rs2 << 20
            | rs1 << 15
            | funct3 << 12
            | rd << 7
            | 0x33
        )
    if operation in BRANCH_FUNCT3:
        rs1, rs2 = register(operands[0]), register(operands[1])
        target = labels[operands[2]]
        return encode_branch(target - pc, rs1, rs2, BRANCH_FUNCT3[operation])
    if operation in ("lbu", "lw", "sb", "sw"):
        first = register(operands[0])
        immediate_value, rs1 = parse_memory_operand(operands[1], labels)
        encoded_immediate = signed_bits(immediate_value, 12)
        if operation in ("lbu", "lw"):
            funct3 = 4 if operation == "lbu" else 2
            return (
                encoded_immediate << 20
                | rs1 << 15
                | funct3 << 12
                | first << 7
                | 0x03
            )
        funct3 = 0 if operation == "sb" else 2
        return (
            ((encoded_immediate >> 5) & 0x7F) << 25
            | first << 20
            | rs1 << 15
            | funct3 << 12
            | (encoded_immediate & 0x1F) << 7
            | 0x23
        )
    if operation == "jalr":
        rd = register(operands[0])
        immediate_value, rs1 = parse_memory_operand(operands[1], labels)
        encoded_immediate = signed_bits(immediate_value, 12)
        return encoded_immediate << 20 | rs1 << 15 | rd << 7 | 0x67
    if operation in CSR_FUNCT3:
        rd = register(operands[0])
        csr = CSR_ADDRESSES[operands[1]]
        rs1 = register(operands[2])
        return csr << 20 | rs1 << 15 | CSR_FUNCT3[operation] << 12 | rd << 7 | 0x73
    if operation in ("lr.w", "sc.w", "amoadd.w"):
        rd = register(operands[0])
        if operation == "lr.w":
            rs2 = 0
            rs1 = register(operands[1].strip("()"))
            atomic_function = 2
        else:
            rs2 = register(operands[1])
            rs1 = register(operands[2].strip("()"))
            atomic_function = 3 if operation == "sc.w" else 0
        return (
            atomic_function << 27
            | rs2 << 20
            | rs1 << 15
            | 2 << 12
            | rd << 7
            | 0x2F
        )
    raise ValueError(f"unsupported instruction {operation}")


def source_records(source: str) -> list[tuple[str, list[str], int, int]]:
    records: list[tuple[str, list[str], int]] = []
    address = 0
    labels: dict[str, int] = {}
    for raw_line in source.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line or line.startswith((".section", ".globl")):
            continue
        if line.endswith(":"):
            labels[line[:-1]] = address
            continue
        if line.startswith(".org"):
            address = integer(line.split(maxsplit=1)[1])
            continue
        address += 4

    address = 0
    for line_number, raw_line in enumerate(source.splitlines(), 1):
        line = raw_line.split("#", 1)[0].strip()
        if not line or line.endswith(":") or line.startswith((".section", ".globl")):
            continue
        if line.startswith(".org"):
            target = integer(line.split(maxsplit=1)[1])
            while address < target:
                records.append((".word", ["0"], address))
                address += 4
            if address != target:
                raise ValueError(f"line {line_number}: .org moves backward")
            continue
        operation, *tail = line.split(maxsplit=1)
        operands = [part.strip() for part in tail[0].split(",")] if tail else []
        records.append((operation, operands, address))
        address += 4

    words = []
    for operation, operands, pc in records:
        word = (
            integer(operands[0]) & 0xFFFFFFFF
            if operation == ".word"
            else encode_instruction(operation, operands, pc, labels)
        )
        words.append((operation, operands, pc, word))
    return words


def assemble(source: str) -> list[int]:
    return [word for _, _, _, word in source_records(source)]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()
    words = assemble(args.source.read_text(encoding="utf-8"))
    binary = b"".join(struct.pack("<I", word) for word in words)
    if args.output is None:
        for index, word in enumerate(words):
            print(f"    if (index == {index}u) return 0x{word:08x}u;")
    else:
        args.output.write_bytes(binary)


if __name__ == "__main__":
    main()
