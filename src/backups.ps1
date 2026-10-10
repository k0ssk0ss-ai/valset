# backups.ps1 — два вида бэкапов.
#   История моих настроек: перед каждым «Запомнить» — копия profile.json + source.txt + graphics\ в history\<время>\
#     с подписью «что было дальше». Хранятся последние 10.
#   Откат аккаунта: облачные настройки аккаунта перед каждой записью в него (backups\, последние 30).

$HistoryDir = Join-Path $Root 'history'
$HistoryMax = 10

function New-HistoryPoint([string]$why) {
    if (-not (Test-Path $ProfilePath)) { return }
    $dir = Join-Path $HistoryDir (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    Copy-ProfileFiles $Root $dir
    $meta = [ordered]@{ when = (Get-Stamp); why = $why; from = (Get-AccountLabel (Get-Source)) }
    Set-Content (Join-Path $dir 'meta.json') (ConvertTo-Json ([pscustomobject]$meta)) -Encoding UTF8
    Get-ChildItem $HistoryDir -Directory | Sort-Object Name -Descending | Select-Object -Skip $HistoryMax |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}


function Get-HistoryPoints {
    @(Get-ChildItem $HistoryDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
        $m = try { Get-Content (Join-Path $_.FullName 'meta.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
        [pscustomobject]@{ Dir = $_.FullName; When = "$($m.when)"; Why = "$($m.why)"; From = "$($m.from)" }
    })
}

function Show-History {
    $points = Get-HistoryPoints
    if (-not $points) {
        Write-Screen (L 'ИСТОРИЯ МОИХ НАСТРОЕК' 'MY SETTINGS HISTORY')
        Write-Note (L 'пока пусто: версия сохраняется перед каждым «Запомнить как мои», правкой и импортом' 'empty so far: a version is kept before every “Save as mine”, edit and import')
        Wait-AnyKey; return
    }
    $cur = if (Test-Path $ProfilePath) { Read-Profile } else { $null }
    $items = @(New-MenuSep (L 'КАК БЫЛО · НОВЫЕ СВЕРХУ' 'AS IT WAS · NEWEST FIRST')) + @(foreach ($p in $points) {
        $hint = ''
        if ($cur) {
            try {
                $old = Get-Content (Join-Path $p.Dir 'profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $hint = if (Test-PrefsEqual $cur $old) { L 'облачные — как сейчас' 'cloud part — same as now' } else { "$(L 'вернёт настроек' 'settings to restore'): $([Math]::Max(1, (Compare-Prefs $old $cur).Count))" }
            } catch { $hint = L 'не читается' 'unreadable' }
        }
        New-MenuEntry "$(Format-When $p.When) · $($p.Why)" $hint $p.Dir
    })
    $i = Select-Item (L 'ИСТОРИЯ МОИХ НАСТРОЕК' 'MY SETTINGS HISTORY') $items -Header {
        Write-Host (L '    версия — твои настройки перед изменением (последние 10); выбери — покажу, что вернётся' '    a version = your settings before a change (last 10); pick one to see what comes back') -ForegroundColor DarkGray
    }
    if ($i -lt 0) { return }
    $p = $points | Where-Object Dir -eq $items[$i].Id
    Write-Screen (L 'ИСТОРИЯ МОИХ НАСТРОЕК' 'MY SETTINGS HISTORY')
    Write-Field (L 'Версия' 'Version') "$(Format-When $p.When) · $($p.Why)"
    if ($p.From -and $p.From -ne '—') { Write-Field (L 'Запомнены с' 'Saved from') $p.From }
    $old = Get-Content (Join-Path $p.Dir 'profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cur) { Show-Diff (Compare-Prefs $cur $old) }
    if (-not (Confirm-Key (L 'Вернуть твои настройки к этой версии? Текущие сохранятся в истории' 'Restore your settings to this version? The current ones stay in history'))) { Write-Note (L 'отменено' 'cancelled'); Wait-AnyKey; return }
    try {
        New-HistoryPoint (L 'до возврата из истории' 'before restoring from history')
        Copy-ProfileFiles $p.Dir $Root
        Log "мои настройки возвращены к версии $(Format-When $p.When) ($($p.Why))"
        Write-Ok (L 'Твои настройки возвращены. На аккаунт — «Перенести мои»' 'Your settings restored. To an account — “Apply mine”')
        $cs = Get-Session; Sync-Graphics $(if ($cs) { $cs.Puuid } else { '' })
    } catch {
        Log "ошибка: $($_.Exception.Message)"
        Write-Fail $_.Exception.Message
    }
    Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu')
}

function Copy-ProfileFiles([string]$from, [string]$to) {
    New-Item -ItemType Directory -Force $to | Out-Null
    foreach ($f in 'profile.json', 'source.txt') {
        $src = Join-Path $from $f; $dst = Join-Path $to $f
        if (Test-Path $src) { Copy-Item $src $dst -Force } elseif (Test-Path $dst) { Remove-Item -LiteralPath $dst }
    }
    $g = Join-Path $to 'graphics'; $sg = Join-Path $from 'graphics'
    if (Test-Path $g) { Remove-Item -LiteralPath $g -Recurse -Force }
    if (Test-Path $sg) { Copy-Item $sg $g -Recurse -Force }
}

# Откат: бэкап — настройки аккаунта перед применением эталона (облако). Перед откатом — ещё один бэкап.
function Show-Restore {
    $files = @(Get-ChildItem $BackupDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15)
    if (-not $files) { Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK'); Write-Note (L 'бэкапов пока нет — они делаются перед каждым переносом' 'no backups yet — one is made before every apply'); Wait-AnyKey; return }
    $s = Get-Session
    $me = if ($s) { Short $s.Puuid } else { '' }
    $meName = if ($s) { Get-AccountLabel $s.Puuid } else { '' }
    # Сверяем каждый бэкап этого аккаунта с тем, что на нём сейчас, — в списке видно, сколько вернётся.
    $curJson = $null; $cur = $null
    if ($s) {
        Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK')
        try { $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json } catch {}
    }
    $mine = @($files | Where-Object { $_.BaseName.Split('_')[0] -eq $me })
    $other = @($files | Where-Object { $_.BaseName.Split('_')[0] -ne $me })
    $items = @()
    $groups = @(@{ T = (L 'ЭТОТ АККАУНТ · НОВЫЕ СВЕРХУ' 'THIS ACCOUNT · NEWEST FIRST'); F = $mine }, @{ T = $(if ($me) { L 'ДРУГИЕ АККАУНТЫ' 'OTHER ACCOUNTS' } else { L 'ВСЕ АККАУНТЫ · НОВЫЕ СВЕРХУ' 'ALL ACCOUNTS · NEWEST FIRST' }); F = $other })
    foreach ($grp in $groups) {
        if (-not $grp.F.Count) { continue }
        $items += New-MenuSep $grp.T
        foreach ($f in $grp.F) {
            $acc = $f.BaseName.Split('_')[0]
            $hint = ''
            if ($acc -eq $me -and $cur) {
                try {
                    $o = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $hint = if (Test-PrefsEqual $cur $o) { L 'как сейчас — откатывать нечего' 'same as now — nothing to roll back' } else { "$(L 'вернёт настроек' 'settings to restore'): $([Math]::Max(1, (Compare-Prefs $cur $o).Count))" }
                } catch { $hint = L 'не читается' 'unreadable' }
            }
            $label = if ($acc -eq $me) { "$(L 'до переноса' 'before apply') $(Format-When $f.LastWriteTime)" } else { "$(Format-When $f.LastWriteTime) · $(Get-LabelByShort $acc)" }
            $items += New-MenuEntry $label $hint $f.FullName
        }
    }
    $i = Select-Item (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK') $items -Header {
        Write-Field (L 'Аккаунт' 'Account') $(if ($meName) { $meName } else { L 'нет входа в клиент Riot' 'not logged into the Riot Client' })
        Write-Host (L '    бэкап — как было на аккаунте перед переносом; выбери — покажу, что именно вернётся' '    a backup = the account before an apply; pick one to see exactly what comes back') -ForegroundColor DarkGray
    }
    if ($i -lt 0) { return }
    Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK')
    try {
        if (-not $s) { $s = Connect-Session }
        $f = Get-Item -LiteralPath $items[$i].Id
        $acc = $f.BaseName.Split('_')[0]
        if ($acc -ne (Short $s.Puuid) -and -not (Confirm-Key (L "Это бэкап аккаунта $(Get-LabelByShort $acc), а вошёл $(Get-AccountLabel $s.Puuid). Залить всё равно?" "This backup is of $(Get-LabelByShort $acc), but you are logged into $(Get-AccountLabel $s.Puuid). Write it anyway?"))) {
            Write-Note (L 'отменено' 'cancelled'); Wait-AnyKey; return
        }
        $json = (Get-Content $f.FullName -Raw -Encoding UTF8).Trim()
        $old = $json | ConvertFrom-Json
        if (-not $curJson) { $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json }
        if (Test-PrefsEqual $cur $old) { Write-Ok (L 'Аккаунт уже в этом состоянии' 'The account is already in this state'); Wait-AnyKey; return }
        Show-Diff (Compare-Prefs $cur $old)
        if (-not (Confirm-Key (L 'Вернуть так?' 'Restore it?'))) { Write-Note (L 'отменено, аккаунт не тронут' 'cancelled, account untouched'); Wait-AnyKey; return }
        $null = Invoke-Step (L 'Резервная копия' 'Backup') { New-Backup $s $curJson }
        Invoke-Step (L 'Запись в облако Riot' 'Writing to the Riot cloud') { Set-Settings $s $json }
        Invoke-Step (L 'Проверка записи' 'Verifying') {
            $check = Get-Settings $s | ConvertFrom-Json
            foreach ($k in $BindKeys + 'floatSettings' + 'intSettings') {
                if ((Get-JsonPart $check $k) -ne (Get-JsonPart $old $k)) { throw "в облаке '$k' не совпадает с бэкапом" }
            }
        }
        Log "откат $(Short $s.Puuid) к бэкапу $($f.Name)"
        Write-Ok (L "Настройки аккаунта $(Get-AccountLabel $s.Puuid) возвращены к $(Format-When $f.LastWriteTime)" "Settings of $(Get-AccountLabel $s.Puuid) restored to $(Format-When $f.LastWriteTime)")
        Write-Note (L 'графику этот откат не трогает: прошлые файлы — *.valset.bak в папке аккаунта' 'this rollback does not touch graphics: previous files are *.valset.bak in the account folder')
    } catch {
        Log "ошибка: $($_.Exception.Message)"
        Write-Fail $_.Exception.Message
    }
    Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu')
}
