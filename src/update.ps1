# update.ps1 — обновления: `valset list update[:now]` (один GET к GitHub, кэш 12 ч), `valset do update` (скачать, сверить
# SHA-256 с SHA256SUMS.txt релиза, запустить скачанный valset.cmd с `install -Yes`), `install -Yes` (тихая установка поверх).
# Проверка — только если config.updateCheck (по умолчанию вкл); выключено — ни одного запроса, кроме `list update:now`.
# В GitHub уходит только User-Agent VALSET/<версия>: ничего о человеке. Ошибки сети — тихо, ответом {error}.

$UpdateApi   = 'https://api.github.com/repos/k0ssk0ss-ai/valset/releases/latest'
$UpdateCache = Join-Path $Root 'cache\update.json'
$UpdateTtlH  = 12
$UpdateDir   = Join-Path $env:TEMP 'valset-update'

# Один запрос к GitHub (в тестах подменяется).
function Invoke-UpdateRequest {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod $UpdateApi -UserAgent "VALSET/$Version" -Headers @{ Accept = 'application/vnd.github+json' } -TimeoutSec 8 -UseBasicParsing
}

# Скачать файл релиза (в тестах подменяется).
function Invoke-UpdateDownload([string]$url, [string]$path) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $url -OutFile $path -UserAgent "VALSET/$Version" -TimeoutSec 60 -UseBasicParsing
}

# Версии сравниваем как [version]: 2.1.10 новее 2.1.9 (строкой было бы наоборот). Плохая строка — $null.
function ConvertTo-UpdateVersion([string]$tag) {
    $t = "$tag".Trim() -replace '^[vV]', ''
    $v = $null
    if ([version]::TryParse($t, [ref]$v)) { $v } else { $null }
}

# Ответ GitHub → то, что храним в кэше (без «newer»: его считаем от текущей версии при каждом чтении).
function ConvertTo-UpdateRelease($rel) {
    $tag = "$($rel.tag_name)".Trim() -replace '^[vV]', ''
    if (-not (ConvertTo-UpdateVersion $tag)) { throw "непонятная версия релиза: $($rel.tag_name)" }
    $assets = @($rel.assets)
    $pick = { param($n) "$((@($assets | Where-Object { $_.name -eq $n }) | Select-Object -First 1).browser_download_url)" }
    $notes = @("$($rel.body)" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 6) -join "`n"
    [ordered]@{ latest = $tag; url = "$($rel.html_url)"; notes = $notes; asset = (& $pick 'valset.cmd'); sums = (& $pick 'SHA256SUMS.txt'); at = [DateTime]::UtcNow.ToString('o') }
}

function Complete-UpdateInfo($c) {
    $lv = ConvertTo-UpdateVersion $c.latest
    [ordered]@{ current = $Version; latest = "$($c.latest)"; newer = [bool]($lv -and $lv -gt [version]$Version)
                url = "$($c.url)"; notes = "$($c.notes)"; asset = "$($c.asset)"; sums = "$($c.sums)" }
}

function Read-UpdateCache {
    if (-not (Test-Path $UpdateCache)) { return $null }
    try { $c = Get-Content $UpdateCache -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.latest) { $c } } catch { $null }
}

# -Force — спросить GitHub сейчас (кнопка «Проверить сейчас», `do update`), даже если проверка выключена или кэш свежий.
function Get-UpdateInfo([switch]$Force) {
    if (-not $Force -and -not (Get-Config).updateCheck) { return [ordered]@{ current = $Version; off = $true } }
    $c = Read-UpdateCache
    if (-not $Force -and $c) {
        $at = [DateTime]::MinValue
        if ([DateTime]::TryParse("$($c.at)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$at) -and
            ([DateTime]::UtcNow - $at.ToUniversalTime()).TotalHours -lt $UpdateTtlH) { return (Complete-UpdateInfo $c) }
    }
    try {
        $rel = ConvertTo-UpdateRelease (Invoke-UpdateRequest)
        New-Item -ItemType Directory -Force (Split-Path $UpdateCache) | Out-Null
        Write-FileSafe $UpdateCache (ConvertTo-Json -InputObject $rel -Compress)
        Complete-UpdateInfo $rel
    } catch {
        Log "обновления: проверка не удалась: $($_.Exception.Message)"
        if ($c) { return (Complete-UpdateInfo $c) }   # нет сети — последнее известное
        [ordered]@{ current = $Version; error = (L 'Не получилось проверить обновления' 'Could not check for updates') }
    }
}

function Get-UpdateJson([switch]$Force) { ConvertTo-Json -InputObject (Get-UpdateInfo -Force:$Force) -Compress }

# Хэш valset.cmd совпадает со строкой «<sha256>  valset.cmd» в SHA256SUMS.txt.
function Test-UpdateHash([string]$file, [string]$sumsPath) {
    if (-not (Test-Path $file) -or -not (Test-Path $sumsPath)) { return $false }
    $m = [regex]::Match([IO.File]::ReadAllText($sumsPath), '(?m)^([0-9a-fA-F]{64})\s+\*?valset\.cmd\s*$')
    $m.Success -and $m.Groups[1].Value.ToLower() -eq (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
}

# `do update`: непроверенный файл не запускается никогда.
function Invoke-Update {
    if (Test-GameRunning) { throw (L 'Идёт игра. Обнови после неё' 'The game is running. Update after it') }
    $i = Get-UpdateInfo -Force
    if ($i.error) { throw (L 'Не получилось связаться с GitHub. Проверь интернет' 'Could not reach GitHub. Check your internet') }
    if (-not $i.newer) { return (L "У тебя последняя версия $Version" "You have the latest version $Version") }
    if (-not $i.asset) { throw (L 'В релизе нет файла valset.cmd. Обновление не поставлено' 'The release has no valset.cmd. Nothing was installed') }
    if (-not $i.sums) { throw (L 'В релизе нет файла с хэшами. Обновление не поставлено' 'The release has no checksum file. Nothing was installed') }
    if (Test-Path $UpdateDir) { Remove-Item -LiteralPath $UpdateDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force $UpdateDir | Out-Null
    $cmd = Join-Path $UpdateDir 'valset.cmd'; $sums = Join-Path $UpdateDir 'SHA256SUMS.txt'
    try { Invoke-UpdateDownload $i.asset $cmd } catch { Log "обновление: не скачалось: $($_.Exception.Message)"; throw (L 'Не получилось скачать обновление. Проверь интернет' 'Could not download the update. Check your internet') }
    try { Invoke-UpdateDownload $i.sums $sums } catch { Log "обновление: нет SHA256SUMS.txt: $($_.Exception.Message)" }
    if (-not (Test-Path $sums)) { Remove-Item -LiteralPath $cmd -Force -ErrorAction SilentlyContinue; throw (L 'Не скачался файл с хэшами. Обновление не поставлено' 'The checksum file did not download. Nothing was installed') }
    if (-not (Test-UpdateHash $cmd $sums)) {
        Remove-Item -LiteralPath $cmd -Force -ErrorAction SilentlyContinue
        Log "обновление $($i.latest): хэш не совпал, файл удалён"
        throw (L 'Хэш файла не совпал с релизом. Обновление не поставлено' 'The file hash does not match the release. Nothing was installed')
    }
    if (Test-Path $InstalledCmd) { Copy-Item -LiteralPath $InstalledCmd (Join-Path $Root 'valset.cmd.prev') -Force }   # ручной откат
    Start-Process -FilePath $cmd -ArgumentList 'install', '-Yes' -WorkingDirectory $UpdateDir -WindowStyle Hidden
    Log "обновление: хэш совпал, ставлю $($i.latest) (прежний valset.cmd — valset.cmd.prev)"
    L "Обновлено до $($i.latest). Приложение перезапустится" "Updated to $($i.latest). The app will restart"
}

# `install -Yes`: без вопросов, поверх установленного. Приложение останавливаем всегда: в его памяти старое ядро,
# даже если исходники окна не менялись (иначе Enable-App его не перезапустит).
function Invoke-InstallQuiet {
    Start-Sleep -Seconds 2   # панель успевает показать ответ `do update`
    if (Test-AppRunning) { Stop-App }
    Invoke-Install
    Log "обновлено до $Version"
}
