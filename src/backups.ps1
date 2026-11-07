# backups.ps1 — два вида бэкапов.
#   История моих настроек: перед каждым «Сохранить» — копия profile.json + source.txt + graphics\ в history\<время>\
#     с подписью «что было дальше». Хранятся последние 50 (эталон обновляется после каждой игры).
#   Откат аккаунта: облачные настройки аккаунта перед каждой записью в него (backups\, последние 30).

$HistoryDir = Join-Path $Root 'history'
$HistoryMax = 50

function New-HistoryPoint([string]$why) {
    if (-not (Test-Path $ProfilePath)) { return }
    $dir = Join-Path $HistoryDir (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    Copy-ProfileFiles $Root $dir
    $script:LastHistory = $dir
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
        Write-Screen (L 'История моих настроек' 'My settings history')
        Write-Note (L 'Пока пусто. Версия сохраняется перед каждым «Сохранить» и изменением' 'Empty so far. A version is kept before every “Save” and change')
        Wait-AnyKey; return
    }
    $cur = if (Test-Path $ProfilePath) { Read-Profile } else { $null }
    $items = @(New-MenuSep (L 'Как было · новые сверху' 'As it was · newest first')) + @(foreach ($p in $points) {
        $hint = ''
        if ($cur) {
            try {
                $old = Get-Content (Join-Path $p.Dir 'profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $hint = if (Test-PrefsEqual $cur $old) { L 'то же, что сейчас' 'same as now' } else { "$(L 'вернёт настроек' 'settings to restore'): $([Math]::Max(1, (Compare-Prefs $old $cur).Count))" }
            } catch { $hint = L 'не прочитать' 'unreadable' }
        }
        New-MenuEntry "$(Format-When $p.When) · $($p.Why)" $hint $p.Dir
    })
    $i = Select-Item (L 'История моих настроек' 'My settings history') $items -Header {
        Write-Host (L '    Версия: твои настройки до изменения (хранятся последние 50). Выбери, и я покажу, что вернётся' '    A version: your settings before a change (the last 50 are kept). Pick one to see what comes back') -ForegroundColor DarkGray
    }
    if ($i -lt 0) { return }
    $p = $points | Where-Object Dir -eq $items[$i].Id
    Write-Screen (L 'История моих настроек' 'My settings history')
    Write-Field (L 'Версия' 'Version') "$(Format-When $p.When) · $($p.Why)"
    if ($p.From -and $p.From -ne '—') { Write-Field (L 'Сохранены с' 'Saved from') $p.From }
    $old = Get-Content (Join-Path $p.Dir 'profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cur) { Show-Diff (Compare-Prefs $cur $old) }
    if (-not (Confirm-Key (L 'Вернуть твои настройки к этой версии? Текущие сохранятся в истории' 'Restore your settings to this version? The current ones stay in history'))) { Write-Note (L 'Отменено' 'Cancelled'); Wait-AnyKey; return }
    try {
        New-HistoryPoint (L 'до возврата из истории' 'before restoring from history')
        Copy-ProfileFiles $p.Dir $Root
        Log "мои настройки возвращены к версии $(Format-When $p.When) ($($p.Why))"
        Write-Ok (L 'Твои настройки возвращены. Чтобы перенести их на аккаунт, нажми «Перенести мои»' 'Your settings restored. To apply them to an account, use “Apply mine”')
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
    if (-not $files) { Write-Screen (L 'Бэкап аккаунта' 'Account backup'); Write-Note (L 'Бэкапов пока нет. Они делаются перед каждым переносом' 'No backups yet. One is made before every apply'); Wait-AnyKey; return }
    $s = Get-Session
    $me = if ($s) { Short $s.Puuid } else { '' }
    $meName = if ($s) { Get-AccountLabel $s.Puuid } else { '' }
    # Сверяем каждый бэкап этого аккаунта с тем, что на нём сейчас, — в списке видно, сколько вернётся.
    $curJson = $null; $cur = $null
    if ($s) {
        Write-Screen (L 'Бэкап аккаунта' 'Account backup')
        try { $curJson = Invoke-Step (L 'Читаю настройки аккаунта' 'Reading the account settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json } catch {}
    }
    $mine = @($files | Where-Object { $_.BaseName.Split('_')[0] -eq $me })
    $other = @($files | Where-Object { $_.BaseName.Split('_')[0] -ne $me })
    $items = @()
    $groups = @(@{ T = (L 'Этот аккаунт · новые сверху' 'This account · newest first'); F = $mine }, @{ T = $(if ($me) { L 'Другие аккаунты' 'Other accounts' } else { L 'Все аккаунты · новые сверху' 'All accounts · newest first' }); F = $other })
    foreach ($grp in $groups) {
        if (-not $grp.F.Count) { continue }
        $items += New-MenuSep $grp.T
        foreach ($f in $grp.F) {
            $acc = $f.BaseName.Split('_')[0]
            $hint = ''
            if ($acc -eq $me -and $cur) {
                try {
                    $o = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $hint = if (Test-PrefsEqual $cur $o) { L 'то же, что сейчас' 'same as now' } else { "$(L 'вернёт настроек' 'settings to restore'): $([Math]::Max(1, (Compare-Prefs $cur $o).Count))" }
                } catch { $hint = L 'не прочитать' 'unreadable' }
            }
            $label = if ($acc -eq $me) { "$(L 'до переноса' 'before apply') $(Format-When $f.LastWriteTime)" } else { "$(Format-When $f.LastWriteTime) · $(Get-LabelByShort $acc)" }
            $items += New-MenuEntry $label $hint $f.FullName
        }
    }
    $i = Select-Item (L 'Бэкап аккаунта' 'Account backup') $items -Header {
        Write-Field (L 'Аккаунт' 'Account') $(if ($meName) { $meName } else { L 'нет входа в клиент Riot' 'not logged into the Riot Client' })
        Write-Host (L '    Бэкап: как было на аккаунте до переноса. Выбери, и я покажу, что вернётся' '    A backup: the account before an apply. Pick one to see what comes back') -ForegroundColor DarkGray
    }
    if ($i -lt 0) { return }
    Write-Screen (L 'Бэкап аккаунта' 'Account backup')
    try {
        if (-not $s) { $s = Connect-Session }
        $f = Get-Item -LiteralPath $items[$i].Id
        $acc = $f.BaseName.Split('_')[0]
        if ($acc -ne (Short $s.Puuid) -and -not (Confirm-Key (L "Это бэкап аккаунта $(Get-LabelByShort $acc), а ты вошёл в $(Get-AccountLabel $s.Puuid). Вернуть всё равно?" "This backup is of $(Get-LabelByShort $acc), but you are logged into $(Get-AccountLabel $s.Puuid). Restore it anyway?"))) {
            Write-Note (L 'Отменено' 'Cancelled'); Wait-AnyKey; return
        }
        $json = (Get-Content $f.FullName -Raw -Encoding UTF8).Trim()
        $old = $json | ConvertFrom-Json
        if (-not $curJson) { $curJson = Invoke-Step (L 'Читаю настройки аккаунта' 'Reading the account settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json }
        if (Test-PrefsEqual $cur $old) { Write-Ok (L 'Аккаунт уже в этом состоянии' 'The account is already in this state'); Wait-AnyKey; return }
        Show-Diff (Compare-Prefs $cur $old)
        if (-not (Confirm-Key (L 'Вернуть так?' 'Restore it?'))) { Write-Note (L 'Отменено, аккаунт не изменён' 'Cancelled, account unchanged'); Wait-AnyKey; return }
        $null = Invoke-Step (L 'Делаю бэкап' 'Backup') { New-Backup $s $curJson }
        Invoke-Step (L 'Записываю настройки' 'Writing the settings') { Set-Settings $s $json }
        Invoke-Step (L 'Проверяю запись' 'Verifying') {
            $check = Get-Settings $s | ConvertFrom-Json
            foreach ($k in $BindKeys + 'floatSettings' + 'intSettings') {
                if ((Get-JsonPart $check $k) -ne (Get-JsonPart $old $k)) { throw "в облаке '$k' не совпадает с бэкапом" }
            }
        }
        Log "откат $(Short $s.Puuid) к бэкапу $($f.Name)"
        Write-Ok (L "Настройки аккаунта $(Get-AccountLabel $s.Puuid) возвращены к $(Format-When $f.LastWriteTime)" "Settings of $(Get-AccountLabel $s.Puuid) restored to $(Format-When $f.LastWriteTime)")
        Write-Note (L 'Графику откат не меняет' 'The rollback does not change graphics')
    } catch {
        Log "ошибка: $($_.Exception.Message)"
        Write-Fail $_.Exception.Message
    }
    Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu')
}
