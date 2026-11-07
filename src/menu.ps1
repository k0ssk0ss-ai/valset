# menu.ps1 — главный экран: что сейчас (аккаунт, совпадают ли настройки, что нажать), меню, справка, одно окно.

# Состояние для главного экрана. Сверка с облаком — одно чтение (~0,5 с).
function Get-MenuState {
    $st = @{ Client = [bool](Get-Process 'RiotClientServices' -ErrorAction SilentlyContinue)
             Game = [bool](Get-Process $GameProc -ErrorAction SilentlyContinue)
             Have = (Test-Path $ProfilePath); Cfg = (Get-Config); Agent = (Test-AgentEnabled); GfxWait = (Test-GfxWaiting) }
    $s = Get-Session
    $st.Session = $s
    if (-not $s) { return $st }
    $st.Name = Register-Account $s
    $st.IsMain = $s.Puuid -eq (Get-MainPuuid)
    if ($st.Have) {
        try {
            $curJson = Get-Settings $s
            $st.Synced = @(Update-Reference $s $curJson)   # правки в игре — сразу в эталон
            $cur = $curJson | ConvertFrom-Json
            $new = Read-Profile
            $null = Join-Crosshairs $cur $new (Test-TempDefault $s.Puuid)
            $st.Same = Test-PrefsEqual $cur $new
            $st.DiffList = if ($st.Same) { @() } else { Compare-Prefs $cur $new }
            $st.Diff = if ($st.Same) { 0 } else { [Math]::Max(1, $st.DiffList.Count) }
            Set-AccountState $s.Puuid @{ state = $(if ($st.Same) { 'same' } else { 'diff' }); diff = $st.Diff; checked = (Get-Stamp) }
        } catch { $st.Error = $_.Exception.Message }
    }
    $st
}

function Write-StateLine([string]$label, [string]$text, [string]$color, [string]$hint = '') {
    Write-Host -NoNewline "    $($label.PadRight(12))" -ForegroundColor DarkGray
    Write-Host -NoNewline $text -ForegroundColor $color
    if ($hint) { Write-Host -NoNewline "  $hint" -ForegroundColor DarkGray }
    Write-Host ''
}

function Write-State($st) {
    Write-Host ''
    if (-not $st.Session) {
        if ($st.Client) { Write-StateLine (L 'Аккаунт' 'Account') (L 'вход не выполнен' 'not logged in') 'Yellow' (L 'войди в аккаунт в клиенте Riot' 'log into an account in the Riot Client') }
        else            { Write-StateLine (L 'Аккаунт' 'Account') (L 'клиент Riot закрыт' 'Riot Client closed') 'Yellow' (L 'открой его и войди' 'open it and log in') }
    } else {
        Write-StateLine (L 'Аккаунт' 'Account') "$($st.Name)$(if ($st.IsMain) { L ' · основной' ' · main' })" 'White'
        if ($st.Synced.Count) { Write-StateLine (L 'Из игры' 'From game') "√ $(L 'сохранено в твои' 'saved to yours'): $(Format-Changed $st.Synced)" 'Green' (L 'отменить: «Ещё» → «Бэкапы»' 'undo: “More” → “Backups”') }
        if (-not $st.Have)  { Write-StateLine (L 'Настройки' 'Settings') (L 'твои настройки ещё не сохранены' 'your settings are not saved yet') 'Yellow' (L '→ «Сохранить»' '→ “Save”') }
        elseif ($st.Error)  { Write-StateLine (L 'Настройки' 'Settings') (L 'не удалось проверить' 'could not check') 'Red' $st.Error }
        elseif ($st.Same)   { Write-StateLine (L 'Настройки' 'Settings') (L '√ совпадают с твоими' '√ match yours') 'Green' }
        elseif ($st.IsMain) { Write-StateLine (L 'Настройки' 'Settings') "‼ $(L 'поменялись в игре' 'changed in game') ($($st.Diff))" 'Yellow' (L '→ «Сохранить» (вернуть прежние: «Ещё» → «Перенести мои»)' '→ “Save” (to revert: “More” → “Apply mine”)') }
        else                { Write-StateLine (L 'Настройки' 'Settings') "‼ $(L 'не твои: отличий' 'not yours: differences') $($st.Diff)" 'Yellow' (L '→ «Перенести мои настройки»' '→ “Apply my settings”') }
    }
    if ($st.Session -and (Test-Temp $st.Session.Puuid)) {
        $how = if (Test-AgentRunning) { L 'вернутся сами после игры' 'come back by themselves after the game' } else { L 'перед выходом: «Вернуть исходные»' 'before logging out: “Restore originals”' }
        Write-StateLine (L 'На время' 'Temporary') (L 'твои настройки, исходные сохранены' 'your settings, originals kept') 'Cyan' $how
    }
    if ($st.Game) { Write-StateLine (L 'Игра' 'Game') (L 'запущена' 'running') 'Yellow' (L 'перенос подействует после перезапуска игры' 'applying takes effect after a game restart') }
    # Помощник — строка только когда он включён (выключен — это норма, не о чем сообщать; настраивается в «Ещё»).
    $c = $st.Cfg
    if ($c.notify -or $c.autoApply) {
        $text = "$(L 'уведомления' 'notifications') $(if ($c.notify) { L 'вкл' 'on' } else { L 'выкл' 'off' }) · $(L 'автоперенос' 'auto-apply') $(if ($c.autoApply) { L 'вкл' 'on' } else { L 'выкл' 'off' })"
        $hint = if (-not $st.Agent) { L 'не запущен, включи заново в «Ещё»' 'not running, turn it on again in “More”' } elseif ($c.autoApply) { L 'переносит сам на любой аккаунт, кроме основного' 'applies by itself to any account except main' } else { L 'подскажет, если настройки не совпали' 'tells you when settings differ' }
        Write-StateLine (L 'Помощник' 'Helper') $text $(if ($st.Agent) { 'Green' } else { 'Yellow' }) $hint
    }
    if ($st.GfxWait -and (Test-Path $CloudQueue)) { Write-StateLine (L 'Перенос' 'Apply') (L 'ждёт выхода из игры' 'waiting for game exit') 'Yellow' (L 'запишется сам' 'will be written automatically') }
    if ($st.GfxWait -and (Test-Path $GfxQueue)) { Write-StateLine (L 'Графика' 'Graphics') (L 'ждёт выхода из игры' 'waiting for game exit') 'Yellow' (L 'запишется сама' 'will be written automatically') }
}

# Пункт, с которого стоит начать.
function Get-Suggested($st, $items) {
    $want = if (-not $st.Session) { 'client' } elseif (-not $st.Have -or ($st.IsMain -and -not $st.Same)) { 'save' } elseif (-not $st.Same) { 'apply' } else { '' }
    for ($n = 0; $n -lt $items.Count; $n++) { if ($items[$n].Id -eq $want -or ($items[$n].Opts -and $items[$n].Opts[0].Id -eq $want)) { return $n } }
    -1
}

# Строки «Перенести мои» / «Сохранить» — одни и те же на главном экране и в «Ещё».
function New-ApplyEntry($st) {
    $temp = $st.Session -and (Test-TempDefault $st.Session.Puuid)
    New-MenuEntry (L 'Перенести мои' 'Apply mine') '' '' @(
        New-MenuOpt (L 'всё' 'all') 'apply' $(if ($temp) { L 'на время: после игры вернутся исходные' 'for now: the originals come back after the game' } else { L 'бинды, мышь, прицел, графика' 'binds, mouse, crosshair, graphics' })
        New-MenuOpt (L 'бинды' 'binds') 'binds' (L 'только клавиши' 'keys only')
        New-MenuOpt (L 'насовсем' 'permanently') 'applyperm' (L 'без возврата исходных' 'originals are not restored'))
}
function New-SaveEntry {
    New-MenuEntry (L 'Сохранить' 'Save') '' '' @(
        New-MenuOpt (L 'всё' 'all') 'save' (L 'с этого аккаунта' 'from this account')
        New-MenuOpt (L 'бинды' 'binds') 'savebinds' (L 'только клавиши' 'keys only')
        New-MenuOpt (L 'графику' 'graphics') 'gfxsave' (L 'можно прямо в игре' 'works even in game'))
}

# Главный экран — только то, что нужно этому аккаунту сейчас; всё остальное — в «Ещё» (more.ps1).
function Get-MenuItems($st) {
    $ok = $st.Session -and -not $st.Error
    $now = @(
        if (-not $st.Session -and -not $st.Client) { New-MenuEntry (L 'Открыть клиент Riot' 'Open Riot Client') (L 'и войти в аккаунт' 'and log in') 'client' }
        if ($st.Session -and (Test-Temp $st.Session.Puuid)) { New-MenuEntry (L 'Вернуть исходные' 'Restore originals') (L 'настройки аккаунта до твоего переноса' 'the account''s settings before your apply') 'untemp' }
        # на основном примеряешь чужое (про) — не предлагать запомнить его как твоё
        if ($ok -and (-not $st.Have -or ($st.IsMain -and -not $st.Same -and -not (Test-Temp $st.Session.Puuid)))) { New-SaveEntry }
        if ($ok -and $st.Have -and -not $st.IsMain -and -not $st.Same) { New-ApplyEntry $st }
        if ($st.Diff -and $st.DiffList.Count) { New-MenuEntry (L 'Что отличается' 'What differs') "$($st.DiffList.Count) $(L (Get-Plural $st.DiffList.Count 'настройка' 'настройки' 'настроек') 'settings'): $(L 'на аккаунте → твои' 'on account → yours')" 'diff' }
    )
    # всё в порядке — действий нет, статус сверху это уже сказал: только «Ещё» и «Выход»
    @(
        if ($now) { New-MenuSep (L 'Сейчас' 'Now'); $now; New-MenuSep '' }
        New-MenuEntry (L 'Ещё' 'More') (L 'вручную, аккаунты, помощник, бэкапы, справка' 'manual, accounts, helper, backups, help') 'more'
        New-MenuEntry (L 'Выход' 'Exit') '' 'exit'
    )
}

# Действие пункта меню (главного или «Ещё»). Возвращает $true, если после него ждать клавишу.
function Invoke-MenuAction([string]$id, $st) {
    switch ($id) {
        'client'    { Open-RiotClient; return $false }
        'apply'     { Write-Screen (L 'Перенести мои настройки' 'Apply my settings'); Invoke-Apply }
        'binds'     { Write-Screen (L 'Перенести: только бинды' 'Apply: binds only'); Invoke-Apply -BindsOnly }
        'applyperm' { Write-Screen (L 'Перенести насовсем' 'Apply permanently'); Invoke-Apply -Permanent }
        'untemp'    { Write-Screen (L 'Вернуть исходные' 'Restore originals'); $null = Invoke-RestoreTemp $st.Session }
        'save'      { Write-Screen (L 'Сохранить как мои' 'Save as mine'); Invoke-Save }
        'savebinds' { Write-Screen (L 'Сохранить: только бинды' 'Save: binds only'); Invoke-SaveBinds }
        'gfxsave'   { Write-Screen (L 'Сохранить: только графику' 'Save: graphics only'); Invoke-SaveGraphics }
        'diff'      { Show-DiffList $st.DiffList "$(L 'Что отличается' 'What differs') · $($st.Name)"; return $false }
        'more'      { return (Show-More $st) }
        'pros'      { return (Show-Pros) }
        'accounts'  { Show-Accounts; return $false }
        'restore'   { Show-Restore; return $false }
        'history'   { Show-History; return $false }
        'help'      { Show-Help; return $false }
        'auto-on'   {
            Write-Screen (L 'Автоперенос' 'Auto-apply')
            Set-Config 'autoApply' $true
            Write-Ok (L 'Включён. Запускай VALORANT как обычно, настройки перенесутся сами при входе в аккаунт' 'On. Launch VALORANT as usual, your settings are applied when you log in')
            Write-Note (L 'Основной аккаунт не меняется. Помощник запускается вместе с Windows' 'The main account is never changed. The helper starts with Windows')
        }
        'auto-off'  { Write-Screen (L 'Автоперенос' 'Auto-apply'); Set-Config 'autoApply' $false; Write-Ok (L 'Выключен. Переноси вручную из этого меню' 'Off. Apply manually from this menu') }
        'notify-on' {
            Write-Screen (L 'Уведомления' 'Notifications')
            Set-Config 'notify' $true
            Send-Toast 'VALSET' (L 'Уведомления включены. Так они будут выглядеть.' 'Notifications are on. This is how they look.')
            Write-Ok (L 'Включены: подскажут, если на аккаунте не твои настройки или на основном они поменялись' 'On: they tell you when an account has different settings, or yours changed on main')
        }
        'notify-off' { Write-Screen (L 'Уведомления' 'Notifications'); Set-Config 'notify' $false; Write-Ok (L 'Выключены' 'Off') }
        default     { return $false }
    }
    $true
}

function Show-Menu {
    if (-not (Enter-SingleMenu)) { Write-Fail (L 'Не удалось закрыть старое окно valset.' 'Could not close the old VALSET window.'); return }
    $Host.UI.RawUI.WindowTitle = 'VALSET'
    $script:InMenu = $true
    if (-not (Test-Path $ProfilePath) -and -not (Get-HistoryPoints)) { Show-Welcome }
    $lastId = ''
    while ($true) {
        Clear-Host; Write-Host ''; Write-Host (L '    Проверяю аккаунт…' '    Checking the account…') -ForegroundColor DarkGray
        $st = Get-MenuState
        $items = Get-MenuItems $st
        $sel = Get-Suggested $st $items
        if ($sel -lt 0) { $sel = [Math]::Max(0, [array]::FindIndex([object[]]$items, [Predicate[object]] { param($x) $x.Id -eq $lastId })) }
        $i = Select-Item -Items $items -Start $sel -Header { Write-Banner; Write-State $st } `
            -Footer (L '↑↓ пункт · Enter — выполнить · цифра — сразу · ? — справка · Esc — выход' '↑↓ item · Enter — run · digit — jump · ? — help · Esc — exit')
        if ($i -lt 0) { return }
        $id = Get-EntryId $items[$i]
        if ($id -eq 'exit') { return }
        $lastId = $items[$i].Id
        $pause = $false
        try { $r = @(Invoke-MenuAction $id $st); $pause = [bool]$r[-1] }   # последнее — признак паузы, до него — вывод действия
        catch {
            Log "ошибка: $($_.Exception.Message)"
            Write-Fail $_.Exception.Message
            $pause = $true
        }
        if ($pause) { Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu') }
    }
}

function Show-Help {
    Write-Screen (L 'Как это работает' 'How it works')
    $ru = @(
        '«Мои настройки»: один набор на все аккаунты. Бинды, мышь, интерфейс,'
        'прицел, статистика на экране и графика.'
        ''
        '  Сохранить           взять настройки с аккаунта, в который ты вошёл (один раз)'
        '  Перенести мои       записать их на аккаунт, в который ты вошёл'
        '  Уведомления         подскажут, если на аккаунте не твои настройки или на основном'
        '                      они поменялись в игре'
        '  Автоперенос         переносит сам при входе в любой аккаунт, кроме основного.'
        '                      Ты просто запускаешь VALORANT как обычно'
        '  На время            так настройки переносятся на любой аккаунт, кроме основного и помеченных'
        '                      «мой»: после игры исходные возвращаются (сами, если работает помощник;'
        '                      без него нажми «Вернуть исходные» перед выходом). «Насовсем»: без возврата.'
        ''
        'Уведомления и автоперенос по желанию, по умолчанию выключены. Для них работает'
        'помощник в фоне, он запускается вместе с Windows. Помощник не следит за тобой: он'
        'просыпается, когда открывается клиент Riot или ты входишь в аккаунт, и сверяет настройки'
        'через сам клиент. Он не отправляет твои данные в сторонние сервисы.'
        'Выключишь оба, и помощник удалится из автозапуска.'
        ''
        'Сохраняешь один раз. Дальше правки, сделанные в игре на твоих аккаунтах, подхватываются'
        'сами и уходят на остальные. Примерки про не подхватываются. Отменить: «Ещё» → «Бэкапы».'
        'Основной аккаунт автоперенос не меняет.'
        ''
        'Переносить нужно до запуска игры: она читает настройки при старте.'
        'Значок VALSET у часов (трей): цвет показывает статус, клик открывает панель. Выключается в его настройках.'
        'Графика хранится на этом ПК, а не в облаке: после «Сохранить» она сама уходит во все'
        'аккаунты этого ПК (если игра запущена, то сразу после выхода из неё).'
        'Перед каждой записью VALSET делает бэкап аккаунта: «Ещё» → «Бэкапы».'
        'Перед каждым изменением твоих настроек сохраняется версия: «Ещё» → «Бэкапы».'
        'Прицелы: на время на аккаунте только твои (его прицелы вернутся вместе с исходными);'
        'насовсем прицелы аккаунта остаются, твой добавляется и становится активным (до 15).'
    )
    $en = @(
        '“My settings” is one set for all your accounts: binds, mouse, interface,'
        'crosshair, on-screen stats and graphics.'
        ''
        '  Save             take the settings from the account you are logged into (once)'
        '  Apply mine       write them to the account you are logged into'
        '  Notifications    tell you when an account has different settings, or when your'
        '                   main account''s settings changed in game'
        '  Auto-apply       applies by itself when you log into any account except the main one.'
        '                   You just launch VALORANT as usual'
        '  For now          how applying works on any account except the main one and those marked'
        '                   “mine”: after the game its originals come back (by themselves with the'
        '                   helper; without it, use “Restore originals” before logout). “Permanently”: no restore.'
        ''
        'Notifications and auto-apply are optional and off by default. They use a background'
        'helper that starts with Windows. It does not watch you: it wakes up when the Riot Client'
        'opens or you log in, and compares settings through the client itself. It does not send'
        'your data to third-party services. Turn both off and the helper is removed from startup.'
        ''
        'You save once. After that, changes you make in game on your accounts are picked up by'
        'themselves and reach the others. Pro try-ons are not. Undo: “More” → “Backups”.'
        'Auto-apply never changes the main account.'
        ''
        'Apply before launching the game: it reads settings at startup.'
        'The VALSET tray icon near the clock: colour shows status, click opens the panel. Turn it off in its settings.'
        'Graphics live on this PC, not in the cloud: after “Save” they go to all accounts'
        'on this PC (if the game is running, right after you exit it).'
        'Before every write VALSET makes an account backup: “More” → “Backups”.'
        'Before every change to your settings a version is kept: “More” → “Backups”.'
        'Crosshairs: for now, only yours on the account (its own come back with the originals);'
        'permanently, the account''s crosshairs are kept, yours is added and made active (up to 15).'
    )
    $(if ($script:Lang -eq 'en') { $en } else { $ru }) | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host ''
    Write-StateLine (L 'Данные' 'Data') (L 'папка VALSET' 'VALSET folder') 'Gray' (L 'O — открыть папку' 'O — open folder')
    Write-StateLine (L 'Язык' 'Language') (L 'русский' 'English') 'Gray' (L 'L — English' 'L — русский')
    Write-Host ''
    Write-Host (L '    любая клавиша — назад' '    any key — back') -ForegroundColor DarkGray
    $k = Read-KeyOrQuit
    $c = "$($k.KeyChar)"
    if ($c -in 'o', 'O', 'щ', 'Щ') { Start-Process explorer.exe $Root }
    if ($c -in 'l', 'L', 'д', 'Д') {
        $script:Lang = if ($script:Lang -eq 'en') { 'ru' } else { 'en' }
        Set-Config 'lang' $script:Lang
        Log "язык интерфейса: $script:Lang"
    }
}

# Первый запуск (своих настроек ещё нет): что это и три шага.
function Show-Welcome {
    Clear-Host
    Write-Banner
    Write-Host ''
    $ru = @(
        'Привет. VALSET переносит твои настройки VALORANT на любой аккаунт:'
        'бинды, мышь, интерфейс, прицел, статистику на экране и графику.'
        ''
        '  1. Открой клиент Riot и войди в свой основной аккаунт.'
        '  2. Нажми «Сохранить», и VALSET возьмёт настройки с него (один раз).'
        '  3. Входи в другие аккаунты и жми «Перенести мои» до запуска игры.'
        '  Дальше правки в игре на твоих аккаунтах подхватываются сами. Отменить можно в истории.'
        ''
        'По желанию в меню: уведомления и автоперенос (сам при входе в аккаунт).'
        'Дальше пользуйся значком VALSET у часов. Консоль: ярлык «VALSET» в Пуске или команда valset.'
        ''
        'VALSET работает с клиентом Riot на этом ПК и облаком настроек Riot. Игру и её файлы'
        'он не трогает. Список предметов он загружает из интернета. Перед каждой записью делает бэкап.'
        ''
        'Язык: русский. L — English.'
    )
    $en = @(
        'Hi. VALSET puts your VALORANT settings on any of your accounts:'
        'binds, mouse, interface, crosshair, on-screen stats and graphics.'
        ''
        '  1. Open the Riot Client and log into your main account.'
        '  2. Press “Save” and VALSET takes the settings from it (once).'
        '  3. Log into your other accounts and press “Apply mine” before launching the game.'
        '  After that, changes you make in game on your accounts are picked up; undo is in “More” → “Backups”.'
        ''
        'Optional in the menu: notifications and auto-apply (by itself on login).'
        'Later: the VALSET icon near the clock; console: the “VALSET” shortcut in Start or the valset command.'
        ''
        'VALSET works with the Riot Client on this PC and the Riot settings cloud. It never touches'
        'the game or its files. It downloads the item list from the internet. A backup before every write.'
        ''
        'Language: English. L — русский.'
    )
    $(if ($script:Lang -eq 'en') { $en } else { $ru }) | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host ''
    Write-Host (L '    любая клавиша — дальше' '    any key — continue') -ForegroundColor DarkGray
    $k = Read-KeyOrQuit
    if ("$($k.KeyChar)" -in 'l', 'L', 'д', 'Д') {
        $script:Lang = if ($script:Lang -eq 'en') { 'ru' } else { 'en' }
        Set-Config 'lang' $script:Lang
        Show-Welcome
    }
}

# ── Одно окно меню ───────────────────────────────────────────────────────────

function Wait-MenuMutex([int]$ms) {
    try { $script:MenuMutex.WaitOne($ms) } catch [Threading.AbandonedMutexException] { $true }
}

# Одно окно меню: новое просит старое закрыться (сигналом) и остаётся само.
# Старое, занятое вводом текста, не слышит сигнал — тогда закрываем его по PID из menu.pid.
function Enter-SingleMenu {
    $script:MenuMutex = New-Object Threading.Mutex($false, 'Local\valset-menu')
    $script:QuitEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, 'Local\valset-menu-quit')
    $got = Wait-MenuMutex 0
    if (-not $got) {
        [void]$script:QuitEvent.Set()
        $got = Wait-MenuMutex 2000
        if (-not $got) {
            $old = if (Test-Path $MenuPidPath) { (Get-Content $MenuPidPath -Raw).Trim() }
            if ($old -and (Get-Process -Id $old -ErrorAction SilentlyContinue).Name -eq 'powershell') { Stop-Process -Id $old -Force }
            $got = Wait-MenuMutex 3000
        }
    }
    [void]$script:QuitEvent.Reset()
    if ($got) { New-Item -ItemType Directory -Force $Root | Out-Null; Set-Content $MenuPidPath $PID }
    $got
}
