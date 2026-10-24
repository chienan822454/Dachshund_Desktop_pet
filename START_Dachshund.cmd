@echo off
setlocal
title Dachshund Pet launcher
cd /d "%~dp0"
set "PET_DIR=%~dp0"
set "MODE=%~1"

if not exist "%~dp0DachshundPet.ps1" goto missing

rem Safety check only reads settings. It never changes them.
rem 2 = this PC requires signed scripts, 3 = file came from the internet, 4 = PowerShell is locked down.
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $f=Join-Path $env:PET_DIR 'DachshundPet.ps1'; $set=@(Get-ExecutionPolicy -List | Where-Object { $_.Scope -ne 'Process' -and [string]$_.ExecutionPolicy -ne 'Undefined' }); if ($set.Count -gt 0 -and @('Restricted','AllSigned') -contains [string](Get-ExecutionPolicy)) { exit 2 }; if (Get-Item -LiteralPath $f -Stream 'Zone.Identifier') { exit 3 }; if ([string]$ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 4 }; exit 0"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto blocked
if /i "%MODE%"=="diag" goto diag

set "PET_ARGS="
if /i "%MODE%"=="classic" set "PET_ARGS=-Classic"
start "Dachshund Pet" /min powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -STA -File "%~dp0DachshundPet.ps1" %PET_ARGS%
exit /b 0

:diag
echo Dachshund Pet diagnostic mode: this window stays open and shows any error.
echo Close the dachshund with right-click, then read the result here.
echo.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -STA -File "%~dp0DachshundPet.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo Dachshund Pet has closed. Exit code: %RC%
echo If an error is shown above, please take a screenshot. Error files: DachshundPet_Error_*.txt
pause
exit /b %RC%

:missing
echo [Cannot start] DachshundPet.ps1 was not found. Keep all files of this folder together.
pause
exit /b 1

:blocked
echo.
if "%RC%"=="2" echo [Cannot start] PowerShell on this PC is set to block unsigned scripts. This program will not override that setting. On a company-managed PC, please contact IT.
if "%RC%"=="3" echo [Cannot start] Windows marks DachshundPet.ps1 as downloaded from the internet, so it will not run. Use the folder that OneDrive synced to this PC. For a ZIP from GitHub: right-click the ZIP, Properties, tick Unblock, OK, then extract it again.
if "%RC%"=="4" echo [Cannot start] PowerShell is locked down on this PC by device management. This program will not work around it. Please contact IT.
if "%RC%"=="9009" echo [Cannot start] Windows PowerShell was not found on this PC.
if not "%RC%"=="2" if not "%RC%"=="3" if not "%RC%"=="4" if not "%RC%"=="9009" echo [Cannot start] Unexpected result from the safety check, code %RC%.
echo.
pause
exit /b %RC%
