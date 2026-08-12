# WinTools - Оптимизация Windows (Русская версия)
# Запускать от имени Администратора
# Поддержка: Windows 10 Home/Pro, Windows 11 Home/Pro/Enterprise/LTSC/InsiderPreview
# Версия скрипта определяется автоматически или через install.ps1

[CmdletBinding()]
param(
    [ValidateSet("win10home", "win10pro", "win11home", "win11pro", "win11enterprise", "win11ltsc", "win11insider")]
    [string]$WindowsVersion
)

$Script:WinToolsVersion = "2.0.0"
$Script:WinToolsLanguage = "ru"
$Script:Repository = "SigmaNagibatorJob/wintools"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ОШИБКА: Запустите от имени Администратора!" -ForegroundColor Red
    Start-Sleep 3; exit
}

# ============================================================
# ОПРЕДЕЛЕНИЕ ВЕРСИИ WINDOWS
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
        elseif ($caption -match "Домашняя|Home") { return "win10home" }
        else                                { return "win10pro" }
    }
    elseif ($caption -match "Windows 11") {
        if ($caption -match "Insider")          { return "win11insider" }
        elseif ($caption -match "LTSC")         { return "win11ltsc" }
        elseif ($caption -match "Enterprise")   { return "win11enterprise" }
        elseif ($caption -match "Pro")          { return "win11pro" }
        elseif ($caption -match "Домашняя|Home") { return "win11home" }
        else                                    { return "win11pro" }
    }
    return "unknown"
}

$Script:WinVer = if ($WindowsVersion) { $WindowsVersion } else { Get-WindowsVersion }
$Script:WinVerName = switch ($Script:WinVer) {
    "win10home"    { "Windows 10 Домашняя" }
    "win10pro"     { "Windows 10 Pro" }
    "win11home"    { "Windows 11 Домашняя" }
    "win11pro"        { "Windows 11 Pro" }
    "win11enterprise" { "Windows 11 Enterprise" }
    "win11ltsc"       { "Windows 11 Enterprise LTSC" }
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
function Write-FAIL($msg) { Write-Host "  [!] $msg" -ForegroundColor Red }

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

    # Set-ItemProperty не поддерживает параметр -Type. Из-за него раньше
    # почти все твики завершались ошибкой, после чего скрипт всё равно писал "успешно".
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
    $actual = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
    if ("$actual" -ne "$value") {
        throw "Проверка реестра не пройдена: $path\$name (ожидалось '$value', получено '$actual')"
    }

    Write-ActionLog -type "Registry" -target "$path|$name" -oldValue $(if ($oldExists) { $old } else { $null }) -desc $desc
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  [ Нажмите любую клавишу для возврата ]" -ForegroundColor DarkGray
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
        Write-SKIP "Не найдено: $label"
        return
    }
    if ($found.StartType -eq "Disabled") {
        Write-SKIP "Уже отключено: $label"
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
        if ($found.StartType -ne "Disabled") { throw "тип запуска не изменился" }
        Write-ActionLog -type "Service" -target $found.Name -oldValue "$oldStartType|$oldStatus" -desc $label
        Write-OK "Отключено: $label"
    } catch {
        Write-FAIL "Не удалось отключить '$label': $($_.Exception.Message)"
    }
}

function ConvertTo-NumberList($inputText, [int]$maxNumber) {
    $numbers = @()
    foreach ($rawToken in ($inputText -split ",")) {
        $token = $rawToken.Trim()
        if ($token -notmatch '^(\d+)(?:-(\d+))?$') {
            throw "Неверный элемент: '$token'"
        }
        $first = [int]$matches[1]
        $last = if ($matches[2]) { [int]$matches[2] } else { $first }
        if ($first -lt 1 -or $last -lt $first -or $last -gt $maxNumber) {
            throw "Номер или диапазон вне списка: '$token'"
        }
        for ($number = $first; $number -le $last; $number++) {
            if ($numbers -notcontains $number) { $numbers += $number }
        }
    }
    return $numbers
}

function Confirm-ActionPreview($lines) {
    Write-Host ""
    Write-Host "  +------------------ ПРЕДПРОСМОТР -------------------------------+" -ForegroundColor Cyan
    foreach ($line in $lines) { Write-Host "  $line" -ForegroundColor White }
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  Применить изменения? [Y/Д = да; N/Н/Enter = вернуться]: " -ForegroundColor Yellow -NoNewline
    $answer = (Read-Host).Trim()
    return $answer -match '^(?i:y|yes|д|да)$'
}

function Enable-Svc($name, $label) {
    $found = Get-Service -Name "$name*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Write-SKIP "Не найдено: $label"; return }
    if ($found.StartType -ne "Disabled") { Write-SKIP "Уже включено: $label"; return }

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
                Write-INFO "Тип запуска восстановлен, но службу не удалось запустить сейчас: $($_.Exception.Message)"
            }
        }
        $restored = Get-Service -Name $found.Name -ErrorAction Stop
        if ($restored.StartType -eq "Disabled") { throw "тип запуска остался Disabled" }
        Write-ActionLog -type "Service" -target $found.Name -oldValue "Disabled|Stopped" -desc $label
        Write-OK "Включено: $label ($($restored.StartType))"
    } catch {
        Write-FAIL "Не удалось включить '$label': $($_.Exception.Message)"
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
    Write-Host "  | Номера переключают службы: 1,3,5-9                            |" -ForegroundColor Cyan
    Write-Host "  | [A] Отключить все зелёные (рекомендуемые)                      |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
        Write-FAIL "Не удалось разобрать список: $($_.Exception.Message)"
        Pause-Menu; Menu-Services; return
    }

    $plan = @()
    foreach ($svcName in ($selectedNames | Select-Object -Unique)) {
        $found = Get-Service -Name "$svcName*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { continue }
        if ($forceDisable -and $found.StartType -eq "Disabled") { continue }
        $desc = ($svcList | Where-Object { $_.N -eq $svcName }).Desc
        $enable = if ($forceDisable) { $false } else { $found.StartType -eq "Disabled" }
        $action = if ($enable) { "ВКЛЮЧИТЬ" } else { "ОТКЛЮЧИТЬ" }
        $plan += [pscustomobject]@{Name=$svcName; Desc=$desc; Enable=$enable; Preview="[$action] $($found.Name) — $desc"}
    }

    if ($plan.Count -eq 0) {
        Write-INFO "Ничего доступного не выбрано"
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
# МЕНЮ 2 - РЕЕСТР
# ============================================================
function Menu-Registry {
    Draw-Header "ТВИКИ РЕЕСТРА - включение, отключение и текущий статус"
    Write-Host "  Статус [ВКЛ] означает, что оптимизационный твик применён." -ForegroundColor DarkGray
    Write-Host "  Номер переключает твик; +номер включает; -номер возвращает стандартное поведение." -ForegroundColor DarkGray
    Write-Host ""

    $tweaks = @(
        @{Num="1";  Rec=$true;  Desc="Планировщик GPU: меньше задержек в играх"}
        @{Num="2";  Rec=$true;  Desc="Отключение Нейгла: меньше сетевых задержек"}
        @{Num="3";  Rec=$true;  Desc="Отключение Power Throttling"}
        @{Num="4";  Rec=$true;  Desc="Отключение Game DVR и фоновой записи"}
        @{Num="5";  Rec=$true;  Desc="Минимум анимаций и визуальных эффектов"}
        @{Num="6";  Rec=$true;  Desc="Отключение быстрого запуска Windows"}
        @{Num="7";  Rec=$true;  Desc="Отключение рекламного идентификатора"}
        @{Num="8";  Rec=$true;  Desc="Минимальная телеметрия и без запросов отзывов"}
        @{Num="9";  Rec=$false; Desc="Отключение синхронизации OneDrive"}
        @{Num="10"; Rec=$true;  Desc="Отключение Spotlight, советов и предложений"}
        @{Num="11"; Rec=$true;  Desc="Таймаут завершения служб: 2 секунды"}
        @{Num="12"; Rec=$true;  Desc="NTFS: без Last Access и имён 8.3"}
        @{Num="13"; Rec=$true;  Desc="Отключение автозапуска со съёмных дисков"}
        @{Num="14"; Rec=$true;  Desc="Отключение P2P оптимизации доставки"}
        @{Num="15"; Rec=$true;  Desc="Отключение персонализации рукописного ввода"}
    )
    if ($Script:IsWin11) {
        $tweaks += @{Num="16"; Rec=$true; Desc="Классическое контекстное меню Windows 11"}
        $tweaks += @{Num="19"; Rec=$true; Desc="Отключение виджетов Windows 11"}
    }

    $tweaks += @(
        @{Num="17"; Rec=$true;  Desc="Включение игрового режима Windows"}
        @{Num="18"; Rec=$false; Desc="Отключение ускорения мыши"}
        @{Num="20"; Rec=$true;  Desc="Отключение веб-поиска в меню Пуск"}
        @{Num="21"; Rec=$false; Desc="Отключение фоновых приложений"}
        @{Num="22"; Rec=$false; Desc="Отключение всплывающих уведомлений"}
        @{Num="23"; Rec=$false; Desc="Отключение гибернации"}
        @{Num="24"; Rec=$false; Desc="Показывать секунды в системных часах"}
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
                    if ($active.Count -eq 0) { throw "Не найден активный IPv4-интерфейс" }
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
                        if (Test-Path $root) { throw "раздел реестра не удалён" }
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
                default { throw "Неизвестный номер твика: $num" }
            }

            $actual = Get-TweakEnabled $num
            if ($enabled -and -not $actual) { throw "проверка включения не пройдена" }
            if (-not $enabled -and $actual) { throw "проверка отключения не пройдена" }
            $stateText = if ($enabled) { "ВКЛЮЧЁН" } else { "ВЫКЛЮЧЕН" }
            Write-OK "Твик [$num] $stateText"
        } catch {
            Write-FAIL "Не удалось изменить твик [$num]: $($_.Exception.Message)"
        }
    }

    function ConvertTo-TweakActions($inputText) {
        $actions = @()
        foreach ($rawToken in ($inputText -split ",")) {
            $token = $rawToken.Trim()
            if ($token -notmatch '^([+-]?)(\d+)(?:-(\d+))?$') {
                throw "Неверный элемент: '$token'"
            }

            $prefix = $matches[1]
            $first = [int]$matches[2]
            $last = if ($matches[3]) { [int]$matches[3] } else { $first }
            if ($last -lt $first) { throw "Неверный диапазон: '$token'" }

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
                    throw "Такого номера твика нет: $num"
                }
                $actions += [pscustomobject]@{Num=$num; Mode=$mode}
            }
        }
        return $actions
    }

    foreach ($t in $tweaks) {
        $tag = if ($t.Rec) { "[РЕК]" } else { "[ОПЦ]" }
        $enabled = Get-TweakEnabled $t.Num
        $state = if ($enabled) { "[ВКЛ ]" } else { "[выкл]" }
        $color = if ($enabled) { "Green" } elseif ($t.Rec) { "Yellow" } else { "DarkGray" }
        Write-Host ("  {0} {1} [{2,2}] {3}" -f $state, $tag, $t.Num, $t.Desc) -ForegroundColor $color
    }

    $allRec = ($tweaks | Where-Object { $_.Rec }).Num
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [N]  Переключить твик                                             |" -ForegroundColor White
    Write-Host "  | [+N] Включить твик                                      |" -ForegroundColor Green
    Write-Host "  | [-N] Отключить твик / вернуть стандарт                         |" -ForegroundColor Yellow
    Write-Host ("  |  {0,-64}|" -f "Список: 2,-3,+4,5-7,+10-12") -ForegroundColor DarkCyan
    Write-Host "  | [A]  Включить ВСЕ рекомендуемые твики                      |" -ForegroundColor Cyan
    Write-Host "  | [0]  Назад в главное меню                                        |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = (Read-Host).Trim()

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    try {
        $actions = if ($choice -eq "A" -or $choice -eq "a") {
            @($allRec | ForEach-Object { [pscustomobject]@{Num="$_"; Mode="Enable"} })
        } else {
            @(ConvertTo-TweakActions $choice)
        }
    } catch {
        Write-FAIL "Не удалось разобрать список: $($_.Exception.Message)"
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
        $verb = if ($requestedState) { "ВКЛЮЧИТЬ ТВИК" } else { "ОТКЛЮЧИТЬ ТВИК" }
        $plan += [pscustomobject]@{Num=$action.Num; Enabled=$requestedState; Preview="[$verb] [$($action.Num)] $desc"}
    }

    if (-not (Confirm-ActionPreview ($plan.Preview))) { Menu-Registry; return }
    foreach ($item in $plan) { Set-TweakState $item.Num $item.Enabled }
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
    Write-Host "  | Номера переключают задачи: 1,3,5-8                            |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
        Write-FAIL "Не удалось разобрать список: $($_.Exception.Message)"
        Pause-Menu; Menu-Tasks; return
    }

    $plan = @()
    foreach ($t in $selected) {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        if ($forceDisable -and $task.State -eq "Disabled") { continue }
        $enable = if ($forceDisable) { $false } else { $task.State -eq "Disabled" }
        $verb = if ($enable) { "ВКЛЮЧИТЬ" } else { "ОТКЛЮЧИТЬ" }
        $plan += [pscustomobject]@{Task=$t; Enable=$enable; OldState=$task.State; Preview="[$verb] $($t.Name) — $($t.Desc)"}
    }
    if ($plan.Count -eq 0) {
        Write-INFO "Нет задач, состояние которых нужно изменить"
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
            if ($item.Enable -and $task.State -eq "Disabled") { throw "задача осталась отключённой" }
            if (-not $item.Enable -and $task.State -ne "Disabled") { throw "задача осталась включённой" }
            Write-ActionLog -type "Task" -target "$($t.Path)|$($t.Name)" -oldValue $item.OldState -desc $t.Name
            Write-OK "$(if ($item.Enable) { 'Включено' } else { 'Отключено' }): $($t.Name)"
        } catch {
            Write-FAIL "Не удалось изменить $($t.Name): $($_.Exception.Message)"
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 4 - АВТОЗАПУСК
# ============================================================
function Menu-Startup {
    Draw-Header "АВТОЗАПУСК - включение и отключение без удаления"
    Write-Host "  Номера переключают состояние. Отключённые записи хранятся в резервном подразделе реестра." -ForegroundColor DarkGray
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
        Write-INFO "Записей автозапуска и резервных отключённых записей не найдено"
        Pause-Menu; return
    }

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $status = if ($entry.Enabled) { "[ВКЛ ]" } else { "[выкл]" }
        $color = if ($entry.Enabled) { "Green" } else { "DarkGray" }
        $valueText = "$($entry.Value)"
        $short = if ($valueText.Length -gt 45) { $valueText.Substring(0,42) + "..." } else { $valueText }
        Write-Host ("  [{0,2}] {1} [{2,-6}] {3,-25} {4}" -f ($i+1), $status, $entry.Scope, $entry.Name, $short) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Номера переключают записи: 1,3,5-8                            |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                      |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = (Read-Host).Trim()
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    try {
        $selected = @(ConvertTo-NumberList $choice $entries.Count | ForEach-Object { $entries[$_ - 1] })
    } catch {
        Write-FAIL "Не удалось разобрать список: $($_.Exception.Message)"
        Pause-Menu; Menu-Startup; return
    }

    $preview = @($selected | ForEach-Object {
        $verb = if ($_.Enabled) { "ОТКЛЮЧИТЬ" } else { "ВКЛЮЧИТЬ" }
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
            if ($destinationHasValue) { throw "в целевом разделе уже есть запись с таким именем" }
            New-ItemProperty -Path $entry.DestinationPath -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force -ErrorAction Stop | Out-Null
            Remove-ItemProperty -Path $entry.SourcePath -Name $entry.Name -ErrorAction Stop
            $moved = Get-ItemPropertyValue -Path $entry.DestinationPath -Name $entry.Name -ErrorAction Stop
            if ("$moved" -ne "$($entry.Value)") { throw "проверка перемещения не пройдена" }
            Write-ActionLog -type "StartupToggle" -target "$($entry.SourcePath)|$($entry.DestinationPath)|$($entry.Name)" -oldValue $(if ($entry.Enabled) { "Enabled" } else { "Disabled" }) -desc $entry.Name
            Write-OK "$(if ($entry.Enabled) { 'Отключено' } else { 'Включено' }): $($entry.Name)"
        } catch {
            Write-FAIL "Не удалось переключить $($entry.Name): $($_.Exception.Message)"
        }
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
        if (-not (Test-Path $item.Path)) {
            Write-SKIP "Не найдено: $($item.Label)"
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
            Write-INFO "Очищено частично: $($item.Label). Некоторые файлы заняты системой: $($removeErrors.Count)"
        } else {
            Write-OK "Очищено: $($item.Label)"
        }
    }

    $selectedItems = @()
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -eq "A" -or $choice -eq "a") {
        $selectedItems = $items
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $items.Count) {
        $selectedItems = @($items[[int]$choice - 1])
    } else {
        Write-FAIL "Неверный выбор"
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
        Write-Host "  |          Нажмите Q чтобы выйти                        |" -ForegroundColor DarkGray
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
        Write-Host ("  Обновлено: {0}  |  Обновление через 3с...  |  Q для выхода" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor DarkGray

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
    $current = & powercfg /getactivescheme 2>&1
    Write-Host "  $current" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Все доступные схемы:" -ForegroundColor DarkGray
    & powercfg /list 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
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
        $guidPattern = '(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b'
        $schemeLine = & powercfg /list 2>&1 | Where-Object { "$_" -match '(?i)Ultimate Performance|Максимальн.*производитель' } | Select-Object -First 1
        $guid = $null
        if ("$schemeLine" -match $guidPattern) { $guid = $matches[0] }

        if (-not $guid) {
            $duplicateOutput = & powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-FAIL "Не удалось создать схему: $($duplicateOutput -join ' ')"
                Pause-Menu; return
            }
            if (($duplicateOutput -join ' ') -match $guidPattern) { $guid = $matches[0] }
            if ($guid) { Write-OK "Схема Максимальная производительность создана" }
        }

        if (-not $guid) {
            Write-FAIL "Windows не вернула GUID созданной схемы питания"
            Pause-Menu; return
        }

        $activateOutput = & powercfg /setactive $guid 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-FAIL "Не удалось активировать схему: $($activateOutput -join ' ')"
        } else {
            $active = & powercfg /getactivescheme 2>&1
            if (($active -join ' ') -match [regex]::Escape($guid)) {
                Write-OK "Схема Максимальная производительность активирована"
            } else {
                Write-FAIL "Команда выполнена, но активная схема не изменилась"
            }
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
    Write-Host "  Использовался вирусом WannaCry. Для старых NAS он может быть нужен." -ForegroundColor DarkGray
    Write-Host ""

    try {
        $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    } catch {
        Write-FAIL "Не удалось прочитать состояние SMB1: $($_.Exception.Message)"
        Pause-Menu; return
    }
    $status = $smb.State
    $safe = $status -eq "Disabled" -or $status -eq "DisablePending"
    $color = if ($safe) { "Green" } else { "Red" }
    Write-Host ("  Статус SMB1: [ {0} ]" -f $status) -ForegroundColor $color
    Write-Host ""

    if (-not $safe) {
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | SMB1 ВКЛЮЧЁН - это угроза безопасности!                       |" -ForegroundColor Red
        Write-Host "  | [1] Отключить SMB1 СЕЙЧАС                                     |" -ForegroundColor Green
        Write-Host "  | [0] Назад в главное меню                                      |" -ForegroundColor DarkGray
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Выбор: " -ForegroundColor White -NoNewline
        $choice = Read-Host
        if ($choice -eq "1") {
            Write-Host ""
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction Stop | Out-Null
                try {
                    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop | Out-Null
                } catch {
                    Write-INFO "Компонент отключён, но серверную настройку проверить не удалось: $($_.Exception.Message)"
                }
                $after = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
                if ($after.State -eq "Disabled" -or $after.State -eq "DisablePending") {
                    Write-OK "SMB1 отключён. Если статус DisablePending, требуется перезагрузка."
                } else {
                    Write-FAIL "SMB1 остался в состоянии $($after.State)"
                }
            } catch {
                Write-FAIL "Не удалось отключить SMB1: $($_.Exception.Message)"
            }
        }
    } else {
        Write-OK "SMB1 уже отключён."
        if ($status -eq "DisablePending") { Write-INFO "Для завершения нужна перезагрузка." }
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
            if ($null -ne $rel.Wear) {
                $wColor = if ($rel.Wear -gt 80) { "Red" } elseif ($rel.Wear -gt 50) { "Yellow" } else { "Green" }
                Write-Host ("    Износ SSD      : {0}%" -f $rel.Wear) -ForegroundColor $wColor
            }
            if ($null -ne $rel.PowerOnHours) {
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
        $temps = Get-WinToolsCimInstance -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($t in $temps) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            $color = if ($celsius -gt 85) { "Red" } elseif ($celsius -gt 70) { "Yellow" } else { "Green" }
            Write-Host ("  Термозона: {0} C" -f $celsius) -ForegroundColor $color
            $tempFound = $true
        }
    } catch {
        $tempFound = $false
    }
    if (-not $tempFound) {
        Write-INFO "Встроенные датчики не сообщили температуру (частое дело на ноутбуках)"
    }
    $cpuLoad = (Get-WinToolsCimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-Host ("  Текущая загрузка ЦП: {0}%" -f $cpuLoad) -ForegroundColor White
    Write-Host ""

    Write-Host "  --- ПРОВЕРКА ОБНОВЛЕНИЙ ДРАЙВЕРОВ ---" -ForegroundColor Cyan
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    try {
        if (-not $wu) { throw "служба Windows Update не найдена" }
        if ($wu.StartType -eq "Disabled") {
            Set-Service -Name wuauserv -StartupType Manual -ErrorAction Stop
            Write-ActionLog -type "Service" -target "wuauserv" -oldValue "Disabled|Stopped" -desc "Windows Update для проверки драйверов"
            Write-INFO "Служба Windows Update включена для проверки"
        }
        Start-Service -Name wuauserv -ErrorAction Stop
        & UsoClient StartScan 2>$null
        if ($LASTEXITCODE -ne 0) { throw "UsoClient завершился с кодом $LASTEXITCODE" }
        Write-OK "Проверка драйверов запущена через Windows Update"
        Write-Host "  Смотри: Параметры -> Центр обновления -> Дополнительные параметры -> Необязательные обновления" -ForegroundColor White
    } catch {
        Write-FAIL "Не удалось запустить проверку: $($_.Exception.Message)"
        Write-INFO "Проверь вручную в Параметры -> Центр обновления Windows"
    }
    Write-Host ""

    Write-Host "  --- ПРОВЕРКА ШРИФТОВ ---" -ForegroundColor Cyan
    $winInstallDate = (Get-WinToolsCimInstance Win32_OperatingSystem).InstallDate
    if ($winInstallDate -isnot [datetime]) {
        $winInstallDate = [Management.ManagementDateTimeConverter]::ToDateTime($winInstallDate)
    }
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

    $cpu = Get-WinToolsCimInstance Win32_Processor | Select-Object -First 1
    Write-Host ("  Процессор : {0}" -f $cpu.Name) -ForegroundColor White

    $gpus = Get-WinToolsCimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Basic|Remote" }
    foreach ($g in $gpus) {
        Write-Host ("  Видео     : {0}" -f $g.Name) -ForegroundColor White
    }

    $wifi = Get-WinToolsCimInstance Win32_NetworkAdapter | Where-Object { $_.Name -match "Wireless|Wi-Fi|WiFi" -and $_.Manufacturer -notmatch "Microsoft" } | Select-Object -First 1
    if ($wifi) { Write-Host ("  Wi-Fi     : {0}" -f $wifi.Name) -ForegroundColor White }

    $audio = Get-WinToolsCimInstance Win32_SoundDevice | Select-Object -First 1
    if ($audio) { Write-Host ("  Аудио     : {0}" -f $audio.Name) -ForegroundColor White }

    $sys = Get-WinToolsCimInstance Win32_ComputerSystem
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
        try {
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-OK "Лимит снят"
        } catch {
            Write-FAIL "Не удалось изменить лимит: $($_.Exception.Message)"
        }
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
        try {
            Remove-Item $Global:LogPath -Force -ErrorAction Stop
            "Timestamp,Type,Target,OldValue,Desc" | Out-File -FilePath $Global:LogPath -Encoding UTF8 -ErrorAction Stop
            Write-OK "Журнал очищен"
        } catch {
            Write-FAIL "Не удалось очистить журнал: $($_.Exception.Message)"
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
                    if ($e.OldValue -eq "NULL") { Write-SKIP "Пропуск: неизвестное состояние для $($e.Target)" }
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
                        if ("$($restored.StartType)" -ne "$oldStartType") { throw "тип запуска не восстановлен" }
                        Write-OK "Служба $($e.Target) возвращена: $oldStartType / $oldStatus"
                    }
                } catch { Write-FAIL "Не удалось отменить службу $($e.Target): $($_.Exception.Message)" }
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
                    if ($e.OldValue -eq "Disabled" -and $task.State -ne "Disabled") { throw "задача не была отключена обратно" }
                    if ($e.OldValue -ne "Disabled" -and $task.State -eq "Disabled") { throw "задача не была включена обратно" }
                    Write-OK "Состояние задачи возвращено: $taskName → $($e.OldValue)"
                } catch { Write-FAIL "Не удалось отменить задачу $($e.Target): $($_.Exception.Message)" }
            }
            "Registry" {
                try {
                    $parts2 = $e.Target -split "\|", 2
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") {
                        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
                        $stillExists = $true
                        try { $null = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction Stop } catch { $stillExists = $false }
                        if ($stillExists) { throw "параметр всё ещё существует" }
                        Write-OK "Параметр реестра удалён: $regName"
                    } else {
                        Set-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -ErrorAction Stop
                        $actual = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction Stop
                        if ("$actual" -ne "$($e.OldValue)") { throw "старое значение не восстановлено" }
                        Write-OK "Реестр $regName возвращён: $($e.OldValue)"
                    }
                } catch { Write-FAIL "Не удалось отменить реестр $($e.Target): $($_.Exception.Message)" }
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
                    Write-OK "Состояние автозапуска возвращено: $regName"
                } catch { Write-FAIL "Не удалось отменить переключение $($e.Target): $($_.Exception.Message)" }
            }
            "Startup" {
                try {
                    $parts2 = $e.Target -split "\|", 2
                    $regPath = $parts2[0]; $regName = $parts2[1]
                    if ($e.OldValue -eq "NULL") { throw "в журнале нет старого значения" }
                    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -Path $regPath -Name $regName -Value $e.OldValue -PropertyType String -Force -ErrorAction Stop | Out-Null
                    Write-OK "Автозапуск возвращён: $regName"
                } catch { Write-FAIL "Не удалось вернуть автозапуск $($e.Target): $($_.Exception.Message)" }
            }
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
                Write-OK "Удалено: $appName"
            } else {
                $detail = if ($removeErrors.Count) { $removeErrors[0].Exception.Message } else { "пакет всё ещё установлен" }
                Write-FAIL "Не удалось удалить ${appName}: $detail"
            }
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
    Write-Host "  Закроет выбранные браузеры и очистит кэш всех профилей." -ForegroundColor DarkGray
    Write-Host "  Пароли, историю и закладки не трогает." -ForegroundColor DarkGray
    Write-Host ""

    $browsers = @(
        @{Name="Brave";  Process="brave";  Root="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"},
        @{Name="Chrome"; Process="chrome"; Root="$env:LOCALAPPDATA\Google\Chrome\User Data"},
        @{Name="Edge";   Process="msedge"; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data"}
    )
    # Keep one property name for all entries (the old Edge entry used Path by mistake in some forks).
    $browsers[2].Root = $browsers[2].Path

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
        $sizeStr = if ($paths.Count -eq 0) { "не найден" } elseif ($size -gt 0) { "$size ГБ" } else { "< 0.01 ГБ" }
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

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    $selected = @()
    if ($choice -eq "A" -or $choice -eq "a") { $selected = $browsers }
    elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $browsers.Count) { $selected = @($browsers[[int]$choice - 1]) }
    else { Write-FAIL "Неверный выбор"; Pause-Menu; return }

    Write-Host ""
    foreach ($b in $selected) {
        Stop-Process -Name $b.Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $paths = @(Get-BrowserCachePaths $b)
        if ($paths.Count -eq 0) {
            Write-SKIP "$($b.Name): кэш не найден"
            continue
        }

        $removeErrors = @()
        foreach ($path in $paths) {
            Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +removeErrors
        }
        if ($removeErrors.Count -gt 0) {
            Write-INFO "Кэш $($b.Name) очищен частично; занятых файлов: $($removeErrors.Count)"
        } else {
            Write-OK "Кэш всех профилей $($b.Name) очищен"
        }
    }
    Pause-Menu
}

# ============================================================
# МЕНЮ 15 - КОСМЕТИКА WINDOWS
# ============================================================
function Menu-Cosmetics {
    Draw-Header "КОСМЕТИКА WINDOWS"

    $classicMenuRoot = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $classicMenuPath = "$classicMenuRoot\InprocServer32"
    $classicEnabled = Test-Path $classicMenuPath

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $hideExt = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).HideFileExt
    $hideHidden = (Get-ItemProperty $advPath -ErrorAction SilentlyContinue).Hidden

    if ($Script:IsWin11) {
        Write-Host ("  [1] Классическое контекстное меню (ПКМ)   статус: {0}" -f $(if($classicEnabled){"ВКЛ"}else{"выкл (Win11 по умолч.)"})) -ForegroundColor $(if($classicEnabled){"Green"}else{"White"})
    } else {
        Write-Host "  [1] Классическое контекстное меню - только для Windows 11" -ForegroundColor DarkGray
    }
    Write-Host ("  [2] Показ расширений файлов (.txt, .exe)   статус: {0}" -f $(if($hideExt -eq 0){"ВКЛ"}else{"выкл"})) -ForegroundColor $(if($hideExt -eq 0){"Green"}else{"White"})
    Write-Host ("  [3] Показ скрытых файлов и папок           статус: {0}" -f $(if($hideHidden -eq 1){"ВКЛ"}else{"выкл"})) -ForegroundColor $(if($hideHidden -eq 1){"Green"}else{"White"})
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    if ($Script:IsWin11) { Write-Host "  | [1] Переключить классическое меню ПКМ                          |" -ForegroundColor White }
    Write-Host "  | [2] Переключить показ расширений файлов                        |" -ForegroundColor White
    Write-Host "  | [3] Переключить показ скрытых файлов                           |" -ForegroundColor White
    Write-Host "  | [A] Включить ВСЕ доступное                                     |" -ForegroundColor Cyan
    Write-Host "  | [0] Назад в главное меню                                       |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Restart-ExplorerShell {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Process explorer.exe -ErrorAction Stop
    }

    function Toggle-ClassicMenu {
        if (-not $Script:IsWin11) { Write-SKIP "Доступно только на Windows 11"; return }
        try {
            if ($classicEnabled) {
                Remove-Item -Path $classicMenuRoot -Recurse -Force -ErrorAction Stop
                if (Test-Path $classicMenuRoot) { throw "раздел реестра не удалён" }
                Write-OK "Классическое меню выключено"
            } else {
                Set-RegLogged $classicMenuPath "(default)" "" "String" "Classic Context Menu"
                if (-not (Test-Path $classicMenuPath)) { throw "раздел реестра не создан" }
                Write-OK "Классическое контекстное меню включено"
            }
            Restart-ExplorerShell
        } catch {
            Write-FAIL "Не удалось переключить контекстное меню: $($_.Exception.Message)"
        }
    }

    function Toggle-FileExt {
        $new = if ($hideExt -eq 0) { 1 } else { 0 }
        try {
            Set-RegLogged $advPath "HideFileExt" $new "DWord" "Показ расширений"
            Restart-ExplorerShell
            if ($new -eq 0) { Write-OK "Расширения файлов показываются" } else { Write-OK "Расширения скрыты" }
        } catch {
            Write-FAIL "Не удалось изменить показ расширений: $($_.Exception.Message)"
        }
    }

    function Toggle-HiddenFiles {
        $new = if ($hideHidden -eq 1) { 2 } else { 1 }
        try {
            Set-RegLogged $advPath "Hidden" $new "DWord" "Скрытые файлы"
            Restart-ExplorerShell
            if ($new -eq 1) { Write-OK "Скрытые файлы показываются" } else { Write-OK "Скрытые файлы скрыты" }
        } catch {
            Write-FAIL "Не удалось изменить показ скрытых файлов: $($_.Exception.Message)"
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
        default { Write-FAIL "Неверный выбор" }
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
    if (-not $quiet) { Write-OK "Снимок создан: $file" }
    return $file
}

function Import-WinToolsSnapshot($path) {
    if (-not (Test-Path $path)) { Write-FAIL "Файл не найден: $path"; return $false }
    try { $snapshot = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Write-FAIL "Не удалось прочитать снимок: $($_.Exception.Message)"; return $false }
    if ([int]$snapshot.FormatVersion -ne 1) { Write-FAIL "Неподдерживаемый формат снимка: $($snapshot.FormatVersion)"; return $false }

    $preview = @(
        "Снимок: $($snapshot.Created)",
        "Параметров реестра: $(@($snapshot.Registry).Count)",
        "Служб: $(@($snapshot.Services).Count)",
        "Задач: $(@($snapshot.Tasks).Count)",
        "Записей автозапуска: $(@($snapshot.Startup).Count)",
        "Записи автозапуска в реестре будут точно восстановлены по снимку"
    )
    if ($snapshot.Computer -and $snapshot.Computer -ne $env:COMPUTERNAME) {
        $preview += "ВНИМАНИЕ: снимок другого компьютера: $($snapshot.Computer)"
    }
    if ($snapshot.User -and $snapshot.User -ne $env:USERNAME) {
        $preview += "ВНИМАНИЕ: снимок другого пользователя: $($snapshot.User)"
    }
    if (-not (Confirm-ActionPreview $preview)) { return $false }

    $preBackup = Export-WinToolsSnapshot -reason "before_import" -quiet
    Write-INFO "Снимок перед импортом: $preBackup"
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
    if ($failed -eq 0) { Write-OK "Снимок восстановлен. Успешных операций: $ok"; return $true }
    Write-FAIL "Импорт завершён частично: успешно $ok, ошибок $failed"
    return $false
}
# ============================================================
# MENU 16 - SYSTEM PROFILES
# ============================================================
function Menu-Profiles {
    Draw-Header "СИСТЕМНЫЕ ПРОФИЛИ - безопасные наборы настроек"
    $hasBattery = $null -ne (Get-WinToolsCimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1)
    $recommended = if ($hasBattery) { 2 } else { 1 }
    $profiles = @(
        @{N=1; Name="Игровой ПК"; Desc="Максимум производительности для настольного ПК"; Power="SCHEME_MIN"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",2,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",1,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",0,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",0,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",1,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",1,"DWord","Game Mode")
        )},
        @{N=2; Name="Игровой ноутбук"; Desc="Игровые настройки без отключения энергосбережения"; Power="SCHEME_BALANCED"; Values=@(
            @("HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers","HwSchMode",2,"DWord","GPU Scheduling"),
            @("HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling","PowerThrottlingOff",0,"DWord","Power Throttling"),
            @("HKCU:\System\GameConfigStore","GameDVR_Enabled",0,"DWord","Game DVR"),
            @("HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR","AppCaptureEnabled",0,"DWord","App Capture"),
            @("HKCU:\Software\Microsoft\GameBar","AllowAutoGameMode",1,"DWord","Game Mode"),
            @("HKCU:\Software\Microsoft\GameBar","AutoGameModeEnabled",1,"DWord","Game Mode")
        )},
        @{N=3; Name="Сбалансированный"; Desc="Стандартное питание и минимум спорных изменений"; Power="SCHEME_BALANCED"; Values=@(
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
        @{N=4; Name="Приватность"; Desc="Телеметрия, реклама, советы, веб-поиск и виджеты"; Power=$null; Values=@(
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
        @{N=5; Name="Стандарт Windows"; Desc="Вернуть стандартные значения управляемых профилями параметров"; Power="SCHEME_BALANCED"; Values=@(
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
        $mark = if ($selectedProfile.N -eq $recommended) { " <<< РЕКОМЕНДУЕТСЯ ДЛЯ ЭТОГО УСТРОЙСТВА" } else { "" }
        Write-Host ("  [{0}] {1,-20} {2}{3}" -f $selectedProfile.N,$selectedProfile.Name,$selectedProfile.Desc,$mark) -ForegroundColor $(if($mark){"Green"}else{"White"})
    }
    Write-Host "  [0] Назад" -ForegroundColor DarkGray
    Write-Host "`n  Выбор: " -NoNewline
    $choice=(Read-Host).Trim()
    if($choice -eq "0"){return}
    $selectedProfile=$profiles|Where-Object{"$($_.N)" -eq $choice}|Select-Object -First 1
    if(-not $selectedProfile){Write-FAIL "Неверный профиль";Pause-Menu;return}
    $preview=@("Профиль: $($selectedProfile.Name)") + @($selectedProfile.Values|ForEach-Object{"[РЕЕСТР] $($_[4]) → $($_[2])"})
    if($selectedProfile.Power){$preview += "[ПИТАНИЕ] $($selectedProfile.Power)"}
    if(-not(Confirm-ActionPreview $preview)){Menu-Profiles;return}
    $backup=Export-WinToolsSnapshot -reason "before_profile_$($selectedProfile.N)" -quiet
    Write-INFO "Резервный снимок: $backup"
    $profileFailures = 0
    foreach ($v in $selectedProfile.Values) {
        try { Set-RegLogged $v[0] $v[1] $v[2] $v[3] $v[4] }
        catch { $profileFailures++; Write-FAIL "$($v[4]): $($_.Exception.Message)" }
    }
    if ($selectedProfile.Power) {
        & powercfg /setactive $selectedProfile.Power 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $profileFailures++; Write-FAIL "Не удалось включить схему питания: код $LASTEXITCODE" }
    }
    if ($profileFailures -eq 0) { Write-OK "Профиль применён: $($selectedProfile.Name)" }
    else { Write-FAIL "Профиль завершён с ошибками: $profileFailures. Используй резервный снимок для отката." }
    Pause-Menu
}
# ============================================================
# MENU 17 - EXPORT / IMPORT
# ============================================================
function Menu-Snapshots {
    Draw-Header "ЭКСПОРТ / ИМПОРТ - снимки настроек"
    $folder="$env:ProgramData\WinTools\Snapshots"
    Write-Host "  [1] Создать полный снимок настроек" -ForegroundColor Green
    Write-Host "  [2] Импортировать последний снимок" -ForegroundColor White
    Write-Host "  [3] Импортировать файл по пути" -ForegroundColor White
    Write-Host "  [4] Показать сохранённые снимки" -ForegroundColor White
    Write-Host "  [0] Назад" -ForegroundColor DarkGray
    Write-Host "`n  Выбор: " -NoNewline
    $choice=(Read-Host).Trim()
    switch($choice){
        "1" { try{$path=Export-WinToolsSnapshot -reason "manual";Write-OK "Снимок сохранён: $path"}catch{Write-FAIL $_.Exception.Message} }
        "2" { $last=Get-ChildItem $folder -Filter "*.json" -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($last){if(-not(Import-WinToolsSnapshot $last.FullName)){Menu-Snapshots;return}}else{Write-INFO "Снимков нет"} }
        "3" { Write-Host "  Путь: " -NoNewline;$path=Read-Host;if(-not(Import-WinToolsSnapshot $path)){Menu-Snapshots;return} }
        "4" { Get-ChildItem $folder -Filter "*.json" -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|ForEach-Object{Write-Host("  {0}  {1:N1} KB" -f $_.FullName,($_.Length/1KB))} }
        "0" { return }
    }
    Pause-Menu
}

# ============================================================
# MENU 18 - DIAGNOSTICS
# ============================================================
function Menu-Diagnostics {
    Draw-Header "ДИАГНОСТИКА - полный отчёт без изменения системы"
    Write-INFO "Собираю данные, это может занять несколько секунд..."
    $lines = New-Object System.Collections.Generic.List[string]
    $os=Get-WinToolsCimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs=Get-WinToolsCimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu=Get-WinToolsCimInstance Win32_Processor -ErrorAction SilentlyContinue|Select-Object -First 1
    $gpus=@(Get-WinToolsCimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object{$_.Name -notmatch 'Basic|Remote'})
    $uptime=if($os.LastBootUpTime){[math]::Round(((Get-Date)-[datetime]$os.LastBootUpTime).TotalHours,1)}else{"?"}
    $lines.Add("WINTOOLS DIAGNOSTIC REPORT")
    $lines.Add("Создан: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("WinTools: $Script:WinToolsVersion")
    $lines.Add("ОС: $($os.Caption), build $($os.BuildNumber), $($os.OSArchitecture)")
    $lines.Add("Компьютер: $($cs.Manufacturer) $($cs.Model)")
    $lines.Add("Процессор: $($cpu.Name)")
    $lines.Add("ОЗУ: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB")
    $lines.Add("Видеокарты: $(($gpus.Name) -join '; ')")
    $lines.Add("Аптайм: $uptime ч")
    $lines.Add("")
    $lines.Add("--- ДИСКИ ---")
    try { Get-PhysicalDisk -ErrorAction Stop|ForEach-Object{$lines.Add("$($_.FriendlyName): $($_.MediaType), Health=$($_.HealthStatus), Size=$([math]::Round($_.Size/1GB)) GB")} } catch {$lines.Add("Физические диски: данные недоступны")}
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{$lines.Add("$($_.Name): свободно $([math]::Round($_.Free/1GB,1)) / $([math]::Round(($_.Used+$_.Free)/1GB,1)) GB")}
    $lines.Add("")
    $lines.Add("--- БЕЗОПАСНОСТЬ И ОБНОВЛЕНИЯ ---")
    $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
    $lines.Add("Windows Update: $($wu.Status), StartType=$($wu.StartType)")
    if(Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue){try{$mp=Get-MpComputerStatus -ErrorAction Stop;$lines.Add("Defender: Antivirus=$($mp.AntivirusEnabled), RealTime=$($mp.RealTimeProtectionEnabled), Signatures=$($mp.AntivirusSignatureLastUpdated)")}catch{$lines.Add("Defender: данные недоступны")}}
    $pending=(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
    $lines.Add("Ожидается перезагрузка: $pending")
    $lines.Add("")
    $lines.Add("--- УСТРОЙСТВА И ОШИБКИ ---")
    if(Get-Command Get-PnpDevice -ErrorAction SilentlyContinue){$bad=@(Get-PnpDevice -ErrorAction SilentlyContinue|Where-Object{$_.Status -ne 'OK'});$lines.Add("Проблемных устройств: $($bad.Count)");$bad|Select-Object -First 20|ForEach-Object{$lines.Add("  $($_.Status): $($_.FriendlyName)")}}
    try{$events=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddHours(-24)} -MaxEvents 20 -ErrorAction Stop);$lines.Add("Критических/ошибочных событий за 24ч: $($events.Count)");$events|Select-Object -First 10|ForEach-Object{$lines.Add("  $($_.TimeCreated) [$($_.Id)] $($_.ProviderName): $(($_.Message -replace '[\r\n]+',' ') | Select-Object -First 1)")}}catch{$lines.Add("Системные события: не удалось прочитать")}
    $disabled=@(Get-Service -ErrorAction SilentlyContinue|Where-Object{$_.StartType -eq 'Disabled'})
    $lines.Add("Отключённых служб: $($disabled.Count)")
    $folder="$env:ProgramData\WinTools\Reports";if(-not(Test-Path $folder)){New-Item $folder -ItemType Directory -Force|Out-Null}
    $file=Join-Path $folder ("diagnostic_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines|Set-Content $file -Encoding UTF8
    Clear-Host;$lines|ForEach-Object{Write-Host "  $_"}
    Write-OK "Отчёт сохранён: $file"
    Pause-Menu
}
# ============================================================
# MENU 19 - APPLICATION MANAGER
# ============================================================
function Menu-Applications {
    Draw-Header "МЕНЕДЖЕР ПРИЛОЖЕНИЙ - установка через winget"
    if(-not(Get-Command winget -ErrorAction SilentlyContinue)){Write-FAIL "winget не найден. Установи App Installer из Microsoft Store.";Pause-Menu;return}
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
        @{Key="G";Name="Игры";Nums=1,5,6,7}, @{Key="I";Name="Интернет";Nums=8,9,10},
        @{Key="S";Name="Безопасность";Nums=11,12}, @{Key="B";Name="Базовый";Nums=1,2,3,4}
    )
    Write-Host "  Профили:" -ForegroundColor Cyan;$packs|ForEach-Object{Write-Host("  [{0}] {1}: {2}" -f $_.Key,$_.Name,(($_.Nums|ForEach-Object{$apps[$_-1].Name}) -join ', '))}
    Write-Host "`n  Приложения:" -ForegroundColor Cyan;$apps|ForEach-Object{Write-Host("  [{0,2}] {1,-24} {2}" -f $_.N,$_.Name,$_.Id)}
    Write-Host "`n  [U] Обновить все установленные приложения" -ForegroundColor Green
    Write-Host "  [0] Назад`n  Выбор профиля или номера (1,3,5-7): " -NoNewline
    $choice=(Read-Host).Trim();if($choice -eq '0'){return}
    if($choice -match '^(?i:u)$'){
        if(-not(Confirm-ActionPreview @("[WINGET] Обновить все приложения"))){Menu-Applications;return}
        & winget upgrade --all --accept-package-agreements --accept-source-agreements --silent
        if($LASTEXITCODE -eq 0){Write-OK "Обновление завершено"}else{Write-FAIL "winget завершился с кодом $LASTEXITCODE"}
        Pause-Menu;return
    }
    $pack=$packs|Where-Object{$_.Key -eq $choice.ToUpper()}|Select-Object -First 1
    try{$selected=if($pack){@($pack.Nums|ForEach-Object{$apps[$_-1]})}else{@(ConvertTo-NumberList $choice $apps.Count|ForEach-Object{$apps[$_-1]})}}catch{Write-FAIL $_.Exception.Message;Pause-Menu;return}
    if(-not(Confirm-ActionPreview @($selected|ForEach-Object{"[УСТАНОВИТЬ] $($_.Name) ($($_.Id))"}))){Menu-Applications;return}
    foreach($app in $selected){Write-INFO "Установка $($app.Name)...";& winget install --id $app.Id --exact --accept-package-agreements --accept-source-agreements --silent;if($LASTEXITCODE -eq 0){Write-OK "$($app.Name): готово"}else{Write-FAIL "$($app.Name): код $LASTEXITCODE"}}
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
    if (-not $installRoot) { Write-FAIL "Автообновление доступно при запуске из локальной папки"; return $false }
    $files = @($manifest.files)
    if ($files.Count -eq 0) { Write-FAIL "Манифест обновления не содержит файлов"; return $false }

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

        Write-OK "WinTools обновлён до версии: $($manifest.version)"
        Write-INFO "Резервная копия: $backup"
        Write-INFO "Перезапусти WinTools, чтобы использовать новую версию"
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
            if ($rollbackFailures -eq 0) { Write-INFO "Неудачное обновление отменено; исходные файлы восстановлены" }
            else { Write-FAIL "Откат не завершён для файлов: $rollbackFailures. Резервная копия: $backup" }
        }
        Write-FAIL "Ошибка обновления: $failure"
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
    if(-not $manifest){if(-not $startupCheck){Write-INFO "Не удалось проверить обновления"};return}
    try { $newer = [version]$manifest.version -gt [version]$Script:WinToolsVersion }
    catch { if (-not $startupCheck) { Write-FAIL "Некорректная версия в манифесте обновления" }; return }
    if(-not $newer){if(-not $startupCheck){Write-OK "Установлена последняя версия: $Script:WinToolsVersion"};return}
    Write-Host "";Write-Host "  Доступно обновление: $Script:WinToolsVersion → $($manifest.version)" -ForegroundColor Green
    $notes=if($Script:WinToolsLanguage -eq 'ru'){$manifest.notes_ru}else{$manifest.notes_en};@($notes)|ForEach-Object{Write-Host "  • $_" -ForegroundColor White}
    Write-Host "  [U/Y] Обновить сейчас   [L/N/Enter] Позже: " -NoNewline -ForegroundColor Yellow
    $answer=(Read-Host).Trim()
    if($answer -match '^(?i:u|y|yes|д|да)$'){$null=Invoke-WinToolsUpdate $manifest}else{Write-INFO "Обновление отложено. Его можно запустить из пункта [20]"}
}
function Menu-Update {
    Draw-Header "ОБНОВЛЕНИЕ WINTOOLS"
    Write-Host "  Текущая версия: $Script:WinToolsVersion"
    Write-Host "  [1] Проверить обновления сейчас" -ForegroundColor Green
    Write-Host "  [0] Назад"
    Write-Host "`n  Выбор: " -NoNewline
    $choice=Read-Host;if($choice -eq '1'){Test-WinToolsUpdate}else{return};Pause-Menu
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
        Write-Host "  | 16  |  Профили системы          |  Игры, баланс, приватность       |" -ForegroundColor Green
        Write-Host "  | 17  |  Экспорт / импорт         |  Снимки конфигурации JSON        |" -ForegroundColor Magenta
        Write-Host "  | 18  |  Диагностика              |  Полный отчёт без изменений      |" -ForegroundColor Cyan
        Write-Host "  | 19  |  Менеджер приложений      |  Пакеты Games/Internet/Security  |" -ForegroundColor Yellow
        Write-Host "  | 20  |  Обновление WinTools      |  Проверить новую версию          |" -ForegroundColor White
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Выход                    |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  СОВЕТ: Сначала [11] точка восстановления, потом [1] Службы -> [A]" -ForegroundColor DarkCyan
        Write-Host "  ВЕРСИЯ WINDOWS: $Script:WinVerName | WINTOOLS: $Script:WinToolsVersion" -ForegroundColor DarkCyan
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
