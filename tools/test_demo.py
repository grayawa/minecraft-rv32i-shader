"""Reference execution test for the bundled RV32IMA interrupt and trap self-test."""

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

EXPECTED_PROGRAM = [
    0x01500193, 0x00600213, 0x024182B3, 0x02419333,
    0x0241A3B3, 0x0241B433, 0x0241C4B3, 0x0241D533,
    0x0241E5B3, 0x0241F633, 0x07E00693, 0x40D29263,
    0x40031063, 0x3E039E63, 0x3E041C63, 0x00300713,
    0x3EE49863, 0x3EE51663, 0x3EE59463, 0x3EE61263,
    0x340297F3, 0x34002873, 0x3C079C63, 0x3C581A63,
    0x60000893, 0x00700913, 0x0128A023, 0x1008A9AF,
    0x00900A13, 0x1948AAAF, 0x0008AB03, 0x00700B93,
    0x3B799863, 0x3A0A9663, 0x00900B93, 0x3B7B1263,
    0x0128AC2F, 0x0008AC83, 0x397C1C63, 0x01000B93,
    0x397C9863, 0x46C00D13, 0x305D1073, 0x00000D93,
    0x00000073, 0x00100E13, 0x37CD9C63, 0x34202EF3,
    0x00B00F13, 0x37EE9663, 0x00102003, 0x00200E13,
    0x37CD9063, 0x34202EF3, 0x00400F13, 0x35EE9A63,
    0x34302EF3, 0x00100F13, 0x35EE9463, 0x00000D93,
    0x020008B7, 0x00100993, 0x0138A023, 0x0008AA03,
    0x333A1863, 0x0008A023, 0x020048B7, 0x0200C937,
    0xFF890913, 0x00092023, 0x00092223, 0x0008A223,
    0x00C00993, 0x0138A023, 0x08000A13, 0x304A2073,
    0x00800A13, 0x300A2073, 0x00000013, 0x00000013,
    0x00000013, 0x00000013, 0x00000013, 0x00000013,
    0x00000013, 0x00000013, 0x00100E13, 0x2DCD9A63,
    0x34202EF3, 0x80000F37, 0x007F0F13, 0x2DEE9263,
    0x0000A8B7, 0x0000B937, 0x000039B7, 0xC0198993,
    0x4138A023, 0x04B00993, 0x01392023, 0x4C700993,
    0x01392223, 0x05900993, 0x01392423, 0x4D700993,
    0x01392623, 0x80000D37, 0x00AD0D13, 0x180D1073,
    0x12000073, 0x000018B7, 0x02A00A13, 0x0148A023,
    0x40001AB7, 0x00021D37, 0x800D0D13, 0x300D1073,
    0x000AAB03, 0x254B1E63, 0x02B00B93, 0x017AA023,
    0x30001073, 0x0008AC03, 0x257C1463, 0x40000D37,
    0x4A0D0D13, 0x105D1073, 0x0000BD37, 0x3F7D0D13,
    0x302D1073, 0x02000A13, 0x304A2073, 0x303A1073,
    0x40000D37, 0x22CD0D13, 0x341D1073, 0x00001D37,
    0x802D0D13, 0x300D1073, 0x30200073, 0x00200E13,
    0x21CD9A63, 0x14202EF3, 0x80000F37, 0x005F0F13,
    0x21EE9263, 0x00000D93, 0x00000073, 0x00100E13,
    0x1FCD9A63, 0x14202EF3, 0x00900F13, 0x1FEE9463,
    0xFFFFFFFF, 0x00200E13, 0x1DCD9E63, 0x14202EF3,
    0x00200F13, 0x1DEE9863, 0x14302EF3, 0xFFF00F13,
    0x1DEE9263, 0x00102003, 0x00300E13, 0x1BCD9C63,
    0x14202EF3, 0x00400F13, 0x1BEE9663, 0x14302EF3,
    0x00100F13, 0x1BEE9063, 0x00002123, 0x00400E13,
    0x19CD9A63, 0x14202EF3, 0x00600F13, 0x19EE9463,
    0x14302EF3, 0x00200F13, 0x17EE9E63, 0x50000D37,
    0x000D2003, 0x00500E13, 0x17CD9663, 0x14202EF3,
    0x00D00F13, 0x17EE9063, 0x14302EF3, 0x15AE9C63,
    0x000D2023, 0x00600E13, 0x15CD9663, 0x14202EF3,
    0x00F00F13, 0x15EE9063, 0x14302EF3, 0x13AE9C63,
    0x00200D13, 0x000D0067, 0x00700E13, 0x13CD9463,
    0x14202EF3, 0x00000F13, 0x11EE9E63, 0x14302EF3,
    0x00200F13, 0x11EE9863, 0x40000D37, 0x34CD0D13,
    0x140D1073, 0x50000D37, 0x000D0067, 0x00800E13,
    0x0FCD9A63, 0x14202EF3, 0x00C00F13, 0x0FEE9463,
    0x14302EF3, 0x0FAE9063, 0x12000073, 0x40003D37,
    0x000D2A03, 0x00900E13, 0x0DCD9663, 0x14202EF3,
    0x00D00F13, 0x0DEE9063, 0x00040CB7, 0x100CA073,
    0x000D2A03, 0x0B7A1863, 0x40002D37, 0x3E0D0D13,
    0x000D2A03, 0x00A00E13, 0x09CD9E63, 0x14202EF3,
    0x00D00F13, 0x09EE9863, 0x00080CB7, 0x100CA073,
    0x000D2A03, 0x07300B93, 0x077A1E63, 0x40002D37,
    0x3DCD0D13, 0x141D1073, 0x10200073, 0x00000D93,
    0x00000073, 0x00100E13, 0x07CD9863, 0x00800E13,
    0x07CF1463, 0x40000D37, 0x000D2003, 0x00200E13,
    0x05CD9C63, 0x00D00E13, 0x05CF1863, 0x400030B7,
    0x00100113, 0x40004337, 0x90030313, 0x0020A023,
    0x00408093, 0x00110113, 0xFE60EAE3, 0x00100073,
    0x000010B7, 0xDEADC137, 0xEEF10113, 0x0020A023,
    0x00100073, 0x400010B7, 0xDEADC137, 0xEEF10113,
    0x0020A023, 0x00100073, 0x400030B7, 0xDEADC137,
    0xEEF10113, 0x0020A023, 0x00100073, 0x34202F73,
    0x000F4C63, 0x001D8D93, 0x34102FF3, 0x004F8F93,
    0x341F9073, 0x30200073, 0x001D8D93, 0x08000F93,
    0x304FB073, 0x02000F93, 0x344FA073, 0x30200073,
    0x14202F73, 0x020F4663, 0x001D8D93, 0x00C00F93,
    0x01FF1863, 0x14002FF3, 0x141F9073, 0x10200073,
    0x14102FF3, 0x004F8F93, 0x141F9073, 0x10200073,
    0x001D8D93, 0x02000F93, 0x144FB073, 0x10200073,
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


def read_pending_interrupts(csrs: dict[int, int], clint: dict[str, int]) -> int:
    pending = csrs[CSR_MIP] & ~0x88
    if clint["msip"]:
        pending |= 1 << 3
    if clint["mtime"] >= clint["mtimecmp"]:
        pending |= 1 << 7
    return pending & MASK32


def select_interrupt_cause(pending: int) -> int | None:
    for cause in (11, 3, 7, 9, 1, 5):
        if pending & (1 << cause):
            return cause
    return None


def verify_interrupt_logic() -> None:
    csrs = {CSR_MIP: 1 << 5}
    clint = {"msip": 1, "mtimecmp": 9, "mtime": 9}
    pending = read_pending_interrupts(csrs, clint)
    assert pending == (1 << 3) | (1 << 5) | (1 << 7)
    assert select_interrupt_cause(pending) == 3
    assert select_interrupt_cause((1 << 7) | (1 << 11)) == 11
    assert select_interrupt_cause(0) is None


def physical_access_valid(address: int) -> bool:
    return address <= RAM_BYTES - 4 or address in {
        CLINT_MSIP,
        CLINT_MTIMECMP_LOW,
        CLINT_MTIMECMP_HIGH,
        CLINT_MTIME_LOW,
        CLINT_MTIME_HIGH,
    }


def read_physical_word(
    memory: bytearray, clint: dict[str, int], address: int
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
    return struct.unpack_from("<I", memory, address)[0]


def run_demo(
    program: list[int],
) -> tuple[list[int], bytearray, dict[int, int], dict[str, int], int, int, int, int]:
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

        enabled_pending = read_pending_interrupts(csrs, clint) & csrs[CSR_MIE]
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
            elif opcode == 0x23 and funct3 == 2:
                immediate = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
                address = (registers[rs1] + sign_extend(immediate, 12)) & MASK32
                if address & 3:
                    trap = (6, address)
                else:
                    physical_address = translate_address(memory, csrs, address, 2, data_privilege)
                    if physical_address is None:
                        trap = (15, address)
                    elif not physical_access_valid(physical_address):
                        trap = (7, address)
                    elif physical_address <= RAM_BYTES - 4:
                        struct.pack_into("<I", memory, physical_address, registers[rs2])
                        reservation = None
                    elif physical_address == CLINT_MSIP:
                        clint["msip"] = registers[rs2] & 1
                    elif physical_address == CLINT_MTIMECMP_LOW:
                        clint["mtimecmp"] = (
                            (clint["mtimecmp"] & 0xFFFFFFFF00000000)
                            | registers[rs2]
                        )
                    elif physical_address == CLINT_MTIMECMP_HIGH:
                        clint["mtimecmp"] = (
                            (clint["mtimecmp"] & MASK32) | (registers[rs2] << 32)
                        )
                    else:
                        mtime_write = (physical_address, registers[rs2])
            elif opcode == 0x03 and funct3 == 2:
                immediate = sign_extend(instruction >> 20, 12)
                address = (registers[rs1] + immediate) & MASK32
                if address & 3:
                    trap = (4, address)
                else:
                    physical_address = translate_address(memory, csrs, address, 1, data_privilege)
                    if physical_address is None:
                        trap = (13, address)
                    elif not physical_access_valid(physical_address):
                        trap = (5, address)
                    else:
                        registers[rd] = read_physical_word(memory, clint, physical_address)
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
                    write_mask = (
                        0x000DE162
                        if address == CSR_SSTATUS
                        else 0x222
                        if address in (CSR_SIE, CSR_SIP, CSR_MIP)
                        else MASK32
                    )
                    raw_value = (
                        read_pending_interrupts(csrs, clint)
                        if state_address == CSR_MIP
                        else csrs[state_address]
                    )
                    old_value = raw_value & write_mask
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
    return registers, memory, csrs, clint, pc, cycle, status, privilege


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
    verify_sv32_translation()
    verify_interrupt_logic()

    registers, memory, csrs, clint, pc, cycle, status, privilege = run_demo(program)
    values = [
        struct.unpack_from("<I", memory, FRAMEBUFFER_ADDRESS + index * 4)[0]
        for index in range(FRAMEBUFFER_WORDS)
    ]
    assert values == list(range(1, FRAMEBUFFER_WORDS + 1))
    assert registers[3:6] == [21, 6, 126]
    assert registers[9:13] == [3, 3, 3, 3]
    assert registers[15] == 0
    assert registers[16] == 126
    assert registers[17:20] == [0x1000, 0xB000, 0x4D7]
    assert registers[21:25] == [0x40001000, 42, 0x73, 43]
    assert registers[25] == 0x80000
    assert registers[27] == 2
    assert registers[29] == 13
    assert struct.unpack_from("<I", memory, 1536)[0] == 16
    assert struct.unpack_from("<I", memory, 0xA400)[0] == 0x2C01
    assert struct.unpack_from("<I", memory, 0xB000)[0] == 0x4B
    assert struct.unpack_from("<I", memory, 0xB004)[0] == 0x4C7
    assert struct.unpack_from("<I", memory, 0xB008)[0] == 0x59
    assert struct.unpack_from("<I", memory, 0xB00C)[0] == 0x4D7
    assert csrs[CSR_MSCRATCH] == 126
    assert csrs[CSR_MTVEC] == 0x46C
    assert csrs[CSR_MEPC] == 0x4000022C
    assert csrs[CSR_MCAUSE] == 0x80000007
    assert csrs[CSR_MTVAL] == 0
    assert csrs[CSR_MEDELEG] == 0xB3F7
    assert csrs[CSR_MIDELEG] == 0x20
    assert csrs[CSR_MIE] == 0x20
    assert csrs[CSR_MIP] == 0
    assert csrs[CSR_STVEC] == 0x400004A0
    assert csrs[CSR_SSCRATCH] == 0x4000034C
    assert csrs[CSR_SEPC] == 0x400023FC
    assert csrs[CSR_SCAUSE] == 13
    assert csrs[CSR_STVAL] == 0x40000000
    assert csrs[CSR_SATP] == 0x8000000A
    assert csrs[CSR_MSTATUS] == 0xC00A2
    assert clint == {"msip": 0, "mtimecmp": 12, "mtime": 0xA3E}
    assert privilege == 0
    assert pc == 0x4000242C
    assert cycle == 2706
    assert status == 1
    print(
        "RV32IMA M/S/U OK: CLINT timer interrupts, Sv32, MPRV, "
        "SUM/MXR, 12 delegated traps, 2706 instructions"
    )


if __name__ == "__main__":
    main()
