"""Reference execution test for the bundled RV32IMA interrupt and trap self-test."""

from __future__ import annotations

import json
import hashlib
import re
import struct
from pathlib import Path

from PIL import Image

from assemble_demo import assemble
from bin_to_texture import BOOT_DESCRIPTOR_WORDS, BOOT_MAGIC, decode_guest_texture
from build_dtb import (
    FDT_BEGIN_NODE,
    FDT_END,
    FDT_END_NODE,
    FDT_MAGIC,
    FDT_PROP,
    build_dtb,
    platform_tree,
    render_dts,
)
from romfs import checksum, entry_name, header_name_end, root_entries


MASK32 = 0xFFFFFFFF
RAM_BYTES = 0x00BFF000
FRAMEBUFFER_ADDRESS = 0x1000
FRAMEBUFFER_WORDS = 32 * 18
UART_TX_BUFFER_ADDRESS = 0x1900
UART_TX_BUFFER_BYTES = 64
CSR_MSCRATCH = 0x340
CSR_MSTATUS = 0x300
CSR_MEDELEG = 0x302
CSR_MIDELEG = 0x303
CSR_MIE = 0x304
CSR_MTVEC = 0x305
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342
CSR_MTVAL = 0x343
CSR_MIP = 0x344
CSR_STVEC = 0x105
CSR_SSTATUS = 0x100
CSR_SIE = 0x104
CSR_SSCRATCH = 0x140
CSR_SEPC = 0x141
CSR_SCAUSE = 0x142
CSR_STVAL = 0x143
CSR_SIP = 0x144
CSR_SATP = 0x180

CLINT_MSIP = 0x02000000
CLINT_MTIMECMP_LOW = 0x02004000
CLINT_MTIMECMP_HIGH = 0x02004004
CLINT_MTIME_LOW = 0x0200BFF8
CLINT_MTIME_HIGH = 0x0200BFFC
MASK64 = 0xFFFFFFFFFFFFFFFF
UART_BASE = 0x10000000
PLIC_PRIORITY = 0x0C000028
PLIC_PENDING = 0x0C001000
PLIC_ENABLE = 0x0C002000
PLIC_SUPERVISOR_ENABLE = 0x0C002080
PLIC_THRESHOLD = 0x0C200000
PLIC_CLAIM_COMPLETE = 0x0C200004
PLIC_SUPERVISOR_THRESHOLD = 0x0C201000
PLIC_SUPERVISOR_CLAIM_COMPLETE = 0x0C201004
UART_INTERRUPT_SOURCE = 10

EXPECTED_PROGRAM = [
    0x01500193, 0x00600213, 0x024182B3, 0x02419333,
    0x0241A3B3, 0x0241B433, 0x0241C4B3, 0x0241D533,
    0x0241E5B3, 0x0241F633, 0x07E00693, 0x52D29863,
    0x52031663, 0x52039463, 0x52041263, 0x00300713,
    0x50E49E63, 0x50E51C63, 0x50E59A63, 0x50E61863,
    0x340297F3, 0x34002873, 0x50079263, 0x50581063,
    0x7FF00893, 0x00188893, 0x00700913, 0x0128A023,
    0x1008A9AF, 0x00900A13, 0x1948AAAF, 0x0008AB03,
    0x00700B93, 0x4D799C63, 0x4C0A9A63, 0x00900B93,
    0x4D7B1663, 0x0128AC2F, 0x0008AC83, 0x4D7C1063,
    0x01000B93, 0x4B7C9C63, 0x60000D13, 0x305D1073,
    0x00000D93, 0x00000073, 0x00100E13, 0x4BCD9063,
    0x34202EF3, 0x00B00F13, 0x49EE9A63, 0x00102003,
    0x00200E13, 0x49CD9463, 0x34202EF3, 0x00400F13,
    0x47EE9E63, 0x34302EF3, 0x00100F13, 0x47EE9863,
    0x00000D93, 0x0C0008B7, 0x02888893, 0x00100993,
    0x0138A023, 0x0C0028B7, 0x40000993, 0x0138A023,
    0x0C2008B7, 0x0008A023, 0x10000937, 0x00200993,
    0x013900A3, 0x00594A03, 0x06000A93, 0x435A1863,
    0x00001A37, 0x800A0A13, 0x304A2073, 0x00800A13,
    0x300A2073, 0x05500993, 0x01390023, 0x00000013,
    0x00000013, 0x00000013, 0x00000013, 0x00100E13,
    0x3FCD9E63, 0x34202EF3, 0x80000F37, 0x00BF0F13,
    0x3FEE9663, 0x000900A3, 0x04100993, 0x01390023,
    0x05200993, 0x01390023, 0x05400993, 0x01390023,
    0x02000993, 0x01390023, 0x04900993, 0x01390023,
    0x05200993, 0x01390023, 0x05100993, 0x01390023,
    0x02000993, 0x01390023, 0x04F00993, 0x01390023,
    0x04B00993, 0x01390023, 0x02000993, 0x01390023,
    0x00000D93, 0x020008B7, 0x00100993, 0x0138A023,
    0x0008AA03, 0x373A1C63, 0x0008A023, 0x020048B7,
    0x0200C937, 0xFF890913, 0x00092023, 0x00092223,
    0x0008A223, 0x00C00993, 0x0138A023, 0x08000A13,
    0x304A2073, 0x00800A13, 0x300A2073, 0x00000013,
    0x00000013, 0x00000013, 0x00000013, 0x00000013,
    0x00000013, 0x00000013, 0x00000013, 0x00100E13,
    0x31CD9E63, 0x34202EF3, 0x80000F37, 0x007F0F13,
    0x31EE9663, 0x0000A8B7, 0x0000B937, 0x000039B7,
    0xC0198993, 0x4138A023, 0x04B00993, 0x01392023,
    0x4C700993, 0x01392223, 0x05900993, 0x01392423,
    0x4D700993, 0x01392623, 0x030009B7, 0x0C798993,
    0x0D38A023, 0x040009B7, 0x0C798993, 0x1138A023,
    0x80000D37, 0x00AD0D13, 0x180D1073, 0x12000073,
    0x000018B7, 0x02A00A13, 0x0148A023, 0x40001AB7,
    0x00021D37, 0x800D0D13, 0x300D1073, 0x000AAB03,
    0x294B1663, 0x02B00B93, 0x017AA023, 0x30001073,
    0x0008AC03, 0x277C1C63, 0x40000D37, 0x668D0D13,
    0x105D1073, 0x0000BD37, 0x3F7D0D13, 0x302D1073,
    0x0C0028B7, 0x08088893, 0x40000993, 0xF808A023,
    0x0138A023, 0x0C2018B7, 0x0008A023, 0x10000937,
    0x00200993, 0x013900A3, 0x05300993, 0x01390023,
    0x22000A13, 0x303A1073, 0x304A2073, 0x40000D37,
    0x358D0D13, 0x341D1073, 0x00001D37, 0x802D0D13,
    0x300D1073, 0x30200073, 0x00300E13, 0x21CD9A63,
    0x14202EF3, 0x80000F37, 0x005F0F13, 0x21EE9263,
    0x00000D93, 0x00000073, 0x00100E13, 0x1FCD9A63,
    0x14202EF3, 0x00900F13, 0x1FEE9463, 0xFFFFFFFF,
    0x00200E13, 0x1DCD9E63, 0x14202EF3, 0x00200F13,
    0x1DEE9863, 0x14302EF3, 0xFFF00F13, 0x1DEE9263,
    0x00102003, 0x00300E13, 0x1BCD9C63, 0x14202EF3,
    0x00400F13, 0x1BEE9663, 0x14302EF3, 0x00100F13,
    0x1BEE9063, 0x00002123, 0x00400E13, 0x19CD9A63,
    0x14202EF3, 0x00600F13, 0x19EE9463, 0x14302EF3,
    0x00200F13, 0x17EE9E63, 0x50000D37, 0x000D2003,
    0x00500E13, 0x17CD9663, 0x14202EF3, 0x00D00F13,
    0x17EE9063, 0x14302EF3, 0x15AE9C63, 0x000D2023,
    0x00600E13, 0x15CD9663, 0x14202EF3, 0x00F00F13,
    0x15EE9063, 0x14302EF3, 0x13AE9C63, 0x00200D13,
    0x000D0067, 0x00700E13, 0x13CD9463, 0x14202EF3,
    0x00000F13, 0x11EE9E63, 0x14302EF3, 0x00200F13,
    0x11EE9863, 0x40000D37, 0x478D0D13, 0x140D1073,
    0x50000D37, 0x000D0067, 0x00800E13, 0x0FCD9A63,
    0x14202EF3, 0x00C00F13, 0x0FEE9463, 0x14302EF3,
    0x0FAE9063, 0x12000073, 0x40003D37, 0x000D2A03,
    0x00900E13, 0x0DCD9663, 0x14202EF3, 0x00D00F13,
    0x0DEE9063, 0x00040CB7, 0x100CA073, 0x000D2A03,
    0x0B7A1863, 0x40002D37, 0x50CD0D13, 0x000D2A03,
    0x00A00E13, 0x09CD9E63, 0x14202EF3, 0x00D00F13,
    0x09EE9863, 0x00080CB7, 0x100CA073, 0x000D2A03,
    0x07300B93, 0x077A1E63, 0x40002D37, 0x508D0D13,
    0x141D1073, 0x10200073, 0x00000D93, 0x00000073,
    0x00100E13, 0x07CD9863, 0x00800E13, 0x07CF1463,
    0x40000D37, 0x000D2003, 0x00200E13, 0x05CD9C63,
    0x00D00E13, 0x05CF1863, 0x400030B7, 0x00100113,
    0x40004337, 0x90030313, 0x0020A023, 0x00408093,
    0x00110113, 0xFE60EAE3, 0x00100073, 0x000010B7,
    0xDEADC137, 0xEEF10113, 0x0020A023, 0x00100073,
    0x400010B7, 0xDEADC137, 0xEEF10113, 0x0020A023,
    0x00100073, 0x400030B7, 0xDEADC137, 0xEEF10113,
    0x0020A023, 0x00100073, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x34202F73, 0x000F4C63, 0x001D8D93, 0x34102FF3,
    0x004F8F93, 0x341F9073, 0x30200073, 0x80000FB7,
    0x00BF8F93, 0x03FF1063, 0x001D8D93, 0x0C200FB7,
    0x004FAE83, 0x00A00E13, 0xF3CE92E3, 0x01DFA223,
    0x30200073, 0x001D8D93, 0x08000F93, 0x304FB073,
    0x02000F93, 0x344FA073, 0x30200073, 0x00000000,
    0x00000000, 0x00000000, 0x14202F73, 0x020F4663,
    0x001D8D93, 0x00C00F93, 0x01FF1863, 0x14002FF3,
    0x141F9073, 0x10200073, 0x14102FF3, 0x004F8F93,
    0x141F9073, 0x10200073, 0x80000FB7, 0x009F8F93,
    0x03FF1463, 0x001D8D93, 0x0C201FB7, 0x004FAE83,
    0x00A00E13, 0xEBCE9EE3, 0x01DFA223, 0x10000FB7,
    0x000F80A3, 0x10200073, 0x001D8D93, 0x02000F93,
    0x144FB073, 0x10200073,
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


def jump_immediate(instruction: int) -> int:
    value = (
        (((instruction >> 31) & 1) << 20)
        | (((instruction >> 12) & 0xFF) << 12)
        | (((instruction >> 20) & 1) << 11)
        | (((instruction >> 21) & 0x3FF) << 1)
    )
    return sign_extend(value, 21)


def run_fibonacci_elf(executable: bytes) -> tuple[bytes, int]:
    """Execute the bundled syscall-only RV32 user program."""
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", executable)
    assert header[0][:4] == b"\x7fELF"
    assert header[1:3] == (2, 243)
    entry_point = header[4]
    program_header_offset = header[5]
    program_header_size = header[9]
    program_header_count = header[10]
    memory = bytearray(0x20000)
    for index in range(program_header_count):
        offset = program_header_offset + index * program_header_size
        kind, file_offset, virtual_address, _, file_size, memory_size, _, _ = (
            struct.unpack_from("<8I", executable, offset)
        )
        if kind == 1:
            memory[virtual_address : virtual_address + file_size] = (
                executable[file_offset : file_offset + file_size]
            )
            memory[virtual_address + file_size : virtual_address + memory_size] = (
                bytes(memory_size - file_size)
            )

    registers = [0] * 32
    pc = entry_point
    output = bytearray()
    for _cycle in range(20_000):
        instruction = struct.unpack_from("<I", memory, pc)[0]
        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        funct7 = instruction >> 25
        next_pc = pc + 4
        if opcode == 0x17:
            registers[rd] = (pc + (instruction & 0xFFFFF000)) & MASK32
        elif opcode == 0x13 and funct3 == 0:
            immediate = sign_extend(instruction >> 20, 12)
            registers[rd] = (registers[rs1] + immediate) & MASK32
        elif opcode == 0x33 and funct7 == 0 and funct3 == 0:
            registers[rd] = (registers[rs1] + registers[rs2]) & MASK32
        elif opcode == 0x33 and funct7 == 1 and funct3 in (5, 7):
            registers[rd] = execute_rv32m(
                funct3, registers[rs1], registers[rs2]
            )
        elif opcode == 0x23 and funct3 == 0:
            immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
            address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
            memory[address] = registers[rs2] & 0xFF
        elif opcode == 0x63 and funct3 in (0, 1):
            equal = registers[rs1] == registers[rs2]
            if equal == (funct3 == 0):
                next_pc = (pc + branch_immediate(instruction)) & MASK32
        elif opcode == 0x6F:
            registers[rd] = next_pc
            next_pc = (pc + jump_immediate(instruction)) & MASK32
        elif opcode == 0x67 and funct3 == 0:
            immediate = sign_extend(instruction >> 20, 12)
            target = (registers[rs1] + immediate) & ~1
            registers[rd] = next_pc
            next_pc = target
        elif opcode == 0x73 and instruction == 0x00000073:
            syscall = registers[17]
            if syscall == 64:
                assert registers[10] == 1
                address = registers[11]
                length = registers[12]
                output.extend(memory[address : address + length])
                registers[10] = length
            elif syscall == 93:
                return bytes(output), registers[10]
            else:
                raise AssertionError(f"unexpected syscall {syscall}")
        else:
            raise AssertionError(f"unexpected Fibonacci instruction {instruction:08x}")
        registers[0] = 0
        pc = next_pc
    raise AssertionError("Fibonacci program exceeded its reference cycle budget")


def verify_fibonacci_elf(executable: bytes) -> None:
    output, status = run_fibonacci_elf(executable)
    values: list[int] = []
    left, right = 0, 1
    for _ in range(48):
        values.append(left)
        left, right = right, left + right
    expected = b"FIBONACCI USER PROGRAM" + b" " * 9 + b"\n"
    expected += b"".join(
        f"F{index:02d} = {value:010d}".encode("ascii") + b" " * 15 + b"\n"
        for index, value in enumerate(values)
    )
    assert status == 0
    assert output == expected


def translate_address(
    memory: bytearray,
    csrs: dict[int, int],
    virtual_address: int,
    access_type: int,
    privilege: int,
) -> int | None:
    satp = csrs[CSR_SATP]
    if privilege == 3 or satp >> 31 == 0:
        return virtual_address

    table_address = (satp & 0x003FFFFF) << 12
    vpn = ((virtual_address >> 12) & 0x3FF, (virtual_address >> 22) & 0x3FF)
    page_offset = virtual_address & 0xFFF

    for level in (1, 0):
        pte_address = table_address + vpn[level] * 4
        if pte_address > RAM_BYTES - 4:
            return None
        pte = struct.unpack_from("<I", memory, pte_address)[0]
        valid = bool(pte & 0x01)
        readable = bool(pte & 0x02)
        writable = bool(pte & 0x04)
        executable = bool(pte & 0x08)
        if not valid or (writable and not readable):
            return None
        if readable or executable:
            break
        table_address = (pte >> 10) << 12
    else:
        return None

    user_page = bool(pte & 0x10)
    accessed = bool(pte & 0x40)
    dirty = bool(pte & 0x80)
    mxr = bool(csrs[CSR_MSTATUS] & (1 << 19))
    sum_access = bool(csrs[CSR_MSTATUS] & (1 << 18))
    privilege_allowed = (
        user_page
        if privilege == 0
        else (not user_page if access_type == 0 else not user_page or sum_access)
    )
    access_allowed = (
        executable
        if access_type == 0
        else readable or (mxr and executable)
        if access_type == 1
        else writable
    )
    if not privilege_allowed or not access_allowed or not accessed:
        return None
    if access_type == 2 and not dirty:
        return None

    physical_page_number = pte >> 10
    if level == 1:
        if physical_page_number & 0x3FF:
            return None
        return (
            ((physical_page_number & ~0x3FF) << 12)
            | (vpn[0] << 12)
            | page_offset
        ) & MASK32
    return ((physical_page_number << 12) | page_offset) & MASK32


def verify_sv32_translation() -> None:
    memory = bytearray(RAM_BYTES)
    csrs = {CSR_SATP: 0x8000000A, CSR_MSTATUS: 0}
    struct.pack_into("<I", memory, 0xA400, 0x2C01)
    struct.pack_into("<I", memory, 0xA800, 0xC7)
    struct.pack_into("<I", memory, 0xB000, 0x4B)
    struct.pack_into("<I", memory, 0xB004, 0x4D7)
    struct.pack_into("<I", memory, 0xB008, 0x859)

    assert translate_address(memory, csrs, 0x40000020, 0, 1) == 0x20
    assert translate_address(memory, csrs, 0x40000020, 1, 1) == 0x20
    assert translate_address(memory, csrs, 0x40001020, 1, 1) is None
    csrs[CSR_MSTATUS] |= 1 << 18
    assert translate_address(memory, csrs, 0x40001020, 1, 1) == 0x1020
    assert translate_address(memory, csrs, 0x40001020, 2, 0) == 0x1020
    assert translate_address(memory, csrs, 0x40000020, 0, 0) is None
    assert translate_address(memory, csrs, 0x40002020, 1, 0) is None
    csrs[CSR_MSTATUS] |= 1 << 19
    assert translate_address(memory, csrs, 0x40002020, 1, 0) == 0x2020
    assert translate_address(memory, csrs, 0x80003004, 1, 1) == 0x3004


def plic_interrupt_eligible(
    uart: dict[str, int], plic: dict[str, int], supervisor: bool = False
) -> bool:
    context = "supervisor" if supervisor else "machine"
    return (
        bool(uart["pending"])
        and plic[f"{context}_claimed"] == 0
        and bool(plic[f"{context}_enable"] & (1 << UART_INTERRUPT_SOURCE))
        and plic["priority"] > plic[f"{context}_threshold"]
    )


def read_pending_interrupts(
    csrs: dict[int, int],
    clint: dict[str, int],
    uart: dict[str, int],
    plic: dict[str, int],
) -> int:
    pending = csrs[CSR_MIP] & ~0xA88
    if clint["msip"]:
        pending |= 1 << 3
    if clint["mtime"] >= clint["mtimecmp"]:
        pending |= 1 << 7
    if plic_interrupt_eligible(uart, plic):
        pending |= 1 << 11
    if plic_interrupt_eligible(uart, plic, supervisor=True):
        pending |= 1 << 9
    return pending & MASK32


def write_mtimecmp(
    csrs: dict[int, int], clint: dict[str, int], address: int, value: int
) -> None:
    if address == CLINT_MTIMECMP_LOW:
        clint["mtimecmp"] = (clint["mtimecmp"] & 0xFFFFFFFF00000000) | value
    else:
        clint["mtimecmp"] = (clint["mtimecmp"] & MASK32) | (value << 32)
    csrs[CSR_MIP] &= ~0xA0


def select_interrupt_cause(pending: int) -> int | None:
    for cause in (11, 3, 7, 9, 1, 5):
        if pending & (1 << cause):
            return cause
    return None


def verify_interrupt_logic() -> None:
    csrs = {CSR_MIP: 1 << 5}
    clint = {"msip": 1, "mtimecmp": 9, "mtime": 9}
    uart = {"ier": 2, "lcr": 0, "tx_head": 0, "pending": 1}
    plic = {
        "priority": 1,
        "machine_enable": 1 << 10,
        "machine_threshold": 0,
        "machine_claimed": 0,
        "supervisor_enable": 0,
        "supervisor_threshold": 0,
        "supervisor_claimed": 0,
    }
    pending = read_pending_interrupts(csrs, clint, uart, plic)
    assert pending == (1 << 3) | (1 << 5) | (1 << 7) | (1 << 11)
    assert select_interrupt_cause(pending) == 11
    plic["machine_enable"] = 0
    plic["supervisor_enable"] = 1 << UART_INTERRUPT_SOURCE
    pending = read_pending_interrupts(csrs, clint, uart, plic)
    assert pending == (1 << 3) | (1 << 5) | (1 << 7) | (1 << 9)
    assert select_interrupt_cause((1 << 7) | (1 << 11)) == 11
    assert select_interrupt_cause(0) is None
    csrs[CSR_MIP] = 0xA8
    write_mtimecmp(csrs, clint, CLINT_MTIMECMP_LOW, 20)
    assert csrs[CSR_MIP] == 0x08
    assert read_pending_interrupts(csrs, clint, uart, plic) & 0xA0 == 0


def physical_access_valid(address: int, width: int) -> bool:
    if 0 < width <= RAM_BYTES and address <= RAM_BYTES - width:
        return True
    if width == 4 and address in {
        CLINT_MSIP,
        CLINT_MTIMECMP_LOW,
        CLINT_MTIMECMP_HIGH,
        CLINT_MTIME_LOW,
        CLINT_MTIME_HIGH,
        PLIC_PRIORITY,
        PLIC_PENDING,
        PLIC_ENABLE,
        PLIC_SUPERVISOR_ENABLE,
        PLIC_THRESHOLD,
        PLIC_CLAIM_COMPLETE,
        PLIC_SUPERVISOR_THRESHOLD,
        PLIC_SUPERVISOR_CLAIM_COMPLETE,
    }:
        return True
    return UART_BASE <= address and address - UART_BASE <= 8 - width


def read_physical_word(
    memory: bytearray,
    clint: dict[str, int],
    uart: dict[str, int],
    plic: dict[str, int],
    address: int,
) -> int:
    if address == CLINT_MSIP:
        return clint["msip"]
    if address == CLINT_MTIMECMP_LOW:
        return clint["mtimecmp"] & MASK32
    if address == CLINT_MTIMECMP_HIGH:
        return clint["mtimecmp"] >> 32
    if address == CLINT_MTIME_LOW:
        return clint["mtime"] & MASK32
    if address == CLINT_MTIME_HIGH:
        return clint["mtime"] >> 32
    if UART_BASE <= address < UART_BASE + 8:
        offset = address - UART_BASE
        divisor_latch = bool(uart["lcr"] & 0x80)
        value = 0
        if offset == 1 and not divisor_latch:
            value = uart["ier"] & 0x0F
        elif offset == 2:
            value = 0x02 if uart["pending"] and uart["ier"] & 2 else 0x01
        elif offset == 3:
            value = uart["lcr"] & 0xFF
        elif offset == 5:
            value = 0x60
        return value << ((address & 3) * 8)
    if address == PLIC_PRIORITY:
        return plic["priority"]
    if address == PLIC_PENDING:
        return (1 << UART_INTERRUPT_SOURCE) if uart["pending"] else 0
    if address == PLIC_ENABLE:
        return plic["machine_enable"]
    if address == PLIC_SUPERVISOR_ENABLE:
        return plic["supervisor_enable"]
    if address == PLIC_THRESHOLD:
        return plic["machine_threshold"]
    if address == PLIC_SUPERVISOR_THRESHOLD:
        return plic["supervisor_threshold"]
    if address == PLIC_CLAIM_COMPLETE:
        return UART_INTERRUPT_SOURCE if plic_interrupt_eligible(uart, plic) else 0
    if address == PLIC_SUPERVISOR_CLAIM_COMPLETE:
        return UART_INTERRUPT_SOURCE if plic_interrupt_eligible(uart, plic, supervisor=True) else 0
    return struct.unpack_from("<I", memory, address & ~3)[0]


def run_demo(
    program: list[int],
) -> tuple[
    list[int], bytearray, dict[int, int], dict[str, int], dict[str, int],
    dict[str, int], int, int, int, int,
]:
    registers = [0] * 32
    memory = bytearray(RAM_BYTES)
    csrs: dict[int, int] = {
        CSR_MSTATUS: 0,
        CSR_MEDELEG: 0,
        CSR_MIDELEG: 0,
        CSR_MIE: 0,
        CSR_MTVEC: 0,
        CSR_MSCRATCH: 0,
        CSR_MEPC: 0,
        CSR_MCAUSE: 0,
        CSR_MTVAL: 0,
        CSR_MIP: 0,
        CSR_STVEC: 0,
        CSR_SSCRATCH: 0,
        CSR_SEPC: 0,
        CSR_SCAUSE: 0,
        CSR_STVAL: 0,
        CSR_SATP: 0,
    }
    clint = {"msip": 0, "mtimecmp": MASK64, "mtime": 0}
    uart = {"ier": 0, "lcr": 0, "tx_head": 0, "pending": 0}
    plic = {
        "priority": 1,
        "machine_enable": 0,
        "machine_threshold": 0,
        "machine_claimed": 0,
        "supervisor_enable": 0,
        "supervisor_threshold": 0,
        "supervisor_claimed": 0,
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
        trap_interrupt = False
        mtime_write: tuple[int, int] | None = None
        instruction = 0
        data_privilege = privilege
        if privilege == 3 and csrs[CSR_MSTATUS] & (1 << 17):
            machine_previous_privilege = (csrs[CSR_MSTATUS] >> 11) & 3
            data_privilege = (
                machine_previous_privilege
                if machine_previous_privilege in (0, 1, 3)
                else 0
            )

        enabled_pending = read_pending_interrupts(csrs, clint, uart, plic) & csrs[CSR_MIE]
        delegated_pending = enabled_pending & csrs[CSR_MIDELEG]
        machine_pending = enabled_pending & ~csrs[CSR_MIDELEG]
        machine_enabled = privilege < 3 or (
            privilege == 3 and bool(csrs[CSR_MSTATUS] & (1 << 3))
        )
        supervisor_enabled = privilege < 1 or (
            privilege == 1 and bool(csrs[CSR_MSTATUS] & (1 << 1))
        )
        interrupt_cause = (
            select_interrupt_cause(machine_pending) if machine_enabled else None
        )
        if interrupt_cause is None and privilege != 3 and supervisor_enabled:
            interrupt_cause = select_interrupt_cause(delegated_pending)
        if interrupt_cause is not None:
            trap = (interrupt_cause, 0)
            trap_interrupt = True

        if trap is None:
            if pc & 3:
                trap = (0, pc)
            else:
                instruction_address = translate_address(memory, csrs, pc, 0, privilege)
                if instruction_address is None:
                    trap = (12, pc)
                    instruction_address = 0
                elif instruction_address > RAM_BYTES - 4:
                    trap = (1, pc)
                    instruction_address = 0
                instruction = (
                    struct.unpack_from("<I", memory, instruction_address)[0]
                    if trap is None
                    else 0
                )

        if trap is None:
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
            elif opcode == 0x23:
                immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
                address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
                width = {0: 1, 1: 2, 2: 4}.get(funct3, 0)
                aligned = width == 1 or width == 2 and address & 1 == 0 or width == 4 and address & 3 == 0
                if width == 0:
                    trap = (2, instruction)
                elif not aligned:
                    trap = (6, address)
                else:
                    physical_address = translate_address(memory, csrs, address, 2, data_privilege)
                    if physical_address is None:
                        trap = (15, address)
                    elif not physical_access_valid(physical_address, width):
                        trap = (7, address)
                    elif physical_address <= RAM_BYTES - width:
                        memory[physical_address : physical_address + width] = registers[rs2].to_bytes(4, "little")[:width]
                        reservation = None
                    elif physical_address == CLINT_MSIP:
                        clint["msip"] = registers[rs2] & 1
                    elif physical_address == CLINT_MTIMECMP_LOW:
                        write_mtimecmp(
                            csrs, clint, physical_address, registers[rs2]
                        )
                    elif physical_address == CLINT_MTIMECMP_HIGH:
                        write_mtimecmp(
                            csrs, clint, physical_address, registers[rs2]
                        )
                    elif physical_address in (CLINT_MTIME_LOW, CLINT_MTIME_HIGH):
                        mtime_write = (physical_address, registers[rs2])
                    elif UART_BASE <= physical_address < UART_BASE + 8:
                        offset = physical_address - UART_BASE
                        divisor_latch = bool(uart["lcr"] & 0x80)
                        value = registers[rs2] & 0xFF
                        if offset == 0 and not divisor_latch:
                            buffer_address = UART_TX_BUFFER_ADDRESS + uart["tx_head"] % UART_TX_BUFFER_BYTES
                            memory[buffer_address] = value
                            uart["tx_head"] = (uart["tx_head"] + 1) & MASK32
                            if uart["ier"] & 2:
                                uart["pending"] = 1
                        elif offset == 1 and not divisor_latch:
                            uart["ier"] = value & 0x0F
                        elif offset == 3:
                            uart["lcr"] = value
                    elif physical_address == PLIC_PRIORITY:
                        plic["priority"] = registers[rs2]
                    elif physical_address == PLIC_ENABLE:
                        plic["machine_enable"] = registers[rs2]
                    elif physical_address == PLIC_SUPERVISOR_ENABLE:
                        plic["supervisor_enable"] = registers[rs2]
                    elif physical_address == PLIC_THRESHOLD:
                        plic["machine_threshold"] = registers[rs2]
                    elif physical_address == PLIC_SUPERVISOR_THRESHOLD:
                        plic["supervisor_threshold"] = registers[rs2]
                    elif physical_address == PLIC_CLAIM_COMPLETE:
                        if registers[rs2] == plic["machine_claimed"]:
                            plic["machine_claimed"] = 0
                    elif physical_address == PLIC_SUPERVISOR_CLAIM_COMPLETE:
                        if registers[rs2] == plic["supervisor_claimed"]:
                            plic["supervisor_claimed"] = 0
            elif opcode == 0x03:
                immediate = sign_extend(instruction >> 20, 12)
                address = (registers[rs1] + immediate) & MASK32
                width = {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}.get(funct3, 0)
                aligned = width == 1 or width == 2 and address & 1 == 0 or width == 4 and address & 3 == 0
                if width == 0:
                    trap = (2, instruction)
                elif not aligned:
                    trap = (4, address)
                else:
                    physical_address = translate_address(memory, csrs, address, 1, data_privilege)
                    if physical_address is None:
                        trap = (13, address)
                    elif not physical_access_valid(physical_address, width):
                        trap = (5, address)
                    else:
                        word = read_physical_word(memory, clint, uart, plic, physical_address)
                        shift = (physical_address & 3) * 8
                        loaded = word >> shift & ((1 << (width * 8)) - 1)
                        if funct3 in (0, 1):
                            loaded = sign_extend(loaded, width * 8) & MASK32
                        registers[rd] = loaded
                        if physical_address == PLIC_CLAIM_COMPLETE and loaded == UART_INTERRUPT_SOURCE:
                            uart["pending"] = 0
                            plic["machine_claimed"] = UART_INTERRUPT_SOURCE
                        elif physical_address == PLIC_SUPERVISOR_CLAIM_COMPLETE and loaded == UART_INTERRUPT_SOURCE:
                            uart["pending"] = 0
                            plic["supervisor_claimed"] = UART_INTERRUPT_SOURCE
            elif opcode == 0x2F and funct3 == 2:
                address = registers[rs1]
                atomic_function = instruction >> 27
                load_reservation = atomic_function == 2 and rs2 == 0
                access_type = 1 if load_reservation else 2
                if address & 3:
                    trap = (4 if load_reservation else 6, address)
                else:
                    physical_address = translate_address(
                        memory, csrs, address, access_type, data_privilege
                    )
                    if physical_address is None:
                        trap = (13 if load_reservation else 15, address)
                    elif physical_address > RAM_BYTES - 4:
                        trap = (5 if load_reservation else 7, address)
                    else:
                        old_value = struct.unpack_from("<I", memory, physical_address)[0]
                        if load_reservation:
                            registers[rd] = old_value
                            reservation = physical_address
                        elif atomic_function == 3:
                            success = reservation == physical_address
                            registers[rd] = 0 if success else 1
                            if success:
                                struct.pack_into(
                                    "<I", memory, physical_address, registers[rs2]
                                )
                            reservation = None
                        elif atomic_function == 0:
                            registers[rd] = old_value
                            struct.pack_into(
                                "<I",
                                memory,
                                physical_address,
                                (old_value + registers[rs2]) & MASK32,
                            )
                            reservation = None
                        else:
                            trap = (2, instruction)
            elif opcode == 0x63:
                left = registers[rs1]
                right = registers[rs2]
                take = funct3 == 0 and left == right
                take |= funct3 == 1 and left != right
                take |= funct3 == 4 and signed(left) < signed(right)
                take |= funct3 == 5 and signed(left) >= signed(right)
                take |= funct3 == 6 and left < right
                take |= funct3 == 7 and left >= right
                if take:
                    target = (pc + branch_immediate(instruction)) & MASK32
                    if target & 3:
                        trap = (0, target)
                    else:
                        next_pc = target
            elif opcode == 0x73 and funct3 in (1, 2, 3):
                address = instruction >> 20
                state_address = (
                    CSR_MSTATUS
                    if address == CSR_SSTATUS
                    else CSR_MIE
                    if address == CSR_SIE
                    else CSR_MIP
                    if address == CSR_SIP
                    else address
                )
                required_privilege = (address >> 8) & 3
                if state_address not in csrs or privilege < required_privilege:
                    trap = (2, instruction)
                else:
                    read_mask = (
                        0x000DE162
                        if address == CSR_SSTATUS
                        else 0x222
                        if address in (CSR_SIE, CSR_SIP)
                        else MASK32
                    )
                    write_mask = (
                        0x000DE162
                        if address == CSR_SSTATUS
                        else 0x222
                        if address == CSR_SIE
                        else 0x22
                        if address in (CSR_SIP, CSR_MIP)
                        else MASK32
                    )
                    raw_value = (
                        read_pending_interrupts(csrs, clint, uart, plic)
                        if state_address == CSR_MIP
                        else csrs[state_address]
                    )
                    old_value = raw_value & read_mask
                    operand = registers[rs1]
                    if funct3 == 1 or operand != 0:
                        requested_value = (
                            operand
                            if funct3 == 1
                            else old_value | operand
                            if funct3 == 2
                            else old_value & ~operand
                        )
                        csrs[state_address] = (
                            (csrs[state_address] & ~write_mask)
                            | (requested_value & write_mask)
                        )
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
                if previous_privilege != 3:
                    csrs[CSR_MSTATUS] &= ~(1 << 17)
                privilege = previous_privilege
                next_pc = csrs[CSR_MEPC]
            elif instruction == 0x10200073 and privilege >= 1:
                previous_interrupt_enable = (csrs[CSR_MSTATUS] >> 5) & 1
                previous_privilege = (csrs[CSR_MSTATUS] >> 8) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x20122)
                    | (previous_interrupt_enable << 1)
                    | (1 << 5)
                )
                privilege = previous_privilege
                next_pc = csrs[CSR_SEPC]
            elif instruction == 0x00100073:
                next_pc = pc
                status = 1
            elif instruction & 0xFE007FFF == 0x12000073 and privilege >= 1:
                pass
            else:
                trap = (2, instruction)

        if trap is not None:
            cause, trap_value = trap
            delegation = csrs[CSR_MIDELEG] if trap_interrupt else csrs[CSR_MEDELEG]
            delegated = privilege != 3 and (delegation >> cause) & 1
            encoded_cause = cause | (0x80000000 if trap_interrupt else 0)
            if delegated:
                supervisor_interrupt_enable = (csrs[CSR_MSTATUS] >> 1) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x122)
                    | (supervisor_interrupt_enable << 5)
                    | ((privilege & 1) << 8)
                )
                csrs[CSR_SEPC] = pc
                csrs[CSR_SCAUSE] = encoded_cause
                csrs[CSR_STVAL] = trap_value
                privilege = 1
                trap_vector = csrs[CSR_STVEC]
                next_pc = (trap_vector & ~3) + (
                    cause * 4 if trap_interrupt and trap_vector & 3 == 1 else 0
                )
            else:
                machine_interrupt_enable = (csrs[CSR_MSTATUS] >> 3) & 1
                csrs[CSR_MSTATUS] = (
                    (csrs[CSR_MSTATUS] & ~0x1888)
                    | (machine_interrupt_enable << 7)
                    | (privilege << 11)
                )
                csrs[CSR_MEPC] = pc
                csrs[CSR_MCAUSE] = encoded_cause
                csrs[CSR_MTVAL] = trap_value
                privilege = 3
                trap_vector = csrs[CSR_MTVEC]
                next_pc = (trap_vector & ~3) + (
                    cause * 4 if trap_interrupt and trap_vector & 3 == 1 else 0
                )

        next_time = (clint["mtime"] + 1) & MASK64
        if mtime_write is not None:
            address, value = mtime_write
            if address == CLINT_MTIME_LOW:
                next_time = (next_time & 0xFFFFFFFF00000000) | value
            else:
                next_time = (next_time & MASK32) | (value << 32)
        clint["mtime"] = next_time
        registers[0] = 0
        pc = next_pc
        cycle += 1
    return registers, memory, csrs, clint, uart, plic, pc, cycle, status, privilege


def run_boot_probe(program: list[int], load_address: int, entry_point: int,
                   dtb_address: int, dtb: bytes) -> tuple[bytes, int, int]:
    registers = [0] * 32
    registers[11] = dtb_address
    pc = entry_point
    uart = bytearray()
    status = 0
    cycles = 0
    while status == 0 and cycles < 100:
        offset = pc - load_address
        assert offset >= 0 and offset % 4 == 0
        instruction = program[offset // 4]
        next_pc = (pc + 4) & MASK32
        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        if opcode == 0x37:
            registers[rd] = instruction & 0xFFFFF000
        elif opcode == 0x13 and funct3 == 0:
            registers[rd] = (registers[rs1] + sign_extend(instruction >> 20, 12)) & MASK32
        elif opcode == 0x03 and funct3 == 4:
            address = (registers[rs1] + sign_extend(instruction >> 20, 12)) & MASK32
            assert dtb_address <= address < dtb_address + len(dtb)
            registers[rd] = dtb[address - dtb_address]
        elif opcode == 0x63 and funct3 == 1:
            if registers[rs1] != registers[rs2]:
                next_pc = (pc + branch_immediate(instruction)) & MASK32
        elif opcode == 0x23 and funct3 == 0:
            immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
            address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
            assert address == UART_BASE
            uart.append(registers[rs2] & 0xFF)
        elif instruction == 0x00100073:
            next_pc = pc
            status = 1
        else:
            raise AssertionError(f"boot probe instruction {instruction:#010x}")
        registers[0] = 0
        pc = next_pc
        cycles += 1
    return bytes(uart), pc, status


def parse_dtb_properties(dtb: bytes) -> dict[str, dict[str, bytes]]:
    header = struct.unpack_from(">10I", dtb)
    magic, total_size, structure_offset, strings_offset = header[:4]
    strings_size, structure_size = header[8:10]
    assert magic == FDT_MAGIC
    assert total_size == len(dtb)
    assert strings_offset + strings_size == total_size
    assert structure_offset + structure_size == strings_offset

    strings = dtb[strings_offset : strings_offset + strings_size]
    offset = structure_offset
    stack: list[str] = []
    properties: dict[str, dict[str, bytes]] = {}
    while offset < strings_offset:
        token = struct.unpack_from(">I", dtb, offset)[0]
        offset += 4
        if token == FDT_BEGIN_NODE:
            end = dtb.index(0, offset)
            name = dtb[offset:end].decode("ascii")
            offset = (end + 4) & ~3
            stack.append(name)
            path = "/" + "/".join(part for part in stack if part)
            properties[path] = {}
        elif token == FDT_PROP:
            length, name_offset = struct.unpack_from(">II", dtb, offset)
            offset += 8
            data = dtb[offset : offset + length]
            offset = (offset + length + 3) & ~3
            name_end = strings.index(0, name_offset)
            name = strings[name_offset:name_end].decode("ascii")
            path = "/" + "/".join(part for part in stack if part)
            properties[path][name] = data
        elif token == FDT_END_NODE:
            stack.pop()
        elif token == FDT_END:
            assert stack == []
            break
        else:
            raise AssertionError(f"FDT token {token}")
    return properties


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    step_shader = (
        project_root / "assets" / "mcrv" / "shaders" / "post" / "rv32_step.fsh"
    ).read_text(encoding="utf-8")
    display_shader = (
        project_root / "assets" / "mcrv" / "shaders" / "post" / "rv32_display.fsh"
    ).read_text(encoding="utf-8")
    input_capture_shader = (
        project_root / "assets" / "mcrv" / "shaders" / "post"
        / "rv32_input_capture.fsh"
    ).read_text(encoding="utf-8")
    assert "const uint UART_TX_BUFFER_OFFSET = RAM_BYTES;" in step_shader
    assert "const uint UART_TX_BUFFER_BYTES = 1024u;" in step_shader
    assert "const uint UART_LINE_LENGTH_BASE = 4871u;" in step_shader
    assert "const uint UART_RX_READY_INDEX = 4906u;" in step_shader
    assert "const uint RAM_PAGE_INDEX = 4907u;" in step_shader
    assert "value = uartReceiveInterruptPending() ? 0x04u" in step_shader
    assert "inputMarker != readStateWord(INPUT_MARKER_INDEX)" in step_shader
    assert "(inputEvent == 5u || inputEvent == 7u)" in step_shader
    assert "(readStateWord(RAM_PAGE_INDEX) + 1u) % 24u" in step_shader
    assert "if (dtbAddressValid(address, width)) return true;" in step_shader
    assert "const uint LINUX_TIMER_DIVIDER = 40u;" in step_shader
    assert "outputWord = readStateWord(csrStateIndex(CSR_MIP)) & ~0x000000a0u;" in step_shader
    assert "const uint UART_TX_BUFFER_OFFSET = RAM_WORDS * 4u;" in display_shader
    assert "const uint UART_TX_BUFFER_BYTES = 1024u;" in display_shader
    assert "const uint UART_TERMINAL_BYTES = 448u;" in display_shader
    assert "const uint KEYBOARD_SELECTION_INDEX = 4904u;" in display_shader
    assert "const uint RAM_PAGE_INDEX = 4907u;" in display_shader
    assert "const uint RAM_PAGE_COUNT = 24u;" in display_shader
    assert "const uint RAM_PAGE_WORDS = 131072u;" in display_shader
    assert "const uint RAM_SAMPLE_WORD_STRIDE = 1024u;" in display_shader
    assert "for (int sampleIndex = 0; sampleIndex < 256; ++sampleIndex)" in input_capture_shader

    keyboard_bytes = [
        *b"1234567890",
        *b"qwertyuiop",
        *b"asdfghjkl/",
        *b"zxcvbnm.-_",
        32, 127, 13, 3, *b"=:;'?\\",
    ]
    step_keyboard_match = re.search(
        r"const uint keys\[50\] = uint\[50\]\((.*?)\);",
        step_shader,
        re.DOTALL,
    )
    assert step_keyboard_match is not None
    step_keyboard = [
        int(value)
        for value in re.findall(r"(\d+)u", step_keyboard_match.group(1))
    ]
    assert step_keyboard == keyboard_bytes
    display_keyboard_match = re.search(
        r"const int keys\[50\] = int\[50\]\((.*?)\);",
        display_shader,
        re.DOTALL,
    )
    assert display_keyboard_match is not None
    display_keyboard = [
        int(value) for value in re.findall(r"\d+", display_keyboard_match.group(1))
    ]
    assert display_keyboard[:40] == [
        ord(character.upper()) if character.isalpha() else ord(character)
        for character in bytes(keyboard_bytes[:40]).decode("ascii")
    ]
    assert display_keyboard[40:] == [95, 60, 69, 67, 61, 58, 59, 39, 63, 92]

    input_font_path = (
        project_root / "assets" / "mcrv" / "textures" / "font" / "input.png"
    )
    with Image.open(input_font_path) as input_font:
        assert input_font.size == (1024, 64)
        for marker_code in range(16):
            assert input_font.getpixel((marker_code * 64 + 32, 32)) == (
                250, 16 + marker_code * 14, 246, 255
            )
    input_font_definition = json.loads(
        (project_root / "assets" / "mcrv" / "font" / "input.json").read_text(
            encoding="utf-8"
        )
    )
    assert input_font_definition["providers"][0]["chars"] == [
        "".join(chr(0xE000 + index) for index in range(16))
    ]

    datapack_root = project_root / "datapack" / "MCRVInput"
    datapack_meta = json.loads((datapack_root / "pack.mcmeta").read_text("utf-8"))
    assert datapack_meta["pack"]["min_format"] == [112, 0]
    datapack_load = (
        datapack_root / "data" / "mcrv" / "function" / "input" / "load.mcfunction"
    ).read_text("utf-8")
    datapack_poll = (
        datapack_root / "data" / "mcrv" / "function" / "input" / "poll.mcfunction"
    ).read_text("utf-8")
    datapack_init = (
        datapack_root / "data" / "mcrv" / "function" / "input" / "init.mcfunction"
    ).read_text("utf-8")
    datapack_emit = (
        datapack_root / "data" / "mcrv" / "function" / "input" / "emit.mcfunction"
    ).read_text("utf-8")
    datapack_tick = (
        datapack_root / "data" / "mcrv" / "function" / "input" / "tick.mcfunction"
    ).read_text("utf-8")
    assert "scoreboard objectives add mcrv_hold dummy" in datapack_load
    assert "scoreboard objectives add mcrv_owner dummy" in datapack_load
    assert "kill @e[type=minecraft:text_display,tag=mcrv_input_marker]" in datapack_load
    assert "title @a clear" in datapack_load
    assert "if score @s mcrv_hold matches 10.. run function mcrv:input/emit" in datapack_poll
    assert "run scoreboard players set @s mcrv_hold 7" in datapack_poll
    assert "execute positioned ^ ^ ^0.4 as @e" in datapack_poll
    assert "run tp @s ~ ~ ~" in datapack_poll
    assert "summon minecraft:text_display ^ ^ ^0.4" in datapack_init
    assert 'billboard:"center"' in datapack_init
    assert "scale:[0.05f,0.05f,0.05f]" in datapack_init
    assert "run data merge entity @s {text:" in datapack_emit
    assert " run title " not in datapack_emit
    assert "at @s anchored eyes run function mcrv:input/poll" in datapack_tick
    for direction, field in {
        "up": "forward",
        "down": "backward",
        "left": "left",
        "right": "right",
        "confirm": "jump",
        "page": "sneak",
        "cancel": "sprint",
    }.items():
        predicate = json.loads(
            (datapack_root / "data" / "mcrv" / "predicate" / "input"
             / f"{direction}.json").read_text("utf-8")
        )
        assert predicate["type"] == "minecraft:entity_properties"
        player_input = predicate["predicate"]["minecraft:type_specific/player"]["input"]
        assert player_input == {field: True}

    texture_path = (
        project_root / "assets" / "mcrv" / "textures" / "effect" / "guest_demo.png"
    )
    width, height, texture_bytes = decode_guest_texture(texture_path.read_bytes())
    assert (width, height) == (2048, 1024)
    program = list(struct.unpack_from(f"<{len(EXPECTED_PROGRAM)}I", texture_bytes))
    assert program == EXPECTED_PROGRAM
    descriptor_offset = len(texture_bytes) - BOOT_DESCRIPTOR_WORDS * 4
    assert texture_bytes[len(program) * 4 : descriptor_offset] == bytes(
        descriptor_offset - len(program) * 4
    )
    assert struct.unpack_from("<4I", texture_bytes, descriptor_offset) == (
        0, 0, 0, BOOT_MAGIC
    )

    post_effect_path = project_root / "assets" / "mcrv" / "post_effect" / "rv32i.json"
    post_effect = json.loads(post_effect_path.read_text(encoding="utf-8"))
    step_passes = [
        entry for entry in post_effect["passes"]
        if entry["fragment_shader"] == "mcrv:post/rv32_step"
    ]
    assert len(step_passes) == 2
    assert post_effect["targets"]["ram_a"] == {
        "width": 4096,
        "height": 768,
        "persistent": True,
        "clear_color": [0.0, 0.0, 0.0, 0.0],
    }
    assert post_effect["targets"]["ram_b"] == post_effect["targets"]["ram_a"]
    assert post_effect["targets"]["input"] == {
        "width": 1,
        "height": 1,
        "persistent": False,
        "clear_color": [0.0, 0.0, 0.0, 0.0],
    }
    for entry in step_passes:
        guest_input = next(
            item for item in entry["inputs"] if item["sampler_name"] == "GuestImage"
        )
        assert guest_input == {
            "sampler_name": "GuestImage",
            "location": "mcrv:guest_demo",
            "width": 2048,
            "height": 1024,
        }
        dtb_input = next(
            item for item in entry["inputs"] if item["sampler_name"] == "DtbImage"
        )
        assert dtb_input == {
            "sampler_name": "DtbImage",
            "location": "mcrv:dtb_mcrv",
            "width": 1024,
            "height": 1,
        }
        assert any(item["sampler_name"] == "Ram" for item in entry["inputs"])
        assert any(item["sampler_name"] == "Input" for item in entry["inputs"])

    commit_passes = [
        entry for entry in post_effect["passes"]
        if entry["fragment_shader"] == "mcrv:post/rv32_ram_commit"
    ]
    assert len(commit_passes) == 2
    assert [entry["output"] for entry in commit_passes] == ["ram_b", "ram_a"]
    for entry in commit_passes:
        assert [item["sampler_name"] for item in entry["inputs"]] == [
            "Ram", "State", "GuestImage", "MtdImage"
        ]
    assert [entry["fragment_shader"] for entry in post_effect["passes"]] == [
        "minecraft:post/blit",
        "mcrv:post/rv32_input_capture",
        "mcrv:post/rv32_step",
        "mcrv:post/rv32_ram_commit",
        "mcrv:post/rv32_cache_clear",
        "mcrv:post/rv32_step",
        "mcrv:post/rv32_ram_commit",
        "mcrv:post/rv32_cache_clear",
        "mcrv:post/rv32_display",
    ]
    display_pass = post_effect["passes"][-1]
    assert [item["sampler_name"] for item in display_pass["inputs"]] == [
        "Scene", "State", "Ram"
    ]

    boot_effect_path = (
        project_root / "assets" / "mcrv" / "post_effect" / "rv32i_boot.json"
    )
    boot_effect = json.loads(boot_effect_path.read_text(encoding="utf-8"))
    boot_step_passes = [
        entry for entry in boot_effect["passes"]
        if entry["fragment_shader"] == "mcrv:post/rv32_step"
    ]
    assert len(boot_step_passes) == 2
    for entry in boot_step_passes:
        guest_input = next(
            item for item in entry["inputs"] if item["sampler_name"] == "GuestImage"
        )
        assert guest_input["location"] == "mcrv:guest_boot_probe"
        assert (guest_input["width"], guest_input["height"]) == (2048, 1024)
        dtb_input = next(
            item for item in entry["inputs"] if item["sampler_name"] == "DtbImage"
        )
        assert dtb_input["location"] == "mcrv:dtb_mcrv"
    boot_commit_passes = [
        entry for entry in boot_effect["passes"]
        if entry["fragment_shader"] == "mcrv:post/rv32_ram_commit"
    ]
    assert len(boot_commit_passes) == 2
    for entry in boot_commit_passes:
        guest_input = next(
            item for item in entry["inputs"] if item["sampler_name"] == "GuestImage"
        )
        assert guest_input == {
            "sampler_name": "GuestImage",
            "location": "mcrv:guest_boot_probe",
            "width": 2048,
            "height": 1024,
        }

    linux_profiles = {
        "rv32i_linux": (64, 71),
        "rv32i_linux_fast": (128, 135),
        "rv32i_linux_turbo": (256, 263),
        "rv32i_linux_ultra": (512, 519),
    }
    for profile_name, (instruction_count, pass_count) in linux_profiles.items():
        linux_effect_path = (
            project_root / "assets" / "mcrv" / "post_effect"
            / f"{profile_name}.json"
        )
        linux_effect = json.loads(linux_effect_path.read_text(encoding="utf-8"))
        linux_step_passes = [
            entry for entry in linux_effect["passes"]
            if entry["fragment_shader"] == "mcrv:post/rv32_step"
        ]
        assert len(linux_step_passes) == instruction_count
        assert len(linux_effect["passes"]) == pass_count
        for entry in linux_step_passes:
            inputs = {item["sampler_name"]: item for item in entry["inputs"]}
            assert inputs["GuestImage"]["location"] == "mcrv:guest_linux"
            assert inputs["DtbImage"]["location"] == "mcrv:dtb_rvc_linux"
            assert inputs["MtdImage"]["location"] == "mcrv:mtd_linux"

    linux_guest_path = (
        project_root / "assets" / "mcrv" / "textures" / "effect"
        / "guest_linux.png"
    )
    linux_width, linux_height, linux_texture = decode_guest_texture(
        linux_guest_path.read_bytes()
    )
    assert (linux_width, linux_height) == (2048, 1024)
    linux_payload_size = 8_305_028
    assert hashlib.sha256(linux_texture[:linux_payload_size]).hexdigest() == (
        "75a060159e959c833df4305839705fdb185752cc6b730b0f3c72854a5d4b3de1"
    )
    assert linux_texture[0x8F0:0x8F8] == bytes.fromhex("1385050067800000")
    assert struct.unpack_from("<4I", linux_texture, len(linux_texture) - 16) == (
        0x1020, 0x80000000, 0x80000000, BOOT_MAGIC
    )

    linux_dtb = (project_root / "programs" / "rvc-linux.dtb").read_bytes()
    linux_dtb_properties = parse_dtb_properties(linux_dtb)
    assert struct.unpack(">4I", linux_dtb_properties["/memory@80000000"]["reg"]) == (
        0, 0x80000000, 0, RAM_BYTES
    )
    assert b"init=/rvcinit" in linux_dtb_properties["/chosen"]["bootargs"]

    mtd_width, mtd_height, mtd_texture = decode_guest_texture(
        (project_root / "assets" / "mcrv" / "textures" / "effect"
         / "mtd_linux.png").read_bytes()
    )
    assert (mtd_width, mtd_height) == (4096, 3447)
    rootfs_size = int.from_bytes(mtd_texture[8:12], "big")
    assert rootfs_size == 56_471_216
    assert hashlib.sha256(mtd_texture[:rootfs_size]).hexdigest() == (
        "1f8adf1c3cc689d68004f362a268d1e9013d337d42a97f5641272a2c1fa86044"
    )
    rootfs = mtd_texture[:rootfs_size]
    assert checksum(rootfs[:512]) == 0
    entries = root_entries(rootfs)
    named_entries = {entry_name(rootfs, offset): offset for offset in entries}
    init_offset = named_entries["rvcinit"]
    init_size = struct.unpack_from(">I", rootfs, init_offset + 8)[0]
    init_data_offset = header_name_end(rootfs, init_offset)
    init_script = rootfs[init_data_offset : init_data_offset + init_size]
    assert init_script == (project_root / "guest" / "rvcinit").read_bytes()
    assert init_script.index(b"/fibonacci") < init_script.index(b"getty")
    fibonacci_offset = named_entries["fibonacci"]
    fibonacci_info = struct.unpack_from(">I", rootfs, fibonacci_offset)[0] & 15
    fibonacci_size = struct.unpack_from(">I", rootfs, fibonacci_offset + 8)[0]
    fibonacci_data_offset = header_name_end(rootfs, fibonacci_offset)
    fibonacci = rootfs[
        fibonacci_data_offset : fibonacci_data_offset + fibonacci_size
    ]
    assert fibonacci_info == 10
    assert fibonacci == (project_root / "guest" / "fibonacci").read_bytes()
    verify_fibonacci_elf(fibonacci)

    dtb_texture_path = (
        project_root / "assets" / "mcrv" / "textures" / "effect" / "dtb_mcrv.png"
    )
    dtb_width, dtb_height, dtb_texture = decode_guest_texture(
        dtb_texture_path.read_bytes()
    )
    assert (dtb_width, dtb_height) == (1024, 1)
    tree = platform_tree()
    dtb = build_dtb(tree)
    assert (project_root / "programs" / "mcrv.dtb").read_bytes() == dtb
    assert (project_root / "programs" / "mcrv.dts").read_text(encoding="utf-8") == render_dts(tree)
    assert dtb_texture[:len(dtb)] == dtb
    assert dtb_texture[len(dtb):] == bytes(4096 - len(dtb))
    dtb_properties = parse_dtb_properties(dtb)
    assert dtb_properties["/"]["compatible"] == b"minecraft,mcrv\0riscv-virtio\0"
    assert struct.unpack(">I", dtb_properties["/cpus"]["timebase-frequency"])[0] == 120
    assert struct.unpack(">4I", dtb_properties["/memory@80000000"]["reg"]) == (
        0, 0x80000000, 0, RAM_BYTES
    )
    assert struct.unpack(">I", dtb_properties["/soc/plic@c000000"]["riscv,ndev"])[0] == 10
    assert struct.unpack(">I", dtb_properties["/soc/uart@10000000"]["interrupts"])[0] == 10
    assert dtb_properties["/chosen"]["stdout-path"] == b"/soc/uart@10000000\0"

    assembly_path = project_root / "programs" / "framebuffer_demo.S"
    assert assemble(assembly_path.read_text(encoding="utf-8")) == EXPECTED_PROGRAM

    boot_source = (project_root / "programs" / "boot_probe.S").read_text(encoding="utf-8")
    boot_program = assemble(boot_source)
    boot_texture_path = (
        project_root / "assets" / "mcrv" / "textures" / "effect"
        / "guest_boot_probe.png"
    )
    boot_width, boot_height, boot_texture = decode_guest_texture(
        boot_texture_path.read_bytes()
    )
    assert (boot_width, boot_height) == (2048, 1024)
    boot_descriptor_offset = len(boot_texture) - BOOT_DESCRIPTOR_WORDS * 4
    dtb_address, entry_point, load_address, magic = struct.unpack_from(
        "<4I", boot_texture, boot_descriptor_offset
    )
    assert (dtb_address, entry_point, load_address, magic) == (
        0x1020, 0x80000000, 0x80000000, BOOT_MAGIC
    )
    texture_boot_program = list(
        struct.unpack_from(f"<{len(boot_program)}I", boot_texture)
    )
    assert texture_boot_program == boot_program
    uart_output, boot_pc, boot_status = run_boot_probe(
        boot_program, load_address, entry_point, dtb_address, dtb
    )
    assert uart_output == b"DTB A1 OK"
    assert boot_pc == 0x8000008C
    assert boot_status == 1
    verify_high_multiply()
    verify_sv32_translation()
    verify_interrupt_logic()

    registers, memory, csrs, clint, uart, plic, pc, cycle, status, privilege = run_demo(program)
    values = [
        struct.unpack_from("<I", memory, FRAMEBUFFER_ADDRESS + index * 4)[0]
        for index in range(FRAMEBUFFER_WORDS)
    ]
    assert values == list(range(1, FRAMEBUFFER_WORDS + 1))
    assert registers[3:6] == [21, 6, 126]
    assert registers[9:13] == [3, 3, 3, 3]
    assert registers[15] == 0
    assert registers[16] == 126
    assert registers[17:20] == [0x0C201000, 0x10000000, 83]
    assert registers[21:25] == [0x40001000, 42, 0x73, 43]
    assert registers[25] == 0x80000
    assert registers[27] == 2
    assert registers[29] == 13
    assert struct.unpack_from("<I", memory, 2048)[0] == 16
    assert struct.unpack_from("<I", memory, 0xA400)[0] == 0x2C01
    assert struct.unpack_from("<I", memory, 0xA0C0)[0] == 0x030000C7
    assert struct.unpack_from("<I", memory, 0xA100)[0] == 0x040000C7
    assert struct.unpack_from("<I", memory, 0xB000)[0] == 0x4B
    assert struct.unpack_from("<I", memory, 0xB004)[0] == 0x4C7
    assert struct.unpack_from("<I", memory, 0xB008)[0] == 0x59
    assert struct.unpack_from("<I", memory, 0xB00C)[0] == 0x4D7
    assert csrs[CSR_MSCRATCH] == 126
    assert csrs[CSR_MTVEC] == 0x600
    assert csrs[CSR_MEPC] == 0x40000358
    assert csrs[CSR_MCAUSE] == 0x80000007
    assert csrs[CSR_MTVAL] == 0
    assert csrs[CSR_MEDELEG] == 0xB3F7
    assert csrs[CSR_MIDELEG] == 0x220
    assert csrs[CSR_MIE] == 0xA20
    assert csrs[CSR_MIP] == 0
    assert csrs[CSR_STVEC] == 0x40000668
    assert csrs[CSR_SSCRATCH] == 0x40000478
    assert csrs[CSR_SEPC] == 0x40002528
    assert csrs[CSR_SCAUSE] == 13
    assert csrs[CSR_STVAL] == 0x40000000
    assert csrs[CSR_SATP] == 0x8000000A
    assert csrs[CSR_MSTATUS] == 0xC00A2
    assert clint == {"msip": 0, "mtimecmp": 12, "mtime": 0xA65}
    assert uart == {"ier": 0, "lcr": 0, "tx_head": 13, "pending": 0}
    assert bytes(memory[UART_TX_BUFFER_ADDRESS : UART_TX_BUFFER_ADDRESS + 13]) == b"UART IRQ OK S"
    assert plic == {
        "priority": 1,
        "machine_enable": 0,
        "machine_threshold": 0,
        "machine_claimed": 0,
        "supervisor_enable": 0x400,
        "supervisor_threshold": 0,
        "supervisor_claimed": 0,
    }
    assert privilege == 0
    assert pc == 0x40002558
    assert cycle == 2815
    assert status == 1
    print(
        "RV32IMA M/S/U guest texture OK: M/S UART/PLIC external interrupts, CLINT timer "
        "interrupts, Sv32, MPRV, SUM/MXR, 12 delegated traps, 2815 instructions; "
        "0x80000000 boot descriptor, platform DTB and a0/a1 probe; Linux payload, "
        "12 MiB RAM DTB, Fibonacci ROMFS user program, 1 KiB UART ring, "
        "50-key world-space input bridge, 24-page RAM sampler, rvc timer semantics "
        "and Linux profiles up to 512 instructions/frame"
    )


if __name__ == "__main__":
    main()
