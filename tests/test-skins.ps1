# test-skins.ps1 — «Все скины» (skins.ps1): подписи цветов, владение (свои уровни и цвета, стандартный скин), список,
# предпросмотр и запись одного предмета, отказ на кривую спецификацию. Сеть подставная: каталог, владения, лоадаут — заглушки.
# Подключается из run-tests.ps1 после test-sets.ps1 (там G, $loA, Check, Parse-Arr, Invoke-Do).

$fnKeepS = @{}; foreach ($f in 'Get-Loadout', 'Send-LoadoutPut', 'Get-SkinCatalog', 'Get-OwnedItems') { $fnKeepS[$f] = (Get-Item "Function:\$f").ScriptBlock }
$script:CosNames = @{ lang = 'ru'; Levels = @{}; Agents = @()
    Names = @{ $gV = 'Vandal'; $gC = 'Classic'; (G 'skina000') = 'Прайм Vandal'; (G 'skinb000') = 'Жнец Vandal'; (G 'chromab2') = "Жнец Vandal`n(Вариант 2)"
               (G 'spray001') = 'Спрей «Ура»'; (G 'spray002') = 'Спрей «Ой»'; (G 'card0001') = 'Карта 1'; (G 'card0002') = 'Карта 2' } }
$cat = ConvertTo-Json -Depth 8 -Compress -InputObject ([ordered]@{ v = 1; lang = 'ru'
    weapons = @([ordered]@{ id = $gV; name = 'Vandal'; cat = 'Rifle'; def = (G 'skind000'); skins = @(
        [ordered]@{ id = (G 'skind000'); name = 'Vandal'; icon = 'https://media.valorant-api.com/d.png'; lv = @((G 'lvld0001')); ch = @([ordered]@{ id = (G 'chromad0'); name = 'обычный'; icon = ''; sw = '' }) }
        [ordered]@{ id = (G 'skina000'); name = 'Прайм Vandal'; icon = 'a.png'; lv = @((G 'lvla0001'), (G 'lvla0002')); ch = @([ordered]@{ id = (G 'chromaa0'); name = 'обычный'; icon = ''; sw = '' }) }
        [ordered]@{ id = (G 'skinb000'); name = 'Жнец Vandal'; icon = 'b.png'; lv = @((G 'lvlb0001'), (G 'lvlb0004'))
                    ch = @([ordered]@{ id = (G 'chromab0'); name = 'обычный'; icon = ''; sw = '' }, [ordered]@{ id = (G 'chromab2'); name = 'Вариант 2'; icon = ''; sw = '' }, [ordered]@{ id = (G 'chromab3'); name = 'Вариант 3'; icon = ''; sw = '' }) }
        [ordered]@{ id = (G 'skinz000'); name = 'Чужой Vandal'; icon = 'z.png'; lv = @((G 'lvlz0001')); ch = @() }) })
    buddies = @([ordered]@{ id = (G 'buddy001'); name = 'Кот'; icon = '' }); sprays = @([ordered]@{ id = (G 'spray001'); name = 'Ура'; icon = '' }, [ordered]@{ id = (G 'spray002'); name = 'Ой'; icon = '' })
    flex = @(); cards = @([ordered]@{ id = (G 'card0001'); name = 'Карта 1'; icon = '' }, [ordered]@{ id = (G 'card0002'); name = 'Карта 2'; icon = '' }); titles = @([ordered]@{ id = (G 'title001'); name = 'Титул 1'; icon = '' }) })
function Get-SkinCatalog { $cat | ConvertFrom-Json }
function Get-OwnedItems($s) {
    $h = New-Object 'Collections.Generic.HashSet[string]'
    foreach ($x in 'lvla0001', 'lvlb0001', 'lvlb0004', 'chromab2', 'buddy001', 'spray002', 'card0002') { [void]$h.Add((G $x)) }
    , $h
}
function Get-Loadout($s) { ConvertTo-Json -InputObject $script:lo -Depth 10 -Compress | ConvertFrom-Json }
function Send-LoadoutPut($s, [string]$body) { $script:puts += $body; if ($script:putFail) { throw $script:putFail }; $script:lo = $body | ConvertFrom-Json; $script:lo }
$script:lo = $loA; $script:puts = @(); $script:putFail = $null

Check 'скины: подпись цвета' ((Get-ChromaLabel "Odin `"Комета`"`n(расцветка 1 `"Красный`")" 1) -eq 'расцветка 1 "Красный"' -and (Get-ChromaLabel 'x' 0) -eq 'обычный')

$l = Parse-Arr (Get-ListJson 'skins')
$sk = @($l | Where-Object { $_.cat -eq 'skin' })
$b = $sk | Where-Object { $_.id -eq (G 'skinb000') }
Check 'скины: только свои (стандартный, надетый, купленные; чужого нет)' ($sk.Count -eq 3 -and -not ($sk | Where-Object { $_.id -eq (G 'skinz000') }) -and ($sk | Where-Object { $_.id -eq (G 'skind000') }).def) (Get-ListJson 'skins')
Check 'скины: свои уровни и цвета (базовый — всегда)' (@($b.lv).Count -eq 2 -and (@($b.ch) | ForEach-Object { $_.id }) -join ',' -eq "$(G 'chromab0'),$(G 'chromab2')")
$a = $sk | Where-Object { $_.id -eq (G 'skina000') }
Check 'скины: надетое отмечено' ($a.on -and $a.curLv -eq (G 'lvla0001') -and -not $b.on)
Check 'скины: оружие, слоты, предметы' (@($l | Where-Object { $_.cat -eq 'weapon' }).Count -eq 1 -and @($l[0].slots).Count -eq 3 -and $l[0].slots[0].type -eq 'flex' -and
    @($l | Where-Object { $_.cat -eq 'spray' }).Count -eq 2 -and @($l | Where-Object { $_.cat -eq 'card' }).Count -eq 2 -and @($l | Where-Object { $_.cat -eq 'buddy' }).Count -eq 1)

$spec = "gun:${gV}:$(G 'skinb000'):$(G 'lvlb0004'):$(G 'chromab2')"
$p = Parse-Arr (Get-ListJson "skin:$spec")
Check 'скин: предпросмотр без записи' ($p[0].same -eq $false -and $p[1].what -eq 'Vandal' -and $p[1].new -like 'Жнец*' -and $script:puts.Count -eq 0) (Get-ListJson "skin:$spec")
$r = Invoke-Do "skin:$spec"
$put = $script:puts[0] | ConvertFrom-Json
$g = @($put.Guns) | Where-Object { $_.ID -eq $gV }
Check 'скин: одна запись, отмена, остальное как было' ($r.ok -and $r.undo -and $script:puts.Count -eq 1 -and $g.SkinID -eq (G 'skinb000') -and $g.ChromaID -eq (G 'chromab2') -and @($g.Attachments).Count -eq 1 -and $put.Identity.PlayerCardID -eq (G 'card0001')) ($r | ConvertTo-Json -Compress)
$r = Invoke-Do "skin:$spec"
Check 'скин повторно: уже надето, без записи' ($r.ok -and $script:puts.Count -eq 1 -and $r.message -eq 'Уже надето')
$script:lo = $loA; $null = Invoke-Do "skin:$spec"; $u = Invoke-Do 'undo'   # повтор без записи стёр точку отмены — надеваем заново
Check 'скин: отмена вернула лоадаут' ($u.ok -and (@($script:lo.Guns) | Where-Object { $_.ID -eq $gV }).SkinID -eq (G 'skina000'))

$r = Invoke-Do "skin:expr:2:d5f120f8-ff8c-4aac-92ea-f2b5acbe9475:$(G 'spray002')"
Check 'спрей в слот 3: только этот слот' ($r.ok -and $script:lo.ActiveExpressions[2].AssetID -eq (G 'spray002') -and $script:lo.ActiveExpressions[1].AssetID -eq (G 'spray001')) ($r | ConvertTo-Json -Compress)
$r = Invoke-Do "skin:card:$(G 'card0002')"
Check 'карточка' ($r.ok -and $script:lo.Identity.PlayerCardID -eq (G 'card0002') -and $script:lo.Identity.AccountLevel -eq 42)
$n = $script:puts.Count
$r1 = Invoke-Do 'skin:expr:9:d5f120f8-ff8c-4aac-92ea-f2b5acbe9475:00000000-0000-0000-0000-000000000001'
$r2 = Invoke-Do 'skin:gun:x"&calc'
$r3 = Invoke-Do "skin:expr:0:$(G 'card0002'):$(G 'spray002')"
Check 'скин: кривой слот / спецификация / тип — отказ без записи' (-not $r1.ok -and -not $r2.ok -and -not $r3.ok -and $script:puts.Count -eq $n) ($r1.message + ' | ' + $r2.message + ' | ' + $r3.message)
$script:putFail = 'Riot не принял'
$r = Invoke-Do "skin:card:$(G 'card0001')"
Check 'скин: отказ Riot — понятная ошибка' (-not $r.ok -and $r.message -like '*Riot не принял*')
$script:putFail = $null

Remove-LastAction
foreach ($f in $fnKeepS.Keys) { Set-Item "Function:\$f" $fnKeepS[$f] }
$script:CosNames = $null
