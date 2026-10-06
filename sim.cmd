@echo off
REM ---------------------------------------------------------------------------
REM Compile and run the 8-bit CPU testbench with Icarus Verilog.
REM
REM This wrapper exists because the PowerShell execution policy on many Windows
REM machines blocks running .ps1 files directly. It calls sim.ps1 with a
REM process-scoped bypass, which changes nothing on the machine.
REM
REM Usage:  sim.cmd [-Trace] [-Waves]
REM ---------------------------------------------------------------------------
setlocal

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    set "PSH=pwsh"
) else (
    set "PSH=powershell"
)

%PSH% -NoProfile -ExecutionPolicy Bypass -File "%~dp0sim.ps1" %*
exit /b %ERRORLEVEL%
