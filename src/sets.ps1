# sets.ps1 — «Скины»: наборы косметики аккаунта (скины оружия с цветом и уровнем, брелоки, спреи, карточка, титул, рамка).
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
    if (-not $x) { throw (L 'Такого набора нет — список обновлён, выбери заново.' 'No such set — the list was refreshed, pick again.') }
    $x
}

# Имя набора из действия панели: base64url (UTF-8) — без пробелов и кавычек в командной строке.
function ConvertFrom-B64Url([string]$t) {
    $b = $t.Replace('-', '+').Replace('_', '/'); $b += '=' * ((4 - $b.Length % 4) % 4)
    try { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { throw (L 'Некорректное имя набора.' 'Invalid set name.') }
}

function Test-SetName([string]$name) {
    $n = ($name -replace '\s+', ' ').Trim()
    if (-not $n) { throw (L 'Назови набор.' 'Name the set.') }
    if ($n.Length -gt $SetNameMax -or $n -match '[\x00-\x1f"]') { throw (L "Имя набора — до $SetNameMax символов, без кавычек." "Set name — up to $SetNameMax characters, no quotes.") }
    $n
}

# ── Лоадаут ↔ набор ─────────────────────────────────────────────────────────

# Из лоадаута — только то, что входит в набор (уровень аккаунта, «скрыть уровень» и т. п. не трогаем).
function ConvertTo-SetItems($lo) {
    [ordered]@{
        guns = @(foreach ($g in @($lo.Guns)) { if ($g.ID) {
            [ordered]@{ ID = "$($g.ID)"; SkinID = "$($g.SkinID)"; SkinLevelID = "$($g.SkinLevelID)"; ChromaID = "$($g.ChromaID)"
                        CharmInstanceID = "$($g.CharmInstanceID)"; CharmID = "$($g.CharmID)"; CharmLevelID = "$($g.CharmLevelID)" } } })
        sprays = @(foreach ($x in @($lo.Sprays)) { if ($x.EquipSlotID) { [ordered]@{ EquipSlotID = "$($x.EquipSlotID)"; SprayID = "$($x.SprayID)"; SprayLevelID = "$($x.SprayLevelID)" } } })
        identity = [ordered]@{ PlayerCardID = "$($lo.Identity.PlayerCardID)"; PlayerTitleID = "$($lo.Identity.PlayerTitleID)"; PreferredLevelBorderID = "$($lo.Identity.PreferredLevelBorderID)" }
    }
}

function Set-Prop($o, [string]$k, $v) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force }

# Текущий лоадаут + набор → новый лоадаут (копия; текущий не меняется). Пустое поле набора — «нет» (брелок снят).
function Join-SetLoadout($cur, $set) {
    $new = ConvertTo-Json -InputObject $cur -Depth 10 -Compress | ConvertFrom-Json
    $guns = @{}; foreach ($g in @($new.Guns)) { $guns["$($g.ID)".ToLowerInvariant()] = $g }
    foreach ($sg in @($set.guns)) {
        $g = $guns["$($sg.ID)".ToLowerInvariant()]
        if (-not $g) { continue }   # оружия нет в лоадауте (новое или убранное) — пропускаем
        foreach ($k in 'SkinID', 'SkinLevelID', 'ChromaID') { if ($sg.$k) { Set-Prop $g $k $sg.$k } }
        if ($sg.CharmID) { foreach ($k in 'CharmInstanceID', 'CharmID', 'CharmLevelID') { Set-Prop $g $k $sg.$k } }
        else { foreach ($k in 'CharmInstanceID', 'CharmID', 'CharmLevelID') { $g.PSObject.Properties.Remove($k) } }
    }
    $sp = @{}; foreach ($x in @($new.Sprays)) { $sp["$($x.EquipSlotID)".ToLowerInvariant()] = $x }
    $add = @()
    foreach ($ss in @($set.sprays)) {
        $x = $sp["$($ss.EquipSlotID)".ToLowerInvariant()]
        $lv = if ($ss.SprayLevelID) { $ss.SprayLevelID } else { $null }
        if ($x) { Set-Prop $x 'SprayID' $ss.SprayID; Set-Prop $x 'SprayLevelID' $lv }
        else { $add += [pscustomobject]@{ EquipSlotID = $ss.EquipSlotID; SprayID = $ss.SprayID; SprayLevelID = $lv } }
    }
    if ($add) { Set-Prop $new 'Sprays' (@($new.Sprays) + $add) }
    if (-not $new.Identity) { Set-Prop $new 'Identity' ([pscustomobject]@{}) }
    foreach ($k in 'PlayerCardID', 'PlayerTitleID', 'PreferredLevelBorderID') { if ($set.identity.$k) { Set-Prop $new.Identity $k $set.identity.$k } }
    $new
}

# Тело записи — как у клиента: оружие, спреи, профиль, инкогнито (Subject/Version — только в ответе).
function ConvertTo-LoadoutBody($lo) {
    [ordered]@{ Guns = @($lo.Guns); Sprays = @($lo.Sprays); Identity = $lo.Identity; Incognito = [bool]$lo.Incognito }
}

# Подпись скина: цвет (у вариантов в названии) или скин, плюс уровень, если не первый.
function Get-SkinLabel($names, $g) {
    if (-not $g) { return '' }
    $n = if ($g.ChromaID -and $names.Names["$($g.ChromaID)".ToLowerInvariant()]) { $names.Names["$($g.ChromaID)".ToLowerInvariant()] } else { Get-ItemName $names $g.SkinID }
    $n = ("$n" -replace '\s*[\r\n]+\s*', ' ').Trim()
    $lv = $names.Levels["$($g.SkinLevelID)".ToLowerInvariant()]
    if ($lv -gt 1) { "$n · $(L 'ур.' 'lvl') $lv" } else { $n }
}

# Что поменяется: [{ what, old, new }] с названиями предметов (нет в справочнике — начало ID).
function Compare-Loadout($cur, $new, $names) {
    $rows = New-Object Collections.ArrayList
    $row = { param($w, $o, $n) [void]$rows.Add([ordered]@{ what = "$w"; old = "$o"; new = "$n" }) }
    $cg = @{}; foreach ($g in @($cur.Guns)) { $cg["$($g.ID)".ToLowerInvariant()] = $g }
    foreach ($g in @($new.Guns)) {
        $o = $cg["$($g.ID)".ToLowerInvariant()]; $w = Get-ItemName $names $g.ID
        if ("$($o.SkinID)|$($o.SkinLevelID)|$($o.ChromaID)" -ne "$($g.SkinID)|$($g.SkinLevelID)|$($g.ChromaID)") { & $row $w (Get-SkinLabel $names $o) (Get-SkinLabel $names $g) }
        if ("$($o.CharmID)|$($o.CharmLevelID)" -ne "$($g.CharmID)|$($g.CharmLevelID)") { & $row "$w · $(L 'брелок' 'buddy')" (Get-ItemName $names $o.CharmID) (Get-ItemName $names $g.CharmID) }
    }
    $cs = @{}; foreach ($x in @($cur.Sprays)) { $cs["$($x.EquipSlotID)".ToLowerInvariant()] = $x }
    $i = 0
    foreach ($x in @($new.Sprays)) {
        $i++; $o = $cs["$($x.EquipSlotID)".ToLowerInvariant()]
        if ("$($o.SprayID)" -ne "$($x.SprayID)") { & $row "$(L 'Спрей' 'Spray') $i" (Get-ItemName $names $o.SprayID) (Get-ItemName $names $x.SprayID) }
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
function Invoke-SetSave([string]$name) {
    $name = Test-SetName $name
    $s = Connect-Session
    $items = ConvertTo-SetItems (Get-Loadout $s)
    $sets = @(Read-Sets)
    $old = $sets | Where-Object { "$($_.name)" -eq $name } | Select-Object -First 1
    if (-not $old -and $sets.Count -ge $SetsMax) { throw (L "Наборов уже $SetsMax — удали ненужный." "Already $SetsMax sets — delete one first.") }
    $id = if ($old) { $old.id } else { [Guid]::NewGuid().ToString('N').Substring(0, 8) }
    $e = [ordered]@{ id = $id; name = $name; agent = $(if ($old) { "$($old.agent)" } else { '' }); puuid = $s.Puuid; saved = (Get-Stamp)
                     guns = $items.guns; sprays = $items.sprays; identity = $items.identity }
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
    $new = Join-SetLoadout $cur $set
    $n = (Compare-Loadout $cur $new (Get-CosmeticNames)).Count
    if (-not $n) { return (L "Набор «$($set.name)» уже надет" "Set `“$($set.name)`” is already on") }
    $curJson = ConvertTo-Json -InputObject $cur -Depth 10 -Compress
    if ($script:UndoAction) { Write-UndoExtra 'loadout' ([ordered]@{ puuid = $s.Puuid; loadout = $curJson }) }
    $bk = New-LoadoutBackup $s $curJson
    $null = Set-Loadout $s (ConvertTo-LoadoutBody $new)
    Log "набор «$($set.name)» → $(Get-AccountLabel $s.Puuid): $n изм., бэкап $(Split-Path $bk -Leaf)"
    L "Набор «$($set.name)» надет: $n $(Get-Plural $n 'изменение' 'изменения' 'изменений')" "Set `“$($set.name)`” on: $n change$(if ($n -ne 1) { 's' })"
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
    if ($agent -and $agent -notmatch '^[0-9a-f-]{36}$') { throw (L 'Некорректный агент.' 'Invalid agent.') }
    $sets = @(Read-Sets)
    Save-UndoFiles @($SetsPath)
    foreach ($x in $sets) {
        if ($x.id -eq $id) { Set-Prop $x 'agent' $agent }
        elseif ($agent -and "$($x.agent)" -eq $agent) { Set-Prop $x 'agent' '' }   # у агента — один набор
    }
    Save-Sets $sets
    if (-not $agent) { return (L "Набор «$($set.name)» отвязан от агента" "Set `“$($set.name)`” unbound from the agent") }
    $an = Get-AgentName (Get-CosmeticNames) $agent
    L "Набор «$($set.name)» — для агента $an" "Set `“$($set.name)`” — for $an"
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
    try { $msg = "$an — $(Invoke-SetApply $set.id $s)" }
    catch { if ((Get-Config).notify) { Send-Toast 'VALSET' "$an — $($_.Exception.Message)" }; throw }
    if ((Get-Config).notify) { Send-Toast 'VALSET' $msg }
    $msg
}

# ── Списки для панели ────────────────────────────────────────────────────────

function Get-ListLoadouts {
    $names = Get-CosmeticNames; $cs = Get-Session
    @(@(Read-Sets) | Sort-Object { "$($_.name)" } | ForEach-Object {
        $hint = @(
            if ($_.agent) { Get-AgentName $names $_.agent } else { L 'без агента' 'no agent' }
            "$(L 'оружия' 'weapons') $(@($_.guns).Count)"
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
        if ($set.puuid -and $set.puuid -ne $s.Puuid) { $info += "`n" + (L "Сохранён на другом аккаунте ($(Get-AccountLabel $set.puuid)) — Riot примет только предметы, которые есть здесь." "Saved on another account ($(Get-AccountLabel $set.puuid)) — Riot accepts only items owned here.") }
        @([ordered]@{ info = $info; account = (Get-AccountLabel $s.Puuid); same = (-not $rows.Count) }) + @($rows)
    } catch { @([ordered]@{ error = $_.Exception.Message }) }
}
