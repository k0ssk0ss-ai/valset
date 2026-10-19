# core.ps1 — облако настроек (с кэшем режима lib) и точка входа для приложения: Invoke-Core.
# Приложение держит ядро загруженным в своём runspace (valset.cmd lib) и зовёт Invoke-Core вместо запуска powershell на каждый
# запрос. Кэши — только в режиме lib ($script:Lib), в памяти процесса: обычный запуск `valset …` ведёт себя как раньше.

$SettingsTtl = 60      # секунд: сколько прочитанные настройки облака считаются свежими
$script:SettingsCache = $null   # @{ Puuid; Json; At } — одна запись: аккаунт в клиенте один
$script:RiotIdCache = $null     # @{ Puuid; Name } — имя аккаунта, пока не сменился puuid сессии
$script:CoreAt = @{ Pros = [DateTime]::UtcNow; PrefUrl = [DateTime]::UtcNow }

# Записали — прочитать обратно и сверить целиком (все группы, включая прицел и миникарту). Читаем только из облака, не из кэша.
function Assert-Written($s, [string]$json, [string]$what) {
    $norm = { param($j) ConvertTo-Json -InputObject ($j | ConvertFrom-Json) -Depth 32 -Compress }
    if ((& $norm (Get-Settings $s -Fresh)) -cne (& $norm $json)) { throw (L "в облаке не то, что записали ($what)" "the cloud doesn't match what was written ($what)") }
}

function Read-CloudSettings($s) {
    $r = Invoke-Cloud { Invoke-RestMethod "$PrefUrl/getPreference/Ares.PlayerSettings" -Headers (Get-Headers $s) -TimeoutSec 15 }
    if (-not $r.data) { throw (L 'Облако вернуло пустые настройки (аккаунт ни разу не заходил в Valorant?).' 'The cloud returned empty settings (has this account never played VALORANT?).') }
    $json = Expand-Pref $r.data
    Register-Actions $json
    $json
}

# -Fresh — обязательно из облака (проверка записи). В lib: кэш на $SettingsTtl с, не при запущенной игре (она пишет в облако сама).
function Get-Settings($s, [switch]$Fresh) {
    if (-not $script:Lib) { return (Read-CloudSettings $s) }
    $game = Test-GameRunning
    $c = $script:SettingsCache
    if (-not $Fresh -and -not $game -and $c -and $c.Puuid -eq $s.Puuid -and ([DateTime]::UtcNow - $c.At).TotalSeconds -lt $SettingsTtl) { return $c.Json }
    $script:SettingsCache = $null
    $json = Read-CloudSettings $s
    if (-not $game) { $script:SettingsCache = @{ Puuid = $s.Puuid; Json = $json; At = [DateTime]::UtcNow } }
    $json
}

function Clear-SettingsCache { $script:SettingsCache = $null }

function Set-Settings($s, [string]$json) {
    Clear-SettingsCache   # и до записи: упадёт посередине — старому кэшу верить нельзя
    $body = @{ type = 'Ares.PlayerSettings'; data = (Compress-Pref $json) } | ConvertTo-Json -Compress
    Invoke-Cloud { Invoke-RestMethod "$PrefUrl/savePreference" -Method Put -Headers (Get-Headers $s) `
        -Body $body -ContentType 'application/json' -TimeoutSec 15 | Out-Null }
    Clear-SettingsCache
}

# ── Invoke-Core ──────────────────────────────────────────────────────────────

# Всё, что в долгоживущем runspace могло устареть между вызовами.
function Reset-CoreState {
    $script:LastApply = $null; $script:LastOp = $null; $script:UndoAction = $null; $script:LastHistory = $null
    $script:LastSync = $null; $script:CrosshairDropped = 0; $script:DoOk = $null
    $script:Lang = Get-Lang   # язык могли поменять в конфиге
    $now = [DateTime]::UtcNow
    if (($now - $script:CoreAt.Pros).TotalMinutes -gt 10) { $script:Pros = $null; $script:CoreAt.Pros = $now }   # список про — раз в 10 минут
    if (($now - $script:CoreAt.PrefUrl).TotalMinutes -gt 10) {   # Riot переносит сервер настроек — адрес из лога игры
        $script:CoreAt.PrefUrl = $now
        if (Test-Path $GameLog) {
            $m = Select-String -Path $GameLog -Pattern 'https://player-preferences[^/\s]*/playerPref/v3' -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($m) { $script:PrefUrl = $m.Matches[0].Value }
        }
    }
}

# state | list <вид> | do <действие> | watch [-AfterGame] → ровно одна строка JSON ('{}' для watch). Не вызывает exit и не спрашивает.
function Invoke-Core([string]$cmd, [string]$arg = '', [string]$token = '') {
    $out = $null
    try {
        Reset-CoreState
        switch ($cmd) {
            'state' { $out = Get-StateJson }
            'list'  { $out = Get-ListJson $arg }
            'do'    { Clear-SettingsCache; $out = Get-DoJson $arg }   # запись читает облако заново: чужие правки с другого ПК не затираем
            'watch' {
                Clear-SettingsCache
                if ($token) { $env:VALSET_GAME_TOKEN = $token }
                try { $null = @(Invoke-Watch -AfterGame:($arg -match 'After')) }
                finally { Remove-Item Env:VALSET_GAME_TOKEN -ErrorAction SilentlyContinue; Clear-SettingsCache }
                $out = '{}'
            }
            default { throw "unknown core command: $cmd" }
        }
    } catch {
        Log "ядро $($cmd): $($_.Exception.Message)"
        $out = ConvertTo-Json -InputObject ([ordered]@{ ok = $false; message = "$($_.Exception.Message)"; error = "$($_.Exception.Message)" }) -Compress
    }
    [string]$out
}
