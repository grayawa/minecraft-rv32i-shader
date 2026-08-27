#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D StateSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 StateSize;
};

layout(location = 0) out vec4 fragColor;

const uint TEXTURE_WIDTH = 128u;
const uint TEXTURE_WORDS = 16384u;
const uint CSR_BASE = 16316u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint MAGIC_INDEX = 16383u;
const uint MAGIC_VALUE = 0x52563332u;
const uint RAM_WORDS = CSR_BASE;
const uint RAM_BYTES = RAM_WORDS * 4u;
const uint INVALID_INDEX = 0xffffffffu;

const uint CLINT_MSIP_ADDRESS = 0x02000000u;
const uint CLINT_MTIMECMP_LOW_ADDRESS = 0x02004000u;
const uint CLINT_MTIMECMP_HIGH_ADDRESS = 0x02004004u;
const uint CLINT_MTIME_LOW_ADDRESS = 0x0200bff8u;
const uint CLINT_MTIME_HIGH_ADDRESS = 0x0200bffcu;

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
const uint CLINT_MSIP_INDEX = CSR_BASE + 16u;
const uint CLINT_MTIMECMP_LOW_INDEX = CSR_BASE + 17u;
const uint CLINT_MTIMECMP_HIGH_INDEX = CSR_BASE + 18u;
const uint CLINT_MTIME_LOW_INDEX = CSR_BASE + 19u;
const uint CLINT_MTIME_HIGH_INDEX = CSR_BASE + 20u;
const uint PRIVILEGE_INDEX = CSR_BASE + 28u;
const uint RESERVATION_ADDRESS_INDEX = CSR_BASE + 29u;
const uint RESERVATION_VALID_INDEX = CSR_BASE + 30u;

const uint PRIVILEGE_USER = 0u;
const uint PRIVILEGE_SUPERVISOR = 1u;
const uint PRIVILEGE_MACHINE = 3u;

const uint ACCESS_INSTRUCTION = 0u;
const uint ACCESS_LOAD = 1u;
const uint ACCESS_STORE = 2u;

const uint STATUS_RUNNING = 0u;
const uint STATUS_EBREAK = 1u;

ivec2 wordCoordinate(uint index) {
    return ivec2(int(index % TEXTURE_WIDTH), int(index / TEXTURE_WIDTH));
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
    if (index >= TEXTURE_WORDS) {
        return 0u;
    }
    return decodeWord(texelFetch(StateSampler, wordCoordinate(index), 0));
}

uint readRegister(uint index) {
    return index == 0u ? 0u : readStateWord(REGISTER_BASE + index);
}

uint readMemoryWord(uint address) {
    return readStateWord(address >> 2u);
}

uint clintStateIndex(uint address) {
    if (address == CLINT_MSIP_ADDRESS) return CLINT_MSIP_INDEX;
    if (address == CLINT_MTIMECMP_LOW_ADDRESS) return CLINT_MTIMECMP_LOW_INDEX;
    if (address == CLINT_MTIMECMP_HIGH_ADDRESS) return CLINT_MTIMECMP_HIGH_INDEX;
    if (address == CLINT_MTIME_LOW_ADDRESS) return CLINT_MTIME_LOW_INDEX;
    if (address == CLINT_MTIME_HIGH_ADDRESS) return CLINT_MTIME_HIGH_INDEX;
    return INVALID_INDEX;
}

bool physicalAccessValid(uint address, uint width) {
    if (width > 0u && address <= RAM_BYTES - width) return true;
    return width == 4u && clintStateIndex(address) != INVALID_INDEX;
}

uint readPhysicalWord(uint address) {
    uint clintIndex = clintStateIndex(address);
    return clintIndex == INVALID_INDEX
        ? readMemoryWord(address) : readStateWord(clintIndex);
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
    if (address == CSR_MSTATUS || address == CSR_SSTATUS) return CSR_BASE + 0u;
    if (address == CSR_MEDELEG) return CSR_BASE + 1u;
    if (address == CSR_MIDELEG) return CSR_BASE + 2u;
    if (address == CSR_MIE || address == CSR_SIE) return CSR_BASE + 3u;
    if (address == CSR_MTVEC) return CSR_BASE + 4u;
    if (address == CSR_MSCRATCH) return CSR_BASE + 5u;
    if (address == CSR_MEPC) return CSR_BASE + 6u;
    if (address == CSR_MCAUSE) return CSR_BASE + 7u;
    if (address == CSR_MTVAL) return CSR_BASE + 8u;
    if (address == CSR_MIP || address == CSR_SIP) return CSR_BASE + 9u;
    if (address == CSR_SATP) return CSR_BASE + 10u;
    if (address == CSR_STVEC) return CSR_BASE + 11u;
    if (address == CSR_SSCRATCH) return CSR_BASE + 12u;
    if (address == CSR_SEPC) return CSR_BASE + 13u;
    if (address == CSR_SCAUSE) return CSR_BASE + 14u;
    if (address == CSR_STVAL) return CSR_BASE + 15u;
    return INVALID_INDEX;
}

bool csrSupported(uint address) {
    return csrStateIndex(address) != INVALID_INDEX
        || address == CSR_MISA
        || address == CSR_MCYCLE
        || address == CSR_MINSTRET
        || address == CSR_CYCLE
        || address == CSR_INSTRET
        || address == CSR_MHARTID;
}

bool csrWritable(uint address) {
    return csrStateIndex(address) != INVALID_INDEX;
}

uint csrWriteMask(uint address) {
    if (address == CSR_SSTATUS) return 0x000de162u;
    if (address == CSR_SIE || address == CSR_SIP || address == CSR_MIP) {
        return 0x00000222u;
    }
    return 0xffffffffu;
}

bool csrAccessible(uint address, uint privilege) {
    uint requiredPrivilege = (address >> 8u) & 0x3u;
    return privilege >= requiredPrivilege;
}

uint readCSR(uint address) {
    if (address == CSR_MISA) return 0x40001101u; // RV32IMA
    if (address == CSR_MCYCLE || address == CSR_MINSTRET
            || address == CSR_CYCLE || address == CSR_INSTRET) {
        return readStateWord(CYCLE_INDEX);
    }
    if (address == CSR_MHARTID) return 0u;
    uint index = csrStateIndex(address);
    uint value = index == INVALID_INDEX ? 0u : readStateWord(index);
    if (address == CSR_MIP || address == CSR_SIP) {
        uint machinePending = value & ~0x88u;
        if (readStateWord(CLINT_MSIP_INDEX) != 0u) machinePending |= 0x8u;
        uint timeLow = readStateWord(CLINT_MTIME_LOW_INDEX);
        uint timeHigh = readStateWord(CLINT_MTIME_HIGH_INDEX);
        uint compareLow = readStateWord(CLINT_MTIMECMP_LOW_INDEX);
        uint compareHigh = readStateWord(CLINT_MTIMECMP_HIGH_INDEX);
        if (timeHigh > compareHigh
                || (timeHigh == compareHigh && timeLow >= compareLow)) {
            machinePending |= 0x80u;
        }
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
    if (pteAddress < tableAddress || pteAddress > RAM_BYTES - 4u) {
        return false;
    }

    uint pte = readMemoryWord(pteAddress);
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
        if (pteAddress < tableAddress || pteAddress > RAM_BYTES - 4u) {
            return false;
        }
        pte = readMemoryWord(pteAddress);
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

uint initialProgramWord(uint index) {
    // The bundled program validates RV32IMA, Sv32, CLINT timer delivery,
    // and M/S/U interrupt and exception transitions before U-mode draws.
    if (index == 0u) return 0x01500193u;
    if (index == 1u) return 0x00600213u;
    if (index == 2u) return 0x024182b3u;
    if (index == 3u) return 0x02419333u;
    if (index == 4u) return 0x0241a3b3u;
    if (index == 5u) return 0x0241b433u;
    if (index == 6u) return 0x0241c4b3u;
    if (index == 7u) return 0x0241d533u;
    if (index == 8u) return 0x0241e5b3u;
    if (index == 9u) return 0x0241f633u;
    if (index == 10u) return 0x07e00693u;
    if (index == 11u) return 0x40d29263u;
    if (index == 12u) return 0x40031063u;
    if (index == 13u) return 0x3e039e63u;
    if (index == 14u) return 0x3e041c63u;
    if (index == 15u) return 0x00300713u;
    if (index == 16u) return 0x3ee49863u;
    if (index == 17u) return 0x3ee51663u;
    if (index == 18u) return 0x3ee59463u;
    if (index == 19u) return 0x3ee61263u;
    if (index == 20u) return 0x340297f3u;
    if (index == 21u) return 0x34002873u;
    if (index == 22u) return 0x3c079c63u;
    if (index == 23u) return 0x3c581a63u;
    if (index == 24u) return 0x60000893u;
    if (index == 25u) return 0x00700913u;
    if (index == 26u) return 0x0128a023u;
    if (index == 27u) return 0x1008a9afu;
    if (index == 28u) return 0x00900a13u;
    if (index == 29u) return 0x1948aaafu;
    if (index == 30u) return 0x0008ab03u;
    if (index == 31u) return 0x00700b93u;
    if (index == 32u) return 0x3b799863u;
    if (index == 33u) return 0x3a0a9663u;
    if (index == 34u) return 0x00900b93u;
    if (index == 35u) return 0x3b7b1263u;
    if (index == 36u) return 0x0128ac2fu;
    if (index == 37u) return 0x0008ac83u;
    if (index == 38u) return 0x397c1c63u;
    if (index == 39u) return 0x01000b93u;
    if (index == 40u) return 0x397c9863u;
    if (index == 41u) return 0x46c00d13u;
    if (index == 42u) return 0x305d1073u;
    if (index == 43u) return 0x00000d93u;
    if (index == 44u) return 0x00000073u;
    if (index == 45u) return 0x00100e13u;
    if (index == 46u) return 0x37cd9c63u;
    if (index == 47u) return 0x34202ef3u;
    if (index == 48u) return 0x00b00f13u;
    if (index == 49u) return 0x37ee9663u;
    if (index == 50u) return 0x00102003u;
    if (index == 51u) return 0x00200e13u;
    if (index == 52u) return 0x37cd9063u;
    if (index == 53u) return 0x34202ef3u;
    if (index == 54u) return 0x00400f13u;
    if (index == 55u) return 0x35ee9a63u;
    if (index == 56u) return 0x34302ef3u;
    if (index == 57u) return 0x00100f13u;
    if (index == 58u) return 0x35ee9463u;
    if (index == 59u) return 0x00000d93u;
    if (index == 60u) return 0x020008b7u;
    if (index == 61u) return 0x00100993u;
    if (index == 62u) return 0x0138a023u;
    if (index == 63u) return 0x0008aa03u;
    if (index == 64u) return 0x333a1863u;
    if (index == 65u) return 0x0008a023u;
    if (index == 66u) return 0x020048b7u;
    if (index == 67u) return 0x0200c937u;
    if (index == 68u) return 0xff890913u;
    if (index == 69u) return 0x00092023u;
    if (index == 70u) return 0x00092223u;
    if (index == 71u) return 0x0008a223u;
    if (index == 72u) return 0x00c00993u;
    if (index == 73u) return 0x0138a023u;
    if (index == 74u) return 0x08000a13u;
    if (index == 75u) return 0x304a2073u;
    if (index == 76u) return 0x00800a13u;
    if (index == 77u) return 0x300a2073u;
    if (index == 78u) return 0x00000013u;
    if (index == 79u) return 0x00000013u;
    if (index == 80u) return 0x00000013u;
    if (index == 81u) return 0x00000013u;
    if (index == 82u) return 0x00000013u;
    if (index == 83u) return 0x00000013u;
    if (index == 84u) return 0x00000013u;
    if (index == 85u) return 0x00000013u;
    if (index == 86u) return 0x00100e13u;
    if (index == 87u) return 0x2dcd9a63u;
    if (index == 88u) return 0x34202ef3u;
    if (index == 89u) return 0x80000f37u;
    if (index == 90u) return 0x007f0f13u;
    if (index == 91u) return 0x2dee9263u;
    if (index == 92u) return 0x0000a8b7u;
    if (index == 93u) return 0x0000b937u;
    if (index == 94u) return 0x000039b7u;
    if (index == 95u) return 0xc0198993u;
    if (index == 96u) return 0x4138a023u;
    if (index == 97u) return 0x04b00993u;
    if (index == 98u) return 0x01392023u;
    if (index == 99u) return 0x4c700993u;
    if (index == 100u) return 0x01392223u;
    if (index == 101u) return 0x05900993u;
    if (index == 102u) return 0x01392423u;
    if (index == 103u) return 0x4d700993u;
    if (index == 104u) return 0x01392623u;
    if (index == 105u) return 0x80000d37u;
    if (index == 106u) return 0x00ad0d13u;
    if (index == 107u) return 0x180d1073u;
    if (index == 108u) return 0x12000073u;
    if (index == 109u) return 0x000018b7u;
    if (index == 110u) return 0x02a00a13u;
    if (index == 111u) return 0x0148a023u;
    if (index == 112u) return 0x40001ab7u;
    if (index == 113u) return 0x00021d37u;
    if (index == 114u) return 0x800d0d13u;
    if (index == 115u) return 0x300d1073u;
    if (index == 116u) return 0x000aab03u;
    if (index == 117u) return 0x254b1e63u;
    if (index == 118u) return 0x02b00b93u;
    if (index == 119u) return 0x017aa023u;
    if (index == 120u) return 0x30001073u;
    if (index == 121u) return 0x0008ac03u;
    if (index == 122u) return 0x257c1463u;
    if (index == 123u) return 0x40000d37u;
    if (index == 124u) return 0x4a0d0d13u;
    if (index == 125u) return 0x105d1073u;
    if (index == 126u) return 0x0000bd37u;
    if (index == 127u) return 0x3f7d0d13u;
    if (index == 128u) return 0x302d1073u;
    if (index == 129u) return 0x02000a13u;
    if (index == 130u) return 0x304a2073u;
    if (index == 131u) return 0x303a1073u;
    if (index == 132u) return 0x40000d37u;
    if (index == 133u) return 0x22cd0d13u;
    if (index == 134u) return 0x341d1073u;
    if (index == 135u) return 0x00001d37u;
    if (index == 136u) return 0x802d0d13u;
    if (index == 137u) return 0x300d1073u;
    if (index == 138u) return 0x30200073u;
    if (index == 139u) return 0x00200e13u;
    if (index == 140u) return 0x21cd9a63u;
    if (index == 141u) return 0x14202ef3u;
    if (index == 142u) return 0x80000f37u;
    if (index == 143u) return 0x005f0f13u;
    if (index == 144u) return 0x21ee9263u;
    if (index == 145u) return 0x00000d93u;
    if (index == 146u) return 0x00000073u;
    if (index == 147u) return 0x00100e13u;
    if (index == 148u) return 0x1fcd9a63u;
    if (index == 149u) return 0x14202ef3u;
    if (index == 150u) return 0x00900f13u;
    if (index == 151u) return 0x1fee9463u;
    if (index == 152u) return 0xffffffffu;
    if (index == 153u) return 0x00200e13u;
    if (index == 154u) return 0x1dcd9e63u;
    if (index == 155u) return 0x14202ef3u;
    if (index == 156u) return 0x00200f13u;
    if (index == 157u) return 0x1dee9863u;
    if (index == 158u) return 0x14302ef3u;
    if (index == 159u) return 0xfff00f13u;
    if (index == 160u) return 0x1dee9263u;
    if (index == 161u) return 0x00102003u;
    if (index == 162u) return 0x00300e13u;
    if (index == 163u) return 0x1bcd9c63u;
    if (index == 164u) return 0x14202ef3u;
    if (index == 165u) return 0x00400f13u;
    if (index == 166u) return 0x1bee9663u;
    if (index == 167u) return 0x14302ef3u;
    if (index == 168u) return 0x00100f13u;
    if (index == 169u) return 0x1bee9063u;
    if (index == 170u) return 0x00002123u;
    if (index == 171u) return 0x00400e13u;
    if (index == 172u) return 0x19cd9a63u;
    if (index == 173u) return 0x14202ef3u;
    if (index == 174u) return 0x00600f13u;
    if (index == 175u) return 0x19ee9463u;
    if (index == 176u) return 0x14302ef3u;
    if (index == 177u) return 0x00200f13u;
    if (index == 178u) return 0x17ee9e63u;
    if (index == 179u) return 0x50000d37u;
    if (index == 180u) return 0x000d2003u;
    if (index == 181u) return 0x00500e13u;
    if (index == 182u) return 0x17cd9663u;
    if (index == 183u) return 0x14202ef3u;
    if (index == 184u) return 0x00d00f13u;
    if (index == 185u) return 0x17ee9063u;
    if (index == 186u) return 0x14302ef3u;
    if (index == 187u) return 0x15ae9c63u;
    if (index == 188u) return 0x000d2023u;
    if (index == 189u) return 0x00600e13u;
    if (index == 190u) return 0x15cd9663u;
    if (index == 191u) return 0x14202ef3u;
    if (index == 192u) return 0x00f00f13u;
    if (index == 193u) return 0x15ee9063u;
    if (index == 194u) return 0x14302ef3u;
    if (index == 195u) return 0x13ae9c63u;
    if (index == 196u) return 0x00200d13u;
    if (index == 197u) return 0x000d0067u;
    if (index == 198u) return 0x00700e13u;
    if (index == 199u) return 0x13cd9463u;
    if (index == 200u) return 0x14202ef3u;
    if (index == 201u) return 0x00000f13u;
    if (index == 202u) return 0x11ee9e63u;
    if (index == 203u) return 0x14302ef3u;
    if (index == 204u) return 0x00200f13u;
    if (index == 205u) return 0x11ee9863u;
    if (index == 206u) return 0x40000d37u;
    if (index == 207u) return 0x34cd0d13u;
    if (index == 208u) return 0x140d1073u;
    if (index == 209u) return 0x50000d37u;
    if (index == 210u) return 0x000d0067u;
    if (index == 211u) return 0x00800e13u;
    if (index == 212u) return 0x0fcd9a63u;
    if (index == 213u) return 0x14202ef3u;
    if (index == 214u) return 0x00c00f13u;
    if (index == 215u) return 0x0fee9463u;
    if (index == 216u) return 0x14302ef3u;
    if (index == 217u) return 0x0fae9063u;
    if (index == 218u) return 0x12000073u;
    if (index == 219u) return 0x40003d37u;
    if (index == 220u) return 0x000d2a03u;
    if (index == 221u) return 0x00900e13u;
    if (index == 222u) return 0x0dcd9663u;
    if (index == 223u) return 0x14202ef3u;
    if (index == 224u) return 0x00d00f13u;
    if (index == 225u) return 0x0dee9063u;
    if (index == 226u) return 0x00040cb7u;
    if (index == 227u) return 0x100ca073u;
    if (index == 228u) return 0x000d2a03u;
    if (index == 229u) return 0x0b7a1863u;
    if (index == 230u) return 0x40002d37u;
    if (index == 231u) return 0x3e0d0d13u;
    if (index == 232u) return 0x000d2a03u;
    if (index == 233u) return 0x00a00e13u;
    if (index == 234u) return 0x09cd9e63u;
    if (index == 235u) return 0x14202ef3u;
    if (index == 236u) return 0x00d00f13u;
    if (index == 237u) return 0x09ee9863u;
    if (index == 238u) return 0x00080cb7u;
    if (index == 239u) return 0x100ca073u;
    if (index == 240u) return 0x000d2a03u;
    if (index == 241u) return 0x07300b93u;
    if (index == 242u) return 0x077a1e63u;
    if (index == 243u) return 0x40002d37u;
    if (index == 244u) return 0x3dcd0d13u;
    if (index == 245u) return 0x141d1073u;
    if (index == 246u) return 0x10200073u;
    if (index == 247u) return 0x00000d93u;
    if (index == 248u) return 0x00000073u;
    if (index == 249u) return 0x00100e13u;
    if (index == 250u) return 0x07cd9863u;
    if (index == 251u) return 0x00800e13u;
    if (index == 252u) return 0x07cf1463u;
    if (index == 253u) return 0x40000d37u;
    if (index == 254u) return 0x000d2003u;
    if (index == 255u) return 0x00200e13u;
    if (index == 256u) return 0x05cd9c63u;
    if (index == 257u) return 0x00d00e13u;
    if (index == 258u) return 0x05cf1863u;
    if (index == 259u) return 0x400030b7u;
    if (index == 260u) return 0x00100113u;
    if (index == 261u) return 0x40004337u;
    if (index == 262u) return 0x90030313u;
    if (index == 263u) return 0x0020a023u;
    if (index == 264u) return 0x00408093u;
    if (index == 265u) return 0x00110113u;
    if (index == 266u) return 0xfe60eae3u;
    if (index == 267u) return 0x00100073u;
    if (index == 268u) return 0x000010b7u;
    if (index == 269u) return 0xdeadc137u;
    if (index == 270u) return 0xeef10113u;
    if (index == 271u) return 0x0020a023u;
    if (index == 272u) return 0x00100073u;
    if (index == 273u) return 0x400010b7u;
    if (index == 274u) return 0xdeadc137u;
    if (index == 275u) return 0xeef10113u;
    if (index == 276u) return 0x0020a023u;
    if (index == 277u) return 0x00100073u;
    if (index == 278u) return 0x400030b7u;
    if (index == 279u) return 0xdeadc137u;
    if (index == 280u) return 0xeef10113u;
    if (index == 281u) return 0x0020a023u;
    if (index == 282u) return 0x00100073u;
    if (index == 283u) return 0x34202f73u;
    if (index == 284u) return 0x000f4c63u;
    if (index == 285u) return 0x001d8d93u;
    if (index == 286u) return 0x34102ff3u;
    if (index == 287u) return 0x004f8f93u;
    if (index == 288u) return 0x341f9073u;
    if (index == 289u) return 0x30200073u;
    if (index == 290u) return 0x001d8d93u;
    if (index == 291u) return 0x08000f93u;
    if (index == 292u) return 0x304fb073u;
    if (index == 293u) return 0x02000f93u;
    if (index == 294u) return 0x344fa073u;
    if (index == 295u) return 0x30200073u;
    if (index == 296u) return 0x14202f73u;
    if (index == 297u) return 0x020f4663u;
    if (index == 298u) return 0x001d8d93u;
    if (index == 299u) return 0x00c00f93u;
    if (index == 300u) return 0x01ff1863u;
    if (index == 301u) return 0x14002ff3u;
    if (index == 302u) return 0x141f9073u;
    if (index == 303u) return 0x10200073u;
    if (index == 304u) return 0x14102ff3u;
    if (index == 305u) return 0x004f8f93u;
    if (index == 306u) return 0x141f9073u;
    if (index == 307u) return 0x10200073u;
    if (index == 308u) return 0x001d8d93u;
    if (index == 309u) return 0x02000f93u;
    if (index == 310u) return 0x144fb073u;
    if (index == 311u) return 0x10200073u;
    return 0u;
}
uint initialWord(uint index) {
    if (index == MAGIC_INDEX) return MAGIC_VALUE;
    if (index == PC_INDEX) return 0u;
    if (index == CYCLE_INDEX) return 0u;
    if (index == STATUS_INDEX) return STATUS_RUNNING;
    if (index == PRIVILEGE_INDEX) return PRIVILEGE_MACHINE;
    if (index == CLINT_MTIMECMP_LOW_INDEX
            || index == CLINT_MTIMECMP_HIGH_INDEX) return 0xffffffffu;
    if (index >= CSR_BASE && index < REGISTER_BASE) return 0u;
    if (index >= REGISTER_BASE && index < REGISTER_BASE + 32u) return 0u;
    return initialProgramWord(index);
}

void main() {
    uvec2 outputSize = uvec2(OutSize + 0.5);
    uvec2 pixel = min(uvec2(texCoord * OutSize), outputSize - uvec2(1u));
    uint outputIndex = pixel.y * TEXTURE_WIDTH + pixel.x;

    if (readStateWord(MAGIC_INDEX) != MAGIC_VALUE) {
        fragColor = encodeWord(initialWord(outputIndex));
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

    uint nextPc = pc + 4u;
    uint nextStatus = STATUS_RUNNING;
    bool writeRegister = false;
    uint destinationRegister = 0u;
    uint registerValue = 0u;
    bool writeMemory = false;
    uint memoryAddress = 0u;
    uint memoryWidth = 0u;
    uint memoryValue = 0u;
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
    bool fetchInRange = fetchTranslated && instructionAddress <= RAM_BYTES - 4u;
    uint instruction = fetchInRange ? readMemoryWord(instructionAddress) : 0u;

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
            bool inRange = translated && physicalAccessValid(physicalAddress, width);

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
            }
        } else if (opcode == 0x23u) { // Stores
            uint address = source1 + immediateS;
            uint width = funct3 == 0u ? 1u : funct3 == 1u ? 2u : funct3 == 2u ? 4u : 0u;
            bool aligned = width == 1u || (width == 2u && (address & 1u) == 0u)
                         || (width == 4u && (address & 3u) == 0u);
            uint physicalAddress = 0u;
            bool translated = width > 0u && aligned
                && translateAddress(address, ACCESS_STORE, dataPrivilege, physicalAddress);
            bool inRange = translated && physicalAccessValid(physicalAddress, width);

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
            bool inRange = translated && physicalAddress <= RAM_BYTES - 4u;

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

    if (writeMemory) {
        nextReservationValid = 0u;
    }

    uint outputWord = currentWord;
    uint currentTimeLow = readStateWord(CLINT_MTIME_LOW_INDEX);
    uint nextTimeLow = currentTimeLow + 1u;
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

    if (writeMemory && memoryAddress < RAM_BYTES
            && outputIndex == (memoryAddress >> 2u)) {
        uint shift = (memoryAddress & 3u) * 8u;
        if (memoryWidth == 1u) {
            uint mask = 0xffu << shift;
            outputWord = (currentWord & ~mask) | ((memoryValue << shift) & mask);
        } else if (memoryWidth == 2u) {
            uint mask = 0xffffu << shift;
            outputWord = (currentWord & ~mask) | ((memoryValue << shift) & mask);
        } else {
            outputWord = memoryValue;
        }
    }
    uint clintWriteIndex = clintStateIndex(memoryAddress);
    if (writeMemory && memoryWidth == 4u
            && clintWriteIndex != INVALID_INDEX && outputIndex == clintWriteIndex) {
        outputWord = memoryValue;
    }

    fragColor = encodeWord(outputWord);
}
