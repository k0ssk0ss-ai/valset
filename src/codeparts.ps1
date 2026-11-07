# codeparts.ps1 — разделы кода VALSET3 поверх codec.ps1: бинды, настройки, прицел и код целиком (заголовок, разделы, CRC).
# Раскладка байтов — NOTES.md «Код VALSET3». Скины — shareskins.ps1.

# ── Бинды ────────────────────────────────────────────────────────────────────
# Запись: действие (base 2; 1 — запись как есть JSON-строкой), клавиша*2 + есть ли байт флагов (base 1),
# [флаги: биты 0–1 bindIndex, 2 ctrl, 3 alt, 4 shift, 5 cmd, 6 — дальше tapHoldType и characterName (base 1)].

$BindFields = 'alt,bindIndex,characterName,cmd,ctrl,key,name,shift,tapHoldType'

function Write-BindPlain($t, $m) {
    if ((@($m.PSObject.Properties.Name) -join ',') -cne $BindFields) { return $false }
    foreach ($f in 'alt', 'cmd', 'ctrl', 'shift') { if ($m.$f -isnot [bool]) { return $false } }
    foreach ($f in 'characterName', 'key', 'name', 'tapHoldType') { if ($m.$f -isnot [string]) { return $false } }
    if ($m.bindIndex -isnot [int] -or $m.bindIndex -lt 0 -or $m.bindIndex -gt 3) { return $false }
    Add-NameRef $t 'act' $m.name 2
    $tc = $m.tapHoldType -cne 'None' -or $m.characterName -cne 'None'
    $x = $m.bindIndex -bor ([int]$m.ctrl -shl 2) -bor ([int]$m.alt -shl 3) -bor ([int]$m.shift -shl 4) -bor ([int]$m.cmd -shl 5) -bor ([int]$tc -shl 6)
    $kr = Get-NameRef 'key' $m.key 1
    Add-Var $t (($kr * 2) + [int]($x -ne 0)); if (-not $kr) { Add-Str $t $m.key }
    if ($x) { $t.Add([byte]$x) }
    if ($tc) { Add-NameRef $t 'tap' $m.tapHoldType 1; Add-NameRef $t 'chr' $m.characterName 1 }
    $true
}

function Read-CodeBind($r) {
    $ar = Read-Var $r
    if ($ar -eq 1) { return (Read-Str $r | ConvertFrom-Json) }
    $name = Read-NameRef $r 'act' $ar 2
    $kv = Read-Var $r; $key = Read-NameRef $r 'key' ($kv -shr 1) 1
    $x = if ($kv -band 1) { Read-CodeByte $r } else { 0 }
    if ($x -band 128) { throw (Get-CodeBad) }
    $tap = 'None'; $chr = 'None'
    if ($x -band 64) { $tap = Read-NameRef $r 'tap' (Read-Var $r) 1; $chr = Read-NameRef $r 'chr' (Read-Var $r) 1 }
    [pscustomobject][ordered]@{ alt = [bool]($x -band 8); bindIndex = [int]($x -band 3); characterName = $chr; cmd = [bool]($x -band 32)
                                ctrl = [bool]($x -band 4); key = $key; name = $name; shift = [bool]($x -band 16); tapHoldType = $tap }
}

function Add-CodeBinds($b, $prefs) {
    $am = @(@($prefs.actionMappings) | Where-Object { $null -ne $_ })
    Add-Var $b $am.Count
    foreach ($m in $am) {
        $t = New-CodeBuf; $ok = $false
        try {
            if (Write-BindPlain $t $m) { $r = New-CodeReader $t.ToArray(); $ok = (Get-JsonText (Read-CodeBind $r)) -ceq (Get-JsonText $m) -and $r.I -eq $t.Count }
        } catch { $ok = $false }
        if ($ok) { $b.AddRange($t) } else { Add-Var $b 1; Add-Str $b (Get-JsonText $m) }
    }
    $ax = @(@($prefs.axisMappings) | Where-Object { $null -ne $_ -and @($_.PSObject.Properties).Count })   # у владельца пусто; записи — как есть
    Add-Var $b $ax.Count
    foreach ($x in $ax) { Add-Str $b (Get-JsonText $x) }
}

function Read-CodeBinds($r, $prof) {
    $n = Read-Var $r
    $am = @(for ($i = 0; $i -lt $n; $i++) { Read-CodeBind $r })
    $n = Read-Var $r
    $ax = @(for ($i = 0; $i -lt $n; $i++) { Read-Str $r | ConvertFrom-Json })
    $prof | Add-Member -NotePropertyName actionMappings -NotePropertyValue $am -Force
    $prof | Add-Member -NotePropertyName axisMappings -NotePropertyValue $ax -Force
}

# ── Настройки ────────────────────────────────────────────────────────────────
# По группам float, int, bool, string: число записей, записи «имя (base 2) + значение»; у bool значения — битами после имён.
# Имя — без префикса группы; не по форме — settingEnum целиком строкой. Запись не по форме — как есть (имя = 1).

$CodeGroups = @(@('floatSettings', 'f', 'EAresFloatSettingName::'), @('intSettings', 'i', 'EAresIntSettingName::'),
                @('boolSettings', 'b', 'EAresBoolSettingName::'), @('stringSettings', 's', 'EAresStringSettingName::'))

function Add-CodeBits($b, $bits) {
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $x = 0; for ($k = 0; $k -lt 8 -and $i + $k -lt $bits.Count; $k++) { if ($bits[$i + $k]) { $x = $x -bor (1 -shl $k) } }
        $b.Add([byte]$x)
    }
}

function Read-CodeBits($r, [int]$n) {
    $out = New-Object Collections.Generic.List[bool]
    for ($i = 0; $i -lt $n; $i += 8) { $x = Read-CodeByte $r; for ($k = 0; $k -lt 8 -and $i + $k -lt $n; $k++) { $out.Add([bool]($x -band (1 -shl $k))) } }
    , $out
}

# Значение записи группы в $t; $false — не по форме.
function Add-SetValue($t, $g, $e) {
    switch ($g[1]) {
        'b' { return ($e.value -is [bool]) }
        's' { if ($e.value -isnot [string]) { return $false }; Add-Str $t $e.value; return $true }
        default { return (Add-Num $t $e.value) }
    }
}

# Группа картой: все имена из словаря и идут по его порядку (так у облака обычно и есть) — вместо номеров
# битовая карта словаря (байты: число байтов карты, карта), затем значения подряд. $false — не подходит.
function Add-SetGroupMap($b, $g, $list) {
    $vals = New-CodeBuf; $bits = New-Object Collections.Generic.List[bool]; $last = -1; $map = New-Object Collections.Generic.List[bool]
    foreach ($e in $list) {
        if ((@($e.PSObject.Properties.Name) -join ',') -cne 'settingEnum,value' -or $e.settingEnum -isnot [string]) { return $false }
        $en = [string]$e.settingEnum
        if (-not $en.StartsWith($g[2], [StringComparison]::Ordinal)) { return $false }
        $i = Get-NameRef $g[1] $en.Substring($g[2].Length) 1
        if ($i -le $last + 1) { return $false }   # нет в словаре или не по порядку
        while ($map.Count -lt $i - 1) { $map.Add($false) }
        $map.Add($true); $last = $i - 1
        if (-not (Add-SetValue $vals $g $e)) { return $false }
        if ($g[1] -eq 'b') { $bits.Add($e.value) }
    }
    Add-Var $b ($list.Count * 2 + 1)
    Add-Var $b ([Math]::Ceiling($map.Count / 8)); Add-CodeBits $b $map
    $b.AddRange($vals); Add-CodeBits $b $bits
    $true
}

function Add-CodeSettings($b, $prefs) {
    foreach ($g in $CodeGroups) {
        $list = @(@($prefs.($g[0])) | Where-Object { $null -ne $_ })
        if ($list.Count -and (Add-SetGroupMap $b $g $list)) { continue }
        Add-Var $b ($list.Count * 2)
        $bits = New-Object Collections.Generic.List[bool]
        foreach ($e in $list) {
            $t = New-CodeBuf; $ok = $false
            if ((@($e.PSObject.Properties.Name) -join ',') -ceq 'settingEnum,value' -and $e.settingEnum -is [string]) {
                $en = [string]$e.settingEnum
                $ref = if ($en.StartsWith($g[2], [StringComparison]::Ordinal)) { Get-NameRef $g[1] $en.Substring($g[2].Length) 2 } else { 0 }
                Add-Var $t $ref; if (-not $ref) { Add-Str $t $en }
                $ok = Add-SetValue $t $g $e
            }
            if ($ok) { $b.AddRange($t); if ($g[1] -eq 'b') { $bits.Add($e.value) } }
            else { Add-Var $b 1; Add-Str $b (Get-JsonText $e) }
        }
        Add-CodeBits $b $bits
    }
}

function Read-SetValue($r, $g) { switch ($g[1]) { 'b' { $false } 's' { Read-Str $r } default { Read-Num $r } } }

function Read-CodeSettings($r, $prof) {
    foreach ($g in $CodeGroups) {
        $h = Read-Var $r; $n = $h -shr 1
        $list = New-Object Collections.ArrayList; $wait = New-Object Collections.ArrayList
        if ($h -band 1) {   # картой словаря
            $map = Read-CodeBits $r ([int](Read-Var $r) * 8)
            $l = $CodeDicts[$g[1]]
            for ($i = 0; $i -lt $map.Count; $i++) {
                if (-not $map[$i]) { continue }
                if ($i -ge $l.Count) { throw $(if ($r.Ver -gt $CodesVer) { Get-CodeNewer } else { Get-CodeBad }) }
                $e = [pscustomobject][ordered]@{ settingEnum = $g[2] + $l[$i]; value = (Read-SetValue $r $g) }
                [void]$list.Add($e); [void]$wait.Add($e)
            }
            if ($list.Count -ne $n) { throw (Get-CodeBad) }
        } else {
            for ($i = 0; $i -lt $n; $i++) {
                $ref = Read-Var $r
                if ($ref -eq 1) { [void]$list.Add((Read-Str $r | ConvertFrom-Json)); continue }
                $en = if ($ref -eq 0) { Read-Str $r } else { $g[2] + (Read-NameRef $r $g[1] $ref 2) }
                $e = [pscustomobject][ordered]@{ settingEnum = $en; value = (Read-SetValue $r $g) }
                [void]$list.Add($e); [void]$wait.Add($e)
            }
        }
        if ($g[1] -eq 'b') { $bits = Read-CodeBits $r $wait.Count; for ($i = 0; $i -lt $wait.Count; $i++) { $wait[$i].value = $bits[$i] } }
        if ($list.Count) { $prof | Add-Member -NotePropertyName $g[0] -NotePropertyValue @($list) -Force }
    }
}

# ── Прицел ───────────────────────────────────────────────────────────────────
# Отличия от стандартного профиля (Get-XhDelta) листьями: заголовок = путь (base 1; 0 — путь строкой)*8 + вид
# (0 false, 1 true, 2 число, 3 строка, 4 как есть JSON-строкой), дальше значение.

function Get-XhLeaves($d, [string]$pre) {
    $keys = if ($d -is [Collections.IDictionary]) { @($d.Keys) } else { @($d.PSObject.Properties.Name) }
    foreach ($k in $keys) {
        $v = $d.$k; $p = if ($pre) { "$pre.$k" } else { "$k" }
        if ($v -is [Collections.IDictionary]) { Get-XhLeaves $v $p } else { , @($p, $v) }
    }
}

function Add-CodeXh($b, $delta) {
    $leaves = @(Get-XhLeaves $delta '')
    Add-Var $b $leaves.Count
    foreach ($lf in $leaves) {
        $v = $lf[1]; $t = New-CodeBuf
        $ty = if ($v -is [bool]) { [int]$v } elseif ($v -is [string]) { 3 } else { 2 }
        if ($ty -eq 3) { Add-Str $t $v }
        elseif ($ty -eq 2 -and -not (Add-Num $t $v)) { $ty = 4; $t = New-CodeBuf; Add-Str $t (Get-JsonText $v) }
        $pr = Get-NameRef 'xh' $lf[0] 1
        Add-Var $b ($pr * 8 + $ty); if (-not $pr) { Add-Str $b $lf[0] }
        $b.AddRange($t)
    }
}

function Read-CodeXh($r) {
    $root = [pscustomobject]@{}
    $n = Read-Var $r
    for ($i = 0; $i -lt $n; $i++) {
        $h = Read-Var $r; $ty = $h -band 7
        $path = Read-NameRef $r 'xh' ($h -shr 3) 1
        $v = switch ($ty) { 0 { $false } 1 { $true } 2 { Read-Num $r } 3 { Read-Str $r } 4 { Read-Str $r | ConvertFrom-Json } default { throw (Get-CodeBad) } }
        $o = $root; $parts = $path.Split('.')
        for ($k = 0; $k -lt $parts.Count - 1; $k++) {
            if (-not (Test-JsonObj $o.($parts[$k]))) { $o | Add-Member -NotePropertyName $parts[$k] -NotePropertyValue ([pscustomobject]@{}) -Force }
            $o = $o.($parts[$k])
        }
        $o | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $v -Force
    }
    $root
}

# ── Код целиком ──────────────────────────────────────────────────────────────
# Байт 0: формат (старшие 4 бита) = 3 | флаги: 1 — только бинды, 2 — настройки, 4 — прицел, 8 — скины.
# Дальше: версия словарей (varint), разделы с длиной впереди (бинды; настройки; прицел; скины), последний байт — CRC-8.

function Add-CodeSection($b, $sec) { Add-Var $b $sec.Count; if ($sec.Count) { $b.AddRange($sec) } }

function ConvertTo-Code3Bytes([bool]$bindsOnly, $prefs, $xhDelta, [byte[]]$skins) {
    $fl = [int]$bindsOnly -bor $(if (-not $bindsOnly) { 2 } else { 0 }) -bor $(if ($null -ne $xhDelta) { 4 } else { 0 }) -bor $(if ($skins) { 8 } else { 0 })
    $b = New-CodeBuf; $b.Add([byte](($CodeFormat -shl 4) -bor $fl)); Add-Var $b $CodesVer
    $s = New-CodeBuf; Add-CodeBinds $s $prefs; Add-CodeSection $b $s
    if (-not $bindsOnly) { $s = New-CodeBuf; Add-CodeSettings $s $prefs; Add-CodeSection $b $s }
    if ($null -ne $xhDelta) { $s = New-CodeBuf; Add-CodeXh $s $xhDelta; Add-CodeSection $b $s }
    if ($skins) { Add-Var $b $skins.Length; $b.AddRange($skins) }
    $a = $b.ToArray()
    $b.Add([byte](Get-Crc8 $a $a.Length))
    , $b.ToArray()
}

# → @{ BindsOnly; Profile; Xh (отличия прицела или $null); Skins (байты раздела или $null) }
function ConvertFrom-Code3Bytes([byte[]]$a) {
    if ($a.Length -lt 4 -or (Get-Crc8 $a ($a.Length - 1)) -ne $a[-1]) { throw (Get-CodeBad) }
    $f = $a[0] -shr 4; $fl = $a[0] -band 15
    if ($f -ne $CodeFormat) { throw $(if ($f -gt $CodeFormat) { Get-CodeNewer } else { Get-CodeBad }) }
    $r = New-CodeReader $a 1 ($a.Length - 1)
    $r.Ver = Read-Var $r
    $sub = {
        $n = Read-Var $r
        if ($n -gt $r.E - $r.I) { throw (Get-CodeBad) }
        $x = New-CodeReader $a $r.I ($r.I + [int]$n); $x.Ver = $r.Ver; $r.I += [int]$n; $x
    }
    $prof = [pscustomobject]@{}
    Read-CodeBinds (& $sub) $prof
    if ($fl -band 2) { Read-CodeSettings (& $sub) $prof }
    $xh = if ($fl -band 4) { Read-CodeXh (& $sub) }
    $sk = $null
    if ($fl -band 8) { $x = & $sub; $sk = if ($x.E -gt $x.I) { [byte[]]$a[$x.I..($x.E - 1)] } else { [byte[]]@() } }
    @{ BindsOnly = [bool]($fl -band 1); Profile = $prof; Xh = $xh; Skins = $sk }
}

# Текст после «VALSET3:» → разобранный код. Мессенджер мог вставить переносы (а приложение — точки вместо них),
# а за кодом может идти подпись: пробуем все куски подряд, потом всё меньше — пока не сойдётся CRC и разбор.
function Read-Code3Text([string]$body) {
    $tok = @([regex]::Match($body, '^[A-Za-z0-9_\-\s.]*').Value -split '[\s.]+' | Where-Object { $_ })
    for ($k = $tok.Count; $k -ge 1; $k--) {
        try { return (ConvertFrom-Code3Bytes (ConvertFrom-Url64 (-join $tok[0..($k - 1)]))) }
        catch { if ($_.Exception.Message -eq (Get-CodeNewer)) { throw } }
    }
    throw (Get-CodeBad)
}
