# report.ps1 — `valset do report`: текст диагностики для сообщения об ошибке (поле text ответа; в буфер кладёт приложение).
# Только то, что нужно для разбора: версии, регион, число аккаунтов, хвост valset.log. Личное маскируется (Hide-Private):
# Riot ID, PUUID (и его короткая форма), путь профиля Windows, токены. profile.json, заголовки и токены не читаются вовсе.

# Маскирует личные данные в строке. $names / $puuids — известные аккаунты (accounts.json): их вырезаем дословно до регулярок.
function Hide-Private([string]$text, [string[]]$names = @(), [string[]]$puuids = @()) {
    if (-not $text) { return $text }
    foreach ($n in @($names | Where-Object { $_ } | Sort-Object Length -Descending)) { $text = $text.Replace($n, '<riot-id>') }
    foreach ($p in @($puuids | Where-Object { $_ })) { $text = $text.Replace($p, '<puuid>'); if ($p.Length -ge 8) { $text = $text.Replace($p.Substring(0, 8), '<id>') } }
    $text = [regex]::Replace($text, '(?i)\bbearer\s+\S+', 'Bearer <token>')
    $text = [regex]::Replace($text, 'eyJ[\w\-]*(\.[\w\-]*){0,2}', '<token>')
    $text = [regex]::Replace($text, '(?i)\b(access_?token|id_?token|entitlements?(_token)?|authorization|token|password)(["'']?\s*[:=]\s*)(?!<|Bearer\b)\S+', '$1$3<token>')
    $text = [regex]::Replace($text, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<puuid>')
    $text = [regex]::Replace($text, '(?i)\b[0-9a-f]{8}\b', '<id>')
    $text = [regex]::Replace($text, '[^\s#«»"''`,;:()\[\]{}<>]{1,32}#[\p{L}\p{N}]{2,6}\b', '<riot-id>')
    if ($env:USERPROFILE) { $text = [regex]::Replace($text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', 'IgnoreCase') }
    $text = [regex]::Replace($text, '(?i)\b([a-z]:\\(users|пользователи)\\)[^\\\s"''<>]+', '$1<user>')
    $text
}

function Get-WindowsVersionText {
    try {
        $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $name = "$($k.ProductName)"
        if ([int]$k.CurrentBuild -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
        "$name $($k.DisplayVersion) (сборка $($k.CurrentBuild).$($k.UBR))".Trim()
    } catch { [Environment]::OSVersion.VersionString }
}

# Версия клиента игры и регион — из ShooterGame.log (без сети).
function Get-GameLogInfo {
    $r = @{ Version = ''; Region = '' }
    if ($GameLog -and (Test-Path $GameLog)) {
        $v = Select-String -Path $GameLog -Pattern 'CI server version: (release-[\w.\-]+)' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($v) { $r.Version = $v.Matches[0].Groups[1].Value }
        $m = Select-String -Path $GameLog -Pattern 'https://glz-([a-z0-9]+)-1\.' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($m) { $r.Region = $m.Matches[0].Groups[1].Value }
    }
    $r
}

function New-ReportText([int]$tail = 40) {
    $acc = Read-Accounts
    $puuids = @($acc.Keys | ForEach-Object { "$_" })
    $names = @($acc.Values | ForEach-Object { "$($_.name)" } | Where-Object { $_ })
    $g = Get-GameLogInfo
    $lines = @(
        "VALSET $Version"
        "Windows: $(Get-WindowsVersionText)"
        "Клиент игры: $(if ($g.Version) { $g.Version } else { 'неизвестно' })"
        "Регион: $(if ($g.Region) { $g.Region } else { 'неизвестно' })"
        "Аккаунтов: $($puuids.Count)"
        "Язык: $script:Lang"
        ''
        "Последние строки valset.log:"
    )
    if (Test-Path $LogPath) { $lines += @(Get-Content $LogPath -Tail $tail -Encoding UTF8) } else { $lines += '(журнала нет)' }
    Hide-Private ($lines -join "`r`n") $names $puuids
}

# `valset do report` — диагностика в ответе (поле text); точку отмены не трогает.
function Invoke-DoReport($r) {
    $r['text'] = New-ReportText
    L 'Диагностика скопирована — вставь в сообщение об ошибке' 'Diagnostics copied — paste them into the bug report'
}
