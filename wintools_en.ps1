# WinTools - Windows Optimization Suite (English version)
# Run as Administrator
# Supports: Windows 10 Home/Pro, Windows 11 Home/Pro/LTSC/InsiderPreview
# Version is auto-detected or selected via install.ps1

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ERROR: Run as Administrator!" -ForegroundColor Red
    Start-Sleep 3; exit
}

# ============================================================
# WINDOWS VERSION DETECTION
# ============================================================
function Get-WindowsVersion {
    $os = Get-WmiObject Win32_OperatingSystem
    $caption = $os.Caption
    $build = $os.BuildNumber

    if ($caption -match "Windows 10") {
        if ($caption -match "Pro")        { return "win10pro" }
        elseif ($caption -match "Home")   { return "win10home" }
        else                              { return "win10pro" }
    }
    elseif ($caption -match "Windows 11") {
        if ($caption -match "LTSC|Enterprise") { return "win11ltsc" }
        elseif ($caption -match "Insider")      { return "win11insider" }
        elseif ($caption -match "Pro")          { return "win11pro" }
        elseif ($caption -match "Home")         { return "win11home" }
        else                                    { return "win11pro" }
    }
    return "unknown"
}

$Script:WinVer = Get-WindowsVersion
$Script:WinVerName = switch ($Script:WinVer) {
    "win10home"    { "Windows 10 Home" }
    "win10pro"     { "Windows 10 Pro" }
    "win11home"    { "Windows 11 Home" }
    "win11pro"     { "Windows 11 Pro" }
    "win11ltsc"    { "Windows 11 Enterprise LTSC" }
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
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $safeOld = if ($null -eq $oldValue) { "NULL" } else { "$oldValue" }
    $safeDesc = ($desc -replace ",", ";")
    $safeTarget = ($target -replace ",", ";")
    "$ts,$type,$safeTarget,$safeOld,$safeDesc" | Out-File -FilePath $Global:LogPath -Append -Encoding UTF8
}

function Set-RegLogged($path, $name, $value, $type, $desc) {
    $old = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    Write-ActionLog -type "Registry" -target "$path|$name" -oldValue $old -desc $desc
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -ErrorAction SilentlyContinue
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  [ Press any key to go back ]" -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-FolderSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    $s = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $s) { return 0 }
    return [math]::Round($s / 1GB, 2)
}

function Disable-Svc($name, $label) {
    $found = Get-Service | Where-Object { $_.Name -like "$name*" } | Select-Object -First 1
    if ($found -and $found.StartType -ne "Disabled") {
        Write-ActionLog -type "Service" -target $found.Name -oldValue $found.StartType -desc $label
        Stop-Service -Name $found.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $found.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "Disabled: $label"
    } else {
        Write-SKIP "Already disabled or not found: $label"
    }
}

function Get-StatusLine {
    $free    = [math]::Round((Get-PSDrive C -ErrorAction SilentlyContinue).Free/1GB,1)
    $os      = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramFree = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $ramTotal= [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    $ramUsed = [math]::Round($ramTotal - $ramFree,1)
    $proc    = (Get-Process -ErrorAction SilentlyContinue).Count
    $cpu     = [math]::Round((Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average,0)
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
    Write-Host "  | Enter numbers comma-separated to DISABLE. Example: 1,3,5-9     |" -ForegroundColor Cyan
    Write-Host "  | [A] Disable all recommended (green)                           |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                         |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    $toDisableNames = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $toDisableNames = $recommendedOff
    } else {
        $parts = $choice -split ","
        foreach ($p in $parts) {
            $p = $p.Trim()
            if ($p -match "^(\d+)-(\d+)$") {
                $from = [int]$matches[1]; $to = [int]$matches[2]
                for ($n = $from; $n -le $to; $n++) { if ($indexMap.ContainsKey($n)) { $toDisableNames += $indexMap[$n] } }
            } elseif ($p -match "^\d+$") {
                $n = [int]$p
                if ($indexMap.ContainsKey($n)) { $toDisableNames += $indexMap[$n] }
            }
        }
    }

    Write-Host ""
    if ($toDisableNames.Count -eq 0) { Write-INFO "Nothing selected" }
    else {
        foreach ($svcName in $toDisableNames) {
            $desc = ($svcList | Where-Object { $_.N -eq $svcName }).Desc
            Disable-Svc $svcName $desc
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 2 - REGISTRY TWEAKS
# ============================================================
function Menu-Registry {
    Draw-Header "REGISTRY TWEAKS - Performance and privacy"
    Write-Host "  Each tweak improves performance or removes tracking." -ForegroundColor DarkGray
    Write-Host "  [A] = apply all recommended at once." -ForegroundColor DarkGray
    Write-Host ""

    $tweaks = @(
        @{Num="1";  Rec=$true;  Desc="GPU Scheduling on            Faster GPU, less frame latency"}
        @{Num="2";  Rec=$true;  Desc="Nagle Algorithm off           Lower network latency for games"}
        @{Num="3";  Rec=$true;  Desc="Power Throttling off          No CPU throttling in background"}
        @{Num="4";  Rec=$true;  Desc="Game DVR off                  Removes Xbox recording overhead"}
        @{Num="5";  Rec=$true;  Desc="Visual Effects best perf      Disables animations, faster UI"}
        @{Num="6";  Rec=$true;  Desc="Fast Startup off              Real shutdown, no cache corruption"}
        @{Num="7";  Rec=$true;  Desc="Advertising ID off             Disables ad tracking ID"}
        @{Num="8";  Rec=$true;  Desc="Telemetry off                 Stops data collection to Microsoft"}
        @{Num="9";  Rec=$false; Desc="OneDrive off                  Disables OneDrive sync policy"}
        @{Num="10"; Rec=$true;  Desc="Spotlight lockscreen off      No Microsoft ads on lock screen"}
        @{Num="11"; Rec=$true;  Desc="Faster shutdown 2 sec          Services killed after 2s on shutdown"}
        @{Num="12"; Rec=$true;  Desc="NTFS tweaks                    Disable last access time, 8.3 names"}
        @{Num="13"; Rec=$true;  Desc="Autorun off                    No autorun from USB drives"}
        @{Num="14"; Rec=$true;  Desc="Delivery Optimization off      Stop sharing your bandwidth"}
        @{Num="15"; Rec=$true;  Desc="Typing personalization off     Stop keystroke collection"}
    )

    if ($Script:IsWin11) {
        $tweaks += @{Num="16"; Rec=$true; Desc="Classic context menu (Win11)    Old menu instead of new Win11 menu"}
    }

    foreach ($t in $tweaks) {
        $tag = if ($t.Rec) { "[REC]" } else { "[OPT]" }
        $color = if ($t.Rec) { "Green" } else { "Yellow" }
        $line = "  $tag [$($t.Num)] $($t.Desc)"
        if ($t.Num.Length -eq 1) { $line = "  $tag [ $($t.Num)] $($t.Desc)" }
        Write-Host $line -ForegroundColor $color
    }

    $allRec = ($tweaks | Where-Object { $_.Rec }).Num

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Apply ALL recommended tweaks at once                    |" -ForegroundColor Cyan
    Write-Host "  | [1-$($tweaks.Count)] Apply a specific tweak                              |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Apply-Tweak($num) {
        switch ($num) {
            "1" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "DWord" "GPU Scheduling"
                Write-OK "Hardware GPU Scheduling enabled"
            }
            "2" {
                $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
                foreach ($iface in $ifaces) {
                    $props = Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue
                    if ($props.DhcpIPAddress -like "192.168.*") {
                        Set-RegLogged $iface.PSPath "TcpAckFrequency" 1 "DWord" "Nagle TcpAckFrequency"
                        Set-RegLogged $iface.PSPath "TCPNoDelay" 1 "DWord" "Nagle TCPNoDelay"
                        Write-OK "Nagle disabled on $($props.DhcpIPAddress)"
                    }
                }
            }
            "3" {
                $pt = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $pt)) { New-Item -Path $pt -Force | Out-Null }
                Set-RegLogged $pt "PowerThrottlingOff" 1 "DWord" "Power Throttling"
                Write-OK "Power Throttling disabled"
            }
            "4" {
                $gdvr = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path $gdvr)) { New-Item -Path $gdvr -Force | Out-Null }
                Set-RegLogged $gdvr "GameDVR_Enabled" 0 "DWord" "Game DVR"
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "DWord" "App Capture"
                Write-OK "Game DVR disabled"
            }
            "5" {
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 "DWord" "Visual FX"
                Set-RegLogged "HKCU:\Control Panel\Desktop" "MinAnimate" "0" "String" "MinAnimate"
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0 "DWord" "Taskbar Animations"
                Write-OK "Visual Effects set to Best Performance"
            }
            "6" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 "DWord" "Fast Startup"
                Write-OK "Fast Startup disabled"
            }
            "7" {
                $ad = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
                if (-not (Test-Path $ad)) { New-Item -Path $ad -Force | Out-Null }
                Set-RegLogged $ad "Enabled" 0 "DWord" "Advertising ID"
                Write-OK "Advertising ID disabled"
            }
            "8" {
                $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
                Set-RegLogged $dc "AllowTelemetry" 0 "DWord" "Telemetry"
                Set-RegLogged $dc "DoNotShowFeedbackNotifications" 1 "DWord" "Feedback Notifications"
                Write-OK "Telemetry disabled"
            }
            "9" {
                $od = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
                if (-not (Test-Path $od)) { New-Item -Path $od -Force | Out-Null }
                Set-RegLogged $od "DisableFileSyncNGSC" 1 "DWord" "OneDrive"
                Write-OK "OneDrive disabled"
            }
            "10" {
                $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                if (-not (Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
                Set-RegLogged $cdm "RotatingLockScreenEnabled" 0 "DWord" "Spotlight"
                Set-RegLogged $cdm "ContentDeliveryAllowed" 0 "DWord" "Content Delivery"
                Set-RegLogged $cdm "SubscribedContent-338387Enabled" 0 "DWord" "Tips"
                Set-RegLogged $cdm "SubscribedContent-338388Enabled" 0 "DWord" "Suggestions"
                Set-RegLogged $cdm "SubscribedContent-338389Enabled" 0 "DWord" "Suggestions2"
                Set-RegLogged $cdm "SilentInstalledAppsEnabled" 0 "DWord" "Silent Installs"
                Write-OK "Spotlight and ads disabled"
            }
            "11" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" "String" "Shutdown timeout"
                Write-OK "Shutdown timeout set to 2 seconds"
            }
            "12" {
                fsutil behavior set disablelastaccess 1 | Out-Null
                fsutil behavior set disable8dot3 1 | Out-Null
                Write-ActionLog -type "FSUtil" -target "NTFS" -oldValue "unknown" -desc "NTFS last access + 8.3 names"
                Write-OK "NTFS last access and 8.3 names disabled"
            }
            "13" {
                $ar = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                if (-not (Test-Path $ar)) { New-Item -Path $ar -Force | Out-Null }
                Set-RegLogged $ar "NoDriveTypeAutoRun" 255 "DWord" "Autorun"
                Write-OK "Autorun disabled for all drives"
            }
            "14" {
                $do = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
                if (-not (Test-Path $do)) { New-Item -Path $do -Force | Out-Null }
                Set-RegLogged $do "DODownloadMode" 0 "DWord" "Delivery Optimization"
                Write-OK "Delivery Optimization disabled"
            }
            "15" {
                $ink = "HKCU:\Software\Microsoft\InputPersonalization"
                if (-not (Test-Path $ink)) { New-Item -Path $ink -Force | Out-Null }
                Set-RegLogged $ink "RestrictImplicitInkCollection" 1 "DWord" "Ink Collection"
                Set-RegLogged $ink "RestrictImplicitTextCollection" 1 "DWord" "Text Collection"
                Write-OK "Typing personalization disabled"
            }
            "16" {
                $classicMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                if (-not (Test-Path $classicMenuPath)) { New-Item -Path $classicMenuPath -Force | Out-Null }
                Set-RegLogged $classicMenuPath "(default)" "" "String" "Classic Context Menu"
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Start-Process explorer
                Write-OK "Classic context menu enabled"
            }
        }
    }

    Write-Host ""
    if ($choice -eq "A" -or $choice -eq "a") {
        foreach ($n in $allRec) { Apply-Tweak $n }
    } elseif ($choice -match "^\d+$") { Apply-Tweak $choice }
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
    Write-Host "  | [1-$($tasks.Count)] Disable a specific task                                |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    $selected = @()
    if ($choice -eq "A" -or $choice -eq "a") { $selected = $tasks }
    elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $tasks.Count) { $selected = @($tasks[[int]$choice - 1]) }

    Write-Host ""
    foreach ($t in $selected) {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne "Disabled") {
            Write-ActionLog -type "Task" -target "$($t.Path)|$($t.Name)" -oldValue $task.State -desc $t.Name
            Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
            Write-OK "Disabled: $($t.Name)"
        } else { Write-SKIP "Already disabled or not found: $($t.Name)" }
    }
    Pause-Menu
}

# ============================================================
# MENU 4 - STARTUP
# ============================================================
function Menu-Startup {
    Draw-Header "STARTUP PROGRAMS - What runs when Windows boots"
    Write-Host "  Enter a number to remove a program from startup." -ForegroundColor DarkGray
    Write-Host ""

    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )

    $entries = @()
    foreach ($path in $regPaths) {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if ($items) {
            $items.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                $entries += @{Name=$_.Name; Value=$_.Value; Path=$path}
            }
        }
    }

    if ($entries.Count -eq 0) {
        Write-INFO "No startup entries found - startup is clean!"
        Pause-Menu; return
    }

    $i = 1
    foreach ($e in $entries) {
        $short = if ($e.Value.Length -gt 50) { $e.Value.Substring(0,47) + "..." } else { $e.Value }
        Write-Host ("  [{0,2}] {1,-28}  {2}" -f $i, $e.Name, $short) -ForegroundColor White
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Enter a number to REMOVE it from startup                       |" -ForegroundColor Yellow
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0") { return }
    if ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $entries.Count) {
        $entry = $entries[[int]$choice - 1]
        Write-ActionLog -type "Startup" -target "$($entry.Path)|$($entry.Name)" -oldValue $entry.Value -desc $entry.Name
        Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        Write-OK "Removed from startup: $($entry.Name)"
        Start-Sleep 1
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
        $isFile = (Test-Path $item.Path) -and (-not (Get-Item $item.Path -ErrorAction SilentlyContinue).PSIsContainer)
        if ($isFile) { Remove-Item $item.Path -Force -ErrorAction SilentlyContinue }
        else { Remove-Item "$($item.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue }
        Write-OK "Cleaned: $($item.Label)"
    }

    Write-Host ""
    if ($choice -eq "A" -or $choice -eq "a") {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        foreach ($item in $items) { if (Test-Path $item.Path) { Clean-Item $item } }
        Start-Process explorer
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $items.Count) {
        $item = $items[[int]$choice - 1]
        if (Test-Path $item.Path) { Clean-Item $item } else { Write-SKIP "Not found: $($item.Label)" }
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
        Write-Host "  |                Press Q + Enter to exit                         |" -ForegroundColor DarkGray
        Write-Host "  +================================================================+" -ForegroundColor Cyan
        Write-Host ""

        $os       = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu      = [math]::Round((Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average,0)
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
    Draw-Header "POWER PLAN - Set Windows performance mode"
    Write-Host "  Current active plan:" -ForegroundColor DarkGray
    $current = powercfg /getactivescheme
    Write-Host "  $current" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  All available plans:" -ForegroundColor DarkGray
    powercfg /list | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [1] Activate Ultimate Performance (best for gaming/work)       |" -ForegroundColor Green
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "1") {
        Write-Host ""
        $existing = powercfg /list | Select-String "Ultimate"
        if (-not $existing) {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
            Write-OK "Ultimate Performance plan created"
        }
        $guid = ((powercfg /list | Select-String "Ultimate") -replace ".*GUID: ([^\s]+).*", '$1').Trim()
        if ($guid) {
            powercfg /setactive $guid
            Write-OK "Ultimate Performance activated"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 8 - SMB1
# ============================================================
function Menu-SMB {
    Draw-Header "SMB1 SECURITY - Disable the SMB1 vulnerability"
    Write-Host "  SMB1 is an old protocol with serious known vulnerabilities." -ForegroundColor DarkGray
    Write-Host "  It was used by WannaCry ransomware. You do not need it." -ForegroundColor DarkGray
    Write-Host ""

    $smb    = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    $status = if ($smb) { $smb.State } else { "Unknown" }
    $color  = if ($status -eq "Disabled") { "Green" } else { "Red" }
    Write-Host ("  SMB1 Status: [ {0} ]" -f $status) -ForegroundColor $color
    Write-Host ""

    if ($status -ne "Disabled") {
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | SMB1 is ENABLED - this is a security risk!                     |" -ForegroundColor Red
        Write-Host "  | [1] Disable SMB1 NOW - strongly recommended                    |" -ForegroundColor Green
        Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Choose: " -ForegroundColor White -NoNewline
        $choice = Read-Host
        if ($choice -eq "1") {
            Write-Host ""
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
            Write-OK "SMB1 disabled - restart required to apply"
        }
    } else {
        Write-Host "  You are safe. SMB1 is already disabled." -ForegroundColor Green
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
            if ($rel.Wear -ne $null) {
                $wColor = if ($rel.Wear -gt 80) { "Red" } elseif ($rel.Wear -gt 50) { "Yellow" } else { "Green" }
                Write-Host ("    Wear (life used): {0}%" -f $rel.Wear) -ForegroundColor $wColor
            }
            if ($rel.PowerOnHours -ne $null) {
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
        $temps = Get-WmiObject -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($t in $temps) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            $color = if ($celsius -gt 85) { "Red" } elseif ($celsius -gt 70) { "Yellow" } else { "Green" }
            Write-Host ("  Thermal Zone: {0} C" -f $celsius) -ForegroundColor $color
            $tempFound = $true
        }
    } catch { }
    if (-not $tempFound) {
        Write-INFO "Built-in sensors did not report temps (common on laptops)"
    }
    $cpuLoad = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-Host ("  Current CPU load: {0}%" -f $cpuLoad) -ForegroundColor White
    Write-Host ""

    Write-Host "  --- DRIVER UPDATE CHECK ---" -ForegroundColor Cyan
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartType -eq "Disabled") {
        Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
        Write-INFO "Windows Update service temporarily enabled to check for drivers"
    }
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    try {
        UsoClient StartScan 2>$null
        Write-OK "Driver scan triggered via Windows Update"
        Write-Host "  Check: Settings -> Windows Update -> Advanced options -> Optional updates" -ForegroundColor White
    } catch {
        Write-INFO "Check manually in Settings -> Windows Update"
    }
    Write-Host ""

    Write-Host "  --- FONT CHECK ---" -ForegroundColor Cyan
    $winInstallDate = (Get-WmiObject Win32_OperatingSystem).InstallDate
    $winInstallDate = [Management.ManagementDateTimeConverter]::ToDateTime($winInstallDate)
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

    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    Write-Host ("  CPU       : {0}" -f $cpu.Name) -ForegroundColor White

    $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Basic|Remote" }
    foreach ($g in $gpus) {
        Write-Host ("  GPU       : {0}" -f $g.Name) -ForegroundColor White
    }

    $wifi = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.Name -match "Wireless|Wi-Fi|WiFi" -and $_.Manufacturer -notmatch "Microsoft" } | Select-Object -First 1
    if ($wifi) { Write-Host ("  Wi-Fi     : {0}" -f $wifi.Name) -ForegroundColor White }

    $audio = Get-WmiObject Win32_SoundDevice | Select-Object -First 1
    if ($audio) { Write-Host ("  Audio     : {0}" -f $audio.Name) -ForegroundColor White }

    $sys = Get-WmiObject Win32_ComputerSystem
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
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-OK "Limit removed"
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
        Remove-Item $Global:LogPath -Force -ErrorAction SilentlyContinue
        "Timestamp,Type,Target,OldValue,Desc" | Out-File -FilePath $Global:LogPath -Encoding UTF8
        Write-OK "Log cleared"
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
                        Set-Service -Name $e.Target -StartupType $e.OldValue -ErrorAction SilentlyContinue
                        if ($e.OldValue -ne "Disabled") { Start-Service -Name $e.Target -ErrorAction SilentlyContinue }
                        Write-OK "Service $($e.Target) restored: $($e.OldValue)"
                    }
                } catch { Write-INFO "Could not undo: $($e.Target)" }
            }
            "Task" {
                try {
                    $parts2 = $e.Target -split "\|"
                    $taskPath = $parts2[0]; $taskName = $parts2[1]
                    if ($e.OldValue -ne "Disabled") {
                        Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
                        Write-OK "Task $taskName re-enabled"
                    }
                } catch { Write-INFO "Could not undo task: $($e.Target)" }
            }
            "Registry" {
                try {
                    $parts2 = $e.Target -split "\|"
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") {
                        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                        Write-OK "Registry value removed: $regName"
                    } else {
                        Set-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -ErrorAction SilentlyContinue
                        Write-OK "Registry $regName restored: $($e.OldValue)"
                    }
                } catch { Write-INFO "Could not undo registry: $($e.Target)" }
            }
            "Startup" { Write-INFO "Startup $($e.Target) - add manually if needed" }
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
        $pkg = Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue
        if ($pkg) {
            Write-ActionLog -type "AppxPackage" -target $appName -oldValue "installed" -desc $appName
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            Write-OK "Removed: $appName"
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
    Draw-Header "BROWSER CACHE - Brave, Chrome, Edge"
    Write-Host "  Will close browsers and clear cache. Passwords/bookmarks are safe." -ForegroundColor DarkGray
    Write-Host ""

    $browsers = @(
        @{Name="Brave";  Process="brave";  Path="$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"},
        @{Name="Chrome"; Process="chrome"; Path="$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache"},
        @{Name="Edge";   Process="msedge"; Path="$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cache"}
    )

    $i = 1
    foreach ($b in $browsers) {
        $size = Get-FolderSize $b.Path
        $sizeStr = if ($size -gt 0) { "$size GB" } else { "not found or empty" }
        Write-Host ("  [{0}] {1,-10} {2}" -f $i, $b.Name, $sizeStr) -ForegroundColor White
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]   Clean ALL browsers                                      |" -ForegroundColor Cyan
    Write-Host "  | [1-3] Clean specific browser                                   |" -ForegroundColor White
    Write-Host "  | [0]   Back to main menu                                        |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    $selected = @()
    if ($choice -eq "A" -or $choice -eq "a") { $selected = $browsers }
    elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $browsers.Count) { $selected = @($browsers[[int]$choice - 1]) }

    Write-Host ""
    foreach ($b in $selected) {
        Stop-Process -Name $b.Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        if (Test-Path $b.Path) {
            Remove-Item "$($b.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Cache $($b.Name) cleared"
        } else {
            Write-SKIP "$($b.Name) not found"
        }
    }
    Pause-Menu
}

# ============================================================
# MENU 15 - COSMETICS
# ============================================================
function Menu-Cosmetics {
    Draw-Header "WINDOWS COSMETICS"

    $classicMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
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
    if ($Script:IsWin11) {
        Write-Host "  | [1] Toggle classic context menu                                |" -ForegroundColor White
    }
    Write-Host "  | [2] Toggle file extensions                                     |" -ForegroundColor White
    Write-Host "  | [3] Toggle hidden files                                        |" -ForegroundColor White
    Write-Host "  | [A] Enable ALL available                                        |" -ForegroundColor Cyan
    Write-Host "  | [0] Back to main menu                                          |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Toggle-ClassicMenu {
        if ($Script:IsWin11) {
            if ($classicEnabled) {
                Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
                Write-OK "Classic menu disabled"
            } else {
                New-Item -Path $classicMenuPath -Force | Out-Null
                Set-ItemProperty -Path $classicMenuPath -Name "(default)" -Value "" -ErrorAction SilentlyContinue
                Write-OK "Classic context menu enabled"
            }
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Start-Process explorer
        } else {
            Write-SKIP "Only available on Windows 11"
        }
    }

    function Toggle-FileExt {
        $new = if ($hideExt -eq 0) { 1 } else { 0 }
        Set-RegLogged $advPath "HideFileExt" $new "DWord" "File extensions"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer
        if ($new -eq 0) { Write-OK "File extensions now visible" } else { Write-OK "File extensions hidden" }
    }

    function Toggle-HiddenFiles {
        $new = if ($hideHidden -eq 1) { 2 } else { 1 }
        Set-RegLogged $advPath "Hidden" $new "DWord" "Hidden files"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer
        if ($new -eq 1) { Write-OK "Hidden files now visible" } else { Write-OK "Hidden files are hidden again" }
    }

    Write-Host ""
    switch ($choice) {
        "1" { Toggle-ClassicMenu }
        "2" { Toggle-FileExt }
        "3" { Toggle-HiddenFiles }
        "A" { if ($Script:IsWin11 -and -not $classicEnabled) { Toggle-ClassicMenu }; if ($hideExt -ne 0) { Toggle-FileExt }; if ($hideHidden -ne 1) { Toggle-HiddenFiles } }
        "a" { if ($Script:IsWin11 -and -not $classicEnabled) { Toggle-ClassicMenu }; if ($hideExt -ne 0) { Toggle-FileExt }; if ($hideHidden -ne 1) { Toggle-HiddenFiles } }
    }
    Pause-Menu
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
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Exit                     |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  TIP: Start with [11] restore point, then [1] Services -> [A]" -ForegroundColor DarkCyan
        Write-Host "  VERSION: $Script:WinVerName" -ForegroundColor DarkCyan
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
            "0"  { Clear-Host; exit }
        }
    }
}

Main-Menu
