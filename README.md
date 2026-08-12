# WinTools 2.0.0

Интерактивный PowerShell-инструмент для настройки, обслуживания и диагностики Windows 10/11.

**Сначала — полная инструкция на русском. [English documentation](#english-documentation).**

> [!WARNING]
> WinTools запускается с правами администратора и может менять реестр, службы, задачи планировщика, автозапуск и схему питания. Перед первой настройкой создайте точку восстановления и снимок конфигурации. Не применяйте пункты, назначение которых вам непонятно.

---

## Русская документация

### Что такое WinTools

WinTools — это меню для ручной настройки Windows. Оно помогает:

- включать и отключать службы, задачи планировщика и программы автозапуска;
- применять обратимые твики реестра;
- очищать временные файлы и кэши;
- проверять состояние компьютера;
- создавать и импортировать JSON-снимки конфигурации;
- применять безопасные системные профили;
- устанавливать программы через `winget`;
- проверять и устанавливать обновления WinTools.

WinTools не является «ускорителем в один клик». Перед изменением показывается план действий, а пользователь сам подтверждает применение.

### Системные требования

- Windows 10 Home/Pro или Windows 11 Home/Pro/Enterprise/LTSC/Insider;
- Windows PowerShell 5.1 или PowerShell 7;
- учётная запись с правами администратора;
- интернет — только для онлайн-запуска, менеджера приложений, страниц драйверов и обновления WinTools;
- `winget` — только для раздела `[19] Менеджер приложений`.

Некоторые функции доступны не на каждом компьютере. Например, аппаратное планирование GPU зависит от видеокарты и драйвера, показ температуры — от поддержки датчиков, а точки восстановления — от включённой защиты системы Windows.

## Установка

### Рекомендуемый способ: локальная папка

Этот вариант предоставляет все функции, включая самообновление.

1. Откройте страницу репозитория:
   <https://github.com/SigmaNagibatorJob/wintools>
2. Нажмите **Code → Download ZIP** или скачайте готовый архив релиза.
3. Полностью распакуйте архив, например в:

   ```text
   C:\WinTools
   ```

   Не запускайте программу прямо внутри ZIP-архива.
4. Откройте распакованную папку и запустите:
   - `start_ru.bat` — русская версия;
   - `start_en.bat` — английская версия.
5. Подтвердите запрос контроля учётных записей Windows — **Да**.

Файл запуска сам запросит права администратора и запустит PowerShell с временным обходом Execution Policy. Глобальная политика выполнения Windows при этом не меняется.

### Если Windows заблокировала скачанные файлы

Откройте PowerShell и выполните:

```powershell
Get-ChildItem "C:\WinTools" -Recurse | Unblock-File
```

Либо откройте свойства ZIP-файла, отметьте **Разблокировать**, нажмите **Применить** и распакуйте архив заново.

### Ручной запуск

Откройте PowerShell **от имени администратора**, перейдите в папку WinTools и выполните:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\wintools_ru.ps1
```

`-Scope Process` действует только до закрытия текущего окна PowerShell.

### Одноразовый онлайн-запуск

```powershell
irm https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1 | iex
```

Онлайн-установщик запросит права администратора, предложит язык и определит версию Windows, после чего загрузит выбранный скрипт в память и запустит его.

> [!NOTE]
> Онлайн-команда удобна для разового запуска, но не создаёт полноценную локальную установку. Для работы самообновления `[20]` и обычного повторного запуска используйте распакованную локальную папку.

Если вы не хотите сразу выполнять удалённый скрипт, сначала сохраните и просмотрите его:

```powershell
$u = "https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1"
Invoke-WebRequest $u -OutFile "$env:TEMP\wintools-install.ps1"
notepad "$env:TEMP\wintools-install.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\wintools-install.ps1"
```

## Какие файлы нужны пользователю

| Файл | Назначение | Нужен обычному пользователю |
|---|---|---:|
| `start_ru.bat` / `start_en.bat` | Удобный запуск с запросом прав администратора | Да |
| `wintools_ru.ps1` / `wintools_en.ps1` | Основные русская и английская версии | Да |
| `version.json` | Версия релиза и SHA-256 хэши файлов | Оставить в папке |
| `install.ps1` | Онлайн-запуск с выбором языка и Windows | Необязательно |
| `README.md` | Эта инструкция | Рекомендуется |
| `tests/` | Автоматические тесты для разработчиков | Нет, но можно оставить |
| `wintools-fixes.patch` | Git-патч для разработчиков | **Нет** |

`wintools-fixes.patch` не используется для запуска. Обычному пользователю его не нужно скачивать, распаковывать или куда-либо копировать.

## Рекомендуемый первый запуск

1. Запустите `start_ru.bat`.
2. Откройте `[18] Диагностика` и убедитесь, что Windows и оборудование определились корректно.
3. Создайте `[11] Точку восстановления`.
4. В `[17] Экспорт / импорт` создайте ручной снимок конфигурации.
5. При желании примените рекомендованный профиль в `[16] Профили системы`.
6. После этого выбирайте только нужные службы, задачи и твики.
7. Перезагрузите компьютер, если программа сообщила, что изменение требует перезапуска.

Не рекомендуется сразу включать все возможные оптимизации без чтения описаний.

## Управление меню и подтверждение

### Обычные списки

В службах, задачах планировщика и автозапуске обычный номер переключает текущее состояние:

```text
2          переключить пункт 2
2,3,5      переключить пункты 2, 3 и 5
5-8        переключить пункты с 5 по 8
2,4-7,10   список и диапазон в одной команде
```

### Твики реестра

В разделе `[2]` доступны переключение и явное направление:

```text
2                  переключить твик 2
+2                 включить твик 2
-2                 отключить твик 2 / вернуть стандартное поведение
2,-3,-4,-6,-7      смешанная команда
+3-5,-7-9          диапазоны с явным действием
```

Обозначения:

- `[ ON ]` — твик применён;
- `[off ]` — твик не применён;
- `[REC]` — рекомендуемый пункт;
- `[OPT]` — необязательный пункт, который нужен не всем.

### Предпросмотр

Перед изменением WinTools показывает список запланированных действий:

- `Y`, `Yes`, `Д` или `Да` — применить;
- `N`, `Н` или пустой `Enter` — ничего не менять и вернуться назад.

Случайное нажатие `Enter` не применяет показанные изменения.

## Разделы главного меню

| № | Раздел | Что делает |
|---:|---|---|
| 1 | Службы | Включает или отключает выбранные службы и запоминает прежний тип запуска |
| 2 | Твики реестра | Показывает текущее состояние и применяет обратимые настройки |
| 3 | Задачи планировщика | Включает или отключает телеметрию и диагностические задачи |
| 4 | Автозапуск | Перемещает записи в безопасное хранилище `WinToolsDisabled`, не удаляя команды |
| 5 | Очистка диска | Очищает временные файлы, дампы, кэши и другой выбранный мусор |
| 6 | Живой монитор | Показывает загрузку ЦП, ОЗУ, диска и активные процессы |
| 7 | Схема питания | Включает схему максимальной производительности |
| 8 | Безопасность SMB1 | Проверяет и отключает устаревший уязвимый протокол SMB1 |
| 9 | Здоровье системы | Проверяет диски, температуры, драйверы и дополнительные шрифты |
| 10 | Обновление драйверов | Определяет ЦП/ГП и открывает официальные страницы производителей |
| 11 | Точка восстановления | Создаёт точку восстановления Windows |
| 12 | Журнал и отмена | Показывает историю WinTools и отменяет поддерживаемые изменения |
| 13 | Встроенные приложения | Удаляет выбранные предустановленные AppX-приложения |
| 14 | Кэш браузеров | Очищает кэш профилей Brave, Chrome и Edge |
| 15 | Косметика Windows | Управляет контекстным меню, расширениями и скрытыми файлами |
| 16 | Профили системы | Применяет готовые безопасные группы настроек |
| 17 | Экспорт / импорт | Создаёт и восстанавливает JSON-снимки конфигурации |
| 18 | Диагностика | Создаёт отчёт без изменения системных настроек |
| 19 | Менеджер приложений | Устанавливает приложения и готовые пакеты через `winget` |
| 20 | Обновление WinTools | Проверяет и устанавливает новую версию с подтверждением |

## Твики реестра `[2]`

| № | Твик | Важное примечание |
|---:|---|---|
| 1 | Аппаратное планирование GPU | Работает только при поддержке GPU и драйвером |
| 2 | Отключение алгоритма Nagle | Применяется к активным IPv4-интерфейсам |
| 3 | Отключение Power Throttling | Может увеличить расход энергии |
| 4 | Отключение Game DVR и фоновой записи | Отключает фоновый захват игр |
| 5 | Минимум анимаций и визуальных эффектов | Перезапускает Проводник |
| 6 | Отключение быстрого запуска Windows | Может увеличить время холодного запуска |
| 7 | Отключение рекламного идентификатора | Настройка приватности |
| 8 | Минимальная телеметрия и отключение запросов отзыва | Доступный минимум зависит от редакции Windows |
| 9 | Отключение синхронизации OneDrive | Не выбирайте, если используете OneDrive |
| 10 | Отключение Spotlight, советов и предложений | Уменьшает рекомендуемый контент Windows |
| 11 | Тайм-аут завершения служб 2 секунды | Используйте осторожно на медленных системах |
| 12 | Отключение NTFS Last Access и коротких имён 8.3 | Может повлиять на старое ПО |
| 13 | Отключение AutoRun для съёмных дисков | Повышает безопасность |
| 14 | Отключение P2P Delivery Optimization | Windows Update не будет раздавать обновления другим ПК |
| 15 | Отключение сбора рукописного ввода и набора текста | Настройка приватности |
| 16 | Классическое контекстное меню Windows 11 | Показывается только на Windows 11 |
| 17 | Включение игрового режима Windows | Обычно рекомендуется для игрового ПК |
| 18 | Отключение ускорения мыши | Необязательно; полезно не всем |
| 19 | Отключение виджетов Windows 11 | Показывается только на Windows 11 |
| 20 | Отключение веб-поиска в меню «Пуск» | Оставляет локальные результаты поиска |
| 21 | Отключение фоновых приложений | Может задерживать фоновые уведомления |
| 22 | Отключение всплывающих уведомлений | Не выбирайте, если уведомления нужны |
| 23 | Отключение гибернации | Также может отключить зависящий от неё быстрый запуск |
| 24 | Секунды в системных часах | Может потребоваться перезапуск Проводника |

Команда `-N` отключает выбранный твик или возвращает предусмотренное WinTools стандартное значение.

## Системные профили `[16]`

Перед применением любого профиля WinTools показывает план и автоматически создаёт снимок `before_profile`.

- **Игровой ПК** — высокая производительность, аппаратное планирование GPU (HAGS), игровой режим, отключение Game DVR и Power Throttling.
- **Игровой ноутбук** — игровая настройка с сохранением сбалансированной схемы питания и энергосбережения.
- **Сбалансированный** — сбалансированное питание, стандартные игровые параметры и анимации.
- **Приватность** — телеметрия, рекламный идентификатор, отзывы, веб-поиск, виджеты, сбор ввода, Spotlight и рекомендации.
- **Стандарт Windows** — возвращает стандартные значения параметров, которыми управляют профили WinTools.

Профили не устанавливают экспериментальные настройки NVIDIA, AMD или Intel и не заменяют драйверы.

> [!IMPORTANT]
> «Стандарт Windows» восстанавливает только параметры, которыми управляют профили WinTools. Это не полный сброс Windows.

## Снимки конфигурации `[17]`

Снимок включает:

- управляемые WinTools значения реестра и информацию об их существовании/типе;
- состояние и тип запуска видимых служб;
- состояние задач планировщика;
- записи автозапуска;
- активную схему питания;
- версию WinTools, компьютер, пользователя и дату создания.

Папка снимков:

```text
C:\ProgramData\WinTools\Snapshots
```

Перед импортом показывается количество объектов. Если снимок создан на другом компьютере или другим пользователем, WinTools выводит предупреждение. Перед применением импорта автоматически создаётся снимок `before_import`.

> [!WARNING]
> Это лёгкий снимок конфигурации, а не образ Windows, не резервная копия диска и не копия личных файлов. Для важных данных используйте отдельное резервное копирование.

## Диагностика `[18]`

Диагностика читает сведения о системе и сохраняет текстовый отчёт:

```text
C:\ProgramData\WinTools\Reports
```

В отчёт входят версия Windows и WinTools, модель ПК, ЦП, ОЗУ, видеокарты, диски, свободное место, Windows Update, Microsoft Defender, ожидаемая перезагрузка, проблемные устройства, ошибки системного журнала за последние 24 часа и количество отключённых служб.

Диагностика не меняет настройки Windows, но создаёт файл отчёта.

## Менеджер приложений `[19]`

Требует `winget`, который входит в пакет **App Installer** из Microsoft Store.

Готовые пакеты:

- **Игры:** 7-Zip, Steam, Discord, Epic Games Launcher;
- **Интернет:** Firefox, Brave, qBittorrent;
- **Безопасность:** Bitwarden, Malwarebytes;
- **Базовый:** 7-Zip, VLC, Notepad++, PowerToys.

Можно выбрать пакет, отдельные номера, список или диапазон. Перед установкой показывается предпросмотр. Пункт `U` запускает обновление всех поддерживаемых установленных приложений.

WinTools передаёт установку официальному клиенту `winget`; лицензии, источники пакетов и доступность приложений зависят от репозиториев winget.

## Обновление WinTools `[20]`

- При запуске проверка выполняется не чаще одного раза в 24 часа.
- Если доступна более новая явная версия, можно выбрать **Обновить сейчас** или **Позже**.
- Ничего не устанавливается без подтверждения.
- Все файлы сначала загружаются во временную папку и проверяются по SHA-256 из `version.json`.
- Перед заменой текущие файлы копируются в:

  ```text
  C:\ProgramData\WinTools\Backups
  ```

- Если замена или проверка не удалась, WinTools пытается автоматически вернуть исходные файлы.
- После успешного обновления перезапустите WinTools.

Самообновление работает только при запуске скрипта из локальной папки. Проверить обновление вручную можно в пункте `[20]`.

## Отмена изменений и удаление

### Способы отката

1. `[12] Журнал и отмена` — отмена поддерживаемых изменений, выполненных WinTools.
2. `[17] Экспорт / импорт` — восстановление сохранённого снимка конфигурации.
3. `[16] Стандарт Windows` — возврат только параметров системных профилей.
4. Точка восстановления Windows — более широкий системный откат.

Некоторые изменения начинают или перестают действовать только после выхода из учётной записи или перезагрузки.

### Удаление WinTools

1. Сначала откатите ненужные изменения одним из способов выше.
2. Закройте WinTools.
3. Удалите папку, например `C:\WinTools`.
4. При необходимости удалите журналы, снимки, отчёты и резервные копии из:

   ```text
   C:\ProgramData\WinTools
   ```

Удаление файлов WinTools само по себе не отменяет уже применённые настройки Windows.

## Где WinTools хранит данные

| Путь | Содержимое |
|---|---|
| `C:\ProgramData\WinTools\actions_log.csv` | Журнал изменений для раздела отмены |
| `C:\ProgramData\WinTools\Snapshots` | JSON-снимки конфигурации |
| `C:\ProgramData\WinTools\Reports` | Диагностические отчёты |
| `C:\ProgramData\WinTools\Backups` | Резервные копии файлов перед самообновлением |
| `C:\ProgramData\WinTools\Update` | Временные файлы обновления; после операции очищаются |
| `C:\ProgramData\WinTools\last_update_check.txt` | Время последней попытки проверки обновления |

## Решение проблем

### Окно сразу закрывается

Запустите `start_ru.bat`, а не двойным щелчком по `.ps1`. Если ошибка повторяется, откройте PowerShell от имени администратора и выполните ручную команду запуска — текст ошибки останется в окне.

### «Запуск сценариев отключён в этой системе»

Используйте `start_ru.bat` или команду с `Set-ExecutionPolicy Bypass -Scope Process`. Необязательно менять Execution Policy для всего компьютера.

### Нет прав администратора

Подтвердите UAC. Если компьютер управляется организацией, некоторые политики могут запрещать изменения даже локальному администратору.

### Не найден `winget`

Установите или обновите **App Installer** через Microsoft Store, затем перезапустите терминал. Проверка:

```powershell
winget --version
```

### Не создаётся точка восстановления

Нажмите `Win + R`, выполните:

```text
SystemPropertiesProtection.exe
```

Включите защиту для системного диска и повторите создание точки.

### Твик не включается или сразу показывает `off`

Причины могут включать неподдерживаемую функцию Windows, корпоративную политику, антивирус, отсутствие нужного драйвера или изменение параметра самой Windows. Красная строка `[!]` содержит реальную ошибку, если она доступна.

### После изменения ничего не произошло

Перезапустите Проводник, выйдите из учётной записи или перезагрузите компьютер. Это особенно важно для части твиков реестра, схем питания, SMB1 и настроек интерфейса.

### Самообновление недоступно

Убедитесь, что WinTools распакован в локальную папку, есть доступ к `raw.githubusercontent.com`, а скрипт не запущен одноразовой онлайн-командой. Ручная проверка находится в `[20]`.

### Антивирус или SmartScreen показывает предупреждение

PowerShell-скрипты, изменяющие системные параметры, могут вызывать предупреждения. Скачивайте WinTools только из официального репозитория, проверьте исходный код и не отключайте антивирус без необходимости.

## Безопасность и ограничения

- WinTools не является официальным продуктом Microsoft.
- Проект не добавляет обычный переключатель для повторного включения небезопасного SMB1.
- Очистка и удаление приложений являются действиями, а не бинарными твиками; внимательно проверяйте выбранные пункты.
- Системные снимки WinTools не заменяют резервное копирование личных файлов.
- Службы принтера, биометрии, Bluetooth/Wi-Fi, сетевого доступа и другого оборудования могут быть необходимы именно вашему компьютеру.
- Корпоративные политики Windows могут отменять или блокировать локальные настройки.
- Использование выполняется на ваш риск. Всегда сохраняйте важные данные отдельно.

## Разработчикам

Все PowerShell-файлы должны сохраняться в UTF-8 с BOM для совместимости с Windows PowerShell 5.1.

Запуск тестов из корня проекта:

```powershell
Get-ChildItem .\tests\*.ps1 | ForEach-Object {
    & pwsh -NoLogo -NoProfile -File $_.FullName
}
```

Статический анализ:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

`wintools-fixes.patch` предназначен только для применения истории изменений к Git-репозиторию, например:

```bash
git am wintools-fixes.patch
```

Обычным пользователям патч не нужен.

---

# English documentation

## Overview

WinTools is an interactive PowerShell utility for configuring, maintaining, and diagnosing Windows 10/11. It can manage services, scheduled tasks, Startup entries, Registry tweaks, cleanup, diagnostics, configuration snapshots, application packages, and WinTools updates.

WinTools is not a blind “one-click booster.” It previews planned state changes and requires explicit confirmation.

## Requirements

- Windows 10 Home/Pro or Windows 11 Home/Pro/Enterprise/LTSC/Insider;
- Windows PowerShell 5.1 or PowerShell 7;
- an administrator account;
- internet only for online launch, winget, driver pages, and WinTools updates;
- `winget` for Application Manager.

## Recommended installation

1. Open <https://github.com/SigmaNagibatorJob/wintools>.
2. Select **Code → Download ZIP**, or download the latest release archive.
3. Extract the complete archive to a local folder such as:

   ```text
   C:\WinTools
   ```

4. Run `start_en.bat` for English or `start_ru.bat` for Russian.
5. Approve the Windows UAC prompt.

Do not run WinTools from inside the ZIP file. Keep the launcher and PowerShell scripts together.

If Windows blocked the downloaded files:

```powershell
Get-ChildItem "C:\WinTools" -Recurse | Unblock-File
```

### Manual launch

Open PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\wintools_en.ps1
```

The execution-policy change applies only to the current PowerShell process.

### One-time online launch

```powershell
irm https://raw.githubusercontent.com/SigmaNagibatorJob/wintools/main/install.ps1 | iex
```

The online installer selects the language, detects Windows, downloads the selected script into memory, and runs it. It does not create a complete local installation, so use the extracted folder if you need self-update and convenient repeat launches.

## Which files do users need?

- Keep `start_en.bat`, `start_ru.bat`, `wintools_en.ps1`, `wintools_ru.ps1`, and `version.json` together.
- `install.ps1` is only for online launch.
- `tests/` and `PSScriptAnalyzerSettings.psd1` are for development.
- **`wintools-fixes.patch` is not needed to install or run WinTools.** It is only a Git patch for developers.

## Safe first run

1. Run `start_en.bat`.
2. Open `[18] Diagnostics` and review the detected system.
3. Create `[11] Restore Point`.
4. Create a manual snapshot in `[17] Export / Import`.
5. Optionally apply the recommended profile under `[16] System Profiles`.
6. Apply only the individual changes you understand.
7. Restart Windows when requested.

## Input and confirmation

Plain numbers toggle current state in Services, Scheduled Tasks, Startup, and Registry Tweaks:

```text
2
2,3,5
5-8
2,4-7,10
```

Registry Tweaks also support explicit direction:

```text
+2               enable tweak 2
-2               disable tweak 2 / restore standard behavior
2,-3,-4,-6       mixed command
+3-5,-7-9        signed ranges
```

At the preview prompt:

- `Y` or `Yes` applies changes;
- `N` or empty `Enter` returns without applying anything.

## Main menu

| # | Section | Purpose |
|---:|---|---|
| 1 | Services | Toggle services and remember their previous startup type |
| 2 | Registry Tweaks | Show current state and apply reversible settings |
| 3 | Scheduled Tasks | Enable or disable selected diagnostic/telemetry tasks |
| 4 | Startup Programs | Move entries safely without deleting their commands |
| 5 | Disk Cleanup | Remove selected temporary files, dumps, and caches |
| 6 | Live Monitor | Display CPU, RAM, disk, and process activity |
| 7 | Power Plan | Activate the Ultimate Performance plan |
| 8 | SMB1 Security | Detect and disable the obsolete SMB1 protocol |
| 9 | System Health | Inspect disks, temperatures, drivers, and extra fonts |
| 10 | Driver Update | Detect CPU/GPU and open official vendor pages |
| 11 | Restore Point | Create a Windows restore point |
| 12 | Change Log & Undo | Review and undo supported WinTools changes |
| 13 | Built-in Apps | Remove selected preinstalled AppX packages |
| 14 | Browser Cache | Clear Brave, Chrome, and Edge profile caches |
| 15 | Windows Cosmetics | Manage context menu, extensions, and hidden files |
| 16 | System Profiles | Apply safe groups of settings |
| 17 | Export / Import | Create and restore JSON configuration snapshots |
| 18 | Diagnostics | Save a read-only system report |
| 19 | Application Manager | Install apps and package profiles through winget |
| 20 | WinTools Update | Check and install a confirmed newer version |

## System Profiles

Every profile displays a preview and creates a `before_profile` snapshot.

- **Gaming Desktop:** high-performance power, HAGS, Game Mode, no Game DVR, and no Power Throttling.
- **Gaming Laptop:** gaming settings with Balanced power and power saving retained.
- **Balanced:** Balanced power plus conservative game and animation settings.
- **Privacy:** telemetry, advertising ID, feedback, web suggestions, widgets, input collection, Spotlight, and recommendations.
- **Windows Defaults:** restores standard values for settings managed by WinTools profiles.

Windows Defaults is not a complete Windows reset. No untested NVIDIA, AMD, or Intel profile is applied.

## Configuration snapshots

Snapshots are stored in:

```text
C:\ProgramData\WinTools\Snapshots
```

They contain managed Registry values, service startup/status, scheduled-task state, Startup Registry entries, active power scheme, version, computer, user, and creation time. Profile and import operations create automatic pre-change snapshots.

Snapshots are lightweight configuration backups, **not** Windows images, disk backups, or personal-file backups.

## Diagnostics

Read-only reports are written to:

```text
C:\ProgramData\WinTools\Reports
```

Reports cover Windows and WinTools versions, hardware, disks, free space, Windows Update, Defender, pending reboot, problem devices, recent System errors, and disabled-service count.

## Application Manager

Application Manager requires `winget` from Microsoft App Installer.

- **Games:** 7-Zip, Steam, Discord, Epic Games Launcher;
- **Internet:** Firefox, Brave, qBittorrent;
- **Security:** Bitwarden, Malwarebytes;
- **Basic:** 7-Zip, VLC, Notepad++, PowerToys.

You can select a profile, individual numbers, lists, or ranges. `U` updates supported installed applications. Every operation is previewed first.

## Self-update

- Startup checks occur at most once every 24 hours.
- A newer explicit version offers **Update now** or **Later**.
- Files are staged and verified against SHA-256 hashes in `version.json`.
- Existing files are backed up under `C:\ProgramData\WinTools\Backups`.
- A replacement failure triggers an automatic rollback attempt.
- Restart WinTools after a successful update.

Self-update requires a local extracted installation and access to `raw.githubusercontent.com`.

## Undo and uninstall

Use one of these before deleting WinTools:

1. `[12] Change Log & Undo` for supported individual changes;
2. `[17] Export / Import` to restore a saved snapshot;
3. `[16] Windows Defaults` for profile-managed settings only;
4. Windows System Restore for a broader rollback.

Deleting the WinTools folder does not undo Windows settings. After rollback, delete the local installation folder. Optional logs, snapshots, reports, and update backups are under:

```text
C:\ProgramData\WinTools
```

## Troubleshooting

- **Window closes immediately:** launch `start_en.bat`, or run the script from an elevated PowerShell window to keep the error visible.
- **Scripts are disabled:** use the BAT launcher or `Set-ExecutionPolicy Bypass -Scope Process`; do not change machine-wide policy unnecessarily.
- **winget missing:** install/update Microsoft App Installer, restart the terminal, and run `winget --version`.
- **Restore point fails:** run `SystemPropertiesProtection.exe` and enable protection for the system drive.
- **A tweak remains off:** the feature may be unsupported or controlled by policy, security software, Windows, or a missing driver.
- **No visible effect:** restart Explorer, sign out, or reboot Windows.
- **Update unavailable:** use a local extracted folder and verify access to `raw.githubusercontent.com`.
- **SmartScreen/antivirus warning:** download only from the official repository and review the source; do not disable security software without a reason.

## Data locations

| Path | Content |
|---|---|
| `C:\ProgramData\WinTools\actions_log.csv` | Undo log |
| `C:\ProgramData\WinTools\Snapshots` | JSON configuration snapshots |
| `C:\ProgramData\WinTools\Reports` | Diagnostic reports |
| `C:\ProgramData\WinTools\Backups` | Pre-update file backups |
| `C:\ProgramData\WinTools\Update` | Temporary update staging |
| `C:\ProgramData\WinTools\last_update_check.txt` | Last update-check attempt |

## Disclaimer

WinTools is not an official Microsoft product. It can disable services and modify system settings. Features needed for printing, biometrics, Bluetooth/Wi-Fi, network sharing, notifications, and other workflows differ by computer. Read every description, keep separate backups of important files, and use the project at your own risk.
