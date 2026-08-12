[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidOverwritingBuiltInCmdlets",
    "",
    Justification = "This isolated test intentionally mocks console and registry commands."
)]
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($scriptFile in @("wintools_ru.ps1", "wintools_en.ps1")) {
    $path = Join-Path $repoRoot $scriptFile
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count) { throw "$scriptFile has parser errors" }

    $menu = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Menu-Registry"
    }, $true) | Select-Object -First 1
    if (-not $menu) { throw "$scriptFile has no Menu-Registry function" }

    . ([scriptblock]::Create($menu.Extent.Text))

    $script:registry = @{}
    $script:choice = "0"
    $script:failures = @()
    $Script:IsWin11 = $true

    function Draw-Header($title) { }
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$Arguments) $null = $Arguments }
    function Write-OK($message) { }
    function Write-INFO($message) { }
    function Write-FAIL($message) { $script:failures += "$message" }
    function Pause-Menu { }
    function Confirm-ActionPreview($lines) { $null = $lines; return $true }
    function Read-Host { return $script:choice }
    function Get-ChildItem([string]$Path, $ErrorAction) {
        if ($Path -like "*Tcpip*Interfaces") {
            return [pscustomobject]@{PSPath="Mock:\TcpInterface"}
        }
        return @()
    }
    function Get-ItemProperty([string]$Path, $ErrorAction) {
        if ($Path -eq "Mock:\TcpInterface") {
            return [pscustomobject]@{DhcpIPAddress="192.168.1.20"; IPAddress=$null}
        }
        return $null
    }
    function Get-ItemPropertyValue([string]$Path, [string]$Name, $ErrorAction) {
        $key = "$Path|$Name"
        if (-not $script:registry.ContainsKey($key)) { throw "missing registry value" }
        return $script:registry[$key]
    }
    function Set-RegLogged($path, $name, $value, $type, $desc) {
        $script:registry["$path|$name"] = $value
    }
    function Write-ActionLog($type, $target, $oldValue, $desc) { }
    function Test-Path([string]$Path) { $null = $Path; return $false }
    function Stop-Process { param([Parameter(ValueFromRemainingArguments)]$Arguments) $null = $Arguments }
    function Start-Process { param([Parameter(ValueFromRemainingArguments)]$Arguments) $null = $Arguments }
    function Start-Sleep { param([Parameter(ValueFromRemainingArguments)]$Arguments) $null = $Arguments }
    function fsutil {
        param([Parameter(ValueFromRemainingArguments)]$Arguments)
        if ($Arguments -contains "disablelastaccess") { "DisableLastAccess = 0" }
        elseif ($Arguments -contains "disable8dot3") { "Disable8dot3 = 0" }
    }
    function powercfg {
        param([Parameter(ValueFromRemainingArguments)]$Arguments)
        if ($Arguments -contains "/hibernate") {
            $enabled = $Arguments -contains "on"
            $script:registry["HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled"] = if ($enabled) { 1 } else { 0 }
        }
        $global:LASTEXITCODE = 0
    }

    $hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers|HwSchMode"

    $script:choice = "+1"
    Menu-Registry
    if ($script:registry[$hagsKey] -ne 2) { throw "${scriptFile}: +1 did not enable tweak 1" }

    $script:choice = "-1"
    Menu-Registry
    if ($script:registry[$hagsKey] -ne 1) { throw "${scriptFile}: -1 did not disable tweak 1" }

    $script:choice = "1"
    Menu-Registry
    if ($script:registry[$hagsKey] -ne 2) { throw "${scriptFile}: N did not toggle tweak 1 on" }

    $script:choice = "1"
    Menu-Registry
    if ($script:registry[$hagsKey] -ne 1) { throw "${scriptFile}: N did not toggle tweak 1 off" }

    $gameDvrKey = "HKCU:\System\GameConfigStore|GameDVR_Enabled"
    $captureKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR|AppCaptureEnabled"
    $script:choice = "+4"
    Menu-Registry
    if ($script:registry[$gameDvrKey] -ne 0 -or $script:registry[$captureKey] -ne 0) {
        throw "${scriptFile}: +4 did not enable the Game DVR tweak"
    }

    $script:choice = "-4"
    Menu-Registry
    if ($script:registry[$gameDvrKey] -ne 1 -or $script:registry[$captureKey] -ne 1) {
        throw "${scriptFile}: -4 did not restore Game DVR"
    }

    # This is the exact mixed list from the reported bug: one toggle plus
    # several explicit disables in a single input.
    $script:choice = "2,-3,-4,-6,-7,-8,-9"
    Menu-Registry
    $expectedValues = @{
        "Mock:\TcpInterface|TcpAckFrequency" = 1
        "Mock:\TcpInterface|TCPNoDelay" = 1
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling|PowerThrottlingOff" = 0
        $gameDvrKey = 1
        $captureKey = 1
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power|HiberbootEnabled" = 1
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo|Enabled" = 1
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry" = 1
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|DoNotShowFeedbackNotifications" = 0
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive|DisableFileSyncNGSC" = 0
    }
    foreach ($key in $expectedValues.Keys) {
        if ($script:registry[$key] -ne $expectedValues[$key]) {
            throw "${scriptFile}: mixed list produced the wrong value for $key"
        }
    }

    # Ranges can also carry a mode prefix.
    $script:choice = "+3-4"
    Menu-Registry
    if ($script:registry["HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling|PowerThrottlingOff"] -ne 1 -or
        $script:registry[$gameDvrKey] -ne 0) {
        throw "${scriptFile}: +3-4 range was not enabled"
    }

    # Release 2.0 tweaks 17-24 are all reversible and work in one range.
    $script:choice = "+17-24"
    Menu-Registry
    $releaseEnabled = @{
        "HKCU:\Software\Microsoft\GameBar|AllowAutoGameMode" = 1
        "HKCU:\Software\Microsoft\GameBar|AutoGameModeEnabled" = 1
        "HKCU:\Control Panel\Mouse|MouseSpeed" = "0"
        "HKCU:\Control Panel\Mouse|MouseThreshold1" = "0"
        "HKCU:\Control Panel\Mouse|MouseThreshold2" = "0"
        "HKLM:\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests" = 0
        "HKCU:\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions" = 1
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications|GlobalUserDisabled" = 1
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications|ToastEnabled" = 0
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled" = 0
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowSecondsInSystemClock" = 1
    }
    foreach ($key in $releaseEnabled.Keys) {
        if ("$($script:registry[$key])" -ne "$($releaseEnabled[$key])") {
            throw "${scriptFile}: +17-24 produced the wrong value for $key"
        }
    }

    $script:choice = "-17-24"
    Menu-Registry
    $releaseDisabled = @{
        "HKCU:\Software\Microsoft\GameBar|AllowAutoGameMode" = 0
        "HKCU:\Software\Microsoft\GameBar|AutoGameModeEnabled" = 0
        "HKCU:\Control Panel\Mouse|MouseSpeed" = "1"
        "HKCU:\Control Panel\Mouse|MouseThreshold1" = "6"
        "HKCU:\Control Panel\Mouse|MouseThreshold2" = "10"
        "HKLM:\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests" = 1
        "HKCU:\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions" = 0
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications|GlobalUserDisabled" = 0
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications|ToastEnabled" = 1
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power|HibernateEnabled" = 1
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowSecondsInSystemClock" = 0
    }
    foreach ($key in $releaseDisabled.Keys) {
        if ("$($script:registry[$key])" -ne "$($releaseDisabled[$key])") {
            throw "${scriptFile}: -17-24 did not restore $key"
        }
    }

    if ($script:failures.Count -gt 0) {
        throw "$scriptFile reported failure(s): $($script:failures -join '; ')"
    }

    Remove-Item Function:\Menu-Registry, Function:\Draw-Header, Function:\Write-Host,
        Function:\Write-OK, Function:\Write-INFO, Function:\Write-FAIL,
        Function:\Pause-Menu, Function:\Confirm-ActionPreview, Function:\Read-Host,
        Function:\Get-ChildItem, Function:\Test-Path,
        Function:\Get-ItemProperty, Function:\Get-ItemPropertyValue, Function:\Set-RegLogged,
        Function:\Write-ActionLog, Function:\Stop-Process, Function:\Start-Process,
        Function:\Start-Sleep, Function:\fsutil, Function:\powercfg -Force

    Write-Host "Tweak toggle checks passed: $scriptFile" -ForegroundColor Green
}
