# Minecraft RV32I Shader

一个完全运行在 Minecraft Java Edition Postprocess Shader 中的 32 位 RISC-V 模拟器。

CPU、寄存器、PC、RAM、显存和执行状态全部保存在两个 128 × 128 persistent render target 中。两个 GPU pass 在每个画面帧完成两条 RV32I 指令，显示 pass 将机器状态与 32 × 18 显存合成为屏幕仪表盘。

## 特性

- RV32I Base Integer Instruction Set 2.1 的 40 条基础指令
- 32 个 32 位整数寄存器与硬连线零寄存器 `x0`
- 32 位程序计数器与周期计数器
- 65,392 字节小端 RAM
- 8 位、16 位和 32 位 load/store
- 自然对齐访问与可视化异常状态
- 32 × 18 单词显存，基地址为 `0x00001000`
- 约 120 指令/秒的 60 FPS 默认执行速度
- PC、周期、状态、`x1`–`x8`、显存与 RAM 活动仪表盘
- 内置 RV32I 显存填充程序
- 平面 RV32 binary 到 GLSL ROM 的转换工具
- 原版资源包运行方式

## 运行环境

当前资源包面向 **Minecraft Java Edition 26.3-snapshot-5**，对应 Resource Pack 93.0。

安装步骤：

1. 下载 [`MinecraftRV32IShader-26.3-snapshot-5.zip`](dist/MinecraftRV32IShader-26.3-snapshot-5.zip)。
2. 将 ZIP 放入当前 Minecraft 实例的 `resourcepacks` 目录。
3. 在“选项 → 资源包”中启用 **Minecraft RV32I**。
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

[`programs/framebuffer_demo.S`](programs/framebuffer_demo.S) 使用九个 RV32I 指令单词循环写入显存：

```asm
lui   x1, 0x1
addi  x2, x0, 1
lui   x6, 0x2
addi  x6, x6, -1792

fill_framebuffer:
sw    x2, 0(x1)
addi  x1, x1, 4
addi  x2, x2, 1
bltu  x1, x6, fill_framebuffer
ebreak
```

程序向 `0x1000`–`0x18ff` 写入 `1`–`576`，完成 576 个显存单元后以 EBREAK 结束。整个过程执行 2309 条指令。

## RV32I 指令范围

| 类别 | 指令 |
| --- | --- |
| Upper immediate | `LUI`, `AUIPC` |
| Jump | `JAL`, `JALR` |
| Branch | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Load | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Store | `SB`, `SH`, `SW` |
| Immediate ALU | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| Register ALU | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Environment | `FENCE`, `ECALL`, `EBREAK` |

`FENCE` 在单一顺序内存环境中完成一次顺序同步。`ECALL` 与 `EBREAK` 将相应状态写入 CPU 元数据并保持仪表盘内容。

当前执行环境聚焦 RV32I 用户态整数程序。CSR、特权架构以及 M/A/F/D/C 扩展适合作为后续实现层。

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
| `0`–`16347` | RAM，字节地址 `0x00000000`–`0x0000ff6f` |
| `16348`–`16379` | `x0`–`x31` |
| `16380` | CPU 状态 |
| `16381` | 周期计数器 |
| `16382` | PC |
| `16383` | 初始化魔数 `0x52563332` |

双缓冲执行流程：

```text
state_a → RV32I tick → state_b → RV32I tick → state_a → dashboard
```

每个片元读取同一条指令、源寄存器与相关内存。输出坐标决定该片元负责 RAM 单词、目标寄存器或 CPU 元数据。这个结构将一次指令提交表达为整张纹理的并行状态转换。

## CPU 状态码

| 值 | 状态 |
| --- | --- |
| `0` | Running |
| `1` | EBREAK |
| `2` | ECALL |
| `3` | Illegal instruction |
| `4` | Instruction fetch fault |
| `5` | Load access fault |
| `6` | Store access fault |
| `7` | Address alignment fault |

仪表盘指示灯以绿色表示运行、金色表示 EBREAK、红色表示异常状态。

## 加载自己的程序

模拟器从字节地址零开始执行平面 RV32 binary。链接脚本可以将 `.text` 放置在 `0x00000000`，并将 RAM 范围控制在 `0x0000ff70` 以内。

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

参考执行测试会重建内置机器码并执行整个程序：

```powershell
python tools/test_demo.py
```

预期输出：

```text
RV32I demo OK: 576 framebuffer stores, 2309 instructions, EBREAK
```

[`tools/ShadercCheck.java`](tools/ShadercCheck.java) 使用 Minecraft 26.3-snapshot-5 附带的 LWJGL ShaderC 3.4.2 编译两个片元着色器。发布流程还会解析资源包 JSON、检查 ZIP 根目录并对比安装副本的 SHA-256。

## 设计依据

[PiMaker/rvc](https://github.com/pimaker/rvc) 展示了以整数纹理承载 RISC-V 状态、让片元并行提交 CPU tick 的架构。本项目将这套思路映射到 Minecraft persistent post-effect target，并为 RGBA8 状态、RV32I 用户态执行环境、Minecraft 仪表盘和资源包生命周期设计了独立实现。第三方说明见 [`THIRD_PARTY.md`](THIRD_PARTY.md)。

指令行为依据 [RISC-V RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20240411/unpriv/rv32.html)。Minecraft 资源格式依据 [25w16a Post Effect 更新](https://www.minecraft.net/en-us/article/minecraft-snapshot-25w16a) 与 [26.3 Snapshot 3 `/posteffect`](https://www.minecraft.net/en-us/article/minecraft-26-3-snapshot-3)。

## 许可证

项目使用 [MIT License](LICENSE.txt)。
