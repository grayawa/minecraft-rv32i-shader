# Third-party software

The Linux profile contains build artifacts and architecture work from the following upstream projects. The links identify the exact source revisions used by the imported assets.

## PiMaker/rvc

- Source: [PiMaker/rvc at `da936a719b4254e91ba422361d7c1d1d0e775b8f`](https://github.com/pimaker/rvc/tree/da936a719b4254e91ba422361d7c1d1d0e775b8f)
- License: MIT
- Local license copy: [`third_party/rvc/LICENSE`](third_party/rvc/LICENSE)

rvc supplies the integer-texture CPU architecture, HLSL execution model, Linux guest build, split-channel payload textures, device tree, and ROMFS image. The Minecraft adapter supplies the GLSL 330 implementation, Post Effect pass graph, RGBA8 persistent targets, dashboard, resource-pack lifecycle, and validation tools.

## OpenSBI

- Source: [riscv-software-src/opensbi at `7aa6c9aa96049b741b754b7340ea96a37719de27`](https://github.com/riscv-software-src/opensbi/tree/7aa6c9aa96049b741b754b7340ea96a37719de27)
- Version reported by the firmware: OpenSBI v0.9
- License: BSD-2-Clause
- Local license copy: [`third_party/opensbi/COPYING.BSD`](third_party/opensbi/COPYING.BSD)

The imported `guest_linux.png` contains the OpenSBI generic platform firmware and its Linux payload. The importer changes one firmware instruction so the next-stage DTB remains at the physical address supplied through `a1`.

## Linux kernel

- Source: [PiMaker/linux-rvc at `0bd94b14f8b6b838bbd48e5c204e819df621e659`](https://github.com/pimaker/linux-rvc/tree/0bd94b14f8b6b838bbd48e5c204e819df621e659)
- Version reported by the kernel: Linux 5.17.11-rvc+
- License: GPL-2.0 WITH Linux-syscall-note
- Local notice: [`third_party/linux/COPYING`](third_party/linux/COPYING)
- Full license text: [Linux `GPL-2.0`](https://github.com/pimaker/linux-rvc/blob/0bd94b14f8b6b838bbd48e5c204e819df621e659/LICENSES/preferred/GPL-2.0)

The kernel image forms the payload starting at physical address `0x80400000`.

## Buildroot ROMFS

- Build system: Buildroot 2022.02.1
- Configuration: [rvc `buildroot-config`](https://github.com/pimaker/rvc/blob/da936a719b4254e91ba422361d7c1d1d0e775b8f/buildroot-config)
- Build recipe: [rvc `Makefile`](https://github.com/pimaker/rvc/blob/da936a719b4254e91ba422361d7c1d1d0e775b8f/Makefile)

`mtd_linux.png` contains a 56,471,216-byte ROMFS based on the rvc Buildroot image. The project importer installs the project `rvcinit` script and Fibonacci ELF into the image. Buildroot package recipes record the source version and license metadata for each selected userspace component. The fixed rvc revision contains the configuration and guest overlay used to reproduce the base filesystem.

## Specifications and Minecraft format

Instruction semantics follow the RISC-V RV32I, RV32M, RV32A, Zicsr and privileged architecture specifications. Minecraft Post Effect files target Java Edition 26.3-snapshot-5 and Resource Pack 93.0.
