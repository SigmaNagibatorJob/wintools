# WinTools - Windows Optimization Suite (English version)
# Run as Administrator
# Supports: Windows 10 Home/Pro, Windows 11 Home/Pro/Enterprise/LTSC/InsiderPreview
# Version is auto-detected or selected via install.ps1

[CmdletBinding()]
param(
    [ValidateSet("win10home", "win10pro", "win11home", "win11pro", "win11enterprise", "win11ltsc", "win11insider")]
    [string]$WindowsVersion
)

$Script:WinToolsVersion = "2.0.0"
$Script:WinToolsLanguage = "en"
$Script:Repository = "SigmaNagibatorJob/wintools"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ERROR: Run as Administrator!" -ForegroundColor Red
    Start-Sleep 3; exit
}

# ============================================================
# WINDOWS VERSION DETECTION
# ============================================================
# Compatibility wrapper for Windows PowerShell 5.1 and PowerShell 7.
function Get-WinToolsCimInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [Alias("Class")]
        [string]$ClassName,
        [string]$Namespace = "root/cimv2"
    )

    $cimParams = @{ ClassName = $ClassName; Namespace = $Namespace }
    if ($PSBoundParameters.ContainsKey("ErrorAction")) {
        $cimParams.ErrorAction = $PSBoundParameters["ErrorAction"]
    }
    Get-CimInstance @cimParams
}

function Get-WindowsVersion {
    $os = Get-WinToolsCimInstance Win32_OperatingSystem
    $caption = $os.Caption
    if ($caption -match "Windows 10") {
        if ($caption -match "Pro")        { return "win10pro" }
        elseif ($caption -match "Home")   { return "win10home" }
        else                              { return "win10pro" }
    }
    elseif ($caption -match "Windows 11") {
        if ($caption -match "Insider")          { return "win11insider" }
        elseif ($caption -match "LTSC")         { return "win11ltsc" }
        elseif ($caption -match "Enterprise")   { return "win11enterprise" }
        elseif ($caption -match "Pro")          { return "win11pro" }
        elseif ($caption -match "Home")         { return "win11home" }
        else                                    { return "win11pro" }
    }
    return "unknown"
}

$Script:WinVer = if ($WindowsVersion) { $WindowsVersion } else { Get-WindowsVersion }
$Script:WinVerName = switch ($Script:WinVer) {
    "win10home"    { "Windows 10 Home" }
    "win10pro"     { "Windows 10 Pro" }
    "win11home"    { "Windows 11 Home" }
    "win11pro"        { "Windows 11 Pro" }
    "win11enterprise" { "Windows 11 Enterprise" }
    "win11ltsc"       { "Windows 11 Enterprise LTSC" }
    "win11insider" { "Windows 11 InsiderPreview Pro" }
    default        { "Unknown version" }
}

$Script:IsWin10 = $Script:WinVer -match "win10"
$Script:IsWin11 = $Script:WinVer -match "win11"
$Script:IsLTSC  = $Script:WinVer -eq "win11ltsc"
$Script:IsHome  = $Script:WinVer -match "home"

function Write-OK($msg)   { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [-] $msg" -ForegroundColor DarkGray }
function Write-INFO($msg) { Write-Host "  [*] $msg" -ForegroundColor Yellow }
function Write-FAIL($msg) { Write-Host "  [!] $msg" -ForegroundColor Red }

# ============================================================
# ACTION LOG (for undo)
# ============================================================
$Global:LogPath = "$env:ProgramData\WinTools\actions_log.csv"
if (-not (Test-Path "$env:ProgramData\WinTools")) {
    New-Item -Path "$env:ProgramData\WinTools" -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $Global:LogPath)) {
    "Timestamp,Type,Target,OldValue,Desc" | Out-File -FilePath $Global:LogPath -Encoding UTF8
}

function Write-ActionLog($type, $target, $oldValue, $desc) {
    [pscustomobject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Type      = $type
        Target    = $target
        OldValue  = if ($null -eq $oldValue) { "NULL" } else { "$oldValue" }
        Desc      = $desc
    } | Export-Csv -Path $Global:LogPath -Append -NoTypeInformation -Encoding UTF8
}

function Set-RegLogged($path, $name, $value, $type, $desc) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    }

    $oldExists = $false
    $old = $null
    try {
        $old = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
        $oldExists = $true
    } catch {
        $oldExists = $false
    }

    # Set-ItemProperty does not support -Type. That parameter used to make
    # almost every tweak fail even though the script still printed "success".
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
    $actual = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
    if ("$actual" -ne "$value") {
        throw "Registry verification failed: $path\$name (expected '$value', got '$actual')"
    }

    Write-ActionLog -type "Registry" -target "$path|$name" -oldValue $(if ($oldExists) { $old } else { $null }) -desc $desc
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  [ Press any key to return ]" -ForegroundColor DarkGray
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        $null = Read-Host
    }
}

function Get-FolderSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    $s = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $s) { return 0 }
    return [math]::Round($s / 1GB, 2)
}

function Disable-Svc($name, $label) {
    $found = Get-Service -Name "$name*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        Write-SKIP "Not found: $label"
        return
    }
    if ($found.StartType -eq "Disabled") {
        Write-SKIP "Already disabled: $label"
        return
    }

    try {
        $oldStartType = $found.StartType
        $oldStatus = $found.Status
        if ($found.Status -ne "Stopped") {
            Stop-Service -Name $found.Name -Force -ErrorAction Stop
        }
        Set-Service -Name $found.Name -StartupType Disabled -ErrorAction Stop
        $found = Get-Service -Name $found.Name -ErrorAction Stop
        if ($found.StartType -ne "Disabled") { throw "startup type did not change" }
        Write-ActionLog -type "Service" -target $found.Name -oldValue "$oldStartType|$oldStatus" -desc $label
        Write-OK "Disabled: $label"
    } catch {
        Write-FAIL "Could not disable '$label': $($_.Exception.Message)"
    }
}

function ConvertTo-NumberList($inputText, [int]$maxNumber) {
    $numbers = @()
    foreach ($rawToken in ($inputText -split ",")) {
        $token = $rawToken.Trim()
        if ($token -notmatch '^(\d+)(?:-(\d+))?$') {
            throw "Invalid item: '$token'"
        }
        $first = [int]$matches[1]
        $last = if ($matches[2]) { [int]$matches[2] } else { $first }
        if ($first -lt 1 -or $last -lt $first -or $last -gt $maxNumber) {
            throw "Number or range is outside the list: '$token'"
        }
        for ($number = $first; $number -le $last; $number++) {
            if ($numbers -notcontains $number) { $numbers += $number }
        }
    }
    return $numbers
}

function Confirm-ActionPreview($lines) {
    Write-Host ""
    Write-Host "  +---------------------- PREVIEW ---------------------------------+" -ForegroundColor Cyan
    foreach ($line in $lines) { Write-Host "  $line" -ForegroundColor White }
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  Apply changes? [Y = yes; N/Enter = return]: " -ForegroundColor Yellow -NoNewline
    $answer = (Read-Host).Trim()
    return $answer -match '^(?i:y|yes)$'
}

function Enable-Svc($name, $label) {
    $found = Get-Service -Name "$name*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Write-SKIP "Not found: $label"; return }
    if ($found.StartType -ne "Disabled") { Write-SKIP "Already enabled: $label"; return }

    try {
        $oldStartType = "Manual"
        $oldStatus = "Running"
        $logEntries = @(Import-Csv -Path $Global:LogPath -ErrorAction SilentlyContinue | Where-Object {
            $_.Type -eq "Service" -and $_.Target -eq $found.Name -and $_.OldValue -ne "NULL"
        })
        if ($logEntries.Count -gt 0) {
            $parts = $logEntries[-1].OldValue -split "\|", 2
            if ($parts[0] -and $parts[0] -ne "Disabled") { $oldStartType = $parts[0] }
            if ($parts.Count -gt 1) { $oldStatus = $parts[1] }
        }

        Set-Service -Name $found.Name -StartupType $oldStartType -ErrorAction Stop
        if ($oldStatus -eq "Running" -or $logEntries.Count -eq 0) {
            try { Start-Service -Name $found.Name -ErrorAction Stop } catch {
                Write-INFO "Startup type was restored, but the service could not start now: $($_.Exception.Message)"
            }
        }
        $restored = Get-Service -Name $found.Name -ErrorAction Stop
        if ($restored.StartType -eq "Disabled") { throw "startup type is still Disabled" }
        Write-ActionLog -type "Service" -target $found.Name -oldValue "Disabled|Stopped" -desc $label
        Write-OK "Enabled: $label ($($restored.StartType))"
    } catch {
        Write-FAIL "Could not enable '$label': $($_.Exception.Message)"
    }
}

function Get-StatusLine {
    $free    = [math]::Round((Get-PSDrive C -ErrorAction SilentlyContinue).Free/1GB,1)
    $os      = Get-WinToolsCimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramFree = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $ramTotal= [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    $ramUsed = [math]::Round($ramTotal - $ramFree,1)
    $proc    = (Get-Process -ErrorAction SilentlyContinue).Count
    $cpu     = [math]::Round((Get-WinToolsCimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average,0)
    return "  Disk C: $free GB free   RAM: $ramUsed/$ramTotal GB   CPU: $cpu%   Processes: $proc"
}

function Draw-Header($title) {
    Clear-Host
    Write-Host ""
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host "  |            WINTOOLS - Windows Optimization Suite               |" -ForegroundColor Cyan
    Write-Host "  |            $Script:WinVerName$((' ' * (50 - $Script:WinVerName.Length)))|" -ForegroundColor DarkCyan
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host (Get-StatusLine) -ForegroundColor DarkCyan
    Write-Host "  +================================================================+" -ForegroundColor DarkGray
    if ($title) {
        Write-Host ("  |  >> {0,-60}|" -f $title) -ForegroundColor White
        Write-Host "  +================================================================+" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ============================================================
# MENU 1 - SERVICES
# ============================================================
function Menu-Services {
    Draw-Header "SERVICES - Disable unused Windows services"

    $svcList = @(
        @{N="DiagTrack";              Desc="Telemetry - collects usage data and sends to Microsoft"},
        @{N="dmwappushservice";       Desc="WAP Push message receiver for telemetry"},
        @{N="DoSvc";                  Desc="Delivery Optimization P2P - shares updates via your internet"},
        @{N="DusmSvc";                Desc="Data Usage tracker"},
        @{N="XblAuthManager";         Desc="Xbox Live Auth Manager"},
        @{N="XblGameSave";            Desc="Xbox Live cloud saves"},
        @{N="XboxGipSvc";             Desc="Xbox Accessory Management (controllers)"},
        @{N="XboxNetApiSvc";          Desc="Xbox Network (multiplayer via MS)"},
        @{N="TermService";            Desc="Remote Desktop (RDP) - allows remote connections"},
        @{N="UmRdpService";           Desc="RDP Port Redirector"},
        @{N="SessionEnv";             Desc="Remote Desktop Configuration"},
        @{N="WinRM";                  Desc="Windows Remote Management via PowerShell"},
        @{N="RemoteRegistry";         Desc="Allows remote registry changes from other PCs"},
        @{N="vmicguestinterface";     Desc="Hyper-V Guest Interface"},
        @{N="vmicheartbeat";          Desc="Hyper-V Heartbeat"},
        @{N="vmickvpexchange";        Desc="Hyper-V Data Exchange"},
        @{N="vmicrdv";                Desc="Hyper-V Remote Desktop"},
        @{N="vmicshutdown";           Desc="Hyper-V Shutdown"},
        @{N="vmictimesync";           Desc="Hyper-V Time Sync"},
        @{N="vmicvmsession";          Desc="Hyper-V PowerShell Direct"},
        @{N="vmicvss";                Desc="Hyper-V VSS"},
        @{N="HvHost";                 Desc="Hyper-V Host service"},
        @{N="Spooler";                Desc="Print Spooler - needed for printers"},
        @{N="PrintNotify";            Desc="Printer Notifications"},
        @{N="PrintWorkflowUserSvc";   Desc="Print Workflow from Store apps"},
        @{N="LanmanServer";           Desc="File/folder sharing over LAN"},
        @{N="lltdsvc";                Desc="Link-Layer Topology (network map)"},
        @{N="lmhosts";                Desc="NetBIOS over TCP/IP (legacy)"},
        @{N="FDResPub";               Desc="Publishes this PC for network discovery"},
        @{N="fdPHost";                Desc="Function Discovery Host"},
        @{N="SSDPSRV";                Desc="SSDP Discovery (UPnP)"},
        @{N="upnphost";               Desc="UPnP Device Host"},
        @{N="p2pimsvc";               Desc="Peer Name Resolution (legacy)"},
        @{N="p2psvc";                 Desc="Peer Networking (legacy)"},
        @{N="PNRPAutoReg";            Desc="PNRP Machine Name Publication"},
        @{N="PNRPsvc";                Desc="PNRP Protocol"},
        @{N="DPS";                    Desc="Diagnostic Policy Service"},
        @{N="WdiServiceHost";         Desc="Diagnostic Service Host"},
        @{N="WdiSystemHost";          Desc="Diagnostic System Host"},
        @{N="WerSvc";                 Desc="Windows Error Reporting"},
        @{N="wercplsupport";          Desc="Error Reporting UI"},
        @{N="PcaSvc";                 Desc="Program Compatibility Assistant"},
        @{N="diagnosticshub.standardcollector.service"; Desc="Diagnostics Hub collector"},
        @{N="TrkWks";                 Desc="Distributed Link Tracking"},
        @{N="FontCache";              Desc="Font Cache"},
        @{N="ShellHWDetection";       Desc="AutoPlay USB/CD detection"},
        @{N="MapsBroker";             Desc="Downloaded Maps"},
        @{N="PhoneSvc";               Desc="Phone Service (calls/SMS on PC)"},
        @{N="WFDSConMgrSvc";          Desc="Wi-Fi Direct"},
        @{N="MessagingService";       Desc="Messaging Service (SMS)"},
        @{N="icssvc";                 Desc="Mobile Hotspot"},
        @{N="SmsRouter";              Desc="SMS Router"},
        @{N="WiaRpc";                 Desc="Camera/Scanner events"},
        @{N="stisvc";                 Desc="Windows Image Acquisition"},
        @{N="Netlogon";               Desc="Domain login (corporate only)"},
        @{N="CDPSvc";                 Desc="Connected Devices Platform"},
        @{N="BcastDVRUserService";    Desc="Game DVR background recording"},
        @{N="CaptureService";         Desc="Screen Capture for Game Bar"},
        @{N="NaturalAuthentication";  Desc="Windows Hello Face login"},
        @{N="GraphicsPerfSvc";        Desc="GPU performance monitor"},
        @{N="WpnService";             Desc="Push notifications"},
        @{N="RetailDemo";             Desc="Retail Demo mode"},
        @{N="SysMain";                Desc="Superfetch - preloads apps (useful on HDD, useless on SSD)"},
        @{N="WSearch";                Desc="Windows Search indexing"},
        @{N="WbioSrvc";               Desc="Biometrics - fingerprint/face login"},
        @{N="RmSvc";                  Desc="Radio Management - Wi-Fi/BT toggle"},
        @{N="wscsvc";                 Desc="Windows Security Center"}
    )

    if ($Script:WinVer -eq "win11insider") {
        Write-INFO "Insider Preview: added Insider-specific services"
    }

    Write-Host "  Green = safe to disable. Yellow = think if you need it." -ForegroundColor DarkGray
    Write-Host ""

    $recommendedOff = @("DiagTrack","dmwappushservice","DoSvc","DusmSvc","XblAuthManager","XblGameSave","XboxGipSvc","XboxNetApiSvc",
        "TermService","UmRdpService","SessionEnv","WinRM","RemoteRegistry",
        "vmicguestinterface","vmicheartbeat","vmickvpexchange","vmicrdv","vmicshutdown","vmictimesync","vmicvmsession","vmicvss","HvHost",
        "LanmanServer","lltdsvc","lmhosts","FDResPub","fdPHost","SSDPSRV","upnphost","p2pimsvc","p2psvc","PNRPAutoReg","PNRPsvc",
        "DPS","WdiServiceHost","WdiSystemHost","WerSvc","wercplsupport","PcaSvc","diagnosticshub.standardcollector.service",
        "TrkWks","FontCache","ShellHWDetection","MapsBroker","PhoneSvc","WFDSConMgrSvc","MessagingService","icssvc","SmsRouter",
        "WiaRpc","stisvc","Netlogon","CDPSvc","BcastDVRUserService","CaptureService","NaturalAuthentication","GraphicsPerfSvc",
        "WpnService","RetailDemo","SysMain","WSearch")

    $i = 1
    $indexMap = @{}
    foreach ($s in $svcList) {
        $found = Get-Service | Where-Object { $_.Name -like "$($s.N)*" } | Select-Object -First 1
        $status = if (-not $found) { "N/A" } elseif ($found.StartType -eq "Disabled") { "OFF" } else { "ON" }
        $isRec = $recommendedOff -contains $s.N
        $color = if ($status -eq "OFF" -or $status -eq "N/A") { "DarkGray" } elseif ($isRec) { "Green" } else { "Yellow" }
        $statusTag = if ($status -eq "ON") { "[ON ]" } elseif ($status -eq "OFF") { "[off]" } else { "[N/A]" }
        Write-Host ("  {0,3}) {1} {2,-22} {3}" -f $i, $statusTag, $s.N, $s.Desc) -ForegroundColor $color
        $indexMap[$i] = $s.N
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Numbers toggle services: 1,3,5-9                              |" -ForegroundColor Cyan
    Write-Host "  | [A] Disable all recommended (green)                           |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                         |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    $forceDisable = $choice -eq "A" -or $choice -eq "a"
    try {
        $selectedNames = if ($forceDisable) {
            $recommendedOff
        } else {
            @(ConvertTo-NumberList $choice $svcList.Count | ForEach-Object { $indexMap[$_] })
        }
    } catch {
        Write-FAIL "Could not parse the list: $($_.Exception.Message)"
        Pause-Menu; Menu-Services; return
    }

    $plan = @()
    foreach ($svcName in ($selectedNames | Select-Object -Unique)) {
        $found = Get-Service -Name "$svcName*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { continue }
        if ($forceDisable -and $found.StartType -eq "Disabled") { continue }
        $desc = ($svcList | Where-Object { $_.N -eq $svcName }).Desc
        $enable = if ($forceDisable) { $false } else { $found.StartType -eq "Disabled" }
        $action = if ($enable) { "ENABLE" } else { "DISABLE" }
        $plan += [pscustomobject]@{Name=$svcName; Desc=$desc; Enable=$enable; Preview="[$action] $($found.Name) — $desc"}
    }

    if ($plan.Count -eq 0) {
        Write-INFO "No available services were selected"
        Pause-Menu; Menu-Services; return
    }
    if (-not (Confirm-ActionPreview ($plan.Preview))) { Menu-Services; return }

    foreach ($item in $plan) {
        if ($item.Enable) { Enable-Svc $item.Name $item.Desc }
        else { Disable-Svc $item.Name $item.Desc }
    }
    Pause-Menu
}

# ============================================================
# MENU 2 - REGISTRY TWEAKS
# ============================================================
function Menu-Registry {
    Draw-Header "REGISTRY TWEAKS - enable, disable and current status"
    Write-Host "  [ON] means that the optimization tweak is currently applied." -ForegroundColor DarkGray
    Write-Host "  A number toggles it; +number enables it; -number restores standard behavior." -ForegroundColor DarkGray
    Write-Host ""

    $tweaks = @(
        @{Num="1";  Rec=$true;  Desc="GPU Scheduling: lower game latency"}
        @{Num="2";  Rec=$true;  Desc="Disable Nagle: lower network latency"}
        @{Num="3";  Rec=$true;  Desc="Disable Power Throttling"}
        @{Num="4";  Rec=$true;  Desc="Disable Game DVR and background capture"}
        @{Num="5";  Rec=$true;  Desc="Minimize animations and visual effects"}
        @{Num="6";  Rec=$true;  Desc="Disable Windows Fast Startup"}
        @{Num="7";  Rec=$true;  Desc="Disable Advertising ID"}
        @{Num="8";  Rec=$true;  Desc="Minimum telemetry and no feedback prompts"}
        @{Num="9";  Rec=$false; Desc="Disable OneDrive synchronization"}
        @{Num="10"; Rec=$true;  Desc="Disable Spotlight, tips and suggestions"}
        @{Num="11"; Rec=$true;  Desc="Service shutdown timeout: 2 seconds"}
        @{Num="12"; Rec=$true;  Desc="NTFS: no Last Access or 8.3 names"}
        @{Num="13"; Rec=$true;  Desc="Disable AutoRun on removable drives"}
        @{Num="14"; Rec=$true;  Desc="Disable Delivery Optimization P2P"}
        @{Num="15"; Rec=$true;  Desc="Disable ink and typing personalization"}
    )
    if ($Script:IsWin11) {
        $tweaks += @{Num="16"; Rec=$true; Desc="Classic Windows 11 context menu"}
        $tweaks += @{Num="19"; Rec=$true; Desc="Disable Windows 11 widgets"}
    }

    $tweaks += @(
        @{Num="17"; Rec=$true;  Desc="Enable Windows Game Mode"}
        @{Num="18"; Rec=$false; Desc="Disable mouse acceleration"}
        @{Num="20"; Rec=$true;  Desc="Disable web search in Start"}
        @{Num="21"; Rec=$false; Desc="Disable background applications"}
        @{Num="22"; Rec=$false; Desc="Disable toast notifications"}
        @{Num="23"; Rec=$false; Desc="Disable hibernation"}
        @{Num="24"; Rec=$false; Desc="Show seconds in the system clock"}
    )
    $tweaks = @($tweaks | Sort-Object { [int]$_.Num })

    function Get-RegistryValue($path, $name) {
        try {
            return Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
        } catch {
            return $null
        }
    }

    function Get-ActiveTcpInterfaces {
        $result = @()
        $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($iface in $ifaces) {
            $props = Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue
            $addresses = @($props.DhcpIPAddress) + @($props.IPAddress)
            $ipv4 = $addresses | Where-Object {
                $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and
                $_ -notmatch '^(0\.0\.0\.0|127\.|169\.254\.)'
            } | Select-Object -First 1
            if ($ipv4) {
                $result += [pscustomobject]@{Path=$iface.PSPath; IPv4=$ipv4}
            }
        }
        return $result
    }

    function Get-TweakEnabled($num) {
        switch ($num) {
            "1" {
                return (Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode") -eq 2
            }
            "2" {
                $active = @(Get-ActiveTcpInterfaces)
                if ($active.Count -eq 0) { return $false }
                foreach ($iface in $active) {
                    if ((Get-RegistryValue $iface.Path "TcpAckFrequency") -ne 1 -or
                        (Get-RegistryValue $iface.Path "TCPNoDelay") -ne 1) {
                        return $false
                    }
                }
                return $true
            }
            "3" {
                return (Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff") -eq 1
            }
            "4" {
                return (Get-RegistryValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled") -eq 0 -and
                    (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled") -eq 0
            }
            "5" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting") -eq 2 -and
                    "$(Get-RegistryValue "HKCU:\Control Panel\Desktop" "MinAnimate")" -eq "0" -and
                    (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations") -eq 0
            }
            "6" {
                return (Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled") -eq 0
            }
            "7" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled") -eq 0
            }
            "8" {
                return (Get-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry") -eq 0 -and
                    (Get-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications") -eq 1
            }
            "9" {
                return (Get-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC") -eq 1
            }
            "10" {
                $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                foreach ($name in @("RotatingLockScreenEnabled", "ContentDeliveryAllowed", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SilentInstalledAppsEnabled")) {
                    if ((Get-RegistryValue $path $name) -ne 0) { return $false }
                }
                return $true
            }
            "11" {
                return "$(Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout")" -eq "2000"
            }
            "12" {
                $lastAccess = (& fsutil behavior query disablelastaccess 2>$null) -join " "
                $shortNames = (& fsutil behavior query disable8dot3 2>$null) -join " "
                return $lastAccess -match '(?i)DisableLastAccess\s*=\s*(?:0x)?1\b' -and
                    $shortNames -match '(?i)Disable8dot3\s*=\s*(?:0x)?1\b'
            }
            "13" {
                return (Get-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun") -eq 255
            }
            "14" {
                return (Get-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode") -eq 0
            }
            "15" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection") -eq 1 -and
                    (Get-RegistryValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection") -eq 1
            }
            "16" {
                return Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            }
            "17" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode") -eq 1 -and
                    (Get-RegistryValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled") -eq 1
            }
            "18" {
                $path = "HKCU:\Control Panel\Mouse"
                return "$(Get-RegistryValue $path "MouseSpeed")" -eq "0" -and
                    "$(Get-RegistryValue $path "MouseThreshold1")" -eq "0" -and
                    "$(Get-RegistryValue $path "MouseThreshold2")" -eq "0"
            }
            "19" {
                return (Get-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests") -eq 0
            }
            "20" {
                return (Get-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions") -eq 1
            }
            "21" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled") -eq 1
            }
            "22" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled") -eq 0
            }
            "23" {
                return (Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled") -eq 0
            }
            "24" {
                return (Get-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock") -eq 1
            }
            default { return $false }
        }
    }

    function Restart-ExplorerForTweak {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer.exe -ErrorAction Stop
    }

    function Set-TweakState($num, [bool]$enabled) {
        try {
            switch ($num) {
                "1" {
                    Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" $(if ($enabled) { 2 } else { 1 }) "DWord" "GPU Scheduling"
                }
                "2" {
                    $active = @(Get-ActiveTcpInterfaces)
                    if ($active.Count -eq 0) { throw "No active IPv4 interface was found" }
                    foreach ($iface in $active) {
                        Set-RegLogged $iface.Path "TcpAckFrequency" $(if ($enabled) { 1 } else { 2 }) "DWord" "Nagle TcpAckFrequency"
                        Set-RegLogged $iface.Path "TCPNoDelay" $(if ($enabled) { 1 } else { 0 }) "DWord" "Nagle TCPNoDelay"
                    }
                }
                "3" {
                    Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" $(if ($enabled) { 1 } else { 0 }) "DWord" "Power Throttling"
                }
                "4" {
                    $value = if ($enabled) { 0 } else { 1 }
                    Set-RegLogged "HKCU:\System\GameConfigStore" "GameDVR_Enabled" $value "DWord" "Game DVR"
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" $value "DWord" "App Capture"
                }
                "5" {
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" $(if ($enabled) { 2 } else { 0 }) "DWord" "Visual FX"
                    Set-RegLogged "HKCU:\Control Panel\Desktop" "MinAnimate" $(if ($enabled) { "0" } else { "1" }) "String" "MinAnimate"
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" $(if ($enabled) { 0 } else { 1 }) "DWord" "Taskbar Animations"
                    Restart-ExplorerForTweak
                }
                "6" {
                    Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" $(if ($enabled) { 0 } else { 1 }) "DWord" "Fast Startup"
                }
                "7" {
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" $(if ($enabled) { 0 } else { 1 }) "DWord" "Advertising ID"
                }
                "8" {
                    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                    Set-RegLogged $path "AllowTelemetry" $(if ($enabled) { 0 } else { 1 }) "DWord" "Telemetry"
                    Set-RegLogged $path "DoNotShowFeedbackNotifications" $(if ($enabled) { 1 } else { 0 }) "DWord" "Feedback Notifications"
                }
                "9" {
                    Set-RegLogged "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" $(if ($enabled) { 1 } else { 0 }) "DWord" "OneDrive"
                }
                "10" {
                    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                    $value = if ($enabled) { 0 } else { 1 }
                    foreach ($name in @("RotatingLockScreenEnabled", "ContentDeliveryAllowed", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SilentInstalledAppsEnabled")) {
                        Set-RegLogged $path $name $value "DWord" "Content Delivery: $name"
                    }
                }
                "11" {
                    Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" $(if ($enabled) { "2000" } else { "5000" }) "String" "Shutdown timeout"
                }
                "12" {
                    & fsutil behavior set disablelastaccess $(if ($enabled) { 1 } else { 2 }) | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "fsutil disablelastaccess: $LASTEXITCODE" }
                    & fsutil behavior set disable8dot3 $(if ($enabled) { 1 } else { 2 }) | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "fsutil disable8dot3: $LASTEXITCODE" }
                    Write-ActionLog -type "FSUtil" -target "NTFS" -oldValue "unknown" -desc "NTFS last access + 8.3 names"
                }
                "13" {
                    Set-RegLogged "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" $(if ($enabled) { 255 } else { 145 }) "DWord" "Autorun"
                }
                "14" {
                    Set-RegLogged "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" $(if ($enabled) { 0 } else { 1 }) "DWord" "Delivery Optimization"
                }
                "15" {
                    $path = "HKCU:\Software\Microsoft\InputPersonalization"
                    $value = if ($enabled) { 1 } else { 0 }
                    Set-RegLogged $path "RestrictImplicitInkCollection" $value "DWord" "Ink Collection"
                    Set-RegLogged $path "RestrictImplicitTextCollection" $value "DWord" "Text Collection"
                }
                "16" {
                    $root = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
                    $path = "$root\InprocServer32"
                    if ($enabled) {
                        Set-RegLogged $path "(default)" "" "String" "Classic Context Menu"
                    } elseif (Test-Path $root) {
                        Remove-Item $root -Recurse -Force -ErrorAction Stop
                        if (Test-Path $root) { throw "the registry key was not removed" }
                        Write-ActionLog -type "RegistryKey" -target $root -oldValue "present" -desc "Classic Context Menu"
                    }
                    Restart-ExplorerForTweak
                }
                "17" {
                    $value = if ($enabled) { 1 } else { 0 }
                    Set-RegLogged "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" $value "DWord" "Game Mode"
                    Set-RegLogged "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" $value "DWord" "Game Mode"
                }
                "18" {
                    $path = "HKCU:\Control Panel\Mouse"
                    Set-RegLogged $path "MouseSpeed" $(if ($enabled) { "0" } else { "1" }) "String" "Mouse acceleration"
                    Set-RegLogged $path "MouseThreshold1" $(if ($enabled) { "0" } else { "6" }) "String" "Mouse acceleration threshold 1"
                    Set-RegLogged $path "MouseThreshold2" $(if ($enabled) { "0" } else { "10" }) "String" "Mouse acceleration threshold 2"
                }
                "19" {
                    Set-RegLogged "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" $(if ($enabled) { 0 } else { 1 }) "DWord" "Widgets"
                }
                "20" {
                    Set-RegLogged "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" $(if ($enabled) { 1 } else { 0 }) "DWord" "Start web search"
                }
                "21" {
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" $(if ($enabled) { 1 } else { 0 }) "DWord" "Background applications"
                }
                "22" {
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled" $(if ($enabled) { 0 } else { 1 }) "DWord" "Toast notifications"
                }
                "23" {
                    $oldValue = Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled"
                    & powercfg /hibernate $(if ($enabled) { "off" } else { "on" }) | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate: $LASTEXITCODE" }
                    Write-ActionLog -type "PowerCfg" -target "Hibernate" -oldValue $oldValue -desc "Hibernation"
                }
                "24" {
                    Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" $(if ($enabled) { 1 } else { 0 }) "DWord" "Clock seconds"
                    Restart-ExplorerForTweak
                }
                default { throw "Unknown tweak number: $num" }
            }

            $actual = Get-TweakEnabled $num
            if ($enabled -and -not $actual) { throw "enable verification failed" }
            if (-not $enabled -and $actual) { throw "disable verification failed" }
            $stateText = if ($enabled) { "ENABLED" } else { "DISABLED" }
            Write-OK "Tweak [$num] $stateText"
        } catch {
            Write-FAIL "Could not change tweak [$num]: $($_.Exception.Message)"
        }
    }

    function ConvertTo-TweakActions($inputText) {
        $actions = @()
        foreach ($rawToken in ($inputText -split ",")) {
            $token = $rawToken.Trim()
            if ($token -notmatch '^([+-]?)(\d+)(?:-(\d+))?$') {
                throw "Invalid item: '$token'"
            }

            $prefix = $matches[1]
            $first = [int]$matches[2]
            $last = if ($matches[3]) { [int]$matches[3] } else { $first }
            if ($last -lt $first) { throw "Invalid range: '$token'" }

            $mode = if ($prefix -eq "+") {
                "Enable"
            } elseif ($prefix -eq "-") {
                "Disable"
            } else {
                "Toggle"
            }

            for ($number = $first; $number -le $last; $number++) {
                $num = "$number"
                if ($tweaks.Num -notcontains $num) {
                    throw "There is no tweak with that number: $num"
                }
                $actions += [pscustomobject]@{Num=$num; Mode=$mode}
            }
        }
        return $actions
    }

    foreach ($t in $tweaks) {
        $tag = if ($t.Rec) { "[REC]" } else { "[OPT]" }
        $enabled = Get-TweakEnabled $t.Num
        $state = if ($enabled) { "[ ON ]" } else { "[off ]" }
        $color = if ($enabled) { "Green" } elseif ($t.Rec) { "Yellow" } else { "DarkGray" }
        Write-Host ("  {0} {1} [{2,2}] {3}" -f $state, $tag, $t.Num, $t.Desc) -ForegroundColor $color
    }

    $allRec = ($tweaks | Where-Object { $_.Rec }).Num
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [N]  Toggle the tweak                                             |" -ForegroundColor White
    Write-Host "  | [+N] Enable the tweak                                      |" -ForegroundColor Green
    Write-Host "  | [-N] Disable tweak / restore standard                         |" -ForegroundColor Yellow
    Write-Host ("  |  {0,-64}|" -f "List: 2,-3,+4,5-7,+10-12") -ForegroundColor DarkCyan
    Write-Host "  | [A]  Enable ALL recommended tweaks                      |" -ForegroundColor Cyan
    Write-Host "  | [0]  Back to main menu                                        |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = (Read-Host).Trim()

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    try {
        $actions = if ($choice -eq "A" -or $choice -eq "a") {
            @($allRec | ForEach-Object { [pscustomobject]@{Num="$_"; Mode="Enable"} })
        } else {
            @(ConvertTo-TweakActions $choice)
        }
    } catch {
        Write-FAIL "Could not parse the list: $($_.Exception.Message)"
        Pause-Menu; Menu-Registry; return
    }

    $plan = @()
    foreach ($action in $actions) {
        $requestedState = switch ($action.Mode) {
            "Enable"  { $true }
            "Disable" { $false }
            default   { -not (Get-TweakEnabled $action.Num) }
        }
        $desc = ($tweaks | Where-Object { $_.Num -eq $action.Num }).Desc
        $verb = if ($requestedState) { "ENABLE TWEAK" } else { "DISABLE TWEAK" }
        $plan += [pscustomobject]@{Num=$action.Num; Enabled=$requestedState; Preview="[$verb] [$($action.Num)] $desc"}
    }

    if (-not (Confirm-ActionPreview ($plan.Preview))) { Menu-Registry; return }
    foreach ($item in $plan) { Set-TweakState $item.Num $item.Enabled }
    Pause-Menu
}

# ============================================================
# MENU 3 - SCHEDULED TASKS
# ============================================================
function Menu-Tasks {
    Draw-Header "SCHEDULED TASKS - Disable telemetry and diagnostic tasks"
    Write-Host "  These tasks run in the background and send data to Microsoft." -ForegroundColor DarkGray
    Write-Host "  All of them are safe to disable." -ForegroundColor DarkGray
    Write-Host ""

    $tasks = @(
        @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"; Desc="Sends app data to MS"}
        @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater";                Desc="Telemetry data updater"}
        @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask";                    Desc="Startup app tracking"}
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClient";                          Desc="Feedback telemetry"}
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClientOnScenarioDownload";        Desc="Feedback on scenario"}
        @{Path="\Microsoft\Windows\Windows Error Reporting\";Name="QueueReporting";                    Desc="Error reports to MS"}
        @{Path="\Microsoft\Windows\NetTrace\";               Name="GatherNetworkInfo";                  Desc="Network data collection"}
        @{Path="\Microsoft\Windows\SettingSync\";            Name="BackgroundUploadTask";               Desc="Sync settings to cloud"}
        @{Path="\Microsoft\Windows\SettingSync\";            Name="NetworkStateChangeTask";             Desc="Network sync trigger"}
        @{Path="\Microsoft\Windows\DiskDiagnostic\";         Name="Microsoft-Windows-DiskDiagnosticDataCollector"; Desc="Disk data to MS"}
        @{Path="\Microsoft\Windows\UNP\";                    Name="RunUpdateNotificationMgr";           Desc="Update nag notifications"}
    )

    if ($Script:WinVer -eq "win11insider") {
        $tasks += @{Path="\Microsoft\Windows\WindowsUpdate\"; Name="ScheduledStart"; Desc="Insider Preview: auto update check"}
        Write-INFO "Insider Preview: added Insider tasks"
    }

    $i = 1
    foreach ($t in $tasks) {
        $task   = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        $status = if ($task) { $task.State } else { "NOT FOUND" }
        $icon   = if ($status -eq "Disabled") { "[OFF]" } elseif ($status -eq "NOT FOUND") { "[N/A]" } else { "[ ON ]" }
        $color  = if ($status -eq "Disabled" -or $status -eq "NOT FOUND") { "DarkGray" } else { "Red" }
        Write-Host ("  {0} [{1,2}] {2,-48} {3}" -f $icon, $i, $t.Name, $t.Desc) -ForegroundColor $color
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Disable ALL tasks                                       |" -ForegroundColor Cyan
    Write-Host "  | Numbers toggle tasks: 1,3,5-8                                 |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    $forceDisable = $choice -eq "A" -or $choice -eq "a"
    try {
        $selected = if ($forceDisable) {
            $tasks
        } else {
            @(ConvertTo-NumberList $choice $tasks.Count | ForEach-Object { $tasks[$_ - 1] })
        }
    } catch {
        Write-FAIL "Could not parse the list: $($_.Exception.Message)"
        Pause-Menu; Menu-Tasks; return
    }

    $plan = @()
    foreach ($t in $selected) {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        if ($forceDisable -and $task.State -eq "Disabled") { continue }
        $enable = if ($forceDisable) { $false } else { $task.State -eq "Disabled" }
        $verb = if ($enable) { "ENABLE" } else { "DISABLE" }
        $plan += [pscustomobject]@{Task=$t; Enable=$enable; OldState=$task.State; Preview="[$verb] $($t.Name) — $($t.Desc)"}
    }
    if ($plan.Count -eq 0) {
        Write-INFO "No task state needs to change"
        Pause-Menu; Menu-Tasks; return
    }
    if (-not (Confirm-ActionPreview ($plan.Preview))) { Menu-Tasks; return }

    foreach ($item in $plan) {
        $t = $item.Task
        try {
            if ($item.Enable) {
                Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
            } else {
                Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
            }
            $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop
            if ($item.Enable -and $task.State -eq "Disabled") { throw "the task remained disabled" }
            if (-not $item.Enable -and $task.State -ne "Disabled") { throw "the task remained enabled" }
            Write-ActionLog -type "Task" -target "$($t.Path)|$($t.Name)" -oldValue $item.OldState -desc $t.Name
            Write-OK "$(if ($item.Enable) { 'Enabled' } else { 'Disabled' }): $($t.Name)"
        } catch {
            Write-FAIL "Could not change $($t.Name): $($_.Exception.Message)"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 4 - STARTUP
# ============================================================
function Menu-Startup {
    Draw-Header "STARTUP PROGRAMS - enable and disable without deleting"
    Write-Host "  Numbers toggle state. Disabled entries are kept in a backup registry subkey." -ForegroundColor DarkGray
    Write-Host ""

    $locations = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="HKCU"},
        @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="HKLM"},
        @{Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope="HKLM32"}
    )

    $entries = @()
    foreach ($location in $locations) {
        $disabledPath = "$($location.Path)\WinToolsDisabled"
        foreach ($source in @(
            @{Path=$location.Path; Enabled=$true},
            @{Path=$disabledPath; Enabled=$false}
        )) {
            $item = Get-ItemProperty -Path $source.Path -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            $item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                $valueType = "String"
                try { $valueType = (Get-Item $source.Path -ErrorAction Stop).GetValueKind($_.Name).ToString() } catch { $valueType = "String" }
                $entries += [pscustomobject]@{
                    Name=$_.Name; Value=$_.Value; Type=$valueType; Enabled=$source.Enabled
                    SourcePath=$source.Path
                    DestinationPath=$(if ($source.Enabled) { $disabledPath } else { $location.Path })
                    Scope=$location.Scope
                }
            }
        }
    }

    if ($entries.Count -eq 0) {
        Write-INFO "No active or backed-up startup entries were found"
        Pause-Menu; return
    }

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $status = if ($entry.Enabled) { "[ ON ]" } else { "[off ]" }
        $color = if ($entry.Enabled) { "Green" } else { "DarkGray" }
        $valueText = "$($entry.Value)"
        $short = if ($valueText.Length -gt 45) { $valueText.Substring(0,42) + "..." } else { $valueText }
        Write-Host ("  [{0,2}] {1} [{2,-6}] {3,-25} {4}" -f ($i+1), $status, $entry.Scope, $entry.Name, $short) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Numbers toggle entries: 1,3,5-8                               |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                         |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = (Read-Host).Trim()
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    try {
        $selected = @(ConvertTo-NumberList $choice $entries.Count | ForEach-Object { $entries[$_ - 1] })
    } catch {
        Write-FAIL "Could not parse the list: $($_.Exception.Message)"
        Pause-Menu; Menu-Startup; return
    }

    $preview = @($selected | ForEach-Object {
        $verb = if ($_.Enabled) { "DISABLE" } else { "ENABLE" }
        "[$verb] [$($_.Scope)] $($_.Name)"
    })
    if (-not (Confirm-ActionPreview $preview)) { Menu-Startup; return }

    foreach ($entry in $selected) {
        try {
            if (-not (Test-Path $entry.DestinationPath)) {
                New-Item -Path $entry.DestinationPath -Force -ErrorAction Stop | Out-Null
            }
            $destinationHasValue = $false
            try { $null = Get-ItemPropertyValue -Path $entry.DestinationPath -Name $entry.Name -ErrorAction Stop; $destinationHasValue = $true } catch { $destinationHasValue = $false }
            if ($destinationHasValue) { throw "the destination already contains an entry with this name" }
            New-ItemProperty -Path $entry.DestinationPath -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction Stop | Out-Null
            Remove-ItemProperty -Path $entry.SourcePath -Name $entry.Name -ErrorAction Stop
            $moved = Get-ItemPropertyValue -Path $entry.DestinationPath -Name $entry.Name -ErrorAction Stop
            if ("$moved" -ne "$($entry.Value)") { throw "move verification failed" }
            Write-ActionLog -type "StartupToggle" -target "$($entry.SourcePath)|$($entry.DestinationPath)|$($entry.Name)" -oldValue $(if ($entry.Enabled) { "Enabled" } else { "Disabled" }) -desc $entry.Name
            Write-OK "$(if ($entry.Enabled) { 'Disabled' } else { 'Enabled' }): $($entry.Name)"
        } catch {
            Write-FAIL "Could not toggle $($entry.Name): $($_.Exception.Message)"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 5 - DISK CLEANUP
# ============================================================
function Menu-DiskCleanup {
    Draw-Header "DISK CLEANUP - Free up space on C:"
    Write-Host "  Scanning folder sizes, please wait..." -ForegroundColor DarkGray
    Write-Host ""

    $items = @(
        @{Label="User Temp files";          Path="$env:USERPROFILE\AppData\Local\Temp"},
        @{Label="Windows Temp folder";      Path="C:\Windows\Temp"},
        @{Label="C:\Temp folder";           Path="C:\Temp"},
        @{Label="Prefetch cache";           Path="C:\Windows\Prefetch"},
        @{Label="Memory crash dump";        Path="C:\Windows\MEMORY.DMP"},
        @{Label="LiveKernel crash reports"; Path="C:\Windows\LiveKernelReports"},
        @{Label="Minidumps";                Path="C:\Windows\Minidump"},
        @{Label="WER error reports";        Path="C:\ProgramData\Microsoft\Windows\WER"},
        @{Label="Brave browser cache";      Path="$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"},
        @{Label="Chrome browser cache";     Path="$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache"},
        @{Label="Python pip cache";         Path="$env:USERPROFILE\AppData\Local\pip\cache"},
        @{Label="Windows thumbnail cache";  Path="$env:USERPROFILE\AppData\Local\Microsoft\Windows\Explorer"},
        @{Label="Windows Update downloads"; Path="C:\Windows\SoftwareDistribution\Download"}
    )

    if ($Script:IsWin11) {
        $items += @{Label="Clipchamp cache (Win11)"; Path="$env:USERPROFILE\AppData\Local\Packages\Clipchamp.Clipchamp_yfvym6g1cvhwe\LocalCache"}
        $items += @{Label="Widgets cache (Win11)";   Path="$env:USERPROFILE\AppData\Local\Packages\MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy\LocalCache"}
    }

    $totalWaste = 0
    $i = 1
    foreach ($item in $items) {
        if (Test-Path $item.Path) {
            $isFile = -not (Get-Item $item.Path -ErrorAction SilentlyContinue).PSIsContainer
            $size = if ($isFile) {
                [math]::Round((Get-Item $item.Path).Length / 1GB, 2)
            } else {
                $s = (Get-ChildItem $item.Path -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($s) { [math]::Round($s/1GB,2) } else { 0 }
            }
            $totalWaste += $size
            $sizeStr = if ($size -ge 1) { "$size GB  <<< BIG" } elseif ($size -gt 0.05) { "$size GB" } else { "< 0.05 GB" }
            $color = if ($size -ge 1) { "Red" } elseif ($size -gt 0.2) { "Yellow" } else { "DarkGray" }
            Write-Host ("  [{0,2}] {1,-35}  {2}" -f $i, $item.Label, $sizeStr) -ForegroundColor $color
        } else {
            Write-Host ("  [{0,2}] {1,-35}  not found" -f $i, $item.Label) -ForegroundColor DarkGray
        }
        $i++
    }

    $free = [math]::Round((Get-PSDrive C).Free/1GB,1)
    Write-Host ""
    Write-Host ("  Current free space : {0} GB" -f $free) -ForegroundColor Cyan
    Write-Host ("  Total junk found   : {0} GB" -f [math]::Round($totalWaste,2)) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Clean ALL items above                                   |" -ForegroundColor Cyan
    Write-Host "  | [1-$($items.Count)] Clean a specific item                                   |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Clean-Item($item) {
        if (-not (Test-Path $item.Path)) {
            Write-SKIP "Not found: $($item.Label)"
            return
        }

        $removeErrors = @()
        $target = Get-Item $item.Path -Force -ErrorAction SilentlyContinue
        if ($target -and -not $target.PSIsContainer) {
            Remove-Item $item.Path -Force -ErrorAction SilentlyContinue -ErrorVariable +removeErrors
        } else {
            Get-ChildItem $item.Path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +removeErrors
        }

        if ($removeErrors.Count -gt 0) {
            Write-INFO "Partially cleaned: $($item.Label). Some files are in use by the system: $($removeErrors.Count)"
        } else {
            Write-OK "Cleaned: $($item.Label)"
        }
    }

    $selectedItems = @()
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -eq "A" -or $choice -eq "a") {
        $selectedItems = $items
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $items.Count) {
        $selectedItems = @($items[[int]$choice - 1])
    } else {
        Write-FAIL "Invalid selection"
        Pause-Menu; return
    }

    $updateCache = "C:\Windows\SoftwareDistribution\Download"
    $explorerCache = "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Explorer"
    $needsWindowsUpdateStop = @($selectedItems | Where-Object { $_.Path -eq $updateCache }).Count -gt 0
    $needsExplorerStop = @($selectedItems | Where-Object { $_.Path -eq $explorerCache }).Count -gt 0
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuWasRunning = $wuService -and $wuService.Status -eq "Running"
    $explorerWasRunning = $null -ne (Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1)

    Write-Host ""
    try {
        if ($needsWindowsUpdateStop -and $wuWasRunning) {
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
        }
        if ($needsExplorerStop -and $explorerWasRunning) {
            Stop-Process -Name explorer -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 500
        }
        foreach ($item in $selectedItems) { Clean-Item $item }
    } catch {
        Write-FAIL $_.Exception.Message
    } finally {
        # The old implementation stopped Windows Update and never started it again.
        if ($needsWindowsUpdateStop -and $wuWasRunning) {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
        if ($needsExplorerStop -and $explorerWasRunning -and -not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer.exe
        }
    }

    $freeAfter = [math]::Round((Get-PSDrive C).Free/1GB,1)
    Write-Host ""
    Write-Host ("  Free space before : {0} GB" -f $free) -ForegroundColor DarkGray
    Write-Host ("  Free space now    : {0} GB  (+{1} GB freed)" -f $freeAfter, [math]::Round($freeAfter-$free,1)) -ForegroundColor Green
    Pause-Menu
}

# ============================================================
# MENU 6 - LIVE MONITOR
# ============================================================
function Menu-Monitor {
    $running = $true
    while ($running) {
        Clear-Host
        Write-Host ""
        Write-Host "  +================================================================+" -ForegroundColor Cyan
        Write-Host "  |                    LIVE SYSTEM MONITOR                         |" -ForegroundColor Cyan
        Write-Host "  |                Press Q to exit                         |" -ForegroundColor DarkGray
        Write-Host "  +================================================================+" -ForegroundColor Cyan
        Write-Host ""

        $os       = Get-WinToolsCimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu      = [math]::Round((Get-WinToolsCimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average,0)
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
        $ramFree  = [math]::Round($os.FreePhysicalMemory/1MB,1)
        $ramUsed  = [math]::Round($ramTotal - $ramFree,1)
        $ramPct   = [math]::Round($ramUsed/$ramTotal*100,0)
        $free     = [math]::Round((Get-PSDrive C).Free/1GB,1)
        $usedD    = [math]::Round((Get-PSDrive C).Used/1GB,1)
        $total    = $free + $usedD
        $diskPct  = [math]::Round($usedD/$total*100,0)
        $proc     = (Get-Process -ErrorAction SilentlyContinue).Count

        function Draw-Bar($pct, $width) {
            $fill  = [math]::Round($pct * $width / 100)
            $empty = $width - $fill
            $color = if ($pct -gt 85) { "Red" } elseif ($pct -gt 60) { "Yellow" } else { "Green" }
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host ("#" * $fill) -NoNewline -ForegroundColor $color
            Write-Host ("-" * $empty) -NoNewline -ForegroundColor DarkGray
            Write-Host "] $pct%" -ForegroundColor $color
        }

        Write-Host "  CPU Usage:" -ForegroundColor White
        Draw-Bar $cpu 50
        Write-Host ""
        Write-Host ("  RAM: {0} GB used / {1} GB total" -f $ramUsed, $ramTotal) -ForegroundColor White
        Draw-Bar $ramPct 50
        Write-Host ""
        Write-Host ("  Disk C: {0} GB used / {1} GB total  ({2} GB free)" -f $usedD, $total, $free) -ForegroundColor White
        Draw-Bar $diskPct 50
        Write-Host ""
        Write-Host ("  Running processes: {0}" -f $proc) -ForegroundColor White
        Write-Host "  Version: $Script:WinVerName" -ForegroundColor DarkCyan
        Write-Host ""

        Write-Host "  --- TOP 10 PROCESSES BY RAM ---" -ForegroundColor Cyan
        Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet -Descending | Select-Object -First 10 | ForEach-Object {
            $mb    = [math]::Round($_.WorkingSet/1MB,1)
            $bar   = "#" * [math]::Min([math]::Round($mb/50),30)
            $color = if ($mb -gt 300) { "Red" } elseif ($mb -gt 100) { "Yellow" } else { "White" }
            Write-Host ("  {0,-30} {1,6} MB  {2}" -f $_.Name, $mb, $bar) -ForegroundColor $color
        }
        Write-Host ""

        Write-Host "  --- KEY SETTINGS STATUS ---" -ForegroundColor Cyan
        $hags = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue).HwSchMode
        $pt   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -ErrorAction SilentlyContinue).PowerThrottlingOff
        $tele = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ErrorAction SilentlyContinue).AllowTelemetry
        $fs   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ErrorAction SilentlyContinue).HiberbootEnabled

        function Show-Bool($label, $val, $goodVal) {
            $ok    = $val -eq $goodVal
            $icon  = if ($ok) { "[OK]" } else { "[!!]" }
            $color = if ($ok) { "Green" } else { "Red" }
            Write-Host ("  {0} {1}" -f $icon, $label) -ForegroundColor $color
        }
        Show-Bool "GPU Hardware Scheduling ON  (need 2, got $hags)" $hags 2
        Show-Bool "Power Throttling OFF        (need 1, got $pt)"   $pt   1
        Show-Bool "Telemetry OFF               (need 0, got $tele)" $tele 0
        Show-Bool "Fast Startup OFF            (need 0, got $fs)"   $fs   0

        Write-Host ""
        Write-Host ("  Updated: {0}  |  Refreshing in 3s...  |  Press Q then Enter to exit" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor DarkGray

        $startTime = Get-Date
        while ((Get-Date) -lt $startTime.AddSeconds(3)) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq "q" -or $key.KeyChar -eq "Q") { $running = $false; break }
            }
            Start-Sleep -Milliseconds 200
        }
    }
}

# ============================================================
# MENU 7 - POWER PLAN
# ============================================================
function Menu-PowerPlan {
    Draw-Header "POWER PLAN - Ultimate Performance mode"
    Write-Host "  Active plan:" -ForegroundColor DarkGray
    $current = & powercfg /getactivescheme 2>&1
    Write-Host "  $current" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  All available plans:" -ForegroundColor DarkGray
    & powercfg /list 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [1] Activate Ultimate Performance                              |" -ForegroundColor Green
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "1") {
        Write-Host ""
        $guidPattern = '(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b'
        $schemeLine = & powercfg /list 2>&1 | Where-Object { "$_" -match '(?i)Ultimate Performance|Максимальн.*производитель' } | Select-Object -First 1
        $guid = $null
        if ("$schemeLine" -match $guidPattern) { $guid = $matches[0] }

        if (-not $guid) {
            $duplicateOutput = & powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-FAIL "Could not create the plan: $($duplicateOutput -join ' ')"
                Pause-Menu; return
            }
            if (($duplicateOutput -join ' ') -match $guidPattern) { $guid = $matches[0] }
            if ($guid) { Write-OK "Ultimate Performance plan created" }
        }

        if (-not $guid) {
            Write-FAIL "Windows did not return the GUID of the created power plan"
            Pause-Menu; return
        }

        $activateOutput = & powercfg /setactive $guid 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-FAIL "Could not activate the plan: $($activateOutput -join ' ')"
        } else {
            $active = & powercfg /getactivescheme 2>&1
            if (($active -join ' ') -match [regex]::Escape($guid)) {
                Write-OK "Ultimate Performance plan activated"
            } else {
                Write-FAIL "The command completed, but the active plan did not change"
            }
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 8 - SMB1
# ============================================================
function Menu-SMB {
    Draw-Header "SMB1 SECURITY - Disable the vulnerable protocol"
    Write-Host "  SMB1 is an old protocol with serious vulnerabilities." -ForegroundColor DarkGray
    Write-Host "  WannaCry used it. Some very old NAS devices may still require it." -ForegroundColor DarkGray
    Write-Host ""

    try {
        $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    } catch {
        Write-FAIL "Could not read SMB1 state: $($_.Exception.Message)"
        Pause-Menu; return
    }
    $status = $smb.State
    $safe = $status -eq "Disabled" -or $status -eq "DisablePending"
    $color = if ($safe) { "Green" } else { "Red" }
    Write-Host ("  SMB1 status: [ {0} ]" -f $status) -ForegroundColor $color
    Write-Host ""

    if (-not $safe) {
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | SMB1 IS ENABLED - this is a security risk!                     |" -ForegroundColor Red
        Write-Host "  | [1] Disable SMB1 NOW                                           |" -ForegroundColor Green
        Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Choose: " -ForegroundColor White -NoNewline
        $choice = Read-Host
        if ($choice -eq "1") {
            Write-Host ""
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction Stop | Out-Null
                try {
                    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop | Out-Null
                } catch {
                    Write-INFO "The feature was disabled, but the server setting could not be checked: $($_.Exception.Message)"
                }
                $after = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
                if ($after.State -eq "Disabled" -or $after.State -eq "DisablePending") {
                    Write-OK "SMB1 disabled. A reboot is required when the state is DisablePending."
                } else {
                    Write-FAIL "SMB1 remained in state $($after.State)"
                }
            } catch {
                Write-FAIL "Could not disable SMB1: $($_.Exception.Message)"
            }
        }
    } else {
        Write-OK "SMB1 is already disabled."
        if ($status -eq "DisablePending") { Write-INFO "Restart Windows to finish." }
    }
    Pause-Menu
}

# ============================================================
# MENU 9 - SYSTEM HEALTH
# ============================================================
function Menu-Health {
    Draw-Header "SYSTEM HEALTH - SSD, temperature, drivers, fonts"
    Write-Host "  Uses only built-in Windows tools." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  --- DISK HEALTH (SSD/HDD) ---" -ForegroundColor Cyan
    Get-PhysicalDisk | ForEach-Object {
        $disk = $_
        Write-Host ("  Disk: {0}" -f $disk.FriendlyName) -ForegroundColor White
        $hColor = if ($disk.HealthStatus -eq "Healthy") { "Green" } else { "Red" }
        Write-Host ("    Type            : {0}" -f $disk.MediaType)
        Write-Host ("    Health Status   : {0}" -f $disk.HealthStatus) -ForegroundColor $hColor
        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
            if ($rel.Temperature) {
                $tColor = if ($rel.Temperature -gt 60) { "Red" } elseif ($rel.Temperature -gt 45) { "Yellow" } else { "Green" }
                Write-Host ("    Temperature     : {0} C" -f $rel.Temperature) -ForegroundColor $tColor
            }
            if ($null -ne $rel.Wear) {
                $wColor = if ($rel.Wear -gt 80) { "Red" } elseif ($rel.Wear -gt 50) { "Yellow" } else { "Green" }
                Write-Host ("    Wear (life used): {0}%" -f $rel.Wear) -ForegroundColor $wColor
            }
            if ($null -ne $rel.PowerOnHours) {
                Write-Host ("    Power On Hours  : {0} hrs (~{1} days)" -f $rel.PowerOnHours, [math]::Round($rel.PowerOnHours/24,0))
            }
        } catch {
            Write-INFO "Detailed counters not available for this disk"
        }
        Write-Host ""
    }

    Write-Host "  --- TEMPERATURE ---" -ForegroundColor Cyan
    $tempFound = $false
    try {
        $temps = Get-WinToolsCimInstance -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($t in $temps) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            $color = if ($celsius -gt 85) { "Red" } elseif ($celsius -gt 70) { "Yellow" } else { "Green" }
            Write-Host ("  Thermal Zone: {0} C" -f $celsius) -ForegroundColor $color
            $tempFound = $true
        }
    } catch {
        $tempFound = $false
    }
    if (-not $tempFound) {
        Write-INFO "Built-in sensors did not report temps (common on laptops)"
    }
    $cpuLoad = (Get-WinToolsCimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-Host ("  Current CPU load: {0}%" -f $cpuLoad) -ForegroundColor White
    Write-Host ""

    Write-Host "  --- DRIVER UPDATE CHECK ---" -ForegroundColor Cyan
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    try {
        if (-not $wu) { throw "Windows Update service was not found" }
        if ($wu.StartType -eq "Disabled") {
            Set-Service -Name wuauserv -StartupType Manual -ErrorAction Stop
            Write-ActionLog -type "Service" -target "wuauserv" -oldValue "Disabled|Stopped" -desc "Windows Update for driver scan"
            Write-INFO "Windows Update service enabled for the scan"
        }
        Start-Service -Name wuauserv -ErrorAction Stop
        & UsoClient StartScan 2>$null
        if ($LASTEXITCODE -ne 0) { throw "UsoClient exited with code $LASTEXITCODE" }
        Write-OK "Driver scan triggered via Windows Update"
        Write-Host "  Check: Settings -> Windows Update -> Advanced options -> Optional updates" -ForegroundColor White
    } catch {
        Write-FAIL "Could not start the scan: $($_.Exception.Message)"
        Write-INFO "Check manually in Settings -> Windows Update"
    }
    Write-Host ""

    Write-Host "  --- FONT CHECK ---" -ForegroundColor Cyan
    $winInstallDate = (Get-WinToolsCimInstance Win32_OperatingSystem).InstallDate
    if ($winInstallDate -isnot [datetime]) {
        $winInstallDate = [Management.ManagementDateTimeConverter]::ToDateTime($winInstallDate)
    }
    $fontPath = "C:\Windows\Fonts"
    $allFonts = Get-ChildItem $fontPath -File -ErrorAction SilentlyContinue
    $suspects = $allFonts | Where-Object { $_.CreationTime -gt $winInstallDate.AddDays(2) }
    Write-Host ("  Total fonts: {0}   Added after Windows install: {1}" -f $allFonts.Count, $suspects.Count) -ForegroundColor White

    if ($suspects.Count -gt 0) {
        Write-Host ""
        $suspects | Sort-Object CreationTime | Select-Object -First 20 | ForEach-Object {
            $sizeKb = [math]::Round($_.Length/1KB,0)
            Write-Host ("  {0,-40} {1,-20} {2} KB" -f $_.Name, $_.CreationTime.ToString("yyyy-MM-dd"), $sizeKb)
        }
        $totalSize = [math]::Round(($suspects | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        Write-Host ("`n  Total size: {0} MB" -f $totalSize) -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Type YES to remove these fonts, or press Enter to skip: " -ForegroundColor White -NoNewline
        $confirm = Read-Host
        if ($confirm -eq "YES") {
            $removed = 0
            foreach ($font in $suspects) {
                try {
                    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                    $regEntries = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                    $propName = $regEntries.PSObject.Properties | Where-Object { $_.Value -like "*$($font.Name)*" } | Select-Object -First 1
                    if ($propName) { Remove-ItemProperty -Path $regPath -Name $propName.Name -ErrorAction SilentlyContinue }
                    Remove-Item $font.FullName -Force -ErrorAction Stop
                    $removed++
                } catch { Write-INFO "Could not remove: $($font.Name)" }
            }
            Write-OK "Removed $removed fonts, freed ~$totalSize MB"
        } else {
            Write-SKIP "Skipped by user"
        }
    } else {
        Write-OK "No extra fonts found"
    }
    Pause-Menu
}

# ============================================================
# MENU 10 - DRIVER UPDATE
# ============================================================
function Menu-DriverUpdate {
    Draw-Header "DRIVER UPDATE - Detect hardware and find latest versions"
    Write-Host "  Detecting your hardware..." -ForegroundColor DarkGray
    Write-Host ""

    $cpu = Get-WinToolsCimInstance Win32_Processor | Select-Object -First 1
    Write-Host ("  CPU       : {0}" -f $cpu.Name) -ForegroundColor White

    $gpus = Get-WinToolsCimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Basic|Remote" }
    foreach ($g in $gpus) {
        Write-Host ("  GPU       : {0}" -f $g.Name) -ForegroundColor White
    }

    $wifi = Get-WinToolsCimInstance Win32_NetworkAdapter | Where-Object { $_.Name -match "Wireless|Wi-Fi|WiFi" -and $_.Manufacturer -notmatch "Microsoft" } | Select-Object -First 1
    if ($wifi) { Write-Host ("  Wi-Fi     : {0}" -f $wifi.Name) -ForegroundColor White }

    $audio = Get-WinToolsCimInstance Win32_SoundDevice | Select-Object -First 1
    if ($audio) { Write-Host ("  Audio     : {0}" -f $audio.Name) -ForegroundColor White }

    $sys = Get-WinToolsCimInstance Win32_ComputerSystem
    Write-Host ("  Laptop    : {0} {1}" -f $sys.Manufacturer, $sys.Model) -ForegroundColor White
    Write-Host ("  OS        : {0}" -f $Script:WinVerName) -ForegroundColor DarkCyan
    Write-Host ""

    $links = @()
    function Build-SearchUrl($query) { return "https://www.google.com/search?q=" + [uri]::EscapeDataString($query) }

    if ($cpu.Name -match "Intel") {
        $links += @{Label="Intel Driver and Support Assistant (CPU, chipset, Wi-Fi, BT)"; Url="https://www.intel.com/content/www/us/en/support/detect.html"}
    } elseif ($cpu.Name -match "AMD") {
        $cpuClean = ($cpu.Name -replace "AMD","" -replace "Processor","" -replace "with Radeon.*","" -replace "\s+"," ").Trim()
        $links += @{Label="AMD - latest chipset driver for $cpuClean"; Url=(Build-SearchUrl "AMD chipset driver $cpuClean latest download")}
    }

    foreach ($g in $gpus) {
        if ($g.Name -match "NVIDIA") {
            $gpuClean = ($g.Name -replace "NVIDIA","" -replace "Laptop GPU","" -replace "\s+"," ").Trim()
            $links += @{Label="NVIDIA - latest driver for: $gpuClean"; Url=(Build-SearchUrl "nvidia driver $gpuClean laptop latest download")}
        } elseif ($g.Name -match "Intel") {
            $links += @{Label="Intel Graphics - latest drivers"; Url="https://www.intel.com/content/www/us/en/download-center/home.html"}
        } elseif ($g.Name -match "AMD|Radeon") {
            $gpuClean = ($g.Name -replace "AMD","" -replace "Radeon","" -replace "Graphics","" -replace "\s+"," ").Trim()
            $links += @{Label="AMD - latest driver for: Radeon $gpuClean"; Url=(Build-SearchUrl "amd radeon driver $gpuClean laptop latest download")}
        }
    }

    if ($sys.Manufacturer -match "HUAWEI") {
        $links += @{Label="HUAWEI - drivers for your model"; Url="https://consumer.huawei.com/en/support/laptops/"}
    } elseif ($sys.Manufacturer -match "ASUS") {
        $links += @{Label="ASUS - drivers for your model"; Url="https://www.asus.com/support/"}
    } elseif ($sys.Manufacturer -match "Lenovo") {
        $links += @{Label="Lenovo - drivers for your model"; Url="https://support.lenovo.com/"}
    } elseif ($sys.Manufacturer -match "HP") {
        $links += @{Label="HP - drivers for your model"; Url="https://support.hp.com/"}
    } elseif ($sys.Manufacturer -match "Dell") {
        $links += @{Label="Dell - drivers for your model"; Url="https://www.dell.com/support/home/"}
    } elseif ($sys.Manufacturer -match "MSI") {
        $links += @{Label="MSI - drivers for your model"; Url="https://www.msi.com/support/"}
    } elseif ($sys.Manufacturer -match "Acer") {
        $links += @{Label="Acer - drivers for your model"; Url="https://www.acer.com/support"}
    }

    if ($links.Count -eq 0) {
        Write-INFO "Could not determine manufacturer for specific links"
    } else {
        Write-Host "  Found the following resources:" -ForegroundColor Cyan
        Write-Host ""
        $i = 1
        foreach ($l in $links) {
            Write-Host ("  [{0}] {1}" -f $i, $l.Label) -ForegroundColor Green
            $i++
        }
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Open ALL links in the browser at once                   |" -ForegroundColor Cyan
    Write-Host "  | [1-N]  Open a specific link                                    |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "A" -or $choice -eq "a") {
        foreach ($l in $links) { Start-Process $l.Url; Write-OK "Opened: $($l.Label)" }
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $links.Count) {
        $l = $links[[int]$choice - 1]; Start-Process $l.Url; Write-OK "Opened: $($l.Label)"
    }
    Pause-Menu
}

# ============================================================
# MENU 11 - RESTORE POINT
# ============================================================
function Menu-RestorePoint {
    Draw-Header "RESTORE POINT - Create system snapshot"
    Write-Host "  If something breaks after tweaks, you can roll back." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NOTE: Windows allows only 1 restore point per 24 hours by default." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [1] Create restore point NOW                                  |" -ForegroundColor Green
    Write-Host "  | [2] Remove 24h limit (allow creating more often)              |" -ForegroundColor White
    Write-Host "  | [3] Open System Restore window (roll back)                    |" -ForegroundColor White
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "1") {
        Write-Host ""
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "WinTools - before changes $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Write-OK "Restore point created"
        } catch {
            Write-INFO "Could not create: 24h limit may have triggered. Use option [2] to remove limit."
        }
    } elseif ($choice -eq "2") {
        Write-Host ""
        try {
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-OK "Limit removed"
        } catch {
            Write-FAIL "Could not change the limit: $($_.Exception.Message)"
        }
    } elseif ($choice -eq "3") {
        Write-Host ""
        Start-Process rstrui.exe
        Write-OK "System Restore window opened"
    }
    Pause-Menu
}

# ============================================================
# MENU 12 - CHANGE LOG & UNDO
# ============================================================
function Menu-ChangeLog {
    Draw-Header "CHANGE LOG - What was changed and undo"

    if (-not (Test-Path $Global:LogPath)) {
        Write-INFO "Log is empty - no changes made yet"
        Pause-Menu; return
    }

    $entries = Import-Csv -Path $Global:LogPath -ErrorAction SilentlyContinue
    if (-not $entries -or $entries.Count -eq 0) {
        Write-INFO "Log is empty - no changes made yet"
        Pause-Menu; return
    }

    Write-Host "  All changes (most recent first):" -ForegroundColor DarkGray
    Write-Host ""

    $reversed = $entries | Sort-Object { [datetime]$_.Timestamp } -Descending
    $i = 1
    $indexMap = @{}
    foreach ($e in $reversed) {
        $typeColor = switch ($e.Type) {
            "Service"  { "Cyan" }
            "Task"     { "Magenta" }
            "Registry" { "Yellow" }
            "Startup"  { "White" }
            default    { "DarkGray" }
        }
        Write-Host ("  [{0,3}] {1,-11} {2,-10} {3}" -f $i, $e.Timestamp, $e.Type, $e.Desc) -ForegroundColor $typeColor
        $indexMap[$i] = $e
        $i++
        if ($i -gt 50) { break }
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Enter numbers comma-separated to UNDO                          |" -ForegroundColor Cyan
    Write-Host "  | [C] Clear log                                                  |" -ForegroundColor Yellow
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -eq "C" -or $choice -eq "c") {
        try {
            Remove-Item $Global:LogPath -Force -ErrorAction Stop
            "Timestamp,Type,Target,OldValue,Desc" | Out-File -FilePath $Global:LogPath -Encoding UTF8 -ErrorAction Stop
            Write-OK "Log cleared"
        } catch {
            Write-FAIL "Could not clear the log: $($_.Exception.Message)"
        }
        Pause-Menu; return
    }

    $parts = $choice -split ","
    $toUndo = @()
    foreach ($p in $parts) {
        $p = $p.Trim()
        if ($p -match "^\d+$") {
            $n = [int]$p
            if ($indexMap.ContainsKey($n)) { $toUndo += $indexMap[$n] }
        }
    }

    Write-Host ""
    foreach ($e in $toUndo) {
        switch ($e.Type) {
            "Service" {
                try {
                    if ($e.OldValue -eq "NULL") { Write-SKIP "Skip: unknown state for $($e.Target)" }
                    else {
                        $oldParts = $e.OldValue -split "\|", 2
                        $oldStartType = $oldParts[0]
                        $oldStatus = if ($oldParts.Count -gt 1) { $oldParts[1] } else { "Running" }
                        Set-Service -Name $e.Target -StartupType $oldStartType -ErrorAction Stop
                        if ($oldStatus -eq "Running") {
                            Start-Service -Name $e.Target -ErrorAction Stop
                        } else {
                            Stop-Service -Name $e.Target -Force -ErrorAction Stop
                        }
                        $restored = Get-Service -Name $e.Target -ErrorAction Stop
                        if ("$($restored.StartType)" -ne "$oldStartType") { throw "startup type was not restored" }
                        Write-OK "Service $($e.Target) restored: $oldStartType / $oldStatus"
                    }
                } catch { Write-FAIL "Could not undo service $($e.Target): $($_.Exception.Message)" }
            }
            "Task" {
                try {
                    $parts2 = $e.Target -split "\|", 2
                    $taskPath = $parts2[0]; $taskName = $parts2[1]
                    if ($e.OldValue -eq "Disabled") {
                        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                    } else {
                        Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                    }
                    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                    if ($e.OldValue -eq "Disabled" -and $task.State -ne "Disabled") { throw "the task was not disabled again" }
                    if ($e.OldValue -ne "Disabled" -and $task.State -eq "Disabled") { throw "the task was not enabled again" }
                    Write-OK "Task state restored: $taskName → $($e.OldValue)"
                } catch { Write-FAIL "Could not undo task $($e.Target): $($_.Exception.Message)" }
            }
            "Registry" {
                try {
                    $parts2 = $e.Target -split "\|", 2
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") {
                        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
                        $stillExists = $true
                        try { $null = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction Stop } catch { $stillExists = $false }
                        if ($stillExists) { throw "the value still exists" }
                        Write-OK "Registry value removed: $regName"
                    } else {
                        Set-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -ErrorAction Stop
                        $actual = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction Stop
                        if ("$actual" -ne "$($e.OldValue)") { throw "the previous value was not restored" }
                        Write-OK "Registry $regName restored: $($e.OldValue)"
                    }
                } catch { Write-FAIL "Could not undo registry $($e.Target): $($_.Exception.Message)" }
            }
            "StartupToggle" {
                try {
                    $parts2 = $e.Target -split "\|", 3
                    $originalPath = $parts2[0]; $currentPath = $parts2[1]; $regName = $parts2[2]
                    $value = Get-ItemPropertyValue -Path $currentPath -Name $regName -ErrorAction Stop
                    $valueType = (Get-Item $currentPath -ErrorAction Stop).GetValueKind($regName).ToString()
                    if (-not (Test-Path $originalPath)) { New-Item -Path $originalPath -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -Path $originalPath -Name $regName -Value $value -PropertyType $valueType -Force -ErrorAction Stop | Out-Null
                    Remove-ItemProperty -Path $currentPath -Name $regName -ErrorAction Stop
                    Write-OK "Startup state restored: $regName"
                } catch { Write-FAIL "Could not undo startup toggle $($e.Target): $($_.Exception.Message)" }
            }
            "Startup" {
                try {
                    $parts2 = $e.Target -split "\|", 2
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") { throw "the log has no previous value" }
                    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -PropertyType String -Force -ErrorAction Stop | Out-Null
                    Write-OK "Startup entry restored: $regName"
                } catch { Write-FAIL "Could not restore startup entry $($e.Target): $($_.Exception.Message)" }
            }
            default { Write-INFO "Cannot undo automatically: $($e.Type) - $($e.Desc)" }
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 13 - BLOATWARE
# ============================================================
function Menu-Bloatware {
    Draw-Header "BLOATWARE - Remove built-in Windows apps"

    if ($Script:IsLTSC) {
        Write-INFO "Windows 11 Enterprise LTSC: almost no bloatware."
        Write-Host "  This Windows version is already clean." -ForegroundColor DarkGray
        Pause-Menu; return
    }

    Write-Host "  These apps come pre-installed with Windows." -ForegroundColor DarkGray
    Write-Host ""

    $apps = @(
        @{N="Microsoft.XboxApp";                    L="Xbox App"},
        @{N="Microsoft.XboxGameOverlay";             L="Xbox Game Bar Overlay"},
        @{N="Microsoft.XboxGamingOverlay";           L="Xbox Gaming Overlay"},
        @{N="Microsoft.XboxIdentityProvider";        L="Xbox Identity Provider"},
        @{N="Microsoft.XboxSpeechToTextOverlay";     L="Xbox Speech to Text"},
        @{N="Microsoft.Xbox.TCUI";                   L="Xbox TCUI"},
        @{N="Microsoft.MicrosoftSolitaireCollection";L="Microsoft Solitaire"},
        @{N="Microsoft.BingWeather";                 L="Weather"},
        @{N="Microsoft.BingNews";                    L="News"},
        @{N="Microsoft.WindowsMaps";                 L="Maps"},
        @{N="Microsoft.YourPhone";                   L="Your Phone"},
        @{N="Microsoft.GetHelp";                     L="Get Help"},
        @{N="Microsoft.Getstarted";                  L="Get Started"},
        @{N="Microsoft.WindowsFeedbackHub";          L="Feedback Hub"},
        @{N="Microsoft.3DBuilder";                    L="3D Builder"},
        @{N="Microsoft.Microsoft3DViewer";            L="3D Viewer"},
        @{N="Microsoft.MixedReality.Portal";          L="Mixed Reality Portal"},
        @{N="Microsoft.MicrosoftOfficeHub";           L="Office Hub (subscription ads)"},
        @{N="Microsoft.SkypeApp";                     L="Skype (built-in)"},
        @{N="Microsoft.People";                       L="People"},
        @{N="Microsoft.WindowsCommunicationsApps";    L="Mail and Calendar"},
        @{N="MicrosoftTeams";                         L="Teams (built-in)"},
        @{N="Microsoft.Todos";                        L="Microsoft To Do"},
        @{N="Microsoft.PowerAutomateDesktop";         L="Power Automate"},
        @{N="Microsoft.MicrosoftStickyNotes";         L="Sticky Notes"},
        @{N="Clipchamp.Clipchamp";                     L="Clipchamp Video Editor"},
        @{N="MicrosoftCorporationII.MicrosoftFamily"; L="Microsoft Family Safety"},
        @{N="Microsoft.WindowsAlarms";                L="Alarms and Clock"},
        @{N="Microsoft.ZuneMusic";                     L="Groove Music"},
        @{N="Microsoft.ZuneVideo";                     L="Movies and TV"}
    )

    if ($Script:IsWin10) {
        $apps += @{N="Microsoft.549981C3F5F10"; L="Cortana (Win10 only)"}
    }

    $i = 1
    $indexMap = @{}
    foreach ($a in $apps) {
        $installed = Get-AppxPackage -Name $a.N -AllUsers -ErrorAction SilentlyContinue
        $status = if ($installed) { "[installed]" } else { "[not found]" }
        $color = if ($installed) { "Green" } else { "DarkGray" }
        Write-Host ("  {0,3}) {1} {2}" -f $i, $status, $a.L) -ForegroundColor $color
        $indexMap[$i] = $a.N
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Enter numbers comma-separated to REMOVE. Example: 1,2,5-8     |" -ForegroundColor Cyan
    Write-Host "  | [A] Remove all from list                                      |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                         |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    $toRemove = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $toRemove = $apps | ForEach-Object { $_.N }
    } else {
        $parts = $choice -split ","
        foreach ($p in $parts) {
            $p = $p.Trim()
            if ($p -match "^(\d+)-(\d+)$") {
                $from = [int]$matches[1]; $to = [int]$matches[2]
                for ($n = $from; $n -le $to; $n++) { if ($indexMap.ContainsKey($n)) { $toRemove += $indexMap[$n] } }
            } elseif ($p -match "^\d+$") {
                $n = [int]$p
                if ($indexMap.ContainsKey($n)) { $toRemove += $indexMap[$n] }
            }
        }
    }

    Write-Host ""
    foreach ($appName in $toRemove) {
        $packages = @(Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue)
        if ($packages.Count -gt 0) {
            $removeErrors = @()
            foreach ($package in $packages) {
                try {
                    Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                } catch {
                    $removeErrors += $_
                }
            }
            $remaining = @(Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) {
                Write-ActionLog -type "AppxPackage" -target $appName -oldValue "installed" -desc $appName
                Write-OK "Removed: $appName"
            } else {
                $detail = if ($removeErrors.Count) { $removeErrors[0].Exception.Message } else { "package is still installed" }
                Write-FAIL "Could not remove ${appName}: $detail"
            }
        } else {
            Write-SKIP "Not installed: $appName"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 14 - BROWSER CACHE
# ============================================================
function Menu-BrowserCache {
    Draw-Header "BROWSER CACHE CLEANUP - Brave, Chrome, Edge"
    Write-Host "  Closes selected browsers and clears cache for every profile." -ForegroundColor DarkGray
    Write-Host "  Passwords, history and bookmarks are not touched." -ForegroundColor DarkGray
    Write-Host ""

    $browsers = @(
        @{Name="Brave";  Process="brave";  Root="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"},
        @{Name="Chrome"; Process="chrome"; Root="$env:LOCALAPPDATA\Google\Chrome\User Data"},
        @{Name="Edge";   Process="msedge"; Root="$env:LOCALAPPDATA\Microsoft\Edge\User Data"}
    )

    function Get-BrowserCachePaths($browser) {
        if (-not (Test-Path $browser.Root)) { return @() }
        $profiles = Get-ChildItem $browser.Root -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq "Default" -or $_.Name -like "Profile *" -or $_.Name -eq "Guest Profile"
        }
        $result = @()
        foreach ($browserProfile in $profiles) {
            foreach ($relative in @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage")) {
                $candidate = Join-Path $browserProfile.FullName $relative
                if (Test-Path $candidate) { $result += $candidate }
            }
        }
        return $result | Select-Object -Unique
    }

    $i = 1
    foreach ($b in $browsers) {
        $paths = @(Get-BrowserCachePaths $b)
        $bytes = ($paths | ForEach-Object {
            (Get-ChildItem $_ -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        } | Measure-Object -Sum).Sum
        $size = if ($bytes) { [math]::Round($bytes / 1GB, 2) } else { 0 }
        $sizeStr = if ($paths.Count -eq 0) { "not found" } elseif ($size -gt 0) { "$size GB" } else { "< 0.01 GB" }
        Write-Host ("  [{0}] {1,-10} {2}" -f $i, $b.Name, $sizeStr) -ForegroundColor White
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]   Clear cache for ALL browsers                            |" -ForegroundColor Cyan
    Write-Host "  | [1-3] Clear a specific browser                                |" -ForegroundColor White
    Write-Host "  | [0]   Back to main menu                                        |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    $selected = @()
    if ($choice -eq "A" -or $choice -eq "a") { $selected = $browsers }
    elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $browsers.Count) { $selected = @($browsers[[int]$choice - 1]) }
    else { Write-FAIL "Invalid selection"; Pause-Menu; return }

    Write-Host ""
    foreach ($b in $selected) {
        Stop-Process -Name $b.Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $paths = @(Get-BrowserCachePaths $b)
        if ($paths.Count -eq 0) {
            Write-SKIP "$($b.Name): cache not found"
            continue
        }

        $removeErrors = @()
        foreach ($path in $paths) {
            Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +removeErrors
        }
        if ($removeErrors.Count -gt 0) {
            Write-INFO "$($b.Name) cache was partially cleared; locked files: $($removeErrors.Count)"
        } else {
            Write-OK "Cache cleared for every $($b.Name) profile"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 15 - COSMETICS
# ============================================================
function Menu-Cosmetics {
    Draw-Header "WINDOWS COSMETICS"

    $classicMenuRoot = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $classicMenuPath = "$classicMenuRoot\InprocServer32"
    $classicEnabled = Test-Path $classicMenuPath

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $hideExt = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).HideFileExt
    $hideHidden = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).Hidden

    if ($Script:IsWin11) {
        Write-Host ("  [1] Classic context menu (right-click)     status: {0}" -f $(if($classicEnabled){"ON"}else{"OFF (Win11 default)"})) -ForegroundColor $(if($classicEnabled){"Green"}else{"White"})
    } else {
        Write-Host "  [1] Classic context menu - Windows 11 only" -ForegroundColor DarkGray
    }
    Write-Host ("  [2] Show file extensions (.txt, .exe)      status: {0}" -f $(if($hideExt -eq 0){"ON"}else{"OFF"})) -ForegroundColor $(if($hideExt -eq 0){"Green"}else{"White"})
    Write-Host ("  [3] Show hidden files and folders          status: {0}" -f $(if($hideHidden -eq 1){"ON"}else{"OFF"})) -ForegroundColor $(if($hideHidden -eq 1){"Green"}else{"White"})
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    if ($Script:IsWin11) { Write-Host "  | [1] Toggle classic context menu                                |" -ForegroundColor White }
    Write-Host "  | [2] Toggle file extensions                                     |" -ForegroundColor White
    Write-Host "  | [3] Toggle hidden files                                        |" -ForegroundColor White
    Write-Host "  | [A] Enable ALL available                                       |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Restart-ExplorerShell {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer.exe -ErrorAction Stop
    }

    function Toggle-ClassicMenu {
        if (-not $Script:IsWin11) { Write-SKIP "Only available on Windows 11"; return }
        try {
            if ($classicEnabled) {
                Remove-Item -Path $classicMenuRoot -Recurse -Force -ErrorAction Stop
                if (Test-Path $classicMenuRoot) { throw "the registry key was not removed" }
                Write-OK "Classic menu disabled"
            } else {
                Set-RegLogged $classicMenuPath "(default)" "" "String" "Classic Context Menu"
                if (-not (Test-Path $classicMenuPath)) { throw "the registry key was not created" }
                Write-OK "Classic context menu enabled"
            }
            Restart-ExplorerShell
        } catch {
            Write-FAIL "Could not toggle the context menu: $($_.Exception.Message)"
        }
    }

    function Toggle-FileExt {
        $new = if ($hideExt -eq 0) { 1 } else { 0 }
        try {
            Set-RegLogged $advPath "HideFileExt" $new "DWord" "File extensions"
            Restart-ExplorerShell
            if ($new -eq 0) { Write-OK "File extensions are visible" } else { Write-OK "File extensions are hidden" }
        } catch {
            Write-FAIL "Could not change file-extension visibility: $($_.Exception.Message)"
        }
    }

    function Toggle-HiddenFiles {
        $new = if ($hideHidden -eq 1) { 2 } else { 1 }
        try {
            Set-RegLogged $advPath "Hidden" $new "DWord" "Hidden files"
            Restart-ExplorerShell
            if ($new -eq 1) { Write-OK "Hidden files are visible" } else { Write-OK "Hidden files are hidden" }
        } catch {
            Write-FAIL "Could not change hidden-file visibility: $($_.Exception.Message)"
        }
    }

    Write-Host ""
    switch ($choice) {
        "0" { return }
        "1" { Toggle-ClassicMenu }
        "2" { Toggle-FileExt }
        "3" { Toggle-HiddenFiles }
        "A" { if ($Script:IsWin11 -and -not $classicEnabled) { Toggle-ClassicMenu }; if ($hideExt -ne 0) { Toggle-FileExt }; if ($hideHidden -ne 1) { Toggle-HiddenFiles } }
        "a" { if ($Script:IsWin11 -and -not $classicEnabled) { Toggle-ClassicMenu }; if ($hideExt -ne 0) { Toggle-FileExt }; if ($hideHidden -ne 1) { Toggle-HiddenFiles } }
        default { Write-FAIL "Invalid selection" }
    }
    Pause-Menu
}

# ============================================================
# SNAPSHOTS / EXPORT / IMPORT
# ============================================================
function Get-WinToolsRegistryTargets {
    $targets = @(
        @{P="HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; N="HwSchMode"},
        @{P="HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; N="PowerThrottlingOff"},
        @{P="HKCU:\System\GameConfigStore"; N="GameDVR_Enabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"; N="AppCaptureEnabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"; N="VisualFXSetting"},
        @{P="HKCU:\Control Panel\Desktop"; N="MinAnimate"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="TaskbarAnimations"},
        @{P="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; N="HiberbootEnabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; N="Enabled"},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; N="AllowTelemetry"},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; N="DoNotShowFeedbackNotifications"},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; N="DisableFileSyncNGSC"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="RotatingLockScreenEnabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="ContentDeliveryAllowed"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338387Enabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338388Enabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338389Enabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SilentInstalledAppsEnabled"},
        @{P="HKLM:\SYSTEM\CurrentControlSet\Control"; N="WaitToKillServiceTimeout"},
        @{P="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; N="NoDriveTypeAutoRun"},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; N="DODownloadMode"},
        @{P="HKCU:\Software\Microsoft\InputPersonalization"; N="RestrictImplicitInkCollection"},
        @{P="HKCU:\Software\Microsoft\InputPersonalization"; N="RestrictImplicitTextCollection"},
        @{P="HKCU:\Software\Microsoft\GameBar"; N="AllowAutoGameMode"},
        @{P="HKCU:\Software\Microsoft\GameBar"; N="AutoGameModeEnabled"},
        @{P="HKCU:\Control Panel\Mouse"; N="MouseSpeed"},
        @{P="HKCU:\Control Panel\Mouse"; N="MouseThreshold1"},
        @{P="HKCU:\Control Panel\Mouse"; N="MouseThreshold2"},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; N="AllowNewsAndInterests"},
        @{P="HKCU:\Software\Policies\Microsoft\Windows\Explorer"; N="DisableSearchBoxSuggestions"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; N="GlobalUserDisabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"; N="ToastEnabled"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ShowSecondsInSystemClock"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="HideFileExt"},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="Hidden"},
        @{P="HKLM:\SYSTEM\CurrentControlSet\Control\Power"; N="HibernateEnabled"},
        @{P="HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; N="(default)"}
    )
    $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
    foreach ($iface in $ifaces) {
        $targets += @{P=$iface.PSPath; N="TcpAckFrequency"}
        $targets += @{P=$iface.PSPath; N="TCPNoDelay"}
    }
    return $targets
}

function Get-WinToolsStartupPaths {
    return @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\WinToolsDisabled",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\WinToolsDisabled",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run\WinToolsDisabled"
    )
}

function Export-WinToolsSnapshot([string]$reason="manual", [switch]$quiet) {
    $folder = "$env:ProgramData\WinTools\Snapshots"
    if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $safeReason = $reason -replace '[^a-zA-Z0-9_-]', '_'
    $file = Join-Path $folder ("WinTools_{0}_{1}.json" -f $safeReason, (Get-Date -Format "yyyyMMdd_HHmmss"))

    $registry = @()
    foreach ($target in Get-WinToolsRegistryTargets) {
        $exists = $false; $value = $null; $valueType = "String"
        try {
            $value = Get-ItemPropertyValue -Path $target.P -Name $target.N -ErrorAction Stop
            $exists = $true
            $nativeName = if ($target.N -eq "(default)") { "" } else { $target.N }
            $valueType = (Get-Item $target.P -ErrorAction Stop).GetValueKind($nativeName).ToString()
        } catch { $exists = $false }
        $registry += [pscustomobject]@{Path=$target.P; Name=$target.N; Exists=$exists; Value=$value; Type=$valueType}
    }

    $services = @(Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{Name=$_.Name; StartType="$($_.StartType)"; Status="$($_.Status)"}
    })
    $tasks = @()
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{Path=$_.TaskPath; Name=$_.TaskName; State="$($_.State)"}
        })
    }

    $startup = @()
    foreach ($path in Get-WinToolsStartupPaths) {
        $item = Get-ItemProperty $path -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        $item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $type = "String"
            try { $type = (Get-Item $path -ErrorAction Stop).GetValueKind($_.Name).ToString() } catch { $type = "String" }
            $startup += [pscustomobject]@{Path=$path; Name=$_.Name; Value=$_.Value; Type=$type}
        }
    }

    $activeText = (& powercfg /getactivescheme 2>$null) -join " "
    $activeGuid = if ($activeText -match '(?i)[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}') { $matches[0] } else { $null }
    $snapshot = [pscustomobject]@{
        FormatVersion=1; WinToolsVersion=$Script:WinToolsVersion; Created=(Get-Date).ToString("o")
        Reason=$reason; Computer=$env:COMPUTERNAME; User=$env:USERNAME; Windows=$Script:WinVerName
        Registry=$registry; Services=$services; Tasks=$tasks; Startup=$startup; ActivePowerScheme=$activeGuid
    }
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $file -Encoding UTF8 -ErrorAction Stop
    if (-not $quiet) { Write-OK "Snapshot created: $file" }
    return $file
}

function Import-WinToolsSnapshot($path) {
    if (-not (Test-Path $path)) { Write-FAIL "File not found: $path"; return $false }
    try { $snapshot = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Write-FAIL "Could not read snapshot: $($_.Exception.Message)"; return $false }
    if ([int]$snapshot.FormatVersion -ne 1) { Write-FAIL "Unsupported snapshot format: $($snapshot.FormatVersion)"; return $false }

    $preview = @(
        "Snapshot: $($snapshot.Created)",
        "Registry values: $(@($snapshot.Registry).Count)",
        "Services: $(@($snapshot.Services).Count)",
        "Tasks: $(@($snapshot.Tasks).Count)",
        "Startup entries: $(@($snapshot.Startup).Count)",
        "Startup registry entries will be restored to the exact snapshot state"
    )
    if ($snapshot.Computer -and $snapshot.Computer -ne $env:COMPUTERNAME) {
        $preview += "WARNING: snapshot is from another computer: $($snapshot.Computer)"
    }
    if ($snapshot.User -and $snapshot.User -ne $env:USERNAME) {
        $preview += "WARNING: snapshot is from another user: $($snapshot.User)"
    }
    if (-not (Confirm-ActionPreview $preview)) { return $false }

    $preBackup = Export-WinToolsSnapshot -reason "before_import" -quiet
    Write-INFO "Pre-import snapshot: $preBackup"
    $ok=0; $failed=0
    $allowedRegistry = @{}
    foreach ($target in Get-WinToolsRegistryTargets) {
        $allowedRegistry[("{0}|{1}" -f $target.P,$target.N).ToLowerInvariant()] = $true
    }
    $allowedTypes = @("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord", "Unknown")
    foreach ($entry in @($snapshot.Registry)) {
        $registryId = ("{0}|{1}" -f $entry.Path,$entry.Name).ToLowerInvariant()
        if (-not $allowedRegistry.ContainsKey($registryId) -or $allowedTypes -notcontains "$($entry.Type)") { $failed++; continue }
        try {
            if ([bool]$entry.Exists) {
                if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction Stop | Out-Null
            } else {
                $classicRoot = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
                if ($entry.Name -eq "(default)" -and "$($entry.Path)" -like "$classicRoot*") {
                    Remove-Item $classicRoot -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                }
            }
            $ok++
        } catch { $failed++ }
    }
    foreach ($entry in @($snapshot.Services)) {
        try {
            $service = Get-Service -Name $entry.Name -ErrorAction Stop
            if ("$($service.StartType)" -ne "$($entry.StartType)") { Set-Service -Name $entry.Name -StartupType $entry.StartType -ErrorAction Stop }
            if ($entry.Status -eq "Running") { Start-Service -Name $entry.Name -ErrorAction Stop }
            elseif ($service.Status -ne "Stopped") { Stop-Service -Name $entry.Name -Force -ErrorAction Stop }
            $ok++
        } catch { $failed++ }
    }
    foreach ($entry in @($snapshot.Tasks)) {
        try {
            if ($entry.State -eq "Disabled") { Disable-ScheduledTask -TaskPath $entry.Path -TaskName $entry.Name -ErrorAction Stop | Out-Null }
            else { Enable-ScheduledTask -TaskPath $entry.Path -TaskName $entry.Name -ErrorAction Stop | Out-Null }
            $ok++
        } catch { $failed++ }
    }
    $startupPaths = @(Get-WinToolsStartupPaths)
    foreach ($startupPath in $startupPaths) {
        $current = Get-ItemProperty $startupPath -ErrorAction SilentlyContinue
        if ($current) {
            foreach ($property in @($current.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
                try { Remove-ItemProperty -Path $startupPath -Name $property.Name -ErrorAction Stop; $ok++ } catch { $failed++ }
            }
        }
    }
    foreach ($entry in @($snapshot.Startup)) {
        try {
            if ($startupPaths -notcontains "$($entry.Path)" -or $allowedTypes -notcontains "$($entry.Type)") { throw "Unsafe startup snapshot entry" }
            if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction Stop | Out-Null
            $ok++
        } catch { $failed++ }
    }
    if ($snapshot.ActivePowerScheme) {
        & powercfg /setactive $snapshot.ActivePowerScheme 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $failed++ }
    }
    if ($failed -eq 0) { Write-OK "Snapshot restored. Successful operations: $ok"; return $true }
    Write-FAIL "Import was partial: $ok succeeded, $failed failed"
    return $false
}
# ============================================================
# MENU 16 - SYSTEM PROFILES
# ============================================================
function Menu-Profiles {
    Draw-Header "SYSTEM PROFILES - safe groups of settings"
    $hasBattery = $null -ne (Get-WinToolsCimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1)
    $recommended = if ($hasBattery) { 2 } else { 1 }
    $profiles = @(
        @{N=1; Name="Gaming Desktop"; Desc="Maximum performance for a desktop"; Power="SCHEME_MIN"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",2,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",1,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",0,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",0,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",1,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",1,"DWord","Game Mode")
        )},
        @{N=2; Name="Gaming Laptop"; Desc="Gaming settings without disabling power saving"; Power="SCHEME_BALANCED"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",2,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",0,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",0,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",0,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",1,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",1,"DWord","Game Mode")
        )},
        @{N=3; Name="Balanced"; Desc="Standard power and minimal changes"; Power="SCHEME_BALANCED"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",1,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",0,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",1,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",1,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects","VisualFXSetting",0,"DWord","Visual FX"),
            @("HKCU:\Control Panel\Desktop","MinAnimate","1","String","MinAnimate"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","TaskbarAnimations",1,"DWord","Taskbar Animations"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",0,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",0,"DWord","Game Mode")
        )},
        @{N=4; Name="Privacy"; Desc="Telemetry, ads, tips, web search and widgets"; Power=$null; Values=@(
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo","Enabled",0,"DWord","Advertising ID"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","AllowTelemetry",0,"DWord","Telemetry"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","DoNotShowFeedbackNotifications",1,"DWord","Feedback"),
            @("HKCU:\Software\Policies\Microsoft\Windows\Explorer","DisableSearchBoxSuggestions",1,"DWord","Web Search"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Dsh","AllowNewsAndInterests",0,"DWord","Widgets"),
            @("HKCU:\Software\Microsoft\InputPersonalization","RestrictImplicitInkCollection",1,"DWord","Ink Collection"),
            @("HKCU:\Software\Microsoft\InputPersonalization","RestrictImplicitTextCollection",1,"DWord","Text Collection"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","RotatingLockScreenEnabled",0,"DWord","Windows Spotlight"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","ContentDeliveryAllowed",0,"DWord","Content Delivery"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338387Enabled",0,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338388Enabled",0,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338389Enabled",0,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SilentInstalledAppsEnabled",0,"DWord","Suggested Apps")
        )},
        @{N=5; Name="Windows Defaults"; Desc="Restore standard values managed by profiles"; Power="SCHEME_BALANCED"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",1,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",0,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",1,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",1,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo","Enabled",1,"DWord","Advertising ID"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","AllowTelemetry",1,"DWord","Telemetry"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","DoNotShowFeedbackNotifications",0,"DWord","Feedback"),
            @("HKCU:\Software\Policies\Microsoft\Windows\Explorer","DisableSearchBoxSuggestions",0,"DWord","Web Search"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Dsh","AllowNewsAndInterests",1,"DWord","Widgets"),
            @("HKCU:\Software\Microsoft\InputPersonalization","RestrictImplicitInkCollection",0,"DWord","Ink Collection"),
            @("HKCU:\Software\Microsoft\InputPersonalization","RestrictImplicitTextCollection",0,"DWord","Text Collection"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",0,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",0,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects","VisualFXSetting",0,"DWord","Visual FX"),
            @("HKCU:\Control Panel\Desktop","MinAnimate","1","String","MinAnimate"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","TaskbarAnimations",1,"DWord","Taskbar Animations"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","RotatingLockScreenEnabled",1,"DWord","Windows Spotlight"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","ContentDeliveryAllowed",1,"DWord","Content Delivery"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338387Enabled",1,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338388Enabled",1,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SubscribedContent-338389Enabled",1,"DWord","Windows Suggestions"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager","SilentInstalledAppsEnabled",1,"DWord","Suggested Apps")
        )}
    )
    foreach ($selectedProfile in $profiles) {
        $mark = if ($selectedProfile.N -eq $recommended) { " <<< RECOMMENDED FOR THIS DEVICE" } else { "" }
        Write-Host ("  [{0}] {1,-20} {2}{3}" -f $selectedProfile.N,$selectedProfile.Name,$selectedProfile.Desc,$mark) -ForegroundColor $(if($mark){"Green"}else{"White"})
    }
    Write-Host "  [0] Back" -ForegroundColor DarkGray
    Write-Host "`n  Choose: " -NoNewline
    $choice=(Read-Host).Trim()
    if($choice -eq "0"){return}
    $selectedProfile=$profiles|Where-Object{"$($_.N)" -eq $choice}|Select-Object -First 1
    if(-not $selectedProfile){Write-FAIL "Invalid profile";Pause-Menu;return}
    $preview=@("Profile: $($selectedProfile.Name)") + @($selectedProfile.Values|ForEach-Object{"[REGISTRY] $($_[4]) → $($_[2])"})
    if($selectedProfile.Power){$preview += "[POWER] $($selectedProfile.Power)"}
    if(-not(Confirm-ActionPreview $preview)){Menu-Profiles;return}
    $backup=Export-WinToolsSnapshot -reason "before_profile_$($selectedProfile.N)" -quiet
    Write-INFO "Backup snapshot: $backup"
    $profileFailures = 0
    foreach ($v in $selectedProfile.Values) {
        try { Set-RegLogged $v[0] $v[1] $v[2] $v[3] $v[4] }
        catch { $profileFailures++; Write-FAIL "$($v[4]): $($_.Exception.Message)" }
    }
    if ($selectedProfile.Power) {
        & powercfg /setactive $selectedProfile.Power 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $profileFailures++; Write-FAIL "Could not activate the power scheme: exit code $LASTEXITCODE" }
    }
    if ($profileFailures -eq 0) { Write-OK "Profile applied: $($selectedProfile.Name)" }
    else { Write-FAIL "Profile finished with $profileFailures error(s). Use the backup snapshot to roll back." }
    Pause-Menu
}
# ============================================================
# MENU 17 - EXPORT / IMPORT
# ============================================================
function Menu-Snapshots {
    Draw-Header "EXPORT / IMPORT - settings snapshots"
    $folder="$env:ProgramData\WinTools\Snapshots"
    Write-Host "  [1] Create a full settings snapshot" -ForegroundColor Green
    Write-Host "  [2] Import the latest snapshot" -ForegroundColor White
    Write-Host "  [3] Import a file by path" -ForegroundColor White
    Write-Host "  [4] Show saved snapshots" -ForegroundColor White
    Write-Host "  [0] Back" -ForegroundColor DarkGray
    Write-Host "`n  Choose: " -NoNewline
    $choice=(Read-Host).Trim()
    switch($choice){
        "1" { try{$path=Export-WinToolsSnapshot -reason "manual";Write-OK "Snapshot saved: $path"}catch{Write-FAIL $_.Exception.Message} }
        "2" { $last=Get-ChildItem $folder -Filter "*.json" -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($last){if(-not(Import-WinToolsSnapshot $last.FullName)){Menu-Snapshots;return}}else{Write-INFO "No snapshots found"} }
        "3" { Write-Host "  Path: " -NoNewline;$path=Read-Host;if(-not(Import-WinToolsSnapshot $path)){Menu-Snapshots;return} }
        "4" { Get-ChildItem $folder -Filter "*.json" -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|ForEach-Object{Write-Host("  {0}  {1:N1} KB" -f $_.FullName,($_.Length/1KB))} }
        "0" { return }
    }
    Pause-Menu
}

# ============================================================
# MENU 18 - DIAGNOSTICS
# ============================================================
function Menu-Diagnostics {
    Draw-Header "DIAGNOSTICS - full read-only report"
    Write-INFO "Collecting data; this can take a few seconds..."
    $lines = New-Object System.Collections.Generic.List[string]
    $os=Get-WinToolsCimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs=Get-WinToolsCimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu=Get-WinToolsCimInstance Win32_Processor -ErrorAction SilentlyContinue|Select-Object -First 1
    $gpus=@(Get-WinToolsCimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object{$_.Name -notmatch 'Basic|Remote'})
    $uptime=if($os.LastBootUpTime){[math]::Round(((Get-Date)-[datetime]$os.LastBootUpTime).TotalHours,1)}else{"?"}
    $lines.Add("WINTOOLS DIAGNOSTIC REPORT")
    $lines.Add("Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("WinTools: $Script:WinToolsVersion")
    $lines.Add("OS: $($os.Caption), build $($os.BuildNumber), $($os.OSArchitecture)")
    $lines.Add("Computer: $($cs.Manufacturer) $($cs.Model)")
    $lines.Add("CPU: $($cpu.Name)")
    $lines.Add("RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB")
    $lines.Add("GPUs: $(($gpus.Name) -join '; ')")
    $lines.Add("Uptime: $uptime h")
    $lines.Add("")
    $lines.Add("--- DISKS ---")
    try { Get-PhysicalDisk -ErrorAction Stop|ForEach-Object{$lines.Add("$($_.FriendlyName): $($_.MediaType), Health=$($_.HealthStatus), Size=$([math]::Round($_.Size/1GB)) GB")} } catch {$lines.Add("Physical disks: unavailable")}
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{$lines.Add("$($_.Name): free $([math]::Round($_.Free/1GB,1)) / $([math]::Round(($_.Used+$_.Free)/1GB,1)) GB")}
    $lines.Add("")
    $lines.Add("--- SECURITY AND UPDATES ---")
    $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
    $lines.Add("Windows Update: $($wu.Status), StartType=$($wu.StartType)")
    if(Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue){try{$mp=Get-MpComputerStatus -ErrorAction Stop;$lines.Add("Defender: Antivirus=$($mp.AntivirusEnabled), RealTime=$($mp.RealTimeProtectionEnabled), Signatures=$($mp.AntivirusSignatureLastUpdated)")}catch{$lines.Add("Defender: unavailable")}}
    $pending=(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
    $lines.Add("Pending reboot: $pending")
    $lines.Add("")
    $lines.Add("--- DEVICES AND ERRORS ---")
    if(Get-Command Get-PnpDevice -ErrorAction SilentlyContinue){$bad=@(Get-PnpDevice -ErrorAction SilentlyContinue|Where-Object{$_.Status -ne 'OK'});$lines.Add("Problem devices: $($bad.Count)");$bad|Select-Object -First 20|ForEach-Object{$lines.Add("  $($_.Status): $($_.FriendlyName)")}}
    try{$events=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddHours(-24)} -MaxEvents 20 -ErrorAction Stop);$lines.Add("Critical/error events in 24h: $($events.Count)");$events|Select-Object -First 10|ForEach-Object{$lines.Add("  $($_.TimeCreated) [$($_.Id)] $($_.ProviderName): $(($_.Message -replace '[\r\n]+',' ') | Select-Object -First 1)")}}catch{$lines.Add("System events: unavailable")}
    $disabled=@(Get-Service -ErrorAction SilentlyContinue|Where-Object{$_.StartType -eq 'Disabled'})
    $lines.Add("Disabled services: $($disabled.Count)")
    $folder="$env:ProgramData\WinTools\Reports";if(-not(Test-Path $folder)){New-Item $folder -ItemType Directory -Force|Out-Null}
    $file=Join-Path $folder ("diagnostic_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines|Set-Content $file -Encoding UTF8
    Clear-Host;$lines|ForEach-Object{Write-Host "  $_"}
    Write-OK "Report saved: $file"
    Pause-Menu
}
# ============================================================
# MENU 19 - APPLICATION MANAGER
# ============================================================
function Menu-Applications {
    Draw-Header "APPLICATION MANAGER - install through winget"
    if(-not(Get-Command winget -ErrorAction SilentlyContinue)){Write-FAIL "winget was not found. Install App Installer from Microsoft Store.";Pause-Menu;return}
    $apps=@(
        @{N=1;Name="7-Zip";Id="7zip.7zip"}, @{N=2;Name="VLC";Id="VideoLAN.VLC"},
        @{N=3;Name="Notepad++";Id="Notepad++.Notepad++"}, @{N=4;Name="PowerToys";Id="Microsoft.PowerToys"},
        @{N=5;Name="Steam";Id="Valve.Steam"}, @{N=6;Name="Discord";Id="Discord.Discord"},
        @{N=7;Name="Epic Games Launcher";Id="EpicGames.EpicGamesLauncher"},
        @{N=8;Name="Firefox";Id="Mozilla.Firefox"}, @{N=9;Name="Brave";Id="Brave.Brave"},
        @{N=10;Name="qBittorrent";Id="qBittorrent.qBittorrent"}, @{N=11;Name="Bitwarden";Id="Bitwarden.Bitwarden"},
        @{N=12;Name="Malwarebytes";Id="Malwarebytes.Malwarebytes"}
    )
    $packs=@(
        @{Key="G";Name="Games";Nums=1,5,6,7}, @{Key="I";Name="Internet";Nums=8,9,10},
        @{Key="S";Name="Security";Nums=11,12}, @{Key="B";Name="Basic";Nums=1,2,3,4}
    )
    Write-Host "  Profiles:" -ForegroundColor Cyan;$packs|ForEach-Object{Write-Host("  [{0}] {1}: {2}" -f $_.Key,$_.Name,(($_.Nums|ForEach-Object{$apps[$_-1].Name}) -join ', '))}
    Write-Host "`n  Applications:" -ForegroundColor Cyan;$apps|ForEach-Object{Write-Host("  [{0,2}] {1,-24} {2}" -f $_.N,$_.Name,$_.Id)}
    Write-Host "`n  [U] Update all installed applications" -ForegroundColor Green
    Write-Host "  [0] Back`n  Choose a profile or numbers (1,3,5-7): " -NoNewline
    $choice=(Read-Host).Trim();if($choice -eq '0'){return}
    if($choice -match '^(?i:u)$'){
        if(-not(Confirm-ActionPreview @("[WINGET] Update all applications"))){Menu-Applications;return}
        & winget upgrade --all --accept-package-agreements --accept-source-agreements --silent
        if($LASTEXITCODE -eq 0){Write-OK "Update complete"}else{Write-FAIL "winget exited with code $LASTEXITCODE"}
        Pause-Menu;return
    }
    $pack=$packs|Where-Object{$_.Key -eq $choice.ToUpper()}|Select-Object -First 1
    try{$selected=if($pack){@($pack.Nums|ForEach-Object{$apps[$_-1]})}else{@(ConvertTo-NumberList $choice $apps.Count|ForEach-Object{$apps[$_-1]})}}catch{Write-FAIL $_.Exception.Message;Pause-Menu;return}
    if(-not(Confirm-ActionPreview @($selected|ForEach-Object{"[INSTALL] $($_.Name) ($($_.Id))"}))){Menu-Applications;return}
    foreach($app in $selected){Write-INFO "Installing $($app.Name)...";& winget install --id $app.Id --exact --accept-package-agreements --accept-source-agreements --silent;if($LASTEXITCODE -eq 0){Write-OK "$($app.Name): done"}else{Write-FAIL "$($app.Name): code $LASTEXITCODE"}}
    Pause-Menu
}
# ============================================================
# MENU 20 - SELF UPDATE
# ============================================================
function Get-WinToolsUpdateManifest {
    $url="https://raw.githubusercontent.com/$Script:Repository/main/version.json"
    try{return Invoke-RestMethod -Uri $url -TimeoutSec 8 -ErrorAction Stop}catch{return $null}
}
function Invoke-WinToolsUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$manifest,
        [string]$installRoot = $PSScriptRoot,
        [string]$downloadBase = "https://raw.githubusercontent.com/$Script:Repository/main"
    )
    if (-not $installRoot) { Write-FAIL "Auto-update is available when running from a local folder"; return $false }
    $files = @($manifest.files)
    if ($files.Count -eq 0) { Write-FAIL "The update manifest contains no files"; return $false }

    $updateRoot = "$env:ProgramData\WinTools\Update"
    $backupRoot = "$env:ProgramData\WinTools\Backups"
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $stage = Join-Path $updateRoot $stamp
    $backup = Join-Path $backupRoot $stamp
    $mutationStarted = $false
    try {
        New-Item $stage -ItemType Directory -Force -ErrorAction Stop | Out-Null
        New-Item $backup -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $seen = @{}
        foreach ($file in $files) {
            $relative = "$($file.path)"
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
                $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -notmatch '^[a-zA-Z0-9_.\\/-]+$') {
                throw "Unsafe update path: $relative"
            }
            if ($seen.ContainsKey($relative.ToLowerInvariant())) { throw "Duplicate update path: $relative" }
            $seen[$relative.ToLowerInvariant()] = $true
            if ("$($file.sha256)" -notmatch '^[0-9a-fA-F]{64}$') { throw "Missing or invalid SHA-256: $relative" }

            $temporary = Join-Path $stage $relative
            $parent = Split-Path $temporary -Parent
            if (-not (Test-Path $parent)) { New-Item $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null }
            Invoke-WebRequest -Uri "$downloadBase/$relative" -OutFile $temporary -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $hash = (Get-FileHash $temporary -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($hash -ne "$($file.sha256)") { throw "Hash mismatch: $relative" }
        }

        # Back up every destination before touching any installed file.
        foreach ($file in $files) {
            $relative = "$($file.path)"
            $target = Join-Path $installRoot $relative
            if (Test-Path $target) {
                $saved = Join-Path $backup $relative
                $parent = Split-Path $saved -Parent
                if (-not (Test-Path $parent)) { New-Item $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null }
                Copy-Item $target $saved -Force -ErrorAction Stop
            }
        }

        $mutationStarted = $true
        foreach ($file in $files) {
            $relative = "$($file.path)"
            $target = Join-Path $installRoot $relative
            $parent = Split-Path $target -Parent
            if (-not (Test-Path $parent)) { New-Item $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null }
            Copy-Item (Join-Path $stage $relative) $target -Force -ErrorAction Stop
            $installedHash = (Get-FileHash $target -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($installedHash -ne "$($file.sha256)") { throw "Installed-file verification failed: $relative" }
        }

        Write-OK "WinTools updated to version: $($manifest.version)"
        Write-INFO "Backup: $backup"
        Write-INFO "Restart WinTools to use the new version"
        return $true
    } catch {
        $failure = $_.Exception.Message
        if ($mutationStarted) {
            $rollbackFailures = 0
            foreach ($file in $files) {
                $relative = "$($file.path)"
                $target = Join-Path $installRoot $relative
                $saved = Join-Path $backup $relative
                try {
                    if (Test-Path $saved) { Copy-Item $saved $target -Force -ErrorAction Stop }
                    elseif (Test-Path $target) { Remove-Item $target -Force -ErrorAction Stop }
                } catch { $rollbackFailures++ }
            }
            if ($rollbackFailures -eq 0) { Write-INFO "The failed update was rolled back; original files were restored" }
            else { Write-FAIL "Rollback was incomplete for $rollbackFailures file(s). Backup: $backup" }
        }
        Write-FAIL "Update failed: $failure"
        return $false
    } finally {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Test-WinToolsUpdate([switch]$startupCheck) {
    $stamp="$env:ProgramData\WinTools\last_update_check.txt"
    if($startupCheck -and (Test-Path $stamp)){
        try { if (((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalHours -lt 24) { return } }
        catch { $null = $_.Exception }
    }
    # Record the attempt even when the network is unavailable, so startup is
    # never delayed by more than one check per 24 hours.
    $stampFolder = Split-Path $stamp -Parent
    if (-not (Test-Path $stampFolder)) { New-Item $stampFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-Content $stamp (Get-Date).ToString("o") -Encoding ASCII -ErrorAction SilentlyContinue
    $manifest=Get-WinToolsUpdateManifest
    if(-not $manifest){if(-not $startupCheck){Write-INFO "Could not check for updates"};return}
    try { $newer = [version]$manifest.version -gt [version]$Script:WinToolsVersion }
    catch { if (-not $startupCheck) { Write-FAIL "Invalid version in update manifest" }; return }
    if(-not $newer){if(-not $startupCheck){Write-OK "You have the latest version: $Script:WinToolsVersion"};return}
    Write-Host "";Write-Host "  Update available: $Script:WinToolsVersion → $($manifest.version)" -ForegroundColor Green
    $notes=if($Script:WinToolsLanguage -eq 'ru'){$manifest.notes_ru}else{$manifest.notes_en};@($notes)|ForEach-Object{Write-Host "  • $_" -ForegroundColor White}
    Write-Host "  [U/Y] Update now   [L/N/Enter] Later: " -NoNewline -ForegroundColor Yellow
    $answer=(Read-Host).Trim()
    if($answer -match '^(?i:u|y|yes|д|да)$'){$null=Invoke-WinToolsUpdate $manifest}else{Write-INFO "Update postponed. Run it later from menu [20]"}
}
function Menu-Update {
    Draw-Header "WINTOOLS UPDATE"
    Write-Host "  Current version: $Script:WinToolsVersion"
    Write-Host "  [1] Check for updates now" -ForegroundColor Green
    Write-Host "  [0] Back"
    Write-Host "`n  Choose: " -NoNewline
    $choice=Read-Host;if($choice -eq '1'){Test-WinToolsUpdate}else{return};Pause-Menu
}

# ============================================================
# MAIN MENU
# ============================================================
function Main-Menu {
    while ($true) {
        Draw-Header $null
        Write-Host "  What do you want to do?" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  #  |  Section                  |  What it does                    |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  1  |  Services                 |  Disable unused background svcs  |" -ForegroundColor Green
        Write-Host "  |  2  |  Registry Tweaks          |  GPU, network, privacy fixes     |" -ForegroundColor Green
        Write-Host "  |  3  |  Scheduled Tasks          |  Kill telemetry tasks            |" -ForegroundColor Green
        Write-Host "  |  4  |  Startup Programs         |  Remove autostart entries        |" -ForegroundColor Green
        Write-Host "  |  5  |  Disk Cleanup             |  Free GB on C: drive             |" -ForegroundColor Yellow
        Write-Host "  |  6  |  Live Monitor             |  CPU/RAM/Disk in real time       |" -ForegroundColor Cyan
        Write-Host "  |  7  |  Power Plan               |  Set Ultimate Performance        |" -ForegroundColor Green
        Write-Host "  |  8  |  SMB1 Security            |  Fix security vulnerability      |" -ForegroundColor Red
        Write-Host "  |  9  |  System Health            |  SSD, temps, drivers, fonts      |" -ForegroundColor Cyan
        Write-Host "  | 10  |  Driver Update            |  Open manufacturer driver pages  |" -ForegroundColor Cyan
        Write-Host "  | 11  |  Restore Point            |  System snapshot before changes  |" -ForegroundColor Magenta
        Write-Host "  | 12  |  Change Log & Undo        |  View/undo changes made          |" -ForegroundColor Magenta
        Write-Host "  | 13  |  Bloatware Apps           |  Remove Xbox, Solitaire, etc.    |" -ForegroundColor Yellow
        Write-Host "  | 14  |  Browser Cache            |  Clear Brave/Chrome/Edge at once |" -ForegroundColor Yellow
        Write-Host "  | 15  |  Windows Cosmetics        |  Classic menu, file extensions   |" -ForegroundColor White
        Write-Host "  | 16  |  System Profiles          |  Gaming, balanced, privacy       |" -ForegroundColor Green
        Write-Host "  | 17  |  Export / Import          |  JSON configuration snapshots   |" -ForegroundColor Magenta
        Write-Host "  | 18  |  Diagnostics              |  Full read-only report           |" -ForegroundColor Cyan
        Write-Host "  | 19  |  Application Manager      |  Games/Internet/Security packs   |" -ForegroundColor Yellow
        Write-Host "  | 20  |  WinTools Update          |  Check for a newer version       |" -ForegroundColor White
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Exit                     |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  TIP: Start with [11] restore point, then [1] Services -> [A]" -ForegroundColor DarkCyan
        Write-Host "  WINDOWS: $Script:WinVerName | WINTOOLS: $Script:WinToolsVersion" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Choose: " -ForegroundColor White -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1"  { Menu-Services }
            "2"  { Menu-Registry }
            "3"  { Menu-Tasks }
            "4"  { Menu-Startup }
            "5"  { Menu-DiskCleanup }
            "6"  { Menu-Monitor }
            "7"  { Menu-PowerPlan }
            "8"  { Menu-SMB }
            "9"  { Menu-Health }
            "10" { Menu-DriverUpdate }
            "11" { Menu-RestorePoint }
            "12" { Menu-ChangeLog }
            "13" { Menu-Bloatware }
            "14" { Menu-BrowserCache }
            "15" { Menu-Cosmetics }
            "16" { Menu-Profiles }
            "17" { Menu-Snapshots }
            "18" { Menu-Diagnostics }
            "19" { Menu-Applications }
            "20" { Menu-Update }
            "0"  { Clear-Host; exit }
        }
    }
}

# Check at most once every 24 hours. A failure never blocks startup.
Test-WinToolsUpdate -startupCheck
Main-Menu
