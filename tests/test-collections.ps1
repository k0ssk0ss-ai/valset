# test-collections.ps1 — «Коллекции» (collections.ps1): группировка по коллекциям без «Стандартных» и «случайного»,
# свои/чужие уровни и цвета, «Надеть коллекцию» (старший свой уровень и цвет, надетый скин —
# как есть), запись с отменой, отказ без записи, набор из коллекции, картинки набора.
# Подключается из run-tests.ps1 после test-skins.ps1 (там G, $gV, $gC, $loA, Check, Parse-Arr, Invoke-Do). Сети нет.

$fnKeepC = @{}; foreach ($f in 'Get-Loadout', 'Send-LoadoutPut', 'Get-SkinCatalog', 'Get-OwnedItems') { $fnKeepC[$f] = (Get-Item "Function:\$f").ScriptBlock }
$thB = G 'beef0001'; $thA = G 'beef0002'; $thZ = G 'beef0003'; $thS = G 'beef000f'
$ch = { param($id) [ordered]@{ id = (G $id); name = $id; icon = "https://media.valorant-api.com/$id.png"; sw = '' } }
$catC = ConvertTo-Json -Depth 8 -Compress -InputObject ([ordered]@{ v = 2; lang = 'ru'
    weapons = @(
        [ordered]@{ id = $gV; name = 'Vandal'; cat = 'Rifle'; def = (G 'skind000'); skins = @(
            [ordered]@{ id = (G 'skind000'); name = 'Vandal'; icon = ''; th = $thS; lv = @((G 'lvld0001')); ch = @((& $ch 'chromad0')) }
            [ordered]@{ id = (G 'skina000'); name = 'Прайм Vandal'; icon = 'https://media.valorant-api.com/a.png'; th = $thA; lv = @((G 'lvla0001'), (G 'lvla0002')); ch = @((& $ch 'chromaa0')) }
            [ordered]@{ id = (G 'skinb000'); name = 'Жнец Vandal'; icon = 'https://media.valorant-api.com/b.png'; th = $thB; lv = @((G 'lvlb0001'), (G 'lvlb0004'))
                        ch = @((& $ch 'chromab0'), (& $ch 'chromab2'), (& $ch 'chromab3')) }
            [ordered]@{ id = (G 'skinz000'); name = 'Чужой Vandal'; icon = ''; th = $thZ; lv = @((G 'lvlz0001')); ch = @((& $ch 'chromaz0')) }
            [ordered]@{ id = (G 'skinr000'); name = 'Random Favorite Skin'; icon = ''; th = $ThemeRandom; lv = @((G 'lvlr0001')); ch = @((& $ch 'chromar0')) }) }
        [ordered]@{ id = $gC; name = 'Classic'; cat = 'Sidearm'; def = (G 'skinc000'); skins = @(
            [ordered]@{ id = (G 'skinc000'); name = 'Classic'; icon = ''; th = $thS; lv = @((G 'lvlc0001')); ch = @((& $ch 'chromac0')) }
            [ordered]@{ id = (G 'skinac00'); name = 'Прайм Classic'; icon = ''; th = $thA; lv = @((G 'lvlac001')); ch = @((& $ch 'chromac1'), (& $ch 'chromac2')) }
            [ordered]@{ id = (G 'skinbc00'); name = 'Жнец Classic'; icon = ''; th = $thB; lv = @((G 'lvlbc001')); ch = @((& $ch 'chromabc')) }) })
    themes = @([ordered]@{ id = $thB; name = 'Жнец' }, [ordered]@{ id = $thA; name = 'Прайм' }, [ordered]@{ id = $thZ; name = 'Чужая' }, [ordered]@{ id = $thS; name = 'Standard' })
    buddies = @(); sprays = @([ordered]@{ id = (G 'spray002'); name = 'Ой'; icon = 'https://media.valorant-api.com/s2.png' }); flex = @()
    cards = @([ordered]@{ id = (G 'card0002'); name = 'Карта 2'; icon = 'https://media.valorant-api.com/c2.png' }); titles = @() })
function Get-SkinCatalog { $catC | ConvertFrom-Json }
function Get-OwnedItems($s) {
    $h = New-Object 'Collections.Generic.HashSet[string]'
    foreach ($x in 'lvla0001', 'lvlb0001', 'lvlb0004', 'chromab2', 'lvlac001', 'chromac2', 'card0002', 'spray002') { [void]$h.Add((G $x)) }
    , $h
}
function Get-Loadout($s) { ConvertTo-Json -InputObject $script:lo -Depth 10 -Compress | ConvertFrom-Json }
function Send-LoadoutPut($s, [string]$body) { $script:puts += $body; if ($script:putFail) { throw $script:putFail }; $script:lo = $body | ConvertFrom-Json; $script:lo }
$script:CosNames = @{ lang = 'ru'; Levels = @{}; Agents = @(); Names = @{ $gV = 'Vandal'; $gC = 'Classic' } }
$script:lo = $loA; $script:puts = @(); $script:putFail = $null
$gun = { param($id) @($script:lo.Guns) | Where-Object { $_.ID -eq $id } }

Write-Host 'коллекции'
# каталог из valorant-api (подставной ответ): у стандартного скина вместо «X» — картинка оружия; коллекция скина
function Invoke-RestMethod($u, $TimeoutSec) {
    $d = if ($u -like '*/weapons?*') { @([pscustomobject]@{ uuid = $gV; displayName = 'Vandal'; category = 'EEquippableCategory::Rifle'; defaultSkinUuid = (G 'skind000'); displayIcon = 'https://media.valorant-api.com/w.png'
        skins = @([pscustomobject]@{ uuid = (G 'skind000'); displayName = 'Standard Vandal'; themeUuid = $thS; displayIcon = 'https://media.valorant-api.com/x.png'; levels = @([pscustomobject]@{ uuid = (G 'lvld0001') })
                                     chromas = @([pscustomobject]@{ uuid = (G 'chromad0'); displayName = 'Standard Vandal'; displayIcon = 'https://media.valorant-api.com/x2.png' }) }) }) } else { @() }
    [pscustomobject]@{ data = $d }
}
$o = Get-CatalogFromApi 'ru'; Remove-Item Function:\Invoke-RestMethod
$k0 = $o.weapons[0].skins[0]
Check 'каталог: стандартный скин — картинка оружия, коллекция скина' ($k0.icon -eq 'https://media.valorant-api.com/w.png' -and $k0.ch[0].icon -eq $k0.icon -and $k0.th -eq $thS) (ConvertTo-Json -InputObject $k0 -Depth 4 -Compress)
$l = Parse-Arr (Get-ListJson 'collections')
Check 'коллекции: без «Стандартных» и «случайного», свои выше' ($l.Count -eq 4 -and $l[1].id -eq $thA -and $l[1].own -eq 2 -and $l[2].id -eq $thB -and $l[2].own -eq 1 -and $l[2].n -eq 2 -and $l[3].own -eq 0 -and
    (@($l[2].items) | ForEach-Object { $_.o }) -join ',' -eq 'False,True') (Get-ListJson 'collections')
$d = Parse-Arr (Get-ListJson "collection:$thB")
$v = $d | Where-Object { $_.id -eq (G 'skinb000') }
Check 'коллекция: оружие по порядку игры, чужое отмечено' ($d[0].name -eq 'Жнец' -and $d[0].own -eq 1 -and $d[0].put -eq 1 -and $d[1].w -eq $gC -and -not $d[1].own -and $v.own -and $v.gun) (Get-ListJson "collection:$thB")
Check 'коллекция: свои уровни и цвета' ($v.lv[0].own -and $v.lv[1].own -and -not ($v.lv[1].PSObject.Properties['v']) -and $v.ch[0].own -and $v.ch[1].own -and -not $v.ch[2].own) (ConvertTo-Json -InputObject $v -Depth 5 -Compress)

$p = Parse-Arr (Get-ListJson "coll:$thB")
Check 'надеть коллекцию: предпросмотр без записи, старший уровень и цвет, картинки' ($p[0].same -eq $false -and $p.Count -eq 2 -and $p[1].what -eq 'Vandal' -and @($p[0].pics).Count -eq 1 -and $p[0].pics[0].i -like '*chromab2.png' -and $script:puts.Count -eq 0) (Get-ListJson "coll:$thB")
$p = Parse-Arr (Get-ListJson "coll:$thA")
Check 'надеть коллекцию: надетый скин коллекции не меняется, единственный уровень — старший свой цвет' ($p.Count -eq 2 -and $p[1].what -eq 'Classic') (Get-ListJson "coll:$thA")
$r = Invoke-Do "coll:$thB"
$g = & $gun $gV
Check 'надеть коллекцию: одна запись, отмена, остальное как было' ($r.ok -and $r.undo -and $script:puts.Count -eq 1 -and $g.SkinID -eq (G 'skinb000') -and $g.SkinLevelID -eq (G 'lvlb0004') -and $g.ChromaID -eq (G 'chromab2') -and
    @($g.Attachments).Count -eq 1 -and (& $gun $gC).SkinID -eq (G 'skinc000') -and $script:lo.Identity.PlayerCardID -eq (G 'card0001')) ($r | ConvertTo-Json -Compress)
$u = Invoke-Do 'undo'
Check 'коллекция: отмена вернула лоадаут' ($u.ok -and (& $gun $gV).SkinID -eq (G 'skina000'))
$n = $script:puts.Count
$r1 = Invoke-Do "coll:$thZ"; $r2 = Invoke-Do 'coll:x"&calc'; $r3 = Invoke-Do "coll:$(G 'dead0000')"
Check 'коллекция: ничего своего / кривой id / нет в каталоге — отказ без записи' (-not $r1.ok -and $r1.message -like '*ничего нет*' -and -not $r2.ok -and -not $r3.ok -and $script:puts.Count -eq $n) ($r1.message + ' | ' + $r2.message + ' | ' + $r3.message)

# набор из коллекции: только её оружие; карточка, спреи, другое оружие не трогаются
$r = Invoke-Do "loadoutsave:$(B64 'Жнец'):$thB"
$set = @(Read-Sets) | Where-Object { $_.name -eq 'Жнец' }
Check 'набор из коллекции: только оружие коллекции' ($r.ok -and @($set.guns).Count -eq 1 -and $set.guns[0].SkinID -eq (G 'skinb000') -and @($set.expressions).Count -eq 0 -and -not $set.identity.PlayerCardID) ($r | ConvertTo-Json -Compress)
$lp = Parse-Arr (Get-ListJson "loadout:$($set.id)")
Check 'набор из коллекции: предпросмотр — одно изменение, картинка скина' ($lp.Count -eq 2 -and $lp[1].what -eq 'Vandal' -and @($lp[0].pics).Count -eq 1 -and $lp[0].pics[0].t -eq 'gun') (Get-ListJson "loadout:$($set.id)")
$pics = @(Get-SetPics ([pscustomobject]@{ guns = @([pscustomobject]@{ SkinID = (G 'skind000'); ChromaID = (G 'chromad0') }); identity = [pscustomobject]@{ PlayerCardID = (G 'card0002') }
                                           expressions = @([pscustomobject]@{ AssetID = (G 'spray002') }, [pscustomobject]@{ AssetID = $ZeroGuid }) }))
Check 'картинки набора: стандартный скин — нет, карточка и спрей — есть' ($pics.Count -eq 2 -and $pics[0].t -eq 'card' -and $pics[1].i -like '*s2.png') (ConvertTo-Json -InputObject $pics -Compress)
$null = Invoke-Do "loadoutdel:$($set.id)"

Remove-LastAction
foreach ($f in $fnKeepC.Keys) { Set-Item "Function:\$f" $fnKeepC[$f] }
$script:CosNames = $null
