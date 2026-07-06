# WinTools one-liner launcher
# Usage: irm https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1 | iex

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator rights..." -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/wintools_ru.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm $scriptUrl | iex`""
    exit
}

$scriptUrl = "https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/wintools_ru.ps1"
Invoke-Expression (Invoke-RestMethod $scriptUrl)
