# pros.ps1 — «Настройки про»: примерить на себя настройки про-игрока. Только на время — «Вернуть исходные» вернёт как было.
# Список — pros.json в репозитории; пока он пуст, пункта в «Ещё» нет. Запись: nick, team, source (откуда взято),
# updated, dpi (на котором его чувствительность), prefs — известная часть облачных настроек в формате profile.json.
# Прицел из кода игры (0;P;…) пока не поддержан: нужен перевод в формат облака.

$ProsUrl   = if ($env:VALSET_PROS) { $env:VALSET_PROS } else { 'https://raw.githubusercontent.com/k0ssk0ss-ai/valset/main/pros.json' }   # VALSET_PROS — для тестов
$ProsCache = Join-Path $Root 'pros.json'
$SensEnum  = 'EAresFloatSettingName::MouseSensitivity'

# Список про — один раз за запуск; без сети — последний скачанный.
function Get-Pros {
    if ($null -eq $script:Pros) {
        $raw = $null
        try {
            $raw = if (Test-Path -LiteralPath $ProsUrl) { Get-Content -LiteralPath $ProsUrl -Raw -Encoding UTF8 } else { (Invoke-WebRequest $ProsUrl -UseBasicParsing -TimeoutSec 3).Content }
            $null = $raw | ConvertFrom-Json
            New-Item -ItemType Directory -Force $Root | Out-Null
            Set-Content $ProsCache $raw -Encoding UTF8
        } catch { $raw = if (Test-Path $ProsCache) { Get-Content $ProsCache -Raw -Encoding UTF8 } }
        $script:Pros = @(if ($raw) { @(($raw | ConvertFrom-Json).pros) | Where-Object { $_.nick -and $_.prefs } })
    }
    , $script:Pros
}

# Наложить известное про на текущие настройки: в списках настроек — по имени, остальные группы — целиком.
function Join-ProPrefs($cur, $prefs) {
    $new = (ConvertTo-Json -InputObject $cur -Depth 32 -Compress) | ConvertFrom-Json
    foreach ($p in $prefs.PSObject.Properties) {
        $items = @($p.Value)
        if ($items.Count -and $items[0].PSObject.Properties['settingEnum'] -and $new.PSObject.Properties[$p.Name]) {
            $names = @($items | ForEach-Object { $_.settingEnum })
            $new.($p.Name) = @(@($new.($p.Name)) | Where-Object { $names -notcontains $_.settingEnum }) + $items
        } else { $new | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
    $new
}

# Чувствительность про пересчитать на твой DPI, чтобы eDPI (DPI × чувствительность) был как у него.
function Convert-ProSens($prefs, [int]$proDpi, [int]$myDpi) {
    $s = @($prefs.floatSettings) | Where-Object { $_.settingEnum -eq $SensEnum } | Select-Object -First 1
    if ($s -and $proDpi -gt 0 -and $myDpi -gt 0) { $s.value = [Math]::Round([double]$s.value * $proDpi / $myDpi, 4) }
}

# DPI мыши спрашиваем один раз.
function Get-MyDpi {
    $dpi = (Get-Config).dpi
    while ($dpi -lt 100) {
        $dpi = (Read-Host (L '    DPI твоей мыши (обычно 400, 800 или 1600)' '    Your mouse DPI (usually 400, 800 or 1600)')) -as [int]
        if ($dpi -ge 100 -and $dpi -le 32000) { Set-Config 'dpi' $dpi } else { $dpi = 0 }
    }
    $dpi
}

function Invoke-ApplyPro($pro) {
    $s = Connect-Session
    $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }
    $cur = $curJson | ConvertFrom-Json
    $prefs = (ConvertTo-Json -InputObject $pro.prefs -Depth 32 -Compress) | ConvertFrom-Json
    if ($pro.dpi -and (@($prefs.floatSettings) | Where-Object { $_.settingEnum -eq $SensEnum })) {
        $my = Get-MyDpi
        Convert-ProSens $prefs ([int]$pro.dpi) $my
        if ([int]$pro.dpi -ne $my) { Write-Note (L "чувствительность пересчитана с его $($pro.dpi) DPI на твои $my" "sensitivity converted from their $($pro.dpi) DPI to your $my") }
    }
    $new = Join-ProPrefs $cur $prefs
    if (Test-PrefsEqual $cur $new) { Write-Ok (L "Уже как у $($pro.nick)" "Already like $($pro.nick)"); return }
    Show-Diff (Compare-Prefs $cur $new)
    Write-Note (L 'на время: «Вернуть исходные» вернёт аккаунт как был' 'for now: “Restore originals” brings the account back')
    if (-not (Confirm-Key (L 'Примерить?' 'Try on?'))) { Write-Note (L 'отменено, аккаунт не тронут' 'cancelled, account untouched'); return }
    $null = Invoke-Step (L 'Резервная копия' 'Backup') { New-Backup $s $curJson }
    Invoke-Step (L 'Запись в облако Riot' 'Writing to the Riot cloud') { Set-Settings $s (ConvertTo-Json -InputObject $new -Depth 32 -Compress) }
    Save-TempOriginal $s.Puuid $curJson
    Log "настройки $($pro.nick) → $(Get-AccountLabel $s.Puuid) (на время)"
    Write-Ok (L "Настройки $($pro.nick) на аккаунте $(Get-AccountLabel $s.Puuid)" "$($pro.nick)'s settings on $(Get-AccountLabel $s.Puuid)")
    if (Get-Process $GameProc -ErrorAction SilentlyContinue) { Write-Note (L 'игра запущена — настройки появятся после её перезапуска' 'the game is running — settings take effect after restarting it') }
    Write-TempNote
}

# Экран выбора: много про — сначала поиск по нику. Возвращает $true, если ждать клавишу.
function Show-Pros {
    $list = Get-Pros
    if ($list.Count -gt 12) {
        Write-Screen (L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS')
        $q = Read-Host (L '    Ник (Enter — все)' '    Nick (Enter — all)')
        if ($q) { $list = @($list | Where-Object { $_.nick -like "*$q*" }) }
        if (-not $list.Count) { Write-Note (L "не нашёл «$q»" "`“$q`” not found"); return $true }
    }
    $items = @($list | ForEach-Object { New-MenuEntry $_.nick ((@($_.team, $_.updated) | Where-Object { $_ }) -join ' · ') }) + (New-MenuEntry (L 'Назад' 'Back') '' 'back')
    $i = Select-Item (L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS') $items
    if ($i -lt 0 -or $i -ge $list.Count) { return $false }
    $pro = $list[$i]
    Write-Screen "$(L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS') · $($pro.nick)"
    if ($pro.source) { Write-Field (L 'Источник' 'Source') $pro.source }
    Invoke-ApplyPro $pro
    $true
}
