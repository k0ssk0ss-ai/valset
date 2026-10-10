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

