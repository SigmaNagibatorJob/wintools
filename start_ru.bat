@echo off
setlocal
set "WINTOOLS_LAUNCHER=%~f0"
title WinTools
cd /d "%~dp0"

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell.exe -NoProfile -Command "Start-Process -FilePath $env:WINTOOLS_LAUNCHER -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wintools_ru.ps1"
if errorlevel 1 pause
endlocal
