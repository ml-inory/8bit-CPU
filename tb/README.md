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
| `tb_top.sv` | testbench: instantiates five DUTs plus taps, runs the programs, self-checks |
| `tb_tap.sv` | observation helper: samples `out` on the falling edge of the `OUT` cycle |
| `program_a.hex` | `LDI 0F, STA 0, LDI 00, LDA 0, OUT, HLT`, plus a marker byte after `HLT` |
| `program_b.hex` | `ADD M[1]` / `SUB M[1]` |
| `program_c.hex` | `STA 0, LDI 00, LDA 0, OUT, HLT` |
| `program_d.hex` | `LDI 0A, STA 0, LDA 0, OUT, HLT` — back-to-back |
| `program_e.hex` | `0x00-0x01` underflows to `0xFF`, `+0x01` carries, then `JC` |

`*.hex` files are one byte per line in `$readmemh` format. They must contain
bare hex data only: `$readmemh` rejects any other characters, including `//`
comment lines.

## How the testbench observes the design

ROM contents are a compile-time parameter, so five independent `top` instances
run five programs in parallel off one clock. Each one is driven only through
its top-level ports (`clk`, `rst`) and observed only through top-level outputs
(`out`, and `instr_valid` to detect that the CPU has halted).

Expected results are derived from `ISA.txt`, not from the RTL. DUT internals are
read only to make a failing check readable.

`top.out` is combinational (`out` is `A` only while the `OUT` instruction is on
the ROM bus) and it depends on the accumulator, which the rising edge updates.
`tb_tap` therefore samples on the falling edge, after the edge has settled and
while the instruction is still on the bus, and presents the result on the next
falling edge for the testbench to collect.

## Current result

```
RESULT: 25 passed, 0 failed
 TEST 1 (basic ld/st/out)      : PASS
 TEST 2 (ADD / SUB)            : PASS
 TEST 3 (load with gap)        : PASS
 TEST 4 (gap-less load)        : PASS
 TEST 5 (carry reaches JC)     : PASS
 TEST 6 (HLT freezes the CPU)  : PASS
```

Exit status is `0`.

Tests 3 and 4 are the regression guards for the memory read path. They
previously failed because `MEM.rdata` was a registered output, so a load-type
opcode consumed the previous cycle's data. The RTL now reads `MEM`
combinationally (`assign rdata = mem[addr];`). If someone reintroduces a
registered read, test 4 fails again.

Test 5 guards the ADD carry: it underflows `0x00-0x01` to `0xFF` (reachable,
because a `LDI` immediate is only 4 bits), adds `0x01` to get `0x00` with
`C=1`, and requires `JC` to take the branch. Test 6 steps five cycles past
`HLT` and requires PC, the accumulator and memory to be unchanged; program A
plants an `LDI 01` immediately after its `HLT`, so a runaway PC shows up as a
changed `A`.
