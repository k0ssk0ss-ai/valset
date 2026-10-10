# crosshair.ps1 — профили прицела. Лежат одной строкой JSON в stringSettings (SavedCrosshairProfileData):
# { currentProfile: <номер активного>, profiles: [ { profileName, primary, ... }, ... ] }.
# Применение эталона не должно стирать прицелы аккаунта — их дописываем после эталонных.

$CrosshairEnum = 'EAresStringSettingName::SavedCrosshairProfileData'
$CrosshairMax  = 15   # лимит игры с патча 5.04 (было 10)
$script:CrosshairDropped = 0   # сколько прицелов аккаунта не влезло при последнем объединении

function Get-CrosshairEntry($prof) { @($prof.stringSettings) | Where-Object { $_ -and $_.settingEnum -eq $CrosshairEnum } | Select-Object -First 1 }

function Get-Crosshairs($prof) {
    $e = Get-CrosshairEntry $prof
    if (-not $e -or -not $e.value) { return $null }
    try { $e.value | ConvertFrom-Json } catch { $null }
}

function Set-CrosshairValue($prof, [string]$value) {
    $list = @(@($prof.stringSettings) | Where-Object { $_ -and $_.settingEnum -ne $CrosshairEnum })
    $list += [pscustomobject][ordered]@{ settingEnum = $CrosshairEnum; value = $value }
    $prof | Add-Member -NotePropertyName stringSettings -NotePropertyValue $list -Force
}

function ConvertTo-CrosshairJson($data) { ConvertTo-Json -InputObject $data -Depth 20 -Compress }

# Объединяет прицелы: список аккаунта остаётся в своём порядке; эталонных, которых в нём нет, — добавляет в начало
# (одноимённый, но другой прицел аккаунта получает пометку «(акк)»); активным становится активный прицел эталона.
# Больше 15 — срезаются прицелы аккаунта с конца. Итог совпал с аккаунтом — кладём его строку как есть (нет лишней записи).
# Возвращает, сколько прицелов аккаунта сохранено.
# Прицелы при переносе. На время — на аккаунте только твои (чужие путали бы; исходные, с его прицелами, вернутся после
# игры). Насовсем — Merge-Crosshairs. Возвращает, сколько прицелов аккаунта сохранено.
function Join-Crosshairs($cur, $new, [bool]$temp) {
    $script:CrosshairDropped = 0
    $b = Get-Crosshairs $new
    if ($temp -and $b -and @($b.profiles).Count) { return 0 }
    Merge-Crosshairs $cur $new
}

function Merge-Crosshairs($cur, $new) {
    $script:CrosshairDropped = 0
    $a = Get-Crosshairs $cur
    if (-not $a -or -not @($a.profiles).Count) { return 0 }
    $b = Get-Crosshairs $new
    if (-not $b -or -not @($b.profiles).Count) {   # в эталоне прицелов нет (стандарт) — у аккаунта остаются как есть
        Set-CrosshairValue $new (Get-CrosshairEntry $cur).value
        return @($a.profiles).Count
    }
    $refs = @($b.profiles)
    $act = $refs[[Math]::Min([Math]::Max(0, [int]$b.currentProfile), $refs.Count - 1)]
    $mine = @($a.profiles)
    $have = @{}; foreach ($p in $mine) { $have[(ConvertTo-CrosshairJson $p)] = 1 }
    $added = @()
    foreach ($r in $refs) {
        if ($have.ContainsKey((ConvertTo-CrosshairJson $r))) { continue }
        foreach ($p in $mine) { if ("$($p.profileName)" -eq "$($r.profileName)") { $p.profileName = "$($p.profileName) $(L '(акк)' '(acc)')" } }
        $added += $r
    }
    $all = @($added) + $mine
    if ($all.Count -gt $CrosshairMax) { $script:CrosshairDropped = $all.Count - $CrosshairMax; $all = @($all | Select-Object -First $CrosshairMax) }
    $actJson = ConvertTo-CrosshairJson $act
    $idx = 0
    for ($i = 0; $i -lt $all.Count; $i++) { if ((ConvertTo-CrosshairJson $all[$i]) -eq $actJson) { $idx = $i; break } }
    $b.profiles = $all; $b.currentProfile = $idx
    if ((ConvertTo-CrosshairJson $b) -eq (ConvertTo-CrosshairJson $a)) { Set-CrosshairValue $new (Get-CrosshairEntry $cur).value }
    else { Set-CrosshairValue $new (ConvertTo-CrosshairJson $b) }
    $all.Count - $added.Count
}

# Код прицела из игры («0;P;o;0.7;d;1;...») → профиль в облачном виде. В коде только отличия от стандарта:
# 0 — версия, P/A/S — разделы (основной, прицеливание, снайперский), дальше пары «ключ;значение».
# Сверено с 5 прицелами владельца (tests\fixtures); ключи без примеров — по общей раскладке сообщества.
$XhLines = '{"lineThickness":2,"lineLength":@L,"lineLengthVertical":@L,"lineOffset":@O,"bAllowVertScaling":false,"bShowMovementError":@M,"bShowShootingError":true,"bShowMinError":true,"opacity":@A,"bShowLines":true,"firingErrorScale":1,"movementErrorScale":1}'
$XhSection = '{"color":{"b":255,"g":255,"r":255,"a":255},"colorCustom":{"b":255,"g":255,"r":255,"a":255},"bUseCustomColor":false,"bHasOutline":true,"outlineThickness":1,"outlineColor":{"b":0,"g":0,"r":0,"a":255},"outlineOpacity":0.5,"centerDotSize":2,"centerDotOpacity":1,"bDisplayCenterDot":false,"bFadeCrosshairWithFiringError":@F,"bShowSpectatedPlayerCrosshair":@F,"bHideCrosshair":false,"bFixMinErrorAcrossWeapons":false,"innerLines":' +
    $XhLines.Replace('@L', '6').Replace('@O', '3').Replace('@M', 'false').Replace('@A', '0.80000001192092896') + ',"outerLines":' +
    $XhLines.Replace('@L', '2').Replace('@O', '10').Replace('@M', 'true').Replace('@A', '0.34999999403953552') + '}'
$XhFocus = '{"color":{"b":255,"g":255,"r":255,"a":255},"colorCustom":{"b":255,"g":255,"r":255,"a":255},"bUseCustomColor":false,"bHasOutline":false,"outlineThickness":0,"outlineColor":{"b":0,"g":0,"r":0,"a":255},"outlineOpacity":0,"centerDotSize":0,"centerDotOpacity":0,"bDisplayCenterDot":false,"bFadeCrosshairWithFiringError":false,"bShowSpectatedPlayerCrosshair":false,"bHideCrosshair":false,"bFixMinErrorAcrossWeapons":false,"innerLines":@Z,"outerLines":@Z}'.Replace('@Z',
    '{"lineThickness":0,"lineLength":0,"lineLengthVertical":0,"lineOffset":0,"bAllowVertScaling":false,"bShowMovementError":false,"bShowShootingError":false,"bShowMinError":false,"opacity":0,"bShowLines":false,"firingErrorScale":0,"movementErrorScale":0}')
$XhPalette = 'FFFFFF', '00FF00', '7FFF00', 'DFFF00', 'FFFF00', '00FFFF', 'FF00FF', 'FF0000'   # c;0..7, 8 — свой цвет
$XhKeys  = @{ h = 'bHasOutline'; t = 'outlineThickness'; o = 'outlineOpacity'; d = 'bDisplayCenterDot'; z = 'centerDotSize'
              a = 'centerDotOpacity'; f = 'bFadeCrosshairWithFiringError'; s = 'bShowSpectatedPlayerCrosshair'; m = 'bFixMinErrorAcrossWeapons' }
$XhLine  = @{ b = 'bShowLines'; t = 'lineThickness'; l = 'lineLength'; v = 'lineLengthVertical'; g = 'bAllowVertScaling'; o = 'lineOffset'
              a = 'opacity'; m = 'bShowMovementError'; f = 'bShowShootingError'; s = 'movementErrorScale'; e = 'firingErrorScale' }
$XhGen   = @{ p = 'bUsePrimaryCrosshairForADS'; c = 'bUseCustomCrosshairOnAllPrimary'; s = 'bUseAdvancedOptions' }
$XhSnip  = @{ d = 'bDisplayCenterDot'; s = 'centerDotSize'; o = 'centerDotOpacity' }

function ConvertTo-XhColor([string]$hex) {
    $h = $hex.PadRight(8, 'F')
    [pscustomobject][ordered]@{ b = [Convert]::ToInt32($h.Substring(4, 2), 16); g = [Convert]::ToInt32($h.Substring(2, 2), 16)
                                r = [Convert]::ToInt32($h.Substring(0, 2), 16); a = [Convert]::ToInt32($h.Substring(6, 2), 16) }
}

# Значение из кода: целое — целым, дробное — как float игры (0.7 → 0.699999988…), чтобы JSON совпал с облаком.
function ConvertFrom-XhValue([string]$v, $old) {
    if ($old -is [bool]) { return $v -ne '0' }
    if ($v -match '^-?\d+$') { return [int]$v }
    $inv = [Globalization.CultureInfo]::InvariantCulture   # ConvertFrom-Json даёт decimal — им и отдаём
    [decimal]::Parse(([double][single][double]::Parse($v, $inv)).ToString('G17', $inv), [Globalization.NumberStyles]::Float, $inv)
}

function ConvertFrom-CrosshairCode([string]$code, [string]$name) {
    $p = '{"primary":' + $XhSection.Replace('@F', 'true') + ',"aDS":' + $XhSection.Replace('@F', 'false') + ',"focusMode":' + $XhFocus +
         ',"sniper":{"centerDotColor":{"b":0,"g":0,"r":255,"a":255},"centerDotColorCustom":{"b":255,"g":255,"r":255,"a":255},"centerDotSize":1,"centerDotOpacity":0.75,"bDisplayCenterDot":true,"bUseCustomCenterDotColor":false}' +
         ',"bUsePrimaryCrosshairForADS":true,"bUsePrimaryCrosshairForFocusMode":false,"bUseCustomCrosshairOnAllPrimary":false,"bUseAdvancedOptions":false,"bScaleToResolution":false,"profileName":""}' | ConvertFrom-Json
    $p.profileName = $name
    $t = @(($code.Trim() -split ';') | Select-Object -Skip 1)   # первое — версия кода
    $sec = 'G'
    for ($i = 0; $i -lt $t.Count; $i++) {
        $k = $t[$i]
        if ($k -cin 'P', 'A', 'S') { $sec = $k; continue }
        $v = if ($i + 1 -lt $t.Count) { $t[$i + 1] } else { '' }; $i++
        if ($sec -eq 'G') { if ($XhGen.ContainsKey($k)) { $p.($XhGen[$k]) = $v -ne '0' }; continue }
        if ($sec -eq 'S') {
            $s = $p.sniper
            if ($k -eq 'c') { if ([int]$v -ge 8) { $s.bUseCustomCenterDotColor = $true } elseif ([int]$v -ge 0) { $s.centerDotColor = ConvertTo-XhColor $XhPalette[[int]$v] } }
            elseif ($k -eq 'u') { $s.centerDotColorCustom = ConvertTo-XhColor $v }
            elseif ($XhSnip.ContainsKey($k)) { $s.($XhSnip[$k]) = ConvertFrom-XhValue $v $s.($XhSnip[$k]) }
            continue
        }
        $s = if ($sec -eq 'P') { $p.primary } else { $p.aDS }
        if ($k -match '^([01])(\w)$') {   # 0x — внутренние линии, 1x — внешние
            $ln = if ($Matches[1] -eq '0') { $s.innerLines } else { $s.outerLines }; $f = $XhLine[$Matches[2]]
            if ($f) { $ln.$f = ConvertFrom-XhValue $v $ln.$f }
        }
        elseif ($k -eq 'c') { if ([int]$v -ge 8) { $s.bUseCustomColor = $true } elseif ([int]$v -ge 0) { $s.color = ConvertTo-XhColor $XhPalette[[int]$v] } }
        elseif ($k -eq 'u') { $s.colorCustom = ConvertTo-XhColor $v }
        elseif ($XhKeys.ContainsKey($k)) { $s.($XhKeys[$k]) = ConvertFrom-XhValue $v $s.($XhKeys[$k]) }
    }
    $p
}

function Format-Crosshairs([string]$value) {
    if (-not $value) { return (L 'стандарт' 'default') }
    try {
        $d = $value | ConvertFrom-Json; $ps = @($d.profiles)
        $act = if ([int]$d.currentProfile -lt $ps.Count) { " · «$($ps[[int]$d.currentProfile].profileName)»" } else { '' }
        "$($ps.Count) $(L 'шт.' 'pcs')$act"
    } catch { L 'есть' 'present' }
}
