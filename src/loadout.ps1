# loadout.ps1 — косметика аккаунта на серверах Riot (для наборов, sets.ps1): адрес региона, чтение и запись лоадаута,
# выбор агента (pregame), названия предметов с valorant-api.com (кэш на неделю, без сети — последние скачанные, иначе ID).
# Эндпоинты (не официальные, как у ValoVault и трекеров):
#   GET/PUT https://pd.{shard}.a.pvp.net/personalization/v2/players/{puuid}/playerloadout
#   GET https://glz-{region}-1.{shard}.a.pvp.net/pregame/v1/players/{puuid}  → MatchID (404 — не в выборе агента)
#   GET https://glz-{region}-1.{shard}.a.pvp.net/pregame/v1/matches/{matchId} → AllyTeam.Players[].CharacterID / CharacterSelectionState
# Владение предметами проверяет сам Riot: чужой скин в наборе — запрос отклоняется целиком, лоадаут не меняется.

$NamesCache = Join-Path $Root 'cache\names.json'
$NamesTtlDays = 7
$ValApi = 'https://valorant-api.com/v1'
$ShardOf = @{ na = 'na'; latam = 'na'; br = 'na'; eu = 'eu'; ap = 'ap'; kr = 'kr'; pbe = 'pbe' }

# ── Адрес: регион, шард, версия клиента ──────────────────────────────────────

# Регион и шард — из лога игры (адрес glz-…), иначе по папке аккаунта в Config (<puuid>-<регион>).
# Версия клиента — из лога (CI server version), иначе valorant-api.com/v1/version. Один раз за процесс.
function Get-RiotRoute($s) {
    $c = $script:RiotRoute
    if ($c -and $c.Puuid -eq $s.Puuid) { return $c }
    $region = $null; $shard = $null; $ver = $null
    if (Test-Path $GameLog) {
        $m = Select-String -Path $GameLog -Pattern 'https://glz-([a-z0-9]+)-1\.([a-z0-9]+)\.a\.pvp\.net' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($m) { $region = $m.Matches[0].Groups[1].Value; $shard = $m.Matches[0].Groups[2].Value }
        $v = Select-String -Path $GameLog -Pattern 'CI server version: (release-[\w.\-]+)' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($v) { $ver = $v.Matches[0].Groups[1].Value }
    }
    if (-not $region) {
        $d = @(Get-AccountDirs | Where-Object { $_.Name.StartsWith("$($s.Puuid)-") }) | Select-Object -First 1
        if ($d) { $region = $d.Name.Substring(37) }
    }
    if (-not $region) { throw (L 'Не знаю регион аккаунта — запусти VALORANT хотя бы раз на этом ПК.' 'Unknown account region — launch VALORANT on this PC at least once.') }
    if (-not $shard) { $shard = if ($ShardOf[$region]) { $ShardOf[$region] } else { $region } }
    if (-not $ver) { try { $ver = (Invoke-RestMethod "$ValApi/version" -TimeoutSec 5).data.riotClientVersion } catch {} }
    $plat = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"platformType":"PC","platformOS":"Windows","platformOSVersion":"10.0.19042.1.256.64bit","platformChipset":"Unknown"}'))
    $script:RiotRoute = [pscustomobject]@{ Puuid = $s.Puuid; Region = $region; Shard = $shard; Version = "$ver"; Platform = $plat
                                           Pd = "https://pd.$shard.a.pvp.net"; Glz = "https://glz-$region-1.$shard.a.pvp.net" }
    $script:RiotRoute
}

function Get-GameHeaders($s, $rt) {
    $h = Get-Headers $s
    $h['X-Riot-ClientPlatform'] = $rt.Platform
    if ($rt.Version) { $h['X-Riot-ClientVersion'] = $rt.Version }
    $h
}

# ── Лоадаут ──────────────────────────────────────────────────────────────────

function Get-Loadout($s) {
    $rt = Get-RiotRoute $s
    Invoke-Cloud { Invoke-RestMethod "$($rt.Pd)/personalization/v2/players/$($s.Puuid)/playerloadout" -Headers (Get-GameHeaders $s $rt) -TimeoutSec 15 } $s
}

# Запись целиком (как делает клиент); ответ — лоадаут после записи.
function Send-LoadoutPut($s, [string]$body) {
    $rt = Get-RiotRoute $s
    Invoke-Cloud { Invoke-RestMethod "$($rt.Pd)/personalization/v2/players/$($s.Puuid)/playerloadout" -Method Put -Headers (Get-GameHeaders $s $rt) `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 15 } $s
}

function Get-LoadoutError([int]$code) {
    if ($code -in 400, 403, 409, 422) { return (L 'Riot не принял набор: в нём есть предмет, которого нет на этом аккаунте (или его сейчас нельзя менять). Ничего не изменено.' 'Riot rejected the set: it has an item this account does not own (or it cannot be changed right now). Nothing was changed.') }
    if ($code -eq 401) { return (L 'Вход в клиенте Riot устарел — перезайди в аккаунт и повтори.' 'The Riot Client login expired — log in again and retry.') }
    if ($code -eq 404) { return (L 'Riot не нашёл лоадаут аккаунта (аккаунт ни разу не заходил в VALORANT?).' 'Riot did not find the account loadout (has it never played VALORANT?).') }
    L "Не удалось записать набор (ошибка Riot $code). Ничего не изменено." "Could not write the set (Riot error $code). Nothing was changed."
}

function Set-Loadout($s, $lo) {
    $body = ConvertTo-Json -InputObject $lo -Depth 10 -Compress
    try { Send-LoadoutPut $s $body } catch { $c = Get-HttpCode $_; if ($c) { throw (Get-LoadoutError $c) }; throw }
}

# Выбор агента: $null — не в выборе агента; иначе MatchId, Agent (id, нижний регистр), Locked.
function Get-PregameAgent($s) {
    $rt = Get-RiotRoute $s; $h = Get-GameHeaders $s $rt
    try { $p = Invoke-RestMethod "$($rt.Glz)/pregame/v1/players/$($s.Puuid)" -Headers $h -TimeoutSec 8 }
    catch { if ((Get-HttpCode $_) -eq 404) { return $null }; throw }
    if (-not $p.MatchID) { return $null }
    $m = Invoke-RestMethod "$($rt.Glz)/pregame/v1/matches/$($p.MatchID)" -Headers $h -TimeoutSec 8
    $me = @($m.AllyTeam.Players) | Where-Object { $_.Subject -eq $s.Puuid } | Select-Object -First 1
    if (-not $me) { return $null }
    [pscustomobject]@{ MatchId = "$($p.MatchID)"; Agent = "$($me.CharacterID)".ToLowerInvariant(); Locked = "$($me.CharacterSelectionState)" -eq 'locked' }
}

# ── Названия предметов ───────────────────────────────────────────────────────

# Скачать названия (оружие со скинами/цветами/уровнями, брелоки, спреи, карточки, титулы, рамки, агенты) на языке интерфейса.
function Get-NamesFromApi([string]$lang) {
    $q = "?language=$(if ($lang -eq 'en') { 'en-US' } else { 'ru-RU' })"
    $get = { param($p) (Invoke-RestMethod "$ValApi/$p$(if ($p.Contains('?')) { $q.Replace('?', '&') } else { $q })" -TimeoutSec 30).data }
    $n = @{}; $lv = @{}
    foreach ($w in & $get 'weapons') {
        $n["$($w.uuid)"] = "$($w.displayName)"
        foreach ($k in @($w.skins)) {
            $n["$($k.uuid)"] = "$($k.displayName)"
            foreach ($c in @($k.chromas)) { if ($c.uuid) { $n["$($c.uuid)"] = "$($c.displayName)" } }
            $i = 0; foreach ($l in @($k.levels)) { $i++; if ($l.uuid) { $lv["$($l.uuid)"] = $i } }
        }
    }
    foreach ($b in & $get 'buddies') { $n["$($b.uuid)"] = "$($b.displayName)" }
    foreach ($x in & $get 'sprays') { $n["$($x.uuid)"] = "$($x.displayName)" }
    foreach ($x in & $get 'playercards') { $n["$($x.uuid)"] = "$($x.displayName)" }
    foreach ($x in & $get 'playertitles') { $n["$($x.uuid)"] = $(if ($x.titleText) { "$($x.titleText)" } else { "$($x.displayName)" }) }
    foreach ($x in & $get 'levelborders') { $n["$($x.uuid)"] = $(if ($x.displayName) { "$($x.displayName)" } else { "$(L 'рамка' 'border') $($x.startingLevel)" }) }
    $ag = @(foreach ($a in & $get 'agents?isPlayableCharacter=true') { [ordered]@{ id = "$($a.uuid)".ToLowerInvariant(); name = "$($a.displayName)" } }) | Sort-Object { $_.name }
    [ordered]@{ lang = $lang; at = (Get-Stamp); names = $n; levels = $lv; agents = @($ag) }
}

# Названия: из памяти → из кэша (моложе недели, тот же язык) → из сети → из старого кэша → пусто (покажем ID).
function Get-CosmeticNames {
    if ($script:CosNames -and $script:CosNames.lang -eq $script:Lang) { return $script:CosNames }
    $raw = $null
    if (Test-Path $NamesCache) { try { $raw = Get-Content $NamesCache -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    $fresh = $raw -and $raw.lang -eq $script:Lang -and $(try { ([DateTime]::Now - [DateTime]$raw.at).TotalDays -lt $NamesTtlDays } catch { $false })
    if (-not $fresh) {
        try {
            $o = Get-NamesFromApi $script:Lang
            Write-FileSafe $NamesCache (ConvertTo-Json -InputObject $o -Depth 5 -Compress)
            $raw = (ConvertTo-Json -InputObject $o -Depth 5 -Compress) | ConvertFrom-Json
        } catch { Log "названия косметики не скачались: $($_.Exception.Message)" }
    }
    $n = @{}; $lv = @{}; $ag = @()
    if ($raw) {
        foreach ($p in $raw.names.PSObject.Properties) { $n[$p.Name.ToLowerInvariant()] = $p.Value }
        foreach ($p in $raw.levels.PSObject.Properties) { $lv[$p.Name.ToLowerInvariant()] = [int]$p.Value }
        $ag = @($raw.agents)
    }
    $script:CosNames = @{ lang = $script:Lang; Names = $n; Levels = $lv; Agents = $ag }
    $script:CosNames
}

# Название по ID; нет в справочнике — первые 8 символов ID.
function Get-ItemName($names, [string]$id) {
    if (-not $id -or $id -match '^0{8}-') { return '' }
    $v = $names.Names[$id.ToLowerInvariant()]
    if ($v) { $v } else { Short $id }
}

function Get-AgentName($names, [string]$id) {
    if (-not $id) { return '' }
    $a = @($names.Agents) | Where-Object { $_.id -eq $id.ToLowerInvariant() } | Select-Object -First 1
    if ($a) { "$($a.name)" } else { Short $id }
}
