# test-update.ps1 — обновления (update.ps1): сравнение версий, кэш 12 ч, выключенная проверка, ошибки сети, `do update`
# с проверкой SHA-256. Сеть и запуск процессов подменены. Подключается из run-tests.ps1 (dot-source).

$updKeep = @{ Req = ${function:Invoke-UpdateRequest}; Dl = ${function:Invoke-UpdateDownload}; Game = ${function:Test-GameRunning}; Ver = $Version; Dir = $UpdateDir }
$cfgKeep = if (Test-Path $ConfigPath) { Get-Content $ConfigPath -Raw -Encoding UTF8 } else { $null }
$instHad = Test-Path $InstalledCmd
$script:updReq = 0; $script:updTag = 'v2.2.0'; $script:updFail = $false
$script:updLaunch = @(); $script:updPayload = 'echo new valset'; $script:updSums = $null; $script:updNoSums = $false
$UpdateDir = Join-Path $tmp 'upd'
function Invoke-UpdateRequest {
    $script:updReq++
    if ($script:updFail) { throw 'сеть недоступна' }
    [pscustomobject]@{ tag_name = $script:updTag; html_url = 'https://github.com/k0ssk0ss-ai/valset/releases/tag/x'; body = "## Что нового`n`n- один`n- два"
        assets = @([pscustomobject]@{ name = 'valset.cmd'; browser_download_url = 'https://x/valset.cmd' }, [pscustomobject]@{ name = 'SHA256SUMS.txt'; browser_download_url = 'https://x/SHA256SUMS.txt' }) }
}
function Invoke-UpdateDownload([string]$url, [string]$path) {
    if ($url -like '*valset.cmd') { [IO.File]::WriteAllText($path, $script:updPayload); return }
    if ($script:updNoSums) { throw '404' }
    $h = if ($script:updSums) { $script:updSums } else { (Get-FileHash (Join-Path $UpdateDir 'valset.cmd') -Algorithm SHA256).Hash.ToLower() }
    [IO.File]::WriteAllText($path, "$h  valset.cmd`n0000000000000000000000000000000000000000000000000000000000000000  valset-2.2.0.zip`n")
}
function Test-GameRunning { $false }
function Start-Process { param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle) $script:updLaunch += , @($FilePath, ($ArgumentList -join ' ')) }

try {
    Remove-Item -LiteralPath $UpdateCache -ErrorAction SilentlyContinue
    Set-Config 'updateCheck' $true

    # сравнение — как [version], не строкой
    $Version = '2.1.9'
    Check 'обновления: 2.1.10 новее 2.1.9 (не строкой)' ((Complete-UpdateInfo @{ latest = '2.1.10' }).newer)
    $Version = '2.1.0'
    $cmp = foreach ($t in 'v2.1.10', '2.2.0', '2.1.0', 'v2.0.9', 'v2.1') { $x = ConvertTo-UpdateRelease ([pscustomobject]@{ tag_name = $t; assets = @() }); "$($x.latest)=$((Complete-UpdateInfo $x).newer)" }
    Check 'обновления: v2.1.10 и 2.2.0 новее 2.1.0; 2.1.0, 2.0.9 и 2.1 нет' (($cmp -join ',') -eq '2.1.10=True,2.2.0=True,2.1.0=False,2.0.9=False,2.1=False') ($cmp -join ',')
    Check 'обновления: непонятный тег — ошибка разбора' ($(try { $null = ConvertTo-UpdateRelease ([pscustomobject]@{ tag_name = 'latest' }); $false } catch { $true }))

    # запрос, кэш на 12 ч
    $i = Get-UpdateInfo
    Check 'list update: новее, ссылки на файл и хэши, первые строки описания' ($script:updReq -eq 1 -and $i.newer -and $i.latest -eq '2.2.0' -and $i.current -eq '2.1.0' -and $i.asset -like '*valset.cmd' -and $i.sums -like '*SHA256SUMS.txt' -and $i.notes -like '## Что нового*два') ($i | ConvertTo-Json -Compress)
    $i = Get-UpdateInfo
    Check 'list update: свежий кэш — без второго запроса' ($script:updReq -eq 1 -and $i.newer -and (Test-Path $UpdateCache))
    $j = Get-ListJson 'update' | ConvertFrom-Json
    Check 'list update: JSON-объект с current/latest/newer' ($j.current -eq '2.1.0' -and $j.latest -eq '2.2.0' -and $j.newer -eq $true -and $script:updReq -eq 1) (Get-ListJson 'update')
    $old = Get-Content $UpdateCache -Raw | ConvertFrom-Json; $old.at = [DateTime]::UtcNow.AddHours(-13).ToString('o')
    Write-FileSafe $UpdateCache (ConvertTo-Json $old -Compress)
    $script:updTag = 'v2.1.0'
    $i = Get-UpdateInfo
    Check 'list update: кэш старше 12 ч — новый запрос; та же версия — не новее' ($script:updReq -eq 2 -and -not $i.newer -and $i.latest -eq '2.1.0')
    $old = Get-Content $UpdateCache -Raw | ConvertFrom-Json; $old.at = [DateTime]::UtcNow.AddHours(-13).ToString('o')
    Write-FileSafe $UpdateCache (ConvertTo-Json $old -Compress)
    $script:updFail = $true
    $i = Get-UpdateInfo
    Check 'list update: нет сети — последнее из кэша, без error' ($script:updReq -eq 3 -and -not $i.error -and $i.latest -eq '2.1.0')
    Remove-Item -LiteralPath $UpdateCache
    $i = Get-UpdateInfo
    Check 'list update: нет сети и кэша — тихо {error}' ($i.error -and -not $i.newer -and $i.current -eq '2.1.0') ($i | ConvertTo-Json -Compress)
    $script:updFail = $false

    # выключено — ни одного запроса; «Проверить сейчас» (update:now) спрашивает
    Set-Config 'updateCheck' $false
    $n = $script:updReq
    $j = Get-ListJson 'update' | ConvertFrom-Json
    Check 'updateCheck=false: list update без запроса' ($script:updReq -eq $n -and $j.off -eq $true -and -not $j.newer) (Get-ListJson 'update')
    $j = Get-ListJson 'update:now' | ConvertFrom-Json
    Check 'updateCheck=false: «Проверить сейчас» спрашивает GitHub' ($script:updReq -eq $n + 1 -and $j.latest -eq '2.1.0')
    $r = Invoke-Do 'set:updateCheck=on'
    Check 'set:updateCheck=on — в конфиге и в state' ($r.ok -and (Get-Config).updateCheck -and (ConvertTo-StateObject @{}).updateCheck) ($r | ConvertTo-Json -Compress)

    # do update
    $script:updTag = 'v2.2.0'
    if (-not $instHad) { [IO.File]::WriteAllText($InstalledCmd, 'old valset') }
    Remove-Item -LiteralPath (Join-Path $Root 'valset.cmd.prev') -ErrorAction SilentlyContinue
    $script:updSums = 'ab' * 32
    $r = Invoke-Do 'update'
    Check 'do update: хэш не совпал — отказ, ничего не запущено, файл удалён' (-not $r.ok -and $r.message -like '*Хэш*не совпал*' -and $script:updLaunch.Count -eq 0 -and -not (Test-Path (Join-Path $UpdateDir 'valset.cmd'))) ($r | ConvertTo-Json -Compress)
    $script:updSums = $null; $script:updNoSums = $true
    $r = Invoke-Do 'update'
    Check 'do update: нет SHA256SUMS.txt — отказ, ничего не запущено' (-not $r.ok -and $r.message -like '*хэшами*' -and $script:updLaunch.Count -eq 0) ($r | ConvertTo-Json -Compress)
    $script:updNoSums = $false
    $r = Invoke-Do 'update'
    $l = @($script:updLaunch)
    Check 'do update: хэш совпал — запущен скачанный valset.cmd install -Yes, прежний в valset.cmd.prev' ($r.ok -and $r.message -eq 'Обновлено до 2.2.0. Приложение перезапустится' -and $l.Count -eq 1 -and $l[0][0] -eq (Join-Path $UpdateDir 'valset.cmd') -and $l[0][1] -eq 'install -Yes' -and (Get-Content (Join-Path $Root 'valset.cmd.prev') -Raw) -eq (Get-Content $InstalledCmd -Raw)) ($r | ConvertTo-Json -Compress)
    $script:updTag = 'v2.1.0'; $script:updLaunch = @()
    $r = Invoke-Do 'update'
    Check 'do update: уже последняя — ничего не качает и не запускает' ($r.ok -and $r.message -like 'У тебя последняя версия*' -and $script:updLaunch.Count -eq 0) ($r | ConvertTo-Json -Compress)
} finally {
    Remove-Item function:Start-Process -ErrorAction SilentlyContinue
    ${function:Invoke-UpdateRequest} = $updKeep.Req; ${function:Invoke-UpdateDownload} = $updKeep.Dl; ${function:Test-GameRunning} = $updKeep.Game
    $Version = $updKeep.Ver; $UpdateDir = $updKeep.Dir
    Remove-Item -LiteralPath $UpdateCache, (Join-Path $Root 'valset.cmd.prev') -ErrorAction SilentlyContinue
    if (-not $instHad) { Remove-Item -LiteralPath $InstalledCmd -ErrorAction SilentlyContinue }
    if ($null -ne $cfgKeep) { Write-FileSafe $ConfigPath $cfgKeep } else { Remove-Item -LiteralPath $ConfigPath -ErrorAction SilentlyContinue }
}
