"""Pack a flat little-endian guest image into an RGBA8 post-effect texture."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def encode_guest_texture(data: bytes, width: int, height: int) -> bytes:
    capacity = width * height * 4
    if len(data) > capacity:
        raise ValueError(f"guest image uses {len(data)} bytes; texture capacity is {capacity}")

    pixels = data + bytes(capacity - len(data))
    stride = width * 4
    scanlines = b"".join(
        b"\x00" + pixels[offset : offset + stride]
        for offset in range(0, len(pixels), stride)
    )
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"".join(
        (
            PNG_SIGNATURE,
            png_chunk(b"IHDR", header),
            png_chunk(b"IDAT", zlib.compress(scanlines, level=9)),
            png_chunk(b"IEND", b""),
        )
    )


def decode_guest_texture(png: bytes) -> tuple[int, int, bytes]:
    if not png.startswith(PNG_SIGNATURE):
        raise ValueError("guest texture must use PNG encoding")

    offset = len(PNG_SIGNATURE)
    width = height = 0
    compressed = bytearray()
    while offset < len(png):
        length = struct.unpack_from(">I", png, offset)[0]
        kind = png[offset + 4 : offset + 8]
        payload = png[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if (depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("guest texture must use non-interlaced RGBA8 pixels")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break

    stride = width * 4
    raw = zlib.decompress(compressed)
    if len(raw) != height * (stride + 1):
        raise ValueError("guest texture scanline size is invalid")
    rows = []
    for row in range(height):
        start = row * (stride + 1)
        if raw[start] != 0:
            raise ValueError("guest texture PNG row filter must be zero")
        rows.append(raw[start + 1 : start + 1 + stride])
    return width, height, b"".join(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="flat guest image loaded at physical address zero")
    parser.add_argument("output", type=Path, help="output PNG under assets/<namespace>/textures/effect")
    parser.add_argument("--width", type=int, default=128)
    parser.add_argument("--height", type=int, default=128)
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        parser.error("texture dimensions must be positive")
    binary = args.binary.read_bytes()
    encoded = encode_guest_texture(binary, args.width, args.height)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(encoded)
    print(f"{args.output}: {args.width}x{args.height}, {len(binary)} guest bytes")


if __name__ == "__main__":
    main()
