# test-codec.ps1 — код VALSET3 (codec.ps1, codeparts.ps1, codes.ps1, shareskins.ps1): словари, числа без потерь, бинды,
# прицелы владельца, CRC и обрезка, «новее» / «повреждён», длины кода, скины с подставным каталогом.
# Подключается из run-tests.ps1 в блоке «код для друга»: там $pf (профиль с прицелами), $xs, $code, $codeB, Check,
# Get-ListJson, Parse-Arr, Invoke-Do, подставное облако $script:cloud. Сети нет.

$cloudKeep = $script:cloud; $codecT0 = [DateTime]::Now.AddSeconds(-1)

# словари: каждое имя туда и обратно, без повторов (повтор сломал бы номера)
$bad = @(foreach ($k in $CodeDicts.Keys) {
    if ((Get-CodeIndex $k).Count -ne $CodeDicts[$k].Count) { "${k}: повтор" }
    foreach ($n in $CodeDicts[$k]) {
        $b = New-CodeBuf; Add-NameRef $b $k $n 1
        $r = New-CodeReader $b.ToArray(); if ((Read-NameRef $r $k (Read-Var $r) 1) -cne $n -or $b.Count -gt 2) { "$k/$n" }
    }
})
Check "код3: словари — все $(@($CodeDicts.Values | ForEach-Object { $_ }).Count) имён туда и обратно, без повторов" (-not $bad.Count) "$bad"
Check 'код3: пути прицела — 15 частых первыми, всего 159' ($CodeDicts.xh.Count -eq 159 -and $CodeDicts.xh[0] -eq 'profileName') "$($CodeDicts.xh.Count)"

# числа: без потерь (печать облака разная: G17, короткая, «лишняя» последняя цифра), короткие — коротко
$nums = '0.23749999701976777', '0.2223682552576065', '0.699999988079071', '0.69999998807907104', '1.2000000476837159', '0.11999999731779099',
        '0', '2', '60', '-3', '-1.5', '123456.789', '0.0000001', '3.4028234663852886E+38', '1E-05', '5000000000', '0.5000'
$bad = @(foreach ($j in $nums) {
    $v = ('{"v":' + $j + '}' | ConvertFrom-Json).v
    $b = New-CodeBuf
    if (-not (Add-Num $b $v)) { if ($j -notmatch 'E') { "${j}: не упаковалось" }; continue }
    $back = Read-Num (New-CodeReader $b.ToArray())
    if ((Get-JsonText $back) -cne (Get-JsonText $v)) { "$j → $(Get-JsonText $back)" }
})
Check 'код3: числа облака — без потерь' (-not $bad.Count) "$bad"
$sz = @(foreach ($j in '0.699999988079071', '0.69999998807907104', '2', '0.23749999701976777') { $b = New-CodeBuf; $null = Add-Num $b (('{"v":' + $j + '}' | ConvertFrom-Json).v); $b.Count })
Check 'код3: 0.7 — 3 байта, 2 — 1 байт, «лишняя цифра» — до 4' ($sz[0] -le 3 -and $sz[1] -le 3 -and $sz[2] -eq 1 -and $sz[3] -le 4) "$sz"
$b = New-CodeBuf; $ok = (Add-Num $b 0.31) -and (Get-JsonText (Read-Num (New-CodeReader $b.ToArray()))) -eq '0.31'
Check 'код3: число с double (0.31 из PowerShell)' $ok

# профиль: бинды и настройки туда и обратно точно; незнакомые имена — строкой; кривая запись — как есть
$p3 = Copy-Json $pf
$p3 | Add-Member -NotePropertyName actionMappings -NotePropertyValue @(@($p3.actionMappings) +
    [pscustomobject][ordered]@{ alt = $true; bindIndex = 1; characterName = 'НовыйАгент'; cmd = $false; ctrl = $true; key = 'F99'; name = 'Новое_Действие'; shift = $true; tapHoldType = 'Hold' } +
    [pscustomobject][ordered]@{ name = 'Ping'; key = 'Q'; extra = 1 }) -Force
$p3 | Add-Member -NotePropertyName floatSettings -NotePropertyValue @(@($p3.floatSettings) + [pscustomobject]@{ settingEnum = 'EAresFloatSettingName::BrandNew'; value = 0.25 } +
    [pscustomobject]@{ settingEnum = 'Other::Thing'; value = 1 } + [pscustomobject]@{ settingEnum = 'EAresFloatSettingName::Odd'; value = 'текст' }) -Force
$pr = ConvertTo-SharePrefs $p3; $xh0 = @((Get-Crosshairs $pr).profiles)[0]
$pr.stringSettings = @(@($pr.stringSettings) | Where-Object { $_.settingEnum -ne $CrosshairEnum })
$d3 = ConvertFrom-Code3Bytes (ConvertTo-Code3Bytes $false $pr (Get-XhDelta $xh0 (Get-XhTemplate)) $null)
Check 'код3: бинды и настройки точно (незнакомые имена, кривые записи)' ((Get-JsonText (ConvertTo-SharePrefs $d3.Profile)) -ceq (Get-JsonText $pr))
$tj = Get-XhTemplate; Join-XhDelta $tj $d3.Xh
Check 'код3: прицел из кода — тот же' ((Get-XhKey $tj) -eq (Get-XhKey $xh0))

# прицелы владельца (5 из tests\fixtures): двоичные отличия против сжатого JSON отличий
$xsz = @(foreach ($x in @($xs.profiles)) {
    $dl = Get-XhDelta $x (Get-XhTemplate)
    $b = New-CodeBuf; Add-CodeXh $b $dl
    $t = Get-XhTemplate; Join-XhDelta $t (Read-CodeXh (New-CodeReader $b.ToArray()))
    [pscustomobject]@{ ok = (Get-XhKey $t) -eq (Get-XhKey $x); bin = $b.Count; def = (Compress-Bytes (ConvertTo-Json -InputObject $dl -Depth 20 -Compress)).Length }
})
Check "код3: 5 прицелов владельца без потерь, байт $(($xsz | ForEach-Object { "$($_.bin)/$($_.def)" }) -join ' ') (двоично/deflate JSON)" (@($xsz | Where-Object { -not $_.ok -or $_.bin -ge $_.def }).Count -eq 0)

# код целиком: длина на тестовом профиле, только base64url, без прицела, только бинды
$body = $code.Substring(8)
Check "код3: VALSET3, только A-Z a-z 0-9 - _, полный $($code.Length) знаков, бинды $($codeB.Length)" ($code.StartsWith('VALSET3:') -and $body -cmatch '^[A-Za-z0-9_-]+$' -and $code.Length -le 220 -and $codeB.Length -le 80)
$rb = Read-ShareCode $codeB
Check 'код3: только бинды — без настроек и прицела' ($rb.Kind -eq 'binds' -and -not $rb.Prefs.PSObject.Properties['floatSettings'] -and -not (Get-Crosshairs $rb.Prefs))
$pn = Copy-Json $pr
$d4 = ConvertFrom-Code3Bytes (ConvertTo-Code3Bytes $false $pn $null $null)
Check 'код3: без прицела — флага нет, прицела нет' ($null -eq $d4.Xh -and -not $d4.Skins)
Check 'код3: ссылка valset:code/ без префикса; точки вместо переносов; подпись за кодом' ((Read-ShareCode $body).Kind -eq 'full' -and (Read-ShareCode ('VALSET3:' + $body.Substring(0, 40) + '.' + $body.Substring(40) + ' спасибо')).Kind -eq 'full' -and (Read-ShareCode ('VALSET3:' + $body + '.have.fun')).Kind -eq 'full')

# CRC и обрезка; «новее»
$err = { param($t) try { $null = Read-ShareCode $t; '' } catch { $_.Exception.Message } }
$flip = $body.Substring(0, 20) + $(if ($body[20] -eq 'A') { 'B' } else { 'A' }) + $body.Substring(21)
Check 'код3: опечатка — «повреждён»' ((& $err "VALSET3:$flip") -like '*повреждён*')
Check 'код3: обрезан — «повреждён»' ((& $err ('VALSET3:' + $body.Substring(0, $body.Length - 3))) -like '*повреждён*' -and (& $err 'VALSET3:AbC') -like '*повреждён*')
$fix = { param([byte[]]$a) $a[-1] = [byte](Get-Crc8 $a ($a.Length - 1)); 'VALSET3:' + (ConvertTo-Url64 $a) }
$a = ConvertFrom-Url64 $body; $a[0] = [byte](0x40 -bor ($a[0] -band 15))
Check 'код3: формат новее — «обнови приложение»' ((& $err (& $fix $a)) -like '*обнови*' -and (& $err 'VALSET4:AAAA') -like '*обнови*')
$mk = { param([int]$ver) $s = New-CodeBuf; Add-Var $s 1; Add-Var $s (2 + $CodeDicts.act.Count + 5); Add-Var $s 2; Add-Var $s 0
        $b = New-CodeBuf; $b.Add([byte]0x31); Add-Var $b $ver; Add-CodeSection $b $s; $b.Add(0); & $fix $b.ToArray() }
Check 'код3: номер за словарём — «обнови», если словарь кода новее, иначе «повреждён»' ((& $err (& $mk ($CodesVer + 1))) -like '*обнови*' -and (& $err (& $mk $CodesVer)) -like '*повреждён*')
$a = ConvertFrom-Url64 $body; $a[1] = [byte]($CodesVer + 1)
Check 'код3: словарь новее, но все номера знакомы — читается' ((Read-ShareCode (& $fix $a)).Kind -eq 'full')

# старые коды: VALSET2 и VALSET1 из того же профиля
$prA = ConvertTo-SharePrefs $pf; $xhA = @((Get-Crosshairs $prA).profiles)[0]
$prA.stringSettings = @(@($prA.stringSettings) | Where-Object { $_.settingEnum -ne $CrosshairEnum })
$v2 = 'VALSET2:' + (ConvertTo-Cjk (Compress-Bytes (ConvertTo-Json -InputObject ([ordered]@{ v = 2; kind = 'full'; profile = $prA; xh = (Get-XhDelta $xhA (Get-XhTemplate)) }) -Depth 32 -Compress)))
$v1 = 'VALSET1:' + (Compress-Pref (ConvertTo-Json -InputObject ([ordered]@{ v = 1; kind = 'binds'; profile = $prA }) -Depth 32 -Compress))
$r2 = Read-ShareCode $v2; $r2b = Read-ShareCode $v2.Substring(8)
Check "код3: VALSET2 ($($v2.Length) знаков) и VALSET1 читаются, как VALSET3" ((Get-JsonText $r2.Prefs) -ceq (Get-JsonText (Read-ShareCode $code).Prefs) -and $r2b.Kind -eq 'full' -and (Read-ShareCode $v1).Kind -eq 'binds')

# ── скины: подставные каталог, лоадаут, владения ──
$fnKeepC = @{}; foreach ($f in 'Get-Loadout', 'Send-LoadoutPut', 'Get-SkinCatalog', 'Get-OwnedItems') { $fnKeepC[$f] = (Get-Item "Function:\$f").ScriptBlock }
$cosKeep = $script:CosNames
$script:CosNames = @{ lang = 'ru'; Levels = @{}; Agents = @(); Names = @{} }   # названия оружия — ниже, когда есть ID
function HexId([string]$s) { $h = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($s)); (New-Object Guid (, $h)).ToString() }
$W1 = HexId 'w-vandal'; $W2 = HexId 'w-classic'; $W3 = HexId 'w-phantom'; $Bc0 = HexId 'b-c0'; $Cc0 = $Bc0.Substring(0, 13) + (HexId 'c-c0').Substring(13)   # Cc0 — то же начало, что Bc0
$sk = { param($id, [string[]]$lv, [string[]]$ch) [ordered]@{ id = $id; name = $id; icon = "$id.png"; th = ''; lv = $lv; ch = @(foreach ($c in $ch) { [ordered]@{ id = $c; name = ''; icon = "$c.png"; sw = '' } }) } }
$catS = ConvertTo-Json -Depth 8 -Compress -InputObject ([ordered]@{ v = 4; lang = 'ru'
    weapons = @([ordered]@{ id = $W1; name = 'Vandal'; cat = 'Rifle'; def = (HexId 'd1'); skins = @((& $sk (HexId 'd1') @(HexId 'dl1') @(HexId 'dc0')), (& $sk (HexId 'a') @((HexId 'al1'), (HexId 'al2')) @((HexId 'ac0'), (HexId 'ac1')))) }
                [ordered]@{ id = $W2; name = 'Classic'; cat = 'Sidearm'; def = (HexId 'd2'); skins = @((& $sk (HexId 'd2') @(HexId 'dl2') @(HexId 'dc2')), (& $sk (HexId 'e') @(HexId 'el1') @(HexId 'ec0'))) }
                [ordered]@{ id = $W3; name = 'Phantom'; cat = 'Rifle'; def = (HexId 'd3'); skins = @((& $sk (HexId 'd3') @(HexId 'dl3') @(HexId 'dc3')), (& $sk (HexId 'b') @(HexId 'bl1') @($Bc0)), (& $sk (HexId 'c') @(HexId 'cl1') @($Cc0))) })
    buddies = @(); sprays = @([ordered]@{ id = (HexId 's1'); name = 'S1'; icon = '' }, [ordered]@{ id = (HexId 's2'); name = 'S2'; icon = '' }); flex = @([ordered]@{ id = (HexId 'f1'); name = 'F1'; icon = '' })
    cards = @([ordered]@{ id = (HexId 'k1'); name = 'K1'; icon = '' }, [ordered]@{ id = (HexId 'k2'); name = 'K2'; icon = '' }); titles = @([ordered]@{ id = (HexId 't1'); name = 'T1'; icon = '' }); themes = @() })
function Get-SkinCatalog { if ($script:catOff) { throw 'Список предметов не загрузился. Проверь сеть и открой позже.' }; $catS | ConvertFrom-Json }
function Get-OwnedItems($s) { $h = New-Object 'Collections.Generic.HashSet[string]'; foreach ($x in 'al1', 'al2', 'ac1', 's1', 's2', 'k2') { [void]$h.Add((HexId $x)) }; , $h }
function Get-Loadout($s) { ConvertTo-Json -InputObject $script:lo -Depth 10 -Compress | ConvertFrom-Json }
function Send-LoadoutPut($s, [string]$body) { $script:puts += $body; $script:lo = $body | ConvertFrom-Json; $script:lo }
$tS = $EntSpray; $tF = $EntFlex; $script:CosNames.Names = @{ $W1 = 'Vandal'; $W2 = 'Classic'; $W3 = 'Phantom' }
$mkLo = { param($g1, $g2, $g3, $ex, $card, $title)
    [ordered]@{ Subject = $tp; Version = 3; Guns = @(
        [ordered]@{ ID = $W1; SkinID = $g1[0]; SkinLevelID = $g1[1]; ChromaID = $g1[2]; Attachments = @() }
        [ordered]@{ ID = $W2; SkinID = $g2[0]; SkinLevelID = $g2[1]; ChromaID = $g2[2]; Attachments = @() }
        [ordered]@{ ID = $W3; SkinID = $g3[0]; SkinLevelID = $g3[1]; ChromaID = $g3[2]; Attachments = @() })
        ActiveExpressions = @(foreach ($x in $ex) { [ordered]@{ TypeID = $x[0]; AssetID = $x[1] } })
        Identity = [ordered]@{ PlayerCardID = $card; PlayerTitleID = $title; PreferredLevelBorderID = (HexId 'border'); AccountLevel = 5 }; Incognito = $false } }
$loMine = & $mkLo @((HexId 'a'), (HexId 'al2'), (HexId 'ac1')) @((HexId 'e'), (HexId 'el1'), (HexId 'ec0')) @((HexId 'b'), (HexId 'bl1'), $Bc0) @(@($tS, (HexId 's1')), @($tF, (HexId 'f1')), @($tS, (HexId 's2')), @($tS, $ZeroGuid)) (HexId 'k2') (HexId 't1')
$loFriend = & $mkLo @((HexId 'd1'), (HexId 'dl1'), (HexId 'dc0')) @((HexId 'd2'), (HexId 'dl2'), (HexId 'dc2')) @((HexId 'd3'), (HexId 'dl3'), (HexId 'dc3')) @(@($tS, (HexId 's2')), @($tF, (HexId 'f9')), @($tS, (HexId 's9'))) (HexId 'k1') (HexId 't9')
$script:lo = $loMine; $script:puts = @(); $script:catOff = $false

$codeS = New-ShareCode -Skins
$rs = Read-ShareCode $codeS; $raw = Read-ShareSkins $rs.Skins
Check "код3: со скинами $($codeS.Length) знаков (+$($codeS.Length - $code.Length)): 3 оружия, 3 слота, карточка и титул" ($raw.Guns.Count -eq 3 -and @($raw.Expr | Where-Object { $_.K }).Count -eq 3 -and $raw.Card -and $raw.Title -and $rs.Skins.Length -eq (1 + 3 * 7 + 1 + 4 + 18 + 1 + 12))
$script:lo = $loFriend; $script:cloud = $cloudC
$lc = Parse-Arr (Get-ListJson "code:$codeS")
Check 'код3: предпросмотр — «4 из 8 у тебя есть», скин, 2 спрея, карточка; облако и лоадаут целы' ($lc[0].info -like '*и надетые скины*' -and $lc[0].info -like '*Скины из кода: 4 из 8 у тебя есть*' -and @($lc | Where-Object { $_.what -eq 'Vandal' }).Count -eq 1 -and @($lc | Where-Object { $_.what -like 'Спрей*' }).Count -eq 2 -and @($lc | Where-Object { $_.what -eq 'Карточка' }).Count -eq 1 -and @($lc | Where-Object { $_.what -in 'Classic', 'Phantom', 'Титул' }).Count -eq 0 -and $script:cloud -ceq $cloudC -and -not $script:puts.Count) (Get-ListJson "code:$codeS")
$r = Invoke-Do "code:$codeS"
$g = @($script:lo.Guns) | Where-Object { $_.ID -eq $W1 }
Check 'код3: do code со скинами — настройки и только свои скины, одна отмена' ($r.ok -and $r.undo -and $r.message -like 'Настройки из кода перенесены*Скины надеты: 4*' -and $script:puts.Count -eq 1 -and $g.SkinLevelID -eq (HexId 'al2') -and $g.ChromaID -eq (HexId 'ac1') -and @($script:lo.ActiveExpressions)[0].AssetID -eq (HexId 's1') -and @($script:lo.ActiveExpressions)[1].AssetID -eq (HexId 'f9') -and @($script:lo.ActiveExpressions)[2].AssetID -eq (HexId 's2') -and $script:lo.Identity.PlayerCardID -eq (HexId 'k2') -and $script:lo.Identity.PlayerTitleID -eq (HexId 't9') -and $script:cloud -cne $cloudC) ($r | ConvertTo-Json -Compress)
$r = Invoke-Do 'undo'
Check 'код3: отмена вернула и настройки, и скины' ($r.ok -and $script:cloud -ceq $cloudC -and (@($script:lo.Guns) | Where-Object { $_.ID -eq $W1 }).SkinID -eq (HexId 'd1') -and $script:lo.Identity.PlayerCardID -eq (HexId 'k1')) ($r | ConvertTo-Json -Compress)
$script:catOff = $true; $script:puts = @()
$lc = Parse-Arr (Get-ListJson "code:$codeS")
$r = Invoke-Do "code:$codeS"
Check 'код3: нет каталога — скины не надеваются, настройки переносятся' ($lc[0].info -like '*Скины из кода не надену: Список предметов*' -and $r.ok -and $r.message -like 'Настройки из кода перенесены*Скины не надеты*' -and -not $script:puts.Count -and $script:cloud -cne $cloudC) ($r | ConvertTo-Json -Compress)
$null = Invoke-Do 'undo'
$script:catOff = $false; $script:lo = $loFriend
$r = Invoke-Do 'share:skins'
Check 'do share:skins: код со скинами, длина в сообщении' ($r.ok -and $r.code -like 'VALSET3:*' -and $r.message -like "Код скопирован ($($r.code.Length) символ*" -and (Read-ShareCode $r.code).Skins) ($r | ConvertTo-Json -Compress)

foreach ($f in $fnKeepC.Keys) { Set-Item "Function:\$f" $fnKeepC[$f] }
$script:CosNames = $cosKeep; $script:cloud = $cloudKeep; Remove-LastAction
# бэкапы лоадаута этого файла — не в счёт проверок наборов (они считают свежие бэкапы)
if (Test-Path $LoadoutBackupDir) { Get-ChildItem $LoadoutBackupDir -Filter *.json | Where-Object { $_.LastWriteTime -gt $codecT0 } | Remove-Item }
