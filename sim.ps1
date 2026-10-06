<#
.SYNOPSIS
    Compile and run the 8-bit CPU testbench with Icarus Verilog.

.DESCRIPTION
    Compiles rtl/*.sv together with tb/tb_top.sv into build/tb_top.out, runs it,
    writes build/tb_top.vcd, and exits with the simulator's status (0 = all
    checks passed).

    The testbench loads its ROM images with $readmemh using paths relative to
    the repository root, so this script always runs from the repository root.

.PARAMETER Trace
    Pass +trace to the simulation: prints a cycle-by-cycle trace of one DUT.

.PARAMETER Waves
    Report where the VCD waveform was written.

.EXAMPLE
    .\sim.ps1
    .\sim.ps1 -Trace
#>
[CmdletBinding()]
param(
    [switch]$Trace,
    [switch]$Waves
)

# Note: deliberately not 'Stop'. Native tools write warnings to stderr, and with
# $ErrorActionPreference='Stop' PowerShell turns a captured native stderr line
# into a terminating error, which would abort on an ordinary compiler warning.
# Status is checked explicitly via $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

$repoRoot = $PSScriptRoot
Set-Location $repoRoot

$rtlFiles = Get-ChildItem -Path (Join-Path $repoRoot 'rtl') -Filter '*.sv' |
    Sort-Object Name | ForEach-Object { $_.FullName }
$tbTop = Join-Path $repoRoot 'tb\tb_top.sv'

if ($rtlFiles.Count -eq 0) {
    Write-Host "no RTL sources found in $repoRoot\rtl" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $tbTop)) {
    Write-Host "testbench not found: $tbTop" -ForegroundColor Red
    exit 2
}

$buildDir = Join-Path $repoRoot 'build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$simOut = Join-Path $buildDir 'tb_top.out'

# --- locate iverilog ---------------------------------------------------------
$iverilog = (Get-Command iverilog -ErrorAction SilentlyContinue).Source
$vvp      = (Get-Command vvp      -ErrorAction SilentlyContinue).Source
if (-not $iverilog) {
    Write-Host "iverilog not found on PATH." -ForegroundColor Red
    Write-Host "Install Icarus Verilog (e.g. winget install --id IcarusVerilog.IcarusVerilog) and re-run."
    exit 2
}
if (-not $vvp) {
    # vvp normally sits next to iverilog
    $vvp = Join-Path (Split-Path $iverilog -Parent) 'vvp.exe'
    if (-not (Test-Path $vvp)) {
        Write-Host "vvp not found next to iverilog ($iverilog)" -ForegroundColor Red
        exit 2
    }
}

# --- compile -----------------------------------------------------------------
Write-Host "compiling ..." -ForegroundColor Cyan
$compileArgs = @('-g2012', '-s', 'tb_top', '-o', $simOut) +
               $rtlFiles +
               @((Join-Path $repoRoot 'tb\tb_tap.sv'), $tbTop)

# `time unit` / port-width notices are expected for this design and are noise
# here; real errors still surface and are always printed.
$compileLog = & $iverilog @compileArgs 2>&1
$compileStatus = $LASTEXITCODE
$compileLog | Where-Object {
    $_ -notmatch 'time unit|time precision|Affected design elements|declared here:|Padding \d+ high bits|expects \d+ bit\(s\), given'
} | ForEach-Object { Write-Host "  $_" }

if ($compileStatus -ne 0) {
    Write-Host "compile FAILED (exit $compileStatus)" -ForegroundColor Red
    exit 1
}
Write-Host "compile ok -> $simOut" -ForegroundColor Green

# --- run ---------------------------------------------------------------------
Write-Host ""
$simArgs = @($simOut)
if ($Trace) { $simArgs += '+trace' }

$simLog = & $vvp @simArgs 2>&1
$simStatus = $LASTEXITCODE
$simLog | Where-Object { $_ -notmatch 'Not enough words in the file|^VCD info:' } |
    ForEach-Object { Write-Host $_ }

# --- report ------------------------------------------------------------------
$resultLine = $simLog | Where-Object { $_ -match 'RESULT:' } | Select-Object -Last 1

Write-Host ""
if ($simStatus -eq 0) {
    Write-Host "SIMULATION PASSED" -ForegroundColor Green
} else {
    Write-Host "SIMULATION FAILED (exit $simStatus)" -ForegroundColor Red
}
if ($resultLine) { Write-Host ("  " + $resultLine.Trim()) }

if ($Waves) {
    Write-Host ("  waveform: " + (Join-Path $buildDir 'tb_top.vcd'))
}

exit $simStatus
