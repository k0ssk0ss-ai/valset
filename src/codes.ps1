# codes.ps1 — словари кода VALSET3 (codec.ps1): имя → номер. В коде вместо имени пишется номер; имени нет в словаре —
# пишется само имя (код не ломается на новых настройках игры).
# ПРАВИЛО: только дописывать в конец, никогда не переставлять и не удалять — номера уже лежат в чужих кодах.
# Дописал хоть одно имя — увеличь $CodesVer: старое приложение по номеру поймёт, что код от более новой версии.
# Источник: реальные имена из profile.json, base, history, backups и tests\fixtures (2026-11-07) + известные имена игры.
# Частые — в начале: номер до 125 (у клавиш до 62, у путей прицела до 14) занимает один байт.

$CodesVer = 1

$CodeDicts = @{
    # actionMappings.name
    act = @('Activate_Ability1', 'Activate_Ability2', 'Activate_GrenadeAbility', 'Activate_Ultimate', 'Activate_Primary', 'Activate_Secondary',
            'Activate_Melee', 'Ping', 'CautionPing', 'CommWheelIndex', 'Crouch', 'Ghost', 'Inspect', 'Spray', 'ToggleMouseCursor',
            'UseAlternateObject', 'VOICE_PartyPTTAction', 'VOICE_TeamPTTAction', 'Jump', 'Walk', 'Fire', 'AltFire', 'Reload', 'UseObject',
            'Drop', 'Activate_Spike', 'Activate_Bomb', 'EquipLastUsed', 'CycleNextWeapon', 'CyclePreviousWeapon', 'Scoreboard', 'Map',
            'ToggleMap', 'Shop', 'BuyMenu', 'MoveForward', 'MoveBackward', 'MoveLeft', 'MoveRight', 'Chat', 'TeamChat', 'AllChat',
            'PartyChat', 'Flex', 'ShowEquipment', 'Activate_Flex', 'PingWheel', 'RadioWheel', 'SprayWheel', 'Activate_Spray')
    # клавиши (FKey Unreal): мышь, буквы, цифры, частые — первыми (номер до 62 — один байт)
    key = @('None', 'LeftMouseButton', 'RightMouseButton', 'MiddleMouseButton', 'ThumbMouseButton', 'ThumbMouseButton2',
            'MouseScrollUp', 'MouseScrollDown', 'SpaceBar', 'LeftShift', 'LeftControl', 'LeftAlt', 'Tab', 'CapsLock', 'Tilde',
            'Equals', 'Hyphen', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
            'V', 'W', 'X', 'Y', 'Z', 'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Enter', 'Escape',
            'BackSpace', 'Up', 'Down', 'Left', 'Right', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
            'NumPadZero', 'NumPadOne', 'NumPadTwo', 'NumPadThree', 'NumPadFour', 'NumPadFive', 'NumPadSix', 'NumPadSeven',
            'NumPadEight', 'NumPadNine', 'Multiply', 'Add', 'Subtract', 'Divide', 'Decimal', 'RightShift', 'RightControl',
            'RightAlt', 'Insert', 'Delete', 'Home', 'End', 'PageUp', 'PageDown', 'LeftBracket', 'RightBracket', 'Semicolon',
            'Apostrophe', 'Comma', 'Period', 'Slash', 'Backslash', 'Pause', 'ScrollLock', 'NumLock', 'LeftCommand', 'RightCommand',
            'MouseX', 'MouseY', 'MouseWheelAxis', 'Ampersand', 'Asterix', 'Caret', 'Colon', 'Dollar', 'Exclamation',
            'LeftParantheses', 'RightParantheses', 'Quote', 'Underscore', 'Section', 'A_AccentGrave', 'E_AccentGrave',
            'E_AccentAigu', 'C_Cedille', 'F13', 'F14', 'F15', 'F16', 'F17', 'F18', 'F19', 'F20', 'F21', 'F22', 'F23', 'F24')
    # characterName: 'None' — для всех агентов, иначе внутреннее имя агента
    chr = @('None', 'Clay', 'Wushu', 'Pandemic', 'Sarge', 'Phoenix', 'Wraith', 'Hunter', 'Thorne', 'Gumshoe', 'Breach', 'Rift',
            'Grenadier', 'Deadeye', 'Killjoy', 'Vampire', 'Stealth', 'Sprinter', 'BountyHunter', 'Mage', 'AggroBot', 'Cable',
            'Sequoia', 'Smonk', 'Nox', 'Terra', 'Cashew', 'Hashi')
    tap = @('None', 'Tap', 'Hold', 'Toggle')
    # settingEnum без префикса EAres<Тип>SettingName:: — по алфавиту, как облако обычно и отдаёт (тогда группа пишется картой
    # словаря, codec.ps1); Plank — сразу за AllMusic, как у владельца. Служебных из $ShareSkip здесь нет — в код не попадают.
    f = @('AllMusicOverallVolume', 'PlankPreviewVolume', 'CharacterSelectMusicVolume', 'CrosshairADSOutlineOpacity', 'CrosshairCenterDotOpacity',
          'CrosshairCenterDotSize', 'CrosshairInnerLinesFiringErrorScale', 'CrosshairInnerLinesLineLength', 'CrosshairInnerLinesLineLengthVertical',
          'CrosshairInnerLinesLineOffset', 'CrosshairInnerLinesLineThickness', 'CrosshairInnerLinesMovementErrorScale', 'CrosshairInnerLinesOpacity',
          'CrosshairOuterLinesFiringErrorScale', 'CrosshairOuterLinesLineLength', 'CrosshairOuterLinesLineLengthVertical',
          'CrosshairOuterLinesLineOffset', 'CrosshairOuterLinesLineThickness', 'CrosshairOuterLinesMovementErrorScale', 'CrosshairOuterLinesOpacity',
          'CrosshairOutlineOpacity', 'CrosshairSniperCenterDotOpacity', 'CrosshairSniperCenterDotSize', 'GamepadBaseRotationSpeedX',
          'GamepadBaseRotationSpeedY', 'GamepadLookStickInnerDeadzone', 'GamepadWalkStickInnerDeadzone', 'MenuAndLobbyMusicVolume', 'MinimapSize',
          'MinimapVisionConeOpacity', 'MinimapZoom', 'MouseSensitivity', 'MouseSensitivityADS', 'MouseSensitivityZoomed', 'ObserverRunSpeedModifier',
          'ObserverWalkSpeedModifier', 'OverallVolume', 'SoundEffectsVolume', 'VideoVolume', 'VoiceOverVolume')
    i = @('ColorBlindMode', 'MinimapKeepPlayerCentered', 'PlayerPerfPresetInfo', 'PlayerPerfShowCPUTime', 'PlayerPerfShowFiringErrors',
          'PlayerPerfShowFrameRate', 'PlayerPerfShowGameTime', 'PlayerPerfShowGPUTime', 'PlayerPerfShowMemory', 'PlayerPerfShowNetworkJitter',
          'PlayerPerfShowNetworkRtt', 'PlayerPerfShowPacketLossPercentage', 'PlayerPerfShowRenderTime', 'PlayerPerfShowServerFrameRate', 'VoiceVolume')
    b = @('AlwaysShowInventoryWidgets', 'AutoEquipPrioritizeStrongest', 'AutoEquipSkipsMelee', 'CollectionShowOwnedOnly', 'CrosshairADSDisplayCenterDot',
          'CrosshairADSInnerLinesShowLines', 'CrosshairADSOuterLinesShowLines', 'CrosshairDisplayCenterDot', 'CrosshairHasOutline',
          'CrosshairInnerLinesShowLines', 'CrosshairInnerLinesShowMovementError', 'CrosshairInnerLinesShowShootingError', 'CrosshairOuterLinesShowLines',
          'CrosshairOuterLinesShowMovementError', 'CrosshairUseAdvancedOptions', 'CrosshairUsePrimaryCrosshairForADS', 'EnableHRTF',
          'EnableInstabilityIndicators', 'FadeCrosshairWithFiringError', 'HasShownAgentDescriptionInRange', 'HasShownHushDescriptionInRange',
          'HoldInputForSniperScopes', 'InvertMouse', 'LeftHanded', 'MinimapRotates', 'MinimapTranslates', 'MuteMusicOnAppWindowDeactivate',
          'RawInputBuffer', 'ShowBlood', 'ShowBulletTracers', 'ShowCorpses', 'ShowCorpsesInRange', 'ShowKeybindsOnMegamap', 'ShowKeybindsOnMinimap',
          'ShowMapRegionNames', 'ShowMatureContent', 'ShowNewPlayerTips', 'ShowSpectatorCount', 'TacticalCalloutsInChat', 'TeamColorAffectsHUD',
          'VoiceChatEnabled', 'VoipDucksMusicVolume', 'VoipDucksVOFlavor')
    s = @('CrosshairColor', 'CrosshairColorCustom', 'CrosshairProfileName', 'CrosshairSniperCenterDotColor', 'PlayerPerfPresetType',
          'PremierPlayoffQualificationNotice', 'PremierPromotionNotice')
    # пути в отличиях прицела от стандартного (Get-XhDelta): первые 15 — самые частые (один байт), дальше — по порядку профиля
    xh = @('profileName', 'primary.outlineOpacity', 'primary.bDisplayCenterDot', 'primary.innerLines.lineLength',
           'primary.innerLines.lineLengthVertical', 'primary.innerLines.lineOffset', 'primary.innerLines.bShowShootingError',
           'primary.innerLines.lineThickness', 'primary.innerLines.opacity', 'primary.outerLines.bShowLines', 'primary.centerDotSize',
           'primary.bHasOutline', 'primary.bFadeCrosshairWithFiringError', 'primary.bUseCustomColor', 'bUseAdvancedOptions')
}

# Остальные пути прицела — по порядку стандартного профиля (crosshair.ps1). Список выписан один раз и заморожен:
# раздел/ключ — каждая комбинация раздела и поля.
$XhSecFields = 'color.b', 'color.g', 'color.r', 'color.a', 'colorCustom.b', 'colorCustom.g', 'colorCustom.r', 'colorCustom.a',
    'bUseCustomColor', 'bHasOutline', 'outlineThickness', 'outlineColor.b', 'outlineColor.g', 'outlineColor.r', 'outlineColor.a',
    'outlineOpacity', 'centerDotSize', 'centerDotOpacity', 'bDisplayCenterDot', 'bFadeCrosshairWithFiringError',
    'bShowSpectatedPlayerCrosshair', 'bHideCrosshair', 'bFixMinErrorAcrossWeapons'
$XhLineFields = 'lineThickness', 'lineLength', 'lineLengthVertical', 'lineOffset', 'bAllowVertScaling', 'bShowMovementError',
    'bShowShootingError', 'bShowMinError', 'opacity', 'bShowLines', 'firingErrorScale', 'movementErrorScale'
$CodeDicts.xh += & {
    $first = $CodeDicts.xh
    $all = @(foreach ($sec in 'primary', 'aDS', 'focusMode') {
        foreach ($f in $XhSecFields) { "$sec.$f" }
        foreach ($ln in 'innerLines', 'outerLines') { foreach ($f in $XhLineFields) { "$sec.$ln.$f" } }
    }) + @(foreach ($f in 'centerDotColor.b', 'centerDotColor.g', 'centerDotColor.r', 'centerDotColor.a', 'centerDotColorCustom.b',
                         'centerDotColorCustom.g', 'centerDotColorCustom.r', 'centerDotColorCustom.a', 'centerDotSize', 'centerDotOpacity',
                         'bDisplayCenterDot', 'bUseCustomCenterDotColor') { "sniper.$f" }) +
        @('bUsePrimaryCrosshairForADS', 'bUsePrimaryCrosshairForFocusMode', 'bUseCustomCrosshairOnAllPrimary', 'bScaleToResolution')
    @($all | Where-Object { $first -cnotcontains $_ })
}

$script:CodeIdx = @{}
# Имя → номер (регистр важен: облако различает). Строится один раз.
function Get-CodeIndex([string]$k) {
    if (-not $script:CodeIdx.ContainsKey($k)) {
        $d = New-Object 'Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
        $i = 0; foreach ($n in $CodeDicts[$k]) { if (-not $d.ContainsKey($n)) { $d[$n] = $i }; $i++ }
        $script:CodeIdx[$k] = $d
    }
    $script:CodeIdx[$k]
}
