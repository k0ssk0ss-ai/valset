# test-range.ps1 — «Надеть и перезайти» в стрельбище (range.ps1): проверка режима, порядок и тело запросов, отказ вне стрельбища,
# разбор `+rejoin` / `!force+rejoin`, inRange в предпросмотре. Сеть подставная: Send-RangeRequest, Get-Loadout, Send-LoadoutPut.
# Подключается из run-tests.ps1 (dot-source) после test-sets.ps1: там $loA, G, Check, Invoke-Do.

$rgKeep = @{}; foreach ($f in 'Send-RangeRequest', 'Get-RiotRoute', 'Get-Loadout', 'Send-LoadoutPut') { $rgKeep[$f] = (Get-Item "Function:\$f").ScriptBlock }
$rgSleepKeep = $script:CloudSleep; $script:CloudSleep = { param([int]$ms) }
$script:CosNames = @{ lang = 'ru'; Names = @{}; Levels = @{}; Agents = @() }
$script:lo = $loA; $script:puts = @(); $script:putFail = $null
$script:rg = @(); $script:rgMode = 'range'; $script:rgFlow = 'ShootingRange'; $script:rgSolo400 = 0
function Get-RiotRoute($s) { [pscustomobject]@{ Puuid = $s.Puuid; Platform = 'p'; Version = 'v'; Glz = 'https://glz'; Pd = 'https://pd' } }
function Get-Loadout($s) { ConvertTo-Json -InputObject $script:lo -Depth 10 -Compress | ConvertFrom-Json }
function Send-LoadoutPut($s, [string]$body) { $script:puts += $body; if ($script:putFail) { throw $script:putFail }; $script:lo = $body | ConvertFrom-Json; $script:lo }
function Send-RangeRequest([string]$method, [string]$url, $h, [string]$body = $null) {
    $script:rg += "$method $url $body".Trim()
    if ($method -eq 'Get') {
        if ($script:rgMode -eq '404') { throw 'Удалённый сервер возвратил ошибку: (404) Не найден.' }
        if ($script:rgMode -eq 'err') { throw 'сеть недоступна' }
        if ($url -like '*/core-game/v1/players/*') { return [pscustomobject]@{ MatchID = 'match-1' } }
        return [pscustomobject]@{ ProvisioningFlow = $script:rgFlow }
    }
    if ($url -like '*/startsoloexperience' -and $script:rgSolo400 -gt 0) { $script:rgSolo400--; throw 'Удалённый сервер возвратил ошибку: (400) Неверный запрос.' }
    $null
}
$rgP = $script:sess.Puuid
$rgDis = "Post https://glz/core-game/v1/players/$rgP/disassociate/match-1"
$rgSolo = "Post https://glz/parties/v1/players/$rgP/startsoloexperience {`"gameType`":`"ShootingRange`"}"
$rgPosts = { @($script:rg | Where-Object { $_ -like 'Post *' }) }

Write-Host 'перезаход в стрельбище'
$GameProc = 'powershell'   # «игра запущена»
$r = Invoke-Do 'rejoin'
$p = & $rgPosts
Check 'rejoin в стрельбище: disassociate, затем startsolo с телом' ($r.ok -and $p.Count -eq 2 -and $p[0] -eq $rgDis -and $p[1] -eq $rgSolo -and $r.message -like 'Стрельбище перезапускается*') (($script:rg -join ' | ') + ' ' + ($r | ConvertTo-Json -Compress))
Check 'rejoin: перед отправкой проверены игрок и матч' ($script:rg.Count -eq 4 -and $script:rg[0] -like 'Get */core-game/v1/players/*' -and $script:rg[1] -eq 'Get https://glz/core-game/v1/matches/match-1')

$script:rg = @(); $script:rgSolo400 = 3
$r = Invoke-Do 'rejoin'; $p = & $rgPosts
Check 'rejoin: startsolo 400 — повтор, пока не пустит' ($r.ok -and $p.Count -eq 5 -and $p[0] -eq $rgDis -and $p[4] -eq $rgSolo) ($script:rg -join ' | ')
$script:rg = @(); $script:rgSolo400 = 100
$r = Invoke-Do 'rejoin'; $p = & $rgPosts
Check 'rejoin: startsolo так и не пустил — предел попыток и понятная ошибка' (-not $r.ok -and $p.Count -eq 1 + $RangeRetryMax -and $r.message -like '*Зайди сам*') $r.message
$script:rgSolo400 = 0

foreach ($c in @(@{ mode = 'range'; flow = 'CustomGame'; n = 'своя игра' }, @{ mode = 'range'; flow = 'Matchmaking'; n = 'матч из очереди' }, @{ mode = 'range'; flow = ''; n = 'режим не указан' },
                @{ mode = '404'; flow = 'ShootingRange'; n = 'не в матче (404)' }, @{ mode = 'err'; flow = 'ShootingRange'; n = 'ошибка сети' })) {
    $script:rg = @(); $script:rgMode = $c.mode; $script:rgFlow = $c.flow
    $r = Invoke-Do 'rejoin'
    Check "rejoin, $($c.n): ни одного POST, отказ" (-not $r.ok -and (& $rgPosts).Count -eq 0 -and $r.message -eq 'Перезайти можно только из стрельбища') (($script:rg -join ' | ') + ' ' + $r.message)
}
$script:rgMode = 'range'; $script:rgFlow = 'ShootingRange'

$mx = New-Object Threading.Mutex($false, $LoadoutAutoMutex); $script:rg = @()
$r = Invoke-Do 'rejoin'
$mx.Dispose()
Check 'rejoin, пока надевается набор при выборе агента: ни одного запроса' (-not $r.ok -and $script:rg.Count -eq 0 -and $r.message -like 'Сейчас надеваются скины*') $r.message

$GameProc = 'valset-test-no-such-process'; $script:rg = @()
$r = Invoke-Do 'rejoin'
Check 'rejoin без запущенной игры: ни одного запроса' (-not $r.ok -and $script:rg.Count -eq 0 -and $r.message -eq 'Перезайти можно только из стрельбища')
$GameProc = 'powershell'

# Запись + перезаход
$spec1 = "card:$(G 'card0007')"; $spec2 = "card:$(G 'card0008')"
$script:rg = @(); $script:puts = @()
$r = Invoke-Do "skin:$spec1+rejoin"; $p = & $rgPosts
Check '+rejoin: сначала запись, потом перезаход; одно сообщение, отмена есть' ($r.ok -and $script:puts.Count -eq 1 -and $p.Count -eq 2 -and $r.undo -and $r.rejoined -and $r.message -like 'Надето: *. Стрельбище перезапускается*') ($r | ConvertTo-Json -Compress)
$script:rg = @(); $script:puts = @()
$r = Invoke-Do "skin:$spec1+rejoin"
Check '+rejoin: «уже надето» — без записи, но перезаход' ($r.ok -and $script:puts.Count -eq 0 -and (& $rgPosts).Count -eq 2 -and $r.message -like 'Уже надето. Стрельбище*') $r.message
$script:rg = @(); $script:puts = @()
$r = Invoke-Do "skin:$spec1!force+rejoin"
Check '!force+rejoin: записано заново и перезаход' ($r.ok -and $script:puts.Count -eq 1 -and (& $rgPosts).Count -eq 2 -and $r.message -like 'Записано заново. Стрельбище*') $r.message
$script:rg = @(); $script:puts = @(); $script:putFail = 'Удалённый сервер возвратил ошибку: (400) Неверный запрос.'
$r = Invoke-Do "skin:$spec2+rejoin"
Check '+rejoin: запись не прошла — перезахода нет' (-not $r.ok -and $script:puts.Count -eq 1 -and $script:rg.Count -eq 0 -and $r.message -like 'Riot не принял*') $r.message
$script:putFail = $null
$script:rg = @(); $script:puts = @(); $script:rgFlow = 'CustomGame'
$r = Invoke-Do "skin:$spec2+rejoin"
Check '+rejoin вне стрельбища: записано, POST нет, отказ в том же сообщении' ($r.ok -and $script:puts.Count -eq 1 -and (& $rgPosts).Count -eq 0 -and -not $r.rejoined -and $r.message -like 'Надето: *. Перезайти можно только из стрельбища') $r.message
$script:rgFlow = 'ShootingRange'
Check 'разбор: +rejoin и !force+rejoin — свои действия, loadoutsave с +rejoin не перезаходит' ((Test-ExtraAction 'rejoin') -and (Test-ExtraAction 'loadout:abc!force+rejoin') -and (Test-ExtraAction 'coll:abc+rejoin') -and 'loadoutsave:x+rejoin' -notmatch '^(loadout|skin|coll):[^+]+\+rejoin$')

# inRange в предпросмотре
$script:rg = @()
$lp = @(Get-ListSkinPreview $spec2)
Check 'предпросмотр в стрельбище: inRange = true' ($lp[0].inRange -eq $true -and $script:rg.Count -eq 2 -and (& $rgPosts).Count -eq 0) ($lp[0] | ConvertTo-Json -Compress)
$script:rgFlow = 'CustomGame'
Check 'предпросмотр в своей игре: inRange = false' ((@(Get-ListSkinPreview $spec2))[0].inRange -eq $false)
$GameProc = 'valset-test-no-such-process'; $script:rg = @(); $script:rgFlow = 'ShootingRange'
$lp = @(Get-ListSkinPreview $spec2)
Check 'предпросмотр без игры: inRange = false, ни одного запроса' ($lp[0].inRange -eq $false -and $script:rg.Count -eq 0)

Remove-LastAction
foreach ($f in $rgKeep.Keys) { Set-Item "Function:\$f" $rgKeep[$f] }
$script:CloudSleep = $rgSleepKeep; $script:CosNames = $null
