# Third-party software

The GPU state-machine architecture and the RV32M/RV32A/CSR/trap execution behavior are derived from [PiMaker/rvc](https://github.com/pimaker/rvc), an MIT-licensed RISC-V emulator written in C and HLSL. The upstream project demonstrates integer-texture CPU state, parallel pixel updates, privileged execution, virtual memory, and shader-hosted Linux.

The Minecraft adapter uses a dedicated RGBA8 state layout, GLSL 330 arithmetic, Post Effect pass graph, framebuffer dashboard, resource-pack lifecycle, and validation tools. The upstream license is included at [`third_party/rvc/LICENSE`](third_party/rvc/LICENSE).

Instruction behavior follows the RISC-V RV32I, RV32M, RV32A, Zicsr and privileged architecture specifications.
