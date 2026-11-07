# range.ps1 — «Надеть и перезайти» в стрельбище. Игра читает скины (CoreGame_FetchMatchLoadouts) только при входе в стрельбище
# или матч; записанное в стрельбище видно после повторного входа. Перезаход — те же два запроса, что шлёт сам клиент игры:
#   POST {Glz}/core-game/v1/players/{puuid}/disassociate/{matchId} → 204 (игра уходит в главное меню за ~3 с)
#   POST {Glz}/parties/v1/players/{puuid}/startsoloexperience, тело {"gameType":"ShootingRange"} → 200 (без тела — 400;
#     сразу после первого — 400, пока игра не вышла: повтор каждые ~250 мс до ~10 с)
# Проверено вручную 2026-11-07 (NOTES.md, «Перезаход в стрельбище из ядра»).
# БЕЗОПАСНОСТЬ: disassociate из настоящего матча — штраф за выход. Шлём только если прямо перед этим оба GET показали
# ProvisioningFlow = ShootingRange; любая ошибка или другой режим — не стрельбище, не шлём ничего.

$LoadoutAutoMutex = 'Local\valset-loadoutauto'   # держит Invoke-DoLoadoutAuto (sets.ps1), пока надевает набор
$RangeBody = '{"gameType":"ShootingRange"}'
$RangeRetryMs = 250; $RangeRetryMax = 40   # 40 × 250 мс ≈ 10 с

# Единственная точка сети модуля (тесты подменяют). $body — JSON или $null.
function Send-RangeRequest([string]$method, [string]$url, $h, [string]$body = $null) {
    if ($body) { Invoke-RestMethod $url -Method $method -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 8 }
    else { Invoke-RestMethod $url -Method $method -Headers $h -TimeoutSec 8 }
}

# $null — не в стрельбище (нет матча, другой режим, любая ошибка); иначе MatchId.
function Get-RangeState($s) {
    try {
        $rt = Get-RiotRoute $s; $h = Get-GameHeaders $s $rt
        $p = Send-RangeRequest 'Get' "$($rt.Glz)/core-game/v1/players/$($s.Puuid)" $h
        if (-not $p -or -not $p.MatchID) { return $null }
        $m = Send-RangeRequest 'Get' "$($rt.Glz)/core-game/v1/matches/$($p.MatchID)" $h
        if (-not $m -or "$($m.ProvisioningFlow)" -ne 'ShootingRange') { return $null }
        [pscustomobject]@{ MatchId = "$($p.MatchID)" }
    } catch { $null }   # 404 — не в матче; прочее — тоже «не стрельбище»
}

# Для предпросмотра: без запущенной игры — false без единого запроса.
function Test-InRange($s) { if (-not $s -or -not (Test-GameRunning)) { return $false }; [bool](Get-RangeState $s) }

function Get-RangeRefusal { L 'Перезайти можно только из стрельбища' 'You can only re-enter from the shooting range' }

# Перезаход: проверка стрельбища прямо перед отправкой, затем disassociate и startsoloexperience (с повтором на 400).
function Invoke-RejoinRange($s = $null) {
    if (Test-NamedMutex $LoadoutAutoMutex) { throw (L 'Сейчас надеваются скины, перезайди чуть позже' 'Skins are being put on right now, re-enter a bit later') }
    if (-not (Test-GameRunning)) { throw (Get-RangeRefusal) }
    if (-not $s) { $s = Connect-Session }
    $st = Get-RangeState $s
    if (-not $st) { throw (Get-RangeRefusal) }
    $rt = Get-RiotRoute $s; $h = Get-GameHeaders $s $rt
    try { $null = Send-RangeRequest 'Post' "$($rt.Glz)/core-game/v1/players/$($s.Puuid)/disassociate/$($st.MatchId)" $h }
    catch { Log "стрельбище: выход не удался: $(Get-HttpCode $_) $($_.Exception.Message)"; throw (L 'Не удалось перезайти в стрельбище. Перезайди сам.' 'Could not re-enter the range. Re-enter it yourself.') }
    $i = 0
    while ($true) {
        try { $null = Send-RangeRequest 'Post' "$($rt.Glz)/parties/v1/players/$($s.Puuid)/startsoloexperience" $h $RangeBody; break }
        catch {
            $i++
            if ((Get-HttpCode $_) -ne 400 -or $i -ge $RangeRetryMax) {
                Log "стрельбище: вход не удался после $i попыток: $(Get-HttpCode $_) $($_.Exception.Message)"
                throw (L 'Вышел из стрельбища, а зайти обратно не вышло. Зайди сам.' 'Left the range but could not get back in. Enter it yourself.')
            }
            & $script:CloudSleep $RangeRetryMs
        }
    }
    Log "стрельбище: перезаход ($($st.MatchId)), попыток входа: $($i + 1)"
    L 'Стрельбище перезапускается, скины подхватятся при входе (~15 с)' 'The range is restarting, skins load on entry (~15 s)'
}

# `do <loadout|skin|coll>:<арг>[!force]+rejoin`: сначала запись; упала — не перезаходим. Отказ перезахода — в том же сообщении.
function Invoke-DoWithRejoin([string]$inner, $r) {
    $w = "$(@(Invoke-DoExtra $inner $r)[-1])"
    try { $j = Invoke-RejoinRange; $r['rejoined'] = $true } catch { $j = $_.Exception.Message; $r['rejoined'] = $false }
    "$($w.TrimEnd('.')). $j"
}
