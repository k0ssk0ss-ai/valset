# do.ps1 — команды для приложения (src\app\*.cs): `valset state` и `valset do <действие>` печатают ровно одну строку JSON
# (UTF-8, без оформления и без вопросов), а также `valset pros|more` — консольное меню сразу на нужном экране.
# Перед каждым действием, пишущим данные, сохраняется last-action.json — что было до; `do undo` возвращает это обратно.

$LastActionPath = Join-Path $Root 'last-action.json'

function Get-Plural([int]$n, [string]$one, [string]$few, [string]$many) {
    $m = $n % 100; $d = $n % 10
    if ($m -ge 11 -and $m -le 14) { $many } elseif ($d -eq 1) { $one } elseif ($d -ge 2 -and $d -le 4) { $few } else { $many }
}

# ── Состояние ────────────────────────────────────────────────────────────────

# Что предложить — как Get-Suggested в menu.ps1, плюс «вернуть исходные», если аккаунт на время (при запущенной игре — нет:
# исходные вернутся сами после выхода из неё).
function Get-SuggestedId($st) {
    if ($st.Error) { return '' }
    if (-not $st.Session) { return $(if ($st.Client) { '' } else { 'client' }) }
    if (Test-Temp $st.Session.Puuid) { return $(if ($st.Game) { '' } else { 'untemp' }) }
    if (-not $st.Have -or ($st.IsMain -and -not $st.Same)) { 'save' } elseif (-not $st.Same) { 'apply' } else { '' }
}

function ConvertTo-StateObject($st) {
    $c = if ($st.Cfg) { $st.Cfg } else { Get-Config }
    $p = if ($st.Session) { $st.Session.Puuid } else { '' }
    $pending = [bool]($p -and (@(Get-Content $CloudQueue -Encoding UTF8 -ErrorAction SilentlyContinue) | Where-Object { $_ -and $_.StartsWith("$p`t") }))
    [ordered]@{
        client = [bool]$st.Client; game = [bool]$st.Game
        account = "$($st.Name)"; puuid = "$p"; isMain = [bool]$st.IsMain; have = [bool]$st.Have
        same = $(if ($null -ne $st.Same) { [bool]$st.Same } else { $null })
        diff = [int]$st.Diff
        diffList = @(ConvertTo-DiffItems $st.DiffList)
        temp = [bool]($p -and (Test-Temp $p)); own = [bool]($p -and -not (Test-TempDefault $p)); pending = $pending
        synced = @($st.Synced | Where-Object { $_ } | ForEach-Object { "$_" })
        suggested = (Get-SuggestedId $st)
        autoApply = [bool]$c.autoApply; notify = [bool]$c.notify; badge = [bool]$c.badge
        lang = $script:Lang; error = "$($st.Error)"
    }
}

function Get-StateJson {
    try { $o = ConvertTo-StateObject (Get-MenuState 6>$null) }
    catch { $o = ConvertTo-StateObject @{ Error = $_.Exception.Message } }
    ConvertTo-Json -InputObject $o -Depth 5 -Compress
}

function Write-StateJson {
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
    Write-Output (Get-StateJson)
}

# ── Отмена ───────────────────────────────────────────────────────────────────

function Remove-LastAction { if (Test-Path $LastActionPath) { Remove-Item -LiteralPath $LastActionPath } }

# Вызывается из Invoke-Apply / Invoke-Save прямо перед записью; вне `valset do` ($script:UndoAction пуст) ничего не делает.
# account — json облака аккаунта до записи; profile — profile.json и source.txt до записи.
function Save-UndoPoint([string]$kind, [string]$puuid, $json = $null) {
    if (-not $script:UndoAction) { return }
    $o = [ordered]@{ action = $script:UndoAction; puuid = $puuid; kind = $kind; when = (Get-Stamp); json = $null; base = $null; temp = $null; source = $null }
    if ($kind -eq 'account') {
        $o.json = $json
        if (Test-Temp $puuid) { $o.temp = [string](Get-Content (Get-TempPath $puuid) -Raw -Encoding UTF8) }
    } else {
        if (Test-Path $ProfilePath) { $o.json = [string](Get-Content $ProfilePath -Raw -Encoding UTF8); $o.source = Get-Source }
    }
    $b = Get-SessionBase $puuid
    if ($b) { $o.base = [ordered]@{ scope = "$($b.scope)"; json = "$($b.json)" } }
    Write-FileSafe $LastActionPath (ConvertTo-Json -InputObject $o -Depth 5 -Compress)
}

function Invoke-Undo {
    if (-not (Test-Path $LastActionPath)) { throw (L 'Нечего отменять.' 'Nothing to undo.') }
    $a = Get-Content $LastActionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($a.kind -in 'history', 'files') { Restore-UndoExtra $a }
    elseif ($a.kind -eq 'account') {
        $s = Connect-Session
        if ($s.Puuid -ne $a.puuid) { throw (L "Отменить можно только в том аккаунте, где было действие ($(Get-AccountLabel $a.puuid))." "Undo works only on the account where it happened ($(Get-AccountLabel $a.puuid)).") }
        if (Test-GameRunning) { throw (L 'Игра запущена — отмени после её закрытия.' 'The game is running — undo after closing it.') }
        Set-Settings $s $a.json
        Assert-Written $s $a.json (L 'отмена' 'undo')
        if ($a.base) { Set-SessionBase $a.puuid $a.base.json $a.base.scope } else { Clear-SessionBase $a.puuid }
        if ($a.temp) { Write-FileSafe (Get-TempPath $a.puuid) $a.temp } else { Clear-Temp $a.puuid }
        Set-AccountState $a.puuid @{ state = ''; checked = (Get-Stamp) }
    } else {
        New-HistoryPoint (L 'до «Отменить»' 'before “Undo”')
        if ($a.json) {
            Write-FileSafe $ProfilePath $a.json
            if ($a.source) { Write-FileSafe $SourcePath $a.source }
        } else {
            foreach ($f in $ProfilePath, $SourcePath) { if (Test-Path $f) { Remove-Item -LiteralPath $f } }
        }
        if ($a.action -eq 'save') { if ($a.base) { Set-SessionBase $a.puuid $a.base.json $a.base.scope } else { Clear-SessionBase $a.puuid } }
    }
    Remove-LastAction
    Log "отменено: $($a.action) ($(Short $a.puuid))"
}

# ── Действия ─────────────────────────────────────────────────────────────────

# Ответ: ok, message (коротко, на языке интерфейса), undo (можно отменить), queued (ждёт выхода из игры).
function Invoke-Do([string]$action) {
    $r = [ordered]@{ ok = $false; message = ''; undo = $false; queued = $false }
    $script:LastApply = $null; $script:LastOp = $null; $script:UndoAction = $null
    try {
        $writes = 'apply', 'binds', 'applyperm', 'save', 'savebinds', 'untemp'
        if ($action -notin ($writes + 'undo') -and -not (Test-ExtraAction $action)) { throw (L "неизвестное действие: $action" "unknown action: $action") }
        if ($action -ne 'undo') { Remove-LastAction; $script:UndoAction = $action }   # старая отмена после новой записи не нужна
        $msg = $null
        switch ($action) {
            { $_ -in 'apply', 'binds', 'applyperm' } {
                Invoke-Apply $null -BindsOnly:($action -eq 'binds') -Permanent:($action -eq 'applyperm') 6>$null
                $la = $script:LastApply
                if ($la.Queued) { $r.queued = $true; $msg = L 'Ждёт выхода из игры' 'Waiting for the game to close' }
                elseif ($la.Same) { $msg = if ($action -eq 'binds') { L 'Бинды уже твои' 'Binds are already yours' } else { L 'Настройки уже твои' 'Settings are already yours' } }
                elseif ($action -eq 'binds') { $msg = L 'Бинды перенесены' 'Binds applied' }
                else {
                    $n = [int]$la.Count
                    $msg = L "Применено$(if ($la.Temp) { ' на время' }): $n $(Get-Plural $n 'настройка' 'настройки' 'настроек')" "Applied$(if ($la.Temp) { ' for now' }): $n setting$(if ($n -ne 1) { 's' })"
                }
            }
            'save' {
                Invoke-Save $null 6>$null
                $msg = if ($script:LastOp -eq 'gfx') { L 'Сохранено вместе с графикой' 'Saved with graphics' } else { L 'Сохранено' 'Saved' }
            }
            'savebinds' {
                Invoke-SaveBinds $null 6>$null
                $msg = if ($script:LastOp -eq 'same') { L 'Бинды уже совпадают' 'Binds already match' } else { L 'Бинды сохранены' 'Binds saved' }
            }
            'untemp' {
                $s = Connect-Session
                if (-not (Test-Temp $s.Puuid)) { $msg = L 'Нечего возвращать' 'Nothing to restore' }
                elseif (Test-GameRunning) { throw (L 'Игра запущена — исходные вернутся после её закрытия.' 'The game is running — the originals come back after it closes.') }
                else {
                    Save-UndoPoint 'account' $s.Puuid (Get-Settings $s)
                    $null = Invoke-RestoreTemp $s 6>$null
                    $msg = L 'Исходные настройки возвращены' 'Original settings restored'
                }
            }
            'undo' { Invoke-Undo 6>$null; $msg = L 'Отменено' 'Undone' }
            default { $msg = @(Invoke-DoExtra $action $r)[-1] }
        }
        $r.ok = $true; $r.message = $msg
    } catch {
        $r.message = $_.Exception.Message
        Log "do $($action): ошибка: $($_.Exception.Message)"
    }
    $r.undo = (-not $r.queued) -and $action -ne 'undo' -and (Test-Path $LastActionPath)
    $script:UndoAction = $null
    $r
}

function Get-DoJson([string]$action) { ConvertTo-Json -InputObject (Invoke-Do $action) -Depth 3 -Compress }

# Печатает ровно одну строку JSON; удалось ли действие — в $script:DoOk (иначе код выхода 1).
function Write-DoJson([string]$action) {
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
    $r = Invoke-Do $action
    $script:DoOk = [bool]$r.ok
    Write-Output (ConvertTo-Json -InputObject $r -Depth 3 -Compress)
}

# ── Консольное меню сразу на экране «Про» / «Ещё» ────────────────────────────

function Show-OneScreen([string]$which) {
    if (-not (Enter-SingleMenu)) { Write-Fail (L 'Не удалось закрыть старое окно valset.' 'Could not close the old VALSET window.'); return }
    $Host.UI.RawUI.WindowTitle = 'VALSET'
    $script:InMenu = $true
    try {
        if ($which -eq 'pros') {
            if (-not (Get-Pros).Count) { Write-Screen (L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS'); Write-Note (L 'список про пока пуст или не скачался' 'the pro list is empty or could not be downloaded'); Wait-AnyKey; return }
            $pause = Show-Pros
        } else {
            Clear-Host; Write-Host ''; Write-Host (L '    проверяю аккаунт…' '    checking the account…') -ForegroundColor DarkGray
            $pause = Show-More (Get-MenuState)
        }
    } catch {
        Log "ошибка: $($_.Exception.Message)"
        Write-Fail $_.Exception.Message
        $pause = $true
    }
    if ($pause) { Wait-AnyKey (L 'любая клавиша — закрыть' 'any key — close') }
}
