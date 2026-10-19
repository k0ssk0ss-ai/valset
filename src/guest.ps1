# guest.ps1 — «на время» (стандарт): перенос на любой аккаунт, кроме основного и помеченных «мой», временный —
# исходные настройки аккаунта сохраняются и возвращаются после игры.
#
# Исходные — temp\<puuid>.json, отдельно от бэкапов (их чистка не трогает); повторный перенос их не затирает.
# Вернуть можно, только пока ты в этом аккаунте: после выхода записать в его облако уже нельзя. Клиент Riot после
# игры обычно не закрывают — поэтому помощник возвращает исходные через ~3 с после закрытия игры (событие клиента).
# Не успели (вышли из аккаунта раньше) — исходные останутся ждать: вернутся при следующем входе в этот аккаунт
# после следующей игры, либо вручную «Вернуть исходные».
# Помощник для этого включается только с согласия (config.json → tempAuto, спрашивается один раз).
# Графику не трогаем: она хранится на ПК, у владельца аккаунта — своя.

$TempDir = Join-Path $Root 'temp'

function Get-TempPath([string]$puuid) { Join-Path $TempDir "$puuid.json" }
function Test-Temp([string]$puuid) { [bool]($puuid -and (Test-Path (Get-TempPath $puuid))) }
function Test-AnyTemp { [bool](Get-ChildItem $TempDir -Filter '*.json' -ErrorAction SilentlyContinue) }
function Test-Own([string]$puuid) { [bool]($puuid -and (Read-Accounts)[$puuid].own) }

# Перенос на время? Основной и помеченные «мой» — насовсем.
function Test-TempDefault([string]$puuid) { $puuid -ne (Get-MainPuuid) -and -not (Test-Own $puuid) }

# Запомнить исходные — только если их ещё нет (иначе второй перенос записал бы сюда уже твои настройки).
function Save-TempOriginal([string]$puuid, [string]$json) {
    New-Item -ItemType Directory -Force $TempDir | Out-Null
    $p = Get-TempPath $puuid
    if (-not (Test-Path $p)) { Write-FileSafe $p $json }
}

# ── Сессионный эталон ─────────────────────────────────────────────────────────
# base\<puuid>.json — что VALSET последним записал (или запомнил) на аккаунт с твоими настройками: { scope, json }.
# Есть база — аккаунт участвует: правки в игре (облако ≠ база) переносятся в эталон (Merge-Reference, session.ps1).
# Примерка про базу снимает (сенса про — не твоя); возврат исходных — тоже, если исходные не совпадают с эталоном.
$BaseDir = Join-Path $Root 'base'
function Get-BasePath([string]$puuid) { Join-Path $BaseDir "$puuid.json" }
function Set-SessionBase([string]$puuid, [string]$json, [string]$scope = 'all') {
    Write-FileSafe (Get-BasePath $puuid) (ConvertTo-Json -InputObject ([ordered]@{ scope = $scope; json = $json }) -Compress)
}
function Get-SessionBase([string]$puuid) {
    $p = Get-BasePath $puuid
    if (-not $puuid -or -not (Test-Path $p)) { return $null }
    try { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}
function Clear-SessionBase([string]$puuid) { $p = Get-BasePath $puuid; if (Test-Path $p) { Remove-Item -LiteralPath $p } }

# Правки в игре на этом аккаунте → в эталон. Возвращает подписи изменённого (пусто — нечего переносить).
function Update-Reference($s, [string]$nowJson) {
    $b = Get-SessionBase $s.Puuid
    if (-not $b -or -not (Test-Path $ProfilePath)) { return @() }
    if (-not $nowJson) { $nowJson = Get-Settings $s }
    if ($nowJson -ceq $b.json) { return @() }
    $old = Read-Profile
    $r = Merge-Reference $old ($b.json | ConvertFrom-Json) ($nowJson | ConvertFrom-Json) $b.scope
    Set-SessionBase $s.Puuid $nowJson $b.scope
    if (-not @($r.Changed).Count) { return @() }
    New-HistoryPoint "$(L 'до правок из игры' 'before in-game changes') ($(Get-AccountLabel $s.Puuid))"
    Save-Profile $r.Ref
    $names = @(Compare-Prefs $old $r.Ref | ForEach-Object { $_.What } | Select-Object -Unique)
    if (-not $names.Count) { $names = @($r.Changed) }
    Log "эталон: правки из игры с $(Get-AccountLabel $s.Puuid) ($($names.Count)): $($names -join ', ')"
    $names
}

# Короткая подпись для уведомления: «сенса, прицел и ещё 3».
function Format-Changed([string[]]$names) {
    $head = @($names | Select-Object -First 3) -join ', '
    if ($names.Count -gt 3) { "$head $(L 'и ещё' 'and') $($names.Count - 3)" } else { $head }
}

function Clear-Temp([string]$puuid) {
    $p = Get-TempPath $puuid
    if (Test-Path $p) { Remove-Item -LiteralPath $p }
}

# Вернуть исходные настройки аккаунта, в который ты вошёл. $true — вернули.
function Invoke-RestoreTemp($s) {
    if (-not $s) { $s = Connect-Session }
    $p = Get-TempPath $s.Puuid
    if (-not (Test-Path $p)) {
        if ($script:Fancy) { Write-Note (L 'на этом аккаунте нечего возвращать' 'nothing to restore on this account') }
        return $false
    }
    $json = (Get-Content $p -Raw -Encoding UTF8).Trim()
    # сначала забрать в эталон то, что ты поменял в игре с твоими настройками (у примерки про базы нет — не заберётся)
    try { $script:LastSync = Update-Reference $s } catch { Log "эталон: не забрал правки: $($_.Exception.Message)" }
    Invoke-Step (L 'Возврат исходных настроек' 'Restoring the original settings') { Set-Settings $s $json }
    Invoke-Step (L 'Проверка записи' 'Verifying') { Assert-Written $s $json (L 'исходные' 'originals') }
    Clear-Temp $s.Puuid
    # исходные — твои (основной после примерки про)? Тогда аккаунт снова участвует, иначе — нет.
    if ((Test-Path $ProfilePath) -and (Test-PrefsEqual ($json | ConvertFrom-Json) (Read-Profile))) { Set-SessionBase $s.Puuid $json } else { Clear-SessionBase $s.Puuid }
    Set-AccountState $s.Puuid @{ state = ''; checked = (Get-Stamp) }
    Log "исходные настройки возвращены: $(Get-AccountLabel $s.Puuid)"
    if ($script:Fancy) { Write-Ok (L "Исходные настройки аккаунта $(Get-AccountLabel $s.Puuid) возвращены" "The original settings of $(Get-AccountLabel $s.Puuid) are back") }
    try { Update-Agent } catch {}   # больше нечего возвращать — помощник нужен, только если включён сам по себе
    $true
}

# После переноса на время (в меню): как вернутся исходные. Один раз спросить про помощника.
function Write-TempNote {
    $cfg = Get-Config
    if ($null -eq $cfg.tempAuto -and -not (Test-AgentEnabled)) {
        $ans = Confirm-Key (L 'Возвращать исходные самому после игры? Для этого, пока есть что вернуть, работает помощник в фоне' 'Restore the originals automatically after the game? The background helper runs while there is something to restore')
        Set-Config 'tempAuto' $ans
        $cfg = Get-Config
    }
    if ($cfg.tempAuto -or $cfg.notify -or $cfg.autoApply) {
        try { Update-Agent } catch { Write-Note "$(L 'помощник не запустился' 'helper did not start'): $($_.Exception.Message)" }
        Write-Note (L 'на время: исходные вернутся сами через ~3 с после закрытия игры' 'for now: the originals come back ~3 s after you close the game')
    } else {
        Write-Note (L 'на время: перед выходом из аккаунта — Ctrl+Alt+V → «Вернуть исходные»' 'for now: before logging out — Ctrl+Alt+V → “Restore originals”')
    }
}
