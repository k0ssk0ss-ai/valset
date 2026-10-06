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
# Оставляет только активный прицел (для короткого кода).
function Select-ActiveCrosshair($prof) {
    $d = Get-Crosshairs $prof
    if (-not $d) { return }
    $ps = @($d.profiles)
    if (-not $ps.Count) { return }
    $i = [int]$d.currentProfile
    if ($i -lt 0 -or $i -ge $ps.Count) { $i = 0 }
    $d.profiles = @($ps[$i]); $d.currentProfile = 0
    Set-CrosshairValue $prof (ConvertTo-CrosshairJson $d)
}

function Format-Crosshairs([string]$value) {
    if (-not $value) { return (L 'стандарт' 'default') }
    try {
        $d = $value | ConvertFrom-Json; $ps = @($d.profiles)
        $act = if ([int]$d.currentProfile -lt $ps.Count) { " · «$($ps[[int]$d.currentProfile].profileName)»" } else { '' }
        "$($ps.Count) $(L 'шт.' 'pcs')$act"
    } catch { L 'есть' 'present' }
}
