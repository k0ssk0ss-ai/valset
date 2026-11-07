# shareskins.ps1 — надетые скины в коде для друга (VALSET3, флаг 8; формат кода — codec.ps1).
# Источник — лоадаут текущего аккаунта (GET, ничего не пишет). Каждый предмет — первые 6 байт его UUID (цвет скина,
# спрей, флекс, карточка, титул), у оружия ещё номер уровня; обратно — по каталогу (skins.ps1). Нет каталога — скины
# не читаются, остальное из кода переносится. Не узнан или узнан неоднозначно — предмет пропускается.
# Не входят: брелоки (форма элемента не измерена), рамка уровня (её нет в каталоге, и она от уровня аккаунта),
# стандартные скины (у друга останутся его скины на этом оружии).
# Раздел: число оружия, [6 байт цвета, уровень]; число слотов, [вид 0 — пропуск, 1 — спрей, 2 — флекс; 6 байт];
# байт: 1 — карточка, 2 — титул; 6 байт каждого.

function ConvertTo-IdPrefix([string]$id) {
    $h = "$id".Replace('-', '')
    if ($h.Length -lt 12 -or $h.Substring(0, 12) -notmatch '^[0-9a-fA-F]{12}$' -or "$id" -eq $ZeroGuid) { return $null }
    , [byte[]]@(for ($i = 0; $i -lt 12; $i += 2) { [Convert]::ToByte($h.Substring($i, 2), 16) })
}

function Get-IdPrefixKey([string]$id) { $p = ConvertTo-IdPrefix $id; if ($p) { ($p | ForEach-Object { $_.ToString('x2') }) -join '' } }

function Read-IdPrefixKey($r) {
    if ($r.I + 6 -gt $r.E) { throw (Get-CodeBad) }
    $k = (@($r.B[$r.I..($r.I + 5)]) | ForEach-Object { $_.ToString('x2') }) -join ''; $r.I += 6; $k
}

# Байты раздела «скины» из лоадаута $lo по каталогу $cat. Уровень и стандартный скин узнаются по каталогу.
function ConvertTo-ShareSkinBytes($lo, $cat) {
    $skins = @{}; foreach ($w in @($cat.weapons)) { foreach ($k in @($w.skins)) { $skins["$($k.id)"] = @($w, $k) } }
    $guns = @(foreach ($g in @($lo.Guns)) {
        $x = $skins["$($g.SkinID)".ToLowerInvariant()]; if (-not $x) { continue }
        $w, $k = $x
        if ($k.id -eq $w.def) { continue }
        $li = [array]::IndexOf(@($k.lv), "$($g.SkinLevelID)".ToLowerInvariant()); if ($li -lt 0) { $li = 0 }
        $ch = if ($g.ChromaID) { "$($g.ChromaID)" } elseif (@($k.ch).Count) { @($k.ch)[0].id } else { '' }
        $p = ConvertTo-IdPrefix $ch; if ($p) { , @($p, [Math]::Min($li, 255)) }
    })
    $b = New-CodeBuf
    Add-Var $b $guns.Count; foreach ($g in $guns) { $b.AddRange($g[0]); $b.Add([byte]$g[1]) }
    $ex = @($lo.ActiveExpressions)
    Add-Var $b $ex.Count
    foreach ($x in $ex) {
        $t = "$($x.TypeID)".ToLowerInvariant(); $p = ConvertTo-IdPrefix $x.AssetID
        $kind = if (-not $p) { 0 } elseif ($t -eq $EntSpray) { 1 } elseif ($t -eq $EntFlex) { 2 } else { 0 }
        $b.Add([byte]$kind); if ($kind) { $b.AddRange($p) }
    }
    $card = ConvertTo-IdPrefix $lo.Identity.PlayerCardID; $title = ConvertTo-IdPrefix $lo.Identity.PlayerTitleID
    $b.Add([byte]([int][bool]$card -bor (2 * [int][bool]$title)))
    if ($card) { $b.AddRange($card) }; if ($title) { $b.AddRange($title) }
    , $b.ToArray()
}

# `do share:skins` — надетое сейчас на текущем аккаунте.
function Get-ShareSkinBytes($s) { ConvertTo-ShareSkinBytes (Get-Loadout $s) (Get-SkinCatalog) }

# Байты раздела → @{ Guns = [@{P; L}]; Expr = [@{K; P}]; Card; Title } (P — 12 hex-знаков начала UUID).
function Read-ShareSkins([byte[]]$a) {
    $r = New-CodeReader $a
    $n = Read-Var $r
    $guns = @(for ($i = 0; $i -lt $n; $i++) { $p = Read-IdPrefixKey $r; @{ P = $p; L = (Read-CodeByte $r) } })
    $n = Read-Var $r
    $ex = @(for ($i = 0; $i -lt $n; $i++) { $k = Read-CodeByte $r; @{ K = $k; P = $(if ($k) { Read-IdPrefixKey $r }) } })
    $f = Read-CodeByte $r
    $card = if ($f -band 1) { Read-IdPrefixKey $r }; $title = if ($f -band 2) { Read-IdPrefixKey $r }
    @{ Guns = $guns; Expr = $ex; Card = $card; Title = $title }
}

# Таблица «начало UUID → предмет»; два предмета с одним началом — 'dup' (такой не надеваем).
function Add-PrefixItem($t, [string]$id, $v) {
    $k = Get-IdPrefixKey $id; if (-not $k) { return }
    if ($t.ContainsKey($k)) { $t[$k] = 'dup' } else { $t[$k] = $v }
}

function Find-PrefixItem($t, $k) { $v = if ($k) { $t[$k] }; if ($v -and $v -isnot [string]) { $v } }

# Скины из кода на текущий аккаунт: только то, что у него есть. → @{ Cur; New; N; M; Note; Pics }.
function Get-ShareSkinPlan($s, [byte[]]$a, $cat = $null) {
    $raw = Read-ShareSkins $a
    if (-not $cat) { $cat = Get-SkinCatalog }
    $chT = @{}; $spT = @{}; $flT = @{}; $cdT = @{}; $tiT = @{}
    foreach ($w in @($cat.weapons)) { foreach ($k in @($w.skins)) { $i = 0; foreach ($c in @($k.ch)) { Add-PrefixItem $chT $c.id @{ W = $w; K = $k; C = $c; I = $i }; $i++ } } }
    foreach ($x in @($cat.sprays)) { Add-PrefixItem $spT $x.id $x }
    foreach ($x in @($cat.flex)) { Add-PrefixItem $flT $x.id $x }
    foreach ($x in @($cat.cards)) { Add-PrefixItem $cdT $x.id $x }
    foreach ($x in @($cat.titles)) { Add-PrefixItem $tiT $x.id $x }
    $cur = Get-Loadout $s; $own = Get-OwnedItems $s
    $m = 0; $n = 0
    $guns = @(foreach ($g in $raw.Guns) {
        $m++; $x = Find-PrefixItem $chT $g.P; if (-not $x) { continue }
        $lv = @($x.K.lv); if (-not $lv.Count) { continue }
        $l = $lv[[Math]::Min([int]$g.L, $lv.Count - 1)]
        if (($x.K.id -eq $x.W.def -or $own.Contains($l)) -and ($x.I -eq 0 -or $own.Contains($x.C.id))) {
            $n++; [ordered]@{ ID = $x.W.id; SkinID = $x.K.id; SkinLevelID = $l; ChromaID = $x.C.id }
        }
    })
    $curEx = @($cur.ActiveExpressions); $changed = $false; $mine = New-Object Collections.ArrayList
    $ex = @(foreach ($x in $curEx) { [ordered]@{ TypeID = "$($x.TypeID)"; AssetID = "$($x.AssetID)" } })
    for ($i = 0; $i -lt $raw.Expr.Count; $i++) {
        $e = $raw.Expr[$i]; if (-not $e.K) { continue }
        $m++
        $x = Find-PrefixItem $(if ($e.K -eq 1) { $spT } else { $flT }) $e.P
        if ($x -and $i -lt $ex.Count -and $own.Contains($x.id)) { $ex[$i] = [ordered]@{ TypeID = $(if ($e.K -eq 1) { $EntSpray } else { $EntFlex }); AssetID = $x.id }; [void]$mine.Add($ex[$i]); $n++; $changed = $true }
    }
    $id = [ordered]@{ PlayerCardID = ''; PlayerTitleID = ''; PreferredLevelBorderID = '' }
    foreach ($q in @(@('Card', $cdT, 'PlayerCardID'), @('Title', $tiT, 'PlayerTitleID'))) {
        if (-not $raw[$q[0]]) { continue }
        $m++; $x = Find-PrefixItem $q[1] $raw[$q[0]]
        if ($x -and $own.Contains($x.id)) { $id[$q[2]] = $x.id; $n++ }
    }
    $set = [ordered]@{ guns = $guns; expressions = $(if ($changed) { $ex } else { @() }); identity = $id }
    $note = if ($n -lt $m) { L "Скины из кода: $n из $m у тебя есть, надену только их" "Skins from the code: you own $n of $m, only those go on" } else { L "Скины из кода: все $m у тебя есть" "Skins from the code: you own all $m" }
    @{ Cur = $cur; New = (Join-SetLoadout $cur $set); N = $n; M = $m; Note = $note
       Pics = @(Get-SetPics ([ordered]@{ guns = $guns; expressions = @($mine); identity = $id }) $cat) }
}

# Последнюю точку отмены (настройки из кода) дополнить прежним лоадаутом: «Отменить» вернёт и то и другое (do.ps1).
function Add-UndoLoadout([string]$puuid, $lo) {
    if (-not (Test-Path $LastActionPath)) { return }
    $a = Get-Content $LastActionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $a | Add-Member -NotePropertyName loadout -NotePropertyValue ([ordered]@{ puuid = $puuid; loadout = (ConvertTo-Json -InputObject $lo -Depth 10 -Compress) }) -Force
    Write-FileSafe $LastActionPath (ConvertTo-Json -InputObject $a -Depth 6 -Compress)
}
