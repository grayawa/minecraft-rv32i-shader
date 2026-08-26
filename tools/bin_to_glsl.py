"""Convert a little-endian RV32 binary into initialProgramWord GLSL cases."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="flat RV32 binary loaded at address zero")
    args = parser.parse_args()

    data = args.binary.read_bytes()
    padding = (-len(data)) % 4
    data += bytes(padding)

    print("uint initialProgramWord(uint index) {")
    for index in range(len(data) // 4):
        word = struct.unpack_from("<I", data, index * 4)[0]
        print(f"    if (index == {index}u) return 0x{word:08x}u;")
    print("    return 0u;")
    print("}")


if __name__ == "__main__":
    main()
