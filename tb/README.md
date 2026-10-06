# Testbench

Self-checking SystemVerilog testbench for the RTL in `../rtl`.

## Running

From the repository root:

```powershell
.\sim.cmd              # compile + run
.\sim.cmd -Trace       # also print a cycle-by-cycle trace of one DUT
.\sim.cmd -Waves       # also report the waveform path
```

or, if your PowerShell execution policy allows scripts:

```powershell
.\sim.ps1
```

Exit status is `0` when every check passes. Requires
[Icarus Verilog](https://github.com/steveicarus/iverilog) (`iverilog` and `vvp`
on `PATH`).

The scripts must run from the repository root: the ROM images are loaded with
`$readmemh` using paths relative to it.

## Files

| File | Purpose |
| --- | --- |
| `tb_top.sv` | testbench: instantiates four DUTs plus taps, runs the programs, self-checks |
| `tb_tap.sv` | observation helper: latches `out` on the edge where `OUT` retires |
| `program_a.hex` | `LDI 0F, STA 0, LDI 00, LDA 0, OUT, HLT` |
| `program_b.hex` | `ADD M[1]` / `SUB M[1]` |
| `program_c.hex` | `STA 0, LDI 00, LDA 0, OUT, HLT` |
| `program_d.hex` | `LDI 0A, STA 0, LDA 0, OUT, HLT` — back-to-back, hostile |

`*.hex` files are one byte per line in `$readmemh` format. They must contain
bare hex data only: `$readmemh` rejects any other characters, including `//`
comment lines.

## How the testbench observes the design

ROM contents are a compile-time parameter, so four independent `top` instances
run four programs in parallel off one clock. Each one is driven only through
its top-level ports (`clk`, `rst`) and observed only through top-level outputs
(`out`, plus `rom_addr`/`rom_data` to detect `HLT`).

Expected results are derived from `ISA.txt`, not from the RTL. DUT internals are
read only to make a failing check readable.

`top.out` is combinational and only presents `A` while the `OUT` instruction is
in the ROM, so `tb_tap` latches the real `out` pin on the retiring clock edge.
Reading `out` any later races the PC increment and silently observes `0`.

## Current result

```
RESULT: 15 passed, 3 failed
 TEST 1 (load with gap)        : PASS
 TEST 2 (ALU, gap before load) : FAIL
 TEST 3 (load path sanity)     : PASS
 TEST 4 (back-to-back ld/st)   : FAIL
```

`TEST 2` and `TEST 4` fail because of a memory read timing hazard in `MEM`/
`CPU`. See the "Known issue" section of the top-level `README.md`.

`HLT` is not currently implemented in the RTL — `cpu.sv` decodes opcode `1111`
but does not stop the PC — so the testbench treats "the ROM word at the current
PC is `HLT`" as the end of each program rather than waiting for the design to
halt itself.
