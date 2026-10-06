# editor.ps1 — «Настроить эталон»: категории → настройка → готовый вариант или своё значение.
# Облачные настройки правятся в profile.json, графика — в файлах graphics\ эталона.
# Подключается из valset.ps1 (dot-source).

$Inv = [Globalization.CultureInfo]::InvariantCulture

function Read-Profile {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои».' 'Your settings are not saved yet — use “Save as mine” first.') }
    Get-Content $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Перед первой правкой за сеанс — версия в истории (history.ps1).
function Save-Profile($prof) {
    Protect-Profile (L 'до правки в «Изменить»' 'before editing in “Edit”')
    Set-Content $ProfilePath (ConvertTo-Json -InputObject $prof -Depth 32 -Compress) -Encoding UTF8
}

function O([string]$label, $value) { [pscustomobject]@{ L = $label; V = $value } }
function New-Setting([hashtable]$h) { [pscustomobject]$h }

$Num = '^\d+([.,]\d+)?$'
# Качество (проверено в игре 2026-10-05): стандарт = «высокое», ключа нет — подпись честно говорит «стандарт», Riot может его сменить; у материалов «среднее» = 2, у остальных = 1.
$Q3  = @((O (L 'низкое' 'low') '0'), (O (L 'среднее' 'medium') '1'), (O (L 'стандарт игры (сейчас = высокое)' 'game default (now = high)') $null))
$Q3M = @((O (L 'низкое' 'low') '0'), (O (L 'среднее' 'medium') '2'), (O (L 'стандарт игры (сейчас = высокое)' 'game default (now = high)') $null))
$OnOff = @((O (L 'вкл' 'on') 'True'), (O (L 'выкл' 'off') 'False'))
# Порядок вариантов как в игре: скрыть / текст / график / текст и график.
$PerfShow = @((O (L 'скрыть' 'hide') 0), (O (L 'текст' 'text') 1), (O (L 'график' 'graph') 2), (O (L 'текст и график' 'text and graph') 3))

# Kind: cloud — облако (Group/Enum/Type); riot — графический ключ RiotUserSettings;
#       ini — ключи GameUserSettings.ini; res / fps — составные. NoDefault — нельзя «стандарт игры».
$SettingDefs = @(
    New-Setting @{ Cat = 'mouse'; Label = (L 'Чувствительность' 'Sensitivity'); Kind = 'cloud'; Group = 'floatSettings'; Type = 'float'
        Enum = 'EAresFloatSettingName::MouseSensitivity'; Free = $Num; FreeHint = (L 'например 0.314' 'e.g. 0.314')
        Opts = @((O '0.2' 0.2), (O '0.25' 0.25), (O '0.3' 0.3), (O '0.35' 0.35), (O '0.4' 0.4), (O '0.5' 0.5)) }
    New-Setting @{ Cat = 'mouse'; Label = (L 'Снайперский прицел' 'Sniper scope'); Kind = 'cloud'; Group = 'boolSettings'; Type = 'bool'
        Enum = 'EAresBoolSettingName::HoldInputForSniperScopes'; Opts = @((O (L 'удержание' 'hold') $true), (O (L 'переключение' 'toggle') $false)) }

    New-Setting @{ Cat = 'ui'; Label = (L 'Размер миникарты' 'Minimap size'); Kind = 'cloud'; Group = 'floatSettings'; Type = 'float'
        Enum = 'EAresFloatSettingName::MinimapSize'; Free = $Num; FreeHint = '0.9 – 1.2'
        Opts = @((O '0.9' 0.9), (O '1.0' 1.0), (O '1.1' 1.1), (O '1.2' 1.2)) }
    New-Setting @{ Cat = 'ui'; Label = (L 'Кровь' 'Blood'); Kind = 'cloud'; Group = 'boolSettings'; Type = 'bool'
        Enum = 'EAresBoolSettingName::ShowBlood'; Opts = @((O (L 'показывать' 'show') $true), (O (L 'скрыть' 'hide') $false)) }
    New-Setting @{ Cat = 'ui'; Label = (L 'Тела убитых' 'Corpses'); Kind = 'cloud'; Group = 'boolSettings'; Type = 'bool'
        Enum = 'EAresBoolSettingName::ShowCorpses'; Opts = @((O (L 'показывать' 'show') $true), (O (L 'скрыть' 'hide') $false)) }
    New-Setting @{ Cat = 'ui'; Label = (L 'Громкость музыки' 'Music volume'); Kind = 'cloud'; Group = 'floatSettings'; Type = 'float'; Format = 'pct'
        Enum = 'EAresFloatSettingName::AllMusicOverallVolume'; Free = '^\d{1,3}$'; FreeHint = (L 'в процентах' 'in percent')
        Opts = @((O '0%' 0), (O '10%' 0.1), (O '25%' 0.25), (O '50%' 0.5), (O '100%' 1)) }
    New-Setting @{ Cat = 'ui'; Label = (L 'Голосовой чат' 'Voice chat'); Kind = 'cloud'; Group = 'intSettings'; Type = 'int'; Format = 'pct100'
        Enum = 'EAresIntSettingName::VoiceVolume'; Free = '^\d{1,3}$'; FreeHint = (L 'в процентах' 'in percent')
        Opts = @((O '25%' 25), (O '50%' 50), (O '75%' 75), (O '100%' 100)) }

    New-Setting @{ Cat = 'stats'; Label = 'FPS'; Kind = 'cloud'; Group = 'intSettings'; Type = 'int'
        Enum = 'EAresIntSettingName::PlayerPerfShowFrameRate'; Opts = $PerfShow }
    New-Setting @{ Cat = 'stats'; Label = (L 'Разброс при стрельбе' 'Firing error'); Kind = 'cloud'; Group = 'intSettings'; Type = 'int'
        Enum = 'EAresIntSettingName::PlayerPerfShowFiringErrors'; Opts = $PerfShow }
    New-Setting @{ Cat = 'stats'; Label = (L 'Джиттер сети' 'Network jitter'); Kind = 'cloud'; Group = 'intSettings'; Type = 'int'
        Enum = 'EAresIntSettingName::PlayerPerfShowNetworkJitter'; Opts = $PerfShow }
    New-Setting @{ Cat = 'stats'; Label = (L 'Потеря пакетов' 'Packet loss'); Kind = 'cloud'; Group = 'intSettings'; Type = 'int'
        Enum = 'EAresIntSettingName::PlayerPerfShowPacketLossPercentage'; Opts = $PerfShow }

    New-Setting @{ Cat = 'gfx'; Label = (L 'Разрешение' 'Resolution'); Kind = 'res'; NoDefault = $true
        Free = '^\s*\d{3,4}\s*[xXхХ×*]\s*\d{3,4}\s*$'; FreeHint = (L 'например 1728x1080' 'e.g. 1728x1080')
        Opts = @((O '1920×1080' '1920x1080'), (O '2560×1440' '2560x1440'), (O '1280×960 (4:3)' '1280x960'),
                 (O '1440×1080 (4:3)' '1440x1080'), (O '1680×1050' '1680x1050'), (O '1600×900' '1600x900'),
                 (O '1280×1024 (5:4)' '1280x1024'), (O '3840×2160' '3840x2160')) }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Режим экрана' 'Display mode'); Kind = 'ini'; NoDefault = $true
        Keys = @('PreferredFullscreenMode', 'LastConfirmedFullscreenMode')
        Opts = @((O (L 'полный экран' 'fullscreen') '0'), (O (L 'оконный без рамки' 'borderless window') '1'), (O (L 'в окне' 'windowed') '2')) }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Заполнение' 'Aspect ratio method'); Kind = 'ini'; NoDefault = $true
        Keys = @('bShouldLetterbox', 'bLastConfirmedShouldLetterbox')
        Opts = @((O (L 'Letterbox (с полосами)' 'Letterbox') 'True'), (O (L 'Fill (растянуть)' 'Fill (stretched)') 'False')) }
    New-Setting @{ Cat = 'gfx'; Label = 'VSync'; Kind = 'ini'; NoDefault = $true; Keys = @('bUseVSync'); Opts = $OnOff }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Лимит FPS' 'FPS limit'); Kind = 'fps'; NoDefault = $true; Free = '^\d{2,3}$'; FreeHint = (L 'кадров в секунду' 'frames per second')
        Opts = @((O (L 'без лимита' 'unlimited') 'off'), (O '60' '60'), (O '120' '120'), (O '144' '144'), (O '165' '165'),
                 (O '240' '240'), (O '300' '300'), (O '360' '360')) }
    New-Setting @{ Cat = 'gfx'; Label = 'NVIDIA Reflex'; Kind = 'riot'; Enum = 'EAresIntSettingName::NvidiaReflexLowLatencySetting'
        Opts = @((O (L 'выкл' 'off') '0'), (O (L 'вкл' 'on') '1'), (O (L 'вкл + буст' 'on + boost') '2')) }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Сглаживание' 'Anti-aliasing'); Kind = 'riot'; Enum = 'EAresIntSettingName::AntiAliasing'
        Opts = @((O (L 'нет' 'none') '0'), (O 'MSAA 2x' '1'), (O 'MSAA 4x' '2'), (O 'FXAA' '3')) }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Анизотропия' 'Anisotropic filtering'); Kind = 'riot'; Enum = 'EAresIntSettingName::AnisotropicFiltering'
        Opts = @((O '1x' '1'), (O '2x' '2'), (O '4x' '4'), (O '8x' '8'), (O '16x' '16')) }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Улучшение чёткости' 'Improve clarity'); Kind = 'riot'; Enum = 'EAresBoolSettingName::ImproveClarity'; Opts = $OnOff }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Качество материалов' 'Material quality'); Kind = 'riot'; Enum = 'EAresIntSettingName::MaterialQuality'; Opts = $Q3M; NoDefault = $true }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Качество текстур' 'Texture quality'); Kind = 'riot'; Enum = 'EAresIntSettingName::TextureQuality'; Opts = $Q3; NoDefault = $true }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Детализация' 'Detail quality'); Kind = 'riot'; Enum = 'EAresIntSettingName::DetailQuality'; Opts = $Q3; NoDefault = $true }
    New-Setting @{ Cat = 'gfx'; Label = (L 'Качество интерфейса' 'UI quality'); Kind = 'riot'; Enum = 'EAresIntSettingName::UIQuality'; Opts = $Q3; NoDefault = $true }
)

function Test-SameValue($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
    $x = 0.0; $y = 0.0
    if ([double]::TryParse("$a", [Globalization.NumberStyles]::Float, $Inv, [ref]$x) -and
        [double]::TryParse("$b", [Globalization.NumberStyles]::Float, $Inv, [ref]$y)) { return [Math]::Abs($x - $y) -lt 0.0001 }
    "$a" -eq "$b"
}

function Get-SettingValue($d) {
    switch ($d.Kind) {
        'cloud' { $e = @((Read-Profile).($d.Group)) | Where-Object { $_.settingEnum -eq $d.Enum } | Select-Object -First 1
                  if ($e) { $e.value } else { $null } }
        'riot'  { (Read-GraphicsValues)[($d.Enum -replace '^.*::', '')] }
        'ini'   { (Read-GraphicsValues)[$d.Keys[0]] }
        'res'   { $v = Read-GraphicsValues; "$($v['ResolutionSizeX'])x$($v['ResolutionSizeY'])" }
        'fps'   { $v = Read-GraphicsValues; if ($v['LimitFramerateAlways'] -eq 'True') { "$($v['MaxFramerateAlways'])" } else { 'off' } }
    }
}

function Set-SettingValue($d, $value) {
    switch ($d.Kind) {
        'cloud' {
            $p = Read-Profile
            $list = @(@($p.($d.Group)) | Where-Object { $_ -and $_.settingEnum -ne $d.Enum })
            if ($null -ne $value) {
                $typed = switch ($d.Type) { 'float' { [double]$value } 'int' { [int]$value } 'bool' { [bool]$value } default { $value } }
                $list += [pscustomobject][ordered]@{ settingEnum = $d.Enum; value = $typed }
            }
            $p | Add-Member -NotePropertyName $d.Group -NotePropertyValue $list -Force
            Save-Profile $p
        }
        'riot' { Set-GfxRiot $d.Enum $value }
        'ini'  { $pairs = @{}; foreach ($k in $d.Keys) { $pairs[$k] = $value }; Set-GfxIni $pairs }
        'res'  {
            $w, $h = "$value" -split 'x'
            Set-GfxIni @{ ResolutionSizeX = $w; ResolutionSizeY = $h; LastUserConfirmedResolutionSizeX = $w; LastUserConfirmedResolutionSizeY = $h }
        }
        'fps'  {
            if ($value -eq 'off') { Set-GfxRiot 'EAresBoolSettingName::LimitFramerateAlways' 'False' }
            else { Set-GfxRiot 'EAresBoolSettingName::LimitFramerateAlways' 'True'; Set-GfxRiot 'EAresFloatSettingName::MaxFramerateAlways' $value }
        }
    }
}

function Format-Setting($d) {
    $v = Get-SettingValue $d
    if ($null -eq $v -or "$v" -eq '') {
        $o = @($d.Opts) | Where-Object { $null -eq $_.V } | Select-Object -First 1
        return $(if ($o) { $o.L } else { L 'стандарт' 'default' })
    }
    foreach ($o in $d.Opts) { if (Test-SameValue $o.V $v) { return $o.L } }
    switch ($d.Format) {
        'pct'    { return ('{0:0}%' -f ([double]$v * 100)) }
        'pct100' { return "$v%" }
    }
    if ($d.Kind -eq 'res') { return ($v -replace 'x', '×') }
    if ($d.Type -eq 'float') { return ([double]$v).ToString('0.###', $Inv) }
    "$v"
}

function ConvertFrom-FreeInput($d, [string]$raw) {
    $raw = $raw.Trim()
    if ($d.Format -eq 'pct') { return [double]$raw / 100 }
    if ($d.Kind -eq 'res') { return (($raw -replace '[^\d]+', ' ').Trim() -replace ' ', 'x') }
    if ($d.Kind -eq 'fps' -or $d.Type -eq 'int') { return "$([int]$raw)" }
    [double]::Parse(($raw -replace ',', '.'), $Inv)
}

# Выбор значения: готовые варианты, «Ввести своё…», «Стандарт игры». @{ Value } или @{ Cancel }.
function Read-SettingValue($d, [string]$title) {
    $cur = Get-SettingValue $d
    $opts = @($d.Opts)
    $start = 0
    $items = @(for ($n = 0; $n -lt $opts.Count; $n++) {
        $same = Test-SameValue $opts[$n].V $cur
        if ($same) { $start = $n }
        New-MenuEntry $opts[$n].L $(if ($same) { L '• сейчас' '• current' } else { '' })
    })
    if ($d.Free) { $items += New-MenuEntry (L 'Ввести своё…' 'Enter your own…') $d.FreeHint }
    if (-not $d.NoDefault) {
        $items += New-MenuEntry (L 'Стандарт игры' 'Game default') (L 'убрать своё значение' 'remove your value')
        if ($null -eq $cur) { $start = $items.Count - 1 }
    }
    $i = Select-Item $title $items $start -Header { Write-Host "    $(L 'сейчас' 'now'): $(Format-Setting $d)" -ForegroundColor Gray }
    if ($i -lt 0) { return @{ Cancel = $true } }
    if ($i -lt $opts.Count) { return @{ Value = $opts[$i].V } }
    if ($d.Free -and $i -eq $opts.Count) {
        Write-Screen $title
        Write-Host "    $(L 'сейчас' 'now'): $(Format-Setting $d)" -ForegroundColor Gray
        Write-Host ''
        Write-Host -NoNewline "    › $(L 'новое значение' 'new value') ($($d.FreeHint)), Enter: " -ForegroundColor Red
        $raw = "$([Console]::ReadLine())"
        if ($raw.Trim() -notmatch $d.Free) {
            Write-Fail (L 'Не похоже на допустимое значение — ничего не изменено.' 'That does not look like a valid value — nothing changed.')
            Wait-AnyKey
            return @{ Cancel = $true }
        }
        return @{ Value = (ConvertFrom-FreeInput $d $raw) }
    }
    @{ Value = $null }
}

function Edit-Settings([string]$cat, [string]$title) {
    $defs = @($SettingDefs | Where-Object { $_.Cat -eq $cat })
    $sel = 0; $msg = ''
    while ($true) {
        $items = @($defs | ForEach-Object { New-MenuEntry $_.Label (Format-Setting $_) })
        $i = Select-Item $title $items $sel -Header {
            if ($msg) { Write-Host "    √ $msg" -ForegroundColor Green }
            else { Write-Host (L '    Enter — изменить значение' '    Enter — change value') -ForegroundColor DarkGray }
        }
        if ($i -lt 0) { return }
        $sel = $i
        $d = $defs[$i]
        $r = Read-SettingValue $d "$title · $($d.Label.ToUpper())"
        if ($r.Cancel) { continue }
        Set-SettingValue $d $r.Value
        $script:EdChanged = $true
        $msg = "$($d.Label) → $(Format-Setting $d)"
        Log "мои настройки: $msg"
    }
}

function Show-Editor {
    if (-not (Test-Path $ProfilePath)) {
        Write-Screen (L 'МОИ НАСТРОЙКИ' 'MY SETTINGS'); Write-Fail (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои».' 'Your settings are not saved yet — use “Save as mine” first.'); Wait-AnyKey; return
    }
    $script:EdChanged = $false; $script:ProfileBackedUp = $false
    $gfxStamp = if (Test-GraphicsSaved) { (Get-Item $GfxRiot).LastWriteTime.Ticks + (Get-Item $GfxIni).LastWriteTime.Ticks }
    $sel = 0
    while ($true) {
        $nb = @((Read-Profile).actionMappings | Where-Object { Test-General $_ }).Count
        $cats = @(
            New-MenuEntry (L 'Бинды' 'Binds') "$(L 'своих биндов' 'custom binds'): $nb" 'binds'
            New-MenuEntry (L 'Мышь и прицел' 'Mouse & scope') (L 'чувствительность, снайперский прицел' 'sensitivity, sniper scope') 'mouse'
            New-MenuEntry (L 'Интерфейс и звук' 'Interface & sound') (L 'миникарта, кровь, громкость' 'minimap, blood, volume') 'ui'
            New-MenuEntry (L 'Статистика на экране' 'On-screen stats') (L 'FPS, разброс, джиттер, потеря пакетов' 'FPS, firing error, jitter, packet loss') 'stats'
            New-MenuEntry (L 'Графика' 'Graphics') $(if (Test-GraphicsSaved) { L 'разрешение, FPS, Reflex, качество' 'resolution, FPS, Reflex, quality' } else { L 'не сохранена — запомни настройки заново' 'not saved — save your settings again' }) 'gfx'
        )
        $i = Select-Item (L 'МОИ НАСТРОЙКИ' 'MY SETTINGS') $cats $sel -Header {
            Write-Host (L '    правки сразу пишутся в твои настройки; на аккаунт — «Перенести мои»' '    edits go straight into your settings; to an account — “Apply mine”') -ForegroundColor DarkGray
        }
        if ($i -lt 0) { break }
        $sel = $i
        try {
            switch ($cats[$i].Id) {
                'binds' { Edit-Binds }
                'mouse' { Edit-Settings 'mouse' (L 'МЫШЬ И ПРИЦЕЛ' 'MOUSE & SCOPE') }
                'ui'    { Edit-Settings 'ui' (L 'ИНТЕРФЕЙС И ЗВУК' 'INTERFACE & SOUND') }
                'stats' { Edit-Settings 'stats' (L 'СТАТИСТИКА НА ЭКРАНЕ' 'ON-SCREEN STATS') }
                'gfx'   { if (Test-GraphicsSaved) { Edit-Settings 'gfx' (L 'ГРАФИКА' 'GRAPHICS') } }
            }
        } catch {
            Log "ошибка: $($_.Exception.Message)"
            Write-Fail $_.Exception.Message
            Wait-AnyKey
        }
    }
    if ((Test-GraphicsSaved) -and $gfxStamp -ne ((Get-Item $GfxRiot).LastWriteTime.Ticks + (Get-Item $GfxIni).LastWriteTime.Ticks)) {
        Write-Screen (L 'МОИ НАСТРОЙКИ' 'MY SETTINGS')
        try { $cs = Get-Session; Sync-Graphics $(if ($cs) { $cs.Puuid } else { '' }) } catch { Log "ошибка: $($_.Exception.Message)"; Write-Fail $_.Exception.Message }
        Wait-AnyKey
    }
    if ($script:EdChanged -and (Get-Session)) {
        Write-Screen (L 'МОИ НАСТРОЙКИ' 'MY SETTINGS')
        if (Confirm-Key (L 'Настройки изменены. Перенести на этот аккаунт сейчас?' 'Settings changed. Apply to this account now?')) {
            try { Invoke-Apply } catch { Log "ошибка: $($_.Exception.Message)"; Write-Fail $_.Exception.Message }
            Wait-AnyKey (L 'любая клавиша — назад в меню' 'any key — back to menu')
        }
    }
}
