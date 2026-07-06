# WinTools - Оптимизация Windows
# Запускать от имени Администратора

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ОШИБКА: Запустите от имени Администратора!" -ForegroundColor Red
    Start-Sleep 3; exit
}

function Write-OK($msg)   { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [-] $msg" -ForegroundColor DarkGray }
function Write-INFO($msg) { Write-Host "  [*] $msg" -ForegroundColor Yellow }

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
        Stop-Service -Name $found.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $found.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "Отключено: $label"
    } else {
        Write-SKIP "Уже отключено: $label"
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
# МЕНЮ 1 - СЛУЖБЫ (индивидуальный выбор)
# ============================================================
function Menu-Services {
    Draw-Header "СЛУЖБЫ - выбери что отключить, каждая с описанием"

    # Плоский список всех служб: Name = имя службы в Windows, Desc = что делает, Rec = рекомендуется ли отключать
    $svcList = @(
        @{N="DiagTrack";              Desc="Телеметрия - собирает данные об использовании ПК и шлёт в Microsoft"},
        @{N="dmwappushservice";       Desc="Приём push-сообщений для телеметрии"},
        @{N="DoSvc";                  Desc="Раздаёт обновления другим компьютерам через твой интернет (P2P)"},
        @{N="DusmSvc";                Desc="Считает сколько трафика ты израсходовал"},
        @{N="XblAuthManager";         Desc="Авторизация в Xbox Live"},
        @{N="XblGameSave";            Desc="Облачные сохранения игр Xbox"},
        @{N="XboxGipSvc";             Desc="Управление аксессуарами Xbox (геймпады)"},
        @{N="XboxNetApiSvc";          Desc="Сетевые функции Xbox (многопользовательские игры через MS)"},
        @{N="TermService";            Desc="Позволяет подключаться к этому ПК удалённо (RDP)"},
        @{N="UmRdpService";           Desc="Часть удалённого рабочего стола - перенаправление портов"},
        @{N="SessionEnv";             Desc="Настройка сервера удалённых рабочих столов"},
        @{N="WinRM";                  Desc="Удалённое управление Windows через PowerShell с другого ПК"},
        @{N="RemoteRegistry";         Desc="Позволяет менять твой реестр удалённо с другого ПК"},
        @{N="vmicguestinterface";     Desc="Часть Hyper-V - интерфейс гостевой ОС в виртуалке"},
        @{N="vmicheartbeat";          Desc="Часть Hyper-V - проверка что виртуалка жива"},
        @{N="vmickvpexchange";        Desc="Часть Hyper-V - обмен данными с виртуалкой"},
        @{N="vmicrdv";                Desc="Часть Hyper-V - удалённый рабочий стол в виртуалке"},
        @{N="vmicshutdown";           Desc="Часть Hyper-V - выключение виртуалки из хоста"},
        @{N="vmictimesync";           Desc="Часть Hyper-V - синхронизация времени с виртуалкой"},
        @{N="vmicvmsession";          Desc="Часть Hyper-V - PowerShell напрямую в виртуалку"},
        @{N="vmicvss";                Desc="Часть Hyper-V - теневые копии для виртуалки"},
        @{N="HvHost";                 Desc="Хост-служба Hyper-V (нужна только если пользуешься виртуалками)"},
        @{N="Spooler";                Desc="Диспетчер печати - без него не работает ни один принтер"},
        @{N="PrintNotify";            Desc="Уведомления о принтере (застрял лист бумаги и т.п.)"},
        @{N="PrintWorkflowUserSvc";   Desc="Дополнительные функции печати из приложений Store"},
        @{N="LanmanServer";           Desc="Общий доступ к папкам/файлам этого ПК по локальной сети"},
        @{N="lltdsvc";                Desc="Показывает схему устройств в локальной сети (карта сети)"},
        @{N="lmhosts";                Desc="Старый протокол поиска компьютеров по имени (NetBIOS)"},
        @{N="FDResPub";               Desc="Публикует этот ПК как доступный для обнаружения в сети"},
        @{N="fdPHost";                Desc="Помогает находить устройства в локальной сети (принтеры и т.д.)"},
        @{N="SSDPSRV";                Desc="Обнаружение UPnP устройств (роутеры, медиаплееры) в сети"},
        @{N="upnphost";               Desc="Работа с UPnP устройствами (автоматическое пробрасывание портов)"},
        @{N="p2pimsvc";               Desc="Одноранговая сеть - устаревшая технология для групповых чатов"},
        @{N="p2psvc";                 Desc="Группировка сетевых участников (тоже устаревшее P2P)"},
        @{N="PNRPAutoReg";            Desc="Публикация имени компьютера в одноранговой сети"},
        @{N="PNRPsvc";                Desc="Протокол разрешения имён в одноранговой сети"},
        @{N="DPS";                    Desc="Диагностика проблем и их автоматическое устранение"},
        @{N="WdiServiceHost";         Desc="Узел для диагностических инструментов Windows"},
        @{N="WdiSystemHost";          Desc="Системный узел диагностики (перезагрузки при сбоях и т.п.)"},
        @{N="WerSvc";                 Desc="Отправляет отчёты о сбоях программ в Microsoft"},
        @{N="wercplsupport";          Desc="Интерфейс для просмотра отчётов об ошибках в панели управления"},
        @{N="PcaSvc";                 Desc="Проверяет совместимость старых программ с текущей Windows"},
        @{N="diagnosticshub.standardcollector.service"; Desc="Сборщик диагностических данных для разработчиков"},
        @{N="TrkWks";                 Desc="Следит за ярлыками файлов если их перемещают по сети"},
        @{N="FontCache";              Desc="Кэширует шрифты для более быстрой отрисовки текста"},
        @{N="ShellHWDetection";       Desc="Показывает окно 'Что делать с диском' при вставке флешки/CD"},
        @{N="MapsBroker";             Desc="Скачивание офлайн-карт для приложения Карты"},
        @{N="PhoneSvc";               Desc="Связь Windows с телефоном (звонки/смс на ПК)"},
        @{N="WFDSConMgrSvc";          Desc="Wi-Fi Direct - прямая передача файлов между устройствами по Wi-Fi"},
        @{N="MessagingService";       Desc="Отправка SMS через это устройство"},
        @{N="icssvc";                 Desc="Раздача интернета с этого ПК как точки доступа (мобильный хот-спот)"},
        @{N="SmsRouter";              Desc="Маршрутизация SMS-сообщений между приложениями"},
        @{N="WiaRpc";                 Desc="События подключения камер и сканеров"},
        @{N="stisvc";                 Desc="Загрузка фото с камер и сканеров (Windows Image Acquisition)"},
        @{N="Netlogon";               Desc="Вход в корпоративный домен (нужно только на работе в офисе)"},
        @{N="CDPSvc";                 Desc="Платформа для синхронизации с другими твоими устройствами (телефон и т.п.)"},
        @{N="BcastDVRUserService";    Desc="Фоновая запись игрового процесса для Xbox Game Bar"},
        @{N="CaptureService";         Desc="Захват экрана для Game Bar и других системных инструментов"},
        @{N="NaturalAuthentication";  Desc="Вход по лицу (Windows Hello Face) - не путать с отпечатком пальца"},
        @{N="GraphicsPerfSvc";        Desc="Мониторинг производительности видеокарты в фоне"},
        @{N="WpnService";             Desc="Push-уведомления от приложений (типа push с телефона)"},
        @{N="RetailDemo";             Desc="Демо-режим для витрин магазинов - не нужен на обычном ПК"},
        @{N="SysMain";                Desc="Superfetch - предзагружает часто используемые программы в память (полезно на HDD, бесполезно на SSD)"},
        @{N="WSearch";                Desc="Индексирование файлов для быстрого поиска через Win+S"},
        @{N="WbioSrvc";               Desc="Биометрия - вход по отпечатку пальца или лицу"},
        @{N="RmSvc";                  Desc="Управление радиомодулями - переключение Wi-Fi и Bluetooth"},
        @{N="wscsvc";                 Desc="Центр безопасности Windows - показывает статус антивируса и фаервола"}
    )

    Write-Host "  Ниже список служб с описанием. Зелёным - можно смело отключать." -ForegroundColor DarkGray
    Write-Host "  Жёлтым - подумай сам, нужна ли тебе эта функция." -ForegroundColor DarkGray
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
        # Разбираем ввод: числа через запятую и диапазоны через дефис
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

    Write-Host "  [РЕК] [ 1] Планировщик GPU включён       Меньше задержек в играх" -ForegroundColor Green
    Write-Host "  [РЕК] [ 2] Алгоритм Нейгла выключен      Меньше пинг в играх" -ForegroundColor Green
    Write-Host "  [РЕК] [ 3] Power Throttling выключен      ЦП не душится в фоне" -ForegroundColor Green
    Write-Host "  [РЕК] [ 4] Game DVR выключен              Убирает оверхед записи Xbox" -ForegroundColor Green
    Write-Host "  [РЕК] [ 5] Визуальные эффекты минимум     Быстрее интерфейс" -ForegroundColor Green
    Write-Host "  [РЕК] [ 6] Быстрый запуск выключен        Настоящее выключение" -ForegroundColor Green
    Write-Host "  [РЕК] [ 7] Рекламный ID выключен          Убирает слежку по ID" -ForegroundColor Green
    Write-Host "  [РЕК] [ 8] Телеметрия выключена           Стоп отправка данных в MS" -ForegroundColor Green
    Write-Host "  [ОПЦ] [ 9] OneDrive выключен              Отключает синхронизацию" -ForegroundColor Yellow
    Write-Host "  [РЕК] [10] Spotlight экран блокировки выкл Нет рекламы от Microsoft" -ForegroundColor Green
    Write-Host "  [РЕК] [11] Быстрое выключение 2 сек       Службы убиваются за 2с" -ForegroundColor Green
    Write-Host "  [РЕК] [12] Твики NTFS                     Меньше операций на диск" -ForegroundColor Green
    Write-Host "  [РЕК] [13] Автозапуск с USB выключен      Безопасность" -ForegroundColor Green
    Write-Host "  [РЕК] [14] Оптимизация доставки выкл      Не раздаёшь трафик другим" -ForegroundColor Green
    Write-Host "  [РЕК] [15] Персонализация ввода выкл      Не собирает нажатия клавиш" -ForegroundColor Green
    Write-Host ""
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | [A]    Применить ВСЕ рекомендуемые твики сразу                |" -ForegroundColor Cyan
    Write-Host "  | [1-15] Применить конкретный твик                              |" -ForegroundColor White
    Write-Host "  | [0]    Назад в главное меню                                   |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Выбор: " -ForegroundColor White -NoNewline
    $choice = Read-Host

    function Apply-Tweak($num) {
        switch ($num) {
            "1" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Планировщик GPU включён"
            }
            "2" {
                $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
                foreach ($iface in $ifaces) {
                    $props = Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue
                    if ($props.DhcpIPAddress -like "192.168.*") {
                        Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord
                        Set-ItemProperty -Path $iface.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord
                        Write-OK "Алгоритм Нейгла выключен на $($props.DhcpIPAddress)"
                    }
                }
            }
            "3" {
                $pt = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
                if (-not (Test-Path $pt)) { New-Item -Path $pt -Force | Out-Null }
                Set-ItemProperty -Path $pt -Name "PowerThrottlingOff" -Value 1 -Type DWord
                Write-OK "Power Throttling выключен"
            }
            "4" {
                $gdvr = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path $gdvr)) { New-Item -Path $gdvr -Force | Out-Null }
                Set-ItemProperty -Path $gdvr -Name "GameDVR_Enabled" -Value 0 -Type DWord
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Game DVR выключен"
            }
            "5" {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -ErrorAction SilentlyContinue
                Write-OK "Визуальные эффекты - максимальная производительность"
            }
            "6" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord
                Write-OK "Быстрый запуск выключен"
            }
            "7" {
                $ad = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
                if (-not (Test-Path $ad)) { New-Item -Path $ad -Force | Out-Null }
                Set-ItemProperty -Path $ad -Name "Enabled" -Value 0 -Type DWord
                Write-OK "Рекламный ID выключен"
            }
            "8" {
                $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
                Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value 0 -Type DWord
                Set-ItemProperty -Path $dc -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
                Write-OK "Телеметрия выключена"
            }
            "9" {
                $od = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
                if (-not (Test-Path $od)) { New-Item -Path $od -Force | Out-Null }
                Set-ItemProperty -Path $od -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
                Write-OK "OneDrive выключен"
            }
            "10" {
                $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Set-ItemProperty -Path $cdm -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "ContentDeliveryAllowed" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $cdm -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-OK "Spotlight и реклама на экране блокировки выключены"
            }
            "11" {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
                Write-OK "Таймаут выключения установлен 2 секунды"
            }
            "12" {
                fsutil behavior set disablelastaccess 1 | Out-Null
                fsutil behavior set disable8dot3 1 | Out-Null
                Write-OK "NTFS: отключено время последнего доступа и имена 8.3"
            }
            "13" {
                $ar = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                if (-not (Test-Path $ar)) { New-Item -Path $ar -Force | Out-Null }
                Set-ItemProperty -Path $ar -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord
                Write-OK "Автозапуск с USB отключён"
            }
            "14" {
                $do = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
                if (-not (Test-Path $do)) { New-Item -Path $do -Force | Out-Null }
                Set-ItemProperty -Path $do -Name "DODownloadMode" -Value 0 -Type DWord
                Write-OK "Оптимизация доставки выключена"
            }
            "15" {
                $ink = "HKCU:\Software\Microsoft\InputPersonalization"
                if (-not (Test-Path $ink)) { New-Item -Path $ink -Force | Out-Null }
                Set-ItemProperty -Path $ink -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord
                Set-ItemProperty -Path $ink -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord
                Write-OK "Персонализация ввода выключена"
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
# МЕНЮ 3 - ЗАДАЧИ ПЛАНИРОВЩИКА
# ============================================================
function Menu-Tasks {
    Draw-Header "ЗАДАЧИ ПЛАНИРОВЩИКА - Отключение телеметрии и диагностики"
    Write-Host "  Эти задачи работают в фоне и отправляют данные в Microsoft." -ForegroundColor DarkGray
    Write-Host "  Все безопасно отключать." -ForegroundColor DarkGray
    Write-Host ""

    $tasks = @(
        @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"; Desc="Отправляет данные о приложениях"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater";                Desc="Обновляет данные телеметрии"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask";                    Desc="Отслеживает автозапуск"},
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClient";                          Desc="Телеметрия отзывов"},
        @{Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClientOnScenarioDownload";        Desc="Телеметрия сценариев"},
        @{Path="\Microsoft\Windows\Windows Error Reporting\"; Name="QueueReporting";                    Desc="Отчёты об ошибках в MS"},
        @{Path="\Microsoft\Windows\NetTrace\";                Name="GatherNetworkInfo";                  Desc="Сбор сетевых данных"},
        @{Path="\Microsoft\Windows\SettingSync\";             Name="BackgroundUploadTask";               Desc="Синхронизация настроек в облако"},
        @{Path="\Microsoft\Windows\SettingSync\";             Name="NetworkStateChangeTask";             Desc="Триггер сетевой синхронизации"},
        @{Path="\Microsoft\Windows\DiskDiagnostic\";          Name="Microsoft-Windows-DiskDiagnosticDataCollector"; Desc="Данные диска в MS"},
        @{Path="\Microsoft\Windows\UNP\";                     Name="RunUpdateNotificationMgr";           Desc="Уведомления об обновлениях"}
    )

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
    Write-Host "  | [1-11] Отключить конкретную задачу                            |" -ForegroundColor White
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
    Write-Host "  | [1-13] Очистить конкретный пункт                              |" -ForegroundColor White
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
            Write-INFO "Подробная статистика недоступна для этого диска (обычное дело для ноутбучных NVMe)"
        }
        Write-Host ""
    }

    Write-Host "  --- ТЕМПЕРАТУРА (встроенные датчики) ---" -ForegroundColor Cyan
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
        Write-INFO "Встроенные датчики не сообщили температуру ЦП/ГП (частое дело на ноутбуках)"
        Write-Host "  Для точных цифр под нагрузкой используй HWiNFO64 (если установлен)." -ForegroundColor DarkGray
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

    Write-Host "  --- ПРОВЕРКА ШРИФТОВ (лишние после установки Windows) ---" -ForegroundColor Cyan
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
        Write-OK "Лишних шрифтов не найдено - стандартный набор Windows, всё в порядке"
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

    # CPU
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    Write-Host ("  Процессор : {0}" -f $cpu.Name) -ForegroundColor White

    # GPU(s)
    $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Basic|Remote" }
    foreach ($g in $gpus) {
        Write-Host ("  Видео     : {0}" -f $g.Name) -ForegroundColor White
    }

    # Network adapters (WiFi chipset)
    $wifi = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.Name -match "Wireless|Wi-Fi|WiFi" -and $_.Manufacturer -notmatch "Microsoft" } | Select-Object -First 1
    if ($wifi) { Write-Host ("  Wi-Fi     : {0}" -f $wifi.Name) -ForegroundColor White }

    # Audio
    $audio = Get-WmiObject Win32_SoundDevice | Select-Object -First 1
    if ($audio) { Write-Host ("  Аудио     : {0}" -f $audio.Name) -ForegroundColor White }

    # Manufacturer / Model (for laptop-specific drivers)
    $sys = Get-WmiObject Win32_ComputerSystem
    $bios = Get-WmiObject Win32_BIOS
    Write-Host ("  Ноутбук   : {0} {1}" -f $sys.Manufacturer, $sys.Model) -ForegroundColor White
    Write-Host ""

    # Build list of what to open
    $links = @()

    function Build-SearchUrl($query) {
        return "https://www.google.com/search?q=" + [uri]::EscapeDataString($query)
    }

    # CPU
    if ($cpu.Name -match "Intel") {
        $links += @{Label="Intel Driver and Support Assistant (CPU, чипсет, Wi-Fi, BT) - уже стоит на этом ПК"; Url="https://www.intel.com/content/www/us/en/support/detect.html"}
    } elseif ($cpu.Name -match "AMD") {
        $cpuClean = ($cpu.Name -replace "AMD","" -replace "Processor","" -replace "with Radeon.*","" -replace "\s+"," ").Trim()
        $links += @{Label="AMD - последний драйвер чипсета для $cpuClean"; Url=(Build-SearchUrl "AMD chipset driver $cpuClean latest download")}
    }

    # GPU(s) - find exact model and search for latest driver specifically for it
    foreach ($g in $gpus) {
        if ($g.Name -match "NVIDIA") {
            $gpuClean = ($g.Name -replace "NVIDIA","" -replace "Laptop GPU","" -replace "\s+"," ").Trim()
            $links += @{Label="NVIDIA - последний драйвер для твоей видеокарты: $gpuClean"; Url=(Build-SearchUrl "nvidia driver $gpuClean laptop latest download")}
            $ge = "C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
            if (Test-Path $ge) {
                Write-INFO "У тебя уже установлен GeForce Experience - он сам определяет точную модель и обновляет автоматически"
            }
        } elseif ($g.Name -match "Intel") {
            $links += @{Label="Intel Graphics - последние драйверы (через Intel DSA выше)"; Url="https://www.intel.com/content/www/us/en/download-center/home.html"}
        } elseif ($g.Name -match "AMD|Radeon") {
            $gpuClean = ($g.Name -replace "AMD","" -replace "Radeon","" -replace "Graphics","" -replace "\s+"," ").Trim()
            $links += @{Label="AMD - последний драйвер для твоей видеокарты: Radeon $gpuClean"; Url=(Build-SearchUrl "amd radeon driver $gpuClean laptop latest download")}
        }
    }

    # Laptop manufacturer specific page
    if ($sys.Manufacturer -match "HUAWEI") {
        $links += @{Label="HUAWEI - драйверы для вашей модели ноутбука"; Url="https://consumer.huawei.com/en/support/laptops/"}
        Write-Host ""
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  | ВНИМАНИЕ: у тебя ноутбук HUAWEI                                |" -ForegroundColor Red
        Write-Host "  |                                                                  |" -ForegroundColor Red
        Write-Host "  | Фирменное приложение HUAWEI PC Manager (и HMS Core) известно   |" -ForegroundColor Yellow
        Write-Host "  | тем, что грузит систему в фоне: сканирует железо, лезет в сеть,|" -ForegroundColor Yellow
        Write-Host "  | проверяет обновления сама по себе. Из-за этого FPS в играх     |" -ForegroundColor Yellow
        Write-Host "  | может проседать и быть нестабильным, особенно в фоне.          |" -ForegroundColor Yellow
        Write-Host "  |                                                                  |" -ForegroundColor Red
        Write-Host "  | Рекомендация: скачай драйверы вручную с сайта, установи        |" -ForegroundColor Green
        Write-Host "  | только нужное (Wi-Fi, звук, графика), а сам PC Manager          |" -ForegroundColor Green
        Write-Host "  | и HMS Core лучше не держать постоянно запущенными.             |" -ForegroundColor Green
        Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
    } elseif ($sys.Manufacturer -match "ASUS") {
        $links += @{Label="ASUS - драйверы для вашей модели"; Url="https://www.asus.com/support/"}
    } elseif ($sys.Manufacturer -match "Lenovo") {
        $links += @{Label="Lenovo - драйверы для вашей модели"; Url="https://support.lenovo.com/"}
    } elseif ($sys.Manufacturer -match "HP") {
        $links += @{Label="HP - драйверы для вашей модели"; Url="https://support.hp.com/"}
    } elseif ($sys.Manufacturer -match "Dell") {
        $links += @{Label="Dell - драйверы для вашей модели"; Url="https://www.dell.com/support/home/"}
    } elseif ($sys.Manufacturer -match "MSI") {
        $links += @{Label="MSI - драйверы для вашей модели"; Url="https://www.msi.com/support/"}
    } elseif ($sys.Manufacturer -match "Acer") {
        $links += @{Label="Acer - драйверы для вашей модели"; Url="https://www.acer.com/support"}
    }

    if ($links.Count -eq 0) {
        Write-INFO "Не удалось определить производителя для точечных ссылок"
    } else {
        Write-Host "  Найдены следующие ресурсы для обновления:" -ForegroundColor Cyan
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
        foreach ($l in $links) {
            Start-Process $l.Url
            Write-OK "Открыто: $($l.Label)"
        }
    } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $links.Count) {
        $l = $links[[int]$choice - 1]
        Start-Process $l.Url
        Write-OK "Открыто: $($l.Label)"
    }

    Write-Host ""
    Write-INFO "Также установленные утилиты (если есть на ПК) можно запустить вручную:"
    $localTools = @(
        @{Name="Intel Driver and Support Assistant"; Path="C:\Program Files (x86)\Intel\Driver and Support Assistant\Application\DSATray.exe"},
        @{Name="NVIDIA GeForce Experience"; Path="C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"}
    )
    foreach ($t in $localTools) {
        if (Test-Path $t.Path) {
            Write-Host ("  Найдено: {0} -> {1}" -f $t.Name, $t.Path) -ForegroundColor White
        }
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
        Write-Host "  |  9  |  Здоровье системы         |  SSD, температуры, драйверы     |" -ForegroundColor Cyan
        Write-Host "  | 10  |  Обновление драйверов     |  Открыть сайты с последними вер.|" -ForegroundColor Cyan
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  0  |  Выход                    |                                  |" -ForegroundColor DarkGray
        Write-Host "  +-----+---------------------------+----------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  СОВЕТ: Начни с [1] Службы -> [A]  потом [2] Реестр -> [A]" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Выбор: " -ForegroundColor White -NoNewline
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
