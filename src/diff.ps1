# diff.ps1 — что изменится на аккаунте: сравнение облачных настроек до записи.
# Понятным списком показываются бинды общего набора и настройки по settingEnum;
# остальное (агентские бинды, оси, профили прицела) сравнивается целиком в Test-PrefsEqual.

function Get-PrefDef([string]$enum) { $SettingDefs | Where-Object { $_.Kind -eq 'cloud' -and $_.Enum -eq $enum } | Select-Object -First 1 }

function Format-PrefValue([string]$enum, $v) {
    if ($null -eq $v) { return (L 'стандарт' 'default') }
    $d = Get-PrefDef $enum
    if ($d) {
        foreach ($o in $d.Opts) { if (Test-SameValue $o.V $v) { return $o.L } }
        if ($d.Format -eq 'pct') { return ('{0:0}%' -f ([double]$v * 100)) }
    }
    if ($v -is [bool]) { return $(if ($v) { L 'вкл' 'on' } else { L 'выкл' 'off' }) }
    if ($v -is [double] -or $v -is [decimal]) { return ([double]$v).ToString('0.####', $Inv) }
    $t = "$v"
    if ($t.Length -gt 18) { $t = $t.Substring(0, 17) + '…' }
    $t
}

# Список отличий: @{ What; Old; New }.
function Compare-Prefs($cur, $new, [switch]$BindsOnly) {
    $out = New-Object Collections.Generic.List[object]
    $keys = @(@($cur.actionMappings) + @($new.actionMappings) | Where-Object { $_ -and (Test-General $_) } |
        ForEach-Object { "$($_.name)|$($_.bindIndex)" } | Sort-Object -Unique)
    foreach ($k in $keys) {
        $a, $i = $k -split '\|'
        $o = Format-Key (Get-Binding $cur $a $i); $w = Format-Key (Get-Binding $new $a $i)
        if ($o -ne $w) { $out.Add([pscustomobject]@{ What = "$(Get-ActionLabel $a)$(if ([int]$i) { L ' · доп.' ' · alt' })"; Old = $o; New = $w }) }
    }
    if ($BindsOnly) { return , $out.ToArray() }
    foreach ($g in 'floatSettings', 'intSettings', 'boolSettings', 'stringSettings') {
        $a = @{}; $b = @{}
        foreach ($e in @($cur.$g)) { if ($e) { $a[$e.settingEnum] = $e.value } }
        foreach ($e in @($new.$g)) { if ($e) { $b[$e.settingEnum] = $e.value } }
        foreach ($k in @($a.Keys) + @($b.Keys) | Sort-Object -Unique) {
            if (Test-SameValue $a[$k] $b[$k]) { continue }
            if ($k -eq $CrosshairEnum) {
                $ja = if ($a[$k]) { try { ConvertTo-CrosshairJson ($a[$k] | ConvertFrom-Json) } catch { $a[$k] } }
                $jb = if ($b[$k]) { try { ConvertTo-CrosshairJson ($b[$k] | ConvertFrom-Json) } catch { $b[$k] } }
                if ($ja -ne $jb) { $out.Add([pscustomobject]@{ What = (L 'Прицелы' 'Crosshairs'); Old = (Format-Crosshairs $a[$k]); New = (Format-Crosshairs $b[$k]) }) }
                continue
            }
            $d = Get-PrefDef $k
            $what = if ($d) { $d.Label } else { $k -replace '^.*::', '' }
            $out.Add([pscustomobject]@{ What = $what; Old = (Format-PrefValue $k $a[$k]); New = (Format-PrefValue $k $b[$k]) })
        }
    }
    , $out.ToArray()   # массив, не List: @() вокруг List[object] в PowerShell 5.1 падает «Argument types do not match»
}

# Совпадают ли наборы целиком (все группы). Порядок записей мог отличаться — тогда просто запишем ещё раз.
function Test-PrefsEqual($cur, $new) {
    $names = @($cur.PSObject.Properties.Name) + @($new.PSObject.Properties.Name) | Sort-Object -Unique
    foreach ($n in $names) { if ((Get-JsonPart $cur $n) -ne (Get-JsonPart $new $n)) { return $false } }
    $true
}

function Show-Diff($list, [int]$max = 12) {
    if (-not $list.Count) { return }
    Write-Host ''
    Write-Host "    $(L 'изменится' 'will change'): $($list.Count)" -ForegroundColor White
    foreach ($d in ($list | Select-Object -First $max)) {
        $what = "$($d.What)"; if ($what.Length -gt 30) { $what = $what.Substring(0, 29) + '…' }
        Write-Host -NoNewline ('      ' + $what.PadRight(31)) -ForegroundColor Gray
        Write-Host -NoNewline "$($d.Old)" -ForegroundColor DarkGray
        Write-Host -NoNewline ' → ' -ForegroundColor DarkGray
        Write-Host "$($d.New)" -ForegroundColor Green
    }
    if ($list.Count -gt $max) { Write-Host "      … $(L 'и ещё' 'and') $($list.Count - $max)$(L '' ' more')" -ForegroundColor DarkGray }
    Write-Host ''
}

# Полный список отличий с листанием: «настройка · на аккаунте → твои».
function Show-DiffList($list, [string]$title) {
    $list = @($list)
    $per = 10; try { $per = [Math]::Max(5, [Console]::WindowHeight - 10) } catch {}
    $pages = [Math]::Max(1, [Math]::Ceiling($list.Count / $per)); $p = 0
    while ($true) {
        Write-Screen $title
        Write-Host ('      ' + (L 'настройка' 'setting').PadRight(31) + (L 'на аккаунте → твои' 'on account → yours')) -ForegroundColor DarkGray
        foreach ($d in ($list | Select-Object -Skip ($p * $per) -First $per)) {
            $what = "$($d.What)"; if ($what.Length -gt 30) { $what = $what.Substring(0, 29) + '…' }
            Write-Host -NoNewline ('      ' + $what.PadRight(31)) -ForegroundColor Gray
            Write-Host -NoNewline "$($d.Old)" -ForegroundColor Yellow
            Write-Host -NoNewline ' → ' -ForegroundColor DarkGray
            Write-Host "$($d.New)" -ForegroundColor Green
        }
        Write-Host ''
        $nav = if ($pages -gt 1) { "$(L 'стр.' 'page') $($p + 1)/$pages · ←→ $(L 'листать' 'scroll') · " } else { '' }
        Write-Host "    $($nav)Esc — $(L 'назад' 'back')" -ForegroundColor DarkGray
        $k = Read-KeyOrQuit
        switch ("$($k.Key)") {
            { $_ -in 'RightArrow', 'DownArrow', 'PageDown', 'Spacebar' } { if ($p -lt $pages - 1) { $p++ } }
            { $_ -in 'LeftArrow', 'UpArrow', 'PageUp' } { if ($p -gt 0) { $p-- } }
            { $_ -in 'Escape', 'Enter', 'Backspace' } { return }
        }
    }
}