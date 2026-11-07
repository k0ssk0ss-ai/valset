# codec.ps1 — двоичный формат кода VALSET3 (share.ps1): байты ↔ base64url, целые varint, числа, имена по словарям
# (codes.ps1); разделы кода — codeparts.ps1. Без сети и файлов. Раскладка байтов — NOTES.md «Код VALSET3».
# Точность: каждое значение после упаковки распаковывается и сравнивается с исходным JSON; не совпало — пишется
# как есть, JSON-строкой. Поэтому код всегда без потерь, а короткие формы — только там, где они точны.

$CodeFormat = 3

function Get-CodeBad { L 'Код повреждён: скопирован не полностью?' 'The code is damaged: copied only partly?' }
function Get-CodeNewer { L 'Код от более новой версии VALSET, обнови приложение.' 'The code is from a newer VALSET. Update the app.' }

# ── Байты ────────────────────────────────────────────────────────────────────

function New-CodeBuf { , (New-Object 'Collections.Generic.List[byte]') }

function Add-Var($b, [long]$v) {
    if ($v -lt 0) { throw 'varint < 0' }
    do { $x = $v -band 0x7F; $v = $v -shr 7; if ($v) { $x = $x -bor 0x80 }; $b.Add([byte]$x) } while ($v)
}

function Get-Zz([long]$n) { ($n -shl 1) -bxor ($n -shr 63) }
function Get-UnZz([long]$z) { ($z -shr 1) -bxor (-($z -band 1)) }

function Add-Str($b, [string]$s) { $x = [Text.Encoding]::UTF8.GetBytes($s); Add-Var $b $x.Length; if ($x.Length) { $b.AddRange($x) } }

# Читатель: B — байты, I — позиция, E — конец, Ver — версия словарей кода.
function New-CodeReader([byte[]]$bytes, [int]$start = 0, [int]$end = -1) {
    @{ B = $bytes; I = $start; E = $(if ($end -lt 0) { $bytes.Length } else { $end }); Ver = $CodesVer }
}

function Read-CodeByte($r) { if ($r.I -ge $r.E) { throw (Get-CodeBad) }; $x = $r.B[$r.I]; $r.I++; [int]$x }

function Read-Var($r) {
    [long]$v = 0; $sh = 0
    do {
        if ($sh -gt 56) { throw (Get-CodeBad) }
        $x = Read-CodeByte $r; $v = $v -bor (([long]($x -band 0x7F)) -shl $sh); $sh += 7
    } while ($x -band 0x80)
    $v
}

function Read-Str($r) {
    $n = Read-Var $r
    if ($n -gt $r.E - $r.I) { throw (Get-CodeBad) }
    $s = [Text.Encoding]::UTF8.GetString($r.B, $r.I, [int]$n); $r.I += [int]$n; $s
}

function ConvertTo-Url64([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

function ConvertFrom-Url64([string]$t) {
    if ($t -notmatch '^[A-Za-z0-9_-]+$' -or $t.Length % 4 -eq 1) { throw (Get-CodeBad) }
    $t = $t.Replace('-', '+').Replace('_', '/'); $t += '=' * ((4 - $t.Length % 4) % 4)
    , [Convert]::FromBase64String($t)
}

# CRC-8 (многочлен 0x07): ловит обрезанный код и опечатку.
function Get-Crc8([byte[]]$b, [int]$n) {
    $c = 0
    for ($i = 0; $i -lt $n; $i++) {
        $c = $c -bxor $b[$i]
        for ($k = 0; $k -lt 8; $k++) { $c = if ($c -band 0x80) { (($c -shl 1) -bxor 0x07) -band 0xFF } else { ($c -shl 1) -band 0xFF } }
    }
    $c
}

# ── Имена по словарям ────────────────────────────────────────────────────────
# Номер в коде = место в словаре + base; 0 — дальше само имя строкой (нет в словаре). base 2 оставляет 1 под «запись как есть».

function Get-NameRef([string]$k, [string]$name, [int]$base) { $i = 0; if ((Get-CodeIndex $k).TryGetValue($name, [ref]$i)) { $i + $base } else { 0 } }

function Add-NameRef($b, [string]$k, [string]$name, [int]$base) {
    $ref = Get-NameRef $k $name $base
    Add-Var $b $ref; if (-not $ref) { Add-Str $b $name }
}

function Read-NameRef($r, [string]$k, [long]$ref, [int]$base) {
    if ($ref -eq 0) { return (Read-Str $r) }
    $i = $ref - $base; $l = $CodeDicts[$k]
    if ($i -lt 0 -or $i -ge $l.Count) { throw $(if ($r.Ver -gt $CodesVer) { Get-CodeNewer } else { Get-CodeBad }) }
    $l[[int]$i]
}

# ── Числа ────────────────────────────────────────────────────────────────────
# Заголовок varint = данные*4 + вид. Виды: 0 — целое (зигзаг); 1 — float32 из короткой десятичной m·10^-e;
# 2 — float32 четырьмя байтами; 3 — точная десятичная (знак, порядок, мантисса). У 1 и 2 после — поправка C:
# облако печатает float32 по-разному (0.699999988079071, 0.23749999701976777), поэтому от печати G17 хранится
# разница: C = зигзаг(k)*32 + зигзаг(ds) — другой порядок (ds) и сдвиг последней цифры (k). Обычно C — один байт.

$Inv3 = [Globalization.CultureInfo]::InvariantCulture
$P32 = [decimal]4294967296

function Get-JsonText($v) { ConvertTo-Json -InputObject $v -Compress -Depth 20 }

# decimal → мантисса со знаком (целое decimal) и порядок.
function Get-DecParts([decimal]$d) {
    $g = [decimal]::GetBits($d)
    $u = { param($x) [decimal]([long]$x -band [long]4294967295) }
    $m = (& $u $g[2]) * $P32 * $P32 + (& $u $g[1]) * $P32 + (& $u $g[0])
    if ($g[3] -lt 0) { $m = -$m }
    $m, (($g[3] -shr 16) -band 0xFF)
}

function New-Dec([decimal]$m, [int]$s) {
    if ($s -lt 0 -or $s -gt 28) { throw (Get-CodeBad) }
    $a = [Math]::Abs($m)
    $w = { param($x) $l = [long]$x; if ($l -ge 2147483648) { $l -= 4294967296 }; [int]$l }
    $lo = & $w ($a % $P32); $a = [decimal]::Truncate($a / $P32); $mid = & $w ($a % $P32); $hi = & $w ([decimal]::Truncate($a / $P32))
    New-Object decimal($lo, $mid, $hi, ($m -lt 0), [byte]$s)
}

function Get-Pow10([int]$n) { [decimal]::Parse('1' + ('0' * $n), $Inv3) }

# Мантисса печати G17 числа $f, приведённая к порядку $so.
function Get-G17At([single]$f, [int]$so) {
    $mt, $st = Get-DecParts ([decimal]::Parse(([double]$f).ToString('G17', $Inv3), [Globalization.NumberStyles]::Float, $Inv3))
    $m = if ($so -ge $st) { $mt * (Get-Pow10 ($so - $st)) } else { [decimal]::Truncate($mt / (Get-Pow10 ($st - $so))) }
    $m, $st
}

function Read-Num($r) {
    $h = Read-Var $r; $mode = $h -band 3; $p = $h -shr 2
    if ($mode -eq 0) { $n = Get-UnZz $p; if ($n -ge [int]::MinValue -and $n -le [int]::MaxValue) { return [int]$n }; return $n }
    if ($mode -eq 3) { return (New-Dec ([decimal](Read-Var $r) * $(if ($p -band 1) { -1 } else { 1 })) ($p -shr 1)) }
    if ($mode -eq 1) { $e = $p -band 7; $f = [single]([double](Get-UnZz ($p -shr 3)) / [Math]::Pow(10, $e)) }
    else { if ($r.I + 4 -gt $r.E) { throw (Get-CodeBad) }; $f = [BitConverter]::ToSingle($r.B, $r.I); $r.I += 4 }
    $c = Read-Var $r
    $ds = Get-UnZz ($c -band 31); $k = Get-UnZz ($c -shr 5)
    $st = (Get-DecParts ([decimal]::Parse(([double]$f).ToString('G17', $Inv3), [Globalization.NumberStyles]::Float, $Inv3)))[1]
    $so = $st + $ds
    $mt = (Get-G17At $f $so)[0]
    New-Dec ($mt + $k) $so
}

# Поправка C к печати G17 числа $f, чтобы вышло $od; $null — не выразить.
function Get-NumFix([single]$f, [decimal]$od) {
    try {
        $mo, $so = Get-DecParts $od
        $mt, $st = Get-G17At $f $so
        $ds = $so - $st; $k = $mo - $mt
        if ($ds -lt -16 -or $ds -gt 15 -or [Math]::Abs($k) -gt [decimal]1e15) { return $null }
        (Get-Zz ([long]$k)) * 32 + (Get-Zz $ds)
    } catch { $null }
}

# Число в $b самой короткой точной формой. $false — не число или не выразить (пишется как есть).
function Add-Num($b, $v) {
    if ($null -eq $v -or $v -is [bool] -or $v -is [string]) { return $false }
    $txt = Get-JsonText $v
    $cands = New-Object Collections.ArrayList
    $add = { param($bytes) [void]$cands.Add($bytes) }
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) {
        if ([Math]::Abs([long]$v) -lt [long]1e17) { $t = New-CodeBuf; Add-Var $t ((Get-Zz ([long]$v)) * 4); & $add $t }
    } elseif ($v -is [decimal] -or $v -is [double] -or $v -is [single]) {
        $od = $null
        try { $od = [decimal]::Parse($txt, [Globalization.NumberStyles]::Float, $Inv3) } catch {}
        if ($null -ne $od) {
            if ($txt -match '^-?\d+$' -and [Math]::Abs($od) -lt [decimal]1e17) { $t = New-CodeBuf; Add-Var $t ((Get-Zz ([long]$od)) * 4); & $add $t }
            $f = [single][double]$od
            if (-not [single]::IsInfinity($f) -and -not [single]::IsNaN($f)) {
                $c = Get-NumFix $f $od
                if ($null -ne $c) {
                    for ($e = 0; $e -le 7; $e++) {
                        $sc = [Math]::Pow(10, $e); $m = [Math]::Round([double]$od * $sc)
                        if ([Math]::Abs($m) -lt 1e12 -and [single]($m / $sc) -eq $f) {
                            $t = New-CodeBuf; Add-Var $t (((Get-Zz ([long]$m)) * 8 + $e) * 4 + 1); Add-Var $t $c; & $add $t; break
                        }
                    }
                    $t = New-CodeBuf; Add-Var $t 2; $t.AddRange([BitConverter]::GetBytes($f)); Add-Var $t $c; & $add $t
                }
            }
            $mo, $so = Get-DecParts $od
            if ([Math]::Abs($mo) -lt [decimal]9e18) { $t = New-CodeBuf; Add-Var $t (($so * 2 + [int]($mo -lt 0)) * 4 + 3); Add-Var $t ([long][Math]::Abs($mo)); & $add $t }
        }
    }
    foreach ($t in @($cands | Sort-Object { $_.Count })) {
        try {
            $r = New-CodeReader $t.ToArray()
            if ((Get-JsonText (Read-Num $r)) -ceq $txt -and $r.I -eq $t.Count) { $b.AddRange($t); return $true }
        } catch {}
    }
    $false
}
