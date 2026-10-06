# VALSET — установка одной командой (Win+R или PowerShell):
#   powershell -c "[Net.ServicePointManager]::SecurityProtocol=3072;irm https://raw.githubusercontent.com/k0ssk0ss-ai/valset/main/install.ps1|iex"
#
# Что делает: скачивает valset.cmd из последнего релиза на GitHub, сверяет SHA-256 с SHA256SUMS.txt того же
# релиза, устанавливает (папка %USERPROFILE%\valset, команда valset, меню по Ctrl+Alt+V) и открывает меню.
# Файлы, скачанные самим PowerShell, Windows не помечает «из интернета» — окна SmartScreen не будет.
# Работает на чистой Windows 10 / 11: только встроенный PowerShell 5.1, TLS 1.2 включается явно,
# -UseBasicParsing — потому что в Windows 11 нет движка Internet Explorer.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # полоса прогресса в PowerShell 5.1 замедляет загрузку в разы

$repo = 'k0ssk0ss-ai/valset'
$base = "https://github.com/$repo/releases/latest/download"
$tmp  = Join-Path $env:TEMP ('valset-setup-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$langs = @((Get-ItemProperty 'HKCU:\Control Panel\International\User Profile' -Name Languages -ErrorAction SilentlyContinue).Languages) + @((Get-UICulture).Name)
$ru = [bool]($langs | Where-Object { $_ -match '^(ru|uk|be|kk)(-|$)' })
function T([string]$r, [string]$e) { if ($ru) { $r } else { $e } }

try {
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Write-Host ''
    Write-Host (T '  VALSET — установка' '  VALSET — setup') -ForegroundColor Red
    Write-Host (T '    скачиваю последнюю версию с GitHub…' '    downloading the latest version from GitHub…') -ForegroundColor Gray
    $cmd = Join-Path $tmp 'valset.cmd'
    Invoke-WebRequest "$base/valset.cmd" -OutFile $cmd -UseBasicParsing
    $raw = (Invoke-WebRequest "$base/SHA256SUMS.txt" -UseBasicParsing).Content
    $sums = if ($raw -is [byte[]]) { [Text.Encoding]::ASCII.GetString($raw) } else { "$raw" }
    $want = ([regex]::Match($sums, '([0-9a-fA-F]{64})\s+valset\.cmd')).Groups[1].Value.ToLower()
    $got  = (Get-FileHash $cmd -Algorithm SHA256).Hash.ToLower()
    if (-not $want -or $want -ne $got) { throw (T 'контрольная сумма не совпала: файл повреждён при загрузке. Ничего не установлено — попробуй ещё раз.' 'checksum mismatch: the file got damaged while downloading. Nothing was installed — please try again.') }
    Write-Host (T '    файл проверен (SHA-256 совпадает с релизом)' '    file verified (SHA-256 matches the release)') -ForegroundColor Gray
    & cmd.exe /c "`"$cmd`" install"
    if ($LASTEXITCODE -ne 0) { throw (T 'установка не завершилась — подробности выше.' 'installation did not finish — see above.') }
    Start-Process (Join-Path $env:USERPROFILE 'valset\valset.cmd')   # открыть меню в своём окне
} catch {
    Write-Host ''
    Write-Host "  × $($_.Exception.Message)" -ForegroundColor Red
    Write-Host (T '    Нет интернета или GitHub недоступен? Можно скачать VALSET-*.zip вручную:' '    No internet or GitHub unreachable? Download VALSET-*.zip manually:') -ForegroundColor Gray
    Write-Host "    https://github.com/$repo/releases/latest" -ForegroundColor Gray
    Write-Host ''
    Read-Host (T '  Enter — закрыть' '  Enter — close')
} finally {
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
