# history.ps1 — история моих настроек: перед каждым изменением (Запомнить, правка, импорт, смена набора)
# копия profile.json + source.txt + graphics\ в history\<время>\ с подписью «что было дальше». Хранятся последние 10.

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

# Одна точка истории на сеанс правок (редактор, импорт): не плодим версию на каждое нажатие.
function Protect-Profile([string]$why) {
    if ($script:ProfileBackedUp) { return }
    New-HistoryPoint $why
    $script:ProfileBackedUp = $true
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
