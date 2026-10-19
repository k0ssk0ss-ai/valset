# session.ps1 — сессионный эталон: после игры берём из облака только то, что игрок поменял сам
# (трёхстороннее слияние: эталон $ref, записанное $base, облако сейчас $now), и накладываем на эталон.

function Copy-Json($o) { (ConvertTo-Json -InputObject $o -Depth 32 -Compress) | ConvertFrom-Json }
function Get-JsonKey($o) { ConvertTo-Json -InputObject $o -Depth 32 -Compress }

# Группа настроек — массив объектов с settingEnum.
function Test-SettingGroup($items) {
    $f = @($items) | Where-Object { $_ } | Select-Object -First 1
    [bool]($f -and $f.PSObject.Properties['settingEnum'])
}

function Get-ProfileName($p) { "$($p.profileName)" }

# Прицелы: по profileName. Чужие прицелы аккаунта в эталон не попадают — только те, что игрок менял/добавлял/удалил.
# Возвращает имена изменённых прицелов; $out правится на месте.
function Merge-RefCrosshairs($out, $base, $now) {
    $chg = @()
    $b = Get-Crosshairs $base; $n = Get-Crosshairs $now
    if (-not $n) { return $chg }   # прицелов в облаке нет совсем (сбой, сброс) — свои не стираем
    $bp = @(if ($b) { $b.profiles }); $np = @(if ($n) { $n.profiles })
    $bAct = if ($bp.Count) { Get-ProfileName $bp[[Math]::Min([Math]::Max(0, [int]$b.currentProfile), $bp.Count - 1)] } else { $null }
    $nAct = if ($np.Count) { Get-ProfileName $np[[Math]::Min([Math]::Max(0, [int]$n.currentProfile), $np.Count - 1)] } else { $null }
    $r0 = Get-Crosshairs $out
    if (-not $r0) { $r0 = [pscustomobject][ordered]@{ currentProfile = 0; profiles = @() } }
    $rp = @($r0.profiles)
    $rAct = if ($rp.Count) { Get-ProfileName $rp[[Math]::Min([Math]::Max(0, [int]$r0.currentProfile), $rp.Count - 1)] } else { $null }
    $bMap = @{}; foreach ($p in $bp) { $bMap[(Get-ProfileName $p)] = Get-JsonKey $p }
    $nNames = @{}; foreach ($p in $np) { $nNames[(Get-ProfileName $p)] = 1 }
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $rp) { [void]$list.Add($p) }
    foreach ($p in $np) {
        $name = Get-ProfileName $p
        if ($bMap.ContainsKey($name) -and $bMap[$name] -eq (Get-JsonKey $p)) { continue }   # игрок не трогал
        $at = -1; for ($i = 0; $i -lt $list.Count; $i++) { if ((Get-ProfileName $list[$i]) -eq $name) { $at = $i; break } }
        $cp = Copy-Json $p
        if ($at -ge 0) { if ((Get-JsonKey $list[$at]) -eq (Get-JsonKey $cp)) { continue }; $list[$at] = $cp } else { [void]$list.Add($cp) }
        $chg += "Crosshair:$name"
    }
    foreach ($name in @($bMap.Keys)) {
        if ($nNames.ContainsKey($name)) { continue }   # удалён в игре
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ((Get-ProfileName $list[$i]) -eq $name) { $list.RemoveAt($i); $chg += "Crosshair:$name"; break }
        }
    }
    while ($list.Count -gt $CrosshairMax) { $list.RemoveAt($list.Count - 1) }
    # активный: прежний эталонный, если остался; переключил игрок — его выбор
    $want = $rAct
    if ($nAct -and $nAct -ne $bAct) { $want = $nAct }
    $idx = 0; for ($i = 0; $i -lt $list.Count; $i++) { if ((Get-ProfileName $list[$i]) -eq $want) { $idx = $i; break } }
    if ($nAct -and $nAct -ne $bAct -and $want -ne $rAct -and (Get-ProfileName $list[$idx]) -eq $want -and $chg -notcontains "Crosshair:$want") { $chg += "Crosshair:$want" }
    if ($chg.Count) {
        $r0.profiles = @($list); $r0.currentProfile = $idx
        Set-CrosshairValue $out (ConvertTo-CrosshairJson $r0)
    }
    $chg
}

# Накладывает на эталон правки игрока (base → now). Входные объекты не меняются.
# Scope 'binds' — только раскладка клавиш ($BindKeys). Changed пуст — делать нечего.
function Merge-Reference($ref, $base, $now, [string]$Scope = 'all') {
    $out = Copy-Json $ref
    $changed = @()
    $keys = @()
    foreach ($o in $now, $base) { if ($o) { foreach ($p in $o.PSObject.Properties) { if ($keys -notcontains $p.Name) { $keys += $p.Name } } } }
    if ($Scope -eq 'binds') { $keys = @($keys | Where-Object { $BindKeys -contains $_ }) }
    foreach ($k in $keys) {
        $bv = if ($base -and $base.PSObject.Properties[$k]) { $base.$k } else { $null }
        $nv = if ($now -and $now.PSObject.Properties[$k]) { $now.$k } else { $null }
        if ((Test-SettingGroup $bv) -or (Test-SettingGroup $nv)) {
            $bm = @{}; foreach ($i in @($bv)) { if ($i) { $bm["$($i.settingEnum)"] = $i } }
            $nm = @{}; foreach ($i in @($nv)) { if ($i) { $nm["$($i.settingEnum)"] = $i } }
            $enums = @($nm.Keys) + @($bm.Keys | Where-Object { -not $nm.ContainsKey($_) })
            $cur = if ($out.PSObject.Properties[$k]) { @($out.$k) } else { @() }
            $touched = $false
            foreach ($e in $enums) {
                if ($e -eq $CrosshairEnum) { continue }   # прицелы — отдельно, по именам
                if ($bm.ContainsKey($e) -and $nm.ContainsKey($e) -and (Get-JsonKey $bm[$e]) -eq (Get-JsonKey $nm[$e])) { continue }
                $cur = @($cur | Where-Object { $_ -and "$($_.settingEnum)" -ne $e })
                if ($nm.ContainsKey($e)) { $cur += Copy-Json $nm[$e] }
                $touched = $true; $changed += $e
            }
            if ($touched) { $out | Add-Member -NotePropertyName $k -NotePropertyValue @($cur) -Force }
        } else {
            if ((Get-JsonKey $bv) -eq (Get-JsonKey $nv)) { continue }
            if ($null -ne $nv) { $out | Add-Member -NotePropertyName $k -NotePropertyValue (Copy-Json ([pscustomobject]@{ v = $nv })).v -Force }   # через обёртку: голый массив 5.1 сериализует криво
            elseif ($out.PSObject.Properties[$k]) { $out.PSObject.Properties.Remove($k) }
            $changed += $k
        }
    }
    if ($Scope -ne 'binds') { $changed += @(Merge-RefCrosshairs $out $base $now) }
    @{ Ref = $out; Changed = @($changed) }
}
