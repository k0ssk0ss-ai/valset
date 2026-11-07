# cloud.ps1 — запросы к серверам Riot (облако настроек, лоадаут) с повторами.
# Повтор — при сбое сети, 5xx, 408 и 429; паузы растут (1 → 2 → 4 → 8 с), пока не вышел общий лимит ожидания
# ($CloudRetry.BudgetMs — панель не должна висеть) и пока жив токен доступа (JWT, поле exp). Токен кончается или Riot
# ответил 401 — один раз берём свежий у клиента Riot (Get-Session) и продолжаем; не вышло — понятная ошибка.
# Пока идут повторы, текст состояния лежит в переменной процесса VALSET_STATUS: ядро работает в памяти приложения,
# панель показывает его под «…». В отдельном процессе (cmd) — только журнал.
# 403 от Cloudflare (страница «you have been blocked», замер 2026-10-11, проходит сама за ~20 мин) — сразу понятной
# ошибкой, без повторов: частые запросы с тем же токеном могут продлить блок.

$CloudRetry = @{ FirstMs = 1000; Factor = 2; MaxMs = 8000; BudgetMs = 20000; TokenSlackSec = 10 }
$script:CloudSleep = { param([int]$ms) Start-Sleep -Milliseconds $ms }   # тесты подменяют, чтобы не ждать

# Код ответа HTTP из ошибки Invoke-RestMethod (или из текста — для подставных ошибок в тестах).
function Get-HttpCode($err) {
    $code = 0; try { $code = [int]$err.Exception.Response.StatusCode } catch {}
    if (-not $code -and "$($err.Exception.Message)" -match '\((\d{3})\)') { $code = [int]$Matches[1] }
    $code
}

# Сколько секунд ещё жив токен доступа (JWT, поле exp); $null — не разобрать (тогда ограничивает только лимит ожидания).
function Get-TokenSecondsLeft([string]$token, $now = $null) {
    $p = @("$token" -split '\.')
    if ($p.Count -lt 3) { return $null }
    try {
        $b = $p[1].Replace('-', '+').Replace('_', '/'); $b += '=' * ((4 - $b.Length % 4) % 4)
        $exp = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) | ConvertFrom-Json).exp
        if (-not $exp) { return $null }
        if (-not $now) { $now = [DateTime]::UtcNow }
        ([DateTimeOffset]::FromUnixTimeSeconds([long]$exp).UtcDateTime - $now).TotalSeconds
    } catch { $null }
}

# Паузы между попытками, мс: растут в Factor раз до MaxMs; сумма — не больше $budgetMs и не дольше,
# чем осталось жить токену (минус запас TokenSlackSec). Пустой список — повторять нельзя.
function Get-RetryDelays([int]$budgetMs, $tokenLeftSec = $null) {
    $limit = $budgetMs
    if ($null -ne $tokenLeftSec) { $limit = [Math]::Min($limit, [int](([double]$tokenLeftSec - $CloudRetry.TokenSlackSec) * 1000)) }
    $out = New-Object Collections.Generic.List[int]
    $sum = 0; $d = $CloudRetry.FirstMs
    while ($d -gt 0 -and $sum + $d -le $limit) { $out.Add($d); $sum += $d; $d = [int][Math]::Min($d * $CloudRetry.Factor, $CloudRetry.MaxMs) }
    , $out.ToArray()
}

function Set-CloudStatus([string]$text) {
    try { [Environment]::SetEnvironmentVariable('VALSET_STATUS', $(if ($text) { $text } else { $null }), 'Process') } catch {}
}

# Свежий токен того же аккаунта у клиента Riot (клиент обновляет его сам). $true — токен сменился.
function Update-SessionToken($s) {
    if (-not $s) { return $false }
    $n = Get-Session
    if (-not $n -or $n.Puuid -ne $s.Puuid -or $n.Token -eq $s.Token) { return $false }
    $s.Token = $n.Token; $s.Entitlement = $n.Entitlement
    Log 'облако: взят свежий токен у клиента Riot'
    $true
}

# Запрос с повторами (запись — целиком, повтор безопасен). $s — сессия: по ней срок токена и его обновление.
# Имена локальных переменных необычные: блок $call видит переменные этой функции (динамическая область видимости).
function Invoke-Cloud([scriptblock]$call, $s = $null) {
    $rcPlan = $null; $rcTry = 0; $rcWaited = 0; $rcFresh = $false; $rcStatus = $false
    try {
        while ($true) {
            try { return (& $call) } catch {
                $rcErr = $_; $rcCode = Get-HttpCode $rcErr
                if ($rcCode -eq 403 -and "$($rcErr.ErrorDetails.Message)" -match 'cloudflare|have been blocked') {
                    throw (L 'Riot временно не пускает к облаку настроек. Обычно это проходит само, попробуй позже. В это время игра тоже не сохранит настройки.' 'Riot is temporarily blocking the settings cloud. It usually clears by itself, try again later. The game cannot save settings meanwhile either.')
                }
                if ($rcCode -eq 401) {
                    if (-not $rcFresh -and (Update-SessionToken $s)) { $rcFresh = $true; continue }
                    throw (L 'Вход в клиенте Riot устарел. Перезайди в аккаунт и повтори.' 'The Riot Client login expired. Log in again and retry.')
                }
                if ($rcCode -ge 400 -and $rcCode -lt 500 -and $rcCode -notin 408, 429) { throw }
                $rcLeft = if ($s) { Get-TokenSecondsLeft $s.Token } else { $null }
                if ($null -eq $rcPlan) { $rcPlan = Get-RetryDelays $CloudRetry.BudgetMs $rcLeft }
                if ($rcTry -ge $rcPlan.Count) {
                    # паузы кончились из-за срока токена, а лимит ожидания ещё есть — свежий токен и новый план
                    $rcRest = $CloudRetry.BudgetMs - $rcWaited
                    if (-not $rcFresh -and $null -ne $rcLeft -and $rcLeft - $CloudRetry.TokenSlackSec -lt $rcRest / 1000 -and (Update-SessionToken $s)) {
                        $rcFresh = $true; $rcPlan = Get-RetryDelays $rcRest (Get-TokenSecondsLeft $s.Token); $rcTry = 0
                    }
                }
                if ($rcTry -ge $rcPlan.Count) {
                    if (-not $rcPlan.Count -and -not $rcWaited) {
                        if ($null -ne $rcLeft -and $rcLeft -lt $CloudRetry.TokenSlackSec) { throw (L 'Вход в клиенте Riot скоро истечёт. Подожди минуту и повтори.' 'The Riot Client login is about to expire. Wait a minute and retry.') }
                        throw
                    }
                    $rcSec = [Math]::Round($rcWaited / 1000)
                    Log "облако: сдаюсь после $($rcTry + 1) попыток (~$rcSec с): $($rcErr.Exception.Message)"
                    throw (L 'Riot не отвечает. Попробуй чуть позже.' 'Riot is not responding. Try again a bit later.')
                }
                $rcMs = $rcPlan[$rcTry]; $rcTry++
                $rcStatus = $true
                Set-CloudStatus (L "Riot не отвечает, пробую снова через $([Math]::Round($rcMs / 1000)) с…" "Riot is not responding, retrying in $([Math]::Round($rcMs / 1000)) s…")
                Log "облако: $(if ($rcCode) { "ошибка $rcCode" } else { 'сбой сети' }), повтор $rcTry через $rcMs мс"
                & $script:CloudSleep $rcMs
                $rcWaited += $rcMs
            }
        }
    } finally { if ($rcStatus) { Set-CloudStatus '' } }
}
