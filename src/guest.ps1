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
    if (-not (Test-Path $p)) { Set-Content $p $json -Encoding UTF8 }
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
    $old = $json | ConvertFrom-Json
    Invoke-Step (L 'Возврат исходных настроек' 'Restoring the original settings') { Set-Settings $s $json }
    Invoke-Step (L 'Проверка записи' 'Verifying') {
        $check = Get-Settings $s | ConvertFrom-Json
        foreach ($k in $BindKeys + 'floatSettings' + 'intSettings') {
            if ((Get-JsonPart $check $k) -ne (Get-JsonPart $old $k)) { throw "в облаке '$k' не совпадает с исходными" }
        }
    }
    Clear-Temp $s.Puuid
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
