# WinTools - Windows Optimization Suite
# Run as Administrator

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ERROR: Run as Administrator!" -ForegroundColor Red
    Start-Sleep 3; exit
}

function Write-OK($msg)   { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [-] $msg" -ForegroundColor DarkGray }
function Write-INFO($msg) { Write-Host "  [*] $msg" -ForegroundColor Yellow }

function Pause-Menu {
    Write-Host ""
    Write-Host "  [ Press any key to go back ]" -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Disable-Svc($name, $label) {
    $found = Get-Service | Where-Object { $_.Name -like "$name*" } | Select-Object -First 1
    if ($found -and $found.StartType -ne "Disabled") {
        Stop-Service -Name $found.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $found.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "Disabled: $label"
    } else {
        Write-SKIP "Already disabled: $label"
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
    Write-Host "  Select a group to disable. Press A to disable all RECOMMENDED." -ForegroundColor DarkGray
    Write-Host ""

    $groups = @(
        @{ Name="Telemetry and data collection";  Tag="REC"; Svcs=@(
            @{N="DiagTrack";L="Connected User Experiences (telemetry)"},
            @{N="dmwappushservice";L="WAP Push telemetry"},
            @{N="DoSvc";L="Delivery Optimization P2P"},
            @{N="DusmSvc";L="Data Usage tracker"}
        )},
        @{ Name="Xbox and gaming bloat";           Tag="REC"; Svcs=@(
            @{N="XblAuthManager";L="Xbox Live Auth Manager"},
            @{N="XblGameSave";L="Xbox Live Game Save"},
            @{N="XboxGipSvc";L="Xbox Accessory Management"},
            @{N="XboxNetApiSvc";L="Xbox Network"}
        )},
        @{ Name="Remote Desktop and management";   Tag="REC"; Svcs=@(
            @{N="TermService";L="Remote Desktop"},
            @{N="UmRdpService";L="RDP Port Redirector"},
            @{N="SessionEnv";L="Remote Desktop Config"},
            @{N="WinRM";L="Windows Remote Management"},
            @{N="RemoteRegistry";L="Remote Registry"}
        )},
        @{ Name="Hyper-V (virtual machines)";      Tag="REC"; Svcs=@(
            @{N="vmicguestinterface";L="Hyper-V Guest Interface"},
            @{N="vmicheartbeat";L="Hyper-V Heartbeat"},
            @{N="vmickvpexchange";L="Hyper-V Data Exchange"},
            @{N="vmicrdv";L="Hyper-V Remote Desktop"},
            @{N="vmicshutdown";L="Hyper-V Shutdown"},
            @{N="vmictimesync";L="Hyper-V Time Sync"},
            @{N="vmicvmsession";L="Hyper-V PowerShell Direct"},
            @{N="vmicvss";L="Hyper-V VSS"},
            @{N="HvHost";L="Hyper-V Host"}
        )},
        @{ Name="Printing (disable if no printer)"; Tag="OPT"; Svcs=@(
            @{N="Spooler";L="Print Spooler"},
            @{N="PrintNotify";L="Printer Notifications"},
            @{N="PrintWorkflowUserSvc";L="Print Workflow"}
        )},
        @{ Name="Unused network features";         Tag="REC"; Svcs=@(
            @{N="LanmanServer";L="Server file sharing"},
            @{N="lltdsvc";L="Link-Layer Topology"},
            @{N="lmhosts";L="NetBIOS over TCP/IP"},
            @{N="FDResPub";L="Function Discovery Pub"},
            @{N="fdPHost";L="Function Discovery Host"},
            @{N="SSDPSRV";L="SSDP Discovery"},
            @{N="upnphost";L="UPnP Device Host"},
            @{N="p2pimsvc";L="Peer Name Resolution"},
            @{N="p2psvc";L="Peer Networking"},
            @{N="PNRPAutoReg";L="PNRP Machine Name"},
            @{N="PNRPsvc";L="PNRP Protocol"}
        )},
        @{ Name="Diagnostics and error reporting";  Tag="REC"; Svcs=@(
            @{N="DPS";L="Diagnostic Policy Service"},
            @{N="WdiServiceHost";L="Diagnostic Service Host"},
            @{N="WdiSystemHost";L="Diagnostic System Host"},
            @{N="WerSvc";L="Windows Error Reporting"},
            @{N="wercplsupport";L="Error Reporting UI"},
            @{N="PcaSvc";L="Program Compatibility"},
            @{N="diagnosticshub.standardcollector.service";L="Diagnostics Hub"}
        )},
        @{ Name="Misc unused services";            Tag="REC"; Svcs=@(
            @{N="TrkWks";L="Distributed Link Tracking"},
            @{N="FontCache";L="Font Cache"},
            @{N="ShellHWDetection";L="Shell HW Detection USB autorun"},
            @{N="MapsBroker";L="Downloaded Maps"},
            @{N="PhoneSvc";L="Phone Service"},
            @{N="WFDSConMgrSvc";L="Wi-Fi Direct"},
            @{N="MessagingService";L="Messaging Service SMS"},
            @{N="icssvc";L="Mobile Hotspot"},
            @{N="SmsRouter";L="SMS Router"},
            @{N="WiaRpc";L="Camera Scanner Events"},
            @{N="stisvc";L="Windows Image Acquisition"},
            @{N="Netlogon";L="Netlogon domain login"},
            @{N="CDPSvc";L="Connected Devices Platform"},
            @{N="BcastDVRUserService";L="Game DVR Broadcast"},
            @{N="CaptureService";L="Screen Capture Service"},
            @{N="NaturalAuthentication";L="Face Login"},
            @{N="GraphicsPerfSvc";L="Graphics Perf Monitor"},
            @{N="WpnService";L="Push Notifications"},
            @{N="RetailDemo";L="Retail Demo"},
            @{N="SysMain";L="SysMain Superfetch"},
            @{N="WSearch";L="Windows Search indexing"}
        )}
    )

    $i = 1
    foreach ($g in $groups) {
        $color = if ($g.Tag -eq "REC") { "Green" } else { "Yellow" }
        $count = $g.Svcs.Count
        Write-Host ("  [{0}] [{1}] {2,-45} ({3} services)" -f $i, $g.Tag, $g.Name, $count) -ForegroundColor $color
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]   Disable ALL recommended groups at once                   |" -ForegroundColor Cyan
    Write-Host "  | [1-8] Disable a specific group                                 |" -ForegroundColor White
    Write-Host "  | [0]   Back to main menu                                        |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0") { return }
    $selected = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $selected = $groups | Where-Object { $_.Tag -eq "REC" }
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $groups.Count) {
        $selected = @($groups[[int]$choice - 1])
    }
    Write-Host ""
    foreach ($g in $selected) {
        Write-Host "  --- $($g.Name) ---" -ForegroundColor Cyan
        foreach ($svc in $g.Svcs) { Disable-Svc $svc.N $svc.L }
    }
    Pause-Menu
}

# ============================================================
# MENU 2 - REGISTRY TWEAKS
# ============================================================
function Menu-Registry {
    Draw-Header "REGISTRY TWEAKS - Performance and privacy settings"
    Write-Host "  Each tweak improves performance or removes tracking." -ForegroundColor DarkGray
    Write-Host "  Press A to apply all RECOMMENDED tweaks at once." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  [REC] [ 1] GPU Scheduling on            Faster GPU, less frame latency" -ForegroundColor Green
    Write-Host "  [REC] [ 2] Nagle Algorithm off           Lower network latency for games" -ForegroundColor Green
    Write-Host "  [REC] [ 3] Power Throttling off          No CPU throttling in background" -ForegroundColor Green
    Write-Host "  [REC] [ 4] Game DVR off                  Removes Xbox recording overhead" -ForegroundColor Green
    Write-Host "  [REC] [ 5] Visual Effects best perf      Disables animations, faster UI" -ForegroundColor Green
    Write-Host "  [REC] [ 6] Fast Startup off              Real shutdown, no cache corruption" -ForegroundColor Green
    Write-Host "  [REC] [ 7] Advertising ID off             Disables ad tracking ID" -ForegroundColor Green
    Write-Host "  [REC] [ 8] Telemetry off                 Stops data collection to Microsoft" -ForegroundColor Green
    Write-Host "  [OPT] [ 9] OneDrive off                  Disables OneDrive sync policy" -ForegroundColor Yellow
    Write-Host "  [REC] [10] Spotlight lockscreen off      No Microsoft ads on lock screen" -ForegroundColor Green
    Write-Host "  [REC] [11] Faster shutdown 2 sec          Services killed after 2s on shutdown" -ForegroundColor Green
    Write-Host "  [REC] [12] NTFS tweaks                    Disable last access time, 8.3 names" -ForegroundColor Green
    Write-Host "  [REC] [13] Autorun off                    No autorun from USB drives" -ForegroundColor Green
    Write-Host "  [REC] [14] Delivery Optimization off      Stop sharing your bandwidth" -ForegroundColor Green
    Write-Host "  [REC] [15] Typing personalization off     Stop keystroke collection" -ForegroundColor Green
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Apply ALL recommended tweaks at once                    |" -ForegroundColor Cyan
    Write-Host "  | [1-15] Apply a specific tweak                                  |" -ForegroundColor White
    Write-Host "  | [0]    Back to main menu                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Apply-Tweak($num) {
        switch ($num) {
            "1" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Hardware GPU Scheduling enabled"
            }
            "2" {
                $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
                foreach ($iface in $ifaces) {
                    $props = Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue
                    if ($props.DhcpIPAddress -like "192.168.*") {
                        Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord
                        Set-ItemProperty -Path $iface.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord
                        Write-OK "Nagle disabled on $($props.DhcpIPAddress)"
                    }
                }
            }
            "3" {
                $pt = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $pt)) { New-Item -Path $pt -Force | Out-Null }
                Set-ItemProperty -Path $pt -Name "PowerThrottlingOff" -Value 1 -Type DWord
                Write-OK "Power Throttling disabled"
            }
            "4" {
                $gdvr = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path $gdvr)) { New-Item -Path $gdvr -Force | Out-Null }
                Set-ItemProperty -Path $gdvr -Name "GameDVR_Enabled" -Value 0 -Type DWord
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Game DVR disabled"
            }
            "5" {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -ErrorAction SilentlyContinue
                Write-OK "Visual Effects set to Best Performance"
            }
            "6" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord
                Write-OK "Fast Startup disabled"
            }
            "7" {
                $ad = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
                if (-not (Test-Path $ad)) { New-Item -Path $ad -Force | Out-Null }
                Set-ItemProperty -Path $ad -Name "Enabled" -Value 0 -Type DWord
                Write-OK "Advertising ID disabled"
            }
            "8" {
                $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
                Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value 0 -Type DWord
                Set-ItemProperty -Path $dc -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
                Write-OK "Telemetry disabled"
            }
            "9" {
                $od = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
                if (-not (Test-Path $od)) { New-Item -Path $od -Force | Out-Null }
                Set-ItemProperty -Path $od -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
                Write-OK "OneDrive disabled"
            }
            "10" {
                $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Set-ItemProperty -Path $cdm -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "ContentDeliveryAllowed" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Spotlight and ads disabled"
            }
            "11" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
                Write-OK "Shutdown timeout set to 2 seconds"
            }
            "12" {
                fsutil behavior set disablelastaccess 1 | Out-Null
                fsutil behavior set disable8dot3 1 | Out-Null
                Write-OK "NTFS last access and 8.3 names disabled"
            }
            "13" {
                $ar = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                if (-not (Test-Path $ar)) { New-Item -Path $ar -Force | Out-Null }
                Set-ItemProperty -Path $ar -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord
                Write-OK "Autorun disabled for all drives"
            }
            "14" {
                $do = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
                if (-not (Test-Path $do)) { New-Item -Path $do -Force | Out-Null }
                Set-ItemProperty -Path $do -Name "DODownloadMode" -Value 0 -Type DWord
                Write-OK "Delivery Optimization disabled"
            }
            "15" {
                $ink = "HKCU:\Software\Microsoft\InputPersonalization"
                if (-not (Test-Path $ink)) { New-Item -Path $ink -Force | Out-Null }
                Set-ItemProperty -Path $ink -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord
                Set-ItemProperty -Path $ink -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord
                Write-OK "Typing personalization disabled"
            }
        }
    }

    Write-Host ""
    if ($choice -eq "A" -or $choice -eq "a") {
        foreach ($n in @("1","2","3","4","5","6","7","8","10","11","12","13","14","15")) { Apply-Tweak $n }
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
        @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"; Desc="Sends app data to MS"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater";                Desc="Telemetry data updater"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask";                    Desc="Startup app tracking"},
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClient";                          Desc="Feedback telemetry"},
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClientOnScenarioDownload";        Desc="Feedback on scenario"},
        @{Path="\Microsoft\Windows\Windows Error Reporting\";Name="QueueReporting";                    Desc="Error reports to MS"},
        @{Path="\Microsoft\Windows\NetTrace\";               Name="GatherNetworkInfo";                  Desc="Network data collection"},
        @{Path="\Microsoft\Windows\SettingSync\";            Name="BackgroundUploadTask";               Desc="Sync settings to cloud"},
        @{Path="\Microsoft\Windows\SettingSync\";            Name="NetworkStateChangeTask";             Desc="Network sync trigger"},
        @{Path="\Microsoft\Windows\DiskDiagnostic\";         Name="Microsoft-Windows-DiskDiagnosticDataCollector"; Desc="Disk data to MS"},
        @{Path="\Microsoft\Windows\UNP\";                    Name="RunUpdateNotificationMgr";           Desc="Update nag notifications"}
    )

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
    Write-Host "  | [1-11] Disable a specific task                                 |" -ForegroundColor White
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
    Write-Host "  | [1-13] Clean a specific item                                   |" -ForegroundColor White
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
            Write-INFO "Detailed counters not available for this disk (common for laptop NVMe drives)"
        }
        Write-Host ""
    }

    Write-Host "  --- TEMPERATURE (built-in sensors) ---" -ForegroundColor Cyan
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
        Write-INFO "Built-in sensors did not report CPU/GPU temps (common on laptops)"
        Write-Host "  Use HWiNFO64 for accurate readings under load if you have it installed." -ForegroundColor DarkGray
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

    Write-Host "  --- FONT CHECK (installed after Windows setup) ---" -ForegroundColor Cyan
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
        Write-OK "No extra fonts found - standard Windows set, all good"
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
    Write-Host ""

    $links = @()

    function Build-SearchUrl($query) {
        return "https://www.google.com/search?q=" + [uri]::EscapeDataString($query)
    }

    if ($cpu.Name -match "Intel") {
        $links += @{Label="Intel Driver and Support Assistant (CPU, chipset, Wi-Fi, BT)"; Url="https://www.intel.com/content/www/us/en/support/detect.html"}
    } elseif ($cpu.Name -match "AMD") {
        $cpuClean = ($cpu.Name -replace "AMD","" -replace "Processor","" -replace "with Radeon.*","" -replace "\s+"," ").Trim()
        $links += @{Label="AMD - latest chipset driver for $cpuClean"; Url=(Build-SearchUrl "AMD chipset driver $cpuClean latest download")}
    }

    foreach ($g in $gpus) {
        if ($g.Name -match "NVIDIA") {
            $gpuClean = ($g.Name -replace "NVIDIA","" -replace "Laptop GPU","" -replace "\s+"," ").Trim()
            $links += @{Label="NVIDIA - latest driver for your GPU: $gpuClean"; Url=(Build-SearchUrl "nvidia driver $gpuClean laptop latest download")}
            $ge = "C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
            if (Test-Path $ge) {
                Write-INFO "GeForce Experience is already installed - it auto-detects your exact card and updates automatically"
            }
        } elseif ($g.Name -match "Intel") {
            $links += @{Label="Intel Graphics - latest drivers (via Intel DSA above)"; Url="https://www.intel.com/content/www/us/en/download-center/home.html"}
        } elseif ($g.Name -match "AMD|Radeon") {
            $gpuClean = ($g.Name -replace "AMD","" -replace "Radeon","" -replace "Graphics","" -replace "\s+"," ").Trim()
            $links += @{Label="AMD - latest driver for your GPU: Radeon $gpuClean"; Url=(Build-SearchUrl "amd radeon driver $gpuClean laptop latest download")}
        }
    }

    if ($sys.Manufacturer -match "HUAWEI") {
        $links += @{Label="HUAWEI - drivers for your laptop model"; Url="https://consumer.huawei.com/en/support/laptops/"}
        Write-Host ""
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | WARNING: this is a HUAWEI laptop                               |" -ForegroundColor Red
        Write-Host "  |                                                                  |" -ForegroundColor Red
        Write-Host "  | HUAWEI PC Manager (and HMS Core) is known to run background    |" -ForegroundColor Yellow
        Write-Host "  | scans, phone-home checks, and its own update checker. This     |" -ForegroundColor Yellow
        Write-Host "  | can cause unstable FPS in games, especially while it runs      |" -ForegroundColor Yellow
        Write-Host "  | in the background.                                              |" -ForegroundColor Yellow
        Write-Host "  |                                                                  |" -ForegroundColor Red
        Write-Host "  | Recommendation: download drivers manually from the site,       |" -ForegroundColor Green
        Write-Host "  | install only what you need (Wi-Fi, audio, graphics), and       |" -ForegroundColor Green
        Write-Host "  | avoid keeping PC Manager / HMS Core running all the time.      |" -ForegroundColor Green
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
    } elseif ($sys.Manufacturer -match "ASUS") {
        $links += @{Label="ASUS - drivers for your laptop model"; Url="https://www.asus.com/support/"}
    } elseif ($sys.Manufacturer -match "Lenovo") {
        $links += @{Label="Lenovo - drivers for your laptop model"; Url="https://support.lenovo.com/"}
    } elseif ($sys.Manufacturer -match "HP") {
        $links += @{Label="HP - drivers for your laptop model"; Url="https://support.hp.com/"}
    } elseif ($sys.Manufacturer -match "Dell") {
        $links += @{Label="Dell - drivers for your laptop model"; Url="https://www.dell.com/support/home/"}
    } elseif ($sys.Manufacturer -match "MSI") {
        $links += @{Label="MSI - drivers for your laptop model"; Url="https://www.msi.com/support/"}
    } elseif ($sys.Manufacturer -match "Acer") {
        $links += @{Label="Acer - drivers for your laptop model"; Url="https://www.acer.com/support"}
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
        foreach ($l in $links) {
            Start-Process $l.Url
            Write-OK "Opened: $($l.Label)"
        }
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $links.Count) {
        $l = $links[[int]$choice - 1]
        Start-Process $l.Url
        Write-OK "Opened: $($l.Label)"
    }

    Write-Host ""
    Write-INFO "You can also use already-installed tools manually:"
    $localTools = @(
        @{Name="Intel Driver and Support Assistant"; Path="C:\Program Files (x86)\Intel\Driver and Support Assistant\Application\DSATray.exe"},
        @{Name="NVIDIA GeForce Experience"; Path="C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"}
    )
    foreach ($t in $localTools) {
        if (Test-Path $t.Path) {
            Write-Host ("  Found: {0} -> {1}" -f $t.Name, $t.Path) -ForegroundColor White
        }
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
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Exit                     |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  TIP: Start with [1] Services -> [A], then [2] Registry -> [A]" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Choose: " -ForegroundColor White -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1" { Menu-Services }
            "2" { Menu-Registry }
            "3" { Menu-Tasks }
            "4" { Menu-Startup }
            "5" { Menu-DiskCleanup }
            "6" { Menu-Monitor }
            "7" { Menu-PowerPlan }
            "8" { Menu-SMB }
            "9" { Menu-Health }
            "10" { Menu-DriverUpdate }
            "0" { Clear-Host; exit }
        }
    }
}

Main-Menu
