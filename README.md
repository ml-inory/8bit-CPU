# 8bit-CPU

一个用 [Logisim](https://github.com/logisim-evolution/logisim-evolution) 搭建�?8 �?CPU，采�?4 位操作码 + 4 位操作数的简单定长指令格式�?
## 文件说明

| 文件 | 说明 |
| --- | --- |
| `rtl/` | SystemVerilog 实现（见下） |
| `tb/` | 自检测试平台与测试程序（�?`tb/README.md`�?|
| `sim.ps1` / `sim.cmd` | 一键编译并运行仿真 |
| `8bit-CPU.circ` | Logisim 电路源文件，包含 `main` / `ALU` / `CPU` / `IF` / `HALT` 五个子电�?|
| `ISA.txt` | 指令集定义（助记符、操作码、机器码、功能） |
| `count.txt` | 示例程序机器码（Logisim ROM/RAM �?`v2.0 raw` 格式�?|
| `README.md` | 本说明文�?|

## RTL 结构

| 文件 | 模块 | 说明 |
| --- | --- | --- |
| `rtl/top.sv` | `top` | 顶层：连�?CPU、ROM、RAM |
| `rtl/cpu.sv` | `CPU` | 取指译码、控制信号、累加器 `A` |
| `rtl/alu.sv` | `ALU` | 加减法、零标志 `Z`、进位标�?`C` |
| `rtl/pc.sv` | `PC` | 程序计数�?|
| `rtl/mem.sv` | `MEM` | 数据存储器，16 × 8 位，同步�?|
| `rtl/rom.sv` | `ROM` | 指令存储器，256 × 8 位，`$readmemh` 初始�?|

## 仿真

需�?[Icarus Verilog](https://github.com/steveicarus/iverilog)（`iverilog`、`vvp`
�?`PATH` 中）。在仓库根目录执行：

```powershell
.\sim.cmd              # 编译 + 运行
.\sim.cmd -Trace       # additionally 打印逐周期跟�?.\sim.cmd -Waves       # 输出 VCD 波形路径
```

全部检查通过时退出码�?`0`，波形写�?`build/tb_top.vcd`�?
四个测试程序并行运行，期望值全部来�?`ISA.txt`，与 RTL 实现无关�?
| 测试 | 程序 | 结果 |
| --- | --- | --- |
| TEST 1 | `LDI 0F, STA 0, LDI 00, LDA 0, OUT, HLT` | PASS |
| TEST 2 | `ADD M[1]` / `SUB M[1]` | **FAIL** |
| TEST 3 | `STA 0, LDI 00, LDA 0, OUT, HLT` | PASS |
| TEST 4 | `LDI 0A, STA 0, LDA 0, OUT, HLT` | **FAIL** |

## 已知问题

### 1. 存储器读时序（TEST 2 / TEST 4 失败�?
`MEM` �?`rdata` 是寄存器输出，在时钟上升沿采�?`mem[addr]`；但 `CPU` �?*同一
个周�?*就把 `mem_rdata` 当作当前指令的操作数送进 ALU。也就是�?`LDA`/`ADD`/
`SUB` 拿到的是**上一次读地址**的数据，而不是当前正在译码的那条指令的地址�?
更麻烦的�?`mem.sv` 里读和写在同一�?`always_ff` 中是互斥分支�?
```systemverilog
else if (wr)
    mem[addr] <= wdata;   // 写周期：rdata 完全不更新，保持更早的�?else
    rdata <= mem[addr];
```

因此�?`ADD` 需�?`M[1]` 时，若该边沿 `wr` �?1（例如前一条是 `STA`），
`rdata` 会停留在更早某个地址的旧值。实�?`ADD M[1]` 退化成 `A + 0`�?
实测证据（`.\sim.cmd -Trace`，程�?B）：

```
 t   PC   instr  addr  mem_rdata  wr   A      M[1]
 0   0    0x42   0x2   0x00       0    0x00   0x00   LDI 2 -> A=2
 1   2    0x43   0x3   0x00       0    0x02   0x02   (STA �?M[1]=2)
 2   3    0x11   0x1   0x00       0    0x03   0x02   ADD M[1]：rdata 仍为 0 -> A=3，应�?5
```

可行修法（任选其一）：

- **读改为组合输�?*：`assign rdata = mem[addr];`，写仍在时钟边沿。单周期 CPU
  最常用；代价是�?FPGA 上会被综合成分布�?RAM�?- **�?CPU 加等待周�?*：访存指令多停一拍，再采 `mem_rdata`�?- **写周期也更新 `rdata`**：把互斥去掉，让 `rdata` 始终对应当前地址；但
  `STA` 后立�?`LDA` 同一地址仍需配合等待或前递�?- **加前�?*：写周期直接�?`rdata` �?`wdata`�?
### 2. HLT 未实�?
`cpu.sv` 译码�?`1111`，但没有真正停住 PC，测试平台只能靠"当前 ROM 字是
`HLT`"来判断程序结束�?
### 3. PC 位宽不匹�?
`cpu.sv:70` �?4 位的 `addr` 接到 8 位的 `PC.data_in`，跳转地址�?4 位被补零�?因此 `JMP`/`JC`/`JZ` 实际只能跳到 `0x00`–`0x0F`。编译时 Icarus 会给�?`Port 4 (data_in) of module PC expects 8 bit(s), given 4` 警告�?
### 4. ISA 文档�?RTL �?JC/JZ 操作码不一�?
`ISA.txt` 记为 `JZ = 0110`、`JC = 0111`；�?`cpu.sv` 的注释与实现�?`0110 = JC`、`0111 = JZ`（见 `cpu.sv:11-12` �?`cpu.sv:52`）。两者需要对齐�?
## 电路结构

- **数据宽度**�? �?- **地址宽度**�?0 �?- **子电�?*�?  - `main` �?顶层，连接数据通路、存储与时钟
  - `ALU` �?算术逻辑单元（加法、减法、零标志 Z、进位标�?C�?  - `CPU` �?控制器，负责指令译码与各控制信号
  - `IF` �?取指单元（PC、指令寄存器�?  - `HALT` �?停机控制

## 指令�?
指令格式：`[opcode 4 位] [操作�?4 位]`，机器码 `= opcode << 4 | 操作数`�?
| 助记�?| 操作�?| 格式 | 机器�?| 操作 | 功能 |
| --- | --- | --- | --- | --- | --- |
| LDA | 0000 | `LDA addr` | `0x0_` | `A �?M[addr]` | 取数 |
| ADD | 0001 | `ADD addr` | `0x1_` | `A �?A + M[addr]` | 加法 |
| SUB | 0010 | `SUB addr` | `0x2_` | `A �?A - M[addr]` | 减法 |
| STA | 0011 | `STA addr` | `0x3_` | `M[addr] �?A` | 存数 |
| LDI | 0100 | `LDI imm` | `0x4_` | `A �?imm` | 立即�?|
| JMP | 0101 | `JMP addr` | `0x5_` | `PC �?addr` | 无条件跳�?|
| JZ | 0110 | `JZ addr` | `0x6_` | `if Z=1 then PC �?addr` | 零跳�?|
| JC | 0111 | `JC addr` | `0x7_` | `if C=1 then PC �?addr` | 进位跳转 |
| OUT | 1110 | `OUT` | `0xE0` | `Output �?A` | 输出 |
| HLT | 1111 | `HLT` | `0xF0` | 停时�?| 停机 |

## 使用方法

1. �?Logisim 打开 `8bit-CPU.circ`�?2. 选中 RAM/ROM 组件，右�?�?**Edit Contents**，切换到 **Hex** 或以 `v2.0 raw` 文本粘贴 `count.txt` 中的机器码�?3. 打开时钟（`Ctrl+T` 单步，或 `Ctrl+K` 连续运行）观察寄存器、ALU 标志与输出�?
### 示例程序

`count.txt` 中的机器码（�?27 字节）：

```
v2.0 raw
4b 30 40 31 41 32 33 1
12 31 e0 2 13 32 20 77
1 e0 f0
```

按上面的编码规则逐字节译码得到的指令序列�?
```
地址  机器�? 指令
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

> 说明：以上仅为按 `ISA.txt` 规则对机器码的译码结果。操作数�?4 位，只能直接寻址 `0x0`–`0xF`；该示例实际能否完整运行，取决于 `8bit-CPU.circ` �?RAM 的容量与 PC 的位宽，请以 Logisim 中的实际运行结果为准�?
## 授权

本仓库未附带开源许可证，如需使用请先联系作者�?