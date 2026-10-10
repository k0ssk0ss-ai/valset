# pros.ps1 — «Настройки про»: примерить на себя настройки про-игрока. Только на время — «Вернуть исходные» вернёт как было.
# Список — pros.json в репозитории; пока он пуст, пункта в «Ещё» нет. Запись: nick, team, source (откуда взято),
# updated, dpi (на котором его чувствительность), crosshair (код игры 0;P;…), prefs — известная часть облачных
# настроек в формате profile.json. Лежит в pros\pros-v2.json, собирается tools\build-pros.ps1 из pros-raw\.

$ProsUrl   = if ($env:VALSET_PROS) { $env:VALSET_PROS } else { 'https://raw.githubusercontent.com/k0ssk0ss-ai/valset/main/pros/pros-v2.json' }   # VALSET_PROS — для тестов; v2 — с прицелом, pros.json в корне пуст для 1.1.0
$ProsCache = Join-Path $Root 'pros-v2.json'
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

# Прицел про — первым в списке и активным; его одноимённый убираем, лишние сверх 15 (лимит игры) — с конца.
function Add-ProCrosshair($prof, $pro) {
    $p = ConvertFrom-CrosshairCode $pro.crosshair $pro.nick
    $d = Get-Crosshairs $prof
    $rest = if ($d) { @(@($d.profiles) | Where-Object { $_.profileName -ne $pro.nick }) } else { @() }
    $all = @(@($p) + $rest | Select-Object -First 15)
    Set-CrosshairValue $prof (ConvertTo-CrosshairJson ([ordered]@{ currentProfile = 0; profiles = $all }))
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
    if ($pro.crosshair) { Add-ProCrosshair $new $pro }
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

# Экран выбора: список по страницам (влезает в окно) + поиск по нику. Возвращает $true, если ждать клавишу.
function Show-Pros {
    $all = Get-Pros; $list = $all; $q = ''; $pg = 0
    $size = 10; try { $size = [Math]::Max(5, [Math]::Min(10, [Console]::WindowHeight - 16)) } catch {}   # больше 10 не влезает в окна с неверной высотой
    while ($true) {
        $pages = [Math]::Max(1, [Math]::Ceiling($list.Count / $size)); $pg = [Math]::Min($pg, $pages - 1)
        $shown = @($list | Select-Object -Skip ($pg * $size) -First $size)
        $items = @(New-MenuEntry (L 'Поиск по нику' 'Search by nick') $(if ($q) { "«$q» · $(L 'Enter без ника — все' 'empty — all')" }) 'search')
        $items += @($shown | ForEach-Object { New-MenuEntry $_.nick ((@($_.team, $(if ($_.PSObject.Properties['active'] -and -not $_.active) { L 'не играет' 'retired' }), $_.updated) | Where-Object { $_ }) -join ' · ') 'pro' })
        if ($pg + 1 -lt $pages) { $items += New-MenuEntry (L 'Дальше →' 'Next →') "$($pg + 2)/$pages" 'next' }
        if ($pg -gt 0) { $items += New-MenuEntry (L '← Раньше' '← Previous') "$pg/$pages" 'prev' }
        $items += New-MenuEntry (L 'Назад' 'Back') '' 'back'
        $title = "$(L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS')$(if ($pages -gt 1) { " · $($pg + 1)/$pages" })"
        $i = Select-Item $title $items
        if ($i -lt 0) { return $false }
        switch ($items[$i].Id) {
            'next'   { $pg++; continue }
            'prev'   { $pg--; continue }
            'back'   { return $false }
            'search' {
                Write-Screen (L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS')
                $q = (Read-Host (L '    Ник (Enter — все)' '    Nick (Enter — all)')).Trim()
                $list = if ($q) { @($all | Where-Object { $_.nick -like "*$q*" }) } else { $all }
                if (-not $list.Count) { Write-Note (L "не нашёл «$q»" "`“$q`” not found"); $q = ''; $list = $all; Start-Sleep 2 }
                $pg = 0; continue
            }
        }
        if ($items[$i].Id -eq 'pro') { break }
    }
    $pro = $shown[$i - 1]
    Write-Screen "$(L 'НАСТРОЙКИ ПРО' 'PRO SETTINGS') · $($pro.nick)"
    if ($pro.source) { Write-Field (L 'Источник' 'Source') $pro.source }
    Invoke-ApplyPro $pro
    $true
}
