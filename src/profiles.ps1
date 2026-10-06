# profiles.ps1 — несколько эталонов, обмен кодом, откат аккаунта из бэкапа.
# Активный набор — файлы в корне (profile.json, source.txt, graphics\): с ними работает всё остальное.
# Сохранённые — копии в profiles\<имя>\. При переключении активный сначала сохраняется под своим именем со всеми правками.

$ProfilesDir = Join-Path $Root 'profiles'
$ActivePath  = Join-Path $Root 'active.txt'
$ExportDir   = Join-Path $Root 'export'

function Get-ActiveName { if (Test-Path $ActivePath) { (Get-Content $ActivePath -Raw -Encoding UTF8).Trim() } }

function Get-ProfileNames {
    @(Get-ChildItem $ProfilesDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'profile.json') } | ForEach-Object Name)
}

function Copy-ProfileFiles([string]$from, [string]$to) {
    New-Item -ItemType Directory -Force $to | Out-Null
    foreach ($f in 'profile.json', 'source.txt') {
        $src = Join-Path $from $f; $dst = Join-Path $to $f
        if (Test-Path $src) { Copy-Item $src $dst -Force } elseif (Test-Path $dst) { Remove-Item -LiteralPath $dst }
    }
    $g = Join-Path $to 'graphics'; $sg = Join-Path $from 'graphics'
    if (Test-Path $g) { Remove-Item -LiteralPath $g -Recurse -Force }
    if (Test-Path $sg) { Copy-Item $sg $g -Recurse -Force }
}

function Save-ProfileAs([string]$name) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои».' 'Your settings are not saved yet — use “Save as mine” first.') }
    Copy-ProfileFiles $Root (Join-Path $ProfilesDir $name)
    Set-Content $ActivePath $name -Encoding UTF8
    Log "активный набор сохранён как «$name»"
}

function Use-Profile([string]$name) {
    $act = Get-ActiveName
    if ($act -eq $name) { return }
    if (Test-Path $ProfilePath) {
        if (-not $act) { $act = (L 'прежний-{0:ddMM-HHmm}' 'previous-{0:ddMM-HHmm}') -f (Get-Date) }
        Copy-ProfileFiles $Root (Join-Path $ProfilesDir $act)
        New-HistoryPoint (L "до смены набора на «$name»" "before switching to set `“$name`”")
    }
    Copy-ProfileFiles (Join-Path $ProfilesDir $name) $Root
    Set-Content $ActivePath $name -Encoding UTF8
    Log "активный набор: «$name» (прошлый сохранён как «$act»)"
}

function Read-ProfileName([string]$default) {
    Write-Host -NoNewline "    › $(L 'имя' 'name')$(if ($default) { " (Enter — $default)" }): " -ForegroundColor Red
    $n = "$([Console]::ReadLine())".Trim()
    if (-not $n) { $n = $default }
    $n = ($n -replace '[\\/:*?"<>|]', '').Trim()
    if ($n.Length -gt 24) { $n = $n.Substring(0, 24).Trim() }
    if (-not $n) { throw (L 'Имя пустое — ничего не сохранено.' 'Empty name — nothing saved.') }
    $n
}

# ── Код для обмена ───────────────────────────────────────────────────────────
# VALSET2: + deflate(JSON), упакованный по 14 бит в символ: иероглифы CJK U+4E00…U+8DFF
# (все назначены, нормализация Юникода их не меняет). Это в 2,3 раза короче base64 (6 бит).
# Графика — текстом (сжимается, в отличие от base64). Служебные LastSeen* не экспортируются.
# Старые коды VALSET1: (base64) по-прежнему читаются.

function Export-Profile([switch]$BindsOnly, [switch]$OneCrosshair) {
    $code = New-ExportCode -BindsOnly:$BindsOnly -OneCrosshair:$OneCrosshair
    $kind = if ($BindsOnly) { 'binds' } elseif ($OneCrosshair) { 'full-1cross' } else { 'full' }
    New-Item -ItemType Directory -Force $ExportDir | Out-Null
    $file = Join-Path $ExportDir ('{0}-{1:yyyyMMdd-HHmm}.txt' -f $kind, (Get-Date))
    [IO.File]::WriteAllText($file, $code, (New-Object Text.UTF8Encoding $false))
    Set-Clipboard -Value $code
    Log "экспорт ($kind): $($code.Length) символов → $(Split-Path $file -Leaf)"
    @{ File = $file; Length = $code.Length }
}

function Compress-Bytes([string]$s) {
    $ms = New-Object IO.MemoryStream
    $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionLevel]::Optimal)
    $b = [Text.Encoding]::UTF8.GetBytes($s); $ds.Write($b, 0, $b.Length); $ds.Close()
    , $ms.ToArray()
}

function Expand-Bytes([byte[]]$b) {
    $ds = New-Object IO.Compression.DeflateStream((New-Object IO.MemoryStream(, $b)), [IO.Compression.CompressionMode]::Decompress)
    $sr = New-Object IO.StreamReader($ds, [Text.Encoding]::UTF8)
    $s = $sr.ReadToEnd(); $sr.Close(); $s
}

# Байты → символы по 14 бит. '=' в конце: последний символ несёт лишний байт-заполнитель.
function ConvertTo-Cjk([byte[]]$b) {
    $sb = New-Object Text.StringBuilder
    $acc = 0; $bits = 0
    foreach ($x in $b) {
        $acc = ($acc -shl 8) -bor $x; $bits += 8
        if ($bits -ge 14) { $bits -= 14; [void]$sb.Append([char](0x4E00 + (($acc -shr $bits) -band 0x3FFF))); $acc = $acc -band ((1 -shl $bits) - 1) }
    }
    if ($bits -gt 0) { [void]$sb.Append([char](0x4E00 + (($acc -shl (14 - $bits)) -band 0x3FFF))) }
    if ([Math]::Floor($sb.Length * 14 / 8) -gt $b.Length) { [void]$sb.Append('=') }
    $sb.ToString()
}

function ConvertFrom-Cjk([string]$t) {
    $extra = $t.EndsWith('=')
    $out = New-Object Collections.Generic.List[byte]
    $acc = 0; $bits = 0
    foreach ($ch in $t.ToCharArray()) {
        $v = [int]$ch - 0x4E00
        if ($v -lt 0 -or $v -gt 0x3FFF) { continue }   # пробелы и переносы, вставленные мессенджером
        $acc = ($acc -shl 14) -bor $v; $bits += 14
        while ($bits -ge 8) { $bits -= 8; $out.Add([byte](($acc -shr $bits) -band 0xFF)); $acc = $acc -band ((1 -shl $bits) - 1) }
    }
    if ($extra -and $out.Count) { $out.RemoveAt($out.Count - 1) }
    , $out.ToArray()
}

function New-ExportCode([switch]$BindsOnly, [switch]$OneCrosshair) {
    $p = Read-Profile
    $data = [ordered]@{ v = 2; kind = $(if ($BindsOnly) { 'binds' } else { 'full' }); name = "$(Get-ActiveName)" }
    if ($BindsOnly) {
        $q = [ordered]@{}
        foreach ($k in $BindKeys) { if ($p.PSObject.Properties[$k]) { $q[$k] = $p.$k } }
        $data.profile = $q
    } else {
        if ($p.PSObject.Properties['stringSettings']) {
            $p.stringSettings = @($p.stringSettings | Where-Object { $_.settingEnum -notmatch '::LastSeen' })
        }
        if ($OneCrosshair) { Select-ActiveCrosshair $p }
        $data.profile = $p
        if (Test-GraphicsSaved) {
            $data.gfxIniT  = [IO.File]::ReadAllText($GfxIni)
            $data.gfxRiotT = [IO.File]::ReadAllText($GfxRiot)
        }
    }
    'VALSET2:' + (ConvertTo-Cjk (Compress-Bytes (ConvertTo-Json -InputObject $data -Depth 32 -Compress)))
}

function Read-ImportCode([string]$text) {
    $t = "$text".Trim()
    try {
        if ($t.StartsWith('VALSET2:'))     { $d = Expand-Bytes (ConvertFrom-Cjk $t.Substring(8)) | ConvertFrom-Json }
        elseif ($t.StartsWith('VALSET1:')) { $d = Expand-Pref $t.Substring(8) | ConvertFrom-Json }
        else { $d = $null }
    } catch { throw (L 'Код повреждён: скопирован не полностью?' 'The code is damaged: copied only partly?') }
    if ($null -eq $d -and -not $t.StartsWith('VALSET')) { throw (L 'В буфере обмена нет кода VALSET — скопируй его целиком (начинается с VALSET).' 'No VALSET code in the clipboard — copy all of it (it starts with VALSET).') }
    if ($d.v -notin 1, 2 -or -not $d.profile) { throw (L 'Код от другой версии VALSET или повреждён.' 'The code is from another VALSET version or damaged.') }
    $d
}
function Invoke-Import {
    $d = Read-ImportCode (Get-Clipboard -Raw)
    $from = if ($d.name) { L ", набор «$($d.name)»" ", set `“$($d.name)`”" } else { '' }
    if ($d.kind -eq 'binds') {
        Write-Field (L 'В коде' 'In the code') "$(L 'только бинды' 'binds only')$from"
        $p = Read-Profile
        $new = $p | ConvertTo-Json -Depth 32 | ConvertFrom-Json
        foreach ($k in $BindKeys) { $new | Add-Member -NotePropertyName $k -NotePropertyValue $d.profile.$k -Force }
        $diff = Compare-Prefs $p $new -BindsOnly
        if (-not $diff.Count) { Write-Ok (L 'Бинды в коде такие же, как в активном наборе' 'The binds in the code are the same as yours'); return }
        Show-Diff $diff
        if (-not (Confirm-Key (L 'Заменить бинды активного набора? Остальные настройки не тронутся' 'Replace your binds? Other settings stay untouched'))) { Write-Note (L 'отменено' 'cancelled'); return }
        $script:ProfileBackedUp = $false; Protect-Profile (L 'до импорта биндов из кода' 'before importing binds from a code')
        Save-Profile $new
        Log "импорт биндов в активный набор ($($diff.Count) изм.)"
        Write-Ok (L 'Бинды записаны в твои настройки. На аккаунт — «Перенести мои»' 'Binds written into your settings. To an account — “Apply mine”')
        return
    }
    Write-Field (L 'В коде' 'In the code') "$(L 'все настройки' 'all settings')$(if ($d.gfxIni -or $d.gfxIniT) { L ' + графика' ' + graphics' })$from"
    Write-Host ''
    $n = Read-ProfileName $(if ($d.name) { "$($d.name)" } else { (L 'импорт-{0:ddMM}' 'import-{0:ddMM}') -f (Get-Date) })
    $dir = Join-Path $ProfilesDir $n
    if ($n -eq (Get-ActiveName)) { throw (L "«$n» — активный набор; выбери другое имя." "`“$n`” is the active set; pick another name.") }
    if ((Test-Path $dir) -and -not (Confirm-Key (L "«$n» уже есть. Перезаписать?" "`“$n`” already exists. Overwrite?"))) { Write-Note (L 'отменено' 'cancelled'); return }
    if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content (Join-Path $dir 'profile.json') (ConvertTo-Json -InputObject $d.profile -Depth 32 -Compress) -Encoding UTF8
    $g = Join-Path $dir 'graphics'
    if ($d.gfxIniT) {
        New-Item -ItemType Directory -Force $g | Out-Null
        $utf = New-Object Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path $g 'GameUserSettings.ini'), $d.gfxIniT, $utf)
        [IO.File]::WriteAllText((Join-Path $g 'RiotUserSettings.graphics.txt'), $d.gfxRiotT, $utf)
    } elseif ($d.gfxIni) {
        New-Item -ItemType Directory -Force $g | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $g 'GameUserSettings.ini'), [Convert]::FromBase64String($d.gfxIni))
        [IO.File]::WriteAllBytes((Join-Path $g 'RiotUserSettings.graphics.txt'), [Convert]::FromBase64String($d.gfxRiot))
    }
    Log "импорт набора «$n»"
    Write-Ok (L "Сохранён как «$n». Чтобы применять его — выбери в списке → «Сделать активным»" "Saved as `“$n`”. To use it — pick it in the list → `“Make active`”")
}

# ── Экраны ───────────────────────────────────────────────────────────────────

function Show-ProfileActions([string]$name) {
    $act = $name -eq (Get-ActiveName)
    $items = @(
        if (-not $act) { New-MenuEntry (L 'Сделать активным' 'Make active') (L 'текущий активный сохранится под своим именем' 'the current one is kept under its name') 'use' }
        New-MenuEntry (L 'Удалить' 'Delete') $(if ($act) { L 'нельзя: он активный' 'not possible: it is active' } else { L 'только эту копию' 'only this copy' }) 'del'
    )
    $i = Select-Item "$(L 'НАБОР' 'SET') «$name»" $items
    if ($i -lt 0) { return $false }
    Write-Screen "$(L 'НАБОР' 'SET') «$name»"
    switch ($items[$i].Id) {
        'use' {
            Use-Profile $name
            Write-Ok "$(L 'Активный набор' 'Active set') — «$name»"
            Write-Note (L 'на аккаунт — «Перенести мои» или автоперенос' 'to an account — “Apply mine” or auto-apply')
        }
        'del' {
            if ($act) { Write-Note (L 'активный набор не удаляется — сначала сделай активным другой' 'the active set cannot be deleted — make another one active first') }
            elseif (Confirm-Key "$(L 'Удалить' 'Delete') «$name»?") {
                Remove-Item -LiteralPath (Join-Path $ProfilesDir $name) -Recurse -Force
                Log "набор «$name» удалён"
                Write-Ok "«$name» $(L 'удалён' 'deleted')"
            } else { Write-Note (L 'отменено' 'cancelled') }
        }
    }
    $true
}

function Show-Profiles {
    $sel = 1
    while ($true) {
        $act = Get-ActiveName
        $items = @(New-MenuSep (L 'СОХРАНЁННЫЕ' 'SAVED'))
        foreach ($n in Get-ProfileNames) {
            $t = (Get-Item (Join-Path $ProfilesDir "$n\profile.json")).LastWriteTime
            $items += New-MenuEntry $n $(if ($n -eq $act) { L '• активный' '• active' } else { '{0:dd.MM HH:mm}' -f $t }) "p:$n"
        }
        $items += New-MenuSep (L 'ДЕЙСТВИЯ' 'ACTIONS')
        $items += New-MenuEntry (L 'Сохранить активный как…' 'Save active as…') (L 'копия под именем, чтобы переключаться' 'a named copy to switch between') 'saveas'
        $items += New-MenuEntry (L 'Код для друга' 'Share code') '' '' @(
            New-MenuOpt (L 'всё' 'all') 'expfull' (L 'все прицелы; в буфер обмена + файл' 'all crosshairs; to clipboard + file')
            New-MenuOpt (L 'один прицел' 'one crosshair') 'expone' (L 'только активный прицел — короче' 'active crosshair only — shorter')
            New-MenuOpt (L 'бинды' 'binds') 'expbinds' (L 'только клавиши — самый короткий' 'keys only — the shortest'))
        $items += New-MenuEntry (L 'Импорт кода' 'Import code') (L 'из буфера обмена' 'from the clipboard') 'import'
        $i = Select-Item (L 'НАБОРЫ И КОД ДЛЯ ДРУГА' 'SETS & SHARE CODE') $items $sel -Header {
            Write-Field (L 'Активный' 'Active') $(if ($act) { $act } elseif (Test-Path $ProfilePath) { L 'без имени' 'unnamed' } else { L 'нет' 'none' }) 'Green'
        }
        if ($i -lt 0) { return }
        $sel = $i
        $id = Get-EntryId $items[$i]
        try {
            if ($id -like 'p:*') {
                if (-not (Show-ProfileActions $id.Substring(2))) { continue }
            } else {
                switch ($id) {
                    'saveas' {
                        Write-Screen (L 'СОХРАНИТЬ КАК' 'SAVE AS')
                        $n = Read-ProfileName $act
                        if ($n -ne $act -and (Get-ProfileNames) -contains $n -and -not (Confirm-Key (L "«$n» уже есть. Перезаписать?" "`“$n`” already exists. Overwrite?"))) { Write-Note (L 'отменено' 'cancelled') }
                        else { Save-ProfileAs $n; Write-Ok "$(L 'Активный набор сохранён как' 'Active set saved as') «$n»" }
                    }
                    'expfull'  { Write-Screen (L 'КОД: ВСЕ НАСТРОЙКИ' 'CODE: ALL SETTINGS'); $r = Export-Profile; Write-Ok "$(L 'Код скопирован в буфер обмена' 'Code copied to the clipboard') ($($r.Length) $(L 'символов' 'characters'))"; Write-Field (L 'Файл' 'File') $r.File }
                    'expone'   { Write-Screen (L 'КОД: С ОДНИМ ПРИЦЕЛОМ' 'CODE: ONE CROSSHAIR'); $r = Export-Profile -OneCrosshair; Write-Ok "$(L 'Код скопирован в буфер обмена' 'Code copied to the clipboard') ($($r.Length) $(L 'символов' 'characters'))"; Write-Field (L 'Файл' 'File') $r.File }
                    'expbinds' { Write-Screen (L 'КОД: ТОЛЬКО БИНДЫ' 'CODE: BINDS ONLY'); $r = Export-Profile -BindsOnly; Write-Ok "$(L 'Код скопирован в буфер обмена' 'Code copied to the clipboard') ($($r.Length) $(L 'символов' 'characters'))"; Write-Field (L 'Файл' 'File') $r.File }
                    'import'   { Write-Screen (L 'ИМПОРТ КОДА' 'IMPORT CODE'); Invoke-Import }
                }
            }
        } catch {
            Log "ошибка: $($_.Exception.Message)"
            Write-Fail $_.Exception.Message
        }
        Wait-AnyKey
    }
}

# Откат: бэкап — настройки аккаунта перед применением эталона (облако). Перед откатом — ещё один бэкап.
function Show-Restore {
    $files = @(Get-ChildItem $BackupDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15)
    if (-not $files) { Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK'); Write-Note (L 'бэкапов пока нет — они делаются перед каждым переносом' 'no backups yet — one is made before every apply'); Wait-AnyKey; return }
    $s = Get-Session
    $me = if ($s) { Short $s.Puuid } else { '' }
    $meName = if ($s) { Get-AccountLabel $s.Puuid } else { '' }
    # Сверяем каждый бэкап этого аккаунта с тем, что на нём сейчас, — в списке видно, сколько вернётся.
    $curJson = $null; $cur = $null
    if ($s) {
        Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK')
        try { $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json } catch {}
    }
    $mine = @($files | Where-Object { $_.BaseName.Split('_')[0] -eq $me })
    $other = @($files | Where-Object { $_.BaseName.Split('_')[0] -ne $me })
    $items = @()
    $groups = @(@{ T = (L 'ЭТОТ АККАУНТ · НОВЫЕ СВЕРХУ' 'THIS ACCOUNT · NEWEST FIRST'); F = $mine }, @{ T = $(if ($me) { L 'ДРУГИЕ АККАУНТЫ' 'OTHER ACCOUNTS' } else { L 'ВСЕ АККАУНТЫ · НОВЫЕ СВЕРХУ' 'ALL ACCOUNTS · NEWEST FIRST' }); F = $other })
    foreach ($grp in $groups) {
        if (-not $grp.F.Count) { continue }
        $items += New-MenuSep $grp.T
        foreach ($f in $grp.F) {
            $acc = $f.BaseName.Split('_')[0]
            $hint = ''
            if ($acc -eq $me -and $cur) {
                try {
                    $o = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $hint = if (Test-PrefsEqual $cur $o) { L 'как сейчас — откатывать нечего' 'same as now — nothing to roll back' } else { "$(L 'вернёт настроек' 'settings to restore'): $([Math]::Max(1, (Compare-Prefs $cur $o).Count))" }
                } catch { $hint = L 'не читается' 'unreadable' }
            }
            $label = if ($acc -eq $me) { "$(L 'до переноса' 'before apply') $(Format-When $f.LastWriteTime)" } else { "$(Format-When $f.LastWriteTime) · $(Get-LabelByShort $acc)" }
            $items += New-MenuEntry $label $hint $f.FullName
        }
    }
    $i = Select-Item (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK') $items -Header {
        Write-Field (L 'Аккаунт' 'Account') $(if ($meName) { $meName } else { L 'нет входа в клиент Riot' 'not logged into the Riot Client' })
        Write-Host (L '    бэкап — как было на аккаунте перед переносом; выбери — покажу, что именно вернётся' '    a backup = the account before an apply; pick one to see exactly what comes back') -ForegroundColor DarkGray
    }
    if ($i -lt 0) { return }
    Write-Screen (L 'ОТКАТ АККАУНТА' 'ACCOUNT ROLLBACK')
    try {
        if (-not $s) { $s = Connect-Session }
        $f = Get-Item -LiteralPath $items[$i].Id
        $acc = $f.BaseName.Split('_')[0]
        if ($acc -ne (Short $s.Puuid) -and -not (Confirm-Key (L "Это бэкап аккаунта $(Get-LabelByShort $acc), а вошёл $(Get-AccountLabel $s.Puuid). Залить всё равно?" "This backup is of $(Get-LabelByShort $acc), but you are logged into $(Get-AccountLabel $s.Puuid). Write it anyway?"))) {
            Write-Note (L 'отменено' 'cancelled'); Wait-AnyKey; return
        }
        $json = (Get-Content $f.FullName -Raw -Encoding UTF8).Trim()
        $old = $json | ConvertFrom-Json
        if (-not $curJson) { $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }; $cur = $curJson | ConvertFrom-Json }
        if (Test-PrefsEqual $cur $old) { Write-Ok (L 'Аккаунт уже в этом состоянии' 'The account is already in this state'); Wait-AnyKey; return }
        Show-Diff (Compare-Prefs $cur $old)
        if (-not (Confirm-Key (L 'Вернуть так?' 'Restore it?'))) { Write-Note (L 'отменено, аккаунт не тронут' 'cancelled, account untouched'); Wait-AnyKey; return }
        $null = Invoke-Step (L 'Резервная копия' 'Backup') { New-Backup $s $curJson }
        Invoke-Step (L 'Запись в облако Riot' 'Writing to the Riot cloud') { Set-Settings $s $json }
        Invoke-Step (L 'Проверка записи' 'Verifying') {
            $check = Get-Settings $s | ConvertFrom-Json
            foreach ($k in $BindKeys + 'floatSettings' + 'intSettings') {
                if ((Get-JsonPart $check $k) -ne (Get-JsonPart $old $k)) { throw "в облаке '$k' не совпадает с бэкапом" }
            }
        }
        Log "откат $(Short $s.Puuid) к бэкапу $($f.Name)"
        Write-Ok (L "Настройки аккаунта $(Get-AccountLabel $s.Puuid) возвращены к $(Format-When $f.LastWriteTime)" "Settings of $(Get-AccountLabel $s.Puuid) restored to $(Format-When $f.LastWriteTime)")
        Write-Note (L 'графику этот откат не трогает: прошлые файлы — *.valset.bak в папке аккаунта' 'this rollback does not touch graphics: previous files are *.valset.bak in the account folder')
    } catch {
        Log "ошибка: $($_.Exception.Message)"
        Write-Fail $_.Exception.Message
    }
    Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu')
}
