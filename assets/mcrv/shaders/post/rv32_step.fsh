#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D StateSampler;
uniform sampler2D RamSampler;
uniform sampler2D GuestImageSampler;
uniform sampler2D DtbImageSampler;
uniform sampler2D MtdImageSampler;
uniform sampler2D InputSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 StateSize;
    vec2 RamSize;
    vec2 GuestImageSize;
    vec2 DtbImageSize;
    vec2 MtdImageSize;
    vec2 InputSize;
};

layout(location = 0) out vec4 fragColor;

const uint STATE_TEXTURE_WIDTH = 128u;
const uint STATE_TEXTURE_WORDS = 16384u;
const uint RAM_TEXTURE_WIDTH = 4096u;
const uint RAM_TEXTURE_WORDS = 3145728u;
const uint RAM_MAGIC_INDEX = RAM_TEXTURE_WORDS - 1u;
const uint RAM_MAGIC_VALUE = 0x52414d31u;
const uint RAM_WORDS = RAM_TEXTURE_WORDS - 1024u;
const uint GUEST_TEXTURE_WIDTH = 2048u;
const uint GUEST_TEXTURE_WORDS = 2097152u;
const uint MTD_TEXTURE_WIDTH = 4096u;
const uint MTD_TEXTURE_WORDS = 14118912u;
const uint DEVICE_BASE = 16300u;
const uint CSR_BASE = 16316u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint MAGIC_INDEX = 16383u;
const uint MAGIC_VALUE = 0x52563332u;
const uint GUEST_DTB_INDEX = GUEST_TEXTURE_WORDS - 4u;
const uint GUEST_ENTRY_INDEX = GUEST_TEXTURE_WORDS - 3u;
const uint GUEST_LOAD_INDEX = GUEST_TEXTURE_WORDS - 2u;
const uint GUEST_MAGIC_INDEX = GUEST_TEXTURE_WORDS - 1u;
const uint GUEST_MAGIC_VALUE = 0x4d435256u;
const uint RAM_BYTES = RAM_WORDS * 4u;
const uint DTB_BYTES = 4096u;
const uint MTD_BASE_ADDRESS = 0x40000000u;
const uint MTD_BYTES = MTD_TEXTURE_WORDS * 4u;
const uint RTC_BASE_ADDRESS = 0x030007f8u;
const uint RTC_REGISTER_BYTES = 8u;
const uint LINUX_TIMER_DIVIDER = 40u;
const uint INVALID_INDEX = 0xffffffffu;

const uint CLINT_MSIP_ADDRESS = 0x02000000u;
const uint CLINT_MTIMECMP_LOW_ADDRESS = 0x02004000u;
const uint CLINT_MTIMECMP_HIGH_ADDRESS = 0x02004004u;
const uint CLINT_MTIME_LOW_ADDRESS = 0x0200bff8u;
const uint CLINT_MTIME_HIGH_ADDRESS = 0x0200bffcu;
const uint UART_BASE_ADDRESS = 0x10000000u;
const uint UART_REGISTER_BYTES = 8u;
const uint UART_TX_BUFFER_OFFSET = RAM_BYTES;
const uint UART_TX_BUFFER_BYTES = 1024u;
const uint PLIC_PRIORITY_ADDRESS = 0x0c000028u;
const uint PLIC_PENDING_ADDRESS = 0x0c001000u;
const uint PLIC_ENABLE_ADDRESS = 0x0c002000u;
const uint PLIC_SUPERVISOR_ENABLE_ADDRESS = 0x0c002080u;
const uint PLIC_THRESHOLD_ADDRESS = 0x0c200000u;
const uint PLIC_CLAIM_COMPLETE_ADDRESS = 0x0c200004u;
const uint PLIC_SUPERVISOR_THRESHOLD_ADDRESS = 0x0c201000u;
const uint PLIC_SUPERVISOR_CLAIM_COMPLETE_ADDRESS = 0x0c201004u;
const uint UART_INTERRUPT_SOURCE = 10u;

const uint CSR_MSTATUS = 0x300u;
const uint CSR_MISA = 0x301u;
const uint CSR_MEDELEG = 0x302u;
const uint CSR_MIDELEG = 0x303u;
const uint CSR_MIE = 0x304u;
const uint CSR_MTVEC = 0x305u;
const uint CSR_MSCRATCH = 0x340u;
const uint CSR_MEPC = 0x341u;
const uint CSR_MCAUSE = 0x342u;
const uint CSR_MTVAL = 0x343u;
const uint CSR_MIP = 0x344u;
const uint CSR_SATP = 0x180u;
const uint CSR_MCYCLE = 0xb00u;
const uint CSR_MINSTRET = 0xb02u;
const uint CSR_CYCLE = 0xc00u;
const uint CSR_INSTRET = 0xc02u;
const uint CSR_MHARTID = 0xf14u;
const uint CSR_SSTATUS = 0x100u;
const uint CSR_SIE = 0x104u;
const uint CSR_STVEC = 0x105u;
const uint CSR_SSCRATCH = 0x140u;
const uint CSR_SEPC = 0x141u;
const uint CSR_SCAUSE = 0x142u;
const uint CSR_STVAL = 0x143u;
const uint CSR_SIP = 0x144u;
const uint CSR_TIME = 0xc01u;
const uint CSR_TIMEH = 0xc81u;
const uint CSR_MEMOP_OP = 0x0b0u;
const uint CSR_MEMOP_SRC = 0x0b1u;
const uint CSR_MEMOP_DST = 0x0b2u;
const uint CSR_MEMOP_N = 0x0b3u;
const uint CLINT_MSIP_INDEX = DEVICE_BASE + 0u;
const uint CLINT_MTIMECMP_LOW_INDEX = DEVICE_BASE + 1u;
const uint CLINT_MTIMECMP_HIGH_INDEX = DEVICE_BASE + 2u;
const uint CLINT_MTIME_LOW_INDEX = DEVICE_BASE + 3u;
const uint CLINT_MTIME_HIGH_INDEX = DEVICE_BASE + 4u;
const uint UART_IER_INDEX = DEVICE_BASE + 5u;
const uint UART_LCR_INDEX = DEVICE_BASE + 6u;
const uint UART_TX_HEAD_INDEX = DEVICE_BASE + 7u;
const uint PLIC_PRIORITY_INDEX = DEVICE_BASE + 8u;
const uint UART_PENDING_INDEX = DEVICE_BASE + 9u;
const uint PLIC_ENABLE_INDEX = DEVICE_BASE + 10u;
const uint PLIC_THRESHOLD_INDEX = DEVICE_BASE + 11u;
const uint PLIC_CLAIMED_INDEX = DEVICE_BASE + 12u;
const uint PLIC_SUPERVISOR_ENABLE_INDEX = DEVICE_BASE + 13u;
const uint PLIC_SUPERVISOR_THRESHOLD_INDEX = DEVICE_BASE + 14u;
const uint PLIC_SUPERVISOR_CLAIMED_INDEX = DEVICE_BASE + 15u;
const uint PRIVILEGE_INDEX = CSR_BASE + 28u;
const uint RESERVATION_ADDRESS_INDEX = CSR_BASE + 29u;
const uint RESERVATION_VALID_INDEX = CSR_BASE + 30u;
const uint CACHE_TAG_BASE = 4096u;
const uint CACHE_VALUE_BASE = 4352u;
const uint CACHE_VALID_BASE = 4608u;
const uint CACHE_SLOTS = 256u;
const uint CACHE_SETS = 64u;
const uint CACHE_WAYS = 4u;
const uint CACHE_OVERFLOW_INDEX = 4864u;
const uint MEMOP_PENDING_INDEX = 4865u;
const uint MEMOP_SOURCE_PHYSICAL_INDEX = 4866u;
const uint MEMOP_DESTINATION_PHYSICAL_INDEX = 4867u;
const uint MEMOP_BYTE_COUNT_INDEX = 4868u;
const uint RTC_LOW_INDEX = 4869u;
const uint RTC_HIGH_INDEX = 4870u;
const uint UART_LINE_LENGTH_BASE = 4871u;
const uint UART_LINE_COUNT = 32u;
const uint INPUT_MARKER_INDEX = 4903u;
const uint KEYBOARD_SELECTION_INDEX = 4904u;
const uint UART_RX_DATA_INDEX = 4905u;
const uint UART_RX_READY_INDEX = 4906u;
const uint RAM_PAGE_INDEX = 4907u;

const uint PRIVILEGE_USER = 0u;
const uint PRIVILEGE_SUPERVISOR = 1u;
const uint PRIVILEGE_MACHINE = 3u;

const uint ACCESS_INSTRUCTION = 0u;
const uint ACCESS_LOAD = 1u;
const uint ACCESS_STORE = 2u;

const uint STATUS_RUNNING = 0u;
const uint STATUS_EBREAK = 1u;

ivec2 stateWordCoordinate(uint index) {
    return ivec2(int(index % STATE_TEXTURE_WIDTH), int(index / STATE_TEXTURE_WIDTH));
}

ivec2 ramWordCoordinate(uint index) {
    return ivec2(int(index % RAM_TEXTURE_WIDTH), int(index / RAM_TEXTURE_WIDTH));
}

ivec2 guestWordCoordinate(uint index) {
    return ivec2(int(index % GUEST_TEXTURE_WIDTH), int(index / GUEST_TEXTURE_WIDTH));
}

ivec2 mtdWordCoordinate(uint index) {
    return ivec2(int(index % MTD_TEXTURE_WIDTH), int(index / MTD_TEXTURE_WIDTH));
}

uint decodeWord(vec4 encoded) {
    uvec4 bytes = uvec4(floor(encoded * 255.0 + 0.5));
    return bytes.r | (bytes.g << 8u) | (bytes.b << 16u) | (bytes.a << 24u);
}

vec4 encodeWord(uint word) {
    uvec4 bytes = uvec4(
        word & 0xffu,
        (word >> 8u) & 0xffu,
        (word >> 16u) & 0xffu,
        (word >> 24u) & 0xffu
    );
    return vec4(bytes) / 255.0;
}

uint readStateWord(uint index) {
    if (index >= STATE_TEXTURE_WORDS) {
        return 0u;
    }
    return decodeWord(texelFetch(StateSampler, stateWordCoordinate(index), 0));
}

uint readInputWord() {
    return decodeWord(texelFetch(InputSampler, ivec2(0), 0));
}

uint readGuestWord(uint index) {
    if (index >= GUEST_TEXTURE_WORDS) {
        return 0u;
    }
    return decodeWord(texelFetch(GuestImageSampler, guestWordCoordinate(index), 0));
}

bool guestDescriptorPresent() {
    return readGuestWord(GUEST_MAGIC_INDEX) == GUEST_MAGIC_VALUE;
}

uint guestLoadAddress() {
    return guestDescriptorPresent() ? readGuestWord(GUEST_LOAD_INDEX) : 0u;
}

uint guestEntryPoint() {
    return guestDescriptorPresent() ? readGuestWord(GUEST_ENTRY_INDEX) : 0u;
}

uint guestDtbAddress() {
    return guestDescriptorPresent() ? readGuestWord(GUEST_DTB_INDEX) : 0u;
}

uint readRegister(uint index) {
    return index == 0u ? 0u : readStateWord(REGISTER_BASE + index);
}

uint readMemoryWord(uint address) {
    uint wordAddress = address & ~3u;
    uint wordIndex = wordAddress >> 2u;
    uint cacheSet = (wordIndex ^ (wordIndex >> 7u) ^ (wordIndex >> 13u))
        & (CACHE_SETS - 1u);
    for (uint way = 0u; way < CACHE_WAYS; ++way) {
        uint slot = cacheSet * CACHE_WAYS + way;
        if (readStateWord(CACHE_VALID_BASE + slot) != 0u
                && readStateWord(CACHE_TAG_BASE + slot) == wordAddress) {
            return readStateWord(CACHE_VALUE_BASE + slot);
        }
    }
    return decodeWord(texelFetch(RamSampler, ramWordCoordinate(wordIndex), 0));
}

uint readRamWord(uint index) {
    return decodeWord(texelFetch(RamSampler, ramWordCoordinate(index), 0));
}

bool ramAddressValid(uint address, uint width) {
    uint base = guestLoadAddress();
    return width > 0u && width <= RAM_BYTES && address >= base
        && address - base <= RAM_BYTES - width;
}

uint ramAddressOffset(uint address) {
    return address - guestLoadAddress();
}

bool dtbAddressValid(uint address, uint width) {
    uint base = guestDtbAddress();
    return base != 0u && width > 0u && width <= DTB_BYTES && address >= base
        && address - base <= DTB_BYTES - width;
}

uint readDtbWord(uint address) {
    uint offset = address - guestDtbAddress();
    return decodeWord(texelFetch(DtbImageSampler, ivec2(int(offset >> 2u), 0), 0));
}

uint readMtdWord(uint address) {
    uint offset = address - MTD_BASE_ADDRESS;
    return decodeWord(texelFetch(MtdImageSampler, mtdWordCoordinate(offset >> 2u), 0));
}

bool linuxGuestPresent() {
    return readMtdWord(MTD_BASE_ADDRESS) == 0x6d6f722du; // "-rom"
}

bool uartReceiveInterruptPending() {
    return readStateWord(UART_RX_READY_INDEX) != 0u
        && (readStateWord(UART_IER_INDEX) & 0x1u) != 0u;
}

bool uartTransmitInterruptPending() {
    return readStateWord(UART_PENDING_INDEX) != 0u
        && (readStateWord(UART_IER_INDEX) & 0x2u) != 0u;
}

bool uartInterruptPending() {
    return uartReceiveInterruptPending() || uartTransmitInterruptPending();
}

uint keyboardByte(uint selection) {
    const uint keys[50] = uint[50](
        49u, 50u, 51u, 52u, 53u, 54u, 55u, 56u, 57u, 48u,
        113u, 119u, 101u, 114u, 116u, 121u, 117u, 105u, 111u, 112u,
        97u, 115u, 100u, 102u, 103u, 104u, 106u, 107u, 108u, 47u,
        122u, 120u, 99u, 118u, 98u, 110u, 109u, 46u, 45u, 95u,
        32u, 127u, 13u, 3u, 61u, 58u, 59u, 39u, 63u, 92u
    );
    return keys[min(selection, 49u)];
}

uint moveKeyboardSelection(uint selection, uint inputEvent) {
    uint row = min(selection, 49u) / 10u;
    uint column = min(selection, 49u) % 10u;
    if (inputEvent == 1u) row = (row + 4u) % 5u;
    if (inputEvent == 2u) row = (row + 1u) % 5u;
    if (inputEvent == 3u) column = (column + 9u) % 10u;
    if (inputEvent == 4u) column = (column + 1u) % 10u;
    return row * 10u + column;
}

uint clintStateIndex(uint address) {
    if (address == CLINT_MSIP_ADDRESS) return CLINT_MSIP_INDEX;
    if (address == CLINT_MTIMECMP_LOW_ADDRESS) return CLINT_MTIMECMP_LOW_INDEX;
    if (address == CLINT_MTIMECMP_HIGH_ADDRESS) return CLINT_MTIMECMP_HIGH_INDEX;
    if (address == CLINT_MTIME_LOW_ADDRESS) return CLINT_MTIME_LOW_INDEX;
    if (address == CLINT_MTIME_HIGH_ADDRESS) return CLINT_MTIME_HIGH_INDEX;
    return INVALID_INDEX;
}

bool plicInterruptEligible(bool supervisorContext) {
    uint priority = readStateWord(PLIC_PRIORITY_INDEX);
    uint enableIndex = supervisorContext
        ? PLIC_SUPERVISOR_ENABLE_INDEX : PLIC_ENABLE_INDEX;
    uint thresholdIndex = supervisorContext
        ? PLIC_SUPERVISOR_THRESHOLD_INDEX : PLIC_THRESHOLD_INDEX;
    uint claimedIndex = supervisorContext
        ? PLIC_SUPERVISOR_CLAIMED_INDEX : PLIC_CLAIMED_INDEX;
    uint threshold = readStateWord(thresholdIndex);
    bool enabled = (readStateWord(enableIndex)
        & (1u << UART_INTERRUPT_SOURCE)) != 0u;
    return uartInterruptPending()
        && readStateWord(claimedIndex) == 0u
        && enabled && priority > threshold;
}

bool uartAccessValid(uint address, uint width) {
    return address >= UART_BASE_ADDRESS && width > 0u
        && address - UART_BASE_ADDRESS <= UART_REGISTER_BYTES - width;
}

bool plicAccessValid(uint address, uint width) {
    return width == 4u && (address == PLIC_PRIORITY_ADDRESS
        || address == PLIC_PENDING_ADDRESS
        || address == PLIC_ENABLE_ADDRESS
        || address == PLIC_SUPERVISOR_ENABLE_ADDRESS
        || address == PLIC_THRESHOLD_ADDRESS
        || address == PLIC_CLAIM_COMPLETE_ADDRESS
        || address == PLIC_SUPERVISOR_THRESHOLD_ADDRESS
        || address == PLIC_SUPERVISOR_CLAIM_COMPLETE_ADDRESS);
}

bool rtcAccessValid(uint address, uint width) {
    return address >= RTC_BASE_ADDRESS && width > 0u
        && address - RTC_BASE_ADDRESS <= RTC_REGISTER_BYTES - width;
}

bool physicalAccessValid(uint address, uint width, bool writeAccess) {
    if (ramAddressValid(address, width)) return true;
    if (dtbAddressValid(address, width)) return true;
    if (!writeAccess && address >= MTD_BASE_ADDRESS && width > 0u
            && width <= MTD_BYTES
            && address - MTD_BASE_ADDRESS <= MTD_BYTES - width) return true;
    return (width == 4u && clintStateIndex(address) != INVALID_INDEX)
        || uartAccessValid(address, width) || plicAccessValid(address, width)
        || rtcAccessValid(address, width);
}

uint readPhysicalWord(uint address) {
    if (dtbAddressValid(address, 1u)) return readDtbWord(address);
    if (address >= MTD_BASE_ADDRESS
            && address - MTD_BASE_ADDRESS <= MTD_BYTES - 4u) {
        return readMtdWord(address);
    }
    if (rtcAccessValid(address, 1u)) {
        return address < RTC_BASE_ADDRESS + 4u
            ? readStateWord(RTC_LOW_INDEX) : readStateWord(RTC_HIGH_INDEX);
    }
    uint clintIndex = clintStateIndex(address);
    if (clintIndex != INVALID_INDEX) return readStateWord(clintIndex);
    if (uartAccessValid(address, 1u)) {
        uint registerOffset = address - UART_BASE_ADDRESS;
        uint lcr = readStateWord(UART_LCR_INDEX) & 0xffu;
        bool divisorLatch = (lcr & 0x80u) != 0u;
        uint value = 0u;
        if (registerOffset == 0u && !divisorLatch) {
            value = readStateWord(UART_RX_DATA_INDEX) & 0xffu;
        } else if (registerOffset == 1u && !divisorLatch) {
            value = readStateWord(UART_IER_INDEX) & 0x0fu;
        } else if (registerOffset == 2u) {
            value = uartReceiveInterruptPending() ? 0x04u
                  : uartTransmitInterruptPending() ? 0x02u
                  : 0x01u;
        } else if (registerOffset == 3u) {
            value = lcr;
        } else if (registerOffset == 5u) {
            value = 0x60u | (readStateWord(UART_RX_READY_INDEX) != 0u ? 0x01u : 0u);
        }
        return value << ((address & 3u) * 8u);
    }
    if (address == PLIC_PRIORITY_ADDRESS) return readStateWord(PLIC_PRIORITY_INDEX);
    if (address == PLIC_PENDING_ADDRESS) {
        return uartInterruptPending()
            ? 1u << UART_INTERRUPT_SOURCE : 0u;
    }
    if (address == PLIC_ENABLE_ADDRESS) return readStateWord(PLIC_ENABLE_INDEX);
    if (address == PLIC_SUPERVISOR_ENABLE_ADDRESS) {
        return readStateWord(PLIC_SUPERVISOR_ENABLE_INDEX);
    }
    if (address == PLIC_THRESHOLD_ADDRESS) return readStateWord(PLIC_THRESHOLD_INDEX);
    if (address == PLIC_SUPERVISOR_THRESHOLD_ADDRESS) {
        return readStateWord(PLIC_SUPERVISOR_THRESHOLD_INDEX);
    }
    if (address == PLIC_CLAIM_COMPLETE_ADDRESS) {
        return plicInterruptEligible(false) ? UART_INTERRUPT_SOURCE : 0u;
    }
    if (address == PLIC_SUPERVISOR_CLAIM_COMPLETE_ADDRESS) {
        return plicInterruptEligible(true) ? UART_INTERRUPT_SOURCE : 0u;
    }
    return readMemoryWord(ramAddressOffset(address));
}

uint signExtend(uint value, uint bits) {
    uint shift = 32u - bits;
    return uint(int(value << shift) >> int(shift));
}

uint multiplyHighUnsigned(uint left, uint right) {
    uint leftLow = left & 0xffffu;
    uint leftHigh = left >> 16u;
    uint rightLow = right & 0xffffu;
    uint rightHigh = right >> 16u;
    uint lowProduct = leftLow * rightLow;
    uint middle = leftHigh * rightLow + (lowProduct >> 16u);
    uint carryProduct = leftLow * rightHigh + (middle & 0xffffu);
    return leftHigh * rightHigh + (middle >> 16u) + (carryProduct >> 16u);
}

uint multiplyHighSignedUnsigned(uint left, uint right) {
    uint highWord = multiplyHighUnsigned(left, right);
    return (left & 0x80000000u) != 0u ? highWord - right : highWord;
}

uint multiplyHighSigned(uint left, uint right) {
    uint highWord = multiplyHighUnsigned(left, right);
    if ((left & 0x80000000u) != 0u) highWord -= right;
    if ((right & 0x80000000u) != 0u) highWord -= left;
    return highWord;
}

uint csrStateIndex(uint address) {
    if (address == CSR_SSTATUS) return CSR_MSTATUS;
    if (address == CSR_SIE) return CSR_MIE;
    if (address == CSR_SIP) return CSR_MIP;
    return address < 4096u ? address : INVALID_INDEX;
}

bool csrSupported(uint address) {
    return address < 4096u;
}

bool csrWritable(uint address) {
    return csrStateIndex(address) != INVALID_INDEX
        && ((address >> 10u) & 0x3u) != 0x3u;
}

uint csrWriteMask(uint address) {
    if (address == CSR_SSTATUS) return 0x000de162u;
    if (address == CSR_SIE) return 0x00000222u;
    if (address == CSR_SIP || address == CSR_MIP) return 0x00000022u;
    if (address == CSR_MIDELEG) return 0x00000666u;
    return 0xffffffffu;
}

bool csrAccessible(uint address, uint privilege) {
    uint requiredPrivilege = (address >> 8u) & 0x3u;
    return privilege >= requiredPrivilege;
}

uint readCSR(uint address) {
    if (address == CSR_MISA) return 0x40141101u; // RV32AIMSU
    if (address == CSR_MCYCLE || address == CSR_MINSTRET
            || address == CSR_CYCLE || address == CSR_INSTRET) {
        return readStateWord(CYCLE_INDEX);
    }
    if (address == CSR_TIME) return readStateWord(CLINT_MTIME_LOW_INDEX);
    if (address == CSR_TIMEH) return readStateWord(CLINT_MTIME_HIGH_INDEX);
    if (address == CSR_MHARTID) return 0u;
    uint index = csrStateIndex(address);
    uint value = index == INVALID_INDEX ? 0u : readStateWord(index);
    if (address == CSR_MIP || address == CSR_SIP) {
        uint machinePending = value & ~0x0a88u;
        if (readStateWord(CLINT_MSIP_INDEX) != 0u) machinePending |= 0x8u;
        uint timeLow = readStateWord(CLINT_MTIME_LOW_INDEX);
        uint timeHigh = readStateWord(CLINT_MTIME_HIGH_INDEX);
        uint compareLow = readStateWord(CLINT_MTIMECMP_LOW_INDEX);
        uint compareHigh = readStateWord(CLINT_MTIMECMP_HIGH_INDEX);
        if (timeHigh > compareHigh
                || (timeHigh == compareHigh && timeLow >= compareLow)) {
            machinePending |= 0x80u;
        }
        if (plicInterruptEligible(false)) machinePending |= 0x800u;
        if (plicInterruptEligible(true)) machinePending |= 0x200u;
        value = machinePending;
    }
    if (address == CSR_SSTATUS) return value & 0x000de162u;
    if (address == CSR_SIE || address == CSR_SIP) return value & 0x00000222u;
    return value;
}

bool translateAddress(uint virtualAddress, uint accessType, uint privilege,
        out uint physicalAddress) {
    physicalAddress = virtualAddress;
    uint satp = readCSR(CSR_SATP);
    if (privilege == PRIVILEGE_MACHINE || (satp >> 31u) == 0u) {
        return true;
    }

    uint tableAddress = (satp & 0x003fffffu) << 12u;
    uint vpn1 = (virtualAddress >> 22u) & 0x3ffu;
    uint vpn0 = (virtualAddress >> 12u) & 0x3ffu;
    uint pageOffset = virtualAddress & 0xfffu;
    uint pteAddress = tableAddress + vpn1 * 4u;
    if (pteAddress < tableAddress || !ramAddressValid(pteAddress, 4u)) {
        return false;
    }

    uint pte = readPhysicalWord(pteAddress);
    bool valid = (pte & 0x1u) != 0u;
    bool readable = (pte & 0x2u) != 0u;
    bool writable = (pte & 0x4u) != 0u;
    bool executable = (pte & 0x8u) != 0u;
    if (!valid || (writable && !readable)) {
        return false;
    }

    uint level = 1u;
    if (!readable && !executable) {
        tableAddress = (pte >> 10u) << 12u;
        pteAddress = tableAddress + vpn0 * 4u;
        if (pteAddress < tableAddress || !ramAddressValid(pteAddress, 4u)) {
            return false;
        }
        pte = readPhysicalWord(pteAddress);
        valid = (pte & 0x1u) != 0u;
        readable = (pte & 0x2u) != 0u;
        writable = (pte & 0x4u) != 0u;
        executable = (pte & 0x8u) != 0u;
        if (!valid || (writable && !readable) || (!readable && !executable)) {
            return false;
        }
        level = 0u;
    }

    bool userPage = (pte & 0x10u) != 0u;
    bool accessed = (pte & 0x40u) != 0u;
    bool dirty = (pte & 0x80u) != 0u;
    uint mstatus = readCSR(CSR_MSTATUS);
    bool mxr = ((mstatus >> 19u) & 1u) != 0u;
    bool sum = ((mstatus >> 18u) & 1u) != 0u;
    bool privilegeAllowed = privilege == PRIVILEGE_USER ? userPage
        : accessType == ACCESS_INSTRUCTION ? !userPage : !userPage || sum;
    bool accessAllowed = accessType == ACCESS_INSTRUCTION ? executable
        : accessType == ACCESS_LOAD ? readable || (mxr && executable)
        : writable;
    if (!privilegeAllowed || !accessAllowed || !accessed
            || (accessType == ACCESS_STORE && !dirty)) {
        return false;
    }

    uint physicalPageNumber = pte >> 10u;
    if (level == 1u) {
        if ((physicalPageNumber & 0x3ffu) != 0u) {
            return false;
        }
        physicalAddress = ((physicalPageNumber & ~0x3ffu) << 12u)
            | (vpn0 << 12u) | pageOffset;
    } else {
        physicalAddress = (physicalPageNumber << 12u) | pageOffset;
    }
    return true;
}

uint selectInterruptCause(uint pending) {
    if ((pending & (1u << 11u)) != 0u) return 11u;
    if ((pending & (1u << 3u)) != 0u) return 3u;
    if ((pending & (1u << 7u)) != 0u) return 7u;
    if ((pending & (1u << 9u)) != 0u) return 9u;
    if ((pending & (1u << 1u)) != 0u) return 1u;
    if ((pending & (1u << 5u)) != 0u) return 5u;
    return INVALID_INDEX;
}

uint initialWord(uint index) {
    if (index == MAGIC_INDEX) return MAGIC_VALUE;
    if (index == PC_INDEX) return guestEntryPoint();
    if (index == CYCLE_INDEX) return 0u;
    if (index == STATUS_INDEX) return STATUS_RUNNING;
    if (index == PRIVILEGE_INDEX) return PRIVILEGE_MACHINE;
    if (index == CLINT_MTIMECMP_LOW_INDEX
            || index == CLINT_MTIMECMP_HIGH_INDEX) return 0xffffffffu;
    if (index == PLIC_PRIORITY_INDEX) return 1u;
    if (index == RTC_LOW_INDEX) return 0x00000020u;
    if (index == RTC_HIGH_INDEX) return 0x26082805u;
    if (index >= DEVICE_BASE && index < REGISTER_BASE) return 0u;
    if (index == REGISTER_BASE + 10u) return 0u;
    if (index == REGISTER_BASE + 11u) return guestDtbAddress();
    if (index >= REGISTER_BASE && index < REGISTER_BASE + 32u) return 0u;
    return 0u;
}

void main() {
    uvec2 outputSize = uvec2(OutSize + 0.5);
    uvec2 pixel = min(uvec2(texCoord * OutSize), outputSize - uvec2(1u));
    uint outputIndex = pixel.y * STATE_TEXTURE_WIDTH + pixel.x;

    if (readStateWord(MAGIC_INDEX) != MAGIC_VALUE) {
        fragColor = encodeWord(initialWord(outputIndex));
        return;
    }

    if (readRamWord(RAM_MAGIC_INDEX) != RAM_MAGIC_VALUE) {
        fragColor = encodeWord(readStateWord(outputIndex));
        return;
    }

    uint currentWord = readStateWord(outputIndex);
    uint pc = readStateWord(PC_INDEX);
    uint cycle = readStateWord(CYCLE_INDEX);
    uint currentStatus = readStateWord(STATUS_INDEX);
    uint currentPrivilege = readStateWord(PRIVILEGE_INDEX);
    uint nextPrivilege = currentPrivilege;
    uint currentMstatus = readCSR(CSR_MSTATUS);
    uint dataPrivilege = currentPrivilege;
    if (currentPrivilege == PRIVILEGE_MACHINE
            && ((currentMstatus >> 17u) & 1u) != 0u) {
        uint machinePreviousPrivilege = (currentMstatus >> 11u) & 0x3u;
        dataPrivilege = machinePreviousPrivilege == PRIVILEGE_MACHINE
            ? PRIVILEGE_MACHINE
            : machinePreviousPrivilege == PRIVILEGE_SUPERVISOR
                ? PRIVILEGE_SUPERVISOR : PRIVILEGE_USER;
    }
    uint nextReservationAddress = readStateWord(RESERVATION_ADDRESS_INDEX);
    uint nextReservationValid = readStateWord(RESERVATION_VALID_INDEX);

    if (currentStatus != STATUS_RUNNING) {
        fragColor = encodeWord(currentWord);
        return;
    }
    if (readStateWord(CACHE_OVERFLOW_INDEX) != 0u
            || readStateWord(MEMOP_PENDING_INDEX) != 0u) {
        fragColor = encodeWord(currentWord);
        return;
    }

    uint nextPc = pc + 4u;
    uint nextStatus = STATUS_RUNNING;
    bool writeRegister = false;
    uint destinationRegister = 0u;
    uint registerValue = 0u;
    bool writeMemory = false;
    uint memoryAddress = 0u;
    uint memoryWidth = 0u;
    uint memoryValue = 0u;
    uint plicClaimIndex = INVALID_INDEX;
    bool writeCSR = false;
    uint csrWriteIndex = INVALID_INDEX;
    uint csrWriteValue = 0u;
    bool machineTrap = false;
    bool supervisorTrap = false;
    bool takeTrap = false;
    bool trapInterrupt = false;
    uint trapCause = 0u;
    uint trapValue = 0u;
    uint trapMstatus = 0u;
    bool memopTrigger = false;
    uint memopSourcePhysical = 0u;
    uint memopDestinationPhysical = 0u;
    uint memopByteCount = 0u;

    uint enabledPending = readCSR(CSR_MIP) & readCSR(CSR_MIE);
    uint delegatedPending = enabledPending & readCSR(CSR_MIDELEG);
    uint machinePending = enabledPending & ~readCSR(CSR_MIDELEG);
    bool machineInterruptsEnabled = currentPrivilege < PRIVILEGE_MACHINE
        || (currentPrivilege == PRIVILEGE_MACHINE
            && ((currentMstatus >> 3u) & 1u) != 0u);
    bool supervisorInterruptsEnabled = currentPrivilege < PRIVILEGE_SUPERVISOR
        || (currentPrivilege == PRIVILEGE_SUPERVISOR
            && ((currentMstatus >> 1u) & 1u) != 0u);
    uint interruptCause = machineInterruptsEnabled
        ? selectInterruptCause(machinePending) : INVALID_INDEX;
    if (interruptCause == INVALID_INDEX && currentPrivilege != PRIVILEGE_MACHINE
            && supervisorInterruptsEnabled) {
        interruptCause = selectInterruptCause(delegatedPending);
    }
    if (interruptCause != INVALID_INDEX) {
        takeTrap = true;
        trapInterrupt = true;
        trapCause = interruptCause;
    }

    bool fetchAligned = (pc & 3u) == 0u;
    uint instructionAddress = 0u;
    bool fetchTranslated = fetchAligned
        && translateAddress(pc, ACCESS_INSTRUCTION, currentPrivilege, instructionAddress);
    bool fetchInRange = fetchTranslated && ramAddressValid(instructionAddress, 4u);
    uint instruction = fetchInRange ? readPhysicalWord(instructionAddress) : 0u;

    if (takeTrap) {
        // Interrupts are taken between instructions, preserving the current PC.
    } else if (!fetchAligned) {
        takeTrap = true;
        trapCause = 0u;
        trapValue = pc;
    } else if (!fetchTranslated) {
        takeTrap = true;
        trapCause = 12u;
        trapValue = pc;
    } else if (!fetchInRange) {
        takeTrap = true;
        trapCause = 1u;
        trapValue = pc;
    } else {
        uint opcode = instruction & 0x7fu;
        uint rd = (instruction >> 7u) & 0x1fu;
        uint funct3 = (instruction >> 12u) & 0x7u;
        uint rs1 = (instruction >> 15u) & 0x1fu;
        uint rs2 = (instruction >> 20u) & 0x1fu;
        uint funct7 = (instruction >> 25u) & 0x7fu;
        uint source1 = readRegister(rs1);
        uint source2 = readRegister(rs2);

        uint immediateI = signExtend(instruction >> 20u, 12u);
        uint immediateS = signExtend(
            ((instruction >> 25u) << 5u) | ((instruction >> 7u) & 0x1fu), 12u);
        uint immediateB = signExtend(
            (((instruction >> 31u) & 1u) << 12u)
            | (((instruction >> 7u) & 1u) << 11u)
            | (((instruction >> 25u) & 0x3fu) << 5u)
            | (((instruction >> 8u) & 0xfu) << 1u), 13u);
        uint immediateU = instruction & 0xfffff000u;
        uint immediateJ = signExtend(
            (((instruction >> 31u) & 1u) << 20u)
            | (((instruction >> 12u) & 0xffu) << 12u)
            | (((instruction >> 20u) & 1u) << 11u)
            | (((instruction >> 21u) & 0x3ffu) << 1u), 21u);

        bool legal = true;

        if (opcode == 0x37u) { // LUI
            writeRegister = true;
            destinationRegister = rd;
            registerValue = immediateU;
        } else if (opcode == 0x17u) { // AUIPC
            writeRegister = true;
            destinationRegister = rd;
            registerValue = pc + immediateU;
        } else if (opcode == 0x6fu) { // JAL
            uint target = pc + immediateJ;
            if ((target & 3u) != 0u) {
                takeTrap = true;
                trapCause = 0u;
                trapValue = target;
            } else {
                writeRegister = true;
                destinationRegister = rd;
                registerValue = pc + 4u;
                nextPc = target;
            }
        } else if (opcode == 0x67u) { // JALR
            if (funct3 != 0u) {
                legal = false;
            } else {
                uint target = (source1 + immediateI) & 0xfffffffeu;
                if ((target & 3u) != 0u) {
                    takeTrap = true;
                    trapCause = 0u;
                    trapValue = target;
                } else {
                    writeRegister = true;
                    destinationRegister = rd;
                    registerValue = pc + 4u;
                    nextPc = target;
                }
            }
        } else if (opcode == 0x63u) { // Conditional branches
            bool takeBranch = false;
            if (funct3 == 0u) takeBranch = source1 == source2;
            else if (funct3 == 1u) takeBranch = source1 != source2;
            else if (funct3 == 4u) takeBranch = int(source1) < int(source2);
            else if (funct3 == 5u) takeBranch = int(source1) >= int(source2);
            else if (funct3 == 6u) takeBranch = source1 < source2;
            else if (funct3 == 7u) takeBranch = source1 >= source2;
            else legal = false;

            if (legal && takeBranch) {
                uint target = pc + immediateB;
                if ((target & 3u) != 0u) {
                    takeTrap = true;
                    trapCause = 0u;
                    trapValue = target;
                } else {
                    nextPc = target;
                }
            }
        } else if (opcode == 0x03u) { // Loads
            uint address = source1 + immediateI;
            uint width = funct3 == 0u || funct3 == 4u ? 1u
                       : funct3 == 1u || funct3 == 5u ? 2u
                       : funct3 == 2u ? 4u : 0u;
            bool aligned = width == 1u || (width == 2u && (address & 1u) == 0u)
                         || (width == 4u && (address & 3u) == 0u);
            uint physicalAddress = 0u;
            bool translated = width > 0u && aligned
                && translateAddress(address, ACCESS_LOAD, dataPrivilege, physicalAddress);
            bool inRange = translated && physicalAccessValid(physicalAddress, width, false);

            if (width == 0u) {
                legal = false;
            } else if (!aligned) {
                takeTrap = true;
                trapCause = 4u;
                trapValue = address;
            } else if (!translated) {
                takeTrap = true;
                trapCause = 13u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = 5u;
                trapValue = address;
            } else {
                memoryAddress = physicalAddress;
                memoryWidth = width;
                uint word = readPhysicalWord(physicalAddress);
                uint shift = (physicalAddress & 3u) * 8u;
                uint loaded = width == 1u ? ((word >> shift) & 0xffu)
                            : width == 2u ? ((word >> shift) & 0xffffu)
                            : word;
                if (funct3 == 0u) loaded = signExtend(loaded, 8u);
                if (funct3 == 1u) loaded = signExtend(loaded, 16u);
                writeRegister = true;
                destinationRegister = rd;
                registerValue = loaded;
                if (width == 4u && loaded == UART_INTERRUPT_SOURCE) {
                    if (physicalAddress == PLIC_CLAIM_COMPLETE_ADDRESS) {
                        plicClaimIndex = PLIC_CLAIMED_INDEX;
                    } else if (physicalAddress
                            == PLIC_SUPERVISOR_CLAIM_COMPLETE_ADDRESS) {
                        plicClaimIndex = PLIC_SUPERVISOR_CLAIMED_INDEX;
                    }
                }
            }
        } else if (opcode == 0x23u) { // Stores
            uint address = source1 + immediateS;
            uint width = funct3 == 0u ? 1u : funct3 == 1u ? 2u : funct3 == 2u ? 4u : 0u;
            bool aligned = width == 1u || (width == 2u && (address & 1u) == 0u)
                         || (width == 4u && (address & 3u) == 0u);
            uint physicalAddress = 0u;
            bool translated = width > 0u && aligned
                && translateAddress(address, ACCESS_STORE, dataPrivilege, physicalAddress);
            bool inRange = translated && physicalAccessValid(physicalAddress, width, true);

            if (width == 0u) {
                legal = false;
            } else if (!aligned) {
                takeTrap = true;
                trapCause = 6u;
                trapValue = address;
            } else if (!translated) {
                takeTrap = true;
                trapCause = 15u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = 7u;
                trapValue = address;
            } else {
                writeMemory = true;
                memoryAddress = physicalAddress;
                memoryWidth = width;
                memoryValue = source2;
            }
        } else if (opcode == 0x13u) { // Register-immediate operations
            writeRegister = true;
            destinationRegister = rd;
            uint shiftAmount = (instruction >> 20u) & 0x1fu;
            if (funct3 == 0u) registerValue = source1 + immediateI;
            else if (funct3 == 2u) registerValue = int(source1) < int(immediateI) ? 1u : 0u;
            else if (funct3 == 3u) registerValue = source1 < immediateI ? 1u : 0u;
            else if (funct3 == 4u) registerValue = source1 ^ immediateI;
            else if (funct3 == 6u) registerValue = source1 | immediateI;
            else if (funct3 == 7u) registerValue = source1 & immediateI;
            else if (funct3 == 1u && funct7 == 0u) registerValue = source1 << shiftAmount;
            else if (funct3 == 5u && funct7 == 0u) registerValue = source1 >> shiftAmount;
            else if (funct3 == 5u && funct7 == 0x20u) registerValue = uint(int(source1) >> int(shiftAmount));
            else legal = false;
        } else if (opcode == 0x33u) { // Register-register operations
            writeRegister = true;
            destinationRegister = rd;
            uint shiftAmount = source2 & 0x1fu;
            if (funct7 == 0x01u) { // RV32M
                if (funct3 == 0u) registerValue = source1 * source2;
                else if (funct3 == 1u) registerValue = multiplyHighSigned(source1, source2);
                else if (funct3 == 2u) registerValue = multiplyHighSignedUnsigned(source1, source2);
                else if (funct3 == 3u) registerValue = multiplyHighUnsigned(source1, source2);
                else if (funct3 == 4u) {
                    if (source2 == 0u) registerValue = 0xffffffffu;
                    else if (source1 == 0x80000000u && source2 == 0xffffffffu) registerValue = source1;
                    else registerValue = uint(int(source1) / int(source2));
                } else if (funct3 == 5u) {
                    registerValue = source2 == 0u ? 0xffffffffu : source1 / source2;
                } else if (funct3 == 6u) {
                    if (source2 == 0u) registerValue = source1;
                    else if (source1 == 0x80000000u && source2 == 0xffffffffu) registerValue = 0u;
                    else registerValue = uint(int(source1) % int(source2));
                } else if (funct3 == 7u) {
                    registerValue = source2 == 0u ? source1 : source1 % source2;
                } else legal = false;
            } else if (funct3 == 0u && funct7 == 0u) registerValue = source1 + source2;
            else if (funct3 == 0u && funct7 == 0x20u) registerValue = source1 - source2;
            else if (funct3 == 1u && funct7 == 0u) registerValue = source1 << shiftAmount;
            else if (funct3 == 2u && funct7 == 0u) registerValue = int(source1) < int(source2) ? 1u : 0u;
            else if (funct3 == 3u && funct7 == 0u) registerValue = source1 < source2 ? 1u : 0u;
            else if (funct3 == 4u && funct7 == 0u) registerValue = source1 ^ source2;
            else if (funct3 == 5u && funct7 == 0u) registerValue = source1 >> shiftAmount;
            else if (funct3 == 5u && funct7 == 0x20u) registerValue = uint(int(source1) >> int(shiftAmount));
            else if (funct3 == 6u && funct7 == 0u) registerValue = source1 | source2;
            else if (funct3 == 7u && funct7 == 0u) registerValue = source1 & source2;
            else legal = false;
        } else if (opcode == 0x2fu) { // RV32A word operations
            uint address = source1;
            uint atomicFunction = instruction >> 27u;
            bool loadReservation = atomicFunction == 2u && rs2 == 0u;
            bool aligned = (address & 3u) == 0u;
            uint physicalAddress = 0u;
            bool translated = funct3 == 2u && aligned
                && translateAddress(address,
                    loadReservation ? ACCESS_LOAD : ACCESS_STORE,
                    dataPrivilege, physicalAddress);
            bool inRange = translated && ramAddressValid(physicalAddress, 4u);

            if (funct3 != 2u) {
                legal = false;
            } else if (!aligned) {
                takeTrap = true;
                trapCause = loadReservation ? 4u : 6u;
                trapValue = address;
            } else if (!translated) {
                takeTrap = true;
                trapCause = loadReservation ? 13u : 15u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = loadReservation ? 5u : 7u;
                trapValue = address;
            } else {
                uint oldMemoryValue = readPhysicalWord(physicalAddress);
                writeRegister = true;
                destinationRegister = rd;
                registerValue = oldMemoryValue;

                if (loadReservation) { // LR.W
                    nextReservationAddress = physicalAddress;
                    nextReservationValid = 1u;
                } else if (atomicFunction == 3u) { // SC.W
                    bool reservationMatches = nextReservationValid != 0u
                        && nextReservationAddress == physicalAddress;
                    registerValue = reservationMatches ? 0u : 1u;
                    if (reservationMatches) {
                        writeMemory = true;
                        memoryAddress = physicalAddress;
                        memoryWidth = 4u;
                        memoryValue = source2;
                    }
                    nextReservationValid = 0u;
                } else {
                    uint atomicValue = 0u;
                    if (atomicFunction == 1u) atomicValue = source2; // AMOSWAP.W
                    else if (atomicFunction == 0u) atomicValue = oldMemoryValue + source2; // AMOADD.W
                    else if (atomicFunction == 4u) atomicValue = oldMemoryValue ^ source2; // AMOXOR.W
                    else if (atomicFunction == 12u) atomicValue = oldMemoryValue & source2; // AMOAND.W
                    else if (atomicFunction == 8u) atomicValue = oldMemoryValue | source2; // AMOOR.W
                    else if (atomicFunction == 16u) atomicValue = int(oldMemoryValue) < int(source2) ? oldMemoryValue : source2; // AMOMIN.W
                    else if (atomicFunction == 20u) atomicValue = int(oldMemoryValue) > int(source2) ? oldMemoryValue : source2; // AMOMAX.W
                    else if (atomicFunction == 24u) atomicValue = oldMemoryValue < source2 ? oldMemoryValue : source2; // AMOMINU.W
                    else if (atomicFunction == 28u) atomicValue = oldMemoryValue > source2 ? oldMemoryValue : source2; // AMOMAXU.W
                    else legal = false;

                    if (legal) {
                        writeMemory = true;
                        memoryAddress = physicalAddress;
                        memoryWidth = 4u;
                        memoryValue = atomicValue;
                        nextReservationValid = 0u;
                    }
                }
            }
        } else if (opcode == 0x0fu) { // FENCE and FENCE.I
            legal = funct3 == 0u || funct3 == 1u;
        } else if (opcode == 0x73u) { // Environment and CSR operations
            if (funct3 == 0u) {
                if (instruction == 0x00000073u) {
                    takeTrap = true;
                    trapCause = currentPrivilege == PRIVILEGE_USER ? 8u
                        : currentPrivilege == PRIVILEGE_SUPERVISOR ? 9u : 11u;
                } else if (instruction == 0x00100073u) {
                    nextPc = pc;
                    nextStatus = STATUS_EBREAK;
                } else if (instruction == 0x30200073u
                        && currentPrivilege == PRIVILEGE_MACHINE) {
                    uint mstatus = readCSR(CSR_MSTATUS);
                    uint machinePreviousInterruptEnable = (mstatus >> 7u) & 1u;
                    uint machinePreviousPrivilege = (mstatus >> 11u) & 0x3u;
                    nextPc = readCSR(CSR_MEPC);
                    nextPrivilege = machinePreviousPrivilege;
                    writeCSR = true;
                    csrWriteIndex = csrStateIndex(CSR_MSTATUS);
                    csrWriteValue = (mstatus & ~0x1888u)
                        | (machinePreviousInterruptEnable << 3u)
                        | (1u << 7u);
                    if (machinePreviousPrivilege != PRIVILEGE_MACHINE) {
                        csrWriteValue &= ~0x20000u;
                    }
                } else if (instruction == 0x10200073u
                        && currentPrivilege >= PRIVILEGE_SUPERVISOR) {
                    uint mstatus = readCSR(CSR_MSTATUS);
                    uint supervisorPreviousInterruptEnable = (mstatus >> 5u) & 1u;
                    uint supervisorPreviousPrivilege = (mstatus >> 8u) & 1u;
                    nextPc = readCSR(CSR_SEPC);
                    nextPrivilege = supervisorPreviousPrivilege;
                    writeCSR = true;
                    csrWriteIndex = csrStateIndex(CSR_MSTATUS);
                    csrWriteValue = (mstatus & ~0x20122u)
                        | (supervisorPreviousInterruptEnable << 1u)
                        | (1u << 5u);
                } else if ((instruction & 0xfe007fffu) == 0x12000073u
                        && currentPrivilege >= PRIVILEGE_SUPERVISOR) {
                    // Address translation reads page tables directly; SFENCE.VMA
                    // completes as a synchronization point.
                } else if (instruction == 0x10500073u
                        && currentPrivilege >= PRIVILEGE_SUPERVISOR) {
                    // WFI completes as a scheduling hint while timer state advances.
                } else {
                    legal = false;
                }
            } else {
                uint csrAddress = instruction >> 20u;
                bool immediateCSR = funct3 >= 5u;
                uint csrOperand = immediateCSR ? rs1 : source1;
                uint oldCSRValue = readCSR(csrAddress);
                bool replaceCSR = funct3 == 1u || funct3 == 5u;
                bool setCSRBits = funct3 == 2u || funct3 == 6u;
                bool clearCSRBits = funct3 == 3u || funct3 == 7u;
                bool wantsCSRWrite = replaceCSR || ((setCSRBits || clearCSRBits) && csrOperand != 0u);

                if (!csrSupported(csrAddress) || !csrAccessible(csrAddress, currentPrivilege)
                        || (!replaceCSR && !setCSRBits && !clearCSRBits)
                        || (wantsCSRWrite && !csrWritable(csrAddress))) {
                    legal = false;
                } else {
                    writeRegister = true;
                    destinationRegister = rd;
                    registerValue = oldCSRValue;
                    if (wantsCSRWrite) {
                        writeCSR = true;
                        csrWriteIndex = csrStateIndex(csrAddress);
                        uint requestedCSRValue = replaceCSR ? csrOperand
                            : setCSRBits ? oldCSRValue | csrOperand
                            : oldCSRValue & ~csrOperand;
                        uint writeMask = csrWriteMask(csrAddress);
                        uint rawCSRValue = readStateWord(csrWriteIndex);
                        csrWriteValue = (rawCSRValue & ~writeMask)
                            | (requestedCSRValue & writeMask);
                        if (csrAddress == CSR_MEMOP_OP) {
                            uint sourceVirtual = readCSR(CSR_MEMOP_SRC);
                            uint destinationVirtual = readCSR(CSR_MEMOP_DST);
                            bool sourceTranslated = translateAddress(
                                sourceVirtual, ACCESS_LOAD, dataPrivilege,
                                memopSourcePhysical);
                            bool destinationTranslated = translateAddress(
                                destinationVirtual, ACCESS_STORE, dataPrivilege,
                                memopDestinationPhysical);
                            if (!sourceTranslated || !destinationTranslated) {
                                takeTrap = true;
                                trapCause = sourceTranslated ? 15u : 13u;
                                trapValue = sourceTranslated
                                    ? destinationVirtual : sourceVirtual;
                            } else {
                                memopTrigger = true;
                                memopByteCount = readCSR(CSR_MEMOP_N);
                            }
                        }
                    }
                }
            }
        } else {
            legal = false;
        }

        if (!legal) {
            takeTrap = true;
            trapCause = 2u;
            trapValue = instruction;
            writeRegister = false;
            writeMemory = false;
            writeCSR = false;
        }
    }

    if (takeTrap) {
        writeRegister = false;
        writeMemory = false;
        writeCSR = false;
        uint mstatus = readCSR(CSR_MSTATUS);
        bool delegated = currentPrivilege != PRIVILEGE_MACHINE
            && (((trapInterrupt ? readCSR(CSR_MIDELEG) : readCSR(CSR_MEDELEG))
                >> trapCause) & 1u) != 0u;
        if (delegated) {
            supervisorTrap = true;
            uint supervisorInterruptEnable = (mstatus >> 1u) & 1u;
            trapMstatus = (mstatus & ~0x122u)
                | (supervisorInterruptEnable << 5u)
                | ((currentPrivilege & 1u) << 8u);
            uint trapVector = readCSR(CSR_STVEC);
            nextPc = (trapVector & ~0x3u)
                + (trapInterrupt && (trapVector & 0x3u) == 1u ? trapCause * 4u : 0u);
            nextPrivilege = PRIVILEGE_SUPERVISOR;
        } else {
            machineTrap = true;
            uint machineInterruptEnable = (mstatus >> 3u) & 1u;
            trapMstatus = (mstatus & ~0x1888u)
                | (machineInterruptEnable << 7u)
                | (currentPrivilege << 11u);
            uint trapVector = readCSR(CSR_MTVEC);
            nextPc = (trapVector & ~0x3u)
                + (trapInterrupt && (trapVector & 0x3u) == 1u ? trapCause * 4u : 0u);
            nextPrivilege = PRIVILEGE_MACHINE;
        }
    }

    if (writeMemory) nextReservationValid = 0u;

    uint uartOffset = memoryAddress - UART_BASE_ADDRESS;
    bool uartWrite = writeMemory && uartAccessValid(memoryAddress, memoryWidth);
    bool uartDivisorLatch = (readStateWord(UART_LCR_INDEX) & 0x80u) != 0u;
    bool uartTransmit = uartWrite && uartOffset == 0u && !uartDivisorLatch;
    bool uartReceiveRead = !writeMemory && memoryWidth > 0u
        && memoryAddress == UART_BASE_ADDRESS && !uartDivisorLatch;
    uint inputMarker = readInputWord() & 0xffu;
    bool inputChanged = linuxGuestPresent() && inputMarker != 0u
        && inputMarker != readStateWord(INPUT_MARKER_INDEX);
    uint inputEvent = inputMarker == 0u ? 0u : (inputMarker - 1u) & 0x7u;
    uint keyboardSelection = readStateWord(KEYBOARD_SELECTION_INDEX);
    uint nextKeyboardSelection = moveKeyboardSelection(keyboardSelection, inputEvent);
    bool inputByteRequested = inputChanged
        && (inputEvent == 5u || inputEvent == 7u);
    uint inputByte = inputEvent == 7u ? 3u
                   : keyboardByte(keyboardSelection);
    bool inputByteAccepted = inputByteRequested
        && (readStateWord(UART_RX_READY_INDEX) == 0u || uartReceiveRead);

    bool cacheWrite = writeMemory && ramAddressValid(memoryAddress, memoryWidth);
    uint cacheWriteAddress = memoryAddress;
    uint cacheWriteValue = memoryValue;
    uint cacheWriteWidth = memoryWidth;
    if (uartTransmit) {
        uint uartHead = readStateWord(UART_TX_HEAD_INDEX);
        cacheWrite = true;
        cacheWriteAddress = guestLoadAddress() + UART_TX_BUFFER_OFFSET
            + uartHead % UART_TX_BUFFER_BYTES;
        cacheWriteWidth = 1u;
    }

    uint cacheSlot = INVALID_INDEX;
    uint cacheTag = 0u;
    uint cacheValue = 0u;
    bool cacheOverflow = false;
    if (cacheWrite) {
        uint offset = ramAddressOffset(cacheWriteAddress);
        cacheTag = offset & ~3u;
        uint oldValue = readMemoryWord(cacheTag);
        uint shift = (offset & 3u) * 8u;
        if (cacheWriteWidth == 1u) {
            uint mask = 0xffu << shift;
            cacheValue = (oldValue & ~mask) | ((cacheWriteValue << shift) & mask);
        } else if (cacheWriteWidth == 2u) {
            uint mask = 0xffffu << shift;
            cacheValue = (oldValue & ~mask) | ((cacheWriteValue << shift) & mask);
        } else {
            cacheValue = cacheWriteValue;
        }
        if (cacheValue == oldValue) {
            cacheWrite = false;
        } else {
            uint wordIndex = cacheTag >> 2u;
            uint cacheSet = (wordIndex ^ (wordIndex >> 7u) ^ (wordIndex >> 13u))
                & (CACHE_SETS - 1u);
            for (uint way = 0u; way < CACHE_WAYS; ++way) {
                uint candidate = cacheSet * CACHE_WAYS + way;
                if (readStateWord(CACHE_VALID_BASE + candidate) != 0u
                        && readStateWord(CACHE_TAG_BASE + candidate) == cacheTag) {
                    cacheSlot = candidate;
                    break;
                }
            }
            if (cacheSlot == INVALID_INDEX) {
                for (uint way = 0u; way < CACHE_WAYS; ++way) {
                    uint candidate = cacheSet * CACHE_WAYS + way;
                    if (readStateWord(CACHE_VALID_BASE + candidate) == 0u) {
                        cacheSlot = candidate;
                        break;
                    }
                }
            }
            cacheOverflow = cacheSlot == INVALID_INDEX;
        }
    }

    if (cacheOverflow) {
        nextPc = pc;
        nextStatus = currentStatus;
        nextPrivilege = currentPrivilege;
        nextReservationAddress = readStateWord(RESERVATION_ADDRESS_INDEX);
        nextReservationValid = readStateWord(RESERVATION_VALID_INDEX);
        writeRegister = false;
        writeCSR = false;
        writeMemory = false;
        uartWrite = false;
        uartTransmit = false;
    }

    uint outputWord = currentWord;
    uint timerIncrement = (!linuxGuestPresent()
        || cycle % LINUX_TIMER_DIVIDER == LINUX_TIMER_DIVIDER - 1u) ? 1u : 0u;
    uint currentTimeLow = readStateWord(CLINT_MTIME_LOW_INDEX);
    uint nextTimeLow = currentTimeLow + timerIncrement;
    uint nextTimeHigh = readStateWord(CLINT_MTIME_HIGH_INDEX)
        + (nextTimeLow < currentTimeLow ? 1u : 0u);
    if (outputIndex == CLINT_MTIME_LOW_INDEX) outputWord = nextTimeLow;
    if (outputIndex == CLINT_MTIME_HIGH_INDEX) outputWord = nextTimeHigh;
    if (outputIndex == PC_INDEX) outputWord = nextPc;
    if (outputIndex == CYCLE_INDEX) outputWord = cycle + 1u;
    if (outputIndex == STATUS_INDEX) outputWord = nextStatus;
    if (outputIndex == PRIVILEGE_INDEX) outputWord = nextPrivilege;
    if (outputIndex == RESERVATION_ADDRESS_INDEX) outputWord = nextReservationAddress;
    if (outputIndex == RESERVATION_VALID_INDEX) outputWord = nextReservationValid;
    if (inputChanged && outputIndex == INPUT_MARKER_INDEX) outputWord = inputMarker;
    if (inputChanged && inputEvent >= 1u && inputEvent <= 4u
            && outputIndex == KEYBOARD_SELECTION_INDEX) {
        outputWord = nextKeyboardSelection;
    }
    if (inputChanged && inputEvent == 6u && outputIndex == RAM_PAGE_INDEX) {
        outputWord = (readStateWord(RAM_PAGE_INDEX) + 1u) % 24u;
    }
    if (uartReceiveRead && outputIndex == UART_RX_READY_INDEX) outputWord = 0u;
    if (inputByteAccepted && outputIndex == UART_RX_DATA_INDEX) {
        outputWord = inputByte;
    }
    if (inputByteAccepted && outputIndex == UART_RX_READY_INDEX) outputWord = 1u;

    if (writeRegister && destinationRegister != 0u
            && outputIndex == REGISTER_BASE + destinationRegister) {
        outputWord = registerValue;
    }
    if (outputIndex == REGISTER_BASE) {
        outputWord = 0u;
    }

    if (writeCSR && outputIndex == csrWriteIndex) {
        outputWord = csrWriteValue;
    }

    if (machineTrap) {
        if (outputIndex == csrStateIndex(CSR_MSTATUS)) outputWord = trapMstatus;
        if (outputIndex == csrStateIndex(CSR_MEPC)) outputWord = pc;
        if (outputIndex == csrStateIndex(CSR_MCAUSE)) {
            outputWord = trapCause | (trapInterrupt ? 0x80000000u : 0u);
        }
        if (outputIndex == csrStateIndex(CSR_MTVAL)) outputWord = trapValue;
    }
    if (supervisorTrap) {
        if (outputIndex == csrStateIndex(CSR_MSTATUS)) outputWord = trapMstatus;
        if (outputIndex == csrStateIndex(CSR_SEPC)) outputWord = pc;
        if (outputIndex == csrStateIndex(CSR_SCAUSE)) {
            outputWord = trapCause | (trapInterrupt ? 0x80000000u : 0u);
        }
        if (outputIndex == csrStateIndex(CSR_STVAL)) outputWord = trapValue;
    }

    uint clintWriteIndex = clintStateIndex(memoryAddress);
    if (writeMemory && memoryWidth == 4u
            && clintWriteIndex != INVALID_INDEX && outputIndex == clintWriteIndex) {
        outputWord = memoryValue;
    }
    if (writeMemory && memoryWidth == 4u
            && (memoryAddress == CLINT_MTIMECMP_LOW_ADDRESS
                || memoryAddress == CLINT_MTIMECMP_HIGH_ADDRESS)
            && outputIndex == csrStateIndex(CSR_MIP)) {
        outputWord = readStateWord(csrStateIndex(CSR_MIP)) & ~0x000000a0u;
    }
    if (writeMemory && rtcAccessValid(memoryAddress, memoryWidth)
            && memoryAddress == RTC_BASE_ADDRESS) {
        if (outputIndex == RTC_LOW_INDEX) outputWord = 0x00000020u;
        if (outputIndex == RTC_HIGH_INDEX) outputWord = 0x26082805u;
    }

    if (uartWrite && uartOffset == 1u && !uartDivisorLatch
            && outputIndex == UART_IER_INDEX) {
        outputWord = memoryValue & 0x0fu;
    }
    if (uartWrite && uartOffset == 3u && outputIndex == UART_LCR_INDEX) {
        outputWord = memoryValue & 0xffu;
    }
    if (uartTransmit) {
        uint uartHead = readStateWord(UART_TX_HEAD_INDEX);
        bool lineFeed = linuxGuestPresent() && (memoryValue & 0xffu) == 10u;
        uint nextUartHead = lineFeed
            ? (uartHead + 32u) & ~31u
            : uartHead + 1u;
        if (outputIndex == UART_TX_HEAD_INDEX) outputWord = nextUartHead;
        uint lineSlot = (uartHead >> 5u) % UART_LINE_COUNT;
        if (linuxGuestPresent()
                && outputIndex == UART_LINE_LENGTH_BASE + lineSlot) {
            outputWord = lineFeed ? uartHead & 31u : (uartHead & 31u) + 1u;
        }
        if ((readStateWord(UART_IER_INDEX) & 0x2u) != 0u
                && outputIndex == UART_PENDING_INDEX) {
            outputWord = 1u;
        }
    }

    if (cacheWrite && !cacheOverflow && outputIndex == CACHE_TAG_BASE + cacheSlot) {
        outputWord = cacheTag;
    }
    if (cacheWrite && !cacheOverflow && outputIndex == CACHE_VALUE_BASE + cacheSlot) {
        outputWord = cacheValue;
    }
    if (cacheWrite && !cacheOverflow && outputIndex == CACHE_VALID_BASE + cacheSlot) {
        outputWord = 1u;
    }
    if (cacheOverflow && outputIndex == CACHE_OVERFLOW_INDEX) outputWord = 1u;
    if (memopTrigger && outputIndex == MEMOP_PENDING_INDEX) outputWord = 1u;
    if (memopTrigger && outputIndex == MEMOP_SOURCE_PHYSICAL_INDEX) {
        outputWord = memopSourcePhysical;
    }
    if (memopTrigger && outputIndex == MEMOP_DESTINATION_PHYSICAL_INDEX) {
        outputWord = memopDestinationPhysical;
    }
    if (memopTrigger && outputIndex == MEMOP_BYTE_COUNT_INDEX) {
        outputWord = memopByteCount;
    }

    if (writeMemory && memoryWidth == 4u) {
        if (memoryAddress == PLIC_PRIORITY_ADDRESS
                && outputIndex == PLIC_PRIORITY_INDEX) {
            outputWord = memoryValue;
        }
        if (memoryAddress == PLIC_ENABLE_ADDRESS
                && outputIndex == PLIC_ENABLE_INDEX) {
            outputWord = memoryValue;
        }
        if (memoryAddress == PLIC_SUPERVISOR_ENABLE_ADDRESS
                && outputIndex == PLIC_SUPERVISOR_ENABLE_INDEX) {
            outputWord = memoryValue;
        }
        if (memoryAddress == PLIC_THRESHOLD_ADDRESS
                && outputIndex == PLIC_THRESHOLD_INDEX) {
            outputWord = memoryValue;
        }
        if (memoryAddress == PLIC_SUPERVISOR_THRESHOLD_ADDRESS
                && outputIndex == PLIC_SUPERVISOR_THRESHOLD_INDEX) {
            outputWord = memoryValue;
        }
        if (memoryAddress == PLIC_CLAIM_COMPLETE_ADDRESS
                && memoryValue == readStateWord(PLIC_CLAIMED_INDEX)
                && outputIndex == PLIC_CLAIMED_INDEX) {
            outputWord = 0u;
        }
        if (memoryAddress == PLIC_SUPERVISOR_CLAIM_COMPLETE_ADDRESS
                && memoryValue == readStateWord(PLIC_SUPERVISOR_CLAIMED_INDEX)
                && outputIndex == PLIC_SUPERVISOR_CLAIMED_INDEX) {
            outputWord = 0u;
        }
    }
    if (plicClaimIndex != INVALID_INDEX) {
        if (outputIndex == UART_PENDING_INDEX) outputWord = 0u;
        if (outputIndex == plicClaimIndex) outputWord = UART_INTERRUPT_SOURCE;
    }

    fragColor = encodeWord(outputWord);
}
