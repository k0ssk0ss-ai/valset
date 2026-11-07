# sets.ps1 — «Скины»: наборы косметики аккаунта (скины оружия с цветом и уровнем, брелоки, спреи и флексы, карточка, титул, рамка).
# Сохранить текущее как набор → надеть набор (предпросмотр «было → станет», бэкап, отмена через last-action.json).
# Набор можно привязать к агенту: при включённом «Менять скины при выборе агента» (config.setsAuto, по умолчанию выкл)
# приложение по событию выбора агента (RiotEvents.cs, без опроса) зовёт `do loadoutauto` — надеваем набор этого агента.
# Запросы к Riot — loadout.ps1. Владение предметами проверяет Riot: чужое — запрос отклоняется целиком.
# Файлы: loadouts\sets.json — наборы; loadouts\auto.json — последний матч, где набор надет сам; loadouts\backups — бэкапы.

$LoadoutDir = Join-Path $Root 'loadouts'
$SetsPath = Join-Path $LoadoutDir 'sets.json'
$SetsAutoPath = Join-Path $LoadoutDir 'auto.json'
$LoadoutBackupDir = Join-Path $LoadoutDir 'backups'
$SetsMax = 30
$SetNameMax = 32

# ── Хранение ─────────────────────────────────────────────────────────────────

function Read-Sets {
    if (-not (Test-Path $SetsPath)) { return @() }
    try { @((Get-Content $SetsPath -Raw -Encoding UTF8 | ConvertFrom-Json).sets | Where-Object { $_ -and $_.id }) } catch { @() }
}

function Save-Sets($sets) {
    Write-FileSafe $SetsPath (ConvertTo-Json -InputObject ([ordered]@{ sets = @($sets) }) -Depth 8 -Compress)
}

function Find-Set([string]$id) {
    $x = @(Read-Sets) | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $x) { throw (L 'Такого набора нет. Список обновлён, выбери заново.' 'No such set. The list was refreshed, pick again.') }
    $x
}

# Имя набора из действия панели: base64url (UTF-8) — без пробелов и кавычек в командной строке.
function ConvertFrom-B64Url([string]$t) {
    $b = $t.Replace('-', '+').Replace('_', '/'); $b += '=' * ((4 - $b.Length % 4) % 4)
    try { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { throw (L 'Недопустимое имя набора.' 'Invalid set name.') }
}

function Test-SetName([string]$name) {
    $n = ($name -replace '\s+', ' ').Trim()
    if (-not $n) { throw (L 'Назови набор.' 'Name the set.') }
    if ($n.Length -gt $SetNameMax -or $n -match '[\x00-\x1f"]') { throw (L "Имя набора: до $SetNameMax символов, без кавычек." "Set name: up to $SetNameMax characters, no quotes.") }
    $n
}

# ── Лоадаут ↔ набор ─────────────────────────────────────────────────────────
# Лоадаут v3 (loadout.ps1): брелоки — Attachments у оружия (формат элемента не измерен — копируем как есть,
# сравниваем по JSON); спреи и флексы — ActiveExpressions, упорядоченные слоты (список целиком, порядок сохраняем).
# Старые наборы (v2): sprays → спреи по порядку в слоты-спреи текущего списка; брелоки v2 (Charm*) не переносятся.

$ExprSpray = 'd5f120f8-ff8c-4aac-92ea-f2b5acbe9475'   # TypeID спрея (AssetID найден в valorant-api /sprays)
$ExprFlex = '03a572de-4234-31ed-d344-ababa488f981'    # TypeID флекса (/flex)
$ZeroGuid = '00000000-0000-0000-0000-000000000000'

# Копия через JSON: без общих ссылок с исходником.
function Copy-Json($o) { if ($null -eq $o) { return $null }; ConvertTo-Json -InputObject $o -Depth 10 -Compress | ConvertFrom-Json }
function Get-JsonKey($o) { ConvertTo-Json -InputObject @(@($o) | Where-Object { $null -ne $_ }) -Depth 10 -Compress }

# Из лоадаута — только то, что входит в набор (уровень аккаунта, «скрыть уровень», инкогнито не трогаем).
function ConvertTo-SetItems($lo) {
    [ordered]@{
        guns = @(foreach ($g in @($lo.Guns)) { if ($g.ID) {
            [ordered]@{ ID = "$($g.ID)"; SkinID = "$($g.SkinID)"; SkinLevelID = "$($g.SkinLevelID)"; ChromaID = "$($g.ChromaID)"
                        Attachments = @(@($g.Attachments) | Where-Object { $null -ne $_ }) } } })
        expressions = @(foreach ($x in @($lo.ActiveExpressions)) { if ($x) { [ordered]@{ TypeID = "$($x.TypeID)"; AssetID = "$($x.AssetID)" } } })
        identity = [ordered]@{ PlayerCardID = "$($lo.Identity.PlayerCardID)"; PlayerTitleID = "$($lo.Identity.PlayerTitleID)"; PreferredLevelBorderID = "$($lo.Identity.PreferredLevelBorderID)" }
    }
}

function Set-Prop($o, [string]$k, $v) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force }
# Есть ли поле: набор из файла — объект, только что собранный — словарь.
function Test-Key($o, [string]$k) { if ($o -is [Collections.IDictionary]) { $o.Contains($k) } else { $null -ne $o -and $null -ne $o.PSObject.Properties[$k] } }

# Набор старого формата (v2: sprays, Charm*, без expressions).
function Test-SetV2($set) { -not (Test-Key $set 'expressions') -and (Test-Key $set 'sprays') }

# Текущий лоадаут + набор → новый лоадаут (копия; текущий не меняется). Пустой Attachments набора — брелок снят.
function Join-SetLoadout($cur, $set) {
    $new = Copy-Json $cur
    $guns = @{}; foreach ($g in @($new.Guns)) { $guns["$($g.ID)".ToLowerInvariant()] = $g }
    foreach ($sg in @($set.guns)) {
        $g = $guns["$($sg.ID)".ToLowerInvariant()]
        if (-not $g) { continue }   # оружия нет в лоадауте (новое или убранное) — пропускаем
        foreach ($k in 'SkinID', 'SkinLevelID', 'ChromaID') { if ($sg.$k) { Set-Prop $g $k $sg.$k } }
        if (Test-Key $sg 'Attachments') { Set-Prop $g 'Attachments' @(@($sg.Attachments) | Where-Object { $null -ne $_ } | ForEach-Object { Copy-Json $_ }) }
    }
    if ((Test-Key $set 'expressions') -and @($set.expressions).Count) {
        Set-Prop $new 'ActiveExpressions' @(foreach ($x in @($set.expressions)) { [pscustomobject]@{ TypeID = "$($x.TypeID)"; AssetID = "$($x.AssetID)" } })
    } elseif (Test-SetV2 $set) {
        # v2 → v3: спреи набора по порядку в слоты-спреи текущего списка; флексы и лишние спреи — как есть
        $q = New-Object Collections.Queue
        foreach ($x in @($set.sprays)) { if ($x.SprayID) { $q.Enqueue("$($x.SprayID)") } }
        foreach ($x in @($new.ActiveExpressions)) { if ($q.Count -and "$($x.TypeID)" -eq $ExprSpray) { Set-Prop $x 'AssetID' $q.Dequeue() } }
    }
    if (-not $new.Identity) { Set-Prop $new 'Identity' ([pscustomobject]@{}) }
    foreach ($k in 'PlayerCardID', 'PlayerTitleID', 'PreferredLevelBorderID') { if ($set.identity.$k) { Set-Prop $new.Identity $k $set.identity.$k } }
    $new
}

# Тело записи — лоадаут целиком, как у клиента (Guns, ActiveExpressions, Identity, Incognito, DynamicOptions и всё,
# что Riot добавит), кроме Subject/Version — они только в ответе.
function ConvertTo-LoadoutBody($lo) {
    $b = [ordered]@{ Guns = @($lo.Guns); ActiveExpressions = @($lo.ActiveExpressions); Identity = $lo.Identity; Incognito = [bool]$lo.Incognito }
    foreach ($p in $lo.PSObject.Properties) { if ($p.Name -notin 'Subject', 'Version' -and -not $b.Contains($p.Name)) { $b[$p.Name] = $p.Value } }
    $b
}

# Подпись скина: цвет (у вариантов в названии) или скин, плюс уровень, если не первый.
function Get-SkinLabel($names, $g) {
    if (-not $g) { return '' }
    $n = if ($g.ChromaID -and $names.Names["$($g.ChromaID)".ToLowerInvariant()]) { $names.Names["$($g.ChromaID)".ToLowerInvariant()] } else { Get-ItemName $names $g.SkinID }
    $n = ("$n" -replace '\s*[\r\n]+\s*', ' ').Trim()
    $lv = $names.Levels["$($g.SkinLevelID)".ToLowerInvariant()]
    if ($lv -gt 1) { "$n · $(L 'уровень' 'level') $lv" } else { $n }
}

# Подпись брелока: первый ID внутри Attachments, известный справочнику (брелок или его уровень), иначе «брелок».
function Get-AttachLabel($names, $att) {
    $a = @(@($att) | Where-Object { $null -ne $_ })
    if (-not $a.Count) { return '' }
    foreach ($m in [regex]::Matches((Get-JsonKey $a), '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}')) {
        $v = $names.Names[$m.Value.ToLowerInvariant()]
        if ($v) { return $v }
    }
    L 'брелок' 'buddy'
}

function Get-ExprName($names, $x) { if (-not $x -or -not $x.AssetID -or "$($x.AssetID)" -eq $ZeroGuid) { '' } else { Get-ItemName $names $x.AssetID } }

# Что поменяется: [{ what, old, new }] с названиями предметов (нет в справочнике — начало ID).
function Compare-Loadout($cur, $new, $names) {
    $rows = New-Object Collections.ArrayList
    $row = { param($w, $o, $n) [void]$rows.Add([ordered]@{ what = "$w"; old = "$o"; new = "$n" }) }
    $cg = @{}; foreach ($g in @($cur.Guns)) { $cg["$($g.ID)".ToLowerInvariant()] = $g }
    foreach ($g in @($new.Guns)) {
        $o = $cg["$($g.ID)".ToLowerInvariant()]; $w = Get-ItemName $names $g.ID
        if ("$($o.SkinID)|$($o.SkinLevelID)|$($o.ChromaID)" -ne "$($g.SkinID)|$($g.SkinLevelID)|$($g.ChromaID)") { & $row $w (Get-SkinLabel $names $o) (Get-SkinLabel $names $g) }
        if ((Get-JsonKey $o.Attachments) -ne (Get-JsonKey $g.Attachments)) { & $row "$w · $(L 'брелок' 'buddy')" (Get-AttachLabel $names $o.Attachments) (Get-AttachLabel $names $g.Attachments) }
    }
    $ce = @($cur.ActiveExpressions); $ne = @($new.ActiveExpressions); $cnt = @{}
    for ($i = 0; $i -lt [Math]::Max($ce.Count, $ne.Count); $i++) {
        $o = if ($i -lt $ce.Count) { $ce[$i] }; $x = if ($i -lt $ne.Count) { $ne[$i] }
        $t = "$(if ($x) { $x.TypeID } else { $o.TypeID })"
        $cnt[$t] = 1 + [int]$cnt[$t]
        $w = if ($t -eq $ExprSpray) { L 'Спрей' 'Spray' } elseif ($t -eq $ExprFlex) { L 'Флекс' 'Flex' } else { L 'Жест' 'Expression' }
        if ("$($o.TypeID)|$($o.AssetID)" -ne "$($x.TypeID)|$($x.AssetID)") { & $row "$w $($cnt[$t])" (Get-ExprName $names $o) (Get-ExprName $names $x) }
    }
    foreach ($k in @(@('PlayerCardID', (L 'Карточка' 'Player card')), @('PlayerTitleID', (L 'Титул' 'Title')), @('PreferredLevelBorderID', (L 'Рамка уровня' 'Level border')))) {
        if ("$($cur.Identity.($k[0]))" -ne "$($new.Identity.($k[0]))") { & $row $k[1] (Get-ItemName $names $cur.Identity.($k[0])) (Get-ItemName $names $new.Identity.($k[0])) }
    }
    , $rows.ToArray()
}

# ── Действия ─────────────────────────────────────────────────────────────────

function New-LoadoutBackup($s, [string]$json) {
    New-Item -ItemType Directory -Force $LoadoutBackupDir | Out-Null
    $path = Join-Path $LoadoutBackupDir ('{0}_{1:yyyyMMdd-HHmmss}.json' -f (Short $s.Puuid), (Get-Date))
    Write-FileSafe $path $json
    Get-ChildItem $LoadoutBackupDir -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -SkipLast 30 | Remove-Item
    $path
}

# `do loadoutsave:<имя base64url>` — текущий лоадаут как набор; то же имя — набор обновляется (агент остаётся).
# `loadoutsave:<имя>:<коллекция>` — набор только из своих скинов коллекции (collections.ps1).
function Invoke-SetSave([string]$name, [string]$theme = '') {
    $name = Test-SetName $name
    $s = Connect-Session
    $items = if ($theme) { Get-CollSetItems $s $theme } else { ConvertTo-SetItems (Get-Loadout $s) }
    $sets = @(Read-Sets)
    $old = $sets | Where-Object { "$($_.name)" -eq $name } | Select-Object -First 1
    if (-not $old -and $sets.Count -ge $SetsMax) { throw (L "Наборов уже $SetsMax. Удали ненужный." "Already $SetsMax sets. Delete one first.") }
    $id = if ($old) { $old.id } else { [Guid]::NewGuid().ToString('N').Substring(0, 8) }
    $e = [ordered]@{ id = $id; name = $name; agent = $(if ($old) { "$($old.agent)" } else { '' }); puuid = $s.Puuid; saved = (Get-Stamp)
                     guns = $items.guns; expressions = $items.expressions; identity = $items.identity }
    Save-UndoFiles @($SetsPath)
    Save-Sets @(@($sets | Where-Object { $_.id -ne $id }) + $e)
    Log "набор сохранён: $name ($(Short $s.Puuid), оружия $(@($items.guns).Count))"
    if ($old) { L "Набор «$name» обновлён" "Set `“$name`” updated" } else { L "Набор «$name» сохранён" "Set `“$name`” saved" }
}

# Надеть набор: бэкап, точка отмены (в `valset do`), запись. Возвращает сообщение для панели.
function Invoke-SetApply([string]$id, $s = $null) {
    $set = Find-Set $id
    if (-not $s) { $s = Connect-Session }
    $cur = Get-Loadout $s
    $n = (Write-LoadoutChange $s $cur (Join-SetLoadout $cur $set) "набор «$($set.name)»").Count
    if (-not $n) { return $(if ($script:ForcedWrite) { L "Набор «$($set.name)» записан заново" "Set `“$($set.name)`” written again" } else { L "Набор «$($set.name)» уже надет" "Set `“$($set.name)`” is already on" }) }
    L "Набор «$($set.name)» надет: $n $(Get-Plural $n 'изменение' 'изменения' 'изменений'). Скины видны после входа в матч или стрельбище" "Set `“$($set.name)`” on: $n change$(if ($n -ne 1) { 's' }). Skins show after you enter a match or the range"
}

# Записать новый лоадаут: точка отмены (в `valset do`), бэкап, PUT. Возвращает строки «было → станет»; пусто — менять нечего.
# Общая для наборов и «Всех скинов» (skins.ps1).
function Write-LoadoutChange($s, $cur, $new, [string]$what) {
    $rows = Compare-Loadout $cur $new (Get-CosmeticNames)
    $script:ForcedWrite = $false
    if (-not $rows.Count) { if (-not $script:ForceWrite) { return }; $script:ForcedWrite = $true }   # !force: писать и без отличий
    $curJson = ConvertTo-Json -InputObject $cur -Depth 10 -Compress
    if ($script:UndoAction) { Write-UndoExtra 'loadout' ([ordered]@{ puuid = $s.Puuid; loadout = $curJson }) }
    $bk = New-LoadoutBackup $s $curJson
    $null = Set-Loadout $s (ConvertTo-LoadoutBody $new)
    Log "$what → $(Get-AccountLabel $s.Puuid): $($rows.Count) изм., бэкап $(Split-Path $bk -Leaf)"
    , $rows
}

# Откат точки отмены 'loadout' (из Restore-UndoExtra): прежний лоадаут целиком.
function Restore-LoadoutUndo($a) {
    $s = Connect-Session
    if ($s.Puuid -ne $a.data.puuid) { throw (L "Отменить можно только в том аккаунте, где было действие ($(Get-AccountLabel $a.data.puuid))." "Undo works only on the account where it happened ($(Get-AccountLabel $a.data.puuid)).") }
    $null = Set-Loadout $s (ConvertTo-LoadoutBody ($a.data.loadout | ConvertFrom-Json))
}

function Invoke-SetBind([string]$id, [string]$agent) {
    $set = Find-Set $id
    $agent = if ($agent -eq 'none') { '' } else { $agent.ToLowerInvariant() }
    if ($agent -and $agent -notmatch '^[0-9a-f-]{36}$') { throw (L 'Не удалось выбрать агента.' 'Could not pick the agent.') }
    $sets = @(Read-Sets)
    Save-UndoFiles @($SetsPath)
    foreach ($x in $sets) {
        if ($x.id -eq $id) { Set-Prop $x 'agent' $agent }
        elseif ($agent -and "$($x.agent)" -eq $agent) { Set-Prop $x 'agent' '' }   # у агента — один набор
    }
    Save-Sets $sets
    if (-not $agent) { return (L "Набор «$($set.name)» отвязан от агента" "Set `“$($set.name)`” unbound from the agent") }
    $an = Get-AgentName (Get-CosmeticNames) $agent
    L "Набор «$($set.name)» для агента $an" "Set `“$($set.name)`” for $an"
}

function Invoke-SetDelete([string]$id) {
    $set = Find-Set $id
    Save-UndoFiles @($SetsPath)
    Save-Sets @(@(Read-Sets) | Where-Object { $_.id -ne $id })
    Log "набор удалён: $($set.name)"
    L "Набор «$($set.name)» удалён" "Set `“$($set.name)`” deleted"
}

# ── Автосмена при выборе агента ──────────────────────────────────────────────

# Решение (без сети): какой набор надеть. $pre — Get-PregameAgent; $last — auto.json (матч, где уже надевали).
function Get-AutoSetChoice([bool]$enabled, $sets, $pre, $last) {
    if (-not $enabled -or -not $pre -or -not $pre.Locked -or -not $pre.Agent) { return $null }
    if ($last -and "$($last.match)" -eq $pre.MatchId) { return $null }   # в этом матче уже решали
    @($sets) | Where-Object { $_ -and "$($_.agent)" -eq $pre.Agent } | Select-Object -First 1
}

function Read-AutoState { if (Test-Path $SetsAutoPath) { try { Get-Content $SetsAutoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} } }

# `do loadoutauto` — от приложения на событие выбора агента. В ответе: done — по этому матчу решено (агент
# зафиксирован), больше не звать; applied — набор надевали (сообщение — итог).
function Invoke-DoLoadoutAuto($r) {
    if (-not (Get-Config).setsAuto) { $r['done'] = $true; return '' }
    $s = Get-Session
    if (-not $s) { return '' }
    $pre = Get-PregameAgent $s
    if ($pre -and $pre.Locked) { $r['done'] = $true }
    $set = Get-AutoSetChoice $true (Read-Sets) $pre (Read-AutoState)
    if (-not $set) { return '' }
    Write-FileSafe $SetsAutoPath (ConvertTo-Json -InputObject ([ordered]@{ match = $pre.MatchId; agent = $pre.Agent; set = $set.id; at = (Get-Stamp) }) -Compress)
    Remove-LastAction; $script:UndoAction = 'loadoutauto'
    $r['applied'] = $true
    $an = Get-AgentName (Get-CosmeticNames) $pre.Agent
    try { $msg = "${an}: $(Invoke-SetApply $set.id $s)" }
    catch { if ((Get-Config).notify) { Send-Toast 'VALSET' "${an}: $($_.Exception.Message)" }; throw }
    if ((Get-Config).notify) { Send-Toast 'VALSET' $msg }
    $msg
}

# ── Списки для панели ────────────────────────────────────────────────────────

function Get-ListLoadouts {
    $names = Get-CosmeticNames; $cs = Get-Session
    @(@(Read-Sets) | Sort-Object { "$($_.name)" } | ForEach-Object {
        $hint = @(
            if ($_.agent) { Get-AgentName $names $_.agent } else { L 'без агента' 'no agent' }
            "$(L 'оружий:' 'weapons:') $(@($_.guns).Count)"
            if ($cs -and $_.puuid -and $_.puuid -ne $cs.Puuid) { "$(L 'с аккаунта' 'from') $(Get-AccountLabel $_.puuid)" }
        ) -join ' · '
        [ordered]@{ id = "$($_.id)"; name = "$($_.name)"; agent = "$($_.agent)"; hint = $hint }
    })
}

function Get-ListAgents { @(@((Get-CosmeticNames).Agents) | ForEach-Object { [ordered]@{ id = "$($_.id)"; name = "$($_.name)" } }) }

# Предпросмотр набора: первый элемент — что за набор и аккаунт (same — уже надет), дальше «было → станет».
function Get-ListLoadoutPreview([string]$id) {
    try {
        $set = Find-Set $id
        $s = Connect-Session
        $cur = Get-Loadout $s; $names = Get-CosmeticNames
        $rows = Compare-Loadout $cur (Join-SetLoadout $cur $set) $names
        $info = "$(L 'Набор' 'Set') «$($set.name)»$(if ($set.agent) { " · $(Get-AgentName $names $set.agent)" })"
        if (Test-SetV2 $set) { $info += "`n" + (L 'Это старый набор: брелоки из него не надеваются. Надень их и сохрани набор заново.' 'This is an old set: its buddies are not put on. Put them on and save the set again.') }
        if ($set.puuid -and $set.puuid -ne $s.Puuid) { $info += "`n" + (L "Сохранён на другом аккаунте ($(Get-AccountLabel $set.puuid)). Надеются только предметы, которые есть здесь." "Saved on another account ($(Get-AccountLabel $set.puuid)). Only items owned here are put on.") }
        $pics = @(); try { $pics = @(Get-SetPics $set) } catch { Log "картинки набора: $($_.Exception.Message)" }   # без каталога — без картинок
        @([ordered]@{ info = $info; account = (Get-AccountLabel $s.Puuid); same = (-not $rows.Count); pics = $pics }) + @($rows)
    } catch { @([ordered]@{ error = $_.Exception.Message }) }
}
