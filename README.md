# WinTools

**English below / Русский ниже**

---

## English

WinTools is an interactive PowerShell menu for optimizing Windows 10/11: disable unnecessary services, apply registry tweaks, clean junk files, check disk health, and find the right drivers for your hardware.

### Quick start (one command)

Open PowerShell **as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/USERNAME/wintools/main/install.ps1 | iex
```

### Manual install

1. Download `wintools_en.ps1` (or `wintools_ru.ps1` for Russian) from this repo
2. Right-click the file -> Run with PowerShell, or open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; .\wintools_en.ps1
```

Or just double-click `start_en.bat` - it will ask for admin rights automatically.

### Features

| Menu | What it does |
|------|--------------|
| 1. Services | Individually choose which background services to disable, each with a plain-language description |
| 2. Registry Tweaks | GPU scheduling, Nagle algorithm, power throttling, telemetry, visual effects, and more |
| 3. Scheduled Tasks | Disable telemetry and diagnostic tasks that run in the background |
| 4. Startup Programs | See and remove what launches at boot |
| 5. Disk Cleanup | Scans folder sizes and lets you clean junk, temp files, crash dumps, caches |
| 6. Live Monitor | Real-time CPU/RAM/Disk usage with a top-10 process view |
| 7. Power Plan | Activate Windows' hidden Ultimate Performance power plan |
| 8. SMB1 Security | Detect and disable the SMB1 protocol vulnerability (used by WannaCry) |
| 9. System Health | SSD health/wear, temperature, driver update check, extra font detection |
| 10. Driver Update | Detects your exact CPU/GPU model and opens the right download page |

### Important

- This script **modifies system settings and disables services**. Read what each option does before applying it.
- Some services are needed for specific features (fingerprint login, printers, Wi-Fi/Bluetooth radio management, network file sharing). The tool tells you what each one does - decide based on your own usage, not blindly.
- Always safe to run: nothing is applied without your explicit confirmation (you choose service numbers yourself).
- Tested on Windows 11. Should work on Windows 10 as well, but some registry paths may not exist there.

### Disclaimer

Use at your own risk. This is a personal optimization tool built from real troubleshooting sessions, not an official Microsoft or Anthropic product. Always know what a setting does before disabling it.

---

## Русский

WinTools - интерактивное меню в PowerShell для оптимизации Windows 10/11: отключение ненужных служб, твики реестра, очистка мусора, проверка здоровья диска и поиск подходящих драйверов под твоё железо.

### Быстрый запуск (одной командой)

Открой PowerShell **от имени администратора** и выполни:

```powershell
irm https://raw.githubusercontent.com/USERNAME/wintools/main/install.ps1 | iex
```

### Установка вручную

1. Скачай `wintools_ru.ps1` из этого репозитория
2. ПКМ на файл -> Запустить с помощью PowerShell, либо открой PowerShell от администратора и выполни:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; .\wintools_ru.ps1
```

Или просто дважды кликни `start_ru.bat` - он сам запросит права администратора.

### Возможности

| Раздел | Что делает |
|--------|-----------|
| 1. Службы | Выбираешь номера служб для отключения по одной, у каждой есть описание простыми словами |
| 2. Твики реестра | Планировщик GPU, алгоритм Нейгла, троттлинг питания, телеметрия, визуальные эффекты и другое |
| 3. Задачи планировщика | Отключение телеметрии и диагностических задач в фоне |
| 4. Автозапуск | Просмотр и удаление программ из автозагрузки |
| 5. Очистка диска | Сканирует размеры папок, чистит мусор, временные файлы, дампы, кэши |
| 6. Живой монитор | ЦП/ОЗУ/Диск в реальном времени с топ-10 процессов |
| 7. Схема питания | Активация скрытой схемы "Максимальная производительность" |
| 8. Безопасность SMB1 | Проверка и отключение уязвимого протокола SMB1 (использовался WannaCry) |
| 9. Здоровье системы | Здоровье и износ SSD, температура, проверка драйверов, лишние шрифты |
| 10. Обновление драйверов | Определяет точную модель ЦП/ГП и открывает нужную страницу загрузки |

### Важно

- Скрипт **меняет системные настройки и отключает службы**. Читай описание каждого пункта перед применением.
- Некоторые службы нужны для конкретных функций (вход по отпечатку, принтеры, управление радио Wi-Fi/Bluetooth, доступ к папкам по сети). Инструмент объясняет что делает каждая - решай исходя из того, чем сам пользуешься, а не вслепую.
- Ничего не применяется без твоего явного подтверждения - номера служб выбираешь сам.
- Проверено на Windows 11. Должно работать и на Windows 10, но некоторые пути реестра там могут отсутствовать.

### Отказ от ответственности

Используй на свой страх и риск. Это личный инструмент оптимизации, собранный по итогам реальной настройки системы, а не официальный продукт Microsoft или Anthropic. Всегда узнавай что делает настройка перед тем как её отключить.
