# share.ps1 — «Код для друга»: мои настройки одной строкой и вставка такого кода на текущий аккаунт (с бэкапом и отменой).
# Формат VALSET3: + base64url (A-Z a-z 0-9 - _, без %-кодировки в ссылке valset:code/<код>) двоичной упаковки
# (codec.ps1, словари — codes.ps1): бинды, настройки, отличия прицела от стандартного, по желанию надетые скины
# (shareskins.ps1). На профиле владельца — 192 знака вместо 583 у VALSET2. Раскладка байтов — NOTES.md «Код VALSET3».
# В коде — только настройки: бинды, чувствительность, один прицел (активный), миникарта, HUD, звук.
# Нет: имени и PUUID аккаунта, служебных отметок (LastSeen*, HasSeen*, принятые соглашения…), микрофона, графики (она под ПК).
# Читаются и старые: VALSET2: (deflate JSON по 14 бит в иероглиф, как в 1.0.0) и VALSET1: (base64).
$ShareSkip = '::(LastSeen|HasSeen|HasAccepted|HasEver|LastAccepted|ContextAware|ShootingRange|MatureContent|Mic|CustomPartyVoice|PushToTalk)'
$ShareKeys = 'actionMappings', 'axisMappings', 'floatSettings', 'intSettings', 'boolSettings', 'stringSettings'
$CjkBase = 0x4E00

# ── Упаковка ─────────────────────────────────────────────────────────────────

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
        if ($bits -ge 14) { $bits -= 14; [void]$sb.Append([char]($CjkBase + (($acc -shr $bits) -band 0x3FFF))); $acc = $acc -band ((1 -shl $bits) - 1) }
    }
    if ($bits -gt 0) { [void]$sb.Append([char]($CjkBase + (($acc -shl (14 - $bits)) -band 0x3FFF))) }
    if ([Math]::Floor($sb.Length * 14 / 8) -gt $b.Length) { [void]$sb.Append('=') }
    $sb.ToString()
}

function ConvertFrom-Cjk([string]$t) {
    $extra = $t -match "[$([char]$CjkBase)-$([char]($CjkBase + 0x3FFF))]\s*="   # '=' сразу за кодом (после него в тексте может быть что угодно)
    $out = New-Object Collections.Generic.List[byte]
    $acc = 0; $bits = 0
    foreach ($ch in $t.ToCharArray()) {
        $v = [int]$ch - $CjkBase
        if ($v -lt 0 -or $v -gt 0x3FFF) { continue }   # пробелы и переносы, вставленные мессенджером
        $acc = ($acc -shl 14) -bor $v; $bits += 14
        while ($bits -ge 8) { $bits -= 8; $out.Add([byte](($acc -shr $bits) -band 0xFF)); $acc = $acc -band ((1 -shl $bits) - 1) }
    }
    if ($extra -and $out.Count) { $out.RemoveAt($out.Count - 1) }
    , $out.ToArray()
}

function Test-HasCjk([string]$t) { foreach ($ch in $t.ToCharArray()) { $v = [int]$ch - $CjkBase; if ($v -ge 0 -and $v -le 0x3FFF) { return $true } }; $false }

# ── Что идёт в код ───────────────────────────────────────────────────────────

# Прицел — только активный: весь список (до 15) длиннее всего остального кода в десятки раз.
function Select-ShareCrosshair($prof) {
    $d = Get-Crosshairs $prof
    if (-not $d -or -not @($d.profiles).Count) { return }
    $all = @($d.profiles); $i = [int]$d.currentProfile
    if ($i -lt 0 -or $i -ge $all.Count) { $i = 0 }
    Set-CrosshairValue $prof (ConvertTo-CrosshairJson ([ordered]@{ currentProfile = 0; profiles = @($all[$i]) }))
}

# Только переносимые настройки: без служебных отметок аккаунта; прицел — один.
function ConvertTo-SharePrefs($p, [switch]$BindsOnly) {
    $q = [ordered]@{}
    foreach ($k in $(if ($BindsOnly) { $BindKeys } else { $ShareKeys })) {
        # бинды — всегда (нет в облаке = стандартные, у друга тоже станут стандартными); настройки — только заданные
        $v = if ($p.PSObject.Properties[$k]) { @($p.$k) } else { @() }
        if ($k -like '*Settings') { $v = @($v | Where-Object { $_ -and "$($_.settingEnum)" -notmatch $ShareSkip }); if (-not $v.Count) { continue } }
        $q[$k] = $v
    }
    $out = Copy-Json ([pscustomobject]$q)
    if (-not $BindsOnly) { Select-ShareCrosshair $out }
    $out
}

# Прицел в коде (поле xh) — только отличия от стандартного профиля: ~400 символов кода → ~50.
# Порядок полей — как в стандартном, лишние — по имени: так сравнение двух прицелов не зависит от порядка полей в облаке.
function Get-XhTemplate { ConvertFrom-CrosshairCode '0' '' }
function Test-JsonObj($v) { $null -ne $v -and $v.GetType().Name -eq 'PSCustomObject' }

function Get-XhDelta($o, $t) {
    $d = [ordered]@{}
    $names = @($t.PSObject.Properties.Name) + @($o.PSObject.Properties.Name | Where-Object { -not $t.PSObject.Properties[$_] } | Sort-Object)
    foreach ($n in $names) {
        if (-not $o.PSObject.Properties[$n]) { continue }
        $v = $o.$n; $tv = if ($t.PSObject.Properties[$n]) { $t.$n } else { $null }
        if ((Test-JsonObj $v) -and (Test-JsonObj $tv)) { $x = Get-XhDelta $v $tv; if ($x.Count) { $d[$n] = $x } }
        elseif ($null -eq $tv -or (Get-JsonKey $v) -ne (Get-JsonKey $tv)) { $d[$n] = $v }
    }
    $d
}

function Join-XhDelta($t, $d) {
    foreach ($p in $d.PSObject.Properties) {
        if ((Test-JsonObj $p.Value) -and (Test-JsonObj $t.($p.Name))) { Join-XhDelta $t.($p.Name) $p.Value }
        else { $t | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

function Get-XhKey($xh) { Get-JsonKey ([pscustomobject](Get-XhDelta $xh (Get-XhTemplate))) }

# Код моих настроек (profile.json); не запомнены — настроек текущего аккаунта. -Skins — плюс надетое сейчас на аккаунте.
function New-ShareCode([switch]$BindsOnly, [switch]$Skins) {
    $p = if (Test-Path $ProfilePath) { Read-Profile } else { (Get-Settings (Connect-Session)) | ConvertFrom-Json }
    $prefs = ConvertTo-SharePrefs $p -BindsOnly:$BindsOnly
    $xhd = $null; $xh = Get-Crosshairs $prefs
    if ($xh -and @($xh.profiles).Count) {
        $xhd = Get-XhDelta @($xh.profiles)[0] (Get-XhTemplate)
        $prefs.stringSettings = @(@($prefs.stringSettings) | Where-Object { $_.settingEnum -ne $CrosshairEnum })
    }
    $sk = if ($Skins) { Get-ShareSkinBytes (Connect-Session) } else { $null }
    'VALSET3:' + (ConvertTo-Url64 (ConvertTo-Code3Bytes ([bool]$BindsOnly) $prefs $xhd $sk))
}

# Текст с кодом (можно с подписью вокруг, из ссылки valset:code/…, с %-кодировкой) → @{ Kind; Prefs; Gfx; Skins }.
# Skins — байты раздела скинов (shareskins.ps1) или $null.
function Read-ShareCode([string]$text) {
    $t = "$text".Trim()
    if ($t -match '%[0-9A-Fa-f]{2}') { try { $t = [Uri]::UnescapeDataString($t) } catch {} }
    $i = $t.IndexOf('VALSET', [StringComparison]::OrdinalIgnoreCase)
    if ($i -ge 0) { $t = $t.Substring($i) }
    elseif (Test-HasCjk $t) { $t = 'VALSET2:' + $t }   # ссылка без префикса
    elseif ($t -match '^[A-Za-z0-9_-]{8,}$') { $t = 'VALSET3:' + $t }
    else { throw (L 'Кода VALSET нет. Скопируй его целиком (он начинается с VALSET).' 'No VALSET code. Copy all of it (it starts with VALSET).') }
    $d = $null; $d3 = $null
    try {
        if ($t.StartsWith('VALSET3:', [StringComparison]::OrdinalIgnoreCase))     { $d3 = Read-Code3Text $t.Substring(8) }
        elseif ($t.StartsWith('VALSET2:', [StringComparison]::OrdinalIgnoreCase)) { $d = Expand-Bytes (ConvertFrom-Cjk $t.Substring(8)) | ConvertFrom-Json }
        elseif ($t.StartsWith('VALSET1:', [StringComparison]::OrdinalIgnoreCase)) { $d = Expand-Pref ($t.Substring(8) -replace '\s', '') | ConvertFrom-Json }
        elseif ($t -match '^VALSET(\d+):' -and [int]$Matches[1] -gt 3) { throw (Get-CodeNewer) }
    } catch {
        if ($_.Exception.Message -eq (Get-CodeNewer)) { throw }
        throw (Get-CodeBad)
    }
    if ($d3) {
        $binds = $d3.BindsOnly; $prof = $d3.Profile; $xh = $d3.Xh; $gfx = $false
    } else {
        if (-not $d -or $d.v -notin 1, 2 -or -not $d.profile) { throw (L 'Код от другой версии VALSET или повреждён.' 'The code is from another VALSET version or damaged.') }
        $binds = $d.kind -eq 'binds'; $prof = $d.profile; $xh = $d.xh; $gfx = [bool]($d.gfxIniT -or $d.gfxIni)
    }
    $prefs = ConvertTo-SharePrefs $prof -BindsOnly:$binds
    if (-not $binds -and $xh) {
        $x = Get-XhTemplate; Join-XhDelta $x $xh
        Set-CrosshairValue $prefs (ConvertTo-CrosshairJson ([ordered]@{ currentProfile = 0; profiles = @($x) }))
    }
    @{ Kind = $(if ($binds) { 'binds' } else { 'full' }); Prefs = $prefs; Gfx = $gfx; Skins = $(if ($d3) { $d3.Skins }) }
}
# ── Наложение на аккаунт ─────────────────────────────────────────────────────

# Прицел из кода — активным: такой же уже есть у аккаунта — просто выбрать его, иначе первым (лишние сверх 15 — с конца).
function Add-ShareCrosshair($prof, $xh) {
    $d = Get-Crosshairs $prof
    $list = if ($d) { @($d.profiles) } else { @() }
    $key = Get-XhKey $xh
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ((Get-XhKey $list[$i]) -eq $key) { $d.currentProfile = $i; Set-CrosshairValue $prof (ConvertTo-CrosshairJson $d); return }
    }
    $rest = @($list | Where-Object { "$($_.profileName)" -ne "$($xh.profileName)" })
    Set-CrosshairValue $prof (ConvertTo-CrosshairJson ([ordered]@{ currentProfile = 0; profiles = @(@($xh) + $rest | Select-Object -First $CrosshairMax) }))
}

# Настройки из кода поверх текущих: списки — по settingEnum, бинды — целиком; прицелы аккаунта не стираются.
function Join-SharePrefs($cur, $code) {
    $prefs = Copy-Json $code.Prefs
    $xh = Get-Crosshairs $prefs
    if ($xh) { $prefs.stringSettings = @(@($prefs.stringSettings) | Where-Object { $_.settingEnum -ne $CrosshairEnum }) }
    # пустой список настроек в коде — «нечего менять», а не «стереть у аккаунта» (Join-ProPrefs заменил бы группу целиком)
    foreach ($g in 'floatSettings', 'intSettings', 'boolSettings', 'stringSettings') {
        if ($prefs.PSObject.Properties[$g] -and -not @($prefs.$g).Count) { $prefs.PSObject.Properties.Remove($g) }
    }
    $new = Join-ProPrefs $cur $prefs
    if ($xh -and @($xh.profiles).Count) { Add-ShareCrosshair $new @($xh.profiles)[0] }
    $new
}

# Подпись «что в коде» для предпросмотра.
function Format-ShareKind($code) {
    $w = if ($code.Kind -eq 'binds') { L 'только бинды' 'binds only' } else { L 'бинды, чувствительность, прицел, HUD, звук' 'binds, sensitivity, crosshair, HUD, audio' }
    if ($code.Skins) { $w += L ' и надетые скины' ' and worn skins' }
    if ($code.Gfx) { $w += L ' (графика из старого кода не берётся)' ' (graphics from an old code are skipped)' }
    $w
}

# `valset list code:<код>` — что изменится на текущем аккаунте. Ошибка — одним элементом { error }.
# Скины из кода — строками «было → станет», как у набора; не прочитались — строкой в сведениях, остальное переносится.
function Get-ListCode([string]$text) {
    try {
        $c = Read-ShareCode $text
        $s = Connect-Session
        $cur = (Get-Settings $s) | ConvertFrom-Json
        $new = Join-SharePrefs $cur $c
        $info = [ordered]@{ info = "$(L 'В коде' 'In the code'): $(Format-ShareKind $c)"; account = (Get-AccountLabel $s.Puuid); same = [bool](Test-PrefsEqual $cur $new) }
        $rows = @(ConvertTo-DiffItems (Compare-Prefs $cur $new -BindsOnly:($c.Kind -eq 'binds')))
        if ($c.Skins) {
            try {
                $p = Get-ShareSkinPlan $s $c.Skins
                $sr = Compare-Loadout $p.Cur $p.New (Get-CosmeticNames)   # массив одним объектом — без @()
                $info.info += "`n" + $p.Note; $info['pics'] = $p.Pics; $rows += @($sr)
                if ($sr.Count) { $info.same = $false }
            } catch { $info.info += "`n" + (L "Скины из кода не надену: $($_.Exception.Message)" "Skins from the code will not go on: $($_.Exception.Message)") }
        }
        @($info) + $rows
    } catch { @([ordered]@{ error = $_.Exception.Message }) }
}

# `valset do code:<код>` — записать на текущий аккаунт насовсем: бэкап, точка отмены, проверка записи.
# Чужие настройки — не твои правки в игре: основа сессии = записанное, в эталон они не попадут (на основном — «Сохранить», если нужны).
# Скины из кода (если есть) — после настроек, через запись набора (Write-LoadoutChange); «Отменить» вернёт и их.
function Invoke-DoCode([string]$text) {
    $c = Read-ShareCode $text
    $s = Connect-Session
    if (Test-GameRunning) { throw (L 'Игра запущена. Вставь код после её закрытия.' 'The game is running. Paste the code after closing it.') }
    $curJson = Get-Settings $s
    $cur = $curJson | ConvertFrom-Json
    $new = Join-SharePrefs $cur $c
    $plan = $null; $skErr = ''
    if ($c.Skins) {
        try { $plan = Get-ShareSkinPlan $s $c.Skins; if (-not (Compare-Loadout $plan.Cur $plan.New (Get-CosmeticNames)).Count) { $plan = $null } }
        catch { $skErr = $_.Exception.Message }
    }
    $same = Test-PrefsEqual $cur $new
    $msg = @()
    if ($same -and -not $plan) { $msg += L 'Настройки уже как в коде' 'Settings already match the code' }
    if (-not $same) {
        $diff = Compare-Prefs $cur $new -BindsOnly:($c.Kind -eq 'binds')   # без @(): пустой массив внутри @() считался бы за 1
        $n = [Math]::Max(1, $diff.Count)
        Save-UndoPoint 'account' $s.Puuid $curJson
        $null = Update-Reference $s $curJson   # твои правки в игре — в эталон до записи, как при переносе
        $null = New-Backup $s $curJson
        $newJson = ConvertTo-Json -InputObject $new -Depth 32 -Compress
        Set-Settings $s $newJson
        Assert-Written $s $newJson (L 'код' 'code')
        Set-SessionBase $s.Puuid $newJson 'all'
        Set-AccountState $s.Puuid @{ state = ''; checked = (Get-Stamp) }
        Log "код для друга ($($c.Kind)) → $(Get-AccountLabel $s.Puuid): $n изм."
        $msg += L "Настройки из кода перенесены: $n $(Get-Plural $n 'изменение' 'изменения' 'изменений')" "Settings from the code applied: $n change$(if ($n -ne 1) { 's' })"
    }
    if ($plan) {
        $ua = $script:UndoAction
        if (-not $same -and $ua) { Add-UndoLoadout $s.Puuid $plan.Cur; $script:UndoAction = $null }   # одна отмена на оба
        try {
            $k = (Write-LoadoutChange $s $plan.Cur $plan.New 'скины из кода').Count
            $msg += L "Скины надеты: $k $(Get-Plural $k 'изменение' 'изменения' 'изменений')" "Skins on: $k change$(if ($k -ne 1) { 's' })"
        } catch { $skErr = $_.Exception.Message } finally { $script:UndoAction = $ua }
    }
    if ($skErr) { $msg += L "Скины не надеты: $skErr" "Skins not put on: $skErr" }
    ($msg | ForEach-Object { "$_".TrimEnd('.') }) -join '. '
}

# `valset do share` / `do share:skins` — код моих настроек (со скинами — плюс надетое сейчас); сам код — в ответе
# (поле code), в буфер его кладёт приложение.
function Invoke-DoShare($r, [switch]$BindsOnly, [switch]$Skins) {
    $code = New-ShareCode -BindsOnly:$BindsOnly -Skins:$Skins
    $r['code'] = $code
    $n = $code.Length
    Log "код для друга$(if ($Skins) { ' со скинами' }): $n символов"
    L "Код скопирован ($n $(Get-Plural $n 'символ' 'символа' 'символов')). Отправь его другу" "Code copied ($n characters). Send it to a friend"
}