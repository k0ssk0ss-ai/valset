# test-cloud.ps1 — повторы запросов к Riot (cloud.ps1): расписание пауз, срок токена, свежий токен. Без сети и без ожидания.
# Подключается из run-tests.ps1 (dot-source): там Check и загруженные функции ядра.

$script:slept = @()
$script:CloudSleep = { param([int]$ms) $script:slept += $ms }
function New-TestJwt([int]$secLeft) {
    $exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $secLeft
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("{`"sub`":`"x`",`"exp`":$exp}")).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    "eyJhbGciOiJSUzI1NiJ9.$b.sig"
}

$d = Get-RetryDelays 20000
Check 'повторы: паузы растут 1-2-4-8 с, в сумме не больше 20 с' (($d -join ',') -eq '1000,2000,4000,8000') ($d -join ',')
$d = Get-RetryDelays 60000
Check 'повторы: пауза не больше 8 с' (($d -join ',') -eq '1000,2000,4000,8000,8000,8000,8000,8000,8000') ($d -join ',')
$d = Get-RetryDelays 20000 14
Check 'повторы: токен живёт 14 с — паузы только на 4 с (запас 10 с)' (($d -join ',') -eq '1000,2000') ($d -join ',')
Check 'повторы: токен истёк — пауз нет' ((Get-RetryDelays 20000 5).Count -eq 0 -and (Get-RetryDelays 20000 -30).Count -eq 0)
$tl = Get-TokenSecondsLeft (New-TestJwt 600)
Check 'срок токена из JWT (exp)' ($tl -gt 590 -and $tl -le 600) "$tl"
Check 'не JWT — срок неизвестен' ($null -eq (Get-TokenSecondsLeft 't') -and $null -eq (Get-TokenSecondsLeft 'a.!!!.b'))

$script:n = 0
$r = Invoke-Cloud { $script:n++; if ($script:n -lt 2) { throw 'сеть моргнула' }; 'ок' }
Check 'сбой сети — повтор через 1 с, удалось' ($r -eq 'ок' -and $script:n -eq 2 -and ($script:slept -join ',') -eq '1000')
Check 'после повторов строка состояния для панели убрана' (-not $env:VALSET_STATUS)
$script:n = 0; $script:slept = @(); $msg = ''
try { Invoke-Cloud { $script:n++; throw 'лежит' } } catch { $msg = $_.Exception.Message }
Check 'сервер лежит: 5 попыток за 15 с, понятная ошибка' ($script:n -eq 5 -and ($script:slept | Measure-Object -Sum).Sum -eq 15000 -and $msg -like 'Riot не отвечает. Попробуй*') "$($script:n) / $msg"
$script:n = 0; $script:slept = @()
try { Invoke-Cloud { $script:n++; throw 'Удаленный сервер возвратил ошибку: (404) Не найден.' } } catch {}
Check '4xx — без повторов' ($script:n -eq 1 -and -not $script:slept.Count)

# токен: истекает — повторы до срока, затем свежий токен у клиента и новые повторы
$ts = [pscustomobject]@{ Puuid = 'p-cloud'; Token = (New-TestJwt 12); Entitlement = 'e' }
$script:fresh = [pscustomobject]@{ Puuid = 'p-cloud'; Token = (New-TestJwt 3600); Entitlement = 'e2' }
$gsKeep = ${function:Get-Session}
function Get-Session { $script:fresh }
$script:n = 0; $script:slept = @()
$r = Invoke-Cloud { $script:n++; if ($script:n -lt 4) { throw 'лежит' }; $s.Token } $ts
Check 'токен на исходе: повтор до срока, потом свежий токен и дальше' ($r -eq $script:fresh.Token -and $ts.Entitlement -eq 'e2' -and ($script:slept -join ',') -eq '1000,1000,2000') ($script:slept -join ',')
$ts.Token = 'old'; $script:n = 0
$r = Invoke-Cloud { $script:n++; if ($s.Token -eq 'old') { throw 'Удаленный сервер возвратил ошибку: (401) Не авторизован.' }; 'ок' } $ts
Check '401 — свежий токен у клиента и сразу повтор' ($r -eq 'ок' -and $script:n -eq 2)
$script:fresh = $null; $ts.Token = 'old'; $msg = ''
try { Invoke-Cloud { throw 'Удаленный сервер возвратил ошибку: (401) Не авторизован.' } $ts } catch { $msg = $_.Exception.Message }
Check '401, а клиент нового токена не дал — просим перезайти' ($msg -like 'Вход в клиенте Riot устарел*') $msg
$ts.Token = (New-TestJwt 5); $msg = ''
try { Invoke-Cloud { throw 'лежит' } $ts } catch { $msg = $_.Exception.Message }
Check 'токен истёк, свежего нет — понятная ошибка без ожидания' ($msg -like 'Вход в клиенте Riot скоро истечёт*') $msg
Set-Item Function:\Get-Session $gsKeep
$script:CloudSleep = { param([int]$ms) }
