# Minecraft RV32IMA Shader

一个完全运行在 Minecraft Java Edition Postprocess Shader 中的 32 位 RISC-V 模拟器。当前核心覆盖 RV32IMA、Zicsr、M/S/U 特权级、Sv32 虚拟内存、同步异常 delegation 和 trap 返回路径。

CPU、寄存器、PC、RAM、CSR、显存和执行状态全部保存在两个 128 × 128 persistent render target 中。两个 GPU pass 在每个画面帧完成两条 RISC-V 指令，显示 pass 将机器状态与 32 × 18 显存合成为屏幕仪表盘。

## 特性

- RV32I Base Integer Instruction Set 2.1 的 40 条基础指令
- RV32M 的八条乘除法指令
- RV32A 的十一条 32 位原子指令
- Zicsr 的六种 CSR 读写指令
- M-mode 与 S-mode CSR bank
- `ECALL` 与内存/指令异常的同步 trap entry
- `medeleg` delegation、`MRET` 与 `SRET`
- Sv32 两级页表遍历、4 KiB 页面与 4 MiB superpage
- R/W/X/U/A/D、`SUM`、`MXR` 权限检查
- `MPRV` 数据访问有效特权级
- instruction/load/store page fault 与 `SFENCE.VMA`
- 32 个 32 位整数寄存器与硬连线零寄存器 `x0`
- 32 位程序计数器与周期计数器
- 65,264 字节小端 RAM
- 8 位、16 位和 32 位 load/store
- 自然对齐访问与标准 `cause`/`tval` 异常元数据
- 32 × 18 单词显存，基地址为 `0x00001000`
- 约 120 指令/秒的 60 FPS 默认执行速度
- PC、周期、状态、`x1`–`x8`、显存与 RAM 活动仪表盘
- 内置 RV32IMA、CSR、trap 自检与显存填充程序
- 平面 RV32 binary 到 GLSL ROM 的转换工具
- 原版资源包运行方式

## 运行环境

当前资源包面向 **Minecraft Java Edition 26.3-snapshot-5**，对应 Resource Pack 93.0。

安装步骤：

1. 下载 [`MinecraftRV32IShader-26.3-snapshot-5.zip`](dist/MinecraftRV32IShader-26.3-snapshot-5.zip)。
2. 将 ZIP 放入当前 Minecraft 实例的 `resourcepacks` 目录。
3. 在“选项 → 资源包”中启用 **Minecraft RV32IMA**。
4. 进入具有命令权限的世界。
5. 执行：

   ```mcfunction
   /posteffect add @s mcrv:rv32i
   ```

关闭模拟器：

```mcfunction
/posteffect remove @s mcrv:rv32i
```

重新启动 CPU 时，依次执行 `remove` 和 `add` 命令。窗口尺寸变化也会重新初始化 persistent target。

## 内置程序

内置程序首先验证八条 RV32M 指令、CSR、LR/SC reservation 和 `AMOADD.W`。M-mode 随后在物理地址 `0xA000` 和 `0xB000` 建立两级 Sv32 页表。页表为物理代码页和显存页分别建立 supervisor 与 user 虚拟别名：

| 虚拟页 | 物理页 | 权限 | 用途 |
| --- | --- | --- | --- |
| `0x40000000` | `0x00000000` | S: R-X | supervisor 代码与 trap handler |
| `0x40001000` | `0x00001000` | S: RW- | supervisor 数据 |
| `0x40002000` | `0x00000000` | U: --X | user 代码 |
| `0x40003000` | `0x00001000` | U: RW- | user framebuffer |

M-mode 通过 `MPRV` 访问 supervisor 数据映射，随后以 `MRET` 进入 S-mode。S-mode 自检覆盖同步异常 delegation、`SUM` user-page 数据访问和 `MXR` execute-only 页读取，再以 `SRET` 进入 U-mode。U-mode 通过 `ECALL` 和权限 page fault 往返 S-mode，最后执行虚拟显存填充循环：

```asm
lui   x1, 0x40003
addi  x2, x0, 1
lui   x6, 0x40004
addi  x6, x6, -1792

fill_framebuffer:
sw    x2, 0(x1)
addi  x1, x1, 4
addi  x2, x2, 1
bltu  x1, x6, fill_framebuffer
ebreak
```

U-mode 通过虚拟地址 `0x40003000`–`0x400038ff` 向物理显存 `0x1000`–`0x18ff` 写入 `1`–`576`，完成 576 个显存单元后以 EBREAK 结束。整个过程执行 2632 条指令。三种特权级各自的验证失败路径会将 `0xDEADBEEF` 写入首个显存单元并进入 EBREAK。

## 指令范围

| 类别 | 指令 |
| --- | --- |
| Upper immediate | `LUI`, `AUIPC` |
| Jump | `JAL`, `JALR` |
| Branch | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Load | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Store | `SB`, `SH`, `SW` |
| Immediate ALU | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| Register ALU | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Multiply/divide | `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU` |
| Atomic | `LR.W`, `SC.W`, `AMOSWAP.W`, `AMOADD.W`, `AMOXOR.W`, `AMOAND.W`, `AMOOR.W`, `AMOMIN.W`, `AMOMAX.W`, `AMOMINU.W`, `AMOMAXU.W` |
| CSR | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI` |
| Environment | `FENCE`, `FENCE.I`, `ECALL`, `EBREAK`, `MRET`, `SRET`, `SFENCE.VMA` |

CSR bank 包含 `mstatus`、`medeleg`、`mideleg`、`mie`、`mtvec`、`mscratch`、`mepc`、`mcause`、`mtval`、`mip`、`sstatus`、`sie`、`stvec`、`sscratch`、`sepc`、`scause`、`stval`、`sip` 和 `satp`。`sstatus`、`sie` 与 `sip` 作为对应机器 CSR 的掩码视图。`misa` 返回 RV32IMA 能力位，周期计数器和 hart ID 通过对应 CSR 读取。机器状态区保存当前特权级与 LR/SC reservation。

当前执行环境覆盖 M/S/U 特权级、Sv32 页表遍历、`MPRV`、`SUM`、`MXR`，以及异常原因 `0`、`1`、`2`、`4`–`9`、`11`–`13`、`15` 的 trap entry。Linux 启动路径的下一层包括 CLINT、timer interrupt、外部中断和 UART。

## 纹理机器布局

RGBA8 状态纹理的每个像素保存一个小端 32 位单词：

```text
R = bits  7..0
G = bits 15..8
B = bits 23..16
A = bits 31..24
```

128 × 128 纹理包含 16,384 个单词：

| 单词索引 | 内容 |
| --- | --- |
| `0`–`16315` | RAM，字节地址 `0x00000000`–`0x0000feef` |
| `16316`–`16347` | CSR、特权级与 atomic reservation 状态 |
| `16348`–`16379` | `x0`–`x31` |
| `16380` | CPU 状态 |
| `16381` | 周期计数器 |
| `16382` | PC |
| `16383` | 初始化魔数 `0x52563332` |

双缓冲执行流程：

```text
state_a → RISC-V tick → state_b → RISC-V tick → state_a → dashboard
```

每个片元读取同一条指令、源寄存器与相关内存。输出坐标决定该片元负责 RAM 单词、目标寄存器或 CPU 元数据。这个结构将一次指令提交表达为整张纹理的并行状态转换。

## CPU 状态码

| 值 | 状态 |
| --- | --- |
| `0` | Running |
| `1` | EBREAK |

同步异常通过 M/S trap handler 继续执行，U-mode 委托异常进入 S-mode。原因和附加值分别保存在 `mcause`/`mtval` 或 `scause`/`stval`。仪表盘指示灯以绿色表示运行、金色表示 EBREAK。

## 加载自己的程序

模拟器从物理字节地址零开始执行平面 RV32 binary。M-mode 可以配置 `satp`，通过 `MRET` 进入 S-mode，再通过 `SRET` 进入 U-mode。物理 RAM 范围为 `0x00000000`–`0x0000feef`。

转换 binary：

```powershell
python tools/bin_to_glsl.py program.bin
```

命令输出一个 `initialProgramWord` GLSL 函数。使用输出内容替换 [`rv32_step.fsh`](assets/mcrv/shaders/post/rv32_step.fsh) 中的同名函数，然后重新打包资源包。

构建 ZIP：

```powershell
powershell -ExecutionPolicy Bypass -File tools/package.ps1
```

## 验证

参考执行测试会重建内置机器码，并执行 RV32IMA、M/S CSR、M/S/U 特权转换、Sv32、MPRV、SUM/MXR、page fault delegation 与 U-mode 虚拟显存程序：

```powershell
python tools/test_demo.py
```

预期输出：

```text
RV32IMA M/S/U OK: Sv32, MPRV, SUM/MXR, 12 delegated traps, 2632 instructions
```

[`tools/ShadercCheck.java`](tools/ShadercCheck.java) 使用 Minecraft 26.3-snapshot-5 附带的 LWJGL ShaderC 3.4.2 编译两个片元着色器。发布流程还会解析资源包 JSON、检查 ZIP 根目录并对比安装副本的 SHA-256。

## 设计依据

[PiMaker/rvc](https://github.com/pimaker/rvc) 展示了以整数纹理承载 RISC-V 状态、让片元并行提交 CPU tick 的架构。本项目将其 RV32M、RV32A、CSR 与特权执行语义移植到 Minecraft persistent post-effect target，并为 RGBA8 状态、GLSL 330、Minecraft 仪表盘和资源包生命周期提供适配层。第三方说明见 [`THIRD_PARTY.md`](THIRD_PARTY.md)。

指令行为依据 [RISC-V Unprivileged ISA](https://docs.riscv.org/reference/isa/unpriv/unpriv-index.html)。Minecraft 资源格式依据 [25w16a Post Effect 更新](https://www.minecraft.net/en-us/article/minecraft-snapshot-25w16a) 与 [26.3 Snapshot 3 `/posteffect`](https://www.minecraft.net/en-us/article/minecraft-26-3-snapshot-3)。

## 许可证

项目使用 [MIT License](LICENSE.txt)。
