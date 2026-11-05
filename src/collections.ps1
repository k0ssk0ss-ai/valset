# collections.ps1 — «Все скины» → «Коллекции»: скины по коллекциям (valorant-api: themeUuid скина → /v1/themes).
# Свои скины коллекции — ярко, чужие — для справки (надеть нельзя). Предпросмотр коллекции: картинки оружия
# и его цветов (картинки качает приложение — Img.cs).
# «Надеть коллекцию» — свои скины коллекции на их оружие: предпросмотр «было → станет», бэкап, отмена (sets.ps1).
# «Сохранить как набор» — набор только из оружия коллекции (остальное при надевании не меняется).
# Картинки набора в предпросмотре «Надеть набор» — Get-SetPics.

$ThemeRandom = '0d7a5bfb-4850-098e-1821-d989bbfd58a8'   # «Random Favorite Skin» — не коллекция

function Test-Guid([string]$t) { $t -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }

# Оружие в порядке игры (пистолеты → ножи), внутри — по имени.
function Get-SortedWeapons($cat) {
    @($cat.weapons) | Sort-Object { $i = [array]::IndexOf($WeaponOrder, "$($_.cat)"); if ($i -lt 0) { 99 } else { $i } }, { "$($_.name)" }
}

# Коллекции каталога по порядку: [{ id, name, items: [{ w, k }] }]. Без «Стандартных» (тема стандартных скинов)
# и «случайного скина». Оружие внутри — в порядке игры.
function Get-CatalogThemes($cat) {
    $names = @{}; $icons = @{}; foreach ($t in @($cat.themes)) { $names["$($t.id)"] = "$($t.name)"; $icons["$($t.id)"] = "$($t.icon)" }
    $skip = @{ $ThemeRandom = $true }
    foreach ($w in @($cat.weapons)) { foreach ($k in @($w.skins)) { if ($k.id -eq $w.def -and $k.th) { $skip["$($k.th)"] = $true } } }
    $by = [ordered]@{}
    foreach ($w in Get-SortedWeapons $cat) {
        foreach ($k in @($w.skins)) {
            $t = "$($k.th)"
            if (-not $t -or $skip[$t]) { continue }
            if (-not $by.Contains($t)) { $by[$t] = [ordered]@{ id = $t; name = $(if ($names[$t]) { $names[$t] } else { "$($k.name)" }); bn = $icons[$t]; items = New-Object Collections.ArrayList } }
            [void]$by[$t].items.Add([pscustomobject]@{ w = $w; k = $k })
        }
    }
    @($by.Values)
}

function Find-CatalogTheme($cat, [string]$id) {
    if (-not (Test-Guid $id)) { throw (L 'Некорректная коллекция.' 'Invalid collection.') }
    $t = Get-CatalogThemes $cat | Where-Object { $_.id -eq $id.ToLowerInvariant() } | Select-Object -First 1
    if (-not $t) { throw (L 'Такой коллекции нет в каталоге — обнови список.' 'No such collection in the catalog — refresh the list.') }
    $t
}

# Есть ли скин на аккаунте: хоть один его уровень.
function Test-SkinOwned($k, $own) { foreach ($l in @($k.lv)) { if ($own.Contains($l)) { return $true } }; $false }

# `valset list collections`: первый элемент — аккаунт; дальше коллекции { id, name, n, own, items: [{ i — картинка, o — своё }] }.
# Сначала те, где есть свои скины (больше своих — выше), потом остальные по имени (для поиска).
function Get-ListCollections {
    try {
        $s = Connect-Session
        $cat = Get-SkinCatalog; $own = Get-OwnedItems $s
        $out = foreach ($t in Get-CatalogThemes $cat) {
            $n = 0
            $items = @(foreach ($x in $t.items) { $o = Test-SkinOwned $x.k $own; if ($o) { $n++ }; [ordered]@{ i = "$($x.k.icon)"; o = $o } })
            [ordered]@{ id = $t.id; name = $t.name; n = $items.Count; own = $n; items = $items; bn = "$($t.bn)" }
        }
        $out = @($out | Sort-Object @{ Expression = { [int]($_.own -gt 0) }; Descending = $true }, @{ Expression = { $_.own }; Descending = $true }, @{ Expression = { $_.name } })
        , (@([ordered]@{ info = ''; account = (Get-AccountLabel $s.Puuid) }) + $out)
    } catch { , @([ordered]@{ error = $_.Exception.Message }) }
}

# Что надеть из коллекции: свои скины на оружие из лоадаута. Уже надетый скин коллекции — как есть (свой цвет и
# уровень); иначе — старший свой уровень и, если он последний, старший свой цвет (цвета открываются на последнем уровне).
function Get-CollGuns($t, $lo, $own) {
    $guns = @{}; foreach ($g in @($lo.Guns)) { $guns["$($g.ID)".ToLowerInvariant()] = $g }
    @(foreach ($x in $t.items) {
        $g = $guns[$x.w.id]; if (-not $g) { continue }
        $o = ConvertTo-OwnedSkin $x.w $x.k $own $g
        if (-not $o -or $o.def -or -not @($o.lv).Count -or -not @($o.ch).Count) { continue }
        if ($o.on) { [ordered]@{ ID = "$($g.ID)"; SkinID = "$($g.SkinID)"; SkinLevelID = "$($g.SkinLevelID)"; ChromaID = "$($g.ChromaID)" }; continue }
        $top = @($o.lv)[-1]
        $ch = if ($top.n -eq @($x.k.lv).Count) { @($o.ch)[-1] } else { @($o.ch)[0] }
        [ordered]@{ ID = "$($g.ID)"; SkinID = $x.k.id; SkinLevelID = $top.id; ChromaID = $ch.id }
    })
}

# `valset list collection:<id>`: первый элемент — коллекция и аккаунт; дальше скины { w, wn, id, name, icon, own, on, gun,
# lv: [{ n, own }], ch: [{ id, name, icon, own }] }.
function Get-ListCollection([string]$id) {
    try {
        $s = Connect-Session
        $cat = Get-SkinCatalog; $t = Find-CatalogTheme $cat $id
        $lo = Get-Loadout $s; $own = Get-OwnedItems $s
        $guns = @{}; foreach ($g in @($lo.Guns)) { $guns["$($g.ID)".ToLowerInvariant()] = $g }
        $n = 0
        $rows = @(foreach ($x in $t.items) {
            $k = $x.k; $g = $guns[$x.w.id]
            $o = ConvertTo-OwnedSkin $x.w $k $own $g
            $mine = [bool]$o; if ($mine) { $n++ }
            $ol = @{}; $oc = @{}
            if ($o) { foreach ($l in @($o.lv)) { $ol[$l.id] = $true }; foreach ($c in @($o.ch)) { $oc[$c.id] = $true } }
            $i = 0
            [ordered]@{ w = $x.w.id; wn = "$($x.w.name)"; id = $k.id; name = "$($k.name)"; icon = "$($k.icon)"; own = $mine; on = [bool]($o -and $o.on); gun = [bool]$g
                lv = @(foreach ($l in @($k.lv)) { [ordered]@{ n = $i + 1; own = [bool]$ol[$l] }; $i++ })
                ch = @(foreach ($c in @($k.ch)) { [ordered]@{ id = $c.id; name = "$($c.name)"; icon = "$($c.icon)"; own = [bool]$oc[$c.id] } }) }
        })
        $put = @(Get-CollGuns $t $lo $own).Count
        , (@([ordered]@{ info = ''; account = (Get-AccountLabel $s.Puuid); name = $t.name; n = $rows.Count; own = $n; put = $put; bn = "$($t.bn)" }) + $rows)
    } catch { , @([ordered]@{ error = $_.Exception.Message }) }
}

# Новый лоадаут с коллекцией: текущий + свои скины коллекции (Join-SetLoadout — как набор только из оружия).
function Join-CollLoadout($cur, $guns) { Join-SetLoadout $cur ([ordered]@{ guns = @($guns) }) }

function Get-CollChange([string]$id) {
    $s = Connect-Session
    $cat = Get-SkinCatalog; $t = Find-CatalogTheme $cat $id
    $cur = Get-Loadout $s
    $guns = @(Get-CollGuns $t $cur (Get-OwnedItems $s))
    if (-not $guns.Count) { throw (L "Из коллекции «$($t.name)» на аккаунте ничего нет — надеть нечего." "Nothing from the `“$($t.name)`” collection on this account — nothing to put on.") }
    [pscustomobject]@{ s = $s; t = $t; cat = $cat; cur = $cur; guns = $guns }
}

# `valset list coll:<id>`: предпросмотр «было → станет» с картинками того, что наденется.
function Get-ListCollPreview([string]$id) {
    try {
        $c = Get-CollChange $id
        $rows = Compare-Loadout $c.cur (Join-CollLoadout $c.cur $c.guns) (Get-CosmeticNames)
        $info = "$(L 'Коллекция' 'Collection') «$($c.t.name)»: $(L 'своих скинов' 'own skins') $($c.guns.Count)"
        @([ordered]@{ info = $info; account = (Get-AccountLabel $c.s.Puuid); same = (-not $rows.Count); pics = @(Get-SetPics ([ordered]@{ guns = $c.guns }) $c.cat) }) + @($rows)
    } catch { @([ordered]@{ error = $_.Exception.Message }) }
}

# `valset do coll:<id>`: бэкап, точка отмены, запись (Write-LoadoutChange, sets.ps1).
function Invoke-CollApply([string]$id) {
    $c = Get-CollChange $id
    $n = (Write-LoadoutChange $c.s $c.cur (Join-CollLoadout $c.cur $c.guns) "коллекция «$($c.t.name)»").Count
    if (-not $n) { return (L "Коллекция «$($c.t.name)» уже надета" "Collection `“$($c.t.name)`” is already on") }
    L "Коллекция «$($c.t.name)» надета: $n $(Get-Plural $n 'изменение' 'изменения' 'изменений')" "Collection `“$($c.t.name)`” on: $n change$(if ($n -ne 1) { 's' })"
}

# Набор из коллекции (Invoke-SetSave): только оружие коллекции; спреи, карточка и титул — пустые (не меняются).
function Get-CollSetItems($s, [string]$id) {
    $c = Get-CollChange $id
    [ordered]@{ guns = $c.guns; expressions = @(); identity = [ordered]@{ PlayerCardID = ''; PlayerTitleID = ''; PreferredLevelBorderID = '' } }
}

# Картинки набора: скины (цвет или сам скин; стандартные — нет), карточка, спреи и флексы. [{ i, n, t: gun|card|expr }]
function Get-SetPics($set, $cat = $null) {
    if (-not $cat) { $cat = Get-SkinCatalog }
    $ic = @{}; $nm = @{}; $def = @{}
    foreach ($w in @($cat.weapons)) {
        $def[$w.def] = $true
        foreach ($k in @($w.skins)) { $ic[$k.id] = "$($k.icon)"; $nm[$k.id] = "$($k.name)"; foreach ($c in @($k.ch)) { if ($c.icon) { $ic[$c.id] = "$($c.icon)" } } }
    }
    foreach ($x in @($cat.cards) + @($cat.sprays) + @($cat.flex)) { $ic[$x.id] = "$($x.icon)"; $nm[$x.id] = "$($x.name)" }
    $pic = { param($id, $from, $t) $id = "$id".ToLowerInvariant(); if ($ic[$id] -or $ic[$from]) { [ordered]@{ i = $(if ($ic[$id]) { $ic[$id] } else { $ic[$from] }); n = "$($nm[$from])"; t = $t } } }
    @(
        foreach ($g in @($set.guns)) { $k = "$($g.SkinID)".ToLowerInvariant(); if ($k -and -not $def[$k]) { & $pic $g.ChromaID $k 'gun' } }
        $card = "$($set.identity.PlayerCardID)".ToLowerInvariant(); if ($card) { & $pic $card $card 'card' }
        foreach ($x in @($set.expressions)) { $a = "$($x.AssetID)".ToLowerInvariant(); if ($a -and $a -ne $ZeroGuid) { & $pic $a $a 'expr' } }
        foreach ($x in @($set.sprays)) { $a = "$($x.SprayID)".ToLowerInvariant(); if ($a) { & $pic $a $a 'expr' } }
    )
}
