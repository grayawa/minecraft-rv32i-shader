"""Import PiMaker/rvc split-channel Linux assets into MCRV textures."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from bin_to_texture import encode_guest_texture


GUEST_WIDTH = 2048
GUEST_HEIGHT = 1024
MTD_WIDTH = 4096
MTD_HEIGHT = 3447
DTB_WIDTH = 1024
DTB_HEIGHT = 1
LINUX_LOAD_ADDRESS = 0x80000000
LINUX_DTB_ADDRESS = 0x1020
UPSTREAM_MEMORY_BYTES = 0x07B00000
MCRV_MEMORY_BYTES = 0x00BFF000
OPENSBI_NEXT_DTB_ADDRESS_OFFSET = 0x8F0
OPENSBI_NEXT_DTB_ADDRESS = bytes.fromhex("37052082")
OPENSBI_KEEP_DTB_ADDRESS = bytes.fromhex("13850500")


def decode_split_texture(directory: Path, stem: str) -> bytes:
    images = [
        Image.open(directory / f"{stem}.{channel}.png").convert("RGBA")
        for channel in "rgba"
    ]
    dimensions = {image.size for image in images}
    if len(dimensions) != 1:
        raise ValueError(f"{stem} channel textures must share dimensions")

    channels = [image.tobytes() for image in images]
    output = bytearray()
    for offset in range(0, len(channels[0]), 4):
        for channel in channels:
            output.extend(channel[offset : offset + 4])
    return bytes(output)


def trim_word_padding(data: bytes) -> bytes:
    last = max((index for index, value in enumerate(data) if value), default=-1)
    return data[: (last + 4) & ~3]


def patch_linux_dtb(dtb: bytes) -> bytes:
    total_size = int.from_bytes(dtb[4:8], "big")
    dtb = dtb[:total_size]
    source = UPSTREAM_MEMORY_BYTES.to_bytes(4, "big")
    target = MCRV_MEMORY_BYTES.to_bytes(4, "big")
    if dtb.count(source) != 1:
        raise ValueError("upstream DTB memory size marker must occur once")
    return dtb.replace(source, target)


def patch_opensbi_payload(payload: bytes) -> bytes:
    """Keep the boot DTB at the physical address supplied through a1."""
    start = OPENSBI_NEXT_DTB_ADDRESS_OFFSET
    end = start + len(OPENSBI_NEXT_DTB_ADDRESS)
    if payload[start:end] != OPENSBI_NEXT_DTB_ADDRESS:
        raise ValueError("OpenSBI DTB destination instruction does not match rvc")
    patched = bytearray(payload)
    patched[start:end] = OPENSBI_KEEP_DTB_ADDRESS
    return bytes(patched)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rvc", type=Path, help="PiMaker/rvc checkout at commit da936a7")
    parser.add_argument("project", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()

    project = args.project.resolve()
    effect = project / "assets" / "mcrv" / "textures" / "effect"
    programs = project / "programs"
    effect.mkdir(parents=True, exist_ok=True)
    programs.mkdir(parents=True, exist_ok=True)

    payload = patch_opensbi_payload(
        trim_word_padding(decode_split_texture(args.rvc, "linux_payload"))
    )
    linux_texture = encode_guest_texture(
        payload,
        GUEST_WIDTH,
        GUEST_HEIGHT,
        load_address=LINUX_LOAD_ADDRESS,
        entry_point=LINUX_LOAD_ADDRESS,
        dtb_address=LINUX_DTB_ADDRESS,
    )
    (effect / "guest_linux.png").write_bytes(linux_texture)

    upstream_dtb = decode_split_texture(args.rvc, "dts")
    dtb = patch_linux_dtb(upstream_dtb)
    (programs / "rvc-linux.dtb").write_bytes(dtb)
    (effect / "dtb_rvc_linux.png").write_bytes(
        encode_guest_texture(dtb, DTB_WIDTH, DTB_HEIGHT, boot_descriptor=False)
    )

    rootfs_directory = args.rvc / "_Nix" / "rvc" / "data-net"
    rootfs = decode_split_texture(rootfs_directory, "rootfs")
    if rootfs[:8] != b"-rom1fs-":
        raise ValueError("rootfs image must use ROMFS encoding")
    rootfs_size = int.from_bytes(rootfs[8:12], "big")
    rootfs = rootfs[:rootfs_size]
    (effect / "mtd_linux.png").write_bytes(
        encode_guest_texture(rootfs, MTD_WIDTH, MTD_HEIGHT, boot_descriptor=False)
    )

    empty_mtd = encode_guest_texture(
        b"", MTD_WIDTH, MTD_HEIGHT, boot_descriptor=False
    )
    (effect / "mtd_empty.png").write_bytes(empty_mtd)

    print(f"guest_linux.png: {len(payload)} payload bytes")
    print(
        f"dtb_rvc_linux.png: {len(dtb)} DTB bytes, "
        f"{MCRV_MEMORY_BYTES} guest RAM bytes"
    )
    print(f"mtd_linux.png: {len(rootfs)} ROMFS bytes")


if __name__ == "__main__":
    main()
