# Minecraft RV32IMA Shader

一个完全运行在 Minecraft Java Edition Postprocess Shader 中的 32 位 RISC-V 模拟器。当前核心覆盖 RV32IMA、Zicsr、M/S/U 特权级、Sv32 虚拟内存、CLINT、16550A 风格 UART、PLIC、异常与中断 delegation，以及 trap 返回路径。

CPU、寄存器、PC、CSR 和设备状态保存在两个 128 × 128 persistent render target 中，1 MiB RAM 保存在一组 1024 × 256 persistent render target 中。guest binary 由资源包内的 RGBA8 纹理提供，纹理尾部的 boot descriptor 指定 RAM 物理基址、入口 PC 与 DTB 地址。初始化 pass 将 guest payload 复制到 RAM，并按 RISC-V 启动约定设置 `a0` 与 `a1`。每条指令依次经过 CPU 计算和 RAM 事务提交，每个画面帧完成两条 RISC-V 指令。显示 pass 将机器状态与 32 × 18 显存合成为屏幕仪表盘。

## 特性

- RV32I Base Integer Instruction Set 2.1 的 40 条基础指令
- RV32M 的八条乘除法指令
- RV32A 的十一条 32 位原子指令
- Zicsr 的六种 CSR 读写指令
- M-mode 与 S-mode CSR bank
- `ECALL` 与内存/指令异常的同步 trap entry
- `medeleg`/`mideleg` delegation、`MRET` 与 `SRET`
- CLINT `msip`、64 位 `mtimecmp` 与 64 位 `mtime`
- 16550A 风格 UART transmit path 与 64-byte 输出 ring
- PLIC UART source 10 与 hart 0 的 M/S context
- machine software/timer/external 与 supervisor software/timer/external interrupt arbitration
- `mtvec`/`stvec` direct 和 vectored trap 地址计算
- Sv32 两级页表遍历、4 KiB 页面与 4 MiB superpage
- R/W/X/U/A/D、`SUM`、`MXR` 权限检查
- `MPRV` 数据访问有效特权级
- instruction/load/store page fault 与 `SFENCE.VMA`
- 32 个 32 位整数寄存器与硬连线零寄存器 `x0`
- 32 位程序计数器与周期计数器
- 1,048,572 字节小端 RAM
- 8 位、16 位和 32 位 load/store
- 自然对齐访问与标准 `cause`/`tval` 异常元数据
- 32 × 18 单词显存，基地址为 `0x00001000`
- 约 120 指令/秒的 60 FPS 默认执行速度
- PC、周期、状态、`x1`–`x8`、UART、显存与 RAM 活动仪表盘
- 内置 RV32IMA、CSR、UART/PLIC、CLINT、interrupt、trap 自检与显存填充程序
- demo 汇编器与汇编源/guest texture 一致性检查
- 平面 RV32 binary 到 RGBA8 guest texture 的转换工具
- 独立 guest image 与 shader CPU 核心
- 可配置 load address、entry point 与 DTB address
- `0x80000000` boot probe 与 `a0`/`a1` 启动寄存器检查
- 4 KiB 只读 DTB texture window
- 确定性 MCRV 平台 DTS/DTB 生成器
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

内置程序首先验证八条 RV32M 指令、CSR、LR/SC reservation 和 `AMOADD.W`。随后，M-mode 配置 PLIC source 10 和 16550A THRE interrupt，发送首字节 `U`，并通过 MEIP 进入 machine external interrupt handler。Handler 从 PLIC claim 寄存器取得 source 10，完成中断后返回。程序继续以 polling-style UART 写入 `ART IRQ OK `。

UART/PLIC 路径通过后，M-mode 通过标准 CLINT 地址验证 `msip` 读写，将 `mtime` 置零，并设置 `mtimecmp=12` 触发 machine timer interrupt。机器中断处理程序记录 `mcause=0x80000007`、关闭 MTIE，并置位 STIP。页表为 UART 与 PLIC 建立 supervisor identity mapping；程序启用 PLIC S context 并发送字节 `S`。进入 S-mode 后，SEIP 与 STIP 依次到达 supervisor handler，最终 dashboard 串口行显示 `UART IRQ OK S`。

定时器路径通过后，M-mode 在物理地址 `0xA000` 和 `0xB000` 建立两级 Sv32 页表。页表为物理代码页和显存页分别建立 supervisor 与 user 虚拟别名：

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

U-mode 通过虚拟地址 `0x40003000`–`0x400038ff` 向物理显存 `0x1000`–`0x18ff` 写入 `1`–`576`，完成 576 个显存单元后以 EBREAK 结束。整个过程执行 2815 条指令。三种特权级各自的验证失败路径会将 `0xDEADBEEF` 写入首个显存单元并进入 EBREAK。

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

CSR bank 包含 `mstatus`、`medeleg`、`mideleg`、`mie`、`mtvec`、`mscratch`、`mepc`、`mcause`、`mtval`、`mip`、`sstatus`、`sie`、`stvec`、`sscratch`、`sepc`、`scause`、`stval`、`sip` 和 `satp`。`sstatus`、`sie` 与 `sip` 作为对应机器 CSR 的掩码视图。`misa` 返回 RV32IMA 能力位，周期计数器和 hart ID 通过对应 CSR 读取。机器状态区保存当前特权级、LR/SC reservation 和 CLINT 计时状态。

当前执行环境覆盖 M/S/U 特权级、Sv32 页表遍历、`MPRV`、`SUM`、`MXR`，异常原因 `0`、`1`、`2`、`4`–`9`、`11`–`13`、`15`，以及中断原因 `1`、`3`、`5`、`7`、`9`、`11` 的 trap entry。Linux 启动路径的下一层包括 OpenSBI payload 验证、SBI 服务和更大容量的 RAM 配置。

## 平台设备与中断

CLINT 提供以下 32 位 MMIO 寄存器。`mtime` 每执行一条 guest 指令增长一次，两个 32 位半部组成无符号 64 位计数器。

| 地址 | 寄存器 | 语义 |
| --- | --- | --- |
| `0x02000000` | `msip` | bit 0 产生 machine software interrupt |
| `0x02004000` | `mtimecmp` low | machine timer compare 低 32 位 |
| `0x02004004` | `mtimecmp` high | machine timer compare 高 32 位 |
| `0x0200bff8` | `mtime` low | machine time 低 32 位 |
| `0x0200bffc` | `mtime` high | machine time 高 32 位 |

中断仲裁综合 `mip`、`mie`、`mideleg` 和 `mstatus` 中的全局使能位。优先级顺序为 MEI、MSI、MTI、SEI、SSI、STI。Trap entry 在 `mcause` 或 `scause` 的最高位置一，并保留被中断指令的 PC。Direct 模式使用对齐后的 `tvec` 基址；vectored 模式使用 `BASE + 4 × cause`。

UART 位于 `0x10000000`，采用 16550A 的 8-byte MMIO register window。当前寄存器语义覆盖 THR、IER、IIR、LCR 与 LSR；LSR 返回 THRE/TEMT，LCR.DLAB 控制 divisor-latch 配置访问。每次 THR 写入会追加到 64-byte transmit ring，dashboard 显示最近 32 字节。

PLIC 使用 QEMU `virt` 风格地址与 UART source 10：

| 地址 | 寄存器 |
| --- | --- |
| `0x0c000028` | source 10 priority |
| `0x0c001000` | pending word 0 |
| `0x0c002000` | hart 0 M-mode enable word 0 |
| `0x0c002080` | hart 0 S-mode enable word 0 |
| `0x0c200000` / `0x0c200004` | M-mode threshold / claim-complete |
| `0x0c201000` / `0x0c201004` | S-mode threshold / claim-complete |

满足 priority、enable 与 threshold 条件的 M context 置位 MEIP，S context 置位 SEIP。读取 claim 返回 source 10 并锁定该 context，向 claim-complete 写回 source ID 完成本次中断。

## 平台设备树

[`mcrv.dts`](programs/mcrv.dts) 描述 shader 当前提供的单 hart RV32IMA 平台：

| 节点 | 关键属性 |
| --- | --- |
| `/cpus/cpu@0` | `rv32imasu`、Sv32、hart 0 |
| `/memory@80000000` | 基址 `0x80000000`，长度 1,048,572 字节 |
| `/soc/clint@2000000` | machine software/timer interrupt |
| `/soc/plic@c000000` | source 1–10，M/S external interrupt context |
| `/soc/uart@10000000` | `ns16550a`，PLIC source 10 |

`timebase-frequency` 为 120 Hz，对应默认两个 tick pass 在 60 FPS 下的 `mtime` 增长率。`chosen` 将串口设为 `/soc/uart@10000000`。[`build_dtb.py`](tools/build_dtb.py) 从同一平台模型确定性生成可读 DTS 与 1579-byte DTB。

## 纹理机器布局

RGBA8 状态纹理的每个像素保存一个小端 32 位单词：

```text
R = bits  7..0
G = bits 15..8
B = bits 23..16
A = bits 31..24
```

CPU state target 使用 128 × 128 布局，共包含 16,384 个单词：

| 单词索引 | 内容 |
| --- | --- |
| `0`–`16299` | 扩展状态空间 |
| `16300`–`16315` | CLINT、UART 与 PLIC device state |
| `16316`–`16347` | CSR、RAM 写事务、特权级与 atomic reservation 状态 |
| `16348`–`16379` | `x0`–`x31` |
| `16380` | CPU 状态 |
| `16381` | 周期计数器 |
| `16382` | PC |
| `16383` | 初始化魔数 `0x52563332` |

RAM target 使用 1024 × 256 布局。单词 `0`–`262142` 提供 1,048,572 字节 guest RAM，单词 `262143` 保存 RAM 初始化魔数。CPU 与 RAM 各自采用双缓冲，默认执行流程为：

```text
state_a + ram_a → CPU step → state_b
ram_a + state_b → RAM commit → ram_b
state_b + ram_b → CPU step → state_a
ram_b + state_a → RAM commit → ram_a
state_a + ram_a → dashboard
```

CPU step 的每个片元读取同一条指令、源寄存器与相关内存，并将一次 RAM 写入编码为地址、数值和宽度。RAM commit 将这笔事务合并到目标 RAM texture。这个结构让 CPU 状态转换保持 128 × 128 的固定成本，同时允许 RAM texture 独立扩展。

guest image 使用 1024 × 256 RGBA8 布局。初始化时，payload 从 guest texture 复制到 RAM，CPU state 由 shader 设置。guest texture 尾部保存四个 32 位 boot descriptor 单词：

| guest 单词索引 | 内容 |
| --- | --- |
| `262140` | DTB 物理地址 |
| `262141` | 入口 PC |
| `262142` | RAM 物理基址 |
| `262143` | descriptor magic `0x4D435256` |

复位时，`a0` 保存 hart ID `0`，`a1` 保存 DTB 物理地址。`DtbImageSampler` 提供 1024 个 RGBA 像素，对应 4 KiB 只读 DTB window。`dtb_mcrv.png` 保存平台 DTB 并映射到 `0x00001020`。内置 framebuffer demo 使用物理基址与入口 `0x00000000`。boot probe 使用物理基址与入口 `0x80000000`。

## CPU 状态码

| 值 | 状态 |
| --- | --- |
| `0` | Running |
| `1` | EBREAK |

异常与中断通过 M/S trap handler 继续执行，委托事件进入 S-mode。原因和附加值分别保存在 `mcause`/`mtval` 或 `scause`/`stval`。仪表盘指示灯以绿色表示运行、金色表示 EBREAK。

## 加载自己的程序

boot descriptor 决定平面 RV32 binary 的物理加载基址和入口 PC。M-mode 可以配置 `satp`，通过 `MRET` 进入 S-mode，再通过 `SRET` 进入 U-mode。RAM window 长度为 1,048,572 字节，guest payload 容量为 1,048,560 字节，平台设备使用上表列出的 MMIO 地址。

仓库内置的小型两遍汇编器支持 demo 使用的 RV32IMA/Zicsr 子集、标签和 `.org`：

```powershell
python tools/assemble_demo.py programs/framebuffer_demo.S -o framebuffer_demo.bin
```

转换 binary 为 guest texture：

```powershell
python tools/bin_to_texture.py framebuffer_demo.bin assets/mcrv/textures/effect/guest_demo.png `
  --load-address 0x0 --entry-point 0x0 --dtb-address 0x0
```

转换器按小端顺序将每个 32 位单词写入一个 RGBA 像素，并在纹理尾部写入 boot descriptor。`rv32i.json` 将 `mcrv:guest_demo` 绑定为两个 CPU pass 的 `GuestImageSampler`。生成纹理后重新打包资源包。

生成平台 DTS、DTB 和 raw texture：

```powershell
python tools/build_dtb.py programs/mcrv.dtb --dts-output programs/mcrv.dts
python tools/bin_to_texture.py programs/mcrv.dtb assets/mcrv/textures/effect/dtb_mcrv.png `
  --width 1024 --height 1 --raw
```

`rv32i_boot` 提供 `0x80000000` 启动探针：

```mcfunction
/posteffect remove @s mcrv:rv32i
/posteffect add @s mcrv:rv32i_boot
```

探针验证 `a0=0`、`a1=0x1020` 和 FDT magic `D0 0D FE ED`，随后通过 UART 输出 `DTB A1 OK` 并停在 PC `0x8000008C`。

构建 ZIP：

```powershell
powershell -ExecutionPolicy Bypass -File tools/package.ps1
```

## 验证

参考执行测试会从汇编源重建内置机器码，校验 guest texture 与 post-effect 绑定，并执行 RV32IMA、M/S CSR、UART/PLIC machine 与 supervisor external interrupt、CLINT machine timer interrupt、supervisor timer delegation、M/S/U 特权转换、Sv32、MPRV、SUM/MXR、page fault delegation 与 U-mode 虚拟显存程序：

```powershell
python tools/test_demo.py
```

预期输出：

```text
RV32IMA M/S/U guest texture OK: M/S UART/PLIC external interrupts, CLINT timer interrupts, Sv32, MPRV, SUM/MXR, 12 delegated traps, 2815 instructions; 0x80000000 boot descriptor, platform DTB and a0/a1 probe
```

[`tools/ShadercCheck.java`](tools/ShadercCheck.java) 使用 Minecraft 26.3-snapshot-5 附带的 LWJGL ShaderC 3.4.2 编译 CPU、RAM commit 和显示三个片元着色器。发布流程还会解析资源包 JSON、检查 ZIP 根目录并对比安装副本的 SHA-256。

## 设计依据

[PiMaker/rvc](https://github.com/pimaker/rvc) 展示了以整数纹理承载 RISC-V 状态、让片元并行提交 CPU tick 的架构。rvc 的 Linux 路径将平面 OpenSBI payload 转换为纹理，从 `0x80000000` 启动，并将 DTB 映射到 `0x1020` 后通过 `a1` 传入。本项目采用相同的镜像与执行状态分离思路，将 guest binary 作为 Minecraft `textures/effect` 输入，同时为 RGBA8 persistent target、GLSL 330、Minecraft 仪表盘和资源包生命周期提供适配层。第三方说明见 [`THIRD_PARTY.md`](THIRD_PARTY.md)。

指令行为依据 [RISC-V Unprivileged ISA](https://docs.riscv.org/reference/isa/unpriv/unpriv-index.html)。Minecraft 资源格式依据 [25w16a Post Effect 更新](https://www.minecraft.net/en-us/article/minecraft-snapshot-25w16a) 与 [26.3 Snapshot 3 `/posteffect`](https://www.minecraft.net/en-us/article/minecraft-26-3-snapshot-3)。

## 许可证

项目使用 [MIT License](LICENSE.txt)。
