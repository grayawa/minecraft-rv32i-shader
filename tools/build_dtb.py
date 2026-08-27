"""Build the deterministic flattened device tree for the MCRV shader platform."""

from __future__ import annotations

import argparse
import struct
from dataclasses import dataclass, field
from pathlib import Path


FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_END = 9


def align4(data: bytes) -> bytes:
    return data + bytes((-len(data)) % 4)


@dataclass(frozen=True)
class Property:
    name: str
    data: bytes
    source: str | None


@dataclass
class Node:
    name: str
    label: str | None = None
    properties: list[Property] = field(default_factory=list)
    children: list["Node"] = field(default_factory=list)


def string_property(name: str, *values: str) -> Property:
    data = b"".join(value.encode("ascii") + b"\0" for value in values)
    source = ", ".join(f'"{value}"' for value in values)
    return Property(name, data, source)


def cell_property(name: str, *values: int, source: str | None = None) -> Property:
    data = struct.pack(f">{len(values)}I", *values)
    rendered = source or "<" + " ".join(f"0x{value:x}" for value in values) + ">"
    return Property(name, data, rendered)


def empty_property(name: str) -> Property:
    return Property(name, b"", None)


def platform_tree() -> Node:
    cpu_intc = Node(
        "interrupt-controller",
        label="cpu_intc",
        properties=[
            cell_property("#interrupt-cells", 1),
            empty_property("interrupt-controller"),
            string_property("compatible", "riscv,cpu-intc"),
            cell_property("phandle", 1),
        ],
    )
    cpu = Node(
        "cpu@0",
        properties=[
            string_property("device_type", "cpu"),
            cell_property("reg", 0),
            string_property("status", "okay"),
            string_property("compatible", "riscv"),
            string_property("riscv,isa", "rv32imasu"),
            string_property("mmu-type", "riscv,sv32"),
        ],
        children=[cpu_intc],
    )
    cpus = Node(
        "cpus",
        properties=[
            cell_property("#address-cells", 1),
            cell_property("#size-cells", 0),
            cell_property("timebase-frequency", 120),
        ],
        children=[cpu],
    )
    memory = Node(
        "memory@80000000",
        properties=[
            string_property("device_type", "memory"),
            cell_property("reg", 0, 0x80000000, 0, 0x000FFFFC),
        ],
    )
    clint = Node(
        "clint@2000000",
        properties=[
            string_property("compatible", "riscv,clint0"),
            cell_property("reg", 0, 0x02000000, 0, 0x00010000),
            cell_property(
                "interrupts-extended", 1, 3, 1, 7,
                source="<&cpu_intc 0x3 &cpu_intc 0x7>",
            ),
        ],
    )
    plic = Node(
        "plic@c000000",
        label="plic",
        properties=[
            cell_property("#address-cells", 0),
            cell_property("#interrupt-cells", 1),
            empty_property("interrupt-controller"),
            string_property("compatible", "sifive,plic-1.0.0", "riscv,plic0"),
            cell_property("reg", 0, 0x0C000000, 0, 0x04000000),
            cell_property(
                "interrupts-extended", 1, 11, 1, 9,
                source="<&cpu_intc 0xb &cpu_intc 0x9>",
            ),
            cell_property("riscv,ndev", 10),
            cell_property("phandle", 2),
        ],
    )
    uart = Node(
        "uart@10000000",
        label="uart0",
        properties=[
            string_property("compatible", "ns16550a"),
            cell_property("reg", 0, 0x10000000, 0, 0x100),
            cell_property("clock-frequency", 3_686_400),
            cell_property("current-speed", 115_200),
            cell_property("interrupt-parent", 2, source="<&plic>"),
            cell_property("interrupts", 10),
            cell_property("reg-shift", 0),
            cell_property("reg-io-width", 1),
        ],
    )
    soc = Node(
        "soc",
        properties=[
            cell_property("#address-cells", 2),
            cell_property("#size-cells", 2),
            string_property("compatible", "simple-bus"),
            empty_property("ranges"),
        ],
        children=[clint, plic, uart],
    )
    return Node(
        "",
        properties=[
            cell_property("#address-cells", 2),
            cell_property("#size-cells", 2),
            string_property("compatible", "minecraft,mcrv", "riscv-virtio"),
            string_property("model", "Minecraft Postprocess RV32IMA"),
        ],
        children=[
            Node("aliases", properties=[string_property("serial0", "/soc/uart@10000000")]),
            Node(
                "chosen",
                properties=[
                    string_property(
                        "bootargs",
                        "console=ttyS0 earlycon=uart8250,mmio,0x10000000",
                    ),
                    string_property("stdout-path", "/soc/uart@10000000"),
                ],
            ),
            cpus,
            memory,
            soc,
        ],
    )


def collect_strings(node: Node, offsets: dict[str, int], data: bytearray) -> None:
    for prop in node.properties:
        if prop.name not in offsets:
            offsets[prop.name] = len(data)
            data.extend(prop.name.encode("ascii") + b"\0")
    for child in node.children:
        collect_strings(child, offsets, data)


def encode_node(node: Node, string_offsets: dict[str, int]) -> bytes:
    output = bytearray(struct.pack(">I", FDT_BEGIN_NODE))
    output.extend(align4(node.name.encode("ascii") + b"\0"))
    for prop in node.properties:
        output.extend(struct.pack(">III", FDT_PROP, len(prop.data), string_offsets[prop.name]))
        output.extend(align4(prop.data))
    for child in node.children:
        output.extend(encode_node(child, string_offsets))
    output.extend(struct.pack(">I", FDT_END_NODE))
    return bytes(output)


def build_dtb(root: Node | None = None) -> bytes:
    root = root or platform_tree()
    string_offsets: dict[str, int] = {}
    strings = bytearray()
    collect_strings(root, string_offsets, strings)
    structure = encode_node(root, string_offsets) + struct.pack(">I", FDT_END)

    reserve_map = bytes(16)
    header_size = 40
    reserve_offset = header_size
    structure_offset = reserve_offset + len(reserve_map)
    strings_offset = structure_offset + len(structure)
    total_size = strings_offset + len(strings)
    header = struct.pack(
        ">10I",
        FDT_MAGIC,
        total_size,
        structure_offset,
        strings_offset,
        reserve_offset,
        17,
        16,
        0,
        len(strings),
        len(structure),
    )
    return header + reserve_map + structure + bytes(strings)


def render_dts_node(node: Node, depth: int = 0) -> list[str]:
    indent = "    " * depth
    label = f"{node.label}: " if node.label else ""
    name = "/" if depth == 0 else node.name
    lines = [f"{indent}{label}{name} {{"]
    for prop in node.properties:
        if prop.source is None:
            lines.append(f"{indent}    {prop.name};")
        else:
            lines.append(f"{indent}    {prop.name} = {prop.source};")
    if node.properties and node.children:
        lines.append("")
    for index, child in enumerate(node.children):
        lines.extend(render_dts_node(child, depth + 1))
        if index + 1 < len(node.children):
            lines.append("")
    lines.append(f"{indent}}};")
    return lines


def render_dts(root: Node | None = None) -> str:
    root = root or platform_tree()
    return "/dts-v1/;\n\n" + "\n".join(render_dts_node(root)) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="output DTB path")
    parser.add_argument("--dts-output", type=Path, help="optional readable DTS path")
    args = parser.parse_args()

    tree = platform_tree()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_dtb(tree))
    if args.dts_output:
        args.dts_output.parent.mkdir(parents=True, exist_ok=True)
        args.dts_output.write_text(render_dts(tree), encoding="utf-8", newline="\n")
    print(f"{args.output}: {args.output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
