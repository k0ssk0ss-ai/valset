# doextra.ps1 — остальные действия `valset do` для панели: gfxsave, pro:<ник>, restore:<id>, history:<id>,
# set:<ключ>=<значение>, account:<puuid>:<действие>. Каждое пишущее оставляет точку отмены (last-action.json).
# Виды точек: account / profile — см. do.ps1; history — прежние твои настройки лежат в истории (data = имя папки);
# files — прежнее содержимое файлов (config.json, accounts.json).

$SetBools = [ordered]@{ notify = 'Уведомления|Notifications'; autoApply = 'Автоперенос|Auto-apply'; badge = 'Значок у клиента|Badge at the client'
                        app = 'Приложение в автозапуске|App at startup'; tempAuto = 'Автовозврат исходных|Auto-restore of originals'; gfxAll = 'Графика во все аккаунты ПК|Graphics to all PC accounts'
                        autoAsked = 'Вопрос про автоперенос|Auto-apply question' }

function Test-ExtraAction([string]$a) {
    $a -eq 'gfxsave' -or $a -match '^(pro|restore|history):.+$' -or $a -match '^set:\w+=.+$' -or $a -match '^account:[^:]+:\w+$'
}

function Write-UndoExtra([string]$kind, $data) {
    $o = [ordered]@{ action = $script:UndoAction; puuid = ''; kind = $kind; when = (Get-Stamp); data = $data }
    Write-FileSafe $LastActionPath (ConvertTo-Json -InputObject $o -Depth 6 -Compress)
}

function Save-UndoFiles([string[]]$paths) {
    Write-UndoExtra 'files' @(foreach ($p in $paths) { [ordered]@{ path = $p; content = $(if (Test-Path $p) { [string](Get-Content $p -Raw -Encoding UTF8) } else { $null }) } })
}

# Откат точек history / files (вызывается из Invoke-Undo).
function Restore-UndoExtra($a) {
    if ($a.kind -eq 'history') {
        New-HistoryPoint (L 'до «Отменить»' 'before “Undo”')
        if ($a.data) {
            $dir = Join-Path $HistoryDir $a.data
            if (-not (Test-Path $dir)) { throw (L 'Прежняя версия уже удалена из истории.' 'The earlier version was already removed from history.') }
            Copy-ProfileFiles $dir $Root
        } else { foreach ($f in $ProfilePath, $SourcePath) { if (Test-Path $f) { Remove-Item -LiteralPath $f } } }
        $cs = Get-Session; Sync-Graphics $(if ($cs) { $cs.Puuid } else { '' })
    } else {
        foreach ($f in @($a.data)) { if ($null -ne $f.content) { Write-FileSafe $f.path $f.content } elseif (Test-Path $f.path) { Remove-Item -LiteralPath $f.path } }
        Update-Agent
        $script:Lang = Get-Lang
    }
}

function Get-LeafId([string]$id) {
    if ($id -match '[\\/:]' -or $id -eq '..') { throw (L "некорректный идентификатор: $id" "invalid id: $id") }
    $id
}

function Invoke-DoPro([string]$nick, $r) {
    $all = Get-Pros; $pro = $all | Where-Object { $_.nick -eq $nick } | Select-Object -First 1
    if (-not $pro) { throw (L "Про «$nick» нет в списке." "Pro `“$nick`” is not in the list.") }
    $s = Connect-Session
    if (Test-GameRunning) {   # игра записала бы свою копию поверх — как в консоли
        Request-CloudAfterExit $s.Puuid "pro:$($pro.nick)"; $r.queued = $true
        return (L 'Ждёт выхода из игры' 'Waiting for the game to close')
    }
    if (Test-ProNeedsDpi $pro) { throw (L 'Нужен DPI мыши, чтобы пересчитать чувствительность — задай его в настройках.' 'Your mouse DPI is needed to convert the sensitivity — set it in settings.') }
    $script:LastOp = $null
    Invoke-ApplyPro $pro $s 6>$null
    if ($script:LastOp -eq 'same') { L "Уже как у $($pro.nick)" "Already like $($pro.nick)" } else { L "Настройки $($pro.nick) на время" "$($pro.nick)'s settings, for now" }
}

function Invoke-DoRestore([string]$id) {
    $f = Join-Path $BackupDir "$(Get-LeafId $id).json"
    if (-not (Test-Path $f)) { throw (L 'Такого бэкапа нет.' 'No such backup.') }
    $s = Connect-Session
    $acc = $id.Split('_')[0]
    if ($acc -ne (Short $s.Puuid)) { throw (L "Это бэкап аккаунта $(Get-LabelByShort $acc), а вошёл $(Get-AccountLabel $s.Puuid)." "This backup is of $(Get-LabelByShort $acc), but you are logged into $(Get-AccountLabel $s.Puuid).") }
    if (Test-GameRunning) { throw (L 'Игра запущена — откатывай после её закрытия.' 'The game is running — roll back after closing it.') }
    $json = (Get-Content $f -Raw -Encoding UTF8).Trim()
    $old = $json | ConvertFrom-Json
    $curJson = Get-Settings $s
    if (Test-PrefsEqual ($curJson | ConvertFrom-Json) $old) { return (L 'Аккаунт уже в этом состоянии' 'The account is already in this state') }
    Save-UndoPoint 'account' $s.Puuid $curJson
    $null = New-Backup $s $curJson
    Set-Settings $s $json
    Assert-Written $s $json (L 'откат' 'rollback')
    Log "откат $(Short $s.Puuid) к бэкапу $id"
    L "Аккаунт возвращён к $(Format-When (Get-Item $f).LastWriteTime)" "Account restored to $(Format-When (Get-Item $f).LastWriteTime)"
}

function Invoke-DoHistory([string]$id) {
    $dir = Join-Path $HistoryDir (Get-LeafId $id)
    $p = Get-HistoryPoints | Where-Object { $_.Dir -eq $dir } | Select-Object -First 1
    if (-not $p) { throw (L 'Такой версии нет.' 'No such version.') }
    $stage = Join-Path $Root 'history-stage'   # самая старая версия может вытесниться новой точкой — берём копию заранее
    Copy-ProfileFiles $dir $stage
    try {
        $script:LastHistory = $null
        New-HistoryPoint (L 'до возврата из истории' 'before restoring from history')
        Write-UndoExtra 'history' $(if ($script:LastHistory) { Split-Path $script:LastHistory -Leaf })
        Copy-ProfileFiles $stage $Root
    } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    Log "мои настройки возвращены к версии $(Format-When $p.When) ($($p.Why))"
    $cs = Get-Session; Sync-Graphics $(if ($cs) { $cs.Puuid } else { '' })
    L "Твои настройки возвращены к версии $(Format-When $p.When)" "Your settings restored to the version of $(Format-When $p.When)"
}

function Invoke-DoSet([string]$key, [string]$val) {
    $c = Get-Config
    if ($SetBools.Contains($key)) {
        if ($val -notin 'on', 'off') { throw (L "значение должно быть on или off: $val" "value must be on or off: $val") }
        $v = $val -eq 'on'; $name = L ($SetBools[$key].Split('|')[0]) ($SetBools[$key].Split('|')[1])
        if ($null -ne $c.$key -and [bool]$c.$key -eq $v) { return "${name}: $(L 'без изменений' 'unchanged')" }
        $msg = "${name}: $(if ($v) { L 'вкл' 'on' } else { L 'выкл' 'off' })"
    } elseif ($key -eq 'lang') {
        if ($val -notin 'ru', 'en') { throw (L 'язык: ru или en' 'language: ru or en') }
        $v = $val
    } elseif ($key -eq 'dpi') {
        $v = $val -as [int]
        if ($v -lt 100 -or $v -gt 32000) { throw (L 'DPI мыши: число от 100 до 32000' 'Mouse DPI: a number from 100 to 32000') }
        $msg = L "DPI мыши: $v" "Mouse DPI: $v"
    } else { throw (L "неизвестная настройка: $key" "unknown setting: $key") }
    Save-UndoFiles @($ConfigPath)
    Set-Config $key $v
    if ($key -eq 'autoApply') { Set-Config 'autoAsked' $true }   # выбрал сам — вопрос в панели больше не нужен
    if ($key -eq 'lang') { $script:Lang = $v; $msg = L 'Язык: русский' 'Language: English' }
    Log "настройка $key = $val"
    $msg
}

function Invoke-DoAccount([string]$puuid, [string]$act) {
    $h = Read-Accounts
    if (-not $h.ContainsKey($puuid)) { throw (L 'Такого аккаунта нет в списке.' 'No such account in the list.') }
    if ($act -notin 'main', 'own', 'notown', 'forget') { throw (L "неизвестное действие с аккаунтом: $act" "unknown account action: $act") }
    if ($act -in 'own', 'notown' -and $puuid -eq (Get-MainPuuid)) { throw (L 'Для основного аккаунта это не применимо.' 'Not applicable to the main account.') }
    $name = Get-AccountLabel $puuid
    Save-UndoFiles @($AccountsPath)
    switch ($act) {
        'main'   { Set-MainAccount $puuid; L "Основной аккаунт: $name" "Main account: $name" }
        'own'    { Set-AccountState $puuid @{ own = $true }; L "$name — мой, переношу насовсем" "$name is mine, applying permanently" }
        'notown' { Set-AccountState $puuid @{ own = $false }; L "$name — не мой, переношу на время" "$name is not mine, applying for now" }
        'forget' { $h.Remove($puuid); Save-Accounts $h; Log "аккаунт забыт: $(Short $puuid)"; L "$name убран из списка" "$name removed from the list" }
    }
}

# Возвращает короткое сообщение; $r — ответ Invoke-Do (сюда пишется queued).
function Invoke-DoExtra([string]$action, $r) {
    switch -regex ($action) {
        '^gfxsave$' {
            $script:LastHistory = $null
            Invoke-SaveGraphics $null 6>$null
            if ($script:LastHistory) { Write-UndoExtra 'history' (Split-Path $script:LastHistory -Leaf) }
            L 'Графика сохранена' 'Graphics saved'
        }
        '^pro:(.+)$'     { Invoke-DoPro $Matches[1] $r }
        '^restore:(.+)$' { Invoke-DoRestore $Matches[1] }
        '^history:(.+)$' { Invoke-DoHistory $Matches[1] }
        '^set:(\w+)=(.+)$' { Invoke-DoSet $Matches[1] $Matches[2] }
        '^account:([^:]+):(\w+)$' { Invoke-DoAccount $Matches[1] $Matches[2] }
    }
}
