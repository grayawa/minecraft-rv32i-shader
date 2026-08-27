# Minecraft RV32IMA Shader

一个运行在 Minecraft Java Edition Postprocess Shader 中的 32 位 RISC-V 模拟器。CPU、RAM、设备与显示均由资源包内的 GLSL 330 shader 驱动。`rv32i_linux` 配置加载 OpenSBI、Linux 5.17.11-rvc+ 与 ROMFS 用户空间，并以 `/rvcinit` 启动系统。

当前资源包面向 **Minecraft Java Edition 26.3-snapshot-5**，资源包格式为 93.0。

## 快速开始

1. 下载 [`MinecraftRV32IShader-26.3-snapshot-5.zip`](dist/MinecraftRV32IShader-26.3-snapshot-5.zip)。
2. 将 ZIP 放入当前 Minecraft 实例的 `resourcepacks` 目录。
3. 在“选项 → 资源包”中启用 **Minecraft RV32IMA**。
4. 进入具有命令权限的世界。
5. 选择一个运行配置：

   ```mcfunction
   /posteffect add @s mcrv:rv32i_linux
   ```

重新启动模拟器时执行：

```mcfunction
/posteffect clear
```

按 `F3+T` 重新加载资源，然后再次添加效果。窗口尺寸变化也会重新初始化 persistent target。

三个运行配置共用同一套 CPU 核心：

| Post Effect | 每帧指令数 | Guest | 用途 |
| --- | ---: | --- | --- |
| `mcrv:rv32i` | 2 | 内置 RV32IMA/Sv32 自检 | 指令、异常、中断与虚拟内存验证 |
| `mcrv:rv32i_boot` | 2 | 启动寄存器探针 | `a0`、`a1` 与 DTB 验证 |
| `mcrv:rv32i_linux` | 64 | OpenSBI + Linux + ROMFS | Linux 启动与用户空间 |

## Linux 启动配置

Linux 配置使用 [PiMaker/rvc](https://github.com/pimaker/rvc/tree/da936a719b4254e91ba422361d7c1d1d0e775b8f) 的来宾构建产物：

- OpenSBI v0.9 从 `0x80000000` 进入 M-mode。
- Linux 5.17.11-rvc+ 从 `0x80400000` 进入 S-mode。
- DTB 位于 `0x00001020`，启动时通过 `a1` 传入。
- ROMFS 映射到只读 MTD 窗口 `0x40000000`。
- 内核命令行使用 `root=mtd:root rootfstype=romfs ro init=/rvcinit`。
- 用户空间启动完成后，UART 显示 `Welcome to userland!` 与 `/ #`。

[`tools/import_rvc_assets.py`](tools/import_rvc_assets.py) 从 rvc 的分通道 PNG 还原 payload、DTB 与 ROMFS。导入器将 DTB 内存大小写为 `0x00BFF000`，并让 OpenSBI 保持使用 `a1=0x1020` 指向的设备树。DTB 写事务按设备空操作完成，与 rvc 的窗口语义一致。

Linux payload 与 ROMFS 的固定校验值为：

| 产物 | 有效字节数 | SHA-256 |
| --- | ---: | --- |
| OpenSBI + Linux payload | 8,305,028 | `75a060159e959c833df4305839705fdb185752cc6b730b0f3c72854a5d4b3de1` |
| ROMFS | 56,466,528 | `b8e1655993bb05358263d39863937f0f643a616072fe0079d1ca338028be5f3d` |

rvc 参考执行器使用同一份 patched payload、DTB 与 ROMFS，可进入 Linux 用户空间并显示 `/ #`。参考轨迹约在 374 万条指令时从 OpenSBI 跳到 Linux 入口，并在第 45,170,487 个 guest 周期附近显示 shell prompt；Linux 建立页表后，PC 进入 `0xC...` 内核虚拟地址。Minecraft 中的墙钟时间由 GPU、分辨率、帧率上限和窗口状态共同决定。

## 仪表盘

显示 pass 将场景与 320 × 180 虚拟仪表盘合成：

- `PC`：当前程序计数器。
- `CY`：shader 执行周期，可用于判断持续推进状态。
- `ST`：`0` 表示运行，`1` 表示 EBREAK。
- `X01`–`X05`：常用整数寄存器。
- `MC`、`ME`、`MT`：`mcause`、`mepc`、`mtval`。
- 绿色指示灯：CPU 正在运行。
- 金色指示灯：CPU 到达 EBREAK。
- 右侧 32 × 18 区域：地址 `0x00001000` 的测试 framebuffer。
- `TX` 下方三行：UART 环形缓冲区中最新的 96 个字符。
- 底部色带：RAM 活动采样。

OpenSBI 阶段的 PC 主要位于 `0x800...`。进入 Linux payload 时 PC 会短暂位于 `0x804...`，页表启用后主要位于 `0xC...`。异常诊断可直接读取 `MC/ME/MT`；Linux 通过 SBI 服务进入 M-mode 时，`MC=9` 表示一次正常的 supervisor environment call。

## CPU 与平台能力

- RV32I Base Integer、RV32M、RV32A 与 Zicsr。
- M/S/U 三种特权级。
- `ECALL`、`EBREAK`、`MRET`、`SRET`、`SFENCE.VMA` 与 `WFI`。
- `medeleg`、`mideleg`、direct/vectored trap 与标准异常元数据。
- Sv32 两级页表、4 KiB 页面、4 MiB superpage、R/W/X/U/A/D 权限。
- `MPRV`、`SUM` 与 `MXR`。
- machine/supervisor software、timer 与 external interrupt。
- LR/SC 与十一条 32 位 AMO 指令。
- 8、16、32 位小端 load/store。
- 4096 个 CSR 存储槽与常用 CSR 掩码视图。

指令范围：

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
| Environment | `FENCE`, `FENCE.I`, `ECALL`, `EBREAK`, `MRET`, `SRET`, `SFENCE.VMA`, `WFI` |

### MMIO

| 地址 | 设备 |
| --- | --- |
| `0x00001020`–`0x00001FFF` | 4 KiB DTB 窗口 |
| `0x02000000` | CLINT `msip` |
| `0x02004000`–`0x02004007` | CLINT `mtimecmp` |
| `0x0200BFF8`–`0x0200BFFF` | CLINT `mtime` |
| `0x030007F8`–`0x030007FF` | RTC 时间寄存器 |
| `0x0C000028` 等 | PLIC UART source 10 与 hart 0 M/S context |
| `0x10000000`–`0x10000007` | 16550A 风格 UART |
| `0x40000000`–`0x435DBFFF` | ROMFS MTD 纹理窗口 |
| `0x80000000`–`0x80BFEFFF` | Linux 配置的 guest RAM |

UART 覆盖 THR、IER、IIR、LCR 与 LSR。LSR 返回 THRE/TEMT，LCR.DLAB 控制 divisor-latch 访问。发送字节写入 RAM target 的 4 KiB 保护页，256-byte 环形缓冲区位于保护页起始位置。

## Shader 状态布局

RGBA8 纹理的每个像素保存一个小端 32 位单词：

```text
R = bits  7..0
G = bits 15..8
B = bits 23..16
A = bits 31..24
```

| 资源 | 尺寸 | 内容 |
| --- | ---: | --- |
| `state_a/state_b` | 128 × 128 | CSR、x0–x31、PC、周期、设备、写缓存 |
| `ram_a/ram_b` | 4096 × 768 | 12 MiB RAM target |
| guest image | 2048 × 1024 | 8 MiB payload 与 16-byte boot descriptor |
| DTB image | 1024 × 1 | 4 KiB DTB window |
| MTD image | 4096 × 3447 | 56,475,648-byte 只读窗口 |

RAM target 的前 `0x00BFF000` 字节属于 guest；末尾 4 KiB 保存 shader 设备数据与 RAM 初始化标记。Linux profile 每帧执行两个 32 指令半批次。每个半批次使用 64 组、4 路、共 256 个单词槽的写缓存，然后由一次全尺寸 RAM pass 统一提交，再清理缓存有效位。

```text
scene copy
32 × CPU step (state ping-pong, ram_a)
RAM commit (ram_a → ram_b)
cache clear
32 × CPU step (state ping-pong, ram_b)
RAM commit (ram_b → ram_a)
cache clear
dashboard
```

写缓存满组时，当前指令保持 PC 并等待本半批次结束。`0x0B0`–`0x0B3` 自定义 CSR 承载 rvc 的批量内存复制协议，RAM commit pass 可在一个 GPU pass 中完成 Linux 的大块复制。

boot descriptor 位于 guest image 的最后 16 字节：

| 单词 | 内容 |
| --- | --- |
| `-4` | DTB 物理地址 |
| `-3` | 入口 PC |
| `-2` | RAM 物理基址 |
| `-1` | magic `0x4D435256` |

复位时 `a0=0` 表示 hart 0，`a1` 保存 DTB 物理地址。

## 内置自检

`mcrv:rv32i` 在 2815 条指令中覆盖 RV32M、RV32A、CSR、UART/PLIC、CLINT、M/S/U 特权转换、Sv32、`MPRV`、`SUM/MXR`、page fault delegation 和 U-mode framebuffer 写入。成功后串口显示 `UART IRQ OK S`，右侧 framebuffer 填入 `1`–`576`。

`mcrv:rv32i_boot` 从 `0x80000000` 运行，验证 `a0=0`、`a1=0x1020` 与 FDT magic，随后通过 UART 输出 `DTB A1 OK` 并在 `0x8000008C` 到达 EBREAK。

## 构建与验证

生成 post-effect pass graph：

```powershell
python tools/build_post_effect.py
```

从固定 rvc revision 导入 Linux 产物：

```powershell
git clone --recursive https://github.com/pimaker/rvc.git
git -C rvc checkout da936a719b4254e91ba422361d7c1d1d0e775b8f
python tools/import_rvc_assets.py .\rvc
```

生成平台 DTB 与 texture：

```powershell
python tools/build_dtb.py programs/mcrv.dtb --dts-output programs/mcrv.dts
python tools/bin_to_texture.py programs/mcrv.dtb assets/mcrv/textures/effect/dtb_mcrv.png `
  --width 1024 --height 1 --raw
```

运行参考测试：

```powershell
python tools/test_demo.py
```

测试会重建内置机器码，执行 2815 条指令的参考模型，并校验 shader 常量、三份 pass graph、boot descriptor、DTB、Linux payload 与 ROMFS 哈希。`tools/ShadercCheck.java` 可配合 Minecraft 附带的 LWJGL ShaderC 3.4.2 编译四个片元 shader。

构建发布 ZIP：

```powershell
powershell -ExecutionPolicy Bypass -File tools/package.ps1
```

## 设计来源与许可证

[PiMaker/rvc](https://github.com/pimaker/rvc) 提供了整数纹理 CPU 状态、HLSL shader 执行模型、rvc 专用 Linux、OpenSBI 启动约定与 ROMFS 构建产物。本项目将这些机制适配到 Minecraft Post Effect、RGBA8 persistent target、GLSL 330、资源包生命周期与游戏内仪表盘。

指令行为依据 [RISC-V Unprivileged ISA](https://docs.riscv.org/reference/isa/unpriv/unpriv-index.html)。Minecraft 资源格式依据 [25w16a Post Effect 更新](https://www.minecraft.net/en-us/article/minecraft-snapshot-25w16a) 与 [26.3 Snapshot 3 `/posteffect`](https://www.minecraft.net/en-us/article/minecraft-26-3-snapshot-3)。

项目代码使用 [MIT License](LICENSE.txt)。Linux 配置附带的第三方组件采用各自许可证，版本与来源记录见 [`THIRD_PARTY.md`](THIRD_PARTY.md)。
