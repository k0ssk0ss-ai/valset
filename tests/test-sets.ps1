# test-sets.ps1 — наборы косметики (sets.ps1): сохранение, предпросмотр, надевание, отказ Riot, отмена, привязка к агенту,
# решение автосмены. Riot подставной: Get-Loadout / Send-LoadoutPut / Get-PregameAgent — функции-заглушки, сети нет.
# Подключается из run-tests.ps1 (dot-source) в разделе «приложение»: там $script:sess, Get-Session, Check, Parse-Arr.

function G([string]$n) { "$n-0000-0000-0000-000000000000".Substring(0, 36) }   # короткий «ID» в формате GUID
$gV = G 'aaaaaaaa'; $gC = G 'bbbbbbbb'
$script:CosNames = @{ lang = 'ru'; Levels = @{ (G 'lvlb0004') = 4; (G 'lvla0001') = 1 }
    Names = @{ $gV = 'Vandal'; $gC = 'Classic'; (G 'skina000') = 'Прайм Vandal'; (G 'skinb000') = 'Жнец Vandal'; (G 'chromab2') = "Жнец Vandal`nВариант 2"
               (G 'buddy001') = 'Брелок-кот'; (G 'spray001') = 'Спрей «Ура»'; (G 'spray002') = 'Спрей «Ой»'; (G 'card0001') = 'Карта 1'; (G 'card0002') = 'Карта 2'
               (G 'title001') = 'Титул 1' }
    Agents = @([pscustomobject]@{ id = (G 'ae000001'); name = 'Jett' }, [pscustomobject]@{ id = (G 'ae000002'); name = 'Sage' }) }
# Лоадаут v3 (как GET .../personalization/v3/.../playerloadout, 13.09): брелок — в Attachments (формат элемента не измерен,
# здесь условный), спреи и флексы — ActiveExpressions; полей v2 (Sprays, Charm*) нет.
$tSpray = 'd5f120f8-ff8c-4aac-92ea-f2b5acbe9475'; $tFlex = '03a572de-4234-31ed-d344-ababa488f981'
function New-Lo($skin, $lvl, $chroma, $buddy, $spray, $card) {
    $att = @(if ($buddy) { [ordered]@{ ItemID = $buddy; InstanceID = (G 'inst0001') } })
    $gun = [ordered]@{ ID = $gV; SkinID = $skin; SkinLevelID = $lvl; ChromaID = $chroma; Attachments = $att }
    $o = [ordered]@{ Subject = $tp; Version = 7; Guns = @($gun, [ordered]@{ ID = $gC; SkinID = (G 'skinc000'); SkinLevelID = (G 'lvlc0001'); ChromaID = (G 'chromac0'); Attachments = @() })
        ActiveExpressions = @([ordered]@{ TypeID = $tFlex; AssetID = (G 'flex0001') }, [ordered]@{ TypeID = $tSpray; AssetID = $spray }, [ordered]@{ TypeID = $tSpray; AssetID = (G 'spray009') })
        DynamicOptions = [ordered]@{}
        Identity = [ordered]@{ PlayerCardID = $card; PlayerTitleID = (G 'title001'); AccountLevel = 42; PreferredLevelBorderID = (G 'border01'); HideAccountLevel = $true }; Incognito = $false }
    ConvertTo-Json -InputObject $o -Depth 10 -Compress | ConvertFrom-Json
}
$loA = New-Lo (G 'skina000') (G 'lvla0001') (G 'chromaa0') (G 'buddy001') (G 'spray001') (G 'card0001')
$loB = New-Lo (G 'skinb000') (G 'lvlb0004') (G 'chromab2') $null (G 'spray002') (G 'card0002')
$script:lo = $loA; $script:puts = @(); $script:putFail = $null; $script:pre = $null
$fnKeep = @{}; foreach ($f in 'Get-Loadout', 'Send-LoadoutPut', 'Get-PregameAgent', 'Get-SkinCatalog') { $fnKeep[$f] = (Get-Item "Function:\$f").ScriptBlock }
function Get-Loadout($s) { ConvertTo-Json -InputObject $script:lo -Depth 10 -Compress | ConvertFrom-Json }
function Send-LoadoutPut($s, [string]$body) { $script:puts += $body; if ($script:putFail) { throw $script:putFail }; $script:lo = $body | ConvertFrom-Json; $script:lo }
function Get-PregameAgent($s) { $script:pre }
function Get-SkinCatalog { [pscustomobject]@{ weapons = @(); sprays = @(); flex = @(); cards = @([pscustomobject]@{ id = (G 'card0002'); name = 'Карта 2'; icon = 'https://media.valorant-api.com/c2.png' }) } }   # картинки набора
function B64([string]$t) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

Write-Host 'наборы косметики'
$items = ConvertTo-SetItems $loB
$j = Join-SetLoadout $loA $items
$jv = @($j.Guns)[0]
$je = @($j.ActiveExpressions)
Check 'набор на лоадаут: скин, цвет, уровень; брелок снят; спрей и карточка; уровень аккаунта не тронут' ($jv.SkinID -eq (G 'skinb000') -and $jv.ChromaID -eq (G 'chromab2') -and @($jv.Attachments).Count -eq 0 -and $je[1].AssetID -eq (G 'spray002') -and $j.Identity.PlayerCardID -eq (G 'card0002') -and $j.Identity.AccountLevel -eq 42 -and $j.Identity.HideAccountLevel -eq $true -and @($loA.Guns)[0].SkinID -eq (G 'skina000'))
Check 'v3: ActiveExpressions целиком и по порядку; полей v2 нет' ($je.Count -eq 3 -and $je[0].TypeID -eq $tFlex -and $je[2].AssetID -eq (G 'spray009') -and -not $j.PSObject.Properties['Sprays'] -and -not $jv.PSObject.Properties['CharmID'] -and -not $items.Contains('sprays'))
$jb = Join-SetLoadout $loB (ConvertTo-SetItems $loA)
Check 'v3: брелок (Attachments) переносится как есть' ((ConvertTo-Json -InputObject @(@($jb.Guns)[0].Attachments) -Compress) -eq (ConvertTo-Json -InputObject @(@($loA.Guns)[0].Attachments) -Compress))
$old = [pscustomobject]@{ guns = @([pscustomobject]@{ ID = $gV; SkinID = (G 'skinb000'); SkinLevelID = (G 'lvlb0004'); ChromaID = (G 'chromab2'); CharmID = ''; CharmLevelID = ''; CharmInstanceID = '' })
    sprays = @([pscustomobject]@{ EquipSlotID = (G 'slot0001'); SprayID = (G 'spray002'); SprayLevelID = '' }, [pscustomobject]@{ EquipSlotID = (G 'slot0002'); SprayID = (G 'spray001'); SprayLevelID = '' })
    identity = [pscustomobject]@{ PlayerCardID = (G 'card0002'); PlayerTitleID = ''; PreferredLevelBorderID = '' } }
$jo = Join-SetLoadout $loA $old; $joe = @($jo.ActiveExpressions)
Check 'старый набор (v2): спреи по порядку в слоты-спреи, флекс не тронут, брелок не снят' ($joe[0].AssetID -eq (G 'flex0001') -and $joe[1].AssetID -eq (G 'spray002') -and $joe[2].AssetID -eq (G 'spray001') -and @(@($jo.Guns)[0].Attachments).Count -eq 1 -and @($jo.Guns)[0].SkinID -eq (G 'skinb000')) ($jo | ConvertTo-Json -Depth 6 -Compress)
$rows = Compare-Loadout $loA $j $script:CosNames
$rv = $rows | Where-Object { $_.what -eq 'Vandal' }
Check 'предпросмотр: названия, цвет без переноса строки, уровень' ($rv.old -eq 'Прайм Vandal' -and $rv.new -eq 'Жнец Vandal Вариант 2 · ур. 4') ($rows | ConvertTo-Json -Compress)
Check 'предпросмотр: брелок, спрей, карточка; Classic не меняется' ($rows.Count -eq 4 -and @($rows | Where-Object { $_.what -eq 'Vandal · брелок' -and $_.old -eq 'Брелок-кот' -and $_.new -eq '' }).Count -eq 1 -and @($rows | Where-Object { $_.what -eq 'Карточка' -and $_.new -eq 'Карта 2' }).Count -eq 1) ($rows | ConvertTo-Json -Compress)
Check 'нет в справочнике — начало ID' ((Get-ItemName $script:CosNames (G 'zzzzzzzz')) -eq 'zzzzzzzz')
$body = ConvertTo-LoadoutBody $j
Check 'тело записи v3: лоадаут целиком без Subject/Version' ((($body.Keys) -join ',') -eq 'Guns,ActiveExpressions,Identity,Incognito,DynamicOptions' -and (ConvertTo-Json -InputObject $body -Depth 10 -Compress) -like '*"Attachments":`[`]*') (ConvertTo-Json -InputObject $body -Depth 10 -Compress)

# сохранить: текущий (B) как набор
$script:lo = $loB
$r = Invoke-Do "loadoutsave:$(B64 'Мой набор')"
$sets = @(Read-Sets)
Check 'do loadoutsave: набор сохранён, отменяемо' ($r.ok -and $r.undo -and $sets.Count -eq 1 -and $sets[0].name -eq 'Мой набор' -and $sets[0].puuid -eq $tp -and @($sets[0].guns).Count -eq 2) ($r | ConvertTo-Json -Compress)
$sid = $sets[0].id
Check 'do loadoutsave: имя с кавычками — ошибка' (-not (Invoke-Do "loadoutsave:$(B64 'a"b')").ok)
$ll = Parse-Arr (Get-ListJson 'loadouts')
Check 'list loadouts: имя и подсказка' ($ll.Count -eq 1 -and $ll[0].id -eq $sid -and $ll[0].hint -like 'без агента*') (Get-ListJson 'loadouts')
Check 'list agents: из справочника' ((Parse-Arr (Get-ListJson 'agents')).Count -eq 2)

# предпросмотр и надевание на A
$script:lo = $loA; $script:puts = @()
$lp = Parse-Arr (Get-ListJson "loadout:$sid")
Check 'list loadout: предпросмотр без записи' ($lp[0].info -like 'Набор «Мой набор»*' -and $lp[0].same -eq $false -and $lp.Count -eq 5 -and @($lp[0].pics).Count -eq 1 -and $lp[0].pics[0].t -eq 'card' -and $script:puts.Count -eq 0) (Get-ListJson "loadout:$sid")
$bkT = [DateTime]::Now.AddSeconds(-1)
$r = Invoke-Do "loadout:$sid"
Check 'do loadout: одна запись, бэкап, отмена' ($r.ok -and $r.undo -and $script:puts.Count -eq 1 -and $r.message -like 'Набор «Мой набор» надет: 4*' -and @(Get-ChildItem $LoadoutBackupDir -Filter *.json | Where-Object { $_.LastWriteTime -gt $bkT }).Count -eq 1) ($r | ConvertTo-Json -Compress)
$r = Invoke-Do "loadout:$sid"
Check 'do loadout повторно: уже надет, без записи' ($r.ok -and $script:puts.Count -eq 1 -and $r.message -like '*уже надет')
$script:lo = $loA; $null = Invoke-Do "loadout:$sid"; $r = Invoke-Do 'undo'
Check 'do undo после набора: прежний лоадаут записан' ($r.ok -and @($script:lo.Guns)[0].SkinID -eq (G 'skina000') -and @(@($script:lo.Guns)[0].Attachments)[0].ItemID -eq (G 'buddy001')) ($r | ConvertTo-Json -Compress)
$script:putFail = 'Удаленный сервер возвратил ошибку: (400) Недопустимый запрос.'; $script:puts = @()
$r = Invoke-Do "loadout:$sid"
Check 'Riot отклонил (нет предмета) — понятная ошибка, лоадаут прежний' (-not $r.ok -and $r.message -like 'Riot не принял набор*' -and @($script:lo.Guns)[0].SkinID -eq (G 'skina000')) ($r | ConvertTo-Json -Compress)
$script:putFail = $null

# привязка к агенту: у агента один набор
$script:lo = $loA; $null = Invoke-Do "loadoutsave:$(B64 'Второй')"
$sid2 = (@(Read-Sets) | Where-Object { $_.name -eq 'Второй' }).id
$r1 = Invoke-Do "loadoutbind:${sid}:$(G 'ae000001')"; $r2 = Invoke-Do "loadoutbind:${sid2}:$(G 'ae000001')"
$by = @{}; foreach ($x in Read-Sets) { $by[$x.id] = "$($x.agent)" }
Check 'loadoutbind: Jett у второго, первый отвязан' ($r1.ok -and $r2.message -like '*для агента Jett' -and $by[$sid2] -eq (G 'ae000001') -and $by[$sid] -eq '') ($r2 | ConvertTo-Json -Compress)
Check 'loadoutbind: агент не GUID — ошибка' (-not (Invoke-Do "loadoutbind:${sid}:jett").ok)
$null = Invoke-Do "loadoutbind:${sid}:$(G 'ae000002')"

# решение автосмены (без сети)
$sets = Read-Sets; $p = [pscustomobject]@{ MatchId = 'm1'; Agent = (G 'ae000002'); Locked = $true }
Check 'авто: выключено — ничего' ($null -eq (Get-AutoSetChoice $false $sets $p $null))
Check 'авто: агент не зафиксирован — ничего' ($null -eq (Get-AutoSetChoice $true $sets ([pscustomobject]@{ MatchId = 'm1'; Agent = (G 'ae000002'); Locked = $false }) $null))
Check 'авто: зафиксирован Sage — его набор' ((Get-AutoSetChoice $true $sets $p $null).id -eq $sid)
Check 'авто: в этом матче уже надевали — ничего' ($null -eq (Get-AutoSetChoice $true $sets $p ([pscustomobject]@{ match = 'm1' })))
Check 'авто: агент без набора / не в выборе агента — ничего' ($null -eq (Get-AutoSetChoice $true $sets ([pscustomobject]@{ MatchId = 'm2'; Agent = (G 'ae000003'); Locked = $true }) $null) -and $null -eq (Get-AutoSetChoice $true $sets $null $null))

# do loadoutauto: выключено — без записи; включено — надевает один раз за матч; чужую отмену не стирает зря
$script:lo = $loA; $script:puts = @(); $script:pre = $p
$null = Invoke-Do "loadoutbind:${sid2}:none"; $la0 = Get-Content $LastActionPath -Raw
$r = Invoke-Do 'loadoutauto'
Check 'loadoutauto: настройка выкл — done, без записи, отмена цела' ($r.ok -and $r.done -and -not $r.applied -and $script:puts.Count -eq 0 -and (Get-Content $LastActionPath -Raw) -eq $la0) ($r | ConvertTo-Json -Compress)
Set-Config 'setsAuto' $true
$script:pre = [pscustomobject]@{ MatchId = 'm1'; Agent = (G 'ae000002'); Locked = $false }
$r = Invoke-Do 'loadoutauto'
Check 'loadoutauto: агент ещё не зафиксирован — не done, без записи' ($r.ok -and -not $r.done -and $script:puts.Count -eq 0)
$script:pre = $p
$r = Invoke-Do 'loadoutauto'
Check 'loadoutauto: Sage зафиксирован — набор надет, отменяемо' ($r.ok -and $r.done -and $r.applied -and $r.undo -and $script:puts.Count -eq 1 -and $r.message -like 'Sage — Набор «Мой набор» надет*') ($r | ConvertTo-Json -Compress)
$r = Invoke-Do 'loadoutauto'
Check 'loadoutauto: тот же матч — второй раз не надевает' ($r.ok -and $r.done -and -not $r.applied -and $script:puts.Count -eq 1)
$st = Get-StateJson | ConvertFrom-Json
Check 'state: setsAuto' ($st.setsAuto -eq $true)
Set-Config 'setsAuto' $false

$r = Invoke-Do "loadoutdel:$sid2"; $n1 = @(Read-Sets).Count; $u = Invoke-Do 'undo'
Check 'loadoutdel и отмена' ($r.ok -and $n1 -eq 1 -and $u.ok -and @(Read-Sets).Count -eq 2) ($u | ConvertTo-Json -Compress)
Remove-LastAction
foreach ($f in $fnKeep.Keys) { Set-Item "Function:\$f" $fnKeep[$f] }
$script:CosNames = $null
