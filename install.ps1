# ============================================================
# WinTools Installer / Launcher
# Chooses language and Windows version, auto-detects mismatch
# Usage: irm https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1 | iex
# ============================================================

# --- Request Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator rights..." -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm $scriptUrl | iex`""
    exit
}

# --- Auto-detect Windows version ---
function Get-WindowsVersionInfo {
    $os = Get-WmiObject Win32_OperatingSystem
    $caption = $os.Caption
    $build = $os.BuildNumber

    if ($caption -match "Windows 10") {
        if ($caption -match "Pro")        { return @{Key="win10pro";   Name="Windows 10 Pro";             Build=$build} }
        elseif ($caption -match "Домашняя|Home") { return @{Key="win10home";  Name="Windows 10 Home";            Build=$build} }
        else                                { return @{Key="win10pro";   Name="Windows 10 Pro";             Build=$build} }
    }
    elseif ($caption -match "Windows 11") {
        if ($caption -match "LTSC|Enterprise") { return @{Key="win11ltsc"; Name="Windows 11 Enterprise LTSC"; Build=$build} }
        elseif ($caption -match "Insider")      { return @{Key="win11insider"; Name="Windows 11 InsiderPreview Pro"; Build=$build} }
        elseif ($caption -match "Pro")          { return @{Key="win11pro"; Name="Windows 11 Pro"; Build=$build} }
        elseif ($caption -match "Домашняя|Home") { return @{Key="win11home"; Name="Windows 11 Home"; Build=$build} }
        else                                    { return @{Key="win11pro"; Name="Windows 11 Pro"; Build=$build} }
    }
    return @{Key="unknown"; Name=$caption; Build=$build}
}

# --- Language strings ---
$ru = @{
    Title    = "WINTOOLS - УСТАНОВЩИК"
    LangAsk  = "Выберите язык / Choose language:"
    Lang1    = "Русский"
    Lang2    = "English"
    VerAsk   = "Выберите вашу версию Windows:"
    Detected = "Обнаружена система:"
    Mismatch = "ВНИМАНИЕ: Вы выбрали '{0}', но у вас установлена '{1}'!"
    AutoFix  = "Автоматически переключаю на вашу версию."
    Correct  = "Выбор совпадает с обнаруженной системой."
    Download = "Загрузка скрипта..."
    Run      = "Запуск WinTools..."
    Error    = "Ошибка загрузки. Проверьте интернет-соединение."
    Invalid  = "Неверный выбор."
    PressKey = "Нажмите любую клавишу для выхода..."
}

$en = @{
    Title    = "WINTOOLS - INSTALLER"
    LangAsk  = "Выберите язык / Choose language:"
    Lang1    = "Русский"
    Lang2    = "English"
    VerAsk   = "Select your Windows version:"
    Detected = "Detected system:"
    Mismatch = "WARNING: You selected '{0}' but you have '{1}' installed!"
    AutoFix  = "Automatically switching to your actual version."
    Correct  = "Selection matches detected system."
    Download = "Downloading script..."
    Run      = "Starting WinTools..."
    Error    = "Download error. Check your internet connection."
    Invalid  = "Invalid choice."
    PressKey = "Press any key to exit..."
}

# --- Main ---
Clear-Host
Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host "  |           WINTOOLS - WINDOWS OPTIMIZATION SUITE               |" -ForegroundColor Cyan
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host ""

# Step 1: Language
Write-Host "  Выберите язык / Choose language:" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Русский" -ForegroundColor Green
Write-Host "  [2] English" -ForegroundColor Green
Write-Host ""
Write-Host "  Choice: " -ForegroundColor White -NoNewline
$langChoice = Read-Host

if ($langChoice -eq "1") { $L = $ru; $langCode = "ru" }
elseif ($langChoice -eq "2") { $L = $en; $langCode = "en" }
else { Write-Host "  Invalid choice." -ForegroundColor Red; Start-Sleep 2; exit }

# Step 2: Windows version
$versions = @(
    @{Key="win10home";    Ru="Windows 10 Домашняя";       En="Windows 10 Home"}
    @{Key="win10pro";     Ru="Windows 10 Pro";            En="Windows 10 Pro"}
    @{Key="win11home";    Ru="Windows 11 Домашняя";       En="Windows 11 Home"}
    @{Key="win11pro";     Ru="Windows 11 Pro";            En="Windows 11 Pro"}
    @{Key="win11ltsc";    Ru="Windows 11 Enterprise LTSC"; En="Windows 11 Enterprise LTSC"}
    @{Key="win11insider"; Ru="Windows 11 InsiderPreview Pro"; En="Windows 11 InsiderPreview Pro"}
)

Clear-Host
Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host "  |           $($L.Title)  " -ForegroundColor Cyan
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host ""

# Auto-detect
$detected = Get-WindowsVersionInfo
Write-Host "  $($L.Detected) $($detected.Name) (Build $($detected.Build))" -ForegroundColor Yellow
Write-Host ""

Write-Host "  $($L.VerAsk)" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $versions.Count; $i++) {
    $v = $versions[$i]
    $label = if ($langCode -eq "ru") { $v.Ru } else { $v.En }
    $marker = if ($v.Key -eq $detected.Key) { " <<< DETECTED" } else { "" }
    $color = if ($v.Key -eq $detected.Key) { "Green" } else { "White" }
    Write-Host ("  [{0}] {1}{2}" -f ($i+1), $label, $marker) -ForegroundColor $color
}
Write-Host ""
Write-Host "  Choice: " -ForegroundColor White -NoNewline
$verChoice = Read-Host

$selectedKey = $null
if ($verChoice -match "^\d+$" -and [int]$verChoice -ge 1 -and [int]$verChoice -le $versions.Count) {
    $selectedKey = $versions[[int]$verChoice - 1].Key
}

if (-not $selectedKey) {
    Write-Host "  $($L.Invalid)" -ForegroundColor Red
    Start-Sleep 2; exit
}

# Step 3: Verify match
if ($selectedKey -ne $detected.Key) {
    $selName = ($versions | Where-Object { $_.Key -eq $selectedKey } | ForEach-Object { if ($langCode -eq "ru") { $_.Ru } else { $_.En } })
    Write-Host ""
    Write-Host ("  $($L.Mismatch)" -f $selName, $detected.Name) -ForegroundColor Red
    Write-Host "  $($L.AutoFix)" -ForegroundColor Yellow
    $selectedKey = $detected.Key
    Start-Sleep 3
} else {
    Write-Host ""
    Write-Host "  $($L.Correct)" -ForegroundColor Green
    Start-Sleep 1
}

# Step 4: Download and run
$scriptName = "wintools_$langCode.ps1"
$baseUrl = "https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main"
$scriptUrl = "$baseUrl/$scriptName"

Write-Host ""
Write-Host "  $($L.Download)" -ForegroundColor Cyan
Write-Host "  URL: $scriptUrl" -ForegroundColor DarkGray
Write-Host ""

try {
    $scriptContent = Invoke-RestMethod $scriptUrl -ErrorAction Stop
    Write-Host "  $($L.Run)" -ForegroundColor Green
    # Pass the detected Windows version to the script
    $scriptContent = $scriptContent -replace '^\$WindowsVersion\s*=.*', "`$WindowsVersion = '$selectedKey'"
    Invoke-Expression $scriptContent
} catch {
    Write-Host "  $($L.Error)" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $($L.PressKey)" -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
