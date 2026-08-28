"""Patch regular files in a ROMFS image while preserving its directory graph."""

from __future__ import annotations

import struct


ROMFS_MAGIC = b"-rom1fs-"
ROMFS_REGULAR = 2
ROMFS_EXECUTABLE = 8


def align16(value: int) -> int:
    return (value + 15) & ~15


def checksum(data: bytes) -> int:
    padded = data + bytes((-len(data)) & 3)
    words = struct.unpack(f">{len(padded) // 4}I", padded)
    return sum(words) & 0xFFFFFFFF


def header_name_end(image: bytes | bytearray, offset: int) -> int:
    terminator = image.index(0, offset + 16)
    return align16(terminator + 1)


def entry_name(image: bytes | bytearray, offset: int) -> str:
    terminator = image.index(0, offset + 16)
    return bytes(image[offset + 16 : terminator]).decode("utf-8")


def update_header_checksum(image: bytearray, offset: int) -> None:
    end = header_name_end(image, offset)
    struct.pack_into(">I", image, offset + 12, 0)
    value = (-checksum(image[offset:end])) & 0xFFFFFFFF
    struct.pack_into(">I", image, offset + 12, value)


def root_entries(image: bytes | bytearray) -> list[int]:
    volume_end = align16(image.index(0, 16) + 1)
    root_offset = volume_end
    child_offset = struct.unpack_from(">I", image, root_offset + 4)[0]
    entries: list[int] = []
    while child_offset:
        entries.append(child_offset)
        child_offset = struct.unpack_from(">I", image, child_offset)[0] & ~15
    return entries


def patch_rootfs(rootfs: bytes, rvcinit: bytes, fibonacci: bytes) -> bytes:
    """Install the project init script and executable at the ROMFS root."""
    if rootfs[:8] != ROMFS_MAGIC:
        raise ValueError("rootfs image must use ROMFS encoding")
    full_size = struct.unpack_from(">I", rootfs, 8)[0]
    image = bytearray(rootfs[:full_size])
    entries = root_entries(image)
    named = {entry_name(image, offset): offset for offset in entries}

    init_offset = named["rvcinit"]
    init_data_offset = header_name_end(image, init_offset)
    init_size = struct.unpack_from(">I", image, init_offset + 8)[0]
    init_capacity = align16(init_size)
    if len(rvcinit) > init_capacity:
        raise ValueError("project rvcinit exceeds the source ROMFS allocation")
    struct.pack_into(">I", image, init_offset + 8, len(rvcinit))
    image[init_data_offset : init_data_offset + init_capacity] = (
        rvcinit + bytes(init_capacity - len(rvcinit))
    )
    update_header_checksum(image, init_offset)

    fibonacci_offset = align16(len(image))
    image.extend(bytes(fibonacci_offset - len(image)))
    name = b"fibonacci\0"
    name_area = name + bytes(align16(16 + len(name)) - 16 - len(name))
    header = bytearray(struct.pack(
        ">4I", ROMFS_REGULAR | ROMFS_EXECUTABLE, 0, len(fibonacci), 0
    ) + name_area)
    header_checksum = (-checksum(header)) & 0xFFFFFFFF
    struct.pack_into(">I", header, 12, header_checksum)
    image.extend(header)
    image.extend(fibonacci)
    image.extend(bytes(align16(len(image)) - len(image)))

    last_offset = entries[-1]
    last_info = struct.unpack_from(">I", image, last_offset)[0] & 15
    struct.pack_into(">I", image, last_offset, fibonacci_offset | last_info)
    update_header_checksum(image, last_offset)

    struct.pack_into(">I", image, 8, len(image))
    struct.pack_into(">I", image, 12, 0)
    superblock_end = min(512, len(image))
    superblock_checksum = (-checksum(image[:superblock_end])) & 0xFFFFFFFF
    struct.pack_into(">I", image, 12, superblock_checksum)

    if checksum(image[:superblock_end]) != 0:
        raise AssertionError("ROMFS superblock checksum mismatch")
    return bytes(image)
