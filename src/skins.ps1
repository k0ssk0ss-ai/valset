# skins.ps1 — «Все скины»: предметы, которые есть на аккаунте (скины оружия с цветами и уровнями, брелоки, спреи,
# флексы, карточки, титулы), с картинками; выбранное — в текущий лоадаут (предпросмотр → бэкап, запись, отмена — sets.ps1).
# Каталог — valorant-api.com (/weapons, /buddies, /sprays, /flex, /playercards, /playertitles) на языке интерфейса,
# кэш cache\catalog-<язык>.json. Обновляется, когда меняется версия игры (ShooterGame.log, «CI server version»),
# а не по таймеру: версия игры = версии в кэше — сеть не нужна; иначе GET /v1/version, качаем, только если там новее.
# Владение — GET https://pd.{shard}.a.pvp.net/store/v1/entitlements/{puuid} (все типы одним запросом, ItemTypeID ниже).
# Картинки качает и кэширует приложение (Img.cs), здесь — только адреса media.valorant-api.com.

$CatalogVer = 3   # 3: коллекции (th, themes — collections.ps1); у стандартных скинов — картинка оружия
$EntSkinLevel = 'e7c63390-eda7-46e0-bb7a-a6abdacd2433'   # уровни скинов (ItemID — uuid уровня)
$EntChroma = '3ad1b2b2-acdb-4524-852f-954a76ddae0a'      # цвета (базовый цвет не выдаётся — он есть у каждого скина)
$EntBuddy = 'dd3bf334-87f3-40bd-b043-682a57a8dc3a'       # брелоки (ItemID — uuid уровня брелока, у каждого экземпляра свой InstanceID)
$EntSpray = 'd5f120f8-ff8c-4aac-92ea-f2b5acbe9475'
$EntCard = '3f296c07-64c3-494c-923b-fe692a4fa1bd'
$EntTitle = 'de7caa6b-adf7-4588-bbd1-143831e786c6'
$EntFlex = '03a572de-4234-31ed-d344-ababa488f981'
$WeaponOrder = 'Sidearm', 'SMG', 'Shotgun', 'Rifle', 'Sniper', 'Heavy', 'Melee'

# ── Каталог ──────────────────────────────────────────────────────────────────

function Get-GameVersion {
    if (-not (Test-Path $GameLog)) { return '' }
    $v = Select-String -Path $GameLog -Pattern 'CI server version: (release-[\w.\-]+)' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($v) { $v.Matches[0].Groups[1].Value } else { '' }
}

# Подпись цвета: «Odin "Комета"\n(расцветка 1 "Красный")» → «расцветка 1 "Красный"»; базовый — «обычный».
function Get-ChromaLabel([string]$name, [int]$i) {
    if ($i -eq 0) { return (L 'обычный' 'base') }
    $m = [regex]::Match($name, '\(([^()]+)\)\s*$')
    if ($m.Success) { $m.Groups[1].Value.Trim() } else { ($name -replace '\s*[\r\n]+\s*', ' ').Trim() }
}

function Get-CatalogFromApi([string]$lang) {
    $q = "?language=$(if ($lang -eq 'en') { 'en-US' } else { 'ru-RU' })"
    $get = { param($p) (Invoke-RestMethod "$ValApi/$p$q" -TimeoutSec 60).data }
    $weapons = @(foreach ($w in & $get 'weapons') {
        $cat = "$($w.category)" -replace '^.*::', ''
        [ordered]@{ id = "$($w.uuid)".ToLowerInvariant(); name = "$($w.displayName)"; cat = $cat; def = "$($w.defaultSkinUuid)".ToLowerInvariant()
            skins = @(foreach ($k in @($w.skins)) { if ($k.uuid -and @($k.levels).Count) {
                $ch = @($k.chromas); $i = 0
                $def = "$($k.uuid)" -eq "$($w.defaultSkinUuid)"   # у стандартного скина вместо картинки — «X», берём картинку оружия
                $icon = @($(if ($def) { $w.displayIcon }), $k.displayIcon, $(if ($ch.Count) { $ch[0].displayIcon }), @($k.levels)[0].displayIcon) | Where-Object { $_ } | Select-Object -First 1
                [ordered]@{ id = "$($k.uuid)".ToLowerInvariant(); name = ("$($k.displayName)" -replace '\s*[\r\n]+\s*', ' ').Trim(); icon = "$icon"; th = "$($k.themeUuid)".ToLowerInvariant()
                    lv = @(foreach ($l in @($k.levels)) { "$($l.uuid)".ToLowerInvariant() })   # по порядку: номер уровня = место в списке
                    ch = @(foreach ($c in $ch) { [ordered]@{ id = "$($c.uuid)".ToLowerInvariant(); name = (Get-ChromaLabel "$($c.displayName)" ($i++)); icon = "$(if ($def) { $w.displayIcon } elseif ($c.displayIcon) { $c.displayIcon } else { $c.fullRender })"; sw = "$($c.swatch)" } }) } } }) }
    })
    $flat = { param($list, $nameOf, $iconOf) @(foreach ($x in $list) { if ($x.uuid) { [ordered]@{ id = "$($x.uuid)".ToLowerInvariant(); name = "$(& $nameOf $x)"; icon = "$(& $iconOf $x)" } } }) }
    [ordered]@{
        v = $CatalogVer; lang = $lang; at = (Get-Stamp); weapons = $weapons
        buddies = @(foreach ($b in & $get 'buddies') { $l = @($b.levels)[0]; if ($l.uuid) { [ordered]@{ id = "$($l.uuid)".ToLowerInvariant(); name = "$($b.displayName)"; icon = "$($b.displayIcon)" } } })
        sprays = & $flat (& $get 'sprays') { param($x) $x.displayName } { param($x) $x.displayIcon }
        flex = & $flat (& $get 'flex') { param($x) $x.displayName } { param($x) $x.displayIcon }
        cards = & $flat (& $get 'playercards') { param($x) $x.displayName } { param($x) $x.smallArt }
        themes = & $flat (& $get 'themes') { param($x) $x.displayName } { param($x) '' }
        titles = & $flat (& $get 'playertitles') { param($x) if ($x.titleText) { $x.titleText } else { $x.displayName } } { param($x) '' }
    }
}

# Каталог: кэш той же версии игры → кэш, если valorant-api ещё не обновился → скачать → старый кэш → ошибка.
# В памяти не держим (несколько МБ): нужен только при открытии страницы. Проверку версии — один раз на версию игры.
function Get-SkinCatalog {
    $lang = $script:Lang; $path = Join-Path $Root "cache\catalog-$lang.json"
    $gv = Get-GameVersion
    $raw = $null
    if (Test-Path $path) { try { $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    $ok = $raw -and $raw.v -eq $CatalogVer -and $raw.lang -eq $lang
    if ($ok -and $gv -and ("$($raw.gameVer)" -eq $gv -or "$($raw.apiVer)" -eq $gv)) { return $raw }
    if ($ok -and $script:CatalogChecked -eq "$lang|$gv") { return $raw }   # valorant-api уже спрашивали при этой версии игры
    $api = $null
    try { $api = "$((Invoke-RestMethod "$ValApi/version" -TimeoutSec 8).data.riotClientVersion)" } catch { Log "valorant-api /version: $($_.Exception.Message)" }
    $script:CatalogChecked = "$lang|$gv"
    if ($ok -and $api -and "$($raw.apiVer)" -eq $api) {   # каталог не изменился — запомнить версию игры, чтобы не спрашивать снова
        Set-Prop $raw 'gameVer' $gv
        Write-FileSafe $path (ConvertTo-Json -InputObject $raw -Depth 8 -Compress)
        return $raw
    }
    if ($api) {
        try {
            $o = Get-CatalogFromApi $lang; $o['apiVer'] = $api; $o['gameVer'] = $gv
            $json = ConvertTo-Json -InputObject $o -Depth 8 -Compress
            Write-FileSafe $path $json
            Log "каталог скинов: $api ($lang), $([Math]::Round($json.Length / 1KB)) КБ"
            return ($json | ConvertFrom-Json)
        } catch { Log "каталог скинов не скачался: $($_.Exception.Message)" }
    }
    if ($raw -and $raw.lang -eq $lang) { return $raw }
    throw (L 'Список предметов не скачался с valorant-api.com (нет сети?) — открой позже.' 'The item list did not download from valorant-api.com (no network?) — try later.')
}

# ── Что есть на аккаунте ─────────────────────────────────────────────────────

# Множество ItemID (нижний регистр) по всем типам одним запросом.
function Get-OwnedItems($s) {
    $rt = Get-RiotRoute $s
    $r = Invoke-Cloud { Invoke-RestMethod "$($rt.Pd)/store/v1/entitlements/$($s.Puuid)" -Headers (Get-GameHeaders $s $rt) -TimeoutSec 15 } $s
    $set = New-Object 'Collections.Generic.HashSet[string]'
    foreach ($t in @($r.EntitlementsByTypes)) { foreach ($e in @($t.Entitlements)) { if ($e.ItemID) { [void]$set.Add("$($e.ItemID)".ToLowerInvariant()) } } }
    , $set
}

# Скин из каталога → строка списка: только свои уровни и цвета. $null — скина нет на аккаунте.
function ConvertTo-OwnedSkin($w, $k, $own, $g) {
    $isDef = $k.id -eq $w.def
    $n = 0
    $lv = @(foreach ($l in @($k.lv)) { $n++; if ($isDef -or $own.Contains($l) -or ($g -and "$($g.SkinLevelID)" -eq $l)) { [ordered]@{ id = $l; n = $n } } })
    $on = $g -and "$($g.SkinID)" -eq $k.id
    if (-not $lv.Count -and -not $on) { return $null }
    $i = 0
    $ch = @(foreach ($c in @($k.ch)) { if (($i++) -eq 0 -or $isDef -or $own.Contains($c.id) -or ($on -and "$($g.ChromaID)" -eq $c.id)) { $c } })
    [ordered]@{ cat = 'skin'; w = $w.id; id = $k.id; name = $k.name; icon = $k.icon; on = [bool]$on; def = $isDef; lv = $lv; ch = $ch
                curLv = $(if ($on) { "$($g.SkinLevelID)".ToLowerInvariant() } else { '' }); curCh = $(if ($on) { "$($g.ChromaID)".ToLowerInvariant() } else { '' }) }
}

# `valset list skins`: первый элемент — сведения (аккаунт, слоты спреев/флексов), дальше оружие, скины, брелоки, спреи,
# флексы, карточки, титулы — только то, что есть на аккаунте (и надетое сейчас).
function Get-ListSkins {
    try {
        $s = Connect-Session
        $cat = Get-SkinCatalog
        $lo = Get-Loadout $s; $own = Get-OwnedItems $s; $names = Get-CosmeticNames
        $guns = @{}; foreach ($g in @($lo.Guns)) { $guns["$($g.ID)".ToLowerInvariant()] = $g }
        $exprOn = @{}; foreach ($x in @($lo.ActiveExpressions)) { $exprOn["$($x.AssetID)".ToLowerInvariant()] = $true }
        $slot = 0
        $info = [ordered]@{ info = ''; account = (Get-AccountLabel $s.Puuid)
            slots = @(foreach ($x in @($lo.ActiveExpressions)) { [ordered]@{ i = $slot++; type = $(if ("$($x.TypeID)" -eq $EntFlex) { 'flex' } else { 'spray' }); name = (Get-ExprName $names $x) } }) }
        $out = New-Object Collections.ArrayList
        [void]$out.Add($info)
        $ws = @($cat.weapons) | Sort-Object { $i = [array]::IndexOf($WeaponOrder, "$($_.cat)"); if ($i -lt 0) { 99 } else { $i } }, { "$($_.name)" }
        foreach ($w in $ws) {
            $g = $guns[$w.id]; if (-not $g) { continue }   # оружия нет в лоадауте — надеть на него нельзя
            $cur = @($w.skins) | Where-Object { $_.id -eq "$($g.SkinID)".ToLowerInvariant() } | Select-Object -First 1
            $chOn = if ($cur) { @($cur.ch) | Where-Object { $_.id -eq "$($g.ChromaID)".ToLowerInvariant() } | Select-Object -First 1 }
            [void]$out.Add([ordered]@{ cat = 'weapon'; id = $w.id; name = $w.name; skin = (Get-SkinLabel $names $g); icon = "$(if ($chOn.icon) { $chOn.icon } elseif ($cur) { $cur.icon })" })
            foreach ($k in @($w.skins)) { $x = ConvertTo-OwnedSkin $w $k $own $g; if ($x) { [void]$out.Add($x) } }
        }
        foreach ($b in @($cat.buddies)) { if ($own.Contains($b.id)) { [void]$out.Add([ordered]@{ cat = 'buddy'; id = $b.id; name = $b.name; icon = $b.icon }) } }
        foreach ($k in @(@('sprays', 'spray'), @('flex', 'flex'))) {
            foreach ($x in @($cat.($k[0]))) { if ($own.Contains($x.id) -or $exprOn[$x.id]) { [void]$out.Add([ordered]@{ cat = $k[1]; id = $x.id; name = $x.name; icon = $x.icon; on = [bool]$exprOn[$x.id] }) } }
        }
        $card = "$($lo.Identity.PlayerCardID)".ToLowerInvariant(); $title = "$($lo.Identity.PlayerTitleID)".ToLowerInvariant()
        foreach ($x in @($cat.cards)) { if ($own.Contains($x.id) -or $x.id -eq $card) { [void]$out.Add([ordered]@{ cat = 'card'; id = $x.id; name = $x.name; icon = $x.icon; on = ($x.id -eq $card) }) } }
        foreach ($x in @($cat.titles)) { if ($x.name -and ($own.Contains($x.id) -or $x.id -eq $title)) { [void]$out.Add([ordered]@{ cat = 'title'; id = $x.id; name = $x.name; on = ($x.id -eq $title) }) } }
        , $out.ToArray()
    } catch { , @([ordered]@{ error = $_.Exception.Message }) }
}

# ── Надеть один предмет ──────────────────────────────────────────────────────
# Спецификация (только GUID и числа — безопасна в командной строке):
#   gun:<оружие>:<скин>:<уровень>:<цвет> | expr:<слот>:<TypeID>:<предмет> | card:<id> | title:<id>
# Брелоки не надеваем: форма элемента Attachments в лоадауте v3 не измерена (NOTES.md).

function Join-SkinLoadout($cur, [string]$spec) {
    $G = '([0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})'   # форма GUID; только буквы и цифры
    $new = Copy-Json $cur
    if ($spec -match "^gun:${G}:${G}:${G}:${G}$") {
        $g = @($new.Guns) | Where-Object { "$($_.ID)" -eq $Matches[1] } | Select-Object -First 1
        if (-not $g) { throw (L 'Этого оружия нет в лоадауте аккаунта.' 'This weapon is not in the account loadout.') }
        Set-Prop $g 'SkinID' $Matches[2]; Set-Prop $g 'SkinLevelID' $Matches[3]; Set-Prop $g 'ChromaID' $Matches[4]
    } elseif ($spec -match "^expr:(\d{1,2}):${G}:${G}$") {
        $i = [int]$Matches[1]; $t = $Matches[2].ToLowerInvariant(); $a = $Matches[3]
        if ($t -notin $EntSpray, $EntFlex) { throw (L 'Неизвестный тип предмета.' 'Unknown item type.') }
        $ex = @($new.ActiveExpressions)
        if ($i -ge $ex.Count) { throw (L 'Такого слота нет — список обновлён, выбери заново.' 'No such slot — the list was refreshed, pick again.') }
        Set-Prop $ex[$i] 'TypeID' $t; Set-Prop $ex[$i] 'AssetID' $a
        Set-Prop $new 'ActiveExpressions' $ex
    } elseif ($spec -match "^(card|title):${G}$") {
        if (-not $new.Identity) { Set-Prop $new 'Identity' ([pscustomobject]@{}) }
        Set-Prop $new.Identity $(if ($Matches[1] -eq 'card') { 'PlayerCardID' } else { 'PlayerTitleID' }) $Matches[2]
    } else { throw (L 'Некорректный предмет.' 'Invalid item.') }
    $new
}

# `valset list skin:<спец>`: предпросмотр «было → станет», как у набора.
function Get-ListSkinPreview([string]$spec) {
    try {
        $s = Connect-Session
        $cur = Get-Loadout $s
        $rows = Compare-Loadout $cur (Join-SkinLoadout $cur $spec) (Get-CosmeticNames)
        @([ordered]@{ info = ''; account = (Get-AccountLabel $s.Puuid); same = (-not $rows.Count) }) + @($rows)
    } catch { @([ordered]@{ error = $_.Exception.Message }) }
}

# `valset do skin:<спец>`: бэкап, точка отмены, запись (Write-LoadoutChange, sets.ps1).
function Invoke-SkinApply([string]$spec) {
    $s = Connect-Session
    $cur = Get-Loadout $s
    $rows = Write-LoadoutChange $s $cur (Join-SkinLoadout $cur $spec) "скин $spec"
    if (-not $rows.Count) { return (L 'Уже надето' 'Already on') }
    $r = $rows[0]
    L "Надето: $($r.what) — $($r.new)" "Put on: $($r.what) — $($r.new)"
}
