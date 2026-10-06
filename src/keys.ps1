# keys.ps1 — бинды эталона: каталог действий, названия клавиш, редактор со стрелками.
# Облако хранит только отличия от стандарта: нет записи — значит стандартная клавиша игры.
# Подключается из valset.ps1 (dot-source).

$ActionsPath = Join-Path $Root 'actions.txt'   # внутренние имена действий, встреченные в облаке

# Имена, проверенные на реальных данных. Новые valset запоминает сам (Register-Actions).
# Способности 1/2/3 и ульта — как в настройках игры (C = 1, Q = 2, E = 3), в скобках — стандартная клавиша.
$ActionLabels = [ordered]@{
    'Activate_Ability1'       = (L 'Способность 2 (обычно Q)' 'Ability 2 (usually Q)')
    'Activate_GrenadeAbility' = (L 'Способность 1 (обычно C)' 'Ability 1 (usually C)')
    'Activate_Ultimate'       = (L 'Ульта (обычно X)' 'Ultimate (usually X)')
    'Activate_Primary'        = (L 'Основное оружие' 'Primary weapon')
    'Activate_Secondary'      = (L 'Пистолет' 'Secondary weapon')
    'Activate_Melee'          = (L 'Нож' 'Melee')
    'Ping'                    = (L 'Пинг' 'Ping')
    'CautionPing'             = (L 'Пинг «Осторожно»' 'Caution ping')
    'Inspect'                 = (L 'Осмотр оружия' 'Inspect weapon')
    'ToggleMouseCursor'       = (L 'Показать курсор' 'Show cursor')
    'VOICE_TeamPTTAction'     = (L 'Голос: команда' 'Voice: team')
    'VOICE_PartyPTTAction'    = (L 'Голос: пати' 'Voice: party')
}
$Digits = 'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'

$KeyLabels = @{
    'LeftMouseButton' = (L 'ЛКМ' 'LMB'); 'RightMouseButton' = (L 'ПКМ' 'RMB'); 'MiddleMouseButton' = (L 'Колесо (клик)' 'Wheel click')
    'ThumbMouseButton' = 'Mouse4'; 'ThumbMouseButton2' = 'Mouse5'
    'MouseScrollUp' = (L 'Колесо вверх' 'Wheel up'); 'MouseScrollDown' = (L 'Колесо вниз' 'Wheel down')
    'SpaceBar' = (L 'Пробел' 'Space'); 'None' = (L '— снят —' '— unbound —'); 'CapsLock' = 'Caps Lock'
    'LeftShift' = 'L-Shift'; 'LeftControl' = 'L-Ctrl'; 'LeftAlt' = 'L-Alt'
}
for ($d = 0; $d -le 9; $d++) { $KeyLabels[$Digits[$d]] = "$d"; $KeyLabels["NumPad$($Digits[$d])"] = "Num $d" }

$ConsoleToUnreal = @{
    Spacebar = 'SpaceBar'; Tab = 'Tab'; Enter = 'Enter'; Backspace = 'BackSpace'
    Insert = 'Insert'; Delete = 'Delete'; Home = 'Home'; End = 'End'; PageUp = 'PageUp'; PageDown = 'PageDown'
    UpArrow = 'Up'; DownArrow = 'Down'; LeftArrow = 'Left'; RightArrow = 'Right'
    Oem3 = 'Tilde'; OemMinus = 'Hyphen'; OemPlus = 'Equals'; Oem4 = 'LeftBracket'; Oem6 = 'RightBracket'
    Oem1 = 'Semicolon'; Oem7 = 'Apostrophe'; OemComma = 'Comma'; OemPeriod = 'Period'; Oem2 = 'Slash'; Oem5 = 'Backslash'
    Multiply = 'Multiply'; Add = 'Add'; Subtract = 'Subtract'; Divide = 'Divide'; Decimal = 'Decimal'
}

# Только подписи: имя не проверено на реальных данных, поэтому в список правки само не попадает,
# но получит понятное название, как только встретится в облаке.
$LabelOnly = @{ 'Activate_Ability2' = (L 'Способность 3 (обычно E)' 'Ability 3 (usually E)') }

function Get-ActionLabel([string]$name) {
    if ($ActionLabels.Contains($name)) { $ActionLabels[$name] }
    elseif ($LabelOnly.ContainsKey($name)) { $LabelOnly[$name] }
    else { $name }
}

function Test-General($m) { "$($m.characterName)" -in '', 'None' }

function Get-Binding($obj, [string]$name, [int]$idx) {
    @($obj.actionMappings) | Where-Object { $_.name -eq $name -and [int]$_.bindIndex -eq $idx -and (Test-General $_) } |
        Select-Object -First 1
}

function Format-Key($m) {
    if (-not $m) { return (L 'стандарт' 'default') }
    $parts = @()
    if ($m.ctrl) { $parts += 'Ctrl' }; if ($m.alt) { $parts += 'Alt' }; if ($m.shift) { $parts += 'Shift' }
    $k = "$($m.key)"
    $parts += $(if ($KeyLabels.ContainsKey($k)) { $KeyLabels[$k] } else { $k })
    $parts -join '+'
}

# Запоминает имена действий из любых прочитанных настроек — так растёт список для переназначения.
function Register-Actions([string]$json) {
    try {
        $seen  = @(($json | ConvertFrom-Json).actionMappings | ForEach-Object { $_.name })
        $known = @(if (Test-Path $ActionsPath) { Get-Content $ActionsPath -Encoding UTF8 })
        $new = $seen | Where-Object { $_ -and $_ -notin $known -and -not $ActionLabels.Contains($_) } | Sort-Object -Unique
        if ($new) { New-Item -ItemType Directory -Force $Root | Out-Null; Add-Content $ActionsPath $new -Encoding UTF8 }
    } catch {}
}

function Get-KnownActions($prof) {
    $names = New-Object Collections.Generic.List[string]
    $all = @($ActionLabels.Keys) + @(if (Test-Path $ActionsPath) { Get-Content $ActionsPath -Encoding UTF8 }) +
           @($prof.actionMappings | ForEach-Object { $_.name })
    foreach ($n in $all) { if ($n -and -not $names.Contains($n)) { $names.Add($n) } }
    $names
}

# Общий набор (не агентский): заменить/добавить бинд или убрать запись ($key = $null → стандарт).
function Set-Bind($prof, [string]$action, [int]$idx, $key) {
    $list = @($prof.actionMappings | Where-Object { -not ($_.name -eq $action -and [int]$_.bindIndex -eq $idx -and (Test-General $_)) })
    if ($key) {
        $list += [pscustomobject][ordered]@{ alt = $false; bindIndex = $idx; characterName = 'None'; cmd = $false
            ctrl = $false; key = $key; name = $action; shift = $false; tapHoldType = 'None' }
    }
    $prof.actionMappings = $list
    Save-Profile $prof
}

# Выбор новой клавиши. Возвращает @{ Key = ... } (Key = $null — стандарт) или @{ Cancel = $true }.
function Read-NewKey([string]$title) {
    $ways = @(
        New-MenuEntry (L 'Нажать клавишу' 'Press a key') (L 'любая клавиша клавиатуры' 'any keyboard key')
        New-MenuEntry (L 'Кнопка мыши…' 'Mouse button…') (L 'ЛКМ, ПКМ, колесо, Mouse4/5' 'LMB, RMB, wheel, Mouse4/5')
        New-MenuEntry 'Shift / Ctrl / Alt…' (L 'и Caps Lock' 'and Caps Lock')
        New-MenuEntry (L 'Снять бинд' 'Unbind') (L 'действие без клавиши' 'no key for this action')
        New-MenuEntry (L 'Вернуть стандарт' 'Reset to default') (L 'клавиша игры по умолчанию' 'the game default key')
    )
    switch (Select-Item $title $ways) {
        0 {
            Write-Screen $title
            Write-Host (L '    нажми клавишу…   Esc — отмена' '    press a key…   Esc — cancel') -ForegroundColor Cyan
            $ki = Read-KeyOrQuit
            if ("$($ki.Key)" -eq 'Escape') { return @{ Cancel = $true } }
            $name = "$($ki.Key)"
            $key = if ($name -match '^[A-Z]$' -or $name -match '^F\d{1,2}$') { $name }
                   elseif ($name -match '^D(\d)$') { $Digits[[int]$Matches[1]] }
                   elseif ($name -match '^NumPad(\d)$') { "NumPad$($Digits[[int]$Matches[1]])" }
                   else { $ConsoleToUnreal[$name] }
            if (-not $key) { Write-Fail "Клавишу '$name' не знаю — выбери через другие пункты."; Wait-AnyKey; return @{ Cancel = $true } }
            return @{ Key = $key }
        }
        1 {
            $mouse = 'LeftMouseButton', 'RightMouseButton', 'MiddleMouseButton', 'ThumbMouseButton', 'ThumbMouseButton2', 'MouseScrollUp', 'MouseScrollDown'
            $c = Select-Item $title @($mouse | ForEach-Object { New-MenuEntry $KeyLabels[$_] })
            if ($c -lt 0) { return @{ Cancel = $true } }
            return @{ Key = $mouse[$c] }
        }
        2 {
            $mods = 'LeftShift', 'LeftControl', 'LeftAlt', 'CapsLock'
            $c = Select-Item $title @($mods | ForEach-Object { New-MenuEntry $KeyLabels[$_] })
            if ($c -lt 0) { return @{ Cancel = $true } }
            return @{ Key = $mods[$c] }
        }
        3 { return @{ Key = 'None' } }
        4 { return @{ Key = $null } }
        default { return @{ Cancel = $true } }
    }
}

function Edit-Binds {
    $cur = $null
    $s = Get-Session
    if ($s) {
        Write-Screen (L 'НАСТРОЙКА · БИНДЫ' 'EDIT · BINDS')
        try { $cur = Invoke-Step (L 'Сверка с текущим аккаунтом' 'Comparing with the current account') { Get-Settings $s | ConvertFrom-Json } } catch {}
    }
    $sel = 0; $msg = ''
    while ($true) {
        $prof = Read-Profile
        $names = Get-KnownActions $prof
        $items = @(foreach ($n in $names) {
            $k0 = Format-Key (Get-Binding $prof $n 0); $k1 = Format-Key (Get-Binding $prof $n 1)
            $hint = $k0.PadRight(15) + $k1
            if ($cur) {
                $c0 = Format-Key (Get-Binding $cur $n 0); $c1 = Format-Key (Get-Binding $cur $n 1)
                if ($c0 -ne $k0 -or $c1 -ne $k1) { $hint += "  ≠ $c0" }
            }
            New-MenuEntry (Get-ActionLabel $n) $hint
        })
        $i = Select-Item (L 'НАСТРОЙКА · БИНДЫ' 'EDIT · BINDS') $items $sel -Header {
            Write-Host "    $(''.PadRight(30))  Основная       Дополнительная" -ForegroundColor DarkGray
            if ($cur) { Write-Host "    ≠ — $(L 'так сейчас на аккаунте' 'differs on account') $(Get-AccountLabel $s.Puuid)" -ForegroundColor DarkGray }
            Write-Host (L '    нет действия? поменяй его раз в игре — valset запомнит' '    action missing? change it once in game — VALSET will pick it up') -ForegroundColor DarkGray
            if ($msg) { Write-Host "    √ $msg" -ForegroundColor Green }
        }
        if ($i -lt 0) { return }
        $sel = $i
        $action = $names[$i]; $label = Get-ActionLabel $action
        $slots = @(
            New-MenuEntry (L 'Основная клавиша' 'Primary key') (Format-Key (Get-Binding $prof $action 0))
            New-MenuEntry (L 'Дополнительная клавиша' 'Secondary key') (Format-Key (Get-Binding $prof $action 1))
        )
        $slot = Select-Item "$(L 'БИНДЫ' 'BINDS') · $($label.ToUpper())" $slots
        if ($slot -lt 0) { continue }
        $pick = Read-NewKey "$(L 'БИНДЫ' 'BINDS') · $($label.ToUpper())"
        if ($pick.Cancel) { continue }

        Set-Bind $prof $action $slot $pick.Key
        $script:EdChanged = $true
        $msg = "$label [$(@((L 'осн.' 'prim.'), (L 'доп.' 'sec.'))[$slot])] → $(Format-Key (Get-Binding $prof $action $slot))"
        if ($pick.Key -and $pick.Key -ne 'None') {
            $clash = @($prof.actionMappings | Where-Object { $_.key -eq $pick.Key -and $_.name -ne $action -and (Test-General $_) })
            if ($clash) { $msg += "   ! $(L 'также на' 'also on'): " + (($clash | ForEach-Object { Get-ActionLabel $_.name }) -join ', ') }
        }
        Log "мои настройки: $msg"
    }
}
