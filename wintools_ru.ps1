# WinTools - Оптимизация Windows (Русская версия)
# Запускать от имени Администратора
# Поддержка: Windows 10 Home/Pro, Windows 11 Home/Pro/LTSC/InsiderPreview
# Версия скрипта определяется автоматически или через install.ps1

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ОШИБКА: Запустите от имени Администратора!" -ForegroundColor Red
    Start-Sleep 3; exit
}

# ============================================================
# ОПРЕДЕЛЕНИЕ ВЕРСИИ WINDOWS
# ============================================================
function Get-WindowsVersion {
    $os = Get-WmiObject Win32_OperatingSystem
    $caption = $os.Caption
    $build = $os.BuildNumber

    if ($caption -match "Windows 10") {
        if ($caption -match "Pro")        { return "win10pro" }
        elseif ($caption -match "Домашняя|Home") { return "win10home" }
        else                                { return "win10pro" }
    }
    elseif ($caption -match "Windows 11") {
        if ($caption -match "LTSC|Enterprise") { return "win11ltsc" }
        elseif ($caption -match "Insider")      { return "win11insider" }
        elseif ($caption -match "Pro")          { return "win11pro" }
        elseif ($caption -match "Домашняя|Home") { return "win11home" }
        else                                    { return "win11pro" }
    }
    return "unknown"
}

$Script:WinVer = Get-WindowsVersion
$Script:WinVerName = switch ($Script:WinVer) {
    "win10home"    { "Windows 10 Домашняя" }
    "win10pro"     { "Windows 10 Pro" }
    "win11home"    { "Windows 11 Домашняя" }
    "win11pro"     { "Windows 11 Pro" }
    "win11ltsc"    { "Windows 11 Enterprise LTSC" }
    "win11insider" { "Windows 11 InsiderPreview Pro" }
    default        { "Неизвестная версия" }
}

$Script:IsWin10 = $Script:WinVer -match "win10"
$Script:IsWin11 = $Script:WinVer -match "win11"
$Script:IsLTSC  = $Script:WinVer -eq "win11ltsc"
$Script:IsHome  = $Script:WinVer -match "home"

# LTSC не имеет Store-приложений и Cortana
# Home не имеет Hyper-V, Remote Desktop host, Group Policy
# Win10 имеет больше bloatware чем Win11
# Win11 InsiderPreview имеет Insider build задачи

function Write-OK($msg)   { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [-] $msg" -ForegroundColor DarkGray }
function Write-INFO($msg) { Write-Host "  [*] $msg" -ForegroundColor Yellow }

# ============================================================
# ЖУРНАЛ ИЗМЕНЕНИЙ (для отмены действий)
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
    Write-Host "  [ Нажмите любую клавишу для возврата ]" -ForegroundColor DarkGray
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
        Write-OK "Отключено: $label"
    } else {
        Write-SKIP "Уже отключено или не найдено: $label"
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
    return "  Диск C: $free ГБ свободно   ОЗУ: $ramUsed/$ramTotal ГБ   ЦП: $cpu%   Процессов: $proc"
}

function Draw-Header($title) {
    Clear-Host
    Write-Host ""
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host "  |           WINTOOLS - Оптимизация Windows                       |" -ForegroundColor Cyan
    Write-Host "  |           $Script:WinVerName $((' ' * (50 - $Script:WinVerName.Length)))|" -ForegroundColor DarkCyan
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
# МЕНЮ 1 - СЛУЖБЫ
# ============================================================
function Menu-Services {
    Draw-Header "СЛУЖБЫ - выбери что отключить"

    # Базовый список для всех версий
    $svcList = @(
        @{N="DiagTrack";              Desc="Телеметрия - собирает данные об использовании ПК и шлёт в Microsoft"},
        @{N="dmwappushservice";       Desc="Приём push-сообщений для телеметрии"},
        @{N="DoSvc";                  Desc="Раздаёт обновления другим компьютерам через твой интернет (P2P)"},
        @{N="DusmSvc";                Desc="Считает сколько трафика ты израсходовал"},
        @{N="XblAuthManager";         Desc="Авторизация в Xbox Live"},
        @{N="XblGameSave";            Desc="Облачные сохранения игр Xbox"},
        @{N="XboxGipSvc";             Desc="Управление аксессуарами Xbox (геймпады)"},
        @{N="XboxNetApiSvc";          Desc="Сетевые функции Xbox"},
        @{N="TermService";            Desc="Позволяет подключаться к этому ПК удалённо (RDP)"},
        @{N="UmRdpService";           Desc="Часть удалённого рабочего стола"},
        @{N="SessionEnv";             Desc="Настройка сервера удалённых рабочих столов"},
        @{N="WinRM";                  Desc="Удалённое управление Windows через PowerShell"},
        @{N="RemoteRegistry";         Desc="Позволяет менять твой реестр удалённо"},
        @{N="vmicguestinterface";     Desc="Часть Hyper-V - интерфейс гостевой ОС"},
        @{N="vmicheartbeat";          Desc="Часть Hyper-V - проверка что виртуалка жива"},
        @{N="vmickvpexchange";        Desc="Часть Hyper-V - обмен данными с виртуалкой"},
        @{N="vmicrdv";                Desc="Часть Hyper-V - удалённый рабочий стол в виртуалке"},
        @{N="vmicshutdown";           Desc="Часть Hyper-V - выключение виртуалки"},
        @{N="vmictimesync";           Desc="Часть Hyper-V - синхронизация времени"},
        @{N="vmicvmsession";          Desc="Часть Hyper-V - PowerShell напрямую в виртуалку"},
        @{N="vmicvss";                Desc="Часть Hyper-V - теневые копии"},
        @{N="HvHost";                 Desc="Хост-служба Hyper-V"},
        @{N="Spooler";                Desc="Диспетчер печати - без него не работает принтер"},
        @{N="PrintNotify";            Desc="Уведомления о принтере"},
        @{N="PrintWorkflowUserSvc";   Desc="Дополнительные функции печати из Store"},
        @{N="LanmanServer";           Desc="Общий доступ к папкам/файлам по локальной сети"},
        @{N="lltdsvc";                Desc="Карта устройств в локальной сети"},
        @{N="lmhosts";                Desc="Старый протокол NetBIOS"},
        @{N="FDResPub";               Desc="Публикует этот ПК для обнаружения в сети"},
        @{N="fdPHost";                Desc="Поиск устройств в локальной сети"},
        @{N="SSDPSRV";                Desc="Обнаружение UPnP устройств"},
        @{N="upnphost";               Desc="Работа с UPnP устройствами"},
        @{N="p2pimsvc";               Desc="Одноранговая сеть (устаревшее)"},
        @{N="p2psvc";                 Desc="Группировка сетевых участников (устаревшее)"},
        @{N="PNRPAutoReg";            Desc="Публикация имени в одноранговой сети"},
        @{N="PNRPsvc";                Desc="Протокол разрешения имён"},
        @{N="DPS";                    Desc="Диагностика проблем и их устранение"},
        @{N="WdiServiceHost";         Desc="Узел диагностических инструментов"},
        @{N="WdiSystemHost";          Desc="Системный узел диагностики"},
        @{N="WerSvc";                 Desc="Отправка отчётов о сбоях в Microsoft"},
        @{N="wercplsupport";          Desc="Интерфейс отчётов об ошибках"},
        @{N="PcaSvc";                 Desc="Проверка совместимости старых программ"},
        @{N="diagnosticshub.standardcollector.service"; Desc="Сборщик диагностических данных"},
        @{N="TrkWks";                 Desc="Следит за ярлыками файлов по сети"},
        @{N="FontCache";              Desc="Кэширует шрифты для быстрой отрисовки"},
        @{N="ShellHWDetection";       Desc="Окно 'Что делать с диском' при вставке флешки"},
        @{N="MapsBroker";             Desc="Скачивание офлайн-карт"},
        @{N="PhoneSvc";               Desc="Связь Windows с телефоном"},
        @{N="WFDSConMgrSvc";          Desc="Wi-Fi Direct - передача файлов по Wi-Fi"},
        @{N="MessagingService";       Desc="Отправка SMS через это устройство"},
        @{N="icssvc";                 Desc="Раздача интернета как точки доступа"},
        @{N="SmsRouter";              Desc="Маршрутизация SMS-сообщений"},
        @{N="WiaRpc";                 Desc="События подключения камер и сканеров"},
        @{N="stisvc";                 Desc="Загрузка фото с камер и сканеров"},
        @{N="Netlogon";               Desc="Вход в корпоративный домен"},
        @{N="CDPSvc";                 Desc="Платформа синхронизации с другими устройствами"},
        @{N="BcastDVRUserService";    Desc="Фоновая запись игрового процесса для Xbox Game Bar"},
        @{N="CaptureService";         Desc="Захват экрана для Game Bar"},
        @{N="NaturalAuthentication";  Desc="Вход по лицу (Windows Hello Face)"},
        @{N="GraphicsPerfSvc";        Desc="Мониторинг производительности видеокарты"},
        @{N="WpnService";             Desc="Push-уведомления от приложений"},
        @{N="RetailDemo";             Desc="Демо-режим для витрин магазинов"},
        @{N="SysMain";                Desc="Superfetch - предзагрузка программ (полезно на HDD, бесполезно на SSD)"},
        @{N="WSearch";                Desc="Индексирование файлов для поиска Win+S"},
        @{N="WbioSrvc";               Desc="Биометрия - вход по отпечатку или лицу"},
        @{N="RmSvc";                  Desc="Управление радиомодулями - Wi-Fi и Bluetooth"},
        @{N="wscsvc";                 Desc="Центр безопасности Windows"}
    )

    # LTSC: добавить Insider-специфичные задачи если Insider
    if ($Script:WinVer -eq "win11insider") {
        Write-INFO "Insider Preview: добавленInsider-специфичные службы"
    }

    Write-Host "  Ниже список служб. Зелёным - можно смело отключать." -ForegroundColor DarkGray
    Write-Host "  Жёлтым - подумай, нужна ли тебе эта функция." -ForegroundColor DarkGray
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
        $status = if (-not $found) { "нет" } elseif ($found.StartType -eq "Disabled") { "выкл" } else { "вкл" }
        $isRec = $recommendedOff -contains $s.N
        $color = if ($status -eq "выкл" -or $status -eq "нет") { "DarkGray" } elseif ($isRec) { "Green" } else { "Yellow" }
        $statusTag = if ($status -eq "вкл") { "[ВКЛ ]" } elseif ($status -eq "выкл") { "[выкл]" } else { "[нет] " }
        Write-Host ("  {0,3}) {1} {2,-22} {3}" -f $i, $statusTag, $s.N, $s.Desc) -ForegroundColor $color
        $indexMap[$i] = $s.N
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Введи номера через запятую, чтобы ОТКЛЮЧИТЬ. Пример: 1,3,5-9   |" -ForegroundColor Cyan
    Write-Host "  | [A] Отключить все зелёные (рекомендуемые)                      |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
                for ($n = $from; $n -le $to; $n++) {
                    if ($indexMap.ContainsKey($n)) { $toDisableNames += $indexMap[$n] }
                }
            } elseif ($p -match "^\d+$") {
                $n = [int]$p
                if ($indexMap.ContainsKey($n)) { $toDisableNames += $indexMap[$n] }
            }
        }
    }

    Write-Host ""
    if ($toDisableNames.Count -eq 0) {
        Write-INFO "Ничего не выбрано"
    } else {
        foreach ($svcName in $toDisableNames) {
            $desc = ($svcList | Where-Object { $_.N -eq $svcName }).Desc
            Disable-Svc $svcName $desc
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 2 - РЕЕСТР
# ============================================================
function Menu-Registry {
    Draw-Header "ТВИКИ РЕЕСТРА - Производительность и приватность"
    Write-Host "  Каждый твик улучшает производительность или убирает слежку." -ForegroundColor DarkGray
    Write-Host "  [A] = применить все рекомендуемые сразу." -ForegroundColor DarkGray
    Write-Host ""

    # Win10: Power Throttling может отсутствовать; Win11 LTSC: нет AdvertisingInfo
    $tweaks = @(
        @{Num="1";  Rec=$true;  Desc="Планировщик GPU включён       Меньше задержек в играх"}
        @{Num="2";  Rec=$true;  Desc="Алгоритм Нейгла выключен      Меньше пинг в играх"}
        @{Num="3";  Rec=$true;  Desc="Power Throttling выключен      ЦП не душится в фоне"}
        @{Num="4";  Rec=$true;  Desc="Game DVR выключен              Убирает оверхед записи Xbox"}
        @{Num="5";  Rec=$true;  Desc="Визуальные эффекты минимум     Быстрее интерфейс"}
        @{Num="6";  Rec=$true;  Desc="Быстрый запуск выключен        Настоящее выключение"}
        @{Num="7";  Rec=$true;  Desc="Рекламный ID выключен          Убирает слежку по ID"}
        @{Num="8";  Rec=$true;  Desc="Телеметрия выключена           Стоп отправка данных в MS"}
        @{Num="9";  Rec=$false; Desc="OneDrive выключен              Отключает синхронизацию"}
        @{Num="10"; Rec=$true;  Desc="Spotlight экран блокировки выкл Нет рекламы от Microsoft"}
        @{Num="11"; Rec=$true;  Desc="Быстрое выключение 2 сек       Службы убиваются за 2с"}
        @{Num="12"; Rec=$true;  Desc="Твики NTFS                     Меньше операций на диск"}
        @{Num="13"; Rec=$true;  Desc="Автозапуск с USB выключен      Безопасность"}
        @{Num="14"; Rec=$true;  Desc="Оптимизация доставки выкл      Не раздаёшь трафик другим"}
        @{Num="15"; Rec=$true;  Desc="Персонализация ввода выкл      Не собирает нажатия клавиш"}
    )

    # Win11: добавить классическое контекстное меню как твик
    if ($Script:IsWin11) {
        $tweaks += @{Num="16"; Rec=$true; Desc="Классическое меню ПКМ (Win11)   Старое меню вместо нового"}
    }

    foreach ($t in $tweaks) {
        $tag = if ($t.Rec) { "[РЕК]" } else { "[ОПЦ]" }
        $color = if ($t.Rec) { "Green" } else { "Yellow" }
        $line = "  $tag [$($t.Num)] $($t.Desc)"
        # Pad number to 2 digits
        if ($t.Num.Length -eq 1) { $line = "  $tag [ $($t.Num)] $($t.Desc)" }
        Write-Host $line -ForegroundColor $color
    }

    $allRec = ($tweaks | Where-Object { $_.Rec }).Num

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Применить ВСЕ рекомендуемые твики сразу                |" -ForegroundColor Cyan
    Write-Host "  | [1-$($tweaks.Count)] Применить конкретный твик                           |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Apply-Tweak($num) {
        switch ($num) {
            "1" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "DWord" "Планировщик GPU"
                Write-OK "Планировщик GPU включён"
            }
            "2" {
                $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
                foreach ($iface in $ifaces) {
                    $props = Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue
                    if ($props.DhcpIPAddress -like "192.168.*") {
                        Set-RegLogged $iface.PSPath "TcpAckFrequency" 1 "DWord" "Nagle TcpAckFrequency"
                        Set-RegLogged $iface.PSPath "TCPNoDelay" 1 "DWord" "Nagle TCPNoDelay"
                        Write-OK "Алгоритм Нейгла выключен на $($props.DhcpIPAddress)"
                    }
                }
            }
            "3" {
                $pt = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $pt)) { New-Item -Path $pt -Force | Out-Null }
                Set-RegLogged $pt "PowerThrottlingOff" 1 "DWord" "Power Throttling"
                Write-OK "Power Throttling выключен"
            }
            "4" {
                $gdvr = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path $gdvr)) { New-Item -Path $gdvr -Force | Out-Null }
                Set-RegLogged $gdvr "GameDVR_Enabled" 0 "DWord" "Game DVR"
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "DWord" "App Capture"
                Write-OK "Game DVR выключен"
            }
            "5" {
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 "DWord" "Visual FX"
                Set-RegLogged "HKCU:\Control Panel\Desktop" "MinAnimate" "0" "String" "MinAnimate"
                Set-RegLogged "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0 "DWord" "Taskbar Animations"
                Write-OK "Визуальные эффекты - максимальная производительность"
            }
            "6" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 "DWord" "Fast Startup"
                Write-OK "Быстрый запуск выключен"
            }
            "7" {
                # LTSC может не иметь этого пути
                $ad = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
                if (-not (Test-Path $ad)) { New-Item -Path $ad -Force | Out-Null }
                Set-RegLogged $ad "Enabled" 0 "DWord" "Advertising ID"
                Write-OK "Рекламный ID выключен"
            }
            "8" {
                $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
                Set-RegLogged $dc "AllowTelemetry" 0 "DWord" "Telemetry"
                Set-RegLogged $dc "DoNotShowFeedbackNotifications" 1 "DWord" "Feedback Notifications"
                Write-OK "Телеметрия выключена"
            }
            "9" {
                $od = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
                if (-not (Test-Path $od)) { New-Item -Path $od -Force | Out-Null }
                Set-RegLogged $od "DisableFileSyncNGSC" 1 "DWord" "OneDrive"
                Write-OK "OneDrive выключен"
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
                Write-OK "Spotlight и реклама на экране блокировки выключены"
            }
            "11" {
                Set-RegLogged "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" "String" "Shutdown timeout"
                Write-OK "Таймаут выключения установлен 2 секунды"
            }
            "12" {
                fsutil behavior set disablelastaccess 1 | Out-Null
                fsutil behavior set disable8dot3 1 | Out-Null
                Write-ActionLog -type "FSUtil" -target "NTFS" -oldValue "unknown" -desc "NTFS last access + 8.3 names"
                Write-OK "NTFS: отключено время последнего доступа и имена 8.3"
            }
            "13" {
                $ar = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                if (-not (Test-Path $ar)) { New-Item -Path $ar -Force | Out-Null }
                Set-RegLogged $ar "NoDriveTypeAutoRun" 255 "DWord" "Autorun"
                Write-OK "Автозапуск с USB отключён"
            }
            "14" {
                $do = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
                if (-not (Test-Path $do)) { New-Item -Path $do -Force | Out-Null }
                Set-RegLogged $do "DODownloadMode" 0 "DWord" "Delivery Optimization"
                Write-OK "Оптимизация доставки выключена"
            }
            "15" {
                $ink = "HKCU:\Software\Microsoft\InputPersonalization"
                if (-not (Test-Path $ink)) { New-Item -Path $ink -Force | Out-Null }
                Set-RegLogged $ink "RestrictImplicitInkCollection" 1 "DWord" "Ink Collection"
                Set-RegLogged $ink "RestrictImplicitTextCollection" 1 "DWord" "Text Collection"
                Write-OK "Персонализация ввода выключена"
            }
            "16" {
                # Win11 only: classic context menu
                $classicMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                if (-not (Test-Path $classicMenuPath)) { New-Item -Path $classicMenuPath -Force | Out-Null }
                Set-RegLogged $classicMenuPath "(default)" "" "String" "Classic Context Menu"
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Start-Process explorer
                Write-OK "Классическое контекстное меню включено"
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
# МЕНЮ 3 - ЗАДАЧИ ПЛАНИРОВЩИКА
# ============================================================
function Menu-Tasks {
    Draw-Header "ЗАДАЧИ ПЛАНИРОВЩИКА - Отключение телеметрии и диагностики"
    Write-Host "  Эти задачи работают в фоне и отправляют данные в Microsoft." -ForegroundColor DarkGray
    Write-Host "  Все безопасно отключать." -ForegroundColor DarkGray
    Write-Host ""

    $tasks = @(
        @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"; Desc="Отправляет данные о приложениях"}
        @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater";                Desc="Обновляет данные телеметрии"}
        @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask";                    Desc="Отслеживает автозапуск"}
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClient";                          Desc="Телеметрия отзывов"}
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClientOnScenarioDownload";        Desc="Телеметрия сценариев"}
        @{Path="\Microsoft\Windows\Windows Error Reporting\"; Name="QueueReporting";                    Desc="Отчёты об ошибках в MS"}
        @{Path="\Microsoft\Windows\NetTrace\";               Name="GatherNetworkInfo";                  Desc="Сбор сетевых данных"}
        @{Path="\Microsoft\Windows\SettingSync\";            Name="BackgroundUploadTask";               Desc="Синхронизация настроек в облако"}
        @{Path="\Microsoft\Windows\SettingSync\";            Name="NetworkStateChangeTask";             Desc="Триггер сетевой синхронизации"}
        @{Path="\Microsoft\Windows\DiskDiagnostic\";         Name="Microsoft-Windows-DiskDiagnosticDataCollector"; Desc="Данные диска в MS"}
        @{Path="\Microsoft\Windows\UNP\";                    Name="RunUpdateNotificationMgr";           Desc="Уведомления об обновлениях"}
    )

    # Insider Preview: добавить Insider-специфичные задачи
    if ($Script:WinVer -eq "win11insider") {
        $tasks += @{Path="\Microsoft\Windows\WindowsUpdate\"; Name="ScheduledStart"; Desc="Insider Preview: автоматическая проверка обновлений"}
        Write-INFO "Insider Preview: добавлены Insider-задачи"
    }

    $i = 1
    foreach ($t in $tasks) {
        $task   = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        $status = if ($task) { $task.State } else { "НЕ НАЙДЕНО" }
        $icon   = if ($status -eq "Disabled") { "[ВЫКЛ]" } elseif ($status -eq "НЕ НАЙДЕНО") { "[ Н/Д ]" } else { "[ ВКЛ ]" }
        $color  = if ($status -eq "Disabled" -or $status -eq "НЕ НАЙДЕНО") { "DarkGray" } else { "Red" }
        Write-Host ("  {0} [{1,2}] {2,-48} {3}" -f $icon, $i, $t.Name, $t.Desc) -ForegroundColor $color
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Отключить ВСЕ задачи                                   |" -ForegroundColor Cyan
    Write-Host "  | [1-$($tasks.Count)] Отключить конкретную задачу                            |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
            Write-OK "Отключено: $($t.Name)"
        } else { Write-SKIP "Уже отключено или не найдено: $($t.Name)" }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 4 - АВТОЗАПУСК
# ============================================================
function Menu-Startup {
    Draw-Header "АВТОЗАПУСК - Программы запускающиеся при старте Windows"
    Write-Host "  Введите номер программы чтобы убрать её из автозапуска." -ForegroundColor DarkGray
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
        Write-INFO "Записей в автозапуске не найдено - всё чисто!"
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
    Write-Host "  | Введите номер чтобы УБРАТЬ из автозапуска                     |" -ForegroundColor Yellow
    Write-Host "  | [0] Назад в главное меню                                      |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0") { return }
    if ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $entries.Count) {
        $entry = $entries[[int]$choice - 1]
        Write-ActionLog -type "Startup" -target "$($entry.Path)|$($entry.Name)" -oldValue $entry.Value -desc $entry.Name
        Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        Write-OK "Убрано из автозапуска: $($entry.Name)"
        Start-Sleep 1
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 5 - ОЧИСТКА ДИСКА
# ============================================================
function Menu-DiskCleanup {
    Draw-Header "ОЧИСТКА ДИСКА - Освободить место на диске C:"
    Write-Host "  Сканирование размеров папок, подождите..." -ForegroundColor DarkGray
    Write-Host ""

    $items = @(
        @{Label="Временные файлы пользователя"; Path="$env:USERPROFILE\AppData\Local\Temp"},
        @{Label="Временные файлы Windows";      Path="C:\Windows\Temp"},
        @{Label="Папка C:\Temp";               Path="C:\Temp"},
        @{Label="Кэш Prefetch";                 Path="C:\Windows\Prefetch"},
        @{Label="Дамп памяти MEMORY.DMP";       Path="C:\Windows\MEMORY.DMP"},
        @{Label="Отчёты о сбоях ядра";          Path="C:\Windows\LiveKernelReports"},
        @{Label="Минидампы";                    Path="C:\Windows\Minidump"},
        @{Label="Отчёты об ошибках WER";        Path="C:\ProgramData\Microsoft\Windows\WER"},
        @{Label="Кэш браузера Brave";           Path="$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"},
        @{Label="Кэш браузера Chrome";          Path="$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache"},
        @{Label="Кэш Python pip";               Path="$env:USERPROFILE\AppData\Local\pip\cache"},
        @{Label="Кэш миниатюр Windows";         Path="$env:USERPROFILE\AppData\Local\Microsoft\Windows\Explorer"},
        @{Label="Загрузки Windows Update";      Path="C:\Windows\SoftwareDistribution\Download"}
    )

    # Win11: добавить кэш Clipchamp и WidgetCache
    if ($Script:IsWin11) {
        $items += @{Label="Кэш Clipchamp (Win11)"; Path="$env:USERPROFILE\AppData\Local\Packages\Clipchamp.Clipchamp_yfvym6g1cvhwe\LocalCache"}
        $items += @{Label="Кэш Widgets (Win11)";   Path="$env:USERPROFILE\AppData\Local\Packages\MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy\LocalCache"}
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
            $sizeStr = if ($size -ge 1) { "$size ГБ  <<< МНОГО" } elseif ($size -gt 0.05) { "$size ГБ" } else { "< 0.05 ГБ" }
            $color = if ($size -ge 1) { "Red" } elseif ($size -gt 0.2) { "Yellow" } else { "DarkGray" }
            Write-Host ("  [{0,2}] {1,-38} {2}" -f $i, $item.Label, $sizeStr) -ForegroundColor $color
        } else {
            Write-Host ("  [{0,2}] {1,-38} не найдено" -f $i, $item.Label) -ForegroundColor DarkGray
        }
        $i++
    }

    $free = [math]::Round((Get-PSDrive C).Free/1GB,1)
    Write-Host ""
    Write-Host ("  Свободно сейчас : {0} ГБ" -f $free) -ForegroundColor Cyan
    Write-Host ("  Найдено мусора  : {0} ГБ" -f [math]::Round($totalWaste,2)) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Очистить ВСЁ сразу                                     |" -ForegroundColor Cyan
    Write-Host "  | [1-$($items.Count)] Очистить конкретный пункт                              |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Clean-Item($item) {
        $isFile = (Test-Path $item.Path) -and (-not (Get-Item $item.Path -ErrorAction SilentlyContinue).PSIsContainer)
        if ($isFile) { Remove-Item $item.Path -Force -ErrorAction SilentlyContinue }
        else { Remove-Item "$($item.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue }
        Write-OK "Очищено: $($item.Label)"
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
        if (Test-Path $item.Path) { Clean-Item $item } else { Write-SKIP "Не найдено: $($item.Label)" }
    }

    $freeAfter = [math]::Round((Get-PSDrive C).Free/1GB,1)
    Write-Host ""
    Write-Host ("  Было свободно : {0} ГБ" -f $free) -ForegroundColor DarkGray
    Write-Host ("  Стало свободно: {0} ГБ  (+{1} ГБ освобождено)" -f $freeAfter, [math]::Round($freeAfter-$free,1)) -ForegroundColor Green
    Pause-Menu
}

# ============================================================
# МЕНЮ 6 - ЖИВОЙ МОНИТОР
# ============================================================
function Menu-Monitor {
    $running = $true
    while ($running) {
        Clear-Host
        Write-Host ""
        Write-Host "  +================================================================+" -ForegroundColor Cyan
        Write-Host "  |               ЖИВОЙ МОНИТОР СИСТЕМЫ                           |" -ForegroundColor Cyan
        Write-Host "  |          Нажмите Q + Enter чтобы выйти                        |" -ForegroundColor DarkGray
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

        Write-Host "  ЦП (CPU):" -ForegroundColor White
        Draw-Bar $cpu 50
        Write-Host ""
        Write-Host ("  ОЗУ: {0} ГБ занято / {1} ГБ всего" -f $ramUsed, $ramTotal) -ForegroundColor White
        Draw-Bar $ramPct 50
        Write-Host ""
        Write-Host ("  Диск C: {0} ГБ занято / {1} ГБ всего  ({2} ГБ свободно)" -f $usedD, $total, $free) -ForegroundColor White
        Draw-Bar $diskPct 50
        Write-Host ""
        Write-Host ("  Запущено процессов: {0}" -f $proc) -ForegroundColor White
        Write-Host "  Версия: $Script:WinVerName" -ForegroundColor DarkCyan
        Write-Host ""

        Write-Host "  --- ТОП 10 ПРОЦЕССОВ ПО ПАМЯТИ ---" -ForegroundColor Cyan
        Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet -Descending | Select-Object -First 10 | ForEach-Object {
            $mb    = [math]::Round($_.WorkingSet/1MB,1)
            $bar   = "#" * [math]::Min([math]::Round($mb/50),30)
            $color = if ($mb -gt 300) { "Red" } elseif ($mb -gt 100) { "Yellow" } else { "White" }
            Write-Host ("  {0,-30} {1,6} МБ  {2}" -f $_.Name, $mb, $bar) -ForegroundColor $color
        }
        Write-Host ""

        Write-Host "  --- СТАТУС НАСТРОЕК ---" -ForegroundColor Cyan
        $hags = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue).HwSchMode
        $pt   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -ErrorAction SilentlyContinue).PowerThrottlingOff
        $tele = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ErrorAction SilentlyContinue).AllowTelemetry
        $fs   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ErrorAction SilentlyContinue).HiberbootEnabled

        function Show-Bool($label, $val, $goodVal) {
            $ok    = $val -eq $goodVal
            $icon  = if ($ok) { "[ОК]" } else { "[!!]" }
            $color = if ($ok) { "Green" } else { "Red" }
            Write-Host ("  {0} {1}" -f $icon, $label) -ForegroundColor $color
        }
        Show-Bool "Планировщик GPU включён (нужно 2, сейчас $hags)" $hags 2
        Show-Bool "Power Throttling выкл   (нужно 1, сейчас $pt)"   $pt   1
        Show-Bool "Телеметрия выкл         (нужно 0, сейчас $tele)" $tele 0
        Show-Bool "Быстрый запуск выкл     (нужно 0, сейчас $fs)"   $fs   0

        Write-Host ""
        Write-Host ("  Обновлено: {0}  |  Обновление через 3с...  |  Q + Enter для выхода" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor DarkGray

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
# МЕНЮ 7 - СХЕМА ПИТАНИЯ
# ============================================================
function Menu-PowerPlan {
    Draw-Header "СХЕМА ПИТАНИЯ - Режим максимальной производительности"
    Write-Host "  Активная схема:" -ForegroundColor DarkGray
    $current = powercfg /getactivescheme
    Write-Host "  $current" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Все доступные схемы:" -ForegroundColor DarkGray
    powercfg /list | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [1] Активировать Максимальная производительность               |" -ForegroundColor Green
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "1") {
        Write-Host ""
        $existing = powercfg /list | Select-String "Ultimate"
        if (-not $existing) {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
            Write-OK "Схема Максимальная производительность создана"
        }
        $guid = ((powercfg /list | Select-String "Ultimate") -replace ".*GUID: ([^\s]+).*", '$1').Trim()
        if ($guid) {
            powercfg /setactive $guid
            Write-OK "Схема Максимальная производительность активирована"
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 8 - SMB1
# ============================================================
function Menu-SMB {
    Draw-Header "БЕЗОПАСНОСТЬ SMB1 - Отключить уязвимый протокол"
    Write-Host "  SMB1 - старый протокол с серьёзными уязвимостями." -ForegroundColor DarkGray
    Write-Host "  Использовался вирусом WannaCry. Вам он не нужен." -ForegroundColor DarkGray
    Write-Host ""

    $smb    = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    $status = if ($smb) { $smb.State } else { "Неизвестно" }
    $color  = if ($status -eq "Disabled") { "Green" } else { "Red" }
    Write-Host ("  Статус SMB1: [ {0} ]" -f $status) -ForegroundColor $color
    Write-Host ""

    if ($status -ne "Disabled") {
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | SMB1 ВКЛЮЧЁН - это угроза безопасности!                       |" -ForegroundColor Red
        Write-Host "  | [1] Отключить SMB1 СЕЙЧАС - настоятельно рекомендуется        |" -ForegroundColor Green
        Write-Host "  | [0] Назад в главное меню                                      |" -ForegroundColor DarkGray
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Выбор: " -ForegroundColor White -NoNewline
        $choice = Read-Host
        if ($choice -eq "1") {
            Write-Host ""
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
            Write-OK "SMB1 отключён - требуется перезагрузка"
        }
    } else {
        Write-Host "  Всё в порядке. SMB1 уже отключён." -ForegroundColor Green
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 9 - ЗДОРОВЬЕ СИСТЕМЫ
# ============================================================
function Menu-Health {
    Draw-Header "ЗДОРОВЬЕ СИСТЕМЫ - SSD, температуры, драйверы, шрифты"
    Write-Host "  Используются только встроенные средства Windows." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  --- ЗДОРОВЬЕ ДИСКА (SSD/HDD) ---" -ForegroundColor Cyan
    Get-PhysicalDisk | ForEach-Object {
        $disk = $_
        Write-Host ("  Диск: {0}" -f $disk.FriendlyName) -ForegroundColor White
        $hColor = if ($disk.HealthStatus -eq "Healthy") { "Green" } else { "Red" }
        Write-Host ("    Тип            : {0}" -f $disk.MediaType)
        Write-Host ("    Статус здоровья: {0}" -f $disk.HealthStatus) -ForegroundColor $hColor
        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
            if ($rel.Temperature) {
                $tColor = if ($rel.Temperature -gt 60) { "Red" } elseif ($rel.Temperature -gt 45) { "Yellow" } else { "Green" }
                Write-Host ("    Температура    : {0} C" -f $rel.Temperature) -ForegroundColor $tColor
            }
            if ($rel.Wear -ne $null) {
                $wColor = if ($rel.Wear -gt 80) { "Red" } elseif ($rel.Wear -gt 50) { "Yellow" } else { "Green" }
                Write-Host ("    Износ SSD      : {0}%" -f $rel.Wear) -ForegroundColor $wColor
            }
            if ($rel.PowerOnHours -ne $null) {
                Write-Host ("    Часов работы   : {0} ч (~{1} дней)" -f $rel.PowerOnHours, [math]::Round($rel.PowerOnHours/24,0))
            }
        } catch {
            Write-INFO "Подробная статистика недоступна для этого диска"
        }
        Write-Host ""
    }

    Write-Host "  --- ТЕМПЕРАТУРА ---" -ForegroundColor Cyan
    $tempFound = $false
    try {
        $temps = Get-WmiObject -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($t in $temps) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            $color = if ($celsius -gt 85) { "Red" } elseif ($celsius -gt 70) { "Yellow" } else { "Green" }
            Write-Host ("  Термозона: {0} C" -f $celsius) -ForegroundColor $color
            $tempFound = $true
        }
    } catch { }
    if (-not $tempFound) {
        Write-INFO "Встроенные датчики не сообщили температуру (частое дело на ноутбуках)"
    }
    $cpuLoad = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-Host ("  Текущая загрузка ЦП: {0}%" -f $cpuLoad) -ForegroundColor White
    Write-Host ""

    Write-Host "  --- ПРОВЕРКА ОБНОВЛЕНИЙ ДРАЙВЕРОВ ---" -ForegroundColor Cyan
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartType -eq "Disabled") {
        Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
        Write-INFO "Служба Windows Update временно включена для проверки"
    }
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    try {
        UsoClient StartScan 2>$null
        Write-OK "Проверка драйверов запущена через Windows Update"
        Write-Host "  Смотри: Параметры -> Центр обновления -> Дополнительные параметры -> Необязательные обновления" -ForegroundColor White
    } catch {
        Write-INFO "Проверь вручную в Параметры -> Центр обновления Windows"
    }
    Write-Host ""

    Write-Host "  --- ПРОВЕРКА ШРИФТОВ ---" -ForegroundColor Cyan
    $winInstallDate = (Get-WmiObject Win32_OperatingSystem).InstallDate
    $winInstallDate = [Management.ManagementDateTimeConverter]::ToDateTime($winInstallDate)
    $fontPath = "C:\Windows\Fonts"
    $allFonts = Get-ChildItem $fontPath -File -ErrorAction SilentlyContinue
    $suspects = $allFonts | Where-Object { $_.CreationTime -gt $winInstallDate.AddDays(2) }
    Write-Host ("  Всего шрифтов: {0}   Добавлено после установки Windows: {1}" -f $allFonts.Count, $suspects.Count) -ForegroundColor White

    if ($suspects.Count -gt 0) {
        Write-Host ""
        $suspects | Sort-Object CreationTime | Select-Object -First 20 | ForEach-Object {
            $sizeKb = [math]::Round($_.Length/1KB,0)
            Write-Host ("  {0,-40} {1,-20} {2} KB" -f $_.Name, $_.CreationTime.ToString("yyyy-MM-dd"), $sizeKb)
        }
        $totalSize = [math]::Round(($suspects | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        Write-Host ("`n  Общий размер: {0} МБ" -f $totalSize) -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Введи YES чтобы удалить эти шрифты, или Enter чтобы пропустить: " -ForegroundColor White -NoNewline
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
                } catch { Write-INFO "Не удалось удалить: $($font.Name)" }
            }
            Write-OK "Удалено $removed шрифтов, освобождено ~$totalSize МБ"
        } else {
            Write-SKIP "Пропущено пользователем"
        }
    } else {
        Write-OK "Лишних шрифтов не найдено"
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 10 - ОБНОВЛЕНИЕ ДРАЙВЕРОВ
# ============================================================
function Menu-DriverUpdate {
    Draw-Header "ОБНОВЛЕНИЕ ДРАЙВЕРОВ - Определение железа и поиск последних версий"
    Write-Host "  Определяю комплектующие компьютера..." -ForegroundColor DarkGray
    Write-Host ""

    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    Write-Host ("  Процессор : {0}" -f $cpu.Name) -ForegroundColor White

    $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Basic|Remote" }
    foreach ($g in $gpus) {
        Write-Host ("  Видео     : {0}" -f $g.Name) -ForegroundColor White
    }

    $wifi = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.Name -match "Wireless|Wi-Fi|WiFi" -and $_.Manufacturer -notmatch "Microsoft" } | Select-Object -First 1
    if ($wifi) { Write-Host ("  Wi-Fi     : {0}" -f $wifi.Name) -ForegroundColor White }

    $audio = Get-WmiObject Win32_SoundDevice | Select-Object -First 1
    if ($audio) { Write-Host ("  Аудио     : {0}" -f $audio.Name) -ForegroundColor White }

    $sys = Get-WmiObject Win32_ComputerSystem
    Write-Host ("  Ноутбук   : {0} {1}" -f $sys.Manufacturer, $sys.Model) -ForegroundColor White
    Write-Host ("  ОС        : {0}" -f $Script:WinVerName) -ForegroundColor DarkCyan
    Write-Host ""

    $links = @()
    function Build-SearchUrl($query) { return "https://www.google.com/search?q=" + [uri]::EscapeDataString($query) }

    if ($cpu.Name -match "Intel") {
        $links += @{Label="Intel Driver and Support Assistant (CPU, чипсет, Wi-Fi, BT)"; Url="https://www.intel.com/content/www/us/en/support/detect.html"}
    } elseif ($cpu.Name -match "AMD") {
        $cpuClean = ($cpu.Name -replace "AMD","" -replace "Processor","" -replace "with Radeon.*","" -replace "\s+"," ").Trim()
        $links += @{Label="AMD - последний драйвер чипсета для $cpuClean"; Url=(Build-SearchUrl "AMD chipset driver $cpuClean latest download")}
    }

    foreach ($g in $gpus) {
        if ($g.Name -match "NVIDIA") {
            $gpuClean = ($g.Name -replace "NVIDIA","" -replace "Laptop GPU","" -replace "\s+"," ").Trim()
            $links += @{Label="NVIDIA - последний драйвер для: $gpuClean"; Url=(Build-SearchUrl "nvidia driver $gpuClean laptop latest download")}
        } elseif ($g.Name -match "Intel") {
            $links += @{Label="Intel Graphics - последние драйверы"; Url="https://www.intel.com/content/www/us/en/download-center/home.html"}
        } elseif ($g.Name -match "AMD|Radeon") {
            $gpuClean = ($g.Name -replace "AMD","" -replace "Radeon","" -replace "Graphics","" -replace "\s+"," ").Trim()
            $links += @{Label="AMD - последний драйвер для: Radeon $gpuClean"; Url=(Build-SearchUrl "amd radeon driver $gpuClean laptop latest download")}
        }
    }

    if ($sys.Manufacturer -match "HUAWEI") {
        $links += @{Label="HUAWEI - драйверы для вашей модели"; Url="https://consumer.huawei.com/ru/support/laptops/"}
    } elseif ($sys.Manufacturer -match "ASUS") {
        $links += @{Label="ASUS - драйверы для вашей модели"; Url="https://www.asus.com/ru/support/"}
    } elseif ($sys.Manufacturer -match "Lenovo") {
        $links += @{Label="Lenovo - драйверы для вашей модели"; Url="https://support.lenovo.com/ru/ru/"}
    } elseif ($sys.Manufacturer -match "HP") {
        $links += @{Label="HP - драйверы для вашей модели"; Url="https://support.hp.com/ru-ru/"}
    } elseif ($sys.Manufacturer -match "Dell") {
        $links += @{Label="Dell - драйверы для вашей модели"; Url="https://www.dell.com/support/home/ru-ru"}
    } elseif ($sys.Manufacturer -match "MSI") {
        $links += @{Label="MSI - драйверы для вашей модели"; Url="https://ru.msi.com/support/"}
    } elseif ($sys.Manufacturer -match "Acer") {
        $links += @{Label="Acer - драйверы для вашей модели"; Url="https://www.acer.com/ru-ru/support"}
    }

    if ($links.Count -eq 0) {
        Write-INFO "Не удалось определить производителя для точечных ссылок"
    } else {
        Write-Host "  Найдены следующие ресурсы:" -ForegroundColor Cyan
        Write-Host ""
        $i = 1
        foreach ($l in $links) {
            Write-Host ("  [{0}] {1}" -f $i, $l.Label) -ForegroundColor Green
            $i++
        }
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Открыть ВСЕ ссылки в браузере сразу                    |" -ForegroundColor Cyan
    Write-Host "  | [1-N]  Открыть конкретную ссылку                              |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "A" -or $choice -eq "a") {
        foreach ($l in $links) { Start-Process $l.Url; Write-OK "Открыто: $($l.Label)" }
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $links.Count) {
        $l = $links[[int]$choice - 1]; Start-Process $l.Url; Write-OK "Открыто: $($l.Label)"
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 11 - ТОЧКА ВОССТАНОВЛЕНИЯ
# ============================================================
function Menu-RestorePoint {
    Draw-Header "ТОЧКА ВОССТАНОВЛЕНИЯ - Создать снапшот системы"
    Write-Host "  Если после твиков что-то сломается, можно откатить систему." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ВАЖНО: Windows по умолчанию разрешает только 1 точку в 24 часа." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [1] Создать точку восстановления СЕЙЧАС                       |" -ForegroundColor Green
    Write-Host "  | [2] Снять лимит 24 часа (разрешить создавать чаще)            |" -ForegroundColor White
    Write-Host "  | [3] Открыть окно восстановления системы (откат назад)         |" -ForegroundColor White
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "1") {
        Write-Host ""
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "WinTools - перед изменениями $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Write-OK "Точка восстановления создана"
        } catch {
            Write-INFO "Не удалось создать: возможно сработал лимит 24 часа. Используй пункт [2]."
        }
    } elseif ($choice -eq "2") {
        Write-Host ""
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-OK "Лимит снят"
    } elseif ($choice -eq "3") {
        Write-Host ""
        Start-Process rstrui.exe
        Write-OK "Открыто окно восстановления системы"
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 12 - ЖУРНАЛ ИЗМЕНЕНИЙ И ОТМЕНА
# ============================================================
function Menu-ChangeLog {
    Draw-Header "ЖУРНАЛ ИЗМЕНЕНИЙ - Что изменено и отмена"

    if (-not (Test-Path $Global:LogPath)) {
        Write-INFO "Журнал пуст - изменений ещё не было"
        Pause-Menu; return
    }

    $entries = Import-Csv -Path $Global:LogPath -ErrorAction SilentlyContinue
    if (-not $entries -or $entries.Count -eq 0) {
        Write-INFO "Журнал пуст - изменений ещё не было"
        Pause-Menu; return
    }

    Write-Host "  Все изменения (последние сверху):" -ForegroundColor DarkGray
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
    Write-Host "  | Введи номера через запятую чтобы ОТМЕНИТЬ                     |" -ForegroundColor Cyan
    Write-Host "  | [C] Очистить журнал                                           |" -ForegroundColor Yellow
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -eq "C" -or $choice -eq "c") {
        Remove-Item $Global:LogPath -Force -ErrorAction SilentlyContinue
        "Timestamp,Type,Target,OldValue,Desc" | Out-File -FilePath $Global:LogPath -Encoding UTF8
        Write-OK "Журнал очищен"
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
                    if ($e.OldValue -eq "NULL") { Write-SKIP "Пропуск: неизвестное состояние для $($e.Target)" }
                    else {
                        Set-Service -Name $e.Target -StartupType $e.OldValue -ErrorAction SilentlyContinue
                        if ($e.OldValue -ne "Disabled") { Start-Service -Name $e.Target -ErrorAction SilentlyContinue }
                        Write-OK "Служба $($e.Target) возвращена: $($e.OldValue)"
                    }
                } catch { Write-INFO "Не удалось отменить: $($e.Target)" }
            }
            "Task" {
                try {
                    $parts2 = $e.Target -split "\|"
                    $taskPath = $parts2[0]; $taskName = $parts2[1]
                    if ($e.OldValue -ne "Disabled") {
                        Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
                        Write-OK "Задача $taskName включена обратно"
                    }
                } catch { Write-INFO "Не удалось отменить задачу: $($e.Target)" }
            }
            "Registry" {
                try {
                    $parts2 = $e.Target -split "\|"
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") {
                        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                        Write-OK "Параметр реестра удалён: $regName"
                    } else {
                        Set-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -ErrorAction SilentlyContinue
                        Write-OK "Реестр $regName возвращён: $($e.OldValue)"
                    }
                } catch { Write-INFO "Не удалось отменить реестр: $($e.Target)" }
            }
            "Startup" { Write-INFO "Автозапуск $($e.Target) - добавь вручную если нужно" }
            default { Write-INFO "Нельзя отменить автоматически: $($e.Type) - $($e.Desc)" }
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 13 - ВСТРОЕННЫЕ ПРИЛОЖЕНИЯ
# ============================================================
function Menu-Bloatware {
    Draw-Header "ВСТРОЕННЫЕ ПРИЛОЖЕНИЯ - Удаление предустановленного мусора"

    # LTSC: почти нет bloatware
    if ($Script:IsLTSC) {
        Write-INFO "Windows 11 Enterprise LTSC: предустановленных приложений почти нет."
        Write-Host "  Эта версия Windows уже очищена от bloatware." -ForegroundColor DarkGray
        Pause-Menu; return
    }

    Write-Host "  Эти приложения идут в комплекте с Windows." -ForegroundColor DarkGray
    Write-Host ""

    $apps = @(
        @{N="Microsoft.XboxApp";                    L="Приложение Xbox"},
        @{N="Microsoft.XboxGameOverlay";             L="Оверлей Xbox Game Bar"},
        @{N="Microsoft.XboxGamingOverlay";           L="Оверлей игр Xbox"},
        @{N="Microsoft.XboxIdentityProvider";        L="Провайдер учётки Xbox"},
        @{N="Microsoft.XboxSpeechToTextOverlay";     L="Голосовой ввод Xbox"},
        @{N="Microsoft.Xbox.TCUI";                   L="Интерфейс Xbox TCUI"},
        @{N="Microsoft.MicrosoftSolitaireCollection";L="Пасьянсы Microsoft"},
        @{N="Microsoft.BingWeather";                 L="Погода"},
        @{N="Microsoft.BingNews";                    L="Новости"},
        @{N="Microsoft.WindowsMaps";                 L="Карты"},
        @{N="Microsoft.YourPhone";                   L="Телефон (связь с Android)"},
        @{N="Microsoft.GetHelp";                     L="Служба поддержки"},
        @{N="Microsoft.Getstarted";                  L="Советы Windows"},
        @{N="Microsoft.WindowsFeedbackHub";          L="Центр отзывов"},
        @{N="Microsoft.3DBuilder";                    L="3D Builder"},
        @{N="Microsoft.Microsoft3DViewer";            L="Просмотр 3D"},
        @{N="Microsoft.MixedReality.Portal";          L="Портал смешанной реальности"},
        @{N="Microsoft.MicrosoftOfficeHub";           L="Ярлыки Office (реклама)"},
        @{N="Microsoft.SkypeApp";                     L="Skype (встроенный)"},
        @{N="Microsoft.People";                       L="Контакты"},
        @{N="Microsoft.WindowsCommunicationsApps";    L="Почта и Календарь"},
        @{N="MicrosoftTeams";                         L="Teams (встроенный)"},
        @{N="Microsoft.Todos";                        L="Microsoft To Do"},
        @{N="Microsoft.PowerAutomateDesktop";         L="Power Automate"},
        @{N="Microsoft.MicrosoftStickyNotes";         L="Липкие заметки"},
        @{N="Clipchamp.Clipchamp";                     L="Видеоредактор Clipchamp"},
        @{N="MicrosoftCorporationII.MicrosoftFamily"; L="Семейная безопасность"},
        @{N="Microsoft.WindowsAlarms";                L="Будильники и часы"},
        @{N="Microsoft.ZuneMusic";                     L="Медиаплеер Groove"},
        @{N="Microsoft.ZuneVideo";                     L="Кино и ТВ"}
    )

    # Win10: больше bloatware (Cortana, etc)
    if ($Script:IsWin10) {
        $apps += @{N="Microsoft.549981C3F5F10"; L="Cortana (только Win10)"}
    }

    $i = 1
    $indexMap = @{}
    foreach ($a in $apps) {
        $installed = Get-AppxPackage -Name $a.N -AllUsers -ErrorAction SilentlyContinue
        $status = if ($installed) { "[стоит]" } else { "[нет]  " }
        $color = if ($installed) { "Green" } else { "DarkGray" }
        Write-Host ("  {0,3}) {1} {2}" -f $i, $status, $a.L) -ForegroundColor $color
        $indexMap[$i] = $a.N
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Введи номера через запятую чтобы УДАЛИТЬ. Пример: 1,2,5-8      |" -ForegroundColor Cyan
    Write-Host "  | [A] Удалить всё из списка                                |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
            Write-OK "Удалено: $appName"
        } else {
            Write-SKIP "Не установлено: $appName"
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 14 - ОЧИСТКА КЭША БРАУЗЕРОВ
# ============================================================
function Menu-BrowserCache {
    Draw-Header "ОЧИСТКА КЭША БРАУЗЕРОВ - Brave, Chrome, Edge"
    Write-Host "  Закроет браузеры и очистит кэш. Пароли и закладки не трогает." -ForegroundColor DarkGray
    Write-Host ""

    $browsers = @(
        @{Name="Brave";  Process="brave";  Path="$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"},
        @{Name="Chrome"; Process="chrome"; Path="$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache"},
        @{Name="Edge";   Process="msedge"; Path="$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cache"}
    )

    $i = 1
    foreach ($b in $browsers) {
        $size = Get-FolderSize $b.Path
        $sizeStr = if ($size -gt 0) { "$size ГБ" } else { "не найдено или пусто" }
        Write-Host ("  [{0}] {1,-10} {2}" -f $i, $b.Name, $sizeStr) -ForegroundColor White
        $i++
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]   Очистить кэш ВСЕХ браузеров                             |" -ForegroundColor Cyan
    Write-Host "  | [1-3] Очистить конкретный браузер                             |" -ForegroundColor White
    Write-Host "  | [0]   Назад в главное меню                                     |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
            Write-OK "Кэш $($b.Name) очищен"
        } else {
            Write-SKIP "$($b.Name) не найден"
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 15 - КОСМЕТИКА WINDOWS
# ============================================================
function Menu-Cosmetics {
    Draw-Header "КОСМЕТИКА WINDOWS"

    $classicMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $classicEnabled = Test-Path $classicMenuPath

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $hideExt = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).HideFileExt
    $hideHidden = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).Hidden

    # Win11 only: classic context menu
    if ($Script:IsWin11) {
        Write-Host ("  [1] Классическое контекстное меню (ПКМ)   статус: {0}" -f $(if($classicEnabled){"ВКЛ"}else{"выкл (Win11 по умолч.)"})) -ForegroundColor $(if($classicEnabled){"Green"}else{"White"})
    } else {
        Write-Host "  [1] Классическое контекстное меню - только для Windows 11" -ForegroundColor DarkGray
    }
    Write-Host ("  [2] Показ расширений файлов (.txt, .exe)   статус: {0}" -f $(if($hideExt -eq 0){"ВКЛ"}else{"выкл"})) -ForegroundColor $(if($hideExt -eq 0){"Green"}else{"White"})
    Write-Host ("  [3] Показ скрытых файлов и папок           статус: {0}" -f $(if($hideHidden -eq 1){"ВКЛ"}else{"выкл"})) -ForegroundColor $(if($hideHidden -eq 1){"Green"}else{"White"})
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    if ($Script:IsWin11) {
        Write-Host "  | [1] Переключить классическое меню ПКМ                          |" -ForegroundColor White
    }
    Write-Host "  | [2] Переключить показ расширений файлов                        |" -ForegroundColor White
    Write-Host "  | [3] Переключить показ скрытых файлов                           |" -ForegroundColor White
    Write-Host "  | [A] Включить ВСЕ доступное                                     |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Toggle-ClassicMenu {
        if ($Script:IsWin11) {
            if ($classicEnabled) {
                Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
                Write-OK "Классическое меню выключено"
            } else {
                New-Item -Path $classicMenuPath -Force | Out-Null
                Set-ItemProperty -Path $classicMenuPath -Name "(default)" -Value "" -ErrorAction SilentlyContinue
                Write-OK "Классическое контекстное меню включено"
            }
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Start-Process explorer
        } else {
            Write-SKIP "Доступно только на Windows 11"
        }
    }

    function Toggle-FileExt {
        $new = if ($hideExt -eq 0) { 1 } else { 0 }
        Set-RegLogged $advPath "HideFileExt" $new "DWord" "Показ расширений"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer
        if ($new -eq 0) { Write-OK "Расширения файлов показываются" } else { Write-OK "Расширения скрыты" }
    }

    function Toggle-HiddenFiles {
        $new = if ($hideHidden -eq 1) { 2 } else { 1 }
        Set-RegLogged $advPath "Hidden" $new "DWord" "Скрытые файлы"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer
        if ($new -eq 1) { Write-OK "Скрытые файлы показываются" } else { Write-OK "Скрытые файлы скрыты" }
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
# ГЛАВНОЕ МЕНЮ
# ============================================================
function Main-Menu {
    while ($true) {
        Draw-Header $null
        Write-Host "  Что хочешь сделать?" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  #  |  Раздел                   |  Что делает                      |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  1  |  Службы                   |  Отключить ненужные службы       |" -ForegroundColor Green
        Write-Host "  |  2  |  Твики реестра            |  GPU, сеть, приватность          |" -ForegroundColor Green
        Write-Host "  |  3  |  Задачи планировщика      |  Убить телеметрию                |" -ForegroundColor Green
        Write-Host "  |  4  |  Автозапуск               |  Убрать программы из автостарта  |" -ForegroundColor Green
        Write-Host "  |  5  |  Очистка диска            |  Освободить ГБ на диске C:       |" -ForegroundColor Yellow
        Write-Host "  |  6  |  Живой монитор            |  ЦП/ОЗУ/Диск в реальном времени |" -ForegroundColor Cyan
        Write-Host "  |  7  |  Схема питания            |  Макс. производительность        |" -ForegroundColor Green
        Write-Host "  |  8  |  Безопасность SMB1        |  Закрыть уязвимость              |" -ForegroundColor Red
        Write-Host "  |  9  |  Здоровье системы         |  SSD, температуры, драйверы      |" -ForegroundColor Cyan
        Write-Host "  | 10  |  Обновление драйверов     |  Открыть сайты с последними вер. |" -ForegroundColor Cyan
        Write-Host "  | 11  |  Точка восстановления     |  Снапшот системы на всякий случай|" -ForegroundColor Magenta
        Write-Host "  | 12  |  Журнал и отмена          |  Посмотреть/отменить изменения   |" -ForegroundColor Magenta
        Write-Host "  | 13  |  Встроенные приложения    |  Удалить Xbox, Пасьянс и т.д.    |" -ForegroundColor Yellow
        Write-Host "  | 14  |  Кэш браузеров            |  Очистить Brave/Chrome/Edge разом|" -ForegroundColor Yellow
        Write-Host "  | 15  |  Косметика Windows        |  Классич. меню, расширения файлов|" -ForegroundColor White
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Выход                    |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  СОВЕТ: Сначала [11] точка восстановления, потом [1] Службы -> [A]" -ForegroundColor DarkCyan
        Write-Host "  ВЕРСИЯ: $Script:WinVerName" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
