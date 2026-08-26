# Third-party inspiration

The GPU state-machine architecture is inspired by [PiMaker/rvc](https://github.com/pimaker/rvc), an MIT-licensed RISC-V emulator written in C and HLSL. That project demonstrates integer-texture CPU state, parallel pixel updates, and shader-hosted machine emulation.

This repository contains an independent GLSL implementation for Minecraft's Post Effect pipeline. Its state layout, RV32I decoder, memory environment, framebuffer, dashboard, resource-pack integration, and validation tools are specific to this project.

The instruction behavior follows the [RISC-V RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20240411/unpriv/rv32.html).
