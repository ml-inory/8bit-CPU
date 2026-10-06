# 8bit-CPU

一个 8 位 CPU：`8bit-CPU.circ` 是 [Logisim](https://github.com/logisim-evolution/logisim-evolution) 电路，
`rtl/` 是对应的 SystemVerilog 实现，`tb/` 是自检测试平台。

采用 4 位操作码 + 4 位操作数的简单定长指令格式。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `rtl/` | SystemVerilog 实现（见下） |
| `tb/` | 自检测试平台与测试程序（见 `tb/README.md`） |
| `sim.ps1` / `sim.cmd` | 一键编译并运行仿真 |
| `8bit-CPU.circ` | Logisim 电路源文件，包含 `main` / `ALU` / `CPU` / `IF` / `HALT` 五个子电路 |
| `ISA.txt` | 指令集定义（助记符、操作码、机器码、功能） |
| `count.txt` | 示例程序机器码（Logisim ROM/RAM 的 `v2.0 raw` 格式） |
| `README.md` | 本说明文档 |

## RTL 结构

| 文件 | 模块 | 说明 |
| --- | --- | --- |
| `rtl/top.sv` | `top` | 顶层：连接 CPU、ROM、RAM |
| `rtl/cpu.sv` | `CPU` | 取指译码、控制信号、累加器 `A` |
| `rtl/alu.sv` | `ALU` | 加减法、零标志 `Z`、进位标志 `C` |
| `rtl/pc.sv` | `PC` | 程序计数器 |
| `rtl/mem.sv` | `MEM` | 数据存储器，16 × 8 位，组合读 |
| `rtl/rom.sv` | `ROM` | 指令存储器，256 × 8 位，`$readmemh` 初始化 |

## 仿真

需要 [Icarus Verilog](https://github.com/steveicarus/iverilog)（`iverilog`、`vvp`
在 `PATH` 中）。在仓库根目录执行：

```powershell
.\sim.cmd              # 编译 + 运行
.\sim.cmd -Trace       # 打印逐周期跟踪
.\sim.cmd -Waves       # 输出 VCD 波形路径
```

全部检查通过时退出码为 `0`，波形写入 `build/tb_top.vcd`。

四个测试程序并行运行，期望值全部来自 `ISA.txt`，与 RTL 实现无关：

| 测试 | 程序 | 结果 |
| --- | --- | --- |
| TEST 1 | `LDI 0F, STA 0, LDI 00, LDA 0, OUT, HLT` | PASS |
| TEST 2 | `ADD M[1]` / `SUB M[1]` | PASS |
| TEST 3 | `STA 0, LDI 00, LDA 0, OUT, HLT` | PASS |
| TEST 4 | `LDI 0A, STA 0, LDA 0, OUT, HLT`（无间隔） | PASS |

当前结果：`18 passed, 0 failed`。

TEST 3 与 TEST 4 是访存通路的回归保护：TEST 4 的 store 与 load 背靠背、中间
没有间隔，TEST 3 的 load 作为程序第一条指令。如果 `MEM` 的读改回寄存器输出，
TEST 4 会立刻失败。

## 已知问题

### 1. HLT 未实现

`cpu.sv` 译码了 `1111`，但没有真正停住 PC，测试平台只能靠「当前 ROM 字是
`HLT`」来判断程序结束。

### 2. PC 位宽不匹配

`cpu.sv:70` 把 4 位的 `addr` 接到 8 位的 `PC.data_in`，跳转地址高 4 位被补零，
因此 `JMP`/`JC`/`JZ` 实际只能跳到 `0x00`–`0x0F`。编译时 Icarus 会给出
`Port 4 (data_in) of module PC expects 8 bit(s), given 4` 警告。

### 3. ISA 文档与 RTL 的 JC/JZ 操作码不一致

`ISA.txt` 记为 `JZ = 0110`、`JC = 0111`；而 `cpu.sv` 的注释与实现是
`0110 = JC`、`0111 = JZ`（见 `cpu.sv:11-12` 与 `cpu.sv:52`）。两者需要对齐。

### 已修复：存储器读时序

`MEM.rdata` 原本是寄存器输出，而 `CPU` 在同一个周期就把 `mem_rdata` 当操作数
送进 ALU，导致 `LDA`/`ADD`/`SUB` 读到的是上一次读地址的数据；写周期又会完全
跳过 `rdata` 更新。现在改为组合读：

```systemverilog
assign rdata = mem[addr];
```

写仍在时钟边沿。TEST 3 / TEST 4 覆盖这个场景。

## 电路结构

- **数据宽度**：8 位
- **地址宽度**：10 位
- **子电路**：
  - `main` — 顶层，连接数据通路、存储与时钟
  - `ALU` — 算术逻辑单元（加法、减法、零标志 Z、进位标志 C）
  - `CPU` — 控制器，负责指令译码与各控制信号
  - `IF` — 取指单元（PC、指令寄存器）
  - `HALT` — 停机控制

## 指令集

指令格式：`[opcode 4 位] [操作数 4 位]`，机器码 `= opcode << 4 | 操作数`。

| 助记符 | 操作码 | 格式 | 机器码 | 操作 | 功能 |
| --- | --- | --- | --- | --- | --- |
| LDA | 0000 | `LDA addr` | `0x0_` | `A ← M[addr]` | 取数 |
| ADD | 0001 | `ADD addr` | `0x1_` | `A ← A + M[addr]` | 加法 |
| SUB | 0010 | `SUB addr` | `0x2_` | `A ← A - M[addr]` | 减法 |
| STA | 0011 | `STA addr` | `0x3_` | `M[addr] ← A` | 存数 |
| LDI | 0100 | `LDI imm` | `0x4_` | `A ← imm` | 立即数 |
| JMP | 0101 | `JMP addr` | `0x5_` | `PC ← addr` | 无条件跳转 |
| JZ | 0110 | `JZ addr` | `0x6_` | `if Z=1 then PC ← addr` | 零跳转 |
| JC | 0111 | `JC addr` | `0x7_` | `if C=1 then PC ← addr` | 进位跳转 |
| OUT | 1110 | `OUT` | `0xE0` | `Output ← A` | 输出 |
| HLT | 1111 | `HLT` | `0xF0` | 停时钟 | 停机 |

## 使用方法

1. 用 Logisim 打开 `8bit-CPU.circ`。
2. 选中 RAM/ROM 组件，右键 → **Edit Contents**，切换到 **Hex** 或以 `v2.0 raw` 文本粘贴 `count.txt` 中的机器码。
3. 打开时钟（`Ctrl+T` 单步，或 `Ctrl+K` 连续运行）观察寄存器、ALU 标志与输出。

### 示例程序

`count.txt` 中的机器码（共 27 字节）：

```
v2.0 raw
4b 30 40 31 41 32 33 1
12 31 e0 2 13 32 20 77
1 e0 f0
```

按上面的编码规则逐字节译码得到的指令序列：

```
地址  机器码  指令
 00    4B     LDI 0xB
 01    30     STA 0x0
 02    40     LDI 0x0
 03    31     STA 0x1
 04    41     LDI 0x1
 05    32     STA 0x2
 06    33     STA 0x3
 07    01     ADD 0x1
 08    12     SUB 0x2
 09    31     STA 0x1
 0A    E0     OUT
 0B    02     SUB 0x2
 0C    13     SUB 0x3
 0D    32     STA 0x2
 0E    20     SUB 0x0
 0F    77     JC 0x7
 10    01     ADD 0x1
 11    E0     OUT
 12    F0     HLT
```

> 说明：以上仅为按 `ISA.txt` 规则对机器码的译码结果。操作数为 4 位，只能直接寻址 `0x0`–`0xF`；该示例实际能否完整运行，取决于 `8bit-CPU.circ` 中 RAM 的容量与 PC 的位宽，请以 Logisim 中的实际运行结果为准。

## 授权

本仓库未附带开源许可证，如需使用请先联系作者。